# Online lobby: room codes through a signalling server, and a lobby room with four seats from any machines

**Status (2026-11-10): a draft for the owner's review, not approved.** Asked by the owner after the netcode spike's S4: "What would it take, to allow for easier joining of multiplayer games?", then: "You can write up a plan for the signalling server! If AWS' free tier is enough, I am familiar with them. But if Cloudflare is just as easy and free, we can use them." And: "We also need a plan for a 'lobby' screen, where the screen is split into 4 seats and then local players can join alongside online players, until all 4 seats are taken or the host start the game before that. A cool feature would be a scenario like so: 2 local players on host machine, joined by 2 local players from another machine. Or like any combination thereof." Then: "Can we make 'The Lobby' a scene players can move around in?"

It builds on the spike ([netcode-spike.md](netcode-spike.md)): host-ordered lockstep over WebRTC, the strict decoders, `NetHandshake`, `NetCode`. It takes three items off the spike's "Not in the spike" list: a signalling server, more than one client, and more than one seat a machine. It leaves joining a run already under way for later (below).

## What the players see

1. **Play** (offline or online) takes everyone into **the lobby**, a small room of its own (`content/rooms/lobby/`). Nobody is in it yet. Along one wall stand **four seat stones**, one a seat (P1 to P4), each in its seat's colour, with what the seat is over it: "Press A / Enter to join" when empty, the player's device glyph and "this machine" or "online" when taken. In the middle stands **the gate**, an arch that leads to the run.
2. **A player presses join** on their device, and their wizard appears at their seat's stone. From then they walk, aim, cast and build their staffs as in a run: the lobby is a place to try spells while the others arrive. There is a **practice dummy** to hit, which never dies.
3. **On the host:** the pause menu (or a board by the gate) has **Open online**, which shows a **room code** of five characters (`KQ7RM`) with Copy. The code also stands on the board in the room, so a player can read it to a friend. Nothing connects anywhere before Open online is pressed.
4. **On another machine:** the main menu's **Join online**, type the five characters, Connect. That machine loads the host's lobby as it is right now, everyone where they stand, and its players press join to take the free seats.
5. **Any mix, up to four seats and four machines:** two players on the host and two on a guest, one on each of four machines, three on the host and one guest.
6. **A seat's player presses leave** and their wizard is gone and the seat free. A machine that goes away frees all its seats.
7. **The host starts:** a wizard of the host's walks into the gate, and a ring around it fills in three seconds (walking out cancels it). Then everyone, wherever they stand in the lobby, goes into the run. From then the run is closed: no new seats until it ends. Leaving still works, and the game plays on without that player (pillar 2: nobody waits for anyone, and nobody has to walk to the gate but the one who starts).
8. **The run's end** brings everyone back to the lobby, each at their stone, so the same party plays again without a new code.

The manual codes of the spike stay as **Join by code**, for a LAN with no internet, a server that is down, and the tests.

## Part 1: the signalling server

### What it does

Two machines can't talk until each has the other's session description and candidates (`NetCode`). The server carries those codes between them in place of chat, and does nothing else. It never sees the game, never stays in the path after the link is up, and keeps nothing once a room closes.

### Cloudflare, not AWS

Both can do it. Cloudflare is both easier and free for good:

| | Cloudflare Workers and Durable Objects | AWS (API Gateway WebSocket, Lambda, DynamoDB) |
|---|---|---|
| Free for good | Yes, on the Workers Free plan: Workers 100,000 requests a day; Durable Objects (SQLite-backed) are on the Free plan since April 2025 | Lambda and DynamoDB are always free; API Gateway's WebSocket allowance is for the first 12 months at most, and accounts made since July 2025 get credits that end after six months on the Free plan |
| Pieces to set up | One Worker and one Durable Object class (a room), one `wrangler.toml` | An API Gateway WebSocket API, Lambda functions for connect, message and disconnect, a DynamoDB table of connections, the IAM roles between them |
| Holding a room's state | The room is one Durable Object; both players' sockets are on it | Connection ids in DynamoDB, a message is posted back through the API Gateway management API |
| Over the limit | Requests fail with an error (no bill on the Free plan) | Billed, so a budget alarm is needed |

**Recommended: Cloudflare.** Our use is tiny: a join is about a dozen messages, so 100,000 requests a day is thousands of joins a day. With WebSocket hibernation an idle lobby costs nothing. The figures above are from the providers' pages as of 2026-11-10; check them again before the owner makes the account.

### The protocol

One WebSocket a machine to `wss://<worker>/room`, open only while a lobby is open online. The messages are small JSON objects of a fixed form. The server checks them as strictly as the game does, and the game checks what the server sends as untrusted (`NetSignal`, below):

| From | Message | What it means |
|---|---|---|
| Host | `open` | Make me a room. |
| Server | `room {code}` | Your room's five characters. |
| Guest | `join {code}` | Put me in this room. |
| Server | `guest {id}` to the host, `joined` to the guest | A guest is here (id 1 to 3 in this room). |
| Host | `offer {id, code}` | A `NetCode` offer for that guest. |
| Guest | `answer {code}` | Its `NetCode` answer, passed to the host. |
| Server | `gone {id}` / `closed` | A guest or the host went away; a room closes with its host. |
| Either | `bye` | Leaving. |

The codes inside are `NetCode`'s as they are today (`SM1.` text), so `NetCode.read` checks them on arrival exactly as a pasted one, and `NetRtc` and the handshake don't change. The server only adds a new way to hand them over: `NetSignalHandshake`, a second `NetHandshake` beside the paste one.

### Room codes and abuse

- **Five characters from 27** (letters and digits without 0, O, 1, I, L, 5, S, U, V, which are easy to misread): about 14 million codes. The server makes them at random and never hands out one still open.
- **A room lives** while its host's socket is open, and 15 minutes at most without a join. It holds at most three guests. A wrong code answers `no_room`, and a socket that gets ten of those in a minute is closed (no one walks the codes).
- **Limits on the server:** a message of at most 16 kB (a code is about 900 characters); at most 20 messages a minute from a socket; at most one room per host socket. Anything malformed closes the socket.
- **What the server sees and keeps:** each machine's IP address (as any server it talks to does) and the codes, which hold the machine's addresses too. It keeps them only in the room's memory while the room lives. It writes no log of its own. Cloudflare's own request logs are Cloudflare's; the privacy note in the builds says so.
- **Whom the game talks to, then:** the STUN server, our signalling server (one URL constant, `NetSignal.URL`), and the machines whose codes the server hands over, which are only those in the same room. Still nothing before a player presses Open online or Join online.

### The game's side (`net/`)

- `NetSignal`: the WebSocket to the server, polled when read, as `NetRtcLink` is. Its strict decoder takes only the server's message forms above, at most 16 kB, as plain text; a code is passed to `NetCode.read` and nowhere else. There is no `JSON.parse` of an open object: the decoder reads the fixed keys of each form and refuses anything more.
- `NetSignalHandshake`: the handshake through the server. On the host it is one `NetRtc` peer per guest, made when the server says `guest {id}`. On a guest it is one peer, answering the host's offer.
- **Rules, the owner's to change:** hard rule 4 gets `WebSocketPeer` added to `NET_CLASSES` in `ci/smbot/rules.py`, in `net/` only, so nothing outside `net/` may name it. Hard rule 4's text in `AGENTS.md`, `net/README.md`'s contract and `docs/SECURITY-CHECKLIST.md` say the same. I draft the change in the PR for the owner to approve, as for the spike.

### Where the server's code lives, and how it is deployed

Hard rule 2 lets no `.js` or `.ts` into the repository today, and the server is a few hundred lines of JavaScript. Two ways:

- **(a) A folder `server/signal/` in this repository,** with its own README and contract, maintained by Claude, its deploy the owner's. `ci/smbot/rules.py` allows `.js`, `.toml` and `package.json` there and only there, for Claude's PRs (as `native/` allows C++). Its tests run in CI next to the game's (Node, with Cloudflare's Workers test pool). One PR can change both sides of the protocol.
- **(b) A repository of its own** (`peterdk31/spellmerge-signal`), which the owner creates. The game's repository doesn't change its file rules, but the protocol is then kept in step across two repositories by hand, and the daily automation doesn't see it.

*Recommended: (a).*

**Deploy:** a workflow in `.github/` (the owner's), run by hand or when `server/signal/` changes on `main`, with a Cloudflare API token that may only deploy this one Worker, in the protected environment that holds the other secrets. Its address is `spellmerge-signal.<account>.workers.dev` to start (free), or a subdomain of the owner's own later.

**One-time owner steps:** make the Cloudflare account (free plan), make the API token (Workers scripts: edit, for this account only), store it as a secret, and run the deploy once.

### TURN, later

Some routers hide a machine even from STUN; only a relay gets through those. S5's tries across the internet say how often that happens. If it is needed, the same Worker can hand out short-lived TURN credentials, from Cloudflare's TURN service or another. A long-lived TURN password can't be shipped in an open-source build. That is its own decision once S5 has numbers. This plan works without it.

## Part 2: the lobby, a room, and four seats from any machines

### The lobby is simulation, so every machine sees the same lobby

A lobby people walk in is part of the game, not a menu: where each wizard stands, what each casts, the dummy's hits. Two machines can only see the same lobby the way they see the same run: by lockstep (AGENTS.md, "The simulation is state by default"). So **the lobby is a run of its own kind**, recorded by the host and played live by every guest, with the spike's sessions.

- **A new start, `lobby_requested`** (`Replay.STARTS`), heard by Flow, which loads the lobby room. Coop seats and unseats wizards in it as it does in any room (`seat_joined`, `seat_left`), each at its seat's stone (the room's `player_spawns`, one a seat, by seat and not by join order).
- **The lobby room's rules,** set in its `.tres` (`RoomBase` grows the fields): no enemies, no rewards, no downing (a wizard at no health stands up again at its stone after two seconds, as nobody should lose anything in a lobby; friendly fire still hits, as everywhere, owner 2026-10-28).
- **The gate:** a host wizard standing in it fills its ring over 180 ticks; at 180 the gate sends the command `run_requested` (`InputFrame.COMMAND_NAMES`), applied at the next tick's start on every machine at once, which starts the run's first room in the same recording. Only the host's seats fill it (owner decision 6).
- **The seat stones, the gate's ring and the code board** are drawn by the HUD and Feel from the seat table and the sim's state (VIEW only). The room's art is ordinary content: 32x32 tiles, four stones, an arch, a board, a dummy, listed in the room's `assets.json`.

### Joining a lobby that is under way

A machine that joins finds the lobby already playing: wizards walking, shots flying. It has to get the same state before it can play along. Two ways:

- **(a) Catch up on the lobby's recording.** The host sends the guest the lobby run's header and every tick so far; the guest plays them as fast as it can behind its loading screen, then plays on live. Only input frames cross the wire, with the decoders the spike already has (`Replay`, `InputFrame`). The lobby is a small room with at most four wizards and a dummy, so a tick costs little: ten minutes of lobby (36,000 ticks, about 1.5 MB of frames) plays in a few seconds. **Each visit to the lobby is a recording of its own** (the host begins a new one when a run ends), so a join only ever catches up on the lobby since the last run. A lobby left open over ten minutes restarts itself when a machine joins (everyone back at their stones, a moment's fade), so a join never takes long.
- **(b) The host's snapshot** (N10). One message, but a snapshot today names scenes and scripts by path, and a path from the wire is exactly what `net/`'s contract refuses ("no code, resource, path or URL ever comes from the wire"). Sending one safely needs a strict wire form that names only what the registry knows. That is the work joining a run under way needs anyway, and it is larger.

*Recommended: (a) for the lobby;* (b) later, with joining a run under way. (a) needs a faster catch-up in the live feed: today it runs at most three ticks a physics step; behind the loading screen it runs as many as fit in the frame (`LiveFeed.ticks_to_run`, the place S1 named for it).

### Seats belong to machines, the host decides

- **The seat table** is the host's: for each of the four seats, empty or the machine that holds it (0 is the host, 1 to 3 the guests) and which of that machine's devices. The host sends the whole table to every guest whenever it changes (`LOBBY`). The stones are drawn from it; the wizards come from the frames, as always.
- **A guest's player presses join:** the guest sends `SEAT_ASK {local}`, naming the device by a local number (0 to 3), never by a device id. The host gives the lowest free seat, or none, records the JOIN for that seat in its next tick (so the wizard appears on every machine at the same tick), and the new table says which seat it was. The guest seats that device on that seat (`PlayerInput.join_as(device, seat)`).
- **The host's own players** join as they do now, on the lowest seat the table has free.
- **Each machine is told its seats:** `set_own_seats(first, count)` becomes a seat mask (`set_own_seats_mask(mask)`), because a machine's seats are no longer one run of numbers (the host may hold P1 and P3). The keyboard can take any seat its machine owns, not only the first. The radial builder's mouse already follows the keyboard's seat.
- **Offline, the lobby is the same room with one machine:** Play goes into it, players press join, one of them walks into the gate. The mouse-click Play that seats the keyboard provisionally (owner, 2026-10-27) still does, in the lobby.

### The run with many seats and many machines

The spike's lockstep, generalised. The idea doesn't change: the host records every seat's frames and sends every tick to every guest.

- **`NetHost` holds up to three guests,** each with its own link, its own seats (a mask in place of the constant `SEAT`), its own limits (`MAX_READ`, `MAX_QUEUED` and the rest, per guest) and its own checks. Each guest seat's source is that guest's queue. A late frame is stood in for, seat by seat, as now.
- **A guest's FRAME carries a frame for each of its seats** (the mask, then the frames). The host takes only the seats the table gives that guest; a frame for any other seat closes that guest's link (`problem`).
- **TICK goes to every guest.** Guests never talk to each other; the host is the one star in the middle. The host's upload is three times the spike's, which is still small (frames are about 9 bytes a seat, 60 a second).
- **From the lobby into the run, and back:** the gate's command starts the run in the lobby's recording, so every guest goes into it at the same tick with no new header. At the run's end the host begins a new lobby recording and sends its header; a session now holds one recording after another (the spike's "no second run starts under one still playing" becomes "a new recording starts only from the host, after the last one ended").
- **Loading:** the run's rooms load as a run's do. A machine still loading when the gate fills is the slow-loading case of the spike (S4: a run cannot start while machines load at different speeds); so the host loads the run's first room on every machine while the ring fills (`play_load_requested`), and the gate's command waits until every machine has said it is loaded. The ring shows "loading P3's machine" meanwhile. That is loading, not waiting on a player.
- **A guest gone** (its link closed): its seats leave, so their wizards leave, as a pad pulled out would. The others play on. **The host gone:** every guest's replay ends, as in the spike. There is no handing the host over to another machine.
- **Checks:** each guest sends its hashes; a parting with any guest is said for that guest, and the host's run is saved once.
- **Pause online stops nothing** (online-ready, decision 3: it opens like the builder). The builder and the pause menu show only this machine's seats, as now.

### Not in this plan

- **Joining a run already under way,** for a machine or a new local player. It needs the host's snapshot sent to the joiner in a strict wire form (above, (b)), and the run's count in the snapshot (the seed-after-seek note in netcode-spike S1). It is the natural next step.
- **The hub.** M5 plans a hub with unlocks, currency and the codex (PLAN.md, `progression`). The lobby room could grow into it; that is M5's to decide (see the decisions).
- **Players' names.** Seats are "P1" to "P4", by colour and glyph. Names typed by strangers would need limits and moderation (see the decisions).
- **Matchmaking, public room lists, friends, Steam lobbies.** Steam (M7) can later give desktop players invites and its relay over the same seat table.
- **Invite links** (`…/play#KQ7RM`). On the web build the game can only read its page's address through `JavaScriptBridge`, which hard rule 4 bans, or through a change to the export's web page. Easy for players, but its own exception: later, if the owner wants it.

## Steps

Each is its own PR, reviewed by a second session, with tests checked against their behaviour broken, as in the spike.

- **L1: the lobby room, offline.** `content/rooms/lobby/` (the room, its four stones, the gate, the dummy, the board; art listed in `assets.json`), the `lobby_requested` start and the `run_requested` command, the room's rules (no enemies, no downing), the gate's ring, the stones' HUD; Play and the run's end go into the lobby. `core/input`: `set_own_seats_mask` and `join_as`. Tests: every join and leave order of 1 to 4 local players in the lobby, each at its own stone; the gate filled, left and filled again; the run started at the same tick in a replay of the lobby played again (the lobby is simulation, so `test_content_determinism.gd` and the snapshot tests cover it as any room); back to the lobby at the run's end with the seats kept. *Needs nothing from the owner but the room's look (decision 9); can start now, beside S5.*
- **L2: many seats, many machines, over pasted codes.** `NetHost` with up to three guests, FRAME with a seat mask, `LOBBY` and `SEAT_ASK`, the table in `NetPlay`, the lobby's recording sent to a joining guest and caught up behind the loading screen, one recording after another in a session. Tests (`tests/net/`): the decoders' new forms with a fuzz; the host against hand-written guests, a guest asking for a seat it was not given closed; a guest joining a lobby five minutes in and in step at its first live tick; the lobby's restart for a guest after ten minutes; scripted parties over the conditioned loopback for the owner's cases (2+2 on two machines, 1+1+1+1 on four, 3+1, 1+2+1), the same state at every tick through lobby, gate, run and back; a guest leaving mid-run while the others play on; `tools/online_pair.sh` grown to `online_party.sh` (three game processes). *After S5's numbers, so the measured `D` and channel choice go in first.*
- **L3: the signalling server.** `server/signal/` (the Worker, its room, its limits, its tests), `NetSignal` and `NetSignalHandshake`, room codes in the lobby. Tests: the server's own (rooms, codes, limits, malformed messages, a fuzz); the game's `NetSignal` decoder with a fuzz; `NetPlay` through a stand-in signalling link on a stepped clock, as `loop_handshake.gd` does now; the real game twice against `wrangler dev` on the machine. *Needs owner decisions 1 to 4 first.*
- **L4: what the owner's tries find.** Error messages that say what went wrong (no room, room full, server unreachable, no link: perhaps a router that needs TURN). TURN, if S5 says so (its own decision).

## Owner decisions

1. **Provider:** Cloudflare Workers and Durable Objects on the free plan (*recommended*), or AWS.
2. **Hard rule 4's exception widened:** `WebSocketPeer` in `net/` only, to the one URL constant `NetSignal.URL`.
3. **Where the server lives:** (a) `server/signal/` in this repository, with `.js` allowed there for Claude's PRs (*recommended*), or (b) a repository of its own.
4. **Deploy:** a workflow in `.github/` with a deploy-only Cloudflare token in the protected environment; the `workers.dev` address to start.
5. **The lobby offline too:** Play always goes into the lobby room (*recommended*: one way in, and local co-op gets the same clear seats and a place to try spells), or the lobby is for online only.
6. **Who starts:** only the host's wizards fill the gate (*recommended*), or any wizard's.
7. **No names for now** (*recommended*), seats by number and colour; or player-chosen names, with a length limit and a filter.
8. **Keep Join by code** beside room codes (*recommended*: a LAN with no internet, a server down, the tests).
9. **The lobby's look:** a corner of the crypt, in the crypt tileset (*recommended*: the art exists; one arch, four stones and a dummy are new), or a place of its own (a wizard's study, a courtyard) with new tiles, drawn in M2's style samples' way.
10. **Joining a lobby under way:** catch up on the lobby's recording (*recommended*), or wait for the snapshot over the wire.
11. **No downing in the lobby** (*recommended*), or the lobby plays by a run's rules.

## Risks

- **A server is something to keep running.** On the free plan it can't bill, but it can be down; Join by code is the fallback, and the game says the server could not be reached.
- **Strangers can reach the server.** It holds no data worth stealing and does nothing but pass two codes; its limits close abuse early, and the game checks everything it hands over as it checks a pasted code.
- **Four machines run the whole game.** The slowest machine sets the pace (online-ready's limits). With three guests the host does three times the spike's sending and checking; L2 measures it in the sandbox storm, browser as host included.
- **A guest joining a busy lobby** catches up on its whole recording. Capped at ten minutes by the lobby's restart; L2 measures the catch-up in a browser, the slowest machine, with four wizards casting the whole time.
- **The lobby is a room the game must keep deterministic,** like any other; it is content in the room's folder, so the content determinism tests play it with no list kept by hand.
- **`NetHost` grows from one guest to three,** in the code every online run goes through. Its limits become per guest, and the hostile-client tests of S2 run for each guest and for guests together.
- **Free tiers change.** The numbers above are as of 2026-11-10; they are checked again when the account is made, and the protocol doesn't depend on Cloudflare (any WebSocket server that passes the room messages will do).
