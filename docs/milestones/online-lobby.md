# Online lobby: room codes through a signalling server, and four seats from any machines

**Status (2026-11-10): a draft for the owner's review, not approved.** Asked by the owner after the netcode spike's S4: "What would it take, to allow for easier joining of multiplayer games?", then: "You can write up a plan for the signalling server! If AWS' free tier is enough, I am familiar with them. But if Cloudflare is just as easy and free, we can use them." And: "We also need a plan for a 'lobby' screen, where the screen is split into 4 seats and then local players can join alongside online players, until all 4 seats are taken or the host start the game before that. A cool feature would be a scenario like so: 2 local players on host machine, joined by 2 local players from another machine. Or like any combination thereof."

It builds on the spike ([netcode-spike.md](netcode-spike.md)): host-ordered lockstep over WebRTC, the strict decoders, `NetHandshake`, `NetCode`. It takes three items off the spike's "Not in the spike" list: a signalling server, more than one client, and more than one seat a machine. It leaves joining a run already under way for later (below).

## What the players see

1. **Play** (offline or online) opens **the lobby**: the screen split into four quadrants, one a seat (P1 to P4), each in its seat's colour. An empty seat says how to join ("Press A / Enter to join"). A taken seat shows its player's device glyph and where they play: "this machine" or "online".
2. **On the host:** a button **Open online** shows a **room code** of five characters (`KQ7RM`) with Copy. Nothing connects anywhere before it is pressed.
3. **On another machine:** **Join online**, type the five characters, Connect. That machine sees the same lobby, with the host's seats already taken.
4. **Anyone on any machine presses join** on their device and takes the lowest free seat. Two players on the host and two on the guest, one on each of four machines, three on the host and one guest: any mix, up to four seats and up to four machines.
5. **A seat's player presses leave** and the seat is free again. A machine that goes away frees all its seats.
6. **The host presses Start** when at least one seat is taken, or the lobby starts itself when all four are taken and every machine is loaded (the host's choice; see the decisions). From then the run is closed: no new seats until the run ends. Leaving still works, and the game plays on without that player (pillar 2: nobody waits).
7. **The run's end** brings everyone back to the lobby with their seats, so the same party plays again without a new code.

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

## Part 2: the lobby and four seats from any machines

### Seats belong to machines, the host decides

- **The seat table** is the host's: for each of the four seats, empty or the machine that holds it (0 is the host, 1 to 3 the guests) and which of that machine's devices. The host sends the whole table to every guest whenever it changes (`LOBBY`), and every machine draws its lobby from it.
- **A guest's player presses join:** the guest sends `SEAT_ASK {local}`, naming the device by a local number (0 to 3) and never by a device id. The host gives the lowest free seat, or none, and the new table says which. The guest then seats that device on that seat (`PlayerInput.join_as(device, seat)`).
- **The host's own players** join as they do now, but on a seat the host picks from the table.
- **Each machine is told its seats:** `set_own_seats(first, count)` becomes a seat mask (`set_own_seats_mask(mask)`), because a machine's seats are no longer one run of numbers (the host may hold P1 and P3). The keyboard can take any seat its machine owns, not only the first. The radial builder's mouse already follows the keyboard's seat.
- **Offline, the lobby is the same screen with one machine:** Play opens it, players press join, the first one in presses Start. The mouse-click Play that seats the keyboard provisionally (owner, 2026-10-27) becomes "click a seat".

### The run with many seats and many machines

The spike's lockstep, generalised. The idea doesn't change: the host records every seat's frames and sends every tick to every guest.

- **`NetHost` holds up to three guests,** each with its own link, its own seats (a mask in place of the constant `SEAT`), its own limits (`MAX_READ`, `MAX_QUEUED` and the rest, per guest) and its own checks. Each guest seat's source is that guest's queue. A late frame is stood in for, seat by seat, as now.
- **A guest's FRAME carries a frame for each of its seats** (the mask, then the frames). The host takes only the seats the table gives that guest; a frame for any other seat closes that guest's link (`problem`).
- **TICK goes to every guest.** Guests never talk to each other; the host is the one star in the middle. The host's upload is three times the spike's, which is still small (frames are about 9 bytes a seat, 60 a second).
- **The header's seats** are the table's at Start, and the replay format already holds four. Each guest learns its own seats from the table, never from a frame.
- **A guest gone** (its link closed): its seats leave, so their wizards leave, as a pad pulled out would. The others play on. **The host gone:** every guest's replay ends, as in the spike. There is no handing the host over to another machine.
- **Checks:** each guest sends its hashes; a parting with any guest is said for that guest, and the host's run is saved once.
- **Loading:** the host starts the run only when every machine in the table has loaded and pinged (the spike's READY_PINGS, per guest). Start shows "waiting for P3's machine" until then. That is loading, not waiting on a player.
- **Pause online stops nothing** (online-ready, decision 3: it opens like the builder). The builder and the pause menu show only this machine's seats, as now.

### Not in this plan

- **Joining a run already under way,** for a machine or a new local player. It needs the host's snapshot sent to the joiner (N10), and the run's count in the snapshot (the seed-after-seek note in netcode-spike S1). It is the natural next step; the lobby is built so that an open seat can say "join the run" later.
- **Players' names.** Seats are "P1" to "P4", by colour and glyph. Names typed by strangers would need limits and moderation (see the decisions).
- **Matchmaking, public room lists, friends, Steam lobbies.** Steam (M7) can later give desktop players invites and its relay over the same seat table.
- **Invite links** (`…/play#KQ7RM`). On the web build the game can only read its page's address through `JavaScriptBridge`, which hard rule 4 bans, or through a change to the export's web page. Easy for players, but its own exception: later, if the owner wants it.

## Steps

Each is its own PR, reviewed by a second session, with tests checked against their behaviour broken, as in the spike.

- **L1: the lobby, offline.** `hud/menus/lobby/`: the four quadrants, join and leave by device, Start; Play and the sandbox go through it. `core/input`: `set_own_seats_mask` and `join_as`. Events for the lobby's requests and its table, on the bus (the lobby knows nothing of `net/`). Tests: every join and leave order of 1 to 4 local players in the lobby, Start with one to four, the mouse click on a seat, back to the lobby at the run's end with the seats kept. *Needs nothing from the owner; can start now, beside S5.*
- **L2: many seats, many machines, over pasted codes.** `NetHost` with up to three guests, FRAME with a seat mask, `LOBBY` and `SEAT_ASK`, the table in `NetPlay`, the lobby online with "Join by code" (one code pair a guest). Tests (`tests/net/`): the decoders' new forms with a fuzz; the host against hand-written guests, a guest asking for a seat it was not given closed; scripted fights over the conditioned loopback for the owner's cases (2+2 on two machines, 1+1+1+1 on four, 3+1, 1+2+1), the same state at every tick, a guest leaving mid-run while the others play on; `tools/online_pair.sh` grown to `online_party.sh` (three game processes, both seats of one scripted). *After S5's numbers, so the measured `D` and channel choice go in first.*
- **L3: the signalling server.** `server/signal/` (the Worker, its room, its limits, its tests), `NetSignal` and `NetSignalHandshake`, room codes in the lobby. Tests: the server's own (rooms, codes, limits, malformed messages, a fuzz); the game's `NetSignal` decoder with a fuzz; `NetPlay` through a stand-in signalling link on a stepped clock, as `loop_handshake.gd` does now; the real game twice against `wrangler dev` on the machine. *Needs owner decisions 1 to 4 first.*
- **L4: what the owner's tries find.** Error messages that say what went wrong (no room, room full, server unreachable, no link: perhaps a router that needs TURN). TURN, if S5 says so (its own decision).

## Owner decisions

1. **Provider:** Cloudflare Workers and Durable Objects on the free plan (*recommended*), or AWS.
2. **Hard rule 4's exception widened:** `WebSocketPeer` in `net/` only, to the one URL constant `NetSignal.URL`.
3. **Where the server lives:** (a) `server/signal/` in this repository, with `.js` allowed there for Claude's PRs (*recommended*), or (b) a repository of its own.
4. **Deploy:** a workflow in `.github/` with a deploy-only Cloudflare token in the protected environment; the `workers.dev` address to start.
5. **The lobby offline too:** Play always goes through the lobby (*recommended*: one screen to learn, and local co-op gets the same clear seats), or the lobby is for online only.
6. **Start:** the host only (*recommended*), or the lobby also starts itself when all four seats are taken.
7. **No names for now** (*recommended*), seats by number and colour; or player-chosen names, with a length limit and a filter.
8. **Keep Join by code** beside room codes (*recommended*: a LAN with no internet, a server down, the tests).

## Risks

- **A server is something to keep running.** On the free plan it can't bill, but it can be down; Join by code is the fallback, and the game says the server could not be reached.
- **Strangers can reach the server.** It holds no data worth stealing and does nothing but pass two codes; its limits close abuse early, and the game checks everything it hands over as it checks a pasted code.
- **Four machines run the whole game.** The slowest machine sets the pace (online-ready's limits). With three guests the host does three times the spike's sending and checking; L2 measures it in the sandbox storm, browser as host included.
- **`NetHost` grows from one guest to three,** in the code every online run goes through. Its limits become per guest, and the hostile-client tests of S2 run for each guest and for guests together.
- **Free tiers change.** The numbers above are as of 2026-11-10; they are checked again when the account is made, and the protocol doesn't depend on Cloudflare (any WebSocket server that passes the room messages will do).
