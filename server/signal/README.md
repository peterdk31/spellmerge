# The room server (`server/signal/`)

## Purpose

Two machines can't talk until each holds the other's code (`NetCode`, [net/README.md](../../net/README.md)). This server carries those codes between the machines of one room, so a player types a room's five characters in place of pasting codes through a chat ([docs/milestones/online-lobby.md](../../docs/milestones/online-lobby.md), Part 1). Beside that it hands each join a relay credential, when it has a TURN key (see "The relay"). It does nothing else: it never sees the game, is out of the path once the machines are linked, stores nothing and logs nothing.

It is the only part of the repository that is not the game: a few hundred lines of JavaScript with no dependencies, run on Cloudflare (Workers Free plan). Claude and the owner maintain it; **the deploy is the owner's**. It is one way machines find each other, behind the game's `NetHandshake` seam: the game outside `net/net_signal*.gd` does not know it exists.

## What is here

| File | What it is |
|---|---|
| `rooms.js` | Everything the server decides: rooms, codes, who is told what, the limits. No word of Cloudflare or Node |
| `worker.js` | Cloudflare's side: a Worker that takes a WebSocket at `/room` and one Durable Object that holds the sockets (hibernating) and calls `rooms.js`; and the one call to Cloudflare's TURN service that draws a relay credential (`drawRelay`) |
| `turn.js` | Cloudflare's TURN answer read for its relay (`relayOfCloudflare`): the one file that knows that layout |
| `local.js` | The same rooms on this machine, behind a WebSocket server written with Node alone: for the tests and for playing against it. Listens on 127.0.0.1 only, never deployed. `--fake-relay` hands every join a relay nobody runs |
| `wrangler.toml`, `package.json` | The deploy's settings. No dependency is listed or committed |
| `test/` | `node --test`: the rooms on a stepped clock with a fuzz (`rooms.test.js`), and through real sockets (`local.test.js`) |

## The protocol

One WebSocket a machine to `/room` (`/room?relay=1` from a game that takes relay messages), text messages only, each a small JSON object of one fixed form. The server writes its own without spaces, keys in the order below, and the game reads exactly that (`NetSignal`).

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
| Server | `{"t":"relay","urls":["turn:…"],"username":"…","credential":"…"}` | A relay for the link about to be made: to the host before `guest`, to the guest before `joined` (only with a TURN key, and only to a socket that came by `/room?relay=1`) |
| Either | `{"t":"bye"}` | Leaving |

## Contract

- **Untrusted messages.** A message is text of at most 16,384 characters, one of the five client forms with exactly its keys, a room code five characters of the alphabet, a guest id 1 to 3, a machine's code `SM1.` and base64 of at most 8,192 characters. Anything else, or a message that is not its sender's to send (a guest's `offer`, a second `open`), closes the socket with code 1008. The game checks a machine's code whole on arrival (`NetCode.read`), as a pasted one.
- **Room codes:** five characters from 27 (no `0 O 1 I L 5 S U V`), made at random; one still open is never handed out again.
- **A room lives** while its host's socket is open, and fifteen minutes at most without a join. It closes with its host: its guests are told and closed.
- **Limits:** twenty messages a minute from a socket; ten wrong room codes in a minute close it; three guests a room; a socket in no room closes after a minute; 4,096 sockets at once; twelve relay credentials a room while it is open (kept in the host's socket state, so it holds over the server's sleep), and thirty a minute by all rooms together (counted in memory: a server that slept counts anew, so this one is best effort). A join past either gets none and goes on without.
- **A code only reaches the room it was sent in:** an offer goes to the one guest it names, an answer to that guest's host.
- **Nothing is kept:** no code is stored; a socket's state is its role, room, id and counters, gone with the socket. Nothing is logged by the server (`observability` off); Cloudflare's own request logs are Cloudflare's.
- **It calls nothing but Cloudflare's TURN service:** no import but its own files, `cloudflare:workers`, and for `local.js` and the tests Node's `crypto`, `http`, `test` and `assert`; no code made from text; one `fetch`, in `worker.js`, of exactly `https://rtc.live.cloudflare.com/v1/turn/keys/<key id>/credentials/generate-ice-servers` (`check_signal_source` and `SIGNAL_RELAY_FETCH` in `ci/smbot/rules.py`; the owner's exception of 2026-11-11).
- **`rooms.js` knows no platform.** A socket is `{ send, close, state, save }`; whoever holds the sockets calls `add`, `message`, `remove` and `sweep`, and may give a `relay()` that resolves to a plain `{ urls, username, credential }`: where that comes from is not the rooms' to know (`turn.js` and `worker.js` on Cloudflare).

## The relay

Two machines on two networks often find no direct way to each other (a phone on mobile data, a router that hides its machines even from STUN); only a relay (TURN) gets through those. The owner chose Cloudflare's TURN service for it (2026-11-11; Steam's relay may take over for the desktop builds later, M7).

- **Per join, one credential.** When a guest joins, `rooms.js` asks `relay()` (on Cloudflare `drawRelay` in `worker.js`, its answer read by `turn.js`) for one credential, and sends the same one to the host and the guest, before telling them of each other.
- **Only to a game that asked.** A game built before relays reads no such message and would give up on the room, so a socket is sent relays only when its address said `?relay=1`; with neither machine of a join asking, none is drawn. (A new message the server sends unasked needs the same care.) It lasts twelve hours (`RELAY_TTL_S`; Cloudflare allows 48), long enough for a play session, since the relay checks it again while the link lasts.
- **Checked, then rewritten.** Cloudflare's answer is not passed on: `relayOfCloudflare` takes its first server with a user name and password, and `relayMessage` only that one's `turn:`/`turns:` addresses by name (or IPv4 address) and port over UDP or TCP, never port 53 (browsers block it), at most eight, and writes them in the one form the game reads (`NetSignal`). Should the two forms ever drift apart, the game treats a relay it cannot read as none and links directly. (The desktop builds use the UDP addresses only: their WebRTC library does TURN over nothing else.)
- **Optional and harmless when it fails.** With no TURN key, or when the call fails or takes over three seconds (`RELAY_MS`), or past a limit, a join goes on without a relay, and the machines link directly or not at all, as before. The game uses the relay only where no direct way works.
- **What it costs.** Cloudflare's first 1,000 GB a month are free (shared with its SFU); past that $0.05 a GB sent. A whole session's input is a few megabytes, so only abuse could reach that: anyone who can open a room can draw credentials, which is why they are short-lived, given only to a room's machines, and limited a room and a minute. A credential relays for its whole twelve hours, so the limits bound how many are out, not what one carries: the dashboard's usage is the real watch (docs/SECURITY-CHECKLIST.md).
- **What it sees.** That two machines talk, and how much; never what: the channel is encrypted end to end (DTLS), with the keys in the codes.

**The owner's steps:** in the Cloudflare dashboard's Realtime section, create a TURN key (name it, e.g. `spellmerge`) and note its id and API token; then, on the Worker `spellmerge-signal` > Settings > Variables and Secrets, add two **secrets**: `TURN_KEY_ID` (the key's id) and `TURN_KEY_API_TOKEN` (its API token). Secrets stay over deploys and are never in `wrangler.toml`. Then run the `deploy-signal` workflow, so the Worker has the relay code.

## Running it

```sh
node --test                 # in server/signal/: its tests
node local.js 8787          # the server on ws://127.0.0.1:8787/room
node local.js 8787 --fake-relay  # the same, every join handed a relay nobody runs
tools/online_signal.sh      # from the repository root: its tests, then the game's real handshake through local.js (with --fake-relay)
npx wrangler deploy         # the owner's: deploys it (signs in through the browser the first time)
```

Or from GitHub, with nothing installed: **Actions > deploy-signal > Run workflow** (`.github/workflows/deploy-signal.yml`; on main, the owner only). It needs two secrets in the `automation` environment, `CLOUDFLARE_API_TOKEN` (a token from the "Edit Cloudflare Workers" template, limited to this account) and `CLOUDFLARE_ACCOUNT_ID`, and writes the Worker's address in the run's summary.

The Worker's address is `NetSignal.URL` (`net/net_signal.gd`): `wss://spellmerge-signal.peterdk31.workers.dev/room`, deployed first on 2026-11-10 by the workflow.

**Checking a deploy:** `worker.js` has no test of its own (that needs wrangler; `rooms.js`, which it only wraps, is what the tests cover). After a deploy, play the game's real handshake against it: `godot --headless --path . --script res://tests/net/signal_runner.gd -- --signal=<the address>` prints `SIGNAL OK` (it did on the first deploy). With the TURN key set, add `--relay=used`: it also needs each machine's code to hold an address on the relay, which only a working credential gives.

## Milestones

- **Online lobby L2** (2026-11-10): the rooms, the Worker, the local server, the tests.
- **Deployed** (2026-11-10): the first deploy, and the game's handshake through it.
- **The relay** (2026-11-11): a Cloudflare TURN credential a join, sent to both machines (`relayMessage`, `drawRelay`).
- **Open:** a CI job for `node --test` (`ci/` is the owner's).
