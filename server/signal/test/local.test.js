// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The rooms behind real WebSockets (local.js, the server the game is played against on one
// machine): a room opened and joined, the codes there and back, a code of the longest kind, a
// refusal's close code, and the room closing with its host.

import assert from "node:assert/strict";
import { test } from "node:test";
import { listen } from "../local.js";
import { LIMITS } from "../rooms.js";

/** A client: what it was sent, in order, awaited one at a time. */
function client(port, path = "/room") {
  const ws = new WebSocket(`ws://127.0.0.1:${port}${path}`);
  const got = [];
  const waiting = [];
  const push = (value) => (waiting.length ? waiting.shift()(value) : got.push(value));
  ws.addEventListener("message", (event) => push(JSON.parse(event.data)));
  ws.addEventListener("close", (event) => push({ closed: event.code, reason: event.reason }));
  return {
    ws,
    opened: new Promise((resolve, reject) => {
      ws.addEventListener("open", resolve);
      ws.addEventListener("error", reject);
    }),
    say: (message) => ws.send(typeof message === "string" ? message : JSON.stringify(message)),
    next: () => (got.length ? Promise.resolve(got.shift()) : new Promise((resolve) => waiting.push(resolve))),
  };
}

test("a room over real sockets: opened, joined, the codes there and back, closed with its host", async () => {
  const server = await listen(0, { code: () => "KQ7RM" });
  try {
    const host = client(server.port);
    await host.opened;
    host.say({ t: "open" });
    assert.deepEqual(await host.next(), { t: "room", code: "KQ7RM" });

    const guest = client(server.port);
    await guest.opened;
    guest.say({ t: "join", code: "KQ7RM" });
    assert.deepEqual(await guest.next(), { t: "joined" });
    assert.deepEqual(await host.next(), { t: "guest", id: 1 });

    // A code of the longest kind crosses whole (a frame with a 16-bit length).
    const offer = "SM1." + "A".repeat(LIMITS.code - 4);
    host.say({ t: "offer", id: 1, code: offer });
    assert.deepEqual(await guest.next(), { t: "offer", code: offer });
    guest.say({ t: "answer", code: "SM1.YW5zd2Vy" });
    assert.deepEqual(await host.next(), { t: "answer", id: 1, code: "SM1.YW5zd2Vy" });

    host.ws.close();
    assert.deepEqual(await guest.next(), { t: "closed" });
    assert.deepEqual(await guest.next(), { closed: 1000, reason: "closed" });
    assert.equal(server.rooms.sockets.size, 0);
  } finally {
    await server.close();
  }
});

test("what is refused closes with the policy code, and a guest's going is told", async () => {
  const server = await listen(0, { code: () => "KQ7RM" });
  try {
    const bad = client(server.port);
    await bad.opened;
    bad.say("nonsense");
    assert.deepEqual(await bad.next(), { closed: 1008, reason: "malformed" });

    const binary = client(server.port);
    await binary.opened;
    binary.ws.send(new Uint8Array([1, 2, 3]));
    assert.deepEqual(await binary.next(), { closed: 1008, reason: "malformed" });

    const host = client(server.port);
    await host.opened;
    host.say({ t: "open" });
    await host.next();
    const guest = client(server.port);
    await guest.opened;
    guest.say({ t: "join", code: "KQ7RM" });
    await host.next();
    guest.say({ t: "bye" });
    assert.deepEqual(await host.next(), { t: "gone", id: 1 });
    assert.deepEqual((await guest.next(), await guest.next()), { closed: 1000, reason: "bye" });
  } finally {
    await server.close();
  }
});

test("only /room is a socket", async () => {
  const server = await listen(0);
  try {
    await assert.rejects(client(server.port, "/elsewhere").opened);
    const response = await fetch(`http://127.0.0.1:${server.port}/room`);
    assert.equal(response.status, 426);
  } finally {
    await server.close();
  }
});
