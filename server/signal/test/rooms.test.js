// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The rooms by themselves (rooms.js), on a clock and with codes the tests give: a room opened,
// joined, the codes handed over, everyone's going, the limits, what is malformed, the server's
// sleep, thousands of random messages, and the relay a join may draw.

import assert from "node:assert/strict";
import { test } from "node:test";
import { ALPHABET, CODE_LENGTH, LIMITS, Rooms, parse, randomCode, relayMessage } from "../rooms.js";
import { relayOfCloudflare } from "../turn.js";

const OFFER = "SM1.b2ZmZXI=";
const ANSWER = "SM1.YW5zd2Vy";

/** A clock, the rooms on it, and a way to make sockets that keep what they were sent. */
function setup(codes = ["KQ7RM", "ABCDE", "FGHJK"], options = {}) {
  const t = { now: 1_000_000 };
  let made = 0;
  const rooms = new Rooms({ now: () => t.now, code: () => codes[Math.min(made++, codes.length - 1)], ...options });
  const sock = (state = {}, asks = {}) => {
    const s = {
      state,
      sent: [],
      closed: null,
      saves: 0,
      send(text) {
        assert.equal(this.closed, null, "nothing is sent to a closed socket");
        this.sent.push(JSON.parse(text));
      },
      close(code, reason) {
        this.closed = { code, reason };
      },
      save() {
        this.saves += 1;
      },
      say(message) {
        rooms.message(this, typeof message === "string" ? message : JSON.stringify(message));
      },
      last() {
        return this.sent[this.sent.length - 1];
      },
    };
    rooms.add(s, asks);
    return s;
  };
  return { t, rooms, sock };
}

/** A room with its host and `count` guests in it. */
function room(count = 1) {
  const all = setup();
  const host = all.sock();
  host.say({ t: "open" });
  const guests = [];
  for (let at = 0; at < count; at++) {
    const guest = all.sock();
    guest.say({ t: "join", code: "KQ7RM" });
    guests.push(guest);
  }
  return { ...all, host, guests };
}

test("a host opens a room and a guest joins it by its code", () => {
  const { host, guests } = room(1);
  assert.deepEqual(host.sent, [{ t: "room", code: "KQ7RM" }, { t: "guest", id: 1 }]);
  assert.deepEqual(guests[0].sent, [{ t: "joined" }]);
});

test("the codes are handed over, each to the one it is for", () => {
  const { host, guests } = room(2);
  host.say({ t: "offer", id: 2, code: OFFER });
  assert.deepEqual(guests[1].last(), { t: "offer", code: OFFER });
  assert.deepEqual(guests[0].sent, [{ t: "joined" }], "the other guest hears nothing of it");
  guests[1].say({ t: "answer", code: ANSWER });
  assert.deepEqual(host.last(), { t: "answer", id: 2, code: ANSWER });
});

test("guests take the lowest free id, and a fourth is told the room is full", () => {
  const { sock, host, guests, rooms } = room(3);
  assert.deepEqual(host.sent.slice(1), [{ t: "guest", id: 1 }, { t: "guest", id: 2 }, { t: "guest", id: 3 }]);
  const fourth = sock();
  fourth.say({ t: "join", code: "KQ7RM" });
  assert.deepEqual(fourth.sent, [{ t: "full" }]);
  assert.equal(fourth.closed, null, "it may try another room");
  rooms.remove(guests[1]);
  assert.deepEqual(host.last(), { t: "gone", id: 2 });
  fourth.say({ t: "join", code: "KQ7RM" });
  assert.deepEqual(host.last(), { t: "guest", id: 2 }, "the freed id is given again");
});

test("a guest that says bye is closed and the host told", () => {
  const { host, guests } = room(1);
  guests[0].say({ t: "bye" });
  assert.deepEqual(guests[0].closed, { code: 1000, reason: "bye" });
  assert.deepEqual(host.last(), { t: "gone", id: 1 });
  host.say({ t: "offer", id: 1, code: OFFER });
  assert.equal(host.closed, null, "an offer for a guest just gone is no fault");
});

test("a room closes with its host: its guests are told and closed, and the code is no room", () => {
  const { sock, host, guests, rooms } = room(2);
  rooms.remove(host);
  for (const guest of guests) {
    assert.deepEqual(guest.last(), { t: "closed" });
    assert.deepEqual(guest.closed, { code: 1000, reason: "closed" });
  }
  const late = sock();
  late.say({ t: "join", code: "KQ7RM" });
  assert.deepEqual(late.sent, [{ t: "no_room" }]);
  assert.equal(rooms.hosts.size + rooms.guests.size, 0, "nothing of the room is kept");
  assert.deepEqual([...rooms.sockets], [late]);
});

test("a host's bye closes its room", () => {
  const { host, guests } = room(1);
  host.say({ t: "bye" });
  assert.deepEqual(host.closed, { code: 1000, reason: "bye" });
  assert.deepEqual(guests[0].last(), { t: "closed" });
});

test("a code still open is never handed out again", () => {
  const { sock } = setup(["KQ7RM", "KQ7RM", "KQ7RM", "ABCDE"]);
  const first = sock();
  first.say({ t: "open" });
  const second = sock();
  second.say({ t: "open" });
  assert.deepEqual(first.sent, [{ t: "room", code: "KQ7RM" }]);
  assert.deepEqual(second.sent, [{ t: "room", code: "ABCDE" }]);
});

test("with no code free the host is refused", () => {
  const { sock } = setup(["KQ7RM"]);
  sock().say({ t: "open" });
  const second = sock();
  second.say({ t: "open" });
  assert.deepEqual(second.closed, { code: 1008, reason: "no room is free" });
});

test("each side may only say what is its own to say", () => {
  const refused = (who, message, reason) => {
    const { sock, host, guests } = room(1);
    const from = who === "host" ? host : who === "guest" ? guests[0] : sock();
    from.say(message);
    assert.deepEqual(from.closed, { code: 1008, reason }, `${who}: ${JSON.stringify(message)}`);
  };
  refused("host", { t: "open" }, "a room is open already");
  refused("host", { t: "join", code: "KQ7RM" }, "in a room already");
  refused("host", { t: "answer", code: ANSWER }, "only a guest answers");
  refused("guest", { t: "open" }, "a room is open already");
  refused("guest", { t: "join", code: "KQ7RM" }, "in a room already");
  refused("guest", { t: "offer", id: 1, code: OFFER }, "only a host offers");
  refused("nobody", { t: "offer", id: 1, code: OFFER }, "only a host offers");
  refused("nobody", { t: "answer", code: ANSWER }, "only a guest answers");
});

test("a refused host's room closes", () => {
  const { host, guests } = room(1);
  host.say("nonsense");
  assert.deepEqual(host.closed, { code: 1008, reason: "malformed" });
  assert.deepEqual(guests[0].last(), { t: "closed" });
});

test("anything malformed closes the socket", () => {
  const long = "SM1." + "A".repeat(LIMITS.code);
  const bad = [
    "",
    "open",
    "null",
    "[]",
    '"open"',
    "{}",
    '{"t":1}',
    '{"t":"shout"}',
    '{"t":"room","code":"KQ7RM"}',
    '{"t":"open","more":1}',
    '{"t":"bye","code":"KQ7RM"}',
    '{"t":"join"}',
    '{"t":"join","code":"kq7rm"}',
    '{"t":"join","code":"KQ7R"}',
    '{"t":"join","code":"KQ7RMM"}',
    '{"t":"join","code":"KQ7R0"}',
    '{"t":"join","code":["KQ7RM"]}',
    '{"t":"join","code":"KQ7RM","id":1}',
    '{"t":"offer","code":"SM1.AAAA"}',
    '{"t":"offer","id":0,"code":"SM1.AAAA"}',
    '{"t":"offer","id":4,"code":"SM1.AAAA"}',
    '{"t":"offer","id":1.5,"code":"SM1.AAAA"}',
    '{"t":"offer","id":"1","code":"SM1.AAAA"}',
    '{"t":"offer","id":1,"code":"XX1.AAAA"}',
    '{"t":"offer","id":1,"code":"SM1."}',
    '{"t":"offer","id":1,"code":"SM1.AA\\"A"}',
    '{"t":"offer","id":1,"code":"SM1.AA AA"}',
    '{"t":"offer","id":1,"code":"SM1.AA=A"}',
    `{"t":"offer","id":1,"code":"${long}"}`,
    '{"t":"answer","id":1,"code":"SM1.AAAA"}',
    '{"t":"answer","code":7}',
    "x".repeat(LIMITS.bytes + 1),
  ];
  for (const text of bad) {
    const { sock } = setup();
    const s = sock();
    s.say(text);
    assert.deepEqual(s.closed, { code: 1008, reason: "malformed" }, text.slice(0, 60));
    assert.deepEqual(s.sent, []);
  }
  const { rooms, sock } = setup();
  for (const data of [new Uint8Array([1, 2]), Buffer.from('{"t":"open"}'), null, 7]) {
    const s = sock();
    rooms.message(s, data);
    assert.deepEqual(s.closed, { code: 1008, reason: "malformed" }, "only text is taken");
  }
});

test("parse hands on only the keys of the form", () => {
  assert.deepEqual(parse(' {"t" : "open"} '), { t: "open" });
  assert.deepEqual(parse('{"code":"KQ7RM","t":"join"}'), { t: "join", code: "KQ7RM" });
  assert.equal(parse('{"t":"join","code":"KQ7RM","__proto__":{}}'), null);
});

test("a socket may send twenty messages a minute, and is closed at the next", () => {
  const { t, host } = room(1);
  for (let at = 0; at < LIMITS.messages - 1; at++) host.say({ t: "offer", id: 1, code: OFFER });
  assert.equal(host.closed, null, "the open and nineteen offers");
  t.now += 60_000;
  for (let at = 0; at < LIMITS.messages; at++) host.say({ t: "offer", id: 1, code: OFFER });
  assert.equal(host.closed, null, "twenty more a minute later");
  host.say({ t: "offer", id: 1, code: OFFER });
  assert.deepEqual(host.closed, { code: 1008, reason: "too many messages" });
});

test("nobody walks the codes: ten wrong ones in a minute close the socket", () => {
  const { t, sock } = room(0);
  const walker = sock();
  for (let at = 0; at < LIMITS.misses - 1; at++) walker.say({ t: "join", code: "ZZZZZ" });
  assert.equal(walker.closed, null);
  assert.equal(walker.sent.length, LIMITS.misses - 1);
  walker.say({ t: "join", code: "ZZZZZ" });
  assert.deepEqual(walker.closed, { code: 1008, reason: "too many wrong codes" });

  const slow = sock();
  for (let at = 0; at < LIMITS.misses - 1; at++) slow.say({ t: "join", code: "ZZZZZ" });
  t.now += 60_000;
  slow.say({ t: "join", code: "ZZZZZ" });
  slow.say({ t: "join", code: "KQ7RM" });
  assert.equal(slow.closed, null, "a minute later the count starts again");
  assert.deepEqual(slow.last(), { t: "joined" });
});

test("a room with no join for fifteen minutes closes; a join gives it fifteen more", () => {
  const { t, rooms, sock, host } = room(0);
  assert.equal(rooms.sweep(), t.now + LIMITS.roomMs);
  t.now += LIMITS.roomMs - 1;
  rooms.sweep();
  assert.equal(host.closed, null);
  const guest = sock();
  guest.say({ t: "join", code: "KQ7RM" });
  t.now += LIMITS.roomMs - 1;
  assert.equal(rooms.sweep(), t.now + 1);
  assert.equal(host.closed, null, "the join was its new start");
  t.now += 1;
  assert.equal(rooms.sweep(), null, "nothing is held any more");
  assert.deepEqual(host.last(), { t: "closed" });
  assert.deepEqual(host.closed, { code: 1000, reason: "closed" });
  assert.deepEqual(guest.last(), { t: "closed" });
  assert.equal(rooms.sockets.size, 0);
});

test("a socket that never opens or joins a room is closed after a minute", () => {
  const { t, rooms, sock } = setup();
  const idle = sock();
  assert.equal(rooms.sweep(), t.now + LIMITS.idleMs);
  t.now += LIMITS.idleMs;
  rooms.sweep();
  assert.deepEqual(idle.closed, { code: 1000, reason: "idle" });
});

test("the rooms are found again from the sockets' states after the server slept", () => {
  const before = room(2);
  before.host.say({ t: "offer", id: 1, code: OFFER });
  assert.ok(before.host.saves > 0 && before.guests[0].saves > 0, "each socket's state was saved");
  const states = [before.host, ...before.guests].map((s) => JSON.parse(JSON.stringify(s.state)));

  const { rooms, sock } = setup(["ABCDE"]);
  const [host, first, second] = states.map((state) => sock(state));
  second.say({ t: "answer", code: ANSWER });
  assert.deepEqual(host.last(), { t: "answer", id: 2, code: ANSWER });
  host.say({ t: "offer", id: 1, code: OFFER });
  assert.deepEqual(first.last(), { t: "offer", code: OFFER });
  const third = sock();
  third.say({ t: "join", code: "KQ7RM" });
  assert.deepEqual(host.last(), { t: "guest", id: 3 });
  rooms.remove(host);
  assert.deepEqual(third.last(), { t: "closed" });
});

test("past the most sockets a new one is turned away", () => {
  const { rooms, sock } = setup();
  for (let at = 0; at < LIMITS.sockets; at++) rooms.sockets.add({});
  const s = sock();
  assert.deepEqual(s.closed, { code: 1013, reason: "full" });
});

test("room codes are five characters of the alphabet, and differ", () => {
  assert.equal(ALPHABET.length, 27);
  assert.ok(!/[0O1IL5SUV]/.test(ALPHABET));
  const seen = new Set();
  for (let at = 0; at < 2000; at++) {
    const code = randomCode();
    assert.match(code, new RegExp(`^[${ALPHABET}]{${CODE_LENGTH}}$`));
    seen.add(code);
  }
  assert.ok(seen.size > 1990, "2,000 codes of 14 million hardly ever meet");
});

test("a fuzz: random and broken messages never throw, never leak a room, never reach the wrong socket", () => {
  let seed = 12345;
  const random = (n) => {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % n;
  };
  const good = [
    '{"t":"open"}',
    '{"t":"bye"}',
    '{"t":"join","code":"KQ7RM"}',
    '{"t":"join","code":"ABCDE"}',
    '{"t":"join","code":"ZZZZZ"}',
    `{"t":"offer","id":1,"code":"${OFFER}"}`,
    `{"t":"offer","id":3,"code":"${OFFER}"}`,
    `{"t":"answer","code":"${ANSWER}"}`,
  ];
  const { t, rooms, sock } = setup(["KQ7RM", "ABCDE", "FGHJK", "MNPQR"]);
  let socks = [];
  for (let step = 0; step < 20000; step++) {
    t.now += random(4000);
    if (socks.length < 12) socks.push(sock());
    const from = socks[random(socks.length)];
    let text = good[random(good.length)];
    const how = random(10);
    if (how === 0) text = text.slice(0, random(text.length));
    else if (how === 1) text = text.replace(/[a-z]/, String.fromCharCode(32 + random(95)));
    else if (how === 2) text = String.fromCharCode(...Array.from({ length: random(40) }, () => random(256)));
    if (random(50) === 0) rooms.remove(from);
    else rooms.message(from, text);
    if (random(200) === 0) rooms.sweep();
    socks = socks.filter((s) => s.closed === null && rooms.sockets.has(s));

    // What the rooms hold is exactly what the open sockets say of themselves.
    assert.equal(rooms.sockets.size, socks.length);
    const hosts = socks.filter((s) => s.state.role === "host");
    assert.equal(rooms.hosts.size, hosts.length);
    assert.equal(rooms.guests.size, hosts.length);
    for (const host of hosts) assert.equal(rooms.hosts.get(host.state.code), host);
    for (const guest of socks.filter((s) => s.state.role === "guest")) {
      assert.equal(rooms.guests.get(guest.state.code)?.get(guest.state.id), guest, "a guest is in a room that is open");
    }
    for (const s of socks) {
      for (const m of s.sent) {
        if (m.t === "offer") assert.equal(s.state.role, "guest");
        if (m.t === "answer" || m.t === "guest" || m.t === "gone" || m.t === "room") assert.ok(s.state.role === "host" || s.closed);
      }
      s.sent.length = 0;
    }
  }
});

// --- The relay ----------------------------------------------------------------------

const TURN_UDP = "turn:turn.cloudflare.com:3478?transport=udp";
const TURN_TLS = "turns:turn.cloudflare.com:443?transport=tcp";
const USER = "bc91b63e2b5d759f8eb9f3b58062439e0a0e15893d76317d833265ad08d6631099ce7c7087caabb31ad3e1c386424e3e";
const PASS = "ebd71f1d3edbc2b0edae3cd5a6d82284aeb5c3b8fdaa9b8e3bf9cec683e0d45fe9f5b44e5145db3300f06c250a15b4a0";
/** Cloudflare's answer as its example gives it (port 53 added: it is filtered). */
const CLOUDFLARE = {
  iceServers: [
    { urls: ["stun:stun.cloudflare.com:3478"] },
    { urls: [TURN_UDP, "turn:turn.cloudflare.com:53?transport=udp", TURN_TLS], username: USER, credential: PASS },
  ],
};
const DRAWN = { urls: [TURN_UDP, "turn:turn.cloudflare.com:53?transport=udp", TURN_TLS], username: USER, credential: PASS };
const RELAY = { t: "relay", urls: [TURN_UDP, TURN_TLS], username: USER, credential: PASS };
const ASKS = { relay: true };

/** Rooms that draw relays from `draw` (each call counted), with a host whose room is open; all sockets ask for relays unless told. */
function relayed(draw = async () => DRAWN, hostAsks = ASKS) {
  const drawn = { n: 0 };
  const all = setup(["KQ7RM", "ABCDE", "FGHJK"], {
    relay: () => {
      drawn.n += 1;
      return draw();
    },
  });
  const host = all.sock({}, hostAsks);
  host.say({ t: "open" });
  /** A guest joins; resolves once its join is done. */
  const join = async (asks = ASKS, code = "KQ7RM") => {
    const guest = all.sock({}, asks);
    await all.rooms.message(guest, JSON.stringify({ t: "join", code }));
    return guest;
  };
  return { ...all, host, join, drawn };
}

test("with a relay, a join draws one, and host and guest are each sent it before hearing of the other", async () => {
  const { host, join, drawn } = relayed();
  const guest = await join();
  assert.equal(drawn.n, 1);
  assert.deepEqual(host.sent, [{ t: "room", code: "KQ7RM" }, RELAY, { t: "guest", id: 1 }]);
  assert.deepEqual(guest.sent, [RELAY, { t: "joined" }]);
  assert.equal(guest.state.waiting, false, "no longer waiting");
});

test("only a socket that asked for relays is sent one: an older game takes no such message", async () => {
  const old = relayed(async () => DRAWN, {});
  const fresh = await old.join();
  assert.deepEqual(old.host.sent, [{ t: "room", code: "KQ7RM" }, { t: "guest", id: 1 }], "a host that did not ask");
  assert.deepEqual(fresh.sent, [RELAY, { t: "joined" }], "its guest that did");
  const { host, join, drawn } = relayed();
  const older = await join({});
  assert.deepEqual(older.sent, [{ t: "joined" }], "a guest that did not ask");
  assert.deepEqual(host.sent.slice(1), [RELAY, { t: "guest", id: 1 }], "its host that did");
  const neither = relayed(async () => DRAWN, {});
  assert.equal(neither.rooms.message(neither.sock(), '{"t":"join","code":"KQ7RM"}'), null, "neither asked: nothing pending");
  assert.equal(neither.drawn.n, 0, "and none is drawn");
  assert.equal(drawn.n, 1);
});

test("the relay message is written in its one fixed form, which the game reads exactly", () => {
  const text = relayMessage(DRAWN);
  assert.equal(text, `{"t":"relay","urls":["${TURN_UDP}","${TURN_TLS}"],"username":"${USER}","credential":"${PASS}"}`);
  assert.equal(text, JSON.stringify(RELAY), "the same as JSON writes it: nothing escaped");
});

test("Cloudflare's answer is read for its relay: the first server with a user name and a password", () => {
  assert.deepEqual(relayOfCloudflare(CLOUDFLARE), DRAWN);
  assert.deepEqual(relayOfCloudflare({ iceServers: [null, { urls: TURN_UDP, username: "u", credential: "p" }] }), { urls: [TURN_UDP], username: "u", credential: "p" }, "one address alone is a list of one");
  for (const nonsense of [null, undefined, "x", [], {}, { iceServers: "x" }, { iceServers: [1, "a", { urls: [TURN_UDP] }, { urls: [TURN_UDP], username: 1, credential: "p" }] }]) {
    assert.equal(relayOfCloudflare(nonsense), null);
  }
  assert.deepEqual(JSON.parse(relayMessage(relayOfCloudflare(CLOUDFLARE))), RELAY, "and through to the message");
});

test("a relay that fails, is refused or is nonsense costs only the relay: the join goes on", async () => {
  const answers = [
    async () => { throw new Error("down"); },
    async () => null,
    async () => ({}),
    async () => CLOUDFLARE,
    async () => ({ urls: [TURN_UDP], username: 'a"b', credential: "x" }),
    () => { throw new Error("not even a promise"); },
  ];
  for (const draw of answers) {
    const { host, join } = relayed(draw);
    const guest = await join();
    assert.deepEqual(host.sent, [{ t: "room", code: "KQ7RM" }, { t: "guest", id: 1 }], String(draw));
    assert.deepEqual(guest.sent, [{ t: "joined" }]);
  }
});

test("a relay is taken strictly: only TURN addresses by name and port, never port 53, a fair word each", () => {
  const relay = (urls, username = "user", credential = "pass") => ({ urls, username, credential });
  assert.equal(relayMessage(relay([TURN_UDP])), `{"t":"relay","urls":["${TURN_UDP}"],"username":"user","credential":"pass"}`);
  assert.equal(relayMessage(relay(TURN_UDP)), "", "its addresses are a list");
  for (const url of [
    "stun:stun.cloudflare.com:3478",
    "turn:turn.cloudflare.com:53?transport=udp",
    "turn:turn.cloudflare.com:0?transport=udp",
    "turn:turn.cloudflare.com:65536?transport=udp",
    "turn:turn.cloudflare.com:3478",
    "turn:turn.cloudflare.com:3478?transport=sctp",
    "turn:TURN.cloudflare.com:3478?transport=udp",
    "turn:localhost:3478?transport=udp",
    'turn:a.b:1?transport=udp","x":"',
    "turn:turn.cloudflare.com:3478?transport=udp ",
    3478,
  ]) {
    assert.equal(relayMessage(relay([url])), "", `refused: ${url}`);
  }
  for (const [username, credential] of [["", "p"], ["u", ""], ["u\\", "p"], ["u", "p q"], ["x".repeat(257), "p"], [1, "p"], ["u", null]]) {
    assert.equal(relayMessage(relay([TURN_UDP], username, credential)), "", `refused: ${username} ${credential}`);
  }
  const many = Array.from({ length: 20 }, (_, at) => `turn:turn.cloudflare.com:${1000 + at}?transport=udp`);
  assert.equal(JSON.parse(relayMessage(relay(many))).urls.length, LIMITS.relayUrls, "at most relayUrls addresses");
  for (const nonsense of [null, undefined, "x", [], {}, CLOUDFLARE]) {
    assert.equal(relayMessage(nonsense), "");
  }
});

test("a guest that leaves while its relay is drawn was never named: the host hears nothing of it", async () => {
  let release;
  const { host, rooms, sock, drawn } = relayed(() => (release ? Promise.resolve(null) : new Promise((resolve) => (release = resolve))));
  const guest = sock({}, ASKS);
  const pending = rooms.message(guest, JSON.stringify({ t: "join", code: "KQ7RM" }));
  assert.ok(pending instanceof Promise, "the join is pending on its relay");
  assert.deepEqual(guest.sent, [], "nothing yet");
  // The host cannot offer to it and it cannot answer: neither knows of the other yet.
  host.say({ t: "offer", id: 1, code: OFFER });
  assert.deepEqual(guest.sent, [{ t: "offer", code: OFFER }], "an offer to its id is handed on all the same (the game refuses one before `joined`)");
  rooms.remove(guest);
  release(DRAWN);
  await pending;
  assert.equal(drawn.n, 1);
  assert.deepEqual(host.sent, [{ t: "room", code: "KQ7RM" }], "no relay, no guest, no gone");
  const next = sock({}, ASKS);
  await rooms.message(next, JSON.stringify({ t: "join", code: "KQ7RM" }));
  assert.deepEqual(host.sent.slice(-1), [{ t: "guest", id: 1 }], "its id is free again");
});

test("a guest's id taken anew while the first one's relay is drawn: only the one in the room is met", async () => {
  const releases = [];
  const { host, rooms, sock } = relayed(() => new Promise((resolve) => releases.push(resolve)));
  const first = sock({}, ASKS);
  const one = rooms.message(first, JSON.stringify({ t: "join", code: "KQ7RM" }));
  rooms.remove(first);
  const second = sock({}, ASKS);
  const two = rooms.message(second, JSON.stringify({ t: "join", code: "KQ7RM" }));
  assert.equal(second.state.id, 1, "the same id");
  releases[0](DRAWN);
  await one;
  assert.deepEqual([host.sent.length, second.sent.length], [1, 0], "the first one's relay meets nobody");
  releases[1](DRAWN);
  await two;
  assert.deepEqual(host.sent.slice(1), [RELAY, { t: "guest", id: 1 }]);
  assert.deepEqual(second.sent, [RELAY, { t: "joined" }]);
});

test("a room that closes while a guest's relay is drawn tells the guest it is closed, and nothing more", async () => {
  let release;
  const { host, rooms, sock } = relayed(() => new Promise((resolve) => (release = resolve)));
  const guest = sock({}, ASKS);
  const pending = rooms.message(guest, JSON.stringify({ t: "join", code: "KQ7RM" }));
  rooms.remove(host);
  release(DRAWN);
  await pending;
  assert.deepEqual(guest.sent, [{ t: "closed" }]);
  assert.equal(guest.closed?.code, 1000);
});

test("a guest found waiting on a relay after the server slept is closed to ask again", () => {
  const { rooms, sock } = setup();
  const host = sock({ role: "host", code: "KQ7RM", since: 1_000_000, born: 1_000_000, relay: true });
  const guest = sock({ role: "guest", code: "KQ7RM", id: 1, born: 1_000_000, relay: true, waiting: true });
  assert.equal(guest.closed?.code, 1013);
  assert.equal(rooms.guests.get("KQ7RM").size, 0, "it holds no place");
  assert.deepEqual(host.sent, [], "and the host hears nothing");
});

test("relays drawn are limited by every room together; past the limit joins go on without one", async () => {
  const all = relayed();
  const { t, rooms, sock, drawn } = all;
  // Three rooms, so no room's own limit is reached.
  for (const code of ["ABCDE", "FGHJK"]) sock({}, ASKS).say({ t: "open" });
  const codes = ["KQ7RM", "ABCDE", "FGHJK"];
  for (let at = 0; at < LIMITS.relays; at++) {
    const guest = await all.join(ASKS, codes[at % 3]);
    guest.say({ t: "bye" });
  }
  assert.equal(drawn.n, LIMITS.relays);
  const over = await all.join();
  assert.equal(drawn.n, LIMITS.relays, "none drawn past the limit");
  assert.deepEqual(over.sent, [{ t: "joined" }]);
  assert.deepEqual(all.host.last(), { t: "guest", id: 1 });
  over.say({ t: "bye" });
  t.now += 60 * 1000;
  const later = await all.join();
  assert.equal(drawn.n, LIMITS.relays + 1, "a minute later they are drawn again");
  assert.deepEqual(later.sent, [RELAY, { t: "joined" }]);
  assert.ok(rooms.hosts.size === 3);
});

test("one room draws only so many relays, however long it is open, and that outlives the server's sleep", async () => {
  const { t, host, join, drawn, sock } = relayed();
  for (let at = 0; at < LIMITS.roomRelays; at++) {
    t.now += 61 * 1000;
    (await join()).say({ t: "bye" });
  }
  assert.equal(drawn.n, LIMITS.roomRelays);
  t.now += 61 * 1000;
  assert.deepEqual((await join()).sent, [{ t: "joined" }], "the next join of that room gets none");
  assert.equal(host.state.relays, LIMITS.roomRelays, "counted in the host's state, which the sleep keeps");
  // After a sleep: new rooms from the saved states.
  let calls = 0;
  const woken = new Rooms({ now: () => t.now, relay: async () => (calls++, DRAWN) });
  const again = { state: { ...host.state }, sent: [], send(text) { this.sent.push(JSON.parse(text)); }, close() {}, save() {} };
  woken.add(again);
  const guest = { state: {}, sent: [], send(text) { this.sent.push(JSON.parse(text)); }, close() {}, save() {} };
  woken.add(guest, ASKS);
  assert.equal(woken.message(guest, '{"t":"join","code":"KQ7RM"}'), null, "still none after the sleep");
  assert.equal(calls, 0);
  assert.deepEqual(guest.sent, [{ t: "joined" }]);
  assert.ok(sock);
});

test("without a relay, a message leaves nothing pending", () => {
  const { rooms, sock } = setup();
  const host = sock({}, ASKS);
  assert.equal(rooms.message(host, '{"t":"open"}'), null);
  assert.equal(rooms.message(sock({}, ASKS), '{"t":"join","code":"KQ7RM"}'), null);
  assert.equal(rooms.message(sock(), "nonsense"), null, "nor does a refusal");
});
