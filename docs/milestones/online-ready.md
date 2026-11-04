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
| A10 | `core/settings/shot_cap.gd` (6,000 on desktop, 1,000 on the web) and any other setting the simulation reads | A per-machine setting that changes the game, not only the look | Two machines with different caps simulate different games |

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

## How it stays easy to develop (the architecture)

The danger is that determinism breaks silently: a forgotten field or a read of real time crashes nothing, it shows weeks later as a desync nobody can trace. The simulation is about 60 scripts with some 800 members (the projectile manager alone 252), so anything kept by hand rots. The rules (the owner, 2026-11-04: "It should NOT become increasingly difficult to develop the game"):

1. **State is everything not declared otherwise; nobody writes hash or save code.** Every member of a simulation script is state unless the script lists it in `DERIVED` (caches, references to nodes and services, anything rebuilt from state). Hashing, saving and loading walk the state generically (N1, N10). Forgetting to list a cache is safe: it is only hashed and saved needlessly; if it holds something that cannot be saved (a node) or that parts between runs, a test names it. Most new members (a timer, a counter) cost nothing at all.
2. **One input path.** Devices, bots, replays and, later, the network all produce `InputFrame`s; the game never knows which. Gameplay code never touches netcode, and online play runs the same path every test, bot and replay runs daily (N2).
3. **Game logic gets time and chance from one place, without new plumbing.** `step(delta)` keeps its signature (the delta is always the tick's `DT`), and the tick and chance come from a `sim` service, found and swapped in tests like `combat`, `spells` and `projectiles` today. Chance is a hash of (run seed, purpose, key, tick, counter), not one shared generator, so a new roll in one system never shifts another's. The tick runs areas in a written order; whatever is iterated goes in id order, never by tree or signal-connection order (N3).
4. **The simulation/view line is a folder, enforced by a test.** Feel, looks, HUD and the camera stay free (real time, particles, anything) as long as they only read the game. Simulation folders get the rules automatically (N9). Most daily work, content and visuals, pays nothing: cards and enemies are data, and data cannot desync.
5. **Desyncs are cheap to find.** Per-area hashes, the first tick that parts, and a diff of the two snapshots down to the member's name (N1). Bug reports carry a replay, which makes ordinary bug fixing easier than today: the payback for the whole phase.
6. **New content is covered by itself.** A test finds every card, enemy and room, replays a short fight with each twice and through a snapshot (N12), as `test_card_rules.gd` plays every card on every carrier.
7. **What is not done.** No rewrite of the areas into another architecture (such as an entity-component system), no fixed-point maths (floats stay; only trig goes through `DMath`, N7), no native kernel the benchmark does not ask for (each is code written twice), and every rule a test with a fix-it message rather than a line in a README, since every session starts cold.

For whoever writes gameplay code, the new costs are: list a new cache or node reference in `DERIVED` (a test says when), and take chance from `sim` rather than a `RandomNumberGenerator`. The costs, part by part, are in "What it costs".

## What it costs (performance and maintenance, reviewed 2026-11-04)

The owner asked: will it cost performance, and will the code be worse off or harder to maintain? The honest answer, part by part. Where a cost is uncertain, it is measured before the part merges (done-when 9 and 10), and the part is changed or dropped if it does not hold.

| Part | Frame time in a normal build | Code and maintenance |
|---|---|---|
| N1 hash, desync report | **None:** hashing never runs in a normal build's tick (tests, replays and later the netcode only, then once a second). Packed arrays are hashed by the engine's `hash()` in one call, not element by element | `DERIVED` lists on caches; the walker and the report are new code in `core/sim/`, used only by tests and tools |
| N2 input frames, replays | **None** worth measuring (a few bytes a seat a tick). Aim quantised to 1/65,536 of a turn, invisible | **Simpler:** `player.gd` stops reading devices, so bots fill frames instead of faking devices. The HUD is unchanged: the bus holds `*_requested` events to the next tick by itself |
| N2b first look | None | A script and a written result |
| N3 one clock | **Likely a gain:** one tick calling steps replaces several engine callbacks (`_process`, `_physics_process` per area), and GDScript calls are what actors already pay most for | **Better:** one written order instead of an order implied by the scene tree. One-time churn: every seeded outcome changes once when chance moves to hashes (combo test numbers, the clips' `hashes.json`), redone in the same PR |
| N4 hit-stop in ticks | None | **Simpler:** no `Engine.time_scale` games, and no real-time clock in Feel's stop |
| N5 actor ids | None (int keys either way) | Neutral |
| N6 own body movement | **Uncertain:** Godot's slide is C++; ours is GDScript for up to 200 actors (circles against a grid, a few cells each). Godot's physics bodies and broadphase for actors also go away. Measured on the stress run; a kernel only if the numbers ask | **A real cost:** a collision rule we own and must keep right (corners, sliding along walls). Kept tiny: circles against the wall grid only, as the swarm already does. **Done only if N2b shows Godot's slide parts between platforms** |
| N7 DMath | **Small:** a polynomial in GDScript is slower than the engine's `sin`, but few sim calls are hot (two trig calls in `ShotKernel`, two in `SwarmKernel`, where C++ makes it as fast as the library). Measured | **A real cost:** `DMath.rotated(v, a)` reads worse than `v.rotated(a)`. **Only the functions N2b shows parting**, and N9's test asks for `DMath` only for those |
| N8 CI across platforms | None | CI time on the daily build only |
| N9 sim/view test | None | **Better:** the rules are a test with a fix-it message, not a README line |
| N10 snapshots | None at rest (taken only on a join, a test or a seek) | One `restore_nodes()` hook per area that makes nodes; the rest is the walker |
| N11 session settings | None | Neutral: the shot cap moves from a per-machine setting to a run's rules |
| N12 content coverage | None | Test time grows with content: a PR runs only the content it touches, the daily build runs all |

**In short:** in normal play the game should be no slower and maybe a little faster (N3); the two parts that could cost frame time (N6, N7) are measured and only built if N2b shows they are needed. The code gets simpler in four places (input, one clock, hit-stop, rules as tests), stays the same in most, and gets two lasting costs (a `DERIVED` list on caches; possibly `DMath` and our own slide). The one-time churn (seeded outcomes, the ~800 members reviewed once) lands early, in N1 and N3.

## Done when

1. Every part below is merged and `ci/build/build.sh --quick --tests` is green.
2. A recorded run (inputs only) replays to the same state hash at every tick: in the same process, at different render frame rates, and with hit-stop on.
3. The same replay gives the same hashes on Linux, Windows and the web build (N2b measures it first, N8 keeps it).
4. A snapshot taken at any tick and restored gives the same hashes from there on (N10).
5. Every setting the simulation reads is a session setting, and a replay carries it (N11).
6. A test fails when simulation code reads real time, `Engine.time_scale`, live input, the camera or the viewport, or uses an instance id as more than an equality key (N9).
7. A member that is not state but is missing from `DERIVED` is named by a test when it matters (it cannot be saved, or it parts between runs), and a member wrongly in `DERIVED` is named by N10's round trip.
8. Every card, enemy and room is replayed and round-tripped by itself, with no test written for it (N12).
9. The stress runs are no slower than before phase N (numbers in docs/DECISIONS.md), on desktop and on the web.
10. Hashing, snapshots and the desync report cost nothing in a normal build's tick (they are off).

## Parts

Each part is one PR, in this order: N1, N2, N2b, N3, then N4, N5, N6, N7 and N11 in parallel (N2b's result decides how much of N6 and N7 is needed), then N8, N9, N10, N12.

### N1: the state hash and the determinism harness

- **State by default.** In every simulation script (the simulation folders, listed in `core/sim/README.md` from N1 on; N9 enforces the line) every member is state, except those it lists in `const DERIVED: Array[StringName]`: caches, references to nodes and services, anything rebuilt from state. A state member is a value, a packed array, an array or dictionary of values, or an object of another simulation script, walked in turn (an actor's components, a brain, a caster's staffs).
- **`core/sim/state_walk.gd` (`StateWalk`):** the one generic walker (the script's own members by name: `get_script_property_list` and `get`), used by the hash here and by save and load in N10. Packed arrays in one engine call each; dictionaries in key order. It runs only in tests, tools, replays and later the netcode, never in a normal build's tick.
- **`core/sim/sim_hash.gd` (`SimHash`):** one 64-bit hash per area and one for the whole game, from `StateWalk`. Areas do not reach into each other: the tick (N3) hands `SimHash` its areas.
- **`tests/core/test_state_declared.gd`:** walks every simulation script's state and fails on a member it cannot save (a node or service not in `DERIVED`: "`gameplay/combat/combat.gd`: `_foo` holds a Node; add it to DERIVED, it is set up again, not saved") and on a `DERIVED` name that is no member (after a rename). The first PR lists today's caches and references; the ~800 members are reviewed once, area by area.
- **The desync report (`core/sim/desync.gd`):** given two runs, the first tick whose hashes part, which areas part, and each differing member by name with both values. Used by every determinism test, N2b and N8, and later the netcode.
- `tests/core/test_determinism.gd`: two runs of a scripted fight (bots, a horde wave, the sandbox storm) agree at every tick. A member that parts between two runs on one machine (a cache filled in a different order, a timing stat) is named by the desync report and goes into `DERIVED` or is fixed.
- The hash's cost is measured once on the stress run, for the netcode's once-a-second check later.

### N2: input frames and replays

- `core/sim/input_frame.gd` (`InputFrame`): one seat's input for one tick: move and aim quantised (move to a signed byte per axis, aim to a 16-bit angle or the "keep" value), held and pressed bits for the four staffs, and that tick's commands (the HUD's `*_requested` events, joins and leaves). `to_bytes` / `from_bytes` with a strict decoder (no `bytes_to_var` with objects).
- `PlayerController` builds its intent from its seat's `InputFrame` for that tick, never from `InputManager` directly. The local input layer (the mouse into a world aim, the press buffer, the stick deadzones) moves in front of the frame. Bots fill frames too.
- HUD commands apply at the start of the next tick, never in the middle of one: the bus holds the `*_requested` events the simulation listens to and sends them when the tick starts, so the HUD's code does not change.
- `core/sim/replay.gd`: records a run's seed, content version and frames to `user://replays/`, and plays it back. A bug report can attach one (a later intake task).
- Fixes A8.

### N2b: a first look across platforms

- A cheap measurement, before the costly parts: one recorded sandbox fight and one horde wave (N2), replayed headless on Linux, under Windows (Wine, or a Windows machine by hand) and in the web build (headless Chromium through Playwright), with N1's hash per area at every tick.
- No CI job yet (that is N8): a script under `tests/` and a written result in docs/DECISIONS.md: the first tick and area that part on each platform, or that none does.
- It decides N7's size (only the functions that differ get a `DMath` version) and tells whether N6 is needed now or is only a guard. If the platforms part somewhere ugly (inside the engine's own code), the owner hears it here, before N6 and N7 are spent.

### N3: one clock, one context

- `core/sim/tick.gd` (`Tick`, autoload): the tick counter and the only driver of the simulation. Each physics frame it runs one tick, in a written order: input frames, commands, Flow, Coop's rules, actors (by id), Spells, projectiles, Combat, the swarm. Nothing in the simulation has its own `_process` or `_physics_process`; each area's step is called by the tick.
- **No new parameter:** `step(delta)` keeps its signature everywhere; the delta is always `Tick.DT` (a test checks it). The tick number and chance come from the `sim` service (`core/sim/sim.gd`), set on areas and actors the way `combat`, `spells` and `projectiles` are, so tests swap it.
- **Chance by hash (`sim.chance(purpose, key, counter) -> float`, and `chance_int`, `chance_range`):** integer mixing of (run seed, purpose, key, tick, counter), a few integer operations, no allocation, as cheap as `RandomNumberGenerator.randf()`. No shared generator holds state, so a new roll in one system never shifts another's, and nothing about the random state needs saving. Spells' scatter, the brain and the AI move onto it; their `RandomNumberGenerator`s go. Feel and the looks keep their own generators (view).
- **Order by id:** what the simulation iterates (actors, targets, a dictionary's keys) it iterates by id; event listeners in the simulation never depend on connection order for an outcome (a listener that changes state does so through the tick's order, or the event names the one listener).
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

### N6: our own body movement (only if N2b asks for it)

Built only if N2b shows Godot's `move_and_slide` parting between platforms; otherwise it stays, and N8 keeps watching it.

- The actor's move against walls is our own circle-against-grid slide, on the wall grid the projectile manager already keeps (room walls and solid shots), the way the swarm moves onto its floor. `move_and_slide` and the bodies' physics shapes leave the simulation.
- Body-against-body pushing stays Combat's push.
- Native `ShotKernel`-style kernel only if the benchmark asks for one (bit-for-bit with the GDScript, as every kernel).
- Fixes A4. The highest-risk part for feel: walking along and into walls is compared in the sandbox and by the bots before it merges.

### N7: deterministic maths

- `core/sim/dmath.gd` (`DMath`): `sin`, `cos`, `atan2`, `from_angle`, `rotated`, `angle` from `+ - * / sqrt` only (polynomials, the same in GDScript and `native/`). Simulation code uses `DMath`; view code may keep the engine's.
- `native/SConstruct` builds with `-ffp-contract=off` and without fast-math on every platform (a protected file: the owner's change, listed in the PR).
- Fixes A6 and A7. Sized by N2b: if Godot's own builds already agree across the three platforms, `DMath` covers only what N2b finds, and N9's test asks for `DMath` only for those functions; the compile flags go in either way. The hot calls in `native/` use the same polynomial, so the kernels stay as fast.

### N8: the same game on every platform

- A CI job plays a set of replays (N2) headless on Linux, under Windows (a Windows runner, or Wine) and in the web build (headless Chromium through Playwright), and compares the hash at every tick. The first tick that differs is reported with each area's hash, so the cause is found quickly.
- Runs on the daily build. The workflow is under `ci/`/`.github/` (protected): the owner's change, drafted in the PR.
- Proves done-when 3.

### N9: the simulation/view line, checked

- Every script is either simulation or view, by folder (simulation: `core/sim`, `core/spells`, `core/projectiles`, `core/actors`, `gameplay/actor` except the looks, `gameplay/ai` except the looks, `gameplay/combat`, `gameplay/coop` rules, `gameplay/flow`, `gameplay/horde` except `swarm_look.gd`, `gameplay/player` controllers, `gameplay/progression`, `gameplay/rewards`, `gameplay/run`, `gameplay/difficulty`; view: `gameplay/feel`, every look, `hud/`, the camera). The list lives in `core/sim/README.md`.
- `tests/core/test_sim_rules.gd` reads every simulation script and fails on `Time.`, `Engine.time_scale`, `Input.`, `InputManager` outside the frame builder, `get_viewport`, `Camera2D`, `_process`, global `randf`/`randi`/`randomize`, and `get_instance_id` (other than in equality keys the test allows by name). AGENTS.md gets the rule ("Simulation code runs on the tick").
- Proves done-when 6. It also fails on `RandomNumberGenerator`, `_process` and `_physics_process` in simulation scripts (N3).

### N10: snapshots

- `core/sim/snapshot.gd` saves and loads the whole game through `StateWalk` (N1): no area writes its own save code. What a walker cannot do alone (making the actors' nodes again from their scene and id before their state is loaded, refilling a pool) is one `restore_nodes()` hook per area, as small as it can be; after loading, each area rebuilds its `DERIVED` members (`rebuild()`).
- Test: a snapshot at a random tick of each scripted fight, restored into a fresh world, continues with the same hashes. This is also what catches a member wrongly put in `DERIVED`: the restored world parts, and the desync report names it.
- Needed online for a player joining mid-run (pillar 2) and for rollback later; offline it can save a run mid-room (M5) and makes replays seekable.
- The largest part; it may split into N10a (actors, Combat, Flow) and N10b (Spells, projectiles, swarm).

### N11: settings that change the game are session settings

- Every setting the simulation reads (today the shot cap; whatever else N9's test finds, such as the mote or particle budgets if anything in the game reads them back) moves into one `SessionRules` resource, set when a run starts and recorded in the replay's header. Settings that only change the look stay per machine.
- Offline nothing changes for the player: a run takes the machine's defaults. Online (later) the host's session rules apply to everyone, capped at what the weakest machine allows.
- Test: a replay recorded with one cap replays to the same hashes on a machine whose own default is another.
- Fixes A10.

### N12: new content is covered by itself

- `tests/core/test_content_determinism.gd` finds every card, enemy, boss and room through the registry, as `test_card_rules.gd` finds every card and carrier: for each, a short scripted fight (bots with that card in a staff; that enemy in the arena; that room) runs twice and through a snapshot at a random tick, and must agree at every tick.
- A new card, enemy or room is covered the day it is added, with no test written for it.
- Test time: a PR runs the fights of the content it touches (by file); the daily build runs them all, in `tools/ptest.sh`'s parallel runs. A fight is a few game seconds headless.

## After phase N: the netcode (a sketch, not approved)

Its own phase and its own owner exception to hard rule 4, best after M7 (Steamworks):

- **Model:** host-ordered lockstep. Every machine sends its seats' input frames to the host (on Steam, through Steam's relay); the host fixes each tick's frames, with a short input delay (2–4 ticks), and sends them to all. A frame that arrives late is replaced by that seat's last one, so **a slow connection hurts only its own player and nobody waits** (pillar 2). Rollback on top is possible later, on N10's snapshots.
- **Desync check:** machines exchange N1's hash every second; on a mismatch the host sends a snapshot.
- **Joining:** the host sends a snapshot (N10), then frames.
- **Security:** only input frames, hashes and snapshots cross the wire, each with a strict decoder and size limits; nothing from the wire is ever code, a resource or a path. All networking lives in one owner-only folder (like `native/`), and hard rule 4 stays for everything else.
- **What it can and can't do (the limits, 2026-11-04):**
  - *Feel over distance.* A player's own input takes effect after the round trip to the host plus the input delay. Good under about 80 ms ping (the same country or region), sluggish above about 150 ms. To hide it, each machine draws its own staff moving at once, ahead of the agreed game (a view-only guess, corrected smoothly; the simulation stays exact). Full rollback would fix it, but re-running 6–8 ticks of 3,000 shots in one frame is likely too slow in GDScript; it is measured before it is promised.
  - *The slowest machine sets the pace.* Every machine runs the whole game, so a machine that cannot keep 60 ticks a second holds the others back or falls out. The session rules (N11) are capped at the weakest machine's; web clients likely play smaller rooms, or only with other web clients (an owner decision then).
  - *The same build.* Every machine must run the same build and content; the game refuses to join a session of another version. With a daily build, a session is "same nightly or same stable".
- **Transport:** Steam networking on desktop; WebRTC with a small signalling server for the web build (infrastructure the project does not have yet).
- **View:** each machine's camera follows its own seats; the HUD shows only local seats' builders.
