# Net

## Purpose

Two machines playing one run (the netcode spike, [docs/milestones/netcode-spike.md](../docs/milestones/netcode-spike.md)): host-ordered lockstep, built on the replay machinery of `core/sim`. The host records its run and sends every tick's input frames; the client plays them as a live replay and sends its own seat's frames. Only inputs cross the wire, and the simulation is the same on both machines.

**Nothing outside this folder knows a network exists.** The game sees input frames (`core/sim/frames.gd`), whatever made them: a device, a bot, a replay, or a session here. This folder knows `core/sim` and `core/input`, and nothing of gameplay or the HUD.

This is the one folder whose scripts may name networking classes (the owner's exception to hard rule 4, 2026-11-10, docs/DECISIONS.md; `NET_DIR` in `ci/smbot/rules.py`), and only a WebRTC peer and its data channel. It is Claude's and the owner's only. So far it makes no peer: the only link is the loopback, inside one process, and `NetWebRTC` only asks whether this build has WebRTC.

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
| `net_press_probe.gd` (`NetPressProbe`) | Times the client's presses from the step they were sent to the step they ran (a measure for S5; it changes nothing) |

The seams, each one-way: a session knows a `NetLink` (never what carries it), and reaches the game only through three things of `core/sim` and `core/input`: the frames service (`Frames.record`, `set_source`, `play_live`), the input layer's virtual device for the client's seat, and a `Callable` that hands it the game's areas for the checks. The frames service holds the host's `FrameSource` and the client's `LiveFeed` (small inner classes that call their session) and knows nothing of sessions.

The WebRTC link, the codes and Host/Join come in S4.

## How a run goes

1. **Before the run** each side holds its session and calls `pump()` every physics step. The client pings; the host answers.
2. **`NetHost.start(start, starter)`** joins a virtual device on seat 1 through the input layer (so the frames service seats it and the recording knows), makes the session that seat's source, starts the run recorded (`Frames.record`) and sends its header.
3. **The client takes the header** only if it is of this build and this content and seats this machine; anything else closes the link (`problem`). It works out its input delay `D` (given, or the measured round trip in ticks, the cushion and one) and starts the live replay (`Frames.play_live`). From here the frames service drives both sessions; neither has a `_process` or a thread.
4. **Every tick on the host:** the frames service asks the session for seat 1's frame. The session reads the link and uses up every client frame that is for this tick or an earlier one: the walk, aim and held buttons are the newest's; the presses and commands are all of theirs. **With none arrived, the last frame stands in without its presses and commands**, and the late frame's come with the next tick. The host never waits. After the tick, `after_tick()` sends it.
5. **Every physics step on the client:** `pump` adds the ticks that arrived to the replay, `send` sends the seat's frame for the host's tick `tick + D`, and the frames service runs the ticks the feed paces (none while none is there, up to three to catch up).
6. **The checks:** after every tick both sides hash one part of the state (`SimHash.slice`, part `tick % 60`); every 60 ticks the client sends its hashes and the host compares them with its own of that tick. Where they differ, the host keeps the tick and the areas (`parted_tick`, `parted_areas`) and tells the client, which keeps them too. A session writes no file and logs nothing: whoever holds it (S4) shows the parting and saves each side's `replay` for the tools of `core/sim` (the desync report, `tools/platform_hashes.py`). The spike does not make the machines agree again.
7. **A link that closes:** the client gone, seat 1's frames are empty and the host plays on. The host gone, the client's replay is closed and ends once played out.

Whoever holds a session calls **`after_tick()` after every tick has stepped** (the tests' harness does; S4 wires the game's Tick).

## Contract

- **Untrusted bytes.** Every message is decoded strictly before anything is used: the envelope by `NetMessage` (the kind, the length, the kind's own limit, names as plain text, nothing left over), a header and a tick by `Replay`'s decoder, a frame by `InputFrame`'s. No `bytes_to_var`, and no code, resource, path or URL ever comes from the wire. A frame's commands are `InputFrame.COMMAND_NAMES`, as a replay's are.
- **Each side takes only the other's kinds.** The host takes FRAME, HASHES and PING; the client HEADER (once), TICK (in order), PARTED and PONG. Anything else, or anything malformed, closes the link, and the session says why (`problem`).
- **Refused is final.** Once a session closed the link for a reason, it reads nothing more from it and uses nothing of it that still waited (the host drops the client's queued frames and commands).
- **Limits.** The host reads at most 64 messages a tick; holds at most 600 client frames, each for a tick no earlier than the one before it and no more than 600 ahead; holds at most 64 commands that wait for a tick's frame with room; writes no tick's frame past a frame's own limits (16 commands, 16 kB: the rest wait a tick); and takes one check per window, in order, of a tick it has played. A check names at most 2,048 areas. The client reads at most 600 messages a step. A loopback end with 8,192 unread messages closes.
- **A link is handed over open,** and carries a whole message of any size up to `NetMessage.MAX_BYTES` (a link whose wire takes less splits and joins it itself: S4).
- **A source never seats.** A JOIN or LEAVE in a client's frame is done by the host session through the input layer (`core/sim/frame_source.gd`).
- **Sessions read the link only when called:** the host when its seat's frame is built, the client at each physics step's start, and both by `pump()` before the run.
- **The clock is given.** The conditioner and the client's ping run on a clock handed to them (a test's steps; the engine's in the game). Nothing here is simulation state, and the simulation reads nothing here.

## Tests

`tests/net/`: the messages and their decoder with a fuzz (`test_net_message.gd`), the loopback and the conditioner (`test_net_link.gd`), each session against a hand-written peer, its refusals by their reason and the host's limits by a flood (`test_net_host.gd`, `test_net_client.gd`), and two scripted fights linked by the sessions over a conditioned loopback (`test_net_session.gd`, on `net_pair.gd`): the same state at every tick at round trips of 0 to 200 ms with jitter and loss, the host on time whatever the link does, a stall caught up, a disturbed world caught by the checks, the client's presses in the host's recording and its command applied once on each machine at the same tick, the received replay played offline. `tests/benchmark/net_grid.gd` prints the counters for the grid of round trips and losses.

## Milestones

- **Netcode spike S2** (2026-11-10): the messages, both sessions, the loopback, the conditioner, the checks and the counters.
- **Open:** S4 (the WebRTC link, the codes, Host/Join, the Tick's hook for `after_tick`, the host's HUD never capturing the client's seat), S5 (the measurements).
