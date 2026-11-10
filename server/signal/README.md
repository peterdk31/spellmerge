# The room server (`server/signal/`)

## Purpose

Two machines can't talk until each holds the other's code (`NetCode`, [net/README.md](../../net/README.md)). This server carries those codes between the machines of one room, so a player types a room's five characters in place of pasting codes through a chat ([docs/milestones/online-lobby.md](../../docs/milestones/online-lobby.md), Part 1). It does nothing else: it never sees the game, is out of the path once the machines are linked, stores nothing and logs nothing.

It is the only part of the repository that is not the game: a few hundred lines of JavaScript with no dependencies, run on Cloudflare (Workers Free plan). Claude and the owner maintain it; **the deploy is the owner's**. It is one way machines find each other, behind the game's `NetHandshake` seam: the game outside `net/net_signal*.gd` does not know it exists.

## What is here

| File | What it is |
|---|---|
| `rooms.js` | Everything the server decides: rooms, codes, who is told what, the limits. No word of Cloudflare or Node |
| `worker.js` | Cloudflare's side: a Worker that takes a WebSocket at `/room` and one Durable Object that holds the sockets (hibernating) and calls `rooms.js` |
| `local.js` | The same rooms on this machine, behind a WebSocket server written with Node alone: for the tests and for playing against it. Listens on 127.0.0.1 only, never deployed |
| `wrangler.toml`, `package.json` | The deploy's settings. No dependency is listed or committed |
| `test/` | `node --test`: the rooms on a stepped clock with a fuzz (`rooms.test.js`), and through real sockets (`local.test.js`) |

## The protocol

One WebSocket a machine to `/room`, text messages only, each a small JSON object of one fixed form. The server writes its own without spaces, keys in the order below, and the game reads exactly that (`NetSignal`).

| From | Message | What it means |
|---|---|---|
| Host | `{"t":"open"}` | Make me a room |
| Server | `{"t":"room","code":"KQ7RM"}` | Your room's five characters |
| Guest | `{"t":"join","code":"KQ7RM"}` | Put me in this room |
| Server | `{"t":"guest","id":1}` to the host, `{"t":"joined"}` to the guest | A guest is here (id 1 to 3) |
| Server | `{"t":"no_room"}`, `{"t":"full"}` to the guest | No room has that code; it has three guests |
| Host | `{"t":"offer","id":1,"code":"SM1.…"}` | Its code for that guest; the guest gets `{"t":"offer","code":"SM1.…"}` |
| Guest | `{"t":"answer","code":"SM1.…"}` | Its code; the host gets `{"t":"answer","id":1,"code":"SM1.…"}` |
| Server | `{"t":"gone","id":1}` to the host | That guest's socket closed (a linked guest closes it: the server's part is done) |
| Server | `{"t":"closed"}` | The room is closed |
| Either | `{"t":"bye"}` | Leaving |

## Contract

- **Untrusted messages.** A message is text of at most 16,384 characters, one of the five client forms with exactly its keys, a room code five characters of the alphabet, a guest id 1 to 3, a machine's code `SM1.` and base64 of at most 8,192 characters. Anything else, or a message that is not its sender's to send (a guest's `offer`, a second `open`), closes the socket with code 1008. The game checks a machine's code whole on arrival (`NetCode.read`), as a pasted one.
- **Room codes:** five characters from 27 (no `0 O 1 I L 5 S U V`), made at random; one still open is never handed out again.
- **A room lives** while its host's socket is open, and fifteen minutes at most without a join. It closes with its host: its guests are told and closed.
- **Limits:** twenty messages a minute from a socket; ten wrong room codes in a minute close it; three guests a room; a socket in no room closes after a minute; 4,096 sockets at once.
- **A code only reaches the room it was sent in:** an offer goes to the one guest it names, an answer to that guest's host.
- **Nothing is kept:** no code is stored; a socket's state is its role, room, id and counters, gone with the socket. Nothing is logged by the server (`observability` off); Cloudflare's own request logs are Cloudflare's.
- **It calls nothing:** no import but its own files, `cloudflare:workers`, and for `local.js` and the tests Node's `crypto`, `http`, `test` and `assert`; no `fetch`, no code made from text (`check_signal_source` in `ci/smbot/rules.py`).
- **`rooms.js` knows no platform.** A socket is `{ send, close, state, save }`; whoever holds the sockets calls `add`, `message`, `remove` and `sweep`.

## Running it

```sh
node --test                 # in server/signal/: its tests
node local.js 8787          # the server on ws://127.0.0.1:8787/room
tools/online_signal.sh      # from the repository root: its tests, then the game's real handshake through local.js
npx wrangler deploy         # the owner's: deploys it (signs in through the browser the first time)
```

Or from GitHub, with nothing installed: **Actions > deploy-signal > Run workflow** (`.github/workflows/deploy-signal.yml`; on main, the owner only). It needs two secrets in the `automation` environment, `CLOUDFLARE_API_TOKEN` (a token from the "Edit Cloudflare Workers" template, limited to this account) and `CLOUDFLARE_ACCOUNT_ID`, and writes the Worker's address in the run's summary.

The Worker's address is `NetSignal.URL` (`net/net_signal.gd`): `wss://spellmerge-signal.peterdk31.workers.dev/room`, deployed first on 2026-11-10 by the workflow.

**Checking a deploy:** `worker.js` has no test of its own (that needs wrangler; `rooms.js`, which it only wraps, is what the tests cover). After a deploy, play the game's real handshake against it: `godot --headless --path . --script res://tests/net/signal_runner.gd -- --signal=<the address>` prints `SIGNAL OK` (it did on the first deploy).

## Milestones

- **Online lobby L2** (2026-11-10): the rooms, the Worker, the local server, the tests.
- **Deployed** (2026-11-10): the first deploy, and the game's handshake through it.
- **Open:** a CI job for `node --test` (`ci/` is the owner's).
