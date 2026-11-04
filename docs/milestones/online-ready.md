# Online-ready: a deterministic simulation (phase N)

**Status (2026-11-04): draft, waiting for the owner's approval.** Asked by the owner on 2026-11-04: "Real online play is wanted. I hereby grant permission to change the design, such that it is possible to add. So I think we should follow your suggestion and tighten determinism." An exception to the milestone order like phases F–P ([ROADMAP.md](../ROADMAP.md)). The owner's decisions go in "Owner decisions"; what changes while building goes in docs/DECISIONS.md.

**This phase builds no netcode.** Networking stays banned by hard rule 4 until the netcode phase sketched at the end, which needs its own owner exception (like the native module's of 2026-11-02). Phase N makes the game *ready* for it, and pays off without it: replays, bug reports that replay exactly, and tests that never flake on frame time.

## Why

Spellmerge has up to about 3,000 shots, 200 actors and a 500+ horde swarm in a room. Sending that state every tick costs far too much bandwidth, so online co-op will send **inputs only**: every machine runs the same simulation from the same inputs (deterministic lockstep). That only works if the same inputs give the same game, to the bit, on every machine and platform (Linux, Windows, the web).

The code already goes a long way:

- every actor is driven by a controller that writes an `ActorIntent` (a move, an aim, two bit masks), and `PuppetController` already drives a body from another's intent;
- seats are kept apart from actor ids, and only HUD, input and co-op rules take seats;
- spell scatter, staff spread, dash and teleport seeds hash the actor id and cast count; the AI brain's RNG is seeded;
- actors step in a fixed order, and areas talk through synchronous `core/` events;
- the HUD already changes the game only through `*_requested` events (`card_move_requested`, `staff_change_requested`, `horde_pick_requested`, ...), which are commands;
- headless runs are frame-deterministic on one machine, the clip tests check two runs agree at every frame, and the native kernels match their GDScript byte for byte.

## What breaks determinism today (the audit, 2026-11-04)

| # | Where | What | Why it breaks |
|---|---|---|---|
| A1 | `gameplay/feel/feel.gd` (`_set_time_scale`, `_process`) | Hit-stop and the downed stop change `Engine.time_scale`, ended by `Time.get_ticks_usec()` | The physics step's `delta` then depends on real time: two machines simulate different steps |
| A2 | `gameplay/flow/flow.gd:273`, `gameplay/coop/coop.gd:101` (`step_revive`), `gameplay/horde/horde.gd:193` | Wave timers, restarts, intro, revive progress and horde breaks run in `_process` | They advance by render frame time, not by ticks (also the cause of the flaky `test_wave_balance.gd`, docs/BACKLOG.md) |
| A3 | `project.godot` `max_physics_steps_per_frame=3` | A slow frame drops simulation time | Fine on one machine; online, the tick count must be the clock, not real time |
| A4 | `gameplay/actor/actor.gd:199`, `gameplay/ai/entities.gd:245` | Bodies move with Godot's `move_and_slide` against `StaticBody2D` walls | Godot Physics is not guaranteed identical across platforms and builds, and its solver is outside our tests |
| A5 | `core/projectiles/projectile_manager.gd` (targets), `core/spells/spells.gd` and `carriers/beam.gd` (zap rolls), `carriers/carrier.gd`, `carriers/dash.gd` | `get_instance_id()` used as an identity | Instance ids differ between machines and runs; safe only while used for equality, never for order, hashing or a seed |
| A6 | Engine math (`sin`, `cos`, `atan2`, `Vector2.angle`, `rotated`, `from_angle`, `pow`, `exp`), about 80 calls in `core/` and `gameplay/` sim code | The engine calls the platform's maths library | glibc, MinGW/MSVC and Emscripten may round differently; `sqrt`, `+ - * /` are exact IEEE and safe |
| A7 | `native/` kernels | Built by GCC (Linux), MinGW (Windows), Emscripten (web) | Each must keep IEEE rounding (no fast-math, no fused multiply-add contraction) |
| A8 | `gameplay/player/player.gd` (`_aim`, `_mouse_world`) | The intent is built from live device state each step | Online, a seat's intent must come from a recorded input frame, quantised so what is sent is what is simulated |
| A9 | Pause (`get_tree().paused`), join and leave | Local-only rules | Online, pausing stops other machines and a joiner needs the current state |

Not a problem: render interpolation (the projectile manager drawing between steps, Feel's particles and motes, the camera, looks, Face's instance-id seed) is view only, as long as nothing in the simulation reads it back.

## Owner decisions

To answer before N1 starts:

1. **Where it goes in the order.** Proposal: right after the current owner-lane work, and before M3, so the run structure is born deterministic.
2. **Hit-stop online (N4).** Proposal: hit-stop stays a game-wide stop, but counted in ticks of the simulation, so every machine stops on the same tick. The alternative, a view-only freeze (the world keeps running under a frozen picture), feels worse.
3. **Pause online.** Rule 6 says the pause menu stops the game for everyone. Proposal (design change, below): offline it still does; online, the pause menu opens without stopping the game, like the builder.
4. **The tick rate.** Proposal: 60 ticks a second, fixed, as today.

## The design change

Made with the owner's permission of 2026-11-04, in docs/DESIGN.md:

- "1–4 co-op players (local co-op now, online co-op later)";
- a new section, **One game, the same everywhere:** the same inputs give the same game, to the bit, on every platform; all game logic runs on the simulation's tick, never on real time, live input, the camera or anything drawn; and nobody waits online either (a slow connection hurts only its own player).

Still to change once decision 3 is answered: rule 6's online variant (the pause menu).

## Done when

1. Every part below is merged and `ci/build/build.sh --quick --tests` is green.
2. A recorded run (inputs only) replays to the same state hash at every tick: in the same process, at different render frame rates, and with hit-stop on.
3. The same replay gives the same hashes on Linux, Windows and the web build (N8).
4. A snapshot taken at any tick and restored gives the same hashes from there on (N10).
5. A test fails when simulation code reads real time, `Engine.time_scale`, live input, the camera or the viewport, or uses an instance id as more than an equality key (N9).
6. The stress runs are no slower than before phase N (numbers in docs/DECISIONS.md).

## Parts

Each part is one PR, in order (N4–N7 can go in parallel once N3 is in).

### N1: the state hash and the determinism harness

- `core/sim/sim_hash.gd` (`SimHash`): folds the simulation's state into one 64-bit value: every actor's id, position, velocity, health, mana per staff, statuses and controller state; the projectile manager's packed arrays (alive slots only); Spells' clock, casters, cursors and waiting launches; the swarm's arrays; Combat's tables; Flow's and Coop's timers; and every simulation RNG's state. Floats are hashed by their bits.
- Each area that owns simulation state gets a `hash_into(h)` method; `SimHash` only calls them, so areas still do not reach into each other.
- `tests/core/test_determinism.gd`: two runs of a scripted fight (bots, a horde wave, the sandbox storm) agree at every tick. It runs per tick in tests only; in a build it is off, or every 60 ticks.
- Cost measured on the stress run (hashing 3,000 shots is a packed-array pass; native if needed).

### N2: input frames and replays

- `core/sim/input_frame.gd` (`InputFrame`): one seat's input for one tick: move and aim quantised (move to a signed byte per axis, aim to a 16-bit angle or the "keep" value), held and pressed bits for the four staffs, and that tick's commands (the HUD's `*_requested` events, joins and leaves). `to_bytes` / `from_bytes` with a strict decoder (no `bytes_to_var` with objects).
- `PlayerController` builds its intent from its seat's `InputFrame` for that tick, never from `InputManager` directly. The local input layer (the mouse into a world aim, the press buffer, the stick deadzones) moves in front of the frame. Bots fill frames too.
- HUD commands go through a `Commands` queue and apply on the next tick, never in the middle of one.
- `core/sim/replay.gd`: records a run's seed, content version and frames to `user://replays/`, and plays it back. A bug report can attach one (a later intake task).
- Fixes A8.

### N3: one clock

- `core/sim/tick.gd` (`Tick`, autoload): the tick counter and the only driver of the simulation. Each physics frame it runs one tick, in a fixed order: input frames, commands, Flow, Coop's rules, actors, Spells, projectiles, Combat, the swarm. Every simulation step takes the constant `Tick.DT`, never a `delta`.
- Flow's timers, Coop's revive and Horde's breaks move from `_process` to the tick. Coop's camera stays in `_process` (view).
- A slow frame runs up to `max_physics_steps_per_frame` ticks and never changes `DT`, as today; online, the netcode decides how many ticks to run.
- Fixes A2 and A3, and the flaky `test_wave_balance.gd` (docs/BACKLOG.md).

### N4: hit-stop in ticks

- Hit-stop and the downed stop become a number of ticks the simulation stands still (`Tick.hold(ticks)`), started by the simulation events that cause them; Feel only draws them. `Engine.time_scale` is no longer set by the game (the dev time-scale switch, if kept, scales the tick rate on one machine only, offline).
- Fixes A1. Feel's feel is checked side by side with today's in the sandbox before it merges.

### N5: identity without instance ids

- Targets, zap rolls and carrier hand-overs keyed by actor id (or the projectile slot), not `get_instance_id()`.
- Actor ids stay "lowest free first" (already deterministic).
- Fixes A5.

### N6: our own body movement

- The actor's move against walls is our own circle-against-grid slide, on the wall grid the projectile manager already keeps (room walls and solid shots), the way the swarm moves onto its floor. `move_and_slide` and the bodies' physics shapes leave the simulation.
- Body-against-body pushing stays Combat's push.
- Native `ShotKernel`-style kernel only if the benchmark asks for one (bit-for-bit with the GDScript, as every kernel).
- Fixes A4. The highest-risk part for feel: walking along and into walls is compared in the sandbox and by the bots before it merges.

### N7: deterministic maths

- `core/sim/dmath.gd` (`DMath`): `sin`, `cos`, `atan2`, `from_angle`, `rotated`, `angle` from `+ - * / sqrt` only (polynomials, the same in GDScript and `native/`). Simulation code uses `DMath`; view code may keep the engine's.
- `native/SConstruct` builds with `-ffp-contract=off` and without fast-math on every platform (a protected file: the owner's change, listed in the PR).
- Fixes A6 and A7. Done after N8's first run says how much differs: if Godot's own builds already agree across the three platforms, `DMath` covers only what N8 finds.

### N8: the same game on every platform

- A CI job plays a set of replays (N2) headless on Linux, under Windows (a Windows runner, or Wine) and in the web build (headless Chromium through Playwright), and compares the hash at every tick. The first tick that differs is reported with each area's hash, so the cause is found quickly.
- Runs on the daily build. The workflow is under `ci/`/`.github/` (protected): the owner's change, drafted in the PR.
- Proves done-when 3.

### N9: the simulation/view line, checked

- Every script is either simulation or view, by folder (simulation: `core/sim`, `core/spells`, `core/projectiles`, `core/actors`, `gameplay/actor` except the looks, `gameplay/ai` except the looks, `gameplay/combat`, `gameplay/coop` rules, `gameplay/flow`, `gameplay/horde` except `swarm_look.gd`, `gameplay/player` controllers, `gameplay/progression`, `gameplay/rewards`, `gameplay/run`, `gameplay/difficulty`; view: `gameplay/feel`, every look, `hud/`, the camera). The list lives in `core/sim/README.md`.
- `tests/core/test_sim_rules.gd` reads every simulation script and fails on `Time.`, `Engine.time_scale`, `Input.`, `InputManager` outside the frame builder, `get_viewport`, `Camera2D`, `_process`, global `randf`/`randi`/`randomize`, and `get_instance_id` (other than in equality keys the test allows by name). AGENTS.md gets the rule ("Simulation code runs on the tick").
- Proves done-when 5.

### N10: snapshots

- Every simulation area gets `save_state(buffer)` and `load_state(buffer)` for its whole state, next to `hash_into`. `core/sim/snapshot.gd` writes and reads them in the tick order.
- Test: a snapshot at a random tick of each scripted fight, restored into a fresh world, continues with the same hashes.
- Needed online for a player joining mid-run (pillar 2) and for rollback later; offline it can save a run mid-room (M5) and makes replays seekable.
- The largest part; it may split into N10a (actors, Combat, Flow) and N10b (Spells, projectiles, swarm).

## After phase N: the netcode (a sketch, not approved)

Its own phase and its own owner exception to hard rule 4, best after M7 (Steamworks):

- **Model:** host-ordered lockstep. Every machine sends its seats' input frames to the host (on Steam, through Steam's relay); the host fixes each tick's frames, with a short input delay (2–4 ticks), and sends them to all. A frame that arrives late is replaced by that seat's last one, so **a slow connection hurts only its own player and nobody waits** (pillar 2). Rollback on top is possible later, on N10's snapshots.
- **Desync check:** machines exchange N1's hash every second; on a mismatch the host sends a snapshot.
- **Joining:** the host sends a snapshot (N10), then frames.
- **Security:** only input frames, hashes and snapshots cross the wire, each with a strict decoder and size limits; nothing from the wire is ever code, a resource or a path. All networking lives in one owner-only folder (like `native/`), and hard rule 4 stays for everything else.
- **Transport:** Steam networking on desktop; WebRTC with a small signalling server for the web build (infrastructure the project does not have yet).
- **View:** each machine's camera follows its own seats; the HUD shows only local seats' builders.
