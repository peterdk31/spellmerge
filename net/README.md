# Net

## Purpose

Online play: host-ordered lockstep on `core/sim`'s replay machinery ([docs/milestones/online-lobby.md](../docs/milestones/online-lobby.md)). The host records its run and sends every tick's input frames; a client plays them as a live replay and sends its own seats' frames. Only inputs cross the wire.

- **Nothing outside this folder knows a network exists.** This folder knows `core/sim` and `core/input`, nothing of gameplay or the HUD.
- **The one folder whose scripts may name networking classes** (the owner's exception to hard rule 4, 2026-11-10; `NET_DIR` in `ci/smbot/rules.py`): only a WebRTC peer, its data channel and the WebSocket to the room server. Claude's and the owner's only.
- Only `NetRtc`/`NetRtcLink` name WebRTC classes, only `NetSignalSocket` the WebSocket; only `net_signal*.gd` knows the room server, and only `net_rtc*.gd` and `net_code.gd` know WebRTC. Nothing connects until a player presses Host or Join (or opens a room).

## What is here

- `NetMessage` (wire messages and strict decoder: HEADER, TICK, FRAME, HASHES, PARTED, PING, PONG, SEAT_ASK, LOBBY, RUN); `NetLink` (whole messages, in order) with `NetLoopback`, `NetConditioner`, `NetRtcLink`.
- Sessions: `NetSession` (`problem`, `reason`), `NetRun`, `NetHost` (`add_guest`, `start`, `begin`, `rebegin`, `GUESTS`, `SEAT`), `NetGuest`, `NetClient` (`LiveFeed`, `pace`), `NetDelay`, `NetChecks`, `NetStats`, `NetLog`.
- Meeting: `NetHandshake` (`takes`, `next_link()`), `NetRtc` (`STUN`, `why_no_link`), `NetSignalHandshake`, `NetSignal` (`read`, `URL`), `NetCode` (`read`), `NetRelay`, `NetWebRTC` (ask before making a peer), `NetWhy` (an `OnlineWhy` name with facts).
- Autoload `NetPlay`: hears the bus requests, picks the handshake, loads, steps the session on the Tick's `ticked`, saves a parted run.

## Seams

- A session knows a `NetLink`, never what carries it, and reaches the game only through the frames service (`Frames.record`, `set_source`, `play_live`, `restart`, `save_run`), the input layer (`join_asker`, `join_as`, virtual devices) and a `Callable` for the checks' areas.
- `NetPlay` knows a `NetHandshake`, never WebRTC, and the game only through `core/`: the bus (`online_*` requests in; `online_changed`, `online_line_changed`, `play_load_requested` out; `hub_changed`), the Tick and the frames service.
- **net/ names why; the HUD words it.** Nothing here writes a sentence for the screen.
- A new way to meet is another `NetHandshake` and `NetLink`, nothing else changed.

## How a run goes

Joining is in the hub only (`hub_changed`); each return to the hub is a new recording. **Seats are the host's to give, only between ticks** (SEAT_ASK by a number 0-3, answered with LOBBY). Each host tick uses a seat's newest walk/aim/held and all presses/commands; **with none arrived the last frame stands in without presses and commands; the host never waits.** Whoever holds a session calls **`after_tick()` after every tick**.

## Contract

- **Untrusted bytes.** Every message is decoded strictly before use: the envelope by `NetMessage` (kind, length, the kind's limit, names as plain text, nothing left over), a header and tick by `Replay`'s decoder, a frame by `InputFrame`'s. Never `bytes_to_var`; no code, resource, path or URL ever comes from the wire. A frame's commands are `InputFrame.COMMAND_NAMES`.
- **Each side takes only the other's kinds.** Host from a guest: FRAME, HASHES, PING, SEAT_ASK, RUN. Client: HEADER, TICK (in order, of the newest recording), PARTED, PONG, LOBBY. Anything else or malformed closes the link, with `problem`.
- **Refused is final.** A closed session reads and uses nothing more of that link (queued frames and commands dropped, its seats leave). A refused guest never touches another guest's link or seats.
- **A client plays only its own seats.** A frame for a seat not given closes the link (one for a seat given back within 600 ticks is dropped). A JOIN in a frame seats nobody; only an ask does, only on a free seat. A LOBBY names players 0-3, each on one seat. A device is never named on the wire. The client never sends a frame for an earlier host tick than the one before.
- **Limits, each guest on its own.** Host: at most 64 messages a tick read from a guest; at most 600 frames waiting (all its seats), each no earlier than that seat's previous and at most 600 ticks ahead; at most 64 commands a seat waiting; a tick's frame within 16 commands and 16 kB; one check per window, in order, of a played tick; a check names at most 2,048 areas; a joined-late guest gets at most 240 ticks a tick; at most 16 seat asks wait. Client: at most 600 messages a step. Loopback: closes at 8,192 unread.
- **A link is handed over open** and carries whole messages up to `NetMessage.MAX_BYTES` (`NetRtcLink` splits into 16 kB packets).
- **A pasted code is untrusted text.** `NetCode.read` checks length, prefix, alphabet, every unpacked line's form, the data channel's required lines and each candidate's whole grammar (an IP address or a `.local` name; nothing is looked up) before WebRTC sees any of it; a refused code changes and keeps nothing. A handshake takes only the code kind its side expects (host an answer, joiner an offer).
- **What the room server says is untrusted text.** `NetSignal.read` takes only the server's nine forms, written exactly (keys in order, no space, nothing more); never parsed as an open object. A handshake takes only its side's kinds in a sensible order; anything else ends it. A code handed over by the server is checked by `NetCode.read` like a pasted one. The socket closes on a non-text, empty, over-16,384-character or non-printable packet, and on 64 unread messages.
- **The room server is reached only when asked** (opening a room, joining by code), only at `NetSignal.URL`; a joiner's socket closes once linked. The server keeps no address or code (server/signal/README.md).
- **Whom a machine talks to:** the STUN server named in `NetRtc.STUN` (it sees the address, nothing of the game) and the machine whose code was pasted. Nothing listens for strangers; nothing is made before Host or Join.
- **The WebRTC link's limits:** a packet that is text, empty, too long or marked otherwise, a message past `NetMessage.MAX_BYTES`, 8,192 unread messages or 8 MB of them, or 4 MB waiting to leave close it; a poll takes at most 1,024 packets.
- **A code always holds a candidate:** made one poll after gathering is done; none after four seconds fails. Only the host, given the answer, times out (thirty seconds). `why_no_link` names no address.
- **Silence:** once something was heard, ten seconds of a session's own stepping with nothing read closes the link (`NetSession.SILENT_MS`); nothing counts before the first message; a local stall counts a quarter second at most.
- **Files:** only `NetLog` writes one (`user://net/host.log`, `client.log`, written out). A parted run is saved by `Frames.save_run` under `user://replays/`, with a name of `NetPlay`'s own, never one from the wire.
- **One recording after another.** A later HEADER is the next recording (at most four wait); the client says which it plays (RUN: never one not sent, else the link closes); the host uses a guest's frames and checks only for that recording.
- **A source never seats.** Seats are given and taken by the host session through the input layer (`core/sim/frame_source.gd`): on an ask, a LEAVE, or the client gone.
- **A run joined a while in is checked from the next whole window.**
- **Sessions read the link only when called:** the host when its seat's frame is built, the client at each physics step's start, both by `pump()` before the run. No `_process`, no thread.
- **The clock is given.** The conditioner and the ping run on a clock handed to them. Nothing here is simulation state, and the simulation reads nothing here.

## Tests

`tests/net/`: `test_net_message.gd` (decoder fuzz, seat messages), `test_net_link.gd`, `test_net_host.gd`, `test_net_client.gd`, `test_net_seats.gd`, `test_net_session.gd` and `test_net_party.gd` (on `net_pair.gd`: up to four machines in step over a conditioned loopback), `test_net_code.gd` (fuzz), `test_net_rtc.gd` (real WebRTC; needs `ci/build/webrtc.sh`), `test_net_play.gd` (`loop_handshake.gd`, `room_handshake.gd`), `test_net_signal.gd` (fuzz), `test_net_signal_handshake.gd` (`signal_socket.gd`). `tests/benchmark/net_grid.gd` (`--guests=3`). The real game twice: `tools/online_pair.sh`, `tools/online_room.sh`; the real server: `tools/online_signal.sh`.

History and reasons: [docs/history/net-README.md](../docs/history/net-README.md).
