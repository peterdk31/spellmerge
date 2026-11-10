# Online lobby: room codes through a signalling server, and the hub as the lobby

**Status (2026-11-10): the owner's direction given, the plan to build from.** Asked by the owner after the netcode spike's S4: "What would it take, to allow for easier joining of multiplayer games?", then: "You can write up a plan for the signalling server! If AWS' free tier is enough, I am familiar with them. But if Cloudflare is just as easy and free, we can use them." And: "We also need a plan for a 'lobby' screen, where the screen is split into 4 seats and then local players can join alongside online players, until all 4 seats are taken or the host start the game before that. A cool feature would be a scenario like so: 2 local players on host machine, joined by 2 local players from another machine. Or like any combination thereof." Then: "Can we make 'The Lobby' a scene players can move around in?" And on the draft: "This room IS the M5 hub! So later on, it carries the hosts savegame/meta progress (one of 3 save files). For now it is a large 'island floating in the void' with only the 'start run' teleporter stone in the middle (which every connected player has to stand on, before the game can be started by pressing A, by anyone) and 3 decoys standing together somewhere. And ofcourse a multiplayer altar with the netcode, which players will be placed on when joining. Go with the replay for joining now! Players can be hit in the lobby, but they are invincible there. So for now players can only join while the host is in the lobby. (And this might actually be how it should just be - although reconnects for players should be possible during a run) A joining player simply enter the code in the main menu. We need to get a working lobby / server quickly. Then the rest can follow later in the plan."

It builds on the spike ([netcode-spike.md](netcode-spike.md)): host-ordered lockstep over WebRTC, the strict decoders, `NetHandshake`, `NetCode`. It takes three items off the spike's "Not in the spike" list: a signalling server, more than one client, and more than one seat a machine. **Speed first** (the owner): the steps below get a working lobby and server first (L1, L2), and the rest follows (L3, L4).

## What the players see

1. **Play** takes everyone into **the hub**: a large island floating in the void (`content/rooms/hub/`). The hub is the lobby now and M5's hub later, where the host's save and meta progress will live (one of three save files; M5's, not this plan's).
2. **On the island, for now, three things:**
   - **the teleporter stone** in the middle, which starts a run;
   - **three training dummies** standing together off to one side (`content/enemies/training_dummy/`, as in the sandbox), to try spells on;
   - **the multiplayer altar**, which holds the room code.
3. **A player presses join** on their device and their wizard appears. From then they walk, aim, cast and build their staffs as in a run.
4. **In the hub, wizards are invincible:** a shot still hits them (the flash, the knockback), but takes no health, so nobody is ever downed there. Friendly fire stays on, as everywhere (owner, 2026-10-28).
5. **Online, on the host:** a host wizard walks to the altar and presses A. The altar opens the room and shows a **room code** of five characters (`KQ7RM`) over it, in the room, and on the HUD with Copy. Nothing connects anywhere before that.
6. **On another machine:** the main menu's **Join online**, type the five characters, Connect. That machine loads the host's hub as it is right now, everyone where they stand, and its players press join. **A joining machine's wizards appear on the altar.**
7. **Any mix, up to four seats and four machines:** two players on the host and two on a guest, one on each of four machines, three on the host and one guest.
8. **A seat's player presses leave** and their wizard is gone and the seat free. A machine that goes away frees all its seats.
9. **Starting a run:** when **every joined wizard stands on the teleporter stone**, it lights, and **anyone** pressing A starts the run. Someone stepping off puts it out again.
10. **Joining is only while the host is in the hub.** During a run the room is closed to new machines. (Later, a machine that lost its link during a run may come back: step L4.)
11. **The run's end** brings everyone back to the hub, so the same party plays again without a new code.

The manual codes of the spike stay, under the main menu's Join online as **Join by code**, for a LAN with no internet, a server that is down, and the tests.

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
- **Whom the game talks to, then:** the STUN server, our signalling server (one URL constant, `NetSignal.URL`), and the machines whose codes the server hands over, which are only those in the same room. Still nothing before the host opens the altar or a player presses Join online.

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

## Part 2: the hub as the lobby, four seats from any machines

### The hub is simulation, so every machine sees the same hub

Where each wizard stands, what each casts, the dummies' hits: that is the game, not a menu. Two machines can only see the same hub the way they see the same run, by lockstep (AGENTS.md, "The simulation is state by default"). So **the hub is a run of its own kind**, recorded by the host and played live by every guest, with the spike's sessions.

- **A new start, `hub_requested`** (`Replay.STARTS`), heard by Flow, which loads the hub. Play and a run's end go there. Coop seats and unseats wizards in it as in any room (`seat_joined`, `seat_left`): the host's at the room's `player_spawns`, a guest's on the altar.
- **The hub's rules,** set in its `.tres` (`RoomBase` grows a field, `invincible`): Flow gives every wizard there the protection `Health.protect` already has, for as long as it is in the hub, so hits land and take nothing. No enemies but the dummies, no rewards.
- **The teleporter stone:** an area of the room. It lights while every joined wizard stands in it (one or four, from any machines). A press of A by any seat while it is lit is the command `run_requested` (`InputFrame.COMMAND_NAMES`), applied at the next tick's start on every machine at once, which starts the run's first room in the same recording.
- **The altar:** an area of the room and the guests' spawn. On the host, A pressed by a host wizard at the altar is the request `online_open_requested` on the bus (not a command: the simulation never knows a network exists); `net/` opens the room and sends back the code, which the HUD draws over the altar (VIEW only).
- **The art:** the island's edge against the void, its floor, the stone (lit and dark), the altar, in 32x32 pixel art, listed in the room's `assets.json`. The void is a backdrop drawn behind the island; its edge is a wall.

### Joining the hub: catch up on its recording

The owner's choice: the host sends the joining machine the hub's header and every tick recorded so far; the guest plays them as fast as it can behind its loading screen, then plays on live. Only input frames cross the wire, through the decoders the spike already has (`Replay`, `InputFrame`), so nothing new is trusted.

- **Each visit to the hub is a recording of its own:** the host begins a new one when a run ends, so a join only catches up on the hub since the last run.
- **The hub is cheap to play:** at most four wizards and three dummies. Ten minutes of hub (36,000 ticks, about 1.5 MB of frames) should play in a few seconds; L2 measures it in a browser.
- **A hub open more than ten minutes** starts itself again when a machine joins (a new hub recording: everyone back at their spawn after a moment's fade), so a join never takes long.
- **The live feed's catch-up:** today it runs at most three ticks a physics step; while a guest catches up behind its loading screen, it runs as many as fit in the frame (`LiveFeed.ticks_to_run`, the place S1 named for it).

The host's snapshot over the wire (N10) stays for later: a snapshot today names scenes and scripts by path, which `net/` must never take from the wire, so it needs a strict wire form first. Reconnecting during a run needs it (L4).

### Seats belong to machines, the host decides

- **The seat table** is the host's: for each of the four seats, empty or the machine that holds it (0 is the host, 1 to 3 the guests) and which of that machine's devices. The host sends the whole table to every guest whenever it changes (`LOBBY`); the HUD shows it (each seat's colour, glyph, "this machine" or "online").
- **A guest's player presses join:** the guest sends `SEAT_ASK {local}`, naming the device by a local number (0 to 3), never by a device id. The host gives the lowest free seat, or none, records the JOIN for that seat in its next tick (so the wizard appears on every machine at the same tick), and the new table says which seat it was. The guest seats that device on that seat (`PlayerInput.join_as(device, seat)`).
- **The host's own players** join as they do now, on the lowest seat the table has free.
- **Each machine is told its seats:** `set_own_seats(first, count)` becomes a seat mask (`set_own_seats_mask(mask)`), because a machine's seats are no longer one run of numbers (the host may hold P1 and P3). The keyboard can take any seat its machine owns, not only the first.

### The run with many seats and many machines

The spike's lockstep, generalised: the host records every seat's frames and sends every tick to every guest.

- **`NetHost` holds up to three guests,** each with its own link, its own seats (a mask in place of the constant `SEAT`), its own limits (`MAX_READ`, `MAX_QUEUED` and the rest, per guest) and its own checks. A late frame is stood in for, seat by seat, as now.
- **A guest's FRAME carries a frame for each of its seats** (the mask, then the frames). The host takes only the seats the table gives that guest; a frame for any other seat closes that guest's link (`problem`).
- **TICK goes to every guest.** Guests never talk to each other; the host is the star in the middle. Its upload is three times the spike's, still small (about 9 bytes a seat a tick).
- **From the hub into the run, and back:** the stone's command starts the run in the hub's recording, so every guest goes in at the same tick with no new header. At the run's end the host begins a new hub recording and sends its header; a session now holds one recording after another.
- **Loading:** while the stone is lit, the host has every machine load the run's first room (`play_load_requested`), and A starts nothing until every machine has said it is loaded (the spike's S4 lesson: machines that start a run while loading at different speeds part). The stone shows "loading" meanwhile.
- **A guest gone:** its seats leave, so their wizards leave, as a pad pulled out would; the others play on. **The host gone:** every guest's replay ends, as in the spike. No host migration.
- **Checks:** each guest sends its hashes; a parting with any guest is said for that guest, and the host's run is saved once.
- **Pause online stops nothing** (online-ready, decision 3). The builder and the pause menu show only this machine's seats.

### Not in this plan

- **The hub's saves and meta progress** (three save files, the host's carried): M5.
- **Reconnecting during a run** (L4, after the strict snapshot), and joining a run under way, which the owner leaves out for now ("this might actually be how it should just be").
- **Players' names.** Seats are "P1" to "P4", by colour and glyph.
- **Matchmaking, public room lists, friends, Steam lobbies** (M7 can give desktop players Steam's invites and relay over the same seat table).
- **Invite links** (`…/play#KQ7RM`): they need `JavaScriptBridge` or a change to the web export's page, an exception of their own.

## Steps

Each is its own PR, reviewed by a second session, with tests checked against their behaviour broken, as in the spike. L1 and L2 are the working lobby and server, as fast as they can come; they don't wait for S5.

- **L1: the hub, offline.** `content/rooms/hub/` (the island, the stone, the altar, three dummies; art in `assets.json`), the `hub_requested` start, the `run_requested` command, the hub's invincibility, the stone's light; Play and a run's end go to the hub. Tests: 1 to 4 local players joining and leaving in any order; the stone lit only with every wizard on it, put out by one stepping off or a new join, A from any seat starting the run; a wizard hit in the hub losing no health; a run started from the hub and played again from its replay at the same tick (the hub is a room, so the content determinism and snapshot tests cover it). *Needs nothing from the owner; first.*
- **L2: the server and room codes, one guest machine with up to three seats.** `server/signal/` (the Worker, its room, its limits, its tests), `NetSignal` and `NetSignalHandshake`; the altar's `online_open_requested`; Join online with the room code on the main menu; the hub's recording caught up by the guest; `LOBBY`, `SEAT_ASK`, the seat mask in FRAME and the input layer's `set_own_seats_mask` and `join_as`; one recording after another in a session. Tests: the server's own (rooms, codes, limits, malformed messages, a fuzz); `NetSignal`'s decoder with a fuzz; `NetPlay` through a stand-in signalling link on a stepped clock; a guest joining a hub five minutes in and in step from its first live tick; 2+2 and 1+3 over the conditioned loopback through hub, stone, run and back to the hub, the same state at every tick; the real game twice against `wrangler dev` on one machine. *Needs the owner's steps below.*
- **L3: up to three guest machines.** `NetHost` with up to three guests, per-guest limits and checks; 1+1+1+1 and 1+2+1 over the loopback; `tools/online_party.sh`, four game processes. The host's cost measured in the storm, a browser host included.
- **L4: what the owner's tries find.** Reconnecting during a run (the strict snapshot over the wire); error messages that say what went wrong (no room, room full, server unreachable, no link); TURN, if S5 says so.

## What the owner does, once

For L2's server (the game's side can be built and tested before, against `wrangler dev`):

1. **A Cloudflare account** on the free plan.
2. **A deploy:** either run `npx wrangler deploy` in `server/signal/` once (it signs in through the browser), or make an API token that may only edit this account's Workers scripts and store it as a secret in the protected environment, for a deploy workflow in `.github/`. Then send me the Worker's address (`spellmerge-signal.<account>.workers.dev`), which goes into `NetSignal.URL`.
3. **Approve the rules change** I draft in L2's PR (`ci/smbot/rules.py`, `AGENTS.md`, `docs/SECURITY-CHECKLIST.md`, `net/README.md`): `WebSocketPeer` allowed in `net/` only; `.js`, `wrangler.toml` and `package.json` allowed in `server/signal/` only, for Claude's PRs; `server/` added to the paths Claude maintains.
4. **Later, a CI job** for the server's tests (`ci/` is the owner's); until then they run in my sessions and in the PR's description.

## Owner decisions

Taken (2026-11-10):

1. **Provider: Cloudflare** Workers and Durable Objects on the free plan (the owner: "if Cloudflare is just as easy and free, we can use them").
2. **The lobby is the hub,** a large island in the void: the teleporter stone in the middle, three dummies together, the multiplayer altar. M5 grows it and gives it the host's save.
3. **Starting:** every joined wizard on the stone, then A by anyone.
4. **Joining:** by catching up on the hub's recording; only while the host is in the hub; the joining machine's wizards appear on the altar; the code typed in the main menu.
5. **In the hub, hits land and take nothing.**
6. **Speed first:** a working lobby and server, the rest after.

Taken as recommended unless the owner says otherwise:

7. **Hard rule 4's exception widened** to `WebSocketPeer` in `net/` only, to the one URL constant `NetSignal.URL`.
8. **The server's code in this repository,** `server/signal/`, maintained by Claude, its deploy the owner's.
9. **The altar opens the room** when a host wizard presses A at it (nothing connects before), rather than every hub opening one by itself.
10. **No names for now;** seats by number and colour.
11. **Join by code stays** beside room codes.

## Risks

- **One player can hold the start back:** the stone lights only with every joined wizard on it, so a player gone for coffee keeps the others in the hub until they press leave for them (or their machine's player does). It is the owner's choice, and only in the hub: in a run, nobody waits (pillar 2).
- **A server is something to keep running.** On the free plan it can't bill, but it can be down; Join by code is the fallback, and the game says the server could not be reached.
- **Strangers can reach the server.** It holds nothing worth stealing and only passes codes; its limits close abuse early, and the game checks everything it hands over as it checks a pasted code.
- **A guest joining a busy hub** catches up on its whole recording; capped by the hub's restart after ten minutes. L2 measures it in a browser, the slowest machine, with four wizards casting.
- **Four machines run the whole game.** The slowest sets the pace (online-ready's limits); L3 measures the host with three guests.
- **`NetHost` grows from one guest to three,** in the code every online run goes through; the hostile-client tests of S2 run for each guest and for guests together.
- **Free tiers change.** The numbers above are as of 2026-11-10, checked again when the account is made; the protocol doesn't depend on Cloudflare.
