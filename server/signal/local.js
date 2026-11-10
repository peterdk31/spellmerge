// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The signalling server on this machine, for the tests and for playing the game against it
// (`node local.js [port]`, then the game's `--signal ws://127.0.0.1:<port>/room`): the same
// rooms.js as on Cloudflare, behind a WebSocket server written out here with Node alone, so
// nothing has to be installed. It listens on 127.0.0.1 only and is never deployed.
//
// It speaks as much WebSocket as the game and the tests need: whole text messages, ping and
// close. Anything else closes the socket.

import { createHash } from "node:crypto";
import { createServer } from "node:http";
import { LIMITS, Rooms } from "./rooms.js";

const GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
/** A frame's most bytes: a message at its longest in UTF-8, with room. */
const MAX_FRAME = LIMITS.bytes * 4;
const SWEEP_MS = 1000;

/** Start it. `options` are `Rooms`' (the tests' clock and codes). Resolves to { port, rooms, close() }. */
export function listen(port = 0, options = {}) {
  const rooms = new Rooms(options);
  const open = new Set();
  const server = createServer((_request, response) => {
    response.writeHead(426).end("A WebSocket is expected");
  });
  server.on("upgrade", (request, socket) => {
    const key = request.headers["sec-websocket-key"];
    if (new URL(request.url, "http://local").pathname !== "/room" || typeof key !== "string") {
      socket.end("HTTP/1.1 404 Not Found\r\n\r\n");
      return;
    }
    const accept = createHash("sha1").update(key + GUID).digest("base64");
    socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
    open.add(socket);
    serve(socket, rooms, () => open.delete(socket));
  });
  const sweeper = setInterval(() => rooms.sweep(), SWEEP_MS);
  return new Promise((resolve) => {
    server.listen(port, "127.0.0.1", () => {
      resolve({
        port: server.address().port,
        rooms,
        close() {
          clearInterval(sweeper);
          for (const socket of open) socket.destroy();
          return new Promise((done) => server.close(done));
        },
      });
    });
  });
}

/** One socket's frames read and written. */
function serve(socket, rooms, closed) {
  let unread = Buffer.alloc(0);
  let gone = false;
  const sock = {
    state: {},
    save() {},
    send(text) {
      if (!gone) socket.write(frame(0x1, Buffer.from(text, "utf8")));
    },
    close(code, reason) {
      if (gone) return;
      gone = true;
      const body = Buffer.alloc(2 + Buffer.byteLength(reason));
      body.writeUInt16BE(code, 0);
      body.write(reason, 2);
      socket.end(frame(0x8, body));
    },
  };
  const end = () => {
    gone = true;
    rooms.remove(sock);
    closed();
  };
  socket.on("close", end);
  socket.on("error", end);
  socket.on("data", (chunk) => {
    unread = Buffer.concat([unread, chunk]);
    while (!gone) {
      const read = unframe(unread);
      if (read === null) return;
      if (read === false) {
        rooms.remove(sock);
        sock.close(1002, "not understood");
        return;
      }
      unread = unread.subarray(read.size);
      if (read.op === 0x1) rooms.message(sock, read.body.toString("utf8"));
      else if (read.op === 0x9) socket.write(frame(0xa, read.body));
      else if (read.op === 0x8) {
        rooms.remove(sock);
        sock.close(1000, "");
      } else if (read.op !== 0xa) rooms.message(sock, read.body);
    }
  });
  rooms.add(sock);
}

/** A server's frame: whole, unmasked. */
function frame(op, body) {
  let head;
  if (body.length < 126) head = Buffer.from([0x80 | op, body.length]);
  else if (body.length < 65536) {
    head = Buffer.alloc(4);
    head[0] = 0x80 | op;
    head[1] = 126;
    head.writeUInt16BE(body.length, 2);
  } else {
    head = Buffer.alloc(10);
    head[0] = 0x80 | op;
    head[1] = 127;
    head.writeBigUInt64BE(BigInt(body.length), 2);
  }
  return Buffer.concat([head, body]);
}

/** A client's frame from the start of `bytes`: { op, body, size }, null while it is not all here, false when it is none we take. */
function unframe(bytes) {
  if (bytes.length < 2) return null;
  const whole = (bytes[0] & 0x80) !== 0;
  const op = bytes[0] & 0x0f;
  const masked = (bytes[1] & 0x80) !== 0;
  let length = bytes[1] & 0x7f;
  let at = 2;
  // A client's frames are masked and, for all we take, whole and plain.
  if (!whole || !masked || (bytes[0] & 0x70) !== 0 || op === 0x0) return false;
  if (length === 126) {
    if (bytes.length < 4) return null;
    length = bytes.readUInt16BE(2);
    at = 4;
  } else if (length === 127) {
    if (bytes.length < 10) return null;
    const long = bytes.readBigUInt64BE(2);
    if (long > BigInt(MAX_FRAME)) return false;
    length = Number(long);
    at = 10;
  }
  if (length > MAX_FRAME) return false;
  if (bytes.length < at + 4 + length) return null;
  const mask = bytes.subarray(at, at + 4);
  const body = Buffer.from(bytes.subarray(at + 4, at + 4 + length));
  for (let i = 0; i < body.length; i++) body[i] ^= mask[i & 3];
  return { op, body, size: at + 4 + length };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const port = Number(process.argv[2] ?? 8787);
  listen(port).then((server) => console.log(`signal: ws://127.0.0.1:${server.port}/room`));
}
