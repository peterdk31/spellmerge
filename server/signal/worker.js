// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The signalling server on Cloudflare (docs/milestones/online-lobby.md, Part 1): a Worker that
// takes a WebSocket at /room and hands it to the one Durable Object that holds every room
// (rooms.js decides everything; this only holds the sockets). The sockets hibernate: an open
// room that nobody talks in costs nothing, and each socket's little state is its attachment, so
// the rooms are found again when the object wakes. Nothing is stored and nothing is logged.
//
// The relay: with the Worker secrets TURN_KEY_ID and TURN_KEY_API_TOKEN set (a TURN key of
// Cloudflare's Realtime service, made in its dashboard), each join draws one short-lived TURN
// credential from Cloudflare (`drawRelay`, the one other server this calls: the owner's exception
// of 2026-11-11, checked by `check_signal_source`). Without them, or when the call fails, the
// rooms work as before and the machines link directly or not at all.

import { DurableObject } from "cloudflare:workers";
import { Rooms } from "./rooms.js";
import { relayOfCloudflare } from "./turn.js";

/** How long a relay credential lasts, in seconds: a whole play session (Cloudflare allows 48 hours). */
const RELAY_TTL_S = 12 * 60 * 60;
/** The credential call's most time, in milliseconds: past it the join goes on without a relay. */
const RELAY_MS = 3000;

/** One relay credential drawn from Cloudflare's TURN service: `{ urls, username, credential }`, or null. */
async function drawRelay(env) {
  const response = await fetch(`https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(env.TURN_KEY_ID)}/credentials/generate-ice-servers`, {
    method: "POST",
    headers: { Authorization: `Bearer ${env.TURN_KEY_API_TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({ ttl: RELAY_TTL_S }),
    signal: AbortSignal.timeout(RELAY_MS),
  });
  if (!response.ok) return null;
  return relayOfCloudflare(await response.json());
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/room") return new Response("Not found", { status: 404 });
    if (request.headers.get("Upgrade") !== "websocket") return new Response("A WebSocket is expected", { status: 426 });
    return env.ROOMS.get(env.ROOMS.idFromName("rooms")).fetch(request);
  },
};

export class SignalRooms extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    const relay = env.TURN_KEY_ID && env.TURN_KEY_API_TOKEN ? () => drawRelay(env) : null;
    this.rooms = new Rooms({ relay });
    /** Each WebSocket's socket as rooms.js knows it. */
    this.socks = new Map();
    /** What the alarm was last set for (so it is written only when it changes); undefined: not known. */
    this.alarmAt = undefined;
    for (const ws of ctx.getWebSockets()) this.rooms.add(this.#sock(ws));
  }

  async fetch(request) {
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1]);
    // A game that takes relay messages says so in its address (`/room?relay=1`); an older one does not.
    this.rooms.add(this.#sock(pair[1]), { relay: new URL(request.url).searchParams.get("relay") === "1" });
    await this.#wake();
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  async webSocketMessage(ws, message) {
    // A join waits here on its relay credential (the object stays awake for it).
    await this.rooms.message(this.#sock(ws), message);
    await this.#wake();
  }

  async webSocketClose(ws) {
    this.#gone(ws);
    try {
      // Our half of the closing (nothing, where the runtime has answered it already).
      ws.close(1000, "");
    } catch {
      // Closed already.
    }
  }

  async webSocketError(ws) {
    this.#gone(ws);
  }

  async alarm() {
    this.alarmAt = undefined;
    await this.#wake();
  }

  #sock(ws) {
    let sock = this.socks.get(ws);
    if (!sock) {
      sock = {
        state: ws.deserializeAttachment() ?? {},
        send: (text) => {
          try {
            ws.send(text);
          } catch {
            // It closed a moment ago; its close is on the way and tells whoever shared its room.
          }
        },
        close: (code, reason) => {
          this.socks.delete(ws);
          try {
            ws.close(code, reason);
          } catch {
            // Closed already.
          }
        },
        save() {
          ws.serializeAttachment(this.state);
        },
      };
      this.socks.set(ws, sock);
    }
    return sock;
  }

  #gone(ws) {
    const sock = this.socks.get(ws);
    if (!sock) return;
    this.socks.delete(ws);
    this.rooms.remove(sock);
  }

  /** What has outlived its time is closed, and the alarm set for the next that will. */
  async #wake() {
    const next = this.rooms.sweep();
    if (next === this.alarmAt) return;
    this.alarmAt = next;
    if (next === null) await this.ctx.storage.deleteAlarm();
    else await this.ctx.storage.setAlarm(next);
  }
}
