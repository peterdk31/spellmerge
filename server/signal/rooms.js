// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The signalling server's rooms (docs/milestones/online-lobby.md, Part 1): everything the server
// decides, with no word of Cloudflare or Node in it. A host opens a room and is given its five
// characters; a guest who names them is put in it; the two then hand each other one code each
// (the game's own `NetCode` text) through here, and talk to each other directly from then on.
//
// Whoever holds the sockets (worker.js on Cloudflare, local.js in the tests) gives each one as
//
//     { send(text), close(code, reason), state, save() }
//
// `state` is a small plain object, all this file knows of a socket; `save()` is called after it
// changed (on Cloudflare it is the socket's attachment, which outlives the server's sleep, so the
// rooms are found again by `add` when it wakes). Nothing else is kept: no code is stored, and
// nothing is logged.
//
// A relay (a TURN server, for two machines with no direct way between them) is optional: given a
// `relay()` that resolves to `{ urls, username, credential }` (whoever holds the sockets knows
// where it comes from), each join draws one short-lived credential, and the host and the guest
// are sent it, checked and written in one fixed form (`relayMessage`), before they are told of
// each other. Only a socket that asked for relays when it came is sent one (`add`'s `asks`): a
// game built before relays takes no such message. A relay that fails or is slow costs nothing
// but the relay: the join goes on without it.

/** The letters and digits of a room code: none that is misread for another (0 O 1 I L 5 S U V). */
export const ALPHABET = "2346789ABCDEFGHJKMNPQRTWXYZ";
export const CODE_LENGTH = 5;

export const LIMITS = {
  /** A message's most characters (a code is about 900). */
  bytes: 16384,
  /** A code's most characters: the game's `NetCode.MAX_CHARS`. */
  code: 8192,
  /** Messages a socket may send in a minute. */
  messages: 20,
  /** Wrong room codes a socket may name in a minute. */
  misses: 10,
  /** Guests in a room. */
  guests: 3,
  /** A room without a join closes after this long. */
  roomMs: 15 * 60 * 1000,
  /** A socket that neither opened nor joined a room closes after this long. */
  idleMs: 60 * 1000,
  /** Sockets held at once. */
  sockets: 4096,
  /**
   * Relay credentials drawn in a minute, by every room together; joins past it get none. Counted
   * in memory, so a server that slept counts anew: `roomRelays` is the limit that always holds.
   */
  relays: 30,
  /** Relay credentials one room may draw while it is open. */
  roomRelays: 12,
  /** A relay message's most addresses. */
  relayUrls: 8,
};

const MINUTE = 60 * 1000;
/** WebSocket close codes: done, refused, full. */
const DONE = 1000;
const REFUSED = 1008;
const TRY_LATER = 1013;

const CODE_FORM = new RegExp(`^[${ALPHABET}]{${CODE_LENGTH}}$`);
/** What a `NetCode` text is made of: its prefix and base64. The game checks the rest. */
const NET_CODE_FORM = /^SM1\.[A-Za-z0-9+/]+={0,2}$/;
/** A relay's address as the game takes it: TURN by name (or IPv4 address) and port, over UDP or TCP. */
const RELAY_URL_FORM = /^turns?:[a-z0-9-]+(\.[a-z0-9-]+)+:([0-9]{1,5})\?transport=(udp|tcp)$/;
/** A relay credential's user name or password. */
const RELAY_WORD_FORM = /^[A-Za-z0-9+/=_.:-]{1,256}$/;

/** A room code at random, evenly over the alphabet. */
export function randomCode() {
  let code = "";
  const bytes = new Uint8Array(1);
  // 243 = 9 * 27: a byte below it is even over the 27 characters.
  while (code.length < CODE_LENGTH) {
    crypto.getRandomValues(bytes);
    if (bytes[0] < 243) code += ALPHABET[bytes[0] % ALPHABET.length];
  }
  return code;
}

export class Rooms {
  /**
   * `now`: the time in milliseconds; `code`: makes a room code (the tests give their own);
   * `relay`: draws one relay credential, resolving to `{ urls, username, credential }` or null
   * (null here: no relay).
   */
  constructor({ now = Date.now, code = randomCode, relay = null } = {}) {
    this.now = now;
    this.makeCode = code;
    this.relay = relay;
    /** Relay credentials drawn in the minute since `relaysAt`. */
    this.relaysAt = undefined;
    this.relays = 0;
    /** Every socket held. */
    this.sockets = new Set();
    /** A room's host by its code, and its guests by their id. */
    this.hosts = new Map();
    this.guests = new Map();
  }

  /**
   * A socket is here: a new one (its state empty; `asks.relay`: it takes relay messages), or one
   * found again after a sleep.
   */
  add(sock, asks = {}) {
    if (this.sockets.size >= LIMITS.sockets) {
      sock.close(TRY_LATER, "full");
      return;
    }
    const s = sock.state;
    if (s.waiting) {
      // Its join was waiting on a relay when the server slept: nobody was told of it, so it asks again.
      sock.close(TRY_LATER, "try again");
      return;
    }
    this.sockets.add(sock);
    if (s.role === "host") {
      this.hosts.set(s.code, sock);
      if (!this.guests.has(s.code)) this.guests.set(s.code, new Map());
    } else if (s.role === "guest") {
      if (!this.guests.has(s.code)) this.guests.set(s.code, new Map());
      this.guests.get(s.code).set(s.id, sock);
    } else if (s.born === undefined) {
      s.role = "";
      s.born = this.now();
      s.relay = asks.relay === true;
      sock.save();
    }
  }

  /** A socket closed, whoever closed it. */
  remove(sock) {
    if (!this.sockets.delete(sock)) return;
    const s = sock.state;
    if (s.role === "host" && this.hosts.get(s.code) === sock) {
      this.#closeRoom(s.code, null);
    } else if (s.role === "guest") {
      const guests = this.guests.get(s.code);
      if (guests && guests.get(s.id) === sock) {
        guests.delete(s.id);
        // A guest still waiting on its relay was never named to the host.
        const host = this.hosts.get(s.code);
        if (host && !s.waiting) host.send(`{"t":"gone","id":${s.id}}`);
      }
    }
  }

  /**
   * A message arrived: `data` as the socket gave it (anything but text is refused). Returns a
   * promise when the message left something to finish (a join waiting on its relay; whoever holds
   * the sockets keeps itself awake until it settles), else null.
   */
  message(sock, data) {
    if (!this.sockets.has(sock)) return null;
    if (typeof data !== "string" || data.length > LIMITS.bytes) return this.#refuse(sock, "malformed");
    const s = sock.state;
    const now = this.now();
    if (s.at === undefined || now - s.at >= MINUTE) {
      s.at = now;
      s.n = 0;
    }
    s.n += 1;
    if (s.n > LIMITS.messages) return this.#refuse(sock, "too many messages");
    const m = parse(data);
    if (m === null) return this.#refuse(sock, "malformed");
    const took = this.#take(sock, s, m, now);
    if (typeof took === "string" && took !== "") return this.#refuse(sock, took);
    if (this.sockets.has(sock)) sock.save();
    return typeof took === "string" ? null : took;
  }

  /**
   * Close what has outlived its time: a room with no join for `roomMs`, a socket in no room for
   * `idleMs`. Returns when to call again (milliseconds, as `now`), or null with nothing held.
   */
  sweep() {
    const now = this.now();
    let next = null;
    for (const sock of [...this.sockets]) {
      const s = sock.state;
      let until = null;
      if (s.role === "host") until = s.since + LIMITS.roomMs;
      else if (s.role === "") until = s.born + LIMITS.idleMs;
      if (until === null) continue;
      if (until > now) {
        next = next === null ? until : Math.min(next, until);
      } else if (s.role === "host") {
        this.#closeRoom(s.code, sock);
      } else {
        this.#drop(sock, DONE, "idle");
      }
    }
    return next;
  }

  /**
   * One message taken. Returns why the socket is refused for it, "" when it is not, or a promise
   * for what it left to finish (a join waiting on its relay).
   */
  #take(sock, s, m, now) {
    switch (m.t) {
      case "open": {
        if (s.role !== "") return "a room is open already";
        let code = "";
        for (let tries = 0; tries < 16 && code === ""; tries++) {
          const made = this.makeCode();
          if (!this.hosts.has(made)) code = made;
        }
        if (code === "") return "no room is free";
        s.role = "host";
        s.code = code;
        s.since = now;
        this.hosts.set(code, sock);
        this.guests.set(code, new Map());
        sock.send(`{"t":"room","code":"${code}"}`);
        return "";
      }
      case "join": {
        if (s.role !== "") return "in a room already";
        const host = this.hosts.get(m.code);
        if (!host) {
          if (s.missAt === undefined || now - s.missAt >= MINUTE) {
            s.missAt = now;
            s.miss = 0;
          }
          s.miss += 1;
          if (s.miss >= LIMITS.misses) return "too many wrong codes";
          sock.send('{"t":"no_room"}');
          return "";
        }
        const guests = this.guests.get(m.code);
        let id = 0;
        for (let at = 1; at <= LIMITS.guests && id === 0; at++) {
          if (!guests.has(at)) id = at;
        }
        if (id === 0) {
          sock.send('{"t":"full"}');
          return "";
        }
        s.role = "guest";
        s.code = m.code;
        s.id = id;
        guests.set(id, sock);
        host.state.since = now;
        host.save();
        if ((host.state.relay || s.relay) && this.#mayRelay(host.state, now)) {
          s.waiting = true;
          return this.#meetWithRelay(m.code, id, host, sock);
        }
        this.#meet(id, host, sock, "");
        return "";
      }
      case "offer": {
        if (s.role !== "host") return "only a host offers";
        // A guest that has just gone is no fault of the host's: its `gone` is on the way.
        const guest = this.guests.get(s.code).get(m.id);
        if (guest) guest.send(`{"t":"offer","code":"${m.code}"}`);
        return "";
      }
      case "answer": {
        if (s.role !== "guest") return "only a guest answers";
        const host = this.hosts.get(s.code);
        if (host) host.send(`{"t":"answer","id":${s.id},"code":"${m.code}"}`);
        return "";
      }
      case "bye":
        this.#drop(sock, DONE, "bye");
        return "";
    }
    return "malformed";
  }

  /** True when a join to the room of the host with state `room` may draw a relay credential now (one is counted). */
  #mayRelay(room, now) {
    if (this.relay === null) return false;
    if (this.relaysAt === undefined || now - this.relaysAt >= MINUTE) {
      this.relaysAt = now;
      this.relays = 0;
    }
    if (this.relays >= LIMITS.relays || (room.relays ?? 0) >= LIMITS.roomRelays) return false;
    this.relays += 1;
    room.relays = (room.relays ?? 0) + 1;
    return true;
  }

  /** A guest's relay drawn, then the guest and its host told of each other, if both are still there. */
  async #meetWithRelay(code, id, host, guest) {
    let text = "";
    try {
      text = relayMessage(await this.relay());
    } catch {
      // No relay this time: the two may still find each other directly.
    }
    const guests = this.guests.get(code);
    if (this.hosts.get(code) !== host || !guests || guests.get(id) !== guest) return;
    guest.state.waiting = false;
    guest.save();
    this.#meet(id, host, guest, text);
  }

  /**
   * The host is told of its guest and the guest that it is in, each sent the relay first when
   * there is one and it takes them.
   */
  #meet(id, host, guest, relay) {
    if (relay && host.state.relay) host.send(relay);
    host.send(`{"t":"guest","id":${id}}`);
    if (relay && guest.state.relay) guest.send(relay);
    guest.send('{"t":"joined"}');
  }

  /** A room ends: its guests are told and closed, and its host too when it is `host` (else it went itself). */
  #closeRoom(code, host) {
    const guests = this.guests.get(code);
    this.hosts.delete(code);
    this.guests.delete(code);
    for (const guest of guests ? guests.values() : []) {
      // Not a guest any more, so its own going tells nobody.
      guest.state.role = "";
      this.#drop(guest, DONE, "closed", '{"t":"closed"}');
    }
    if (host) {
      host.state.role = "";
      this.#drop(host, DONE, "closed", '{"t":"closed"}');
    }
  }

  #refuse(sock, why) {
    this.#drop(sock, REFUSED, why);
    return null;
  }

  /** Let a socket go: whoever it shared a room with is told (`remove`), then it is closed. */
  #drop(sock, code, reason, last = "") {
    this.remove(sock);
    try {
      if (last) sock.send(last);
      sock.close(code, reason);
    } catch {
      // It was gone already.
    }
  }
}

/**
 * The relay message the machines of a join are sent, from a relay `{ urls, username, credential }`:
 * only its TURN addresses of RELAY_URL_FORM (never port 53, which browsers block), at most
 * `relayUrls` of them. Written in one fixed form, which the game reads exactly (`NetSignal`):
 *
 *     {"t":"relay","urls":["turn:host:3478?transport=udp",...],"username":"...","credential":"..."}
 *
 * "" when it is no relay: no such address, or a user name or password out of form.
 */
export function relayMessage(relay) {
  if (relay === null || typeof relay !== "object") return "";
  const { urls, username, credential } = relay;
  if (!Array.isArray(urls) || !isRelayWord(username) || !isRelayWord(credential)) return "";
  const list = urls.filter(isRelayUrl).slice(0, LIMITS.relayUrls);
  if (list.length === 0) return "";
  return `{"t":"relay","urls":[${list.map((url) => `"${url}"`).join(",")}],"username":"${username}","credential":"${credential}"}`;
}

function isRelayUrl(value) {
  if (typeof value !== "string") return false;
  const m = RELAY_URL_FORM.exec(value);
  if (m === null) return false;
  const port = Number(m[2]);
  return port >= 1 && port <= 65535 && port !== 53;
}

function isRelayWord(value) {
  return typeof value === "string" && RELAY_WORD_FORM.test(value);
}

/**
 * A client's message, or null when it is none: one of the five forms, with exactly its keys, each
 * of its own kind. (`JSON.parse` makes plain data only; what it made is then checked whole.)
 */
export function parse(text) {
  let m;
  try {
    m = JSON.parse(text);
  } catch {
    return null;
  }
  if (m === null || typeof m !== "object" || Array.isArray(m) || typeof m.t !== "string") return null;
  const keys = Object.keys(m).sort().join(",");
  switch (m.t) {
    case "open":
    case "bye":
      return keys === "t" ? { t: m.t } : null;
    case "join":
      return keys === "code,t" && isRoomCode(m.code) ? { t: "join", code: m.code } : null;
    case "offer":
      return keys === "code,id,t" && isGuestId(m.id) && isNetCode(m.code) ? { t: "offer", id: m.id, code: m.code } : null;
    case "answer":
      return keys === "code,t" && isNetCode(m.code) ? { t: "answer", code: m.code } : null;
  }
  return null;
}

function isRoomCode(value) {
  return typeof value === "string" && CODE_FORM.test(value);
}

function isGuestId(value) {
  return Number.isInteger(value) && value >= 1 && value <= LIMITS.guests;
}

function isNetCode(value) {
  return typeof value === "string" && value.length <= LIMITS.code && NET_CODE_FORM.test(value);
}
