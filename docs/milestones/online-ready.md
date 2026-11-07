# Online-ready: a deterministic simulation (phase N)

**Status (2026-11-04): approved by the owner** ("Go with your proposals on all four decisions"). The tasks are in the owner lane of [NEXT.md](../NEXT.md), after the lane's current work; phase N does not hold up D3 and C2, and ends before M3 starts. Asked by the owner on 2026-11-04: "Real online play is wanted. I hereby grant permission to change the design, such that it is possible to add. So I think we should follow your suggestion and tighten determinism." An exception to the milestone order like phases F–P ([ROADMAP.md](../ROADMAP.md)). The owner's decisions go in "Owner decisions"; what changes while building goes in docs/DECISIONS.md.

**This phase builds no netcode.** Networking stays banned by hard rule 4 until the netcode phase sketched at the end, which needs its own owner exception (like the native module's of 2026-11-02). The owner will give it (2026-11-06: "netcode can easily be allowed"): the rule and its check change when netcode work starts. Phase N makes the game *ready* for it, and pays off without it: replays, bug reports that replay exactly, and tests that never flake on frame time.

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
| A11 | `gameplay/horde/horde.gd` (`rng`: spawns and offers), `gameplay/horde/swarm.gd` (`rng`: each row's seed) | `RandomNumberGenerator.new()`, seeded only by tests | In a real run each starts from a random seed: two runs of the same inputs spawn different hordes (found in the second check, 2026-11-04) |
| A12 | `gameplay/horde/horde.gd` (`_set_paused`), `hud/menus/pause/pause_menu.gd` | The level-up break and the pause menu pause the scene tree | The tree's pause is not part of the simulation's state: a replay or a snapshot cannot say the game was standing still |
| A13 | `core/projectiles/projectile_manager.gd` (`_process`, `update_draw`, the sparks' `_spark_rng`) | Drawing code lives in a simulation script | Fine while it only reads the arrays, but N9's test must tell it apart, and nothing may let it write state |
| A10 | `core/settings/shot_cap.gd` (6,000 on desktop, 1,000 on the web) and any other setting the simulation reads | A per-machine setting that changes the game, not only the look | Two machines with different caps simulate different games |

Not a problem: render interpolation (the projectile manager drawing between steps, Feel's particles and motes, the camera, looks, Face's instance-id seed) is view only, as long as nothing in the simulation reads it back.

## Owner decisions

Decided by the owner on 2026-11-04 ("Go with your proposals on all four decisions"):

1. **Where it goes in the order:** right after the owner lane's current work, and before M3, so the run structure is born deterministic. It runs beside D3 and C2 and does not hold them up.
2. **Hit-stop online (N4):** hit-stop stays a game-wide stop, counted in ticks of the simulation, so every machine stops on the same tick (not a view-only freeze).
3. **Pause online:** offline the pause menu still stops the game for everyone; online it opens without stopping the game, like the builder (design rule 6, below).
4. **The tick rate:** 60 ticks a second, fixed, as today. **Amended by the owner on 2026-11-06:** "Slowing the game is an option if we have to!" Online, a session may run the game slower when a machine cannot keep up (fewer ticks a second, or the game's speed lowered), as a last resort after the session rules (N11).

## The design change

Made with the owner's permission of 2026-11-04, in docs/DESIGN.md:

- "1–4 co-op players (local co-op now, online co-op later)";
- a new section, **One game, the same everywhere:** the same inputs give the same game, to the bit, on every platform; all game logic runs on the simulation's tick, never on real time, live input, the camera or anything drawn; and nobody waits online either (a slow connection hurts only its own player).

- and, with decision 3, rule 6's online variant: online the pause menu stops nothing.

## How it stays easy to develop (the architecture)

The danger is that determinism breaks silently: a forgotten field or a read of real time crashes nothing, it shows weeks later as a desync nobody can trace. The simulation is about 60 scripts with some 800 members (the projectile manager alone 252), so anything kept by hand rots. The rules (the owner, 2026-11-04: "It should NOT become increasingly difficult to develop the game"):

1. **State is everything not declared otherwise; nobody writes hash or save code.** Every member of a simulation script is state unless the script lists it in `DERIVED` (caches, references to nodes and services, anything rebuilt from state). Hashing, saving and loading walk the state generically (N1, N10). Forgetting to list a cache is safe: it is only hashed and saved needlessly; if it holds something that cannot be saved (a node) or that parts between runs, a test names it. Most new members (a timer, a counter) cost nothing at all.
2. **One input path.** Devices, bots, replays and, later, the network all produce `InputFrame`s; the game never knows which. Gameplay code never touches netcode, and online play runs the same path every test, bot and replay runs daily (N2).
3. **Game logic gets time and chance from one place, without new plumbing.** `step(delta)` keeps its signature (the delta is always the tick's `DT`), and the tick and chance come from a `sim` service, found and swapped in tests like `combat`, `spells` and `projectiles` today. Chance is a hash of (run seed, purpose, key, tick, counter), not one shared generator, so a new roll in one system never shifts another's. The tick runs areas in a written order; whatever is iterated goes in id order, never by tree or signal-connection order (N3).
4. **The simulation/view line is a folder, enforced by a test.** Feel, looks, HUD and the camera stay free (real time, particles, anything) as long as they only read the game. Simulation folders get the rules automatically (N9). Most daily work, content and visuals, pays nothing: cards and enemies are data, and data cannot desync.
5. **Desyncs are cheap to find.** Per-area hashes, the first tick that parts, and a diff of the two snapshots down to the member's name (N1). Bug reports carry a replay, which makes ordinary bug fixing easier than today: the payback for the whole phase.
6. **New content is covered by itself.** A test finds every card, enemy and room, replays a short fight with each twice and through a snapshot (N12), as `test_card_rules.gd` plays every card on every carrier.
7. **What is not done.** No rewrite of the areas into another architecture (such as an entity-component system), no fixed-point maths (floats stay; only trig goes through `DMath`, N7), no native kernel beyond N6 and N7 that the benchmark does not ask for, and every rule a test with a fix-it message rather than a line in a README, since every session starts cold.

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
| N6 own body movement (C++) | **Likely a gain:** one native call moves every actor against the wall grid, and Godot's physics bodies and broadphase for actors go away. Measured on the stress run | **A real cost, kept small:** a collision rule we own (corners, sliding along walls), in C++ with a GDScript twin (about 150 lines) for the editor without the module. Circles against the wall grid only, as the swarm already does |
| N7 DMath (C++) | **None:** one native call per use costs about what the engine's own `sin` does, and inside the kernels it is a plain inline function | `DMath.rotated(v, a)` reads a little worse than `v.rotated(a)`, but the rule is simple: simulation code calls no engine trig at all. The GDScript twin is about 60 lines of polynomials |
| N8 CI across platforms | None | CI time on the daily build only |
| N9 sim/view test | None | **Better:** the rules are a test with a fix-it message, not a README line |
| N10 snapshots | None at rest (taken only on a join, a test or a seek) | One `restore_nodes()` hook per area that makes nodes; the rest is the walker |
| N11 session settings | None | Neutral: the shot cap moves from a per-machine setting to a run's rules |
| N12 content coverage | None | Test time grows with content: a PR runs only the content it touches, the daily build runs all |

**In short:** in normal play the game should be no slower and maybe a little faster (N3); N6 and N7 are C++ from the start (the owner, 2026-11-04), so they should cost nothing and N6 likely saves time. The code gets simpler in four places (input, one clock, hit-stop, rules as tests), stays the same in most, and gets two lasting costs (a `DERIVED` list on caches; `DMath` and our own slide, in C++ with small GDScript twins). The one-time churn (seeded outcomes, the ~800 members reviewed once) lands early, in N1 and N3.

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
11. With shot scale's threads (H5), the shot kernel gives the same bits with one thread and with many (rule T2 below).

## Parts

Each part is one PR, in this order: N1, N2, N2b, N3, then N4, N5, N6, N7 and N11 in parallel, then N8, N9, N10, N12. N6 and N7 do not wait for N2b's result.

### N1: the state hash and the determinism harness

- **State by default.** In every simulation script (the simulation folders, listed in `core/sim/README.md` from N1 on; N9 enforces the line) every member is state, except those it lists in `const DERIVED: Array[StringName]`: caches, references to nodes and services, anything rebuilt from state. References to other bodies that are state all the same go in `const REFS` and are hashed as who they point at (added in N1's review; the table in `core/sim/README.md`, "Steps", says which list a member takes). A state member is a value, a packed array, an array or dictionary of values, or an object of another simulation script, walked in turn (an actor's components, a brain, a caster's staffs).
- **`core/sim/state_walk.gd` (`StateWalk`):** the one generic walker (the script's own members by name: `get_script_property_list` and `get`), used by the hash here and by save and load in N10. It skips `DERIVED` and `VIEW` members (N9). Packed arrays in one engine call each; dictionaries in key order. It runs only in tests, tools, replays and later the netcode, never in a normal build's tick.
- **`core/sim/sim_hash.gd` (`SimHash`):** one 64-bit hash per area and one for the whole game, from `StateWalk`. Areas do not reach into each other: the tick (N3) hands `SimHash` its areas.
- **`tests/core/test_state_declared.gd`:** walks every simulation script's state and fails on a member it cannot save (a node or service not in `DERIVED`: "`gameplay/combat/combat.gd`: `_foo` holds a Node; add it to DERIVED, it is set up again, not saved") and on a `DERIVED` name that is no member (after a rename). The first PR lists today's caches and references; the ~800 members are reviewed once, area by area.
- **The desync report (`core/sim/desync.gd`):** given two runs, the first tick whose hashes part, which areas part, and each differing member by name with both values. Used by every determinism test, N2b and N8, and later the netcode.
- `tests/core/test_determinism.gd`: two runs of a scripted fight (bots, a horde wave, the sandbox storm) agree at every tick. A member that parts between two runs on one machine (a cache filled in a different order, a timing stat) is named by the desync report and goes into `DERIVED` or is fixed.
- The hash's cost is measured once on the stress run, for the netcode's once-a-second check later.

**Done (2026-11-05).** `core/sim/` (`StateWalk`, `SimHash`, `Desync`, `SimSeed`, README with the folders); `tests/core/test_state_walk.gd`, `test_state_declared.gd` (static over every simulation script and its inner classes, the source read for static members, clocks and global dice), `test_state_walked.gd` (live walks of the three scenes and of every card cast in the card rules' world), `test_determinism.gd` (a staffed fight, a spell storm and a horde wave on `tests/core/sim_scenes.gd`, each played twice and compared at every tick). What the first runs and the review found and how it was settled:

- **Instance ids parted at tick 0** in five members (`Actors._node`, `ProjectileManager._target_id`, `Combat._node_id` and `_row_by_node`, `AIBrain._target_id`), as the audit said (A5): DERIVED until N5.
- **`Spells._scatter` started on a random seed** (a new generator does), though every cast seeds it before it rolls: it now starts at 0, which changes no cast.
- **Three lists, not two.** DERIVED holds only what is set up again (services, caches, scratch, instance ids); references to other bodies that are state (the AI's `target`, `grudge` and `plan_target`, a decoy's target, `ProjectileManager._stuck_to`, Spells' due zaps and jumps, the beams', swings' and slams' sources, Combat's body per row, Entities' casters and enemies, Flow's and Coop's bodies, the swarm's rows and target slots, a pending launch's source, a dash's struck bodies) are **REFS**: hashed as who they point at (an actor's id, else what it is), never entered, so a different target parts the runs at the tick it was picked. They are the worklist of N5: each becomes an identity there. Looks and the manager's drawing members (written only from `update_draw`) are VIEW; the looks, the intro and the shader warm-up `VIEW_ONLY`. The rest of the ~1,100 members is state by default; the review area by area goes on as N2 to N10 touch them.
- **What the walker cannot see.** Static members (all caches or test switches today) are listed in DERIVED, and a test fails on one that is not. No simulation script reads a clock or rolls global dice; the horde director and the swarm seeded themselves with `randomize()` (the fixtures overrode it), and now take `SimSeed.fresh()`, the one seed nobody chose, which N11 makes the session's.
- **Every card walked.** The three scenes cast six cards; walking every card found `Entities.spells` (a service) missing from DERIVED, and the static pass over inner classes found `Solid.body` (DERIVED), `PendingLaunch.source` and `MovePass.struck` (REFS).
- **The hash's cost grows with the shot cap, not the live shots:** the projectile manager and the actor table hash in about 2 ms at the desktop cap (6,000) and 15 ms at 100,000 (the owner's machine, headless; 150 ms before a REFS array walked only its filled entries). Fine for the netcode's once a second. The desync report builds paths for its kept tick only (the determinism test took 101 s with a path per leaf every tick, 37 s now).
- **Left for later parts, as planned:** the hash's cost on the stress run itself (its real autoloads are handed to `SimHash` only once N3's tick names them: measured in N3), and determinism runs of the real game's flow, coop and player areas with bots and the sandbox storm (the scenes are the test worlds, stepped by hand: N2's replays bring the real game in).

### N2: input frames and replays

- `core/sim/input_frame.gd` (`InputFrame`): one seat's input for one tick: move and aim quantised (move to a signed byte per axis, aim to a 16-bit angle or the "keep" value), held and pressed bits for the four staffs, and that tick's commands (the HUD's `*_requested` events, joins and leaves). `to_bytes` / `from_bytes` with a strict decoder (no `bytes_to_var` with objects).
- `PlayerController` builds its intent from its seat's `InputFrame` for that tick, never from `InputManager` directly. The local input layer (the mouse into a world aim, the press buffer, the stick deadzones) moves in front of the frame. Bots fill frames too.
- HUD commands apply at the start of the next tick, never in the middle of one: the bus holds the `*_requested` events the simulation listens to and sends them when the tick starts, so the HUD's code does not change.
- `core/sim/replay.gd`: records a run's seed, content version and frames to `user://replays/`, and plays it back. A bug report can attach one (a later intake task).
- Fixes A8.
- From N1: the determinism runs move onto the real game (Flow, Coop, Player, bots, the sandbox storm) through replays; N1's scenes are test worlds stepped by hand.

**Done (2026-11-05).** `core/sim/input_frame.gd` (`InputFrame`, strict bytes), `core/sim/frames.gd` (the `Frames` autoload: each seat's frame at the tick's start, before every other physics step; commands applied; `record`, `play`), `core/sim/frame_source.gd` (`FrameSource`; bots fill frames), `core/input/local_input.gd` (`LocalInput`, the device layer in front of the frame), `core/sim/replay.gd` (`Replay`, `user://replays/`), `SimSeed.begin` (a replay's seeds); `PlayerController` reads only its frame; commands through `Events.listen` and `command_sink`. Tests: `test_input_frame.gd`, `test_frames.gd`, `test_replay.gd`, `test_replay_game.gd` (a scripted sandbox run with the storm and a mid-run rebuild, a wave of two bots, a horde run of a bot: recorded and replayed on the real game to the same hash at all 240 ticks). Decisions in docs/DECISIONS.md (2026-11-05). What the first runs found:

- **The press buffer stays in the simulation** (it ends when a cast leaves); the frame carries the fresh press.
- **Session residue:** the services' clocks run from the game's start and their counters carry from run to run, so a replay plays the same only from a fresh game, the same number of ticks after its start (the test makes the autoloads again before each run). **For N3:** start the one clock, and reset the run's counters, at the run's start.
- **A bot changes what it reads:** its threat and target queries fill the projectile manager's caches, which count as state and change the next step, so a bot's run replays with the bot watching again (a source set while a replay plays is asked and its frame dropped). A scripted player's run replays as it is. **For N3 or the projectile lane:** caches built at a fixed point of the tick, or listed in DERIVED.
- **Instance ids** parted the AI board's attack targets and the swarm's rows (DERIVED now) and the shots' homing targets (`_home_target`, `_skip_id`: the projectile lane's file, so the scripted run uses no homing card). **For N5.**
- **Real time:** Feel's stops (A1) are frozen and Flow's, Coop's and the horde's `_process` timers (A2) stepped once a tick by the test. **For N3 and N4.**
- **Pauses:** each recorded tick says whether the game stood paused, so a pause-menu pause in the recording is skipped through and the horde's break plays paused. **For N4:** a stop that is part of the state.
- **Joins and leaves** are in the frames but happen as the device joins (Flow and Coop read the seats at a run's start); a replay joins its seats then. **For N10:** joining online.
- **N1's tools** missed four things the real game showed: a kept tick held packed arrays by reference, a float in a report was an error line, a REFS array of arrays stopped the walker, and Flow, Coop, the swarm, the AI board and the swing and slam carriers had members in no list. Fixed, with tests.

### N2b: a first look across platforms

- A cheap measurement, before the costly parts: one recorded sandbox fight and one horde wave (N2), replayed headless on Linux, under Windows (Wine, or a Windows machine by hand) and in the web build (headless Chromium through Playwright), with N1's hash per area at every tick.
- No CI job yet (that is N8): a script under `tests/` and a written result in docs/DECISIONS.md: the first tick and area that part on each platform, or that none does.
- It shows what parts besides trig and the body move, which N6 and N7 take out of the engine anyway: if the platforms part somewhere else (inside the engine's own code), the owner hears it here, early.

**Done (2026-11-06).** `tests/platforms/replay_hashes_runner.gd` (on `--replay-hashes` in the Linux Test, Windows Test and Web Test exports; the Windows Test preset is new) and `tools/platform_hashes.py` (exports, runs Linux headless, Windows through WSL and the web in headless Chromium, and names the first tick, area and members that part); the replay test's machinery is shared in `tests/support/replay_run.gd`. The result, in docs/DECISIONS.md (2026-11-06):

- **Only trig parts, one float step apart:** Windows at the sandbox's tick 0 and the horde's tick 89 (`Vector2.angle_to`, atan2, in Spells' walk turn), the web at the sandbox's tick 1 (`Vector2.from_angle` in the atom's spread) and the horde's tick 117 (`Vector2.from_angle` of a frame's aim). Nothing inside the engine's own code parted first. What hides behind the first parting (the body move, A4) shows once N7 lands; N8 runs this again then.
- **The inputs were the same bytes on every platform,** and each platform replayed its own recording exactly. Windows ran the GDScript twins (no MinGW here), the web the Emscripten kernels; Linux native and GDScript agree at all 600 ticks.
- **Fixed in N1's and N2's tools:** StringName keys walked by text (the engine sorts them by address), kept leaves sliced (the native kernels write past copy-on-write; N10's snapshots must copy so too), and the native switch and the hit test's scratch listed in DERIVED.

### N3: one clock, one context

- `core/sim/tick.gd` (`Tick`, autoload): the tick counter and the only driver of the simulation. Each physics frame it runs one tick, in a written order: input frames, commands, Flow, Coop's rules, actors (by id), Spells, projectiles, Combat, the swarm. Nothing in the simulation has its own `_process` or `_physics_process`; each area's step is called by the tick.
- **No new parameter:** `step(delta)` keeps its signature everywhere; the delta is always `Tick.DT` (a test checks it). The tick number and chance come from the `sim` service (`core/sim/sim.gd`), set on areas and actors the way `combat`, `spells` and `projectiles` are, so tests swap it.
- **Chance by hash (`sim.chance(purpose, key, counter) -> float`, and `chance_int`, `chance_range`):** integer mixing of (run seed, purpose, key, tick, counter), a few integer operations, no allocation, as cheap as `RandomNumberGenerator.randf()`. No shared generator holds state, so a new roll in one system never shifts another's, and nothing about the random state needs saving. Spells' scatter, the brain, the AI, the horde's spawns and offers and the swarm's row seeds move onto it; their `RandomNumberGenerator`s go (fixes A11). Feel and the looks keep their own generators (view).
- **Order by id:** what the simulation iterates (actors, targets, a dictionary's keys) it iterates by id; event listeners in the simulation never depend on connection order for an outcome (a listener that changes state does so through the tick's order, or the event names the one listener).
- Flow's timers, Coop's revive and Horde's breaks move from `_process` to the tick. Coop's camera stays in `_process` (view).
- A slow frame runs up to `max_physics_steps_per_frame` ticks and never changes `DT`, as today; online, the netcode decides how many ticks to run.
- Fixes A2 and A3, and the flaky `test_wave_balance.gd` (docs/BACKLOG.md).
- From N1: the state hash's cost measured on the stress run, now that the tick names the real areas (N1 measured the test worlds only).

**Split in three (2026-11-06):** **N3a** the Tick, its order and the timers on it; **N3b** a run starts from a fresh game's state (every service's clocks, counters, free lists and slots as a fresh one's, so a replay recorded in any run plays in a fresh game; the proof is a replay played after other runs in the same game); **N3c** the `sim` service, chance by hash, order by id beyond the bodies, and the hash's cost on the stress run.

**N3a done (2026-11-06).** `core/sim/tick.gd` (`Tick`) steps the frames, the services, the swarm, the bodies by actor id and the run's rules and timers, in the scene tree's old order (docs/DECISIONS.md, 2026-11-06); the areas' own callbacks are gone; `tests/core/test_tick.gd`. The replay test no longer holds Flow's, Coop's and the horde's timers, which showed that the horde's spawns read the eased camera: Coop now sends the fitted view on the tick (`view_fitted`) and the horde spawns outside it.

**N3b done (2026-11-07).** A run starts from a fresh game's state: Flow's `start_run` calls `Tick.begin_run`, which counts the clock from 0 again and makes the services and the horde director fresh (`Tick.FRESH_AT_RUN`, each one's `begin_run`). An area takes every state member from a blank of its own script (`core/sim/sim_fresh.gd`, `SimFresh`): by construction, so a member added later is reset too; settings stay (`RUN_KEEPS`). The proof is `tests/core/test_replay_game.gd`'s two "after other runs" tests: a sandbox run and a horde run, each recorded in a fresh game, played after other runs in the same game and recorded again there, agree at every tick (before, they parted at tick 0 in every service). What the runs found:

- **Dead slots, pools and free lists** (the projectile manager's per-slot arrays, Spells' pending launches, a dash's passes, Combat's pool): the blank's, as a fresh game has them. A member that points into a pool (`Spells._ray`, the first of `_rays`) points into it again: `SimFresh` keeps what the blank shares shared.
- **A cache carried a run's answer:** `CompiledSpell._plain_hit` (worked out on the first hit) lives on a compiled staff, which outlives a run in the compile cache: DERIVED.
- **Feel's rests and repeats** (view, but they decide the simulation's holds, A1) run on Feel's clock: a reaction heard in the last run kept the next run's first one from holding. They start again at `room_entered` until N4 counts the stops in ticks.
- **The horde director** kept its swarm and the last run's seats' bags: made fresh too. A blank deals the run no seeds (`SimSeed.aside`), so making one changes no horde.
- **Entities' decoy bodies** (a pool out of the tree) are freed at a run's start, as a fresh game has none; dropped, they leaked.
- **Cost:** `Tick.begin_run` takes about 19 ms at the desktop cap (6,000) and 38 ms at 100,000 (the owner's machine, headless), once per run start; copying a pool's items member by member took 238 ms, so a pool takes the blank's items whole.

### N4: stops in ticks

- Hit-stop and the downed stop become a number of ticks the simulation stands still (`Tick.hold(ticks)`), started by the simulation events that cause them; Feel only draws them.
- The horde's level-up break and, offline, the pause menu stop the tick (`Tick.stop(reason)` / `Tick.go(reason)`, part of the state) instead of pausing the scene tree for the simulation; the HUD and Feel run on as they do today. Fixes A12. `Engine.time_scale` is no longer set by the game (the dev time-scale switch, if kept, scales the tick rate on one machine only, offline).
- Fixes A1. Feel's feel is checked side by side with today's in the sandbox before it merges.

### N5: identity without instance ids

- Targets, zap rolls and carrier hand-overs keyed by actor id (or the projectile slot), not `get_instance_id()`.
- Actor ids stay "lowest free first" (already deterministic).
- Fixes A5.

### N6: our own body movement, in C++

C++ from the start, whatever N2b finds (the owner, 2026-11-04).

- `BodyKernel` (`native/src/body_kernel.cpp`): one call per tick moves every actor against the wall grid the projectile manager already keeps (room walls and solid shots): circles sliding along the grid's walls, the way the swarm moves onto its floor. It takes the actors' packed arrays (position, wanted move, radius) and the grid, and writes the positions back, as the other kernels do (native/README.md: arrays in place, nothing kept). Its maths is N7's.
- `move_and_slide` and the bodies' physics shapes leave the simulation; the actor sets its position from the kernel's result.
- Body-against-body pushing stays Combat's push.
- **A GDScript twin, as every kernel has** (`gameplay/actor/body_move.gd`): the fallback when the module is not loaded (the project opened in the Godot editor without building it), and the reference its side-by-side test compares with, to the bit. Its tests also check the behaviour directly: sliding along a wall, into a corner, between two solid shots, at every speed a dash reaches.
- Fixes A4. The highest-risk part for feel: walking along and into walls is compared with today's in the sandbox and by the bots before it merges.

### N7: deterministic maths, in C++

C++ from the start, whatever N2b finds (the owner, 2026-11-04).

- `native/src/dmath.h`: `sin`, `cos`, `tan`, `atan2`, `exp`, `log`, `pow` from `+ - * / sqrt` only (polynomials with a range reduction, never the C library). The kernels (`ShotKernel`, `SwarmKernel`, `BodyKernel`) call it inline, in place of their `std::` trig.
- `DMath` (the module's class, made by `core/native/native.gd` like the others): the same functions for GDScript, plus `from_angle`, `rotated`, `angle`, `angle_to` and `lerp_angle` on `Vector2`. Simulation code calls `DMath` and never the engine's trig (N9's test); view code keeps the engine's.
- Two PRs: **N7a**, the C++ side (`dmath.h`, the kernels' trig, the build flags), in the projectiles lane before H5; **N7b**, the GDScript side (the `DMath` class, its twin, every simulation trig call).
- `native/SConstruct` builds with `-ffp-contract=off` and without fast-math on every platform (a protected file: the owner's change, listed in the PR).
- **A GDScript twin** (`core/sim/dmath.gd`, the same polynomials): the fallback without the module, and the reference the side-by-side test compares with, to the bit. Tests also check it against known values (within a few units in the last place of the engine's results) and that it gives the same bits on every platform (N8).
- Fixes A6 and A7.

**The native contract holds.** N6 and N7 follow native/README.md like every kernel: C++ is what every build runs, and a GDScript twin, compared to the bit, keeps the project opening and playing in a plain Godot editor without a compiler (the owner, 2026-11-04: "So then I can't open it in Godot anymore?"). Because the twins match the C++ bit for bit, a game without the module is the same game, only slower; only the netcode, later, may require the module, for speed.

### N8: the same game on every platform

- A CI job plays a set of replays (N2) headless on Linux, under Windows (a Windows runner, or Wine) and in the web build (headless Chromium through Playwright), and compares the hash at every tick. The first tick that differs is reported with each area's hash, so the cause is found quickly.
- Runs on the daily build. The workflow is under `ci/`/`.github/` (protected): the owner's change, drafted in the PR.
- Proves done-when 3.

### N9: the simulation/view line, checked

- Every script is either simulation or view, by folder (simulation: `core/sim`, `core/spells`, `core/projectiles`, `core/actors`, `gameplay/actor` except the looks, `gameplay/ai` except the looks, `gameplay/combat`, `gameplay/coop` rules, `gameplay/flow`, `gameplay/horde` except `swarm_look.gd`, `gameplay/player` controllers, `gameplay/progression`, `gameplay/rewards`, `gameplay/run`, `gameplay/difficulty`; view: `gameplay/feel`, every look, `hud/`, the camera). The list lives in `core/sim/README.md`.
- `tests/core/test_sim_rules.gd` reads every simulation script and fails on `Time.`, `Engine.time_scale`, `Input.`, `InputManager` outside the frame builder, `get_viewport`, `Camera2D`, `_process`, global `randf`/`randi`/`randomize`, and `get_instance_id` (other than in equality keys the test allows by name). AGENTS.md gets the rule ("Simulation code runs on the tick").
- **View code inside a simulation script** (A13: the projectile manager's drawing and sparks) is named in that script's `const VIEW: Array[StringName]` (functions and members). The test skips those functions, the walker skips those members, and the determinism test at different render frame rates (done-when 2) catches a view function that writes state.
- Proves done-when 6. It also fails on `RandomNumberGenerator`, `_process` and `_physics_process` in simulation scripts (N3), and on the engine's trig (`sin`, `cos`, `tan`, `atan2`, `exp`, `log`, `pow`, `Vector2.angle`, `rotated`, `from_angle`, `angle_to`, `lerp_angle`) there (N7).

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

## With shot scale (threads, 100,000 shots)

[shot-scale.md](shot-scale.md) (approved by the owner on 2026-11-04, with these rules) adds threads to the shot kernel and aims at 100,000 shots. Checked against this plan on 2026-11-04: they fit, on five rules, written into both plans.

- **T1: the hit budget is fixed work, never measured time.** `WORK_PER_STEP` stays a number of work units in the code, sized once from H0 on the target PC (shot-scale Q3). A budget measured at run time would let a fast machine test more hits a step than a slow one: two different games. (Shot-scale H2 said "by time"; changed.)
- **T2: threads never change a result.** Chunks of a fixed size (not one per core), each reading only the target grid and writing only its own shots; partial results (hits, the threat grid's sums) combined in chunk order; the hit budget spent at the merge, in shot order. A test runs the kernel with one thread and with several and compares the bits, so the web's single chunk and a 12-core desktop play the same game.
- **T3: the kernels' maths is `dmath.h`** (N7), threaded or not.
- **T4: the caps are session rules** (N11). The weakest machine in a session sets the shot cap online, and at 100,000 shots that matters more: every machine simulates every shot. A snapshot of a full room grows to roughly 10 MB (a join only, N10); the hash runs once a second.
- **T5: what shot scale changes only in the look stays view.** H3b's one look per target is drawn only; it may use real time and its own generators, in `VIEW` (N9).

**Both help each other.** N1's hash and desync report prove H5's "threaded equals one thread" and the damage check; H3b's re-recorded hit traces and N3's (chance by hash) are recorded again together, once.

**One order for both** (they share `core/projectiles/projectile_manager.gd` and `native/src/shot_kernel.cpp`, so one PR at a time there):

1. N1, with H0 beside it (benchmarks only).
2. The projectiles lane, one at a time: ~~H1~~ (dropped 2026-11-05, measured: H3b folds it in), H2 (fixed budget, T1; done 2026-11-05), N5, N7a (the kernel side of N7), H5 (T2), H5w if the web supports threads, H6 if measured, H7 last (after N11; H4 is dropped).
3. Beside it, the rest: N2, N2b, N3, then N4, N7b (the GDScript side of N7), N6 (after N7a), N11; then H3 (one listener at a time) and H3b after N3; then N8, N9, N10, N12.

The tasks are in NEXT.md's owner lane in this order.

## After phase N: the netcode (a sketch, not approved)

Its own phase and its own owner exception to hard rule 4 (the owner, 2026-11-06: "netcode can easily be allowed"), best after M7 (Steamworks):

- **Model:** host-ordered lockstep. Every machine sends its seats' input frames to the host (on Steam, through Steam's relay); the host fixes each tick's frames, with a short input delay (2–4 ticks), and sends them to all. A frame that arrives late is replaced by that seat's last one, so **a slow connection hurts only its own player and nobody waits** (pillar 2). Rollback on top is possible later, on N10's snapshots.
- **Desync check:** machines exchange N1's hash every second; on a mismatch the host sends a snapshot.
- **Joining:** the host sends a snapshot (N10), then frames.
- **Security:** only input frames, hashes and snapshots cross the wire, each with a strict decoder and size limits; nothing from the wire is ever code, a resource or a path. All networking lives in one owner-only folder (like `native/`), and hard rule 4 stays for everything else.
- **What it can and can't do (the limits, 2026-11-04):**
  - *Feel over distance.* A player's own input takes effect after the round trip to the host plus the input delay. Good under about 80 ms ping (the same country or region), sluggish above about 150 ms. To hide it, each machine draws its own staff moving at once, ahead of the agreed game (a view-only guess, corrected smoothly; the simulation stays exact). Full rollback would fix it, but re-running 6–8 ticks of 3,000 shots in one frame is likely too slow in GDScript; it is measured before it is promised.
  - *The slowest machine sets the pace.* Every machine runs the whole game, so a machine that cannot keep 60 ticks a second holds the others back or falls out. The session rules (N11) are capped at the weakest machine's, and if that is not enough the session may slow the game (the owner, 2026-11-06: "Slowing the game is an option if we have to!"); web clients likely play smaller rooms, or only with other web clients (an owner decision then).
  - *The same build.* Every machine must run the same build and content; the game refuses to join a session of another version. With a daily build, a session is "same nightly or same stable".
- **Transport:** Steam networking on desktop; WebRTC with a small signalling server for the web build (infrastructure the project does not have yet).
- **View:** each machine's camera follows its own seats; the HUD shows only local seats' builders.
