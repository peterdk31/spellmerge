# Netcode spike: lockstep over WebRTC, browsers and desktops, measured

**Status (2026-11-10): approved by the owner** ("I agree"), with every decision below taken; the owner gave the go the same day ("Continue with the multiplayer plan"). **S1 built** (below); S2 next. Asked on 2026-11-09 after phase N (docs/milestones/online-ready.md) was done: "Shall I draft the spike plan for you to approve first?" "yes".

A spike, not the netcode: the smallest lockstep that lets two players, each in a browser or a desktop build, play a run together, measured before anything is promised. What it measures decides the netcode phase (sketched in online-ready.md, "After phase N"): its signalling, its input delay, and whether it needs rollback.

## The questions it answers

1. **Input delay:** how long from the remote player's press to their staff acting, at round trips of 0, 50, 100, 150 and 200 ms? Up to what ping is that playable?
2. **Agreement:** do two machines agree at every hash check through ten-minute runs, storms included: two browsers, a desktop and a browser, a Linux and a Windows desktop?
3. **Nobody waits:** does a slow or lossy link hurt only the player on it (pillar 2)? How often is a late frame stood in for, and how fast does a client that fell behind catch up?
4. **The slowest machine:** does the browser, the slowest platform, keep 60 ticks a second in a storm, as host and as client, and what happens when it does not?
5. **Cost:** bytes a second each way, and the time each machine spends on the network and the hash checks per tick.

## Not in the spike

Left for the netcode phase, which the measurements inform:

- a signalling server (the spike swaps codes by copy and paste) and a TURN relay (for the routers a STUN server cannot see through);
- joining a run already under way (a snapshot's bytes);
- more than one client, and more than one seat per machine;
- rollback, and the view-only guess of one's own staff;
- Steam, matchmaking, a lobby;
- what a pause does online (in the spike it stops both machines, as it stops a local co-op run);
- who may change the session's rules online (N11's open question; in the spike, either seat, as offline).

## How it works: a run recorded on the host, played live on the client

Host-ordered lockstep (decided 2026-11-09), built from the replay machinery phase N made and tested. A replay is a run's header (build, content, seed, rules, how it started, its seats) and every tick's input frames; that is exactly what a client needs.

- **Seats:** the host's machine plays seat 0, the client seat 1.
- **The host records its run** (`Frames.record`, as the replay tests do). Seat 1 is a virtual device whose frames come from the connection: a `FrameSource`, the same seam the bots and the replay tests' scripted players use. Each tick the frames service builds every seat's frame (seat 0 from the host's own device) and records it. The host sends the header once and every recorded tick's bytes as they are made. **The host never waits:** if seat 1's frame for this tick has not arrived, its source gives seat 1's last frame without its presses and commands (buttons held stay held; a command must not apply twice). The late frame's presses and commands come with the next frame used.
- **The client plays the replay as it arrives** (`Frames.play`), a live one: the header's seats join (seat 0 as a virtual device, as a replay's seats do; the client's own device joined as seat 1 first), the run starts by the header's start, seed and rules, and each tick takes the host's frames. **A tick that has not arrived yet** makes the game run no tick (the picture holds) instead of ending the replay. With more ticks buffered than its cushion, the client runs up to three a physics step to catch up.
- **The client's own input:** while the live replay plays, the frames service still builds seat 1's frame from the client's device, with its commands (the builder's staff changes, a pause), as each tick runs. It hands the frame to the client session, which sends it tagged for tick `t + D`, `t` being that tick. While no tick runs, a press waits for the next frame, as a stopped tick's does (`Frames.stood`), so none is lost.
- **Input delay `D`:** the host's own seat has none (its frame is built as its tick runs). The client's `D` covers the round trip and its cushion, about (RTT + cushion) / 16.7 ms, set at the start from a measured ping, or given (to measure fixed values). The client feels about its ping; the host feels nothing of it.
- **The same game:** the header names the build and the content hash, as a replay's does; the client refuses a header of another build or content. (`Frames.play` only warns on another build, which is right for a replay file but not online.) The published web and desktop builds of one day match.
- **Checks:** every 60 ticks the client sends its per-area hashes (`SimHash.areas`, N1) for that tick; the host compares them with its own. On a mismatch both log the tick and the areas that differ, and both save the run as a replay (`Replay.save`). Who differs, and in which member, is found offline with the tools phase N built (the replay played again on each platform, `tools/platform_hashes.py`; the desync report). The spike does not make the machines agree again: that is a snapshot from the host, the netcode phase.
- **A link that closes:** the client gone, seat 1's frames are empty from then on (its wizard stands) and the host plays on. The host gone, the client's run ends.
- **A browser host's tab:** a browser slows or stops a hidden tab's frames, and the host is the run's clock, so a host in a browser keeps its tab in view (both stall otherwise). A hidden client tab falls behind and catches up once shown. A desktop host has no such limit. The spike measures it; the netcode phase decides what to do about it.

## Connecting: WebRTC everywhere, codes by copy and paste, a public STUN server

**WebRTC** on every platform, through Godot's one API (`WebRTCPeerConnection`, a data channel):

- **In browsers** it is built in: the web export uses the browser's own, and it works from the https page the web build is published on (GitHub Pages).
- **In the desktop builds** it is the official WebRTC extension (godotengine/webrtc-native, MIT; owner, 2026-11-10: "We can include the WebRTC gd extension!"). It ships in the Linux and Windows builds only (decisions 7 and 8).

So one link serves a browser and a desktop, two desktops, or two browsers.

- **The codes:** before two machines can talk, each hands the other a description of how to reach it: its session description and its network candidates. With no signalling server, the players swap them by hand:
  1. The host presses Host and gets a code to copy.
  2. The client presses Join, pastes the host's code, and gets a code back.
  3. The host pastes that, and they connect.

  On one PC that is two windows or tabs; across machines the codes go by chat. A code is the description with every candidate in it (gathered before it is shown, so one code each way), packed as text.
- **STUN:** to reach each other across the internet, each side asks a public STUN server for its address as the internet sees it (owner, 2026-11-10: allowed). The server is one constant in `net/`, a public one (Google's). It sees each player's address when they press Host or Join, and nothing of the game. On one network no STUN is needed. Some routers hide a machine even from STUN; those need a TURN relay (a server), which is outside the spike, and S5 notes how often that happens.
- **The data channel:** one channel, ordered and reliable, since lockstep needs every tick's frames in order. A lost packet then holds back the ones behind it, as on TCP. The conditioner's loss runs show the cost; an unreliable channel with each message carrying the last few ticks is the netcode phase's fix if needed.

## Where the code goes

Nothing outside `net/` knows a network exists. `core/sim` learns one generic thing, a replay that is still arriving, and nothing of networks.

- **`core/sim` (S1):**
  - A replay can grow while it plays: ticks added from bytes, each checked by the replay's own strict decoder.
  - The tape it plays from says whether it is live and how many ticks it holds ahead.
  - The Tick asks the frames service how many ticks to run this physics step: 1 normally and for a replay file, 0 while a live replay waits, up to 3 to catch up.
  - A live replay is played with two callables from whoever plays it: one called at each physics step's start, before the ticks are counted (the client session reads its link there and adds the ticks that arrived), and one handed each frame the frames service builds for the seats whose devices are on this machine, instead of dropping them.

  A live replay is also what the netcode phase's join needs: restore the host's snapshot, then `Frames.seek` to its tick and play on (N10).
- **`core/input` (S4):** a device can join as a given seat (today it takes the first free one). The client's keyboard or pad must be seat 1 there too, or its builder and pause would act as seat 0's.
- **`net/` (S2, S4):** the only folder with networking classes, owner-only as `native/` is (decision 1). It holds:
  - the messages: the header, a tick, a client frame, a hash, ping and pong. Each is a kind byte and a length, read by a strict decoder with size limits on top of the replay's and `InputFrame`'s own decoders; `bytes_to_var` is never used;
  - the host session (the `FrameSource` for seat 1, sending the recorded ticks) and the client session (feeding the live replay, sending seat 1's frames);
  - the link: send bytes, read bytes, open or closed. There are two: an in-process loopback (the tests and the measured grid) and WebRTC (with its codes and STUN). A conditioner wraps any link (delay, jitter, loss, all seeded) and runs on the clock it is given: the test's steps, or real time in the game. A session reads its link only when the frames service calls it (the client at each physics step's start, the host when its seat-1 source is asked for a frame), so it has no `_process` of its own and no order to keep against the Tick;
  - the counters (ping, `D`, ticks run and waited, late frames, bytes, hash checks), logged to `user://` and shown for S5.
- **The WebRTC extension (S3):** in `addons/webrtc/`, owner-only. It is never committed: CI puts it in the desktop builds and the test runs (decision 7), and writes the `.gdextension` the engine loads, as `ci/build/native.sh` does for the native module. No script names it: Godot's `WebRTCPeerConnection` uses it where it is present.
- **The game's side (S4):** "Host" and "Join" on the main menu of every build, with a box for the codes and a button that copies one. They are sent as events (`core/events`) that `net/` hears; `net/` hands back the code and its counters by events, which the menu and one line of text in the HUD show. The HUD knows no network. When the two are linked, the run starts as a sandbox (its storms).

## Parts (each one PR, in order)

- **S1: a live replay** (`core/sim`; no network). Tests:
  - a replay fed tick by tick, held back at times, makes the game run no tick while it waits and then agrees with the same replay played whole, at every tick;
  - ticks held back and then let go are caught up within the cushion;
  - a press made while no tick runs reaches the seat's next frame;
  - the local seat's frames are handed out while the replay plays;
  - a replay file still records, plays, seeks and ends as before (the replay and snapshot tests).

  **Built (2026-11-10), then reworked after a review the same day** (a second session, unanchored, on architecture and coupling; owner: "make sure we are following good software architecture and have low coupling"):
  - `Replay.header_bytes`, `tick_bytes`, `add_tick_bytes` (the file's decoder, per tick) and `seats_at`.
  - `LiveFeed` (`core/sim/live_feed.gd`): the one seam for whoever plays a live replay (`pump`, `send`, `local_seats`, the pacing `ticks_to_run` with the cushion and `CATCH_UP` 3 as its default), so S2's client session extends it and S5 tunes the pacing in `net/`, not in `core/sim`. The tape keeps only the feed and `closed`, and never runs more ticks than it holds.
  - `Frames.play_live(replay, feed)`, `close_live`, `is_live`, `begin_step` (the Tick calls it once a step; the pump, the local frames, the count), `hears_commands(seat)`.
  - **Changed from the plan above:** a local seat's frame is built and sent **once a physics step**, also while the replay waits, not as each tick runs. Built per tick, a client stalled by the link sent nothing for the stall and then several frames of one moment at once, so the host stood in its last frame (a released button held) for the whole stall. Which host tick a frame is for (`t + D`) is the client session's, S2.
  - **Seats are the simulation's:** a replay's seats come from its frames, and the frames service alone sends `seat_joined`/`seat_left` (Coop heard `device_joined` before: a pad plugged in on the client, or the client's seat leaving and joining again, would have parted the run; a replay file had the same latent bug).
  - The Tick runs `begin_step` ticks a physics step, called also under the picture's pause; the pause menu sends `pause_requested` online.
  - Tests: `tests/core/test_live_replay.gd` (waits, the default pace 3-3-3-1, a feed asking too much, the fed frames and commands, a frame sent every step with its commands and a press made while waiting, the seats the replay's and not the devices', a file replay too, the end once closed, refusals, a stop from inside the feed), `tests/core/test_live_replay_game.gd` (a scripted sandbox run with its storm, rebuild and pause, played whole and live with jitter, a late start and stalls, its own player's seat this machine's and driven otherwise: the same hashes after every step, waits included; no step ran a tick not there or more than three), `test_coop.gd` (a device joining during a replay adds no wizard), the Tick's ticks a step in `test_tick.gd`, the tick bytes in `test_replay.gd`. Each new test was checked against its fix broken.
  - Left for later, from the review: the engine's own catch-up (3 physics steps a frame) times the pace's (3 ticks) lets a slow client run 9 ticks in a frame; S5 measures it and the feed's `ticks_to_run` is where to change it. A run's seed after `Frames.seek` (the join): the tape deals the next run's seed from the replay's seed in turn and a seek does not move the dealer, so a client that joins in the host's third run would deal the wrong seed at the next restart. The join is the netcode phase's (below); it needs the run's count in the snapshot.
- **S2: `net/` over the loopback** (and the rule's exception, decision 1). The messages, both sessions, the loopback and the conditioner. Tests run two scripted fights (N12's `ContentFight`, each with its own frames service) linked by the loopback on a stepped clock, and check:
  - the client agrees with the host at every tick, at 0 to 200 ms of delay with jitter and 5% loss;
  - the host runs every tick on time whatever the link does;
  - a late frame stands in as the seat's last, and its press comes with the next;
  - the client refuses another build's or content's header;
  - a disturbed world (a test changes one) is caught at the next hash check, with its areas;
  - the replay the client received, played offline, agrees with the host's run;
  - every decoder refuses truncated, oversized and unknown messages (random bytes as a fuzz).

  The same harness, as a benchmark beside the tests, prints the counters for the grid of round trips and losses (S5's first numbers).
- **S3: the WebRTC extension in the desktop builds** (`ci/`, `addons/`, `export_presets.cfg`; drafted by Claude for the owner, as `native/` was). CI puts the pinned extension in the Linux and Windows builds and the test runs, and writes its `.gdextension`. `tools/check.sh` and the merge script accept it there and nowhere else. The checks:
  - the web build still exports without it, using the browser's WebRTC;
  - a test fails if the desktop test runs lack it (as `SPELLMERGE_NATIVE=required` does for the native module);
  - the platform runs (N8) load it on Windows.
- **S4: WebRTC, Host/Join and the counters**, and a device joining as a given seat (`core/input`, with its test). With the extension in the test runs, a test links two peers in one process over WebRTC on the machine (no STUN) and plays two scripted fights through it, so the real link is tested in CI too. Each pasted code is checked strictly before it reaches WebRTC (its size, its form). Copying and pasting a code in the browser is checked first; if pasting into the game fails there, the code box is a plain web text field the game reads.
- **S5: the measurements and the write-up.**
  - The grid from S2's benchmark.
  - Then the owner's: two windows on one PC; a desktop and a browser, two browsers and two desktops on the LAN; two machines across the internet (STUN); ten-minute runs with storms, and a browser host's tab hidden for a while.
  - The numbers go into this doc, with the answers to the five questions and a recommendation for the netcode phase: signalling, a TURN relay, `D`, a reliable or unreliable channel, whether rollback is worth its cost, and the join.

## Measurements (S5), and what they decide

| What | How | Decides |
|---|---|---|
| The client's press to its staff acting | The client logs each press's tick and the tick it ran; the grid at 0 to 200 ms | Playable ping; whether the staff guess or rollback is needed |
| Hash checks agreeing | Ten-minute runs: browser and browser, desktop and browser, Linux and Windows | Whether lockstep holds between real machines and platforms (N8 says it does offline) |
| Late frames, waits, catch-up | The counters, the conditioner's jitter and loss, a hidden tab | `D`, the cushion, a reliable or unreliable channel, what to do about hidden tabs |
| Ticks a second in a storm, in the browser | A browser as host and as client in the sandbox storm | Whether online web plays big rooms, hosts, or slows the session (owner, 2026-11-06: slowing is allowed) |
| Linking across the internet | The owner's tries with STUN | Whether the netcode phase needs a TURN relay or a signalling server |
| Bytes a second, network and hash time per tick | The counters | Expected small (frames are about 9 bytes, 60 a second); confirms it |

## Security (the exceptions to hard rule 4, and what stays)

- **Where:** networking classes only in `net/`, which only the owner and Claude change. Hard rule 4 stays for every other folder, so a contributor's PR can add no network call anywhere.
- **The extension:** the one native library besides the native module, and the only one from outside the project. It is pinned to one version, checked by its hash, and never committed (decision 7). Unlike the native module, it parses what comes over the network (DTLS, SCTP, STUN, by libdatachannel and mbedTLS), so it is a library to update when it has a security release. `docs/SECURITY-CHECKLIST.md` says so.
- **Whom it talks to:** the other player, whose code was pasted, and the one public STUN server named in `net/` (which sees the player's address, nothing of the game). Nothing listens for strangers: a WebRTC link is made only with the code a player pasted.
- **What crosses the wire:** only the header, input frames, ticks, hashes and pings. Each is decoded strictly with a size limit; an unknown kind or a malformed message closes the link. A pasted code is untrusted text: checked for its size and form before WebRTC is handed it.
- **Limits:** the host takes one client and reads at most a set number of messages from it a frame. No code, resource, path, URL or `Variant` object comes from the wire. A frame's commands are `InputFrame.COMMAND_NAMES`, decoded as a replay's are.
- **When:** nothing connects anywhere until a player presses Host or Join. A desktop build may then be asked by Windows' firewall to let it through.

## Risks

- **The browser may not keep up:** a browser runs the whole game, and a client behind in a storm runs extra ticks to catch up. That is question 4; it may keep online web play to smaller rooms, a slower session, or desktop hosts.
- **Hidden tabs:** a browser host whose tab is hidden stalls both players. The spike measures it; the fix (a warning, a desktop host, or handing the clock over) is the netcode phase's.
- **The extension and Godot 4.7:** the extension's release is built for Godot 4's extension interface and should load in 4.7. S3 checks it on Linux and Windows before anything else is built on it; if it does not load, S3 builds it from source (decision 7's other way).
- **Codes by hand are clunky** across machines. They are enough to measure; the netcode phase decides on a signalling server.
- **S1 touches the frames service and the Tick**, which every run goes through. Its change is small, and the existing replay, snapshot and determinism tests check it.

## Owner decisions (2026-11-10)

1. **The exception to hard rule 4:** networking classes allowed in a new folder `net/` (the owner's and Claude's only), nowhere else. Owner: "Ill allow it!" I draft the change to `ci/smbot/rules.py`, `AGENTS.md` (rule 4 and the protected paths) and `docs/SECURITY-CHECKLIST.md` in S2's PR, for the owner to approve, as with `native/` on 2026-11-02.
2. **Transport: WebRTC.** The owner asked whether WebRTC would let two browsers play, e.g. in the sandbox; told of the codes swapped by hand, the STUN server, the desktop builds and the host's tab, the owner chose it ("A"), then allowed the WebRTC extension for the desktop builds: "We can include the WebRTC gd extension!" (WebSocket, the first proposal, would have needed a desktop host and a web build served from the LAN.)
3. **A public STUN server**, so two players can link across the internet: "yes it can use a public STUN server".
4. **Machines:** "Fine": one PC first, then two machines on the LAN, then across the internet.
5. **Host/Join in every build** (owner: "if Host/Join can work in all build, that will be great and I can easier test it"): the published web and desktop builds.
6. **Scope:** S1 to S5 as above, with everything in "Not in the spike" left for the netcode phase. Owner: "Fine I guess".
7. **How the extension gets into the builds: (a), decided by the owner ("I agree").**
   - (a) The official release (godotengine/webrtc-native 1.2.2, 2026-09-30), pinned by version and SHA-256, fetched by CI as it fetches its pinned tools. Fast and simple; it trusts the binaries the Godot project builds.
   - (b) Built from source in CI at a pinned commit, as the native module is. Upstream builds Windows with MinGW on Ubuntu, as our CI does, so it is possible, but it builds libdatachannel and mbedTLS: much longer builds and more CI to keep.

   *Recommended: (a) for the spike*; (b) if the netcode phase keeps WebRTC and the owner wants every native library built from source.
8. **Its licenses: allowed, decided by the owner ("I agree").** The extension is MIT. It bundles libdatachannel and libjuice (MPL-2.0), usrsctp (BSD-3-Clause) and mbedTLS (Apache-2.0). MPL-2.0 can be shipped in a GPL-3.0 game, but it is not on hard rule 5's list (which covers the repository's files; these are only in the builds). *Recommended:* allow it. The desktop builds then ship a notices file naming the extension, its libraries, their licenses and where their source is (MPL-2.0 asks for that). Rule 5 says that a library shipped in the builds, never in the repository, is listed there. PLAN.md already allows third-party addons the owner adds ("Supply chain").
