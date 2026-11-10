# Net

## Purpose

Two machines playing one run (the netcode spike, [docs/milestones/netcode-spike.md](../docs/milestones/netcode-spike.md)): host-ordered lockstep, built on the replay machinery of `core/sim`. The host records its run and sends every tick's input frames; the client plays them as a live replay and sends its own seat's frames. Only inputs cross the wire, and the simulation is the same on both machines.

**Nothing outside this folder knows a network exists.** The game sees input frames (`core/sim/frames.gd`), whatever made them: a device, a bot, a replay, or a session here. This folder knows `core/sim` and `core/input`, and nothing of gameplay or the HUD.

This is the one folder whose scripts may name networking classes (the owner's exception to hard rule 4, 2026-11-10, docs/DECISIONS.md; `NET_DIR` in `ci/smbot/rules.py`), and only a WebRTC peer and its data channel. It is Claude's and the owner's only. Only `NetRtc` and `NetRtcLink` name those classes, and nothing connects anywhere until a player presses Host or Join.

## What is here

| File | What it is |
|---|---|
| `net_message.gd` (`NetMessage`) | The messages on the wire and their strict decoder: HEADER, TICK, FRAME, HASHES, PARTED, PING, PONG |
| `net_link.gd` (`NetLink`) | What a session knows of the wire: whole messages out and in, in order, open or closed |
| `net_loopback.gd` (`NetLoopback`) | A link inside one process (the tests, the measured grid) |
| `net_conditioner.gd` (`NetConditioner`) | A link made worse on purpose: delay, jitter and loss, seeded, on a clock it is given |
| `net_session.gd` (`NetSession`) | What both sessions are: reading the link within a limit, refusing it (`problem`), the checks, the parting kept, the counters |
| `net_host.gd` (`NetHost`) | The host's session: seats the client, gives its seat a `FrameSource`, sends the header and every recorded tick, compares the checks |
| `net_client.gd` (`NetClient`) | The client's session: gives the frames service a `LiveFeed` that plays the host's run, and sends its seat's frames |
| `net_checks.gd` (`NetChecks`) | The hash checks: one part of the state each tick, a whole check every 60 |
| `net_stats.gd` (`NetStats`) | A session's counters (ping, delay, late frames, waits, bytes, check and link time) |
| `net_webrtc.gd` (`NetWebRTC`) | Whether this build has WebRTC: a browser's own, or the WebRTC extension that `ci/build/webrtc.sh` puts in the desktop builds and the test runs (S3; `addons/webrtc_native/`, never committed). A peer made without it logs an engine error, so ask first |
| `net_code.gd` (`NetCode`) | The code two players swap by copy and paste: a session description and its candidates as text, and the strict check of a pasted one |
| `net_handshake.gd` (`NetHandshake`) | How two machines come to hold a link: the host offers, each takes the other's code, and a `NetLink` is there. What `NetPlay` knows of connecting |
| `net_rtc.gd` (`NetRtc`) | The handshake over WebRTC: the peer, its channel, the one STUN server, the code once the candidates are gathered |
| `net_rtc_link.gd` (`NetRtcLink`) | The link over the WebRTC data channel: polled when read, large messages split and joined |
| `net_play.gd` (the autoload `NetPlay`) | Host and Join: hears the main menu's requests on the bus, swaps the codes, has both machines load, makes the session, starts the run, follows the Tick, says where things stand, saves a parted run |
| `net_log.gd` (`NetLog`) | A session's counters as a file, `user://net/host.log` or `client.log` |
| `net_press_probe.gd` (`NetPressProbe`) | Times the client's presses from the step they were sent to the step they ran (a measure for S5; it changes nothing) |

The seams, each one-way: a session knows a `NetLink` (never what carries it), and reaches the game only through three things of `core/sim` and `core/input`: the frames service (`Frames.record`, `set_source`, `play_live`), the input layer's virtual device for the client's seat, and a `Callable` that hands it the game's areas for the checks. The frames service holds the host's `FrameSource` and the client's `LiveFeed` (small inner classes that call their session) and knows nothing of sessions.

Connecting has its own seams. `NetPlay` knows a `NetHandshake` (never WebRTC) and the two sessions; a handshake hands it a `NetLink`. It reaches the rest of the game only through `core/`: the bus (the menu's `online_*` requests in, `online_changed` and `online_line_changed` out, `play_load_requested` to whoever loads), the input layer's `set_own_seats`, the Tick's `ticked` and `state_areas`, and the frames service through the sessions. The main menu and the HUD's line know the bus only.

## Host and Join

1. **Host** makes this machine's code (`online_changed(&"code", code, "")`); the player sends it to the other, by chat.
2. **Join**, with the host's code pasted, makes that machine's code, which goes back the same way.
3. **The host given that code**, the machines look for each other (a public STUN server tells each its address as the internet sees it; on one network or one machine none is needed).
4. **Linked**, each machine loads what a room needs (`play_load_requested`), then the client pings; the host starts the run, a sandbox, when it is loaded and has heard three pings.
5. **While it plays**, one line of counters goes to the HUD a second and a row to the log every ten; a failed hash check is said once and each side saves its run (`user://replays/online_host_parted.replay`, `online_client_parted.replay`).
6. **The other machine gone:** the host's run plays on without the client's seat; the client's replay ends and its game goes on alone. All four seats are the machine's again, its own device staying where it plays. Nothing more is heard after that: no second run starts under one still playing.

**Each machine has one seat** (the host 0, the client `NetHost.SEAT`), and `NetPlay` tells the input layer so (`set_own_seats`): that machine's keyboard or first gamepad is that seat, in the builder, the pause menu and the frames it sends, and no second device joins. **A run two machines start together cannot load at its start** (a load takes each its own time; they would begin on different ticks and part), which is why step 4 loads first.

## How a run goes

1. **Before the run** each side holds its session and calls `pump()` every physics step. The client pings; the host answers.
2. **`NetHost.start(start, starter)`** joins a virtual device on seat 1 through the input layer (so the frames service seats it and the recording knows), makes the session that seat's source, starts the run recorded (`Frames.record`) and sends its header.
3. **The client takes the header** only if it is of this build and this content and seats this machine; anything else closes the link (`problem`). It works out its input delay `D` (given, or the measured round trip in ticks, the cushion and one) and starts the live replay (`Frames.play_live`). From here the frames service drives both sessions; neither has a `_process` or a thread.
4. **Every tick on the host:** the frames service asks the session for seat 1's frame. The session reads the link and uses up every client frame that is for this tick or an earlier one: the walk, aim and held buttons are the newest's; the presses and commands are all of theirs. **With none arrived, the last frame stands in without its presses and commands**, and the late frame's come with the next tick. The host never waits. After the tick, `after_tick()` sends it.
5. **Every physics step on the client:** `pump` adds the ticks that arrived to the replay, `send` sends the seat's frame for the host's tick `tick + D`, and the frames service runs the ticks the feed paces (none while none is there, up to three to catch up).
6. **The checks:** after every tick both sides hash one part of the state (`SimHash.slice`, part `tick % 60`); every 60 ticks the client sends its hashes and the host compares them with its own of that tick. Where they differ, the host keeps the tick and the areas (`parted_tick`, `parted_areas`) and tells the client, which keeps them too. A session writes no file and logs nothing: whoever holds it (S4) shows the parting and saves each side's `replay` for the tools of `core/sim` (the desync report, `tools/platform_hashes.py`). The spike does not make the machines agree again.
7. **A link that closes:** the client gone, seat 1's frames are empty and the host plays on. The host gone, the client's replay is closed and ends once played out.

Whoever holds a session calls **`after_tick()` after every tick has stepped** (the tests' harness does; in the game `NetPlay`, on the Tick's `ticked`).

## Contract

- **Untrusted bytes.** Every message is decoded strictly before anything is used: the envelope by `NetMessage` (the kind, the length, the kind's own limit, names as plain text, nothing left over), a header and a tick by `Replay`'s decoder, a frame by `InputFrame`'s. No `bytes_to_var`, and no code, resource, path or URL ever comes from the wire. A frame's commands are `InputFrame.COMMAND_NAMES`, as a replay's are.
- **Each side takes only the other's kinds.** The host takes FRAME, HASHES and PING; the client HEADER (once), TICK (in order), PARTED and PONG. Anything else, or anything malformed, closes the link, and the session says why (`problem`).
- **Refused is final.** Once a session closed the link for a reason, it reads nothing more from it and uses nothing of it that still waited (the host drops the client's queued frames and commands).
- **Limits.** The host reads at most 64 messages a tick; holds at most 600 client frames, each for a tick no earlier than the one before it and no more than 600 ahead; holds at most 64 commands that wait for a tick's frame with room; writes no tick's frame past a frame's own limits (16 commands, 16 kB: the rest wait a tick); and takes one check per window, in order, of a tick it has played. A check names at most 2,048 areas. The client reads at most 600 messages a step. A loopback end with 8,192 unread messages closes.
- **A link is handed over open,** and carries a whole message of any size up to `NetMessage.MAX_BYTES` (a link whose wire takes less splits and joins it itself: `NetRtcLink`, 16 kB a packet).
- **A pasted code is untrusted text.** `NetCode.read` checks its length, prefix and alphabet, the form of every line it unpacks to, that the description holds the lines a data channel's always does, and each candidate's whole grammar (its address an IP address written out or a browser's `.local` name: nothing a code says is looked up) before WebRTC is handed any of it; a refused code changes nothing and keeps nothing. A handshake takes only the kind of code its side expects (the host an answer, the joining machine an offer). What passes all that may still be refused by WebRTC itself (which logs it): the handshake then fails.
- **Whom a machine talks to:** the STUN server named in `NetRtc.STUN` (it sees the machine's address, nothing of the game) and the machine whose code was pasted. Nothing listens for strangers, and nothing is made before Host or Join.
- **The WebRTC link's limits:** a packet that is text, empty, too long or marked otherwise, a message past `NetMessage.MAX_BYTES`, 8,192 unread messages or 8 MB of them, or 4 MB waiting to leave close it; a poll takes at most 1,024 packets.
- **A code always holds a candidate:** it is made one poll after the gathering is seen done (the last candidates are handed over by then), and a machine with none after four seconds fails instead of showing a code that reaches nobody. Only the host, once given the answer, runs out of time (thirty seconds); the joining machine waits as long as its player.
- **Files:** only `NetLog` writes one (`user://net/host.log`, `client.log`, the paths written out). A parted run is saved by the frames service (`Frames.save_run`, under `user://replays/`), asked by `NetPlay` with a name of its own, never one from the wire.
- **A source never seats.** A JOIN or LEAVE in a client's frame is done by the host session through the input layer (`core/sim/frame_source.gd`).
- **Sessions read the link only when called:** the host when its seat's frame is built, the client at each physics step's start, and both by `pump()` before the run.
- **The clock is given.** The conditioner and the client's ping run on a clock handed to them (a test's steps; the engine's in the game). Nothing here is simulation state, and the simulation reads nothing here.

## Tests

`tests/net/`: the messages and their decoder with a fuzz (`test_net_message.gd`), the loopback and the conditioner (`test_net_link.gd`), each session against a hand-written peer, its refusals by their reason and the host's limits by a flood (`test_net_host.gd`, `test_net_client.gd`), and two scripted fights linked by the sessions over a conditioned loopback (`test_net_session.gd`, on `net_pair.gd`): the same state at every tick at round trips of 0 to 200 ms with jitter and loss, the host on time whatever the link does, a stall caught up, a disturbed world caught by the checks, the client's presses in the host's recording and its command applied once on each machine at the same tick, the received replay played offline. `tests/benchmark/net_grid.gd` prints the counters for the grid of round trips and losses.

S4's: the codes with a fuzz (`test_net_code.gd`); the real link, two WebRTC peers in the test process with no STUN server, and two scripted fights through it (`test_net_rtc.gd`; needs the extension, `ci/build/webrtc.sh`); Host and Join, two machines with a stand-in handshake (`test_net_play.gd`, `loop_handshake.gd`). **The real game twice:** `tools/online_pair.sh` starts two game processes that go through Host and Join over WebRTC and play a sandbox (`online_runner.gd`, on the main menu's `--online`), and passes when every hash check agreed.

## Milestones

- **Netcode spike S2** (2026-11-10): the messages, both sessions, the loopback, the conditioner, the checks and the counters.
- **Netcode spike S4** (2026-11-10): the codes, the handshake, the WebRTC link, Host and Join (`NetPlay`), the counters' line and log.
- **Open:** S5 (the measurements; `D` measured again once the run plays).
