# The room server (`server/signal/`)

## Purpose

Carries `NetCode`s ([net/README.md](../../net/README.md)) between the machines of one room, so a player types a room's five characters instead of pasting codes ([docs/milestones/online-lobby.md](../../docs/milestones/online-lobby.md)), and hands each join a relay credential when it has a TURN key ("The relay"). Nothing else: it never sees the game, is out of the path once machines are linked, stores nothing and logs nothing.

The only part of the repository that is not the game: JavaScript with no dependencies, run on Cloudflare Workers. Claude and the owner maintain it; **the deploy is the owner's**. It sits behind the game's `NetHandshake` seam: nothing outside `net/net_signal*.gd` knows it exists.

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

- **Untrusted messages.** At most 16,384 characters, one of the five client forms with exactly its keys, a room code of five alphabet characters, a guest id 1 to 3, a machine's code `SM1.` plus base64 of at most 8,192 characters. Anything else, or a message not its sender's to send (a guest's `offer`, a second `open`), closes the socket with code 1008. The game checks a code whole on arrival (`NetCode.read`).
- **Room codes:** five characters from 27 (no `0 O 1 I L 5 S U V`), random; one still open is never handed out again.
- **A room lives** while its host's socket is open, at most fifteen minutes without a join, and closes with its host (its guests told and closed).
- **Limits:** twenty messages a minute a socket; ten wrong room codes in a minute close it; three guests a room; a socket in no room closes after a minute; 4,096 sockets at once; twelve relay credentials a room, thirty a minute in all (best effort). A join past a limit goes on without a relay.
- **A code only reaches the room it was sent in:** an offer to the guest it names, an answer to that guest's host.
- **Nothing is kept or logged:** a socket's state is its role, room, id and counters, gone with it; `observability` off.
- **It calls nothing but Cloudflare's TURN service:** no import but its own files, `cloudflare:workers`, and for `local.js` and the tests Node's `crypto`, `http`, `test` and `assert`; no code made from text; one `fetch`, in `worker.js`, of exactly `https://rtc.live.cloudflare.com/v1/turn/keys/<key id>/credentials/generate-ice-servers` (`check_signal_source` and `SIGNAL_RELAY_FETCH` in `ci/smbot/rules.py`).
- **`rooms.js` knows no platform.** A socket is `{ send, close, state, save }`; the holder calls `add`, `message`, `remove` and `sweep`, and may give a `relay()` resolving to `{ urls, username, credential }`.
- **A new message the server sends unasked** goes only to games that asked for it (as `?relay=1` does): an older game would give up on a room.

## The relay

A TURN relay for machines that find no direct way to each other (Cloudflare's TURN service).

- **Per join, one credential:** `rooms.js` asks `relay()` (`drawRelay` in `worker.js`, read by `turn.js`) once and sends it to host and guest before telling them of each other.
- **Only to a game that asked** (`?relay=1`); none drawn if neither machine asked. It lasts twelve hours (`RELAY_TTL_S`).
- **Checked, then rewritten:** `relayOfCloudflare` takes the first server with a user name and password; `relayMessage` keeps only its `turn:`/`turns:` addresses by name or IPv4 and port over UDP or TCP, never port 53, at most eight, in the one form `NetSignal` reads.
- **Optional and harmless when it fails:** no TURN key, a failed call, over three seconds (`RELAY_MS`) or past a limit, and the join goes on without a relay.
- **The owner's steps:** create a TURN key in Cloudflare's Realtime section; on the Worker `spellmerge-signal` add the **secrets** `TURN_KEY_ID` and `TURN_KEY_API_TOKEN` (never in `wrangler.toml`); run the `deploy-signal` workflow. Usage is watched in the dashboard (docs/SECURITY-CHECKLIST.md).

## Running it

```sh
node --test                 # in server/signal/: its tests
node local.js 8787          # the server on ws://127.0.0.1:8787/room
node local.js 8787 --fake-relay  # the same, every join handed a relay nobody runs
tools/online_signal.sh      # from the repository root: its tests, then the game's real handshake through local.js (with --fake-relay)
npx wrangler deploy         # the owner's: deploys it (signs in through the browser the first time)
```

Or **Actions > deploy-signal > Run workflow** (`.github/workflows/deploy-signal.yml`; the owner only; secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` in the `automation` environment). The Worker's address is `NetSignal.URL` (`net/net_signal.gd`).

**Checking a deploy** (`worker.js` has no test of its own): `godot --headless --path . --script res://tests/net/signal_runner.gd -- --signal=<the address>` prints `SIGNAL OK`; with the TURN key set, add `--relay=used`.

History and reasons: [docs/history/server-signal-README.md](../../docs/history/server-signal-README.md).
