# The simulation's hot paths in C++, built for threads

**Status (2026-11-22): the owner's go-ahead of 2026-11-22.** SN1 (this document and the first kernel, a body's walk) built ("Built (SN1)" below); SN2 (Flow's waking) built ("Built (SN2)"); SN3 (the foes' nearest-foe search) built ("Built (SN3)"); SN4 (the long rays) built ("Built (SN4)"); SN5 on are each a PR of their own, in the order below, the next opened once the last is merged.

**The owner's decisions (2026-11-22):**

1. **The same bits.** The game stays bit for bit what it is, on every machine and with any number of threads: the web build has none and online play needs the web and the desktop to agree. `tests/benchmark/tick_hash.gd`'s four biomes (1p seed 11, 2p 23, 3p 37, 4p 11, the whole state hash every tick) stay identical between main and each PR, with the native module on and off.
2. **Determinism by structure.** A step is cut into independent parts (one body's think, one shot's move) that read the state as the step found it and write only their own results; the results are applied after, in a fixed order. Chance is already counter-based (`sim.chance(purpose, key, counter)`): no roll needs shared state. No sum whose order depends on the threads; no fused multiply-add or fast-math (#910's `no_fma` check).
3. **The GDScript stays** as the reference and the fallback (AGENTS.md: native kernels mirror their GDScript to the bit), each kernel with a byte-for-byte side-by-side test.
4. **Threads on the desktop only**, the web single-threaded with the same result.
5. **Later:** the tick on its own thread beside the drawing. That needs the simulation's state off the nodes; the data layout here is chosen for it, but it is not this series' job.

The steps are **SN1 to SN6** (SN for simulation native).

## What a tick costs now (SN1's profile)

Measured headless with the native module, `tick_hash.gd --profile-steps` (bots playing a whole biome, `--sturdy`, each step timed from a second into the run), main at 356803a, on this container's 4 cores. ms a tick:

| Step (`Tick.STEPS`) | 1p (seed 11) | 2p (23) | 3p (37) | 4p (11) |
|---|---|---|---|---|
| bodies | 0.293 | 0.375 | 0.468 | 0.606 |
| Flow | 0.338 | 0.345 | 0.335 | 0.380 |
| Projectiles | 0.151 | 0.156 | 0.176 | 0.229 |
| Cover | 0.156 | 0.147 | 0.154 | 0.196 |
| Spells | 0.086 | 0.094 | 0.109 | 0.140 |
| Combat | 0.050 | 0.055 | 0.058 | 0.075 |
| Rewards, Items, Entities, Coop | 0.088 | 0.100 | 0.109 | 0.112 |
| **whole tick** | **1.162** | **1.273** | **1.407** | **1.740** |

**The bodies, per path** (a timer round each call of `Actor.tick_step` and its parts, a patch kept out of the tree: the timers themselves add about a fifth, so the shares count, not the sums). 4p, seed 11, ms a tick over 13,689 ticks:

| Path | Wizards (4 a tick) | Foes (about 1.8 awake a tick) |
|---|---|---|
| the controller's think (a wizard's `PlayerController.think`: its frame read, `announce_stats` to the HUD; a foe's `AIController`/`AIBrain`) | 0.100 | 0.046 |
| the caster's step (`Caster.step`): its place sent (`_push_place`: the manager's anchor, Spells' aim) 0.043, its casts (`cast`: Spells' `press_staff`/`cast_staff`) 0.066, the mana's refill | 0.137 | 0.015 |
| the Mover's step (`Mover.step`) | 0.041 | 0.014 |
| the rest of the step (health, the hurtbox, the inventory, the looks' clock, a hold) | 0.084 | 0.026 |
| **the move** (`Actor.move`) | **0.130** | **0.039** |
| of which: the slide over holes (main's `_move_over_holes`: two or three `slide_body` calls with `is_hole`/`touches_hole` between) | 0.052 (all bodies) | |
| the ground under it (`_check_ground`: `is_hole`, `touches_hole`) | 0.034 (all bodies) | |
| the room it stands in (`find_room`: `RoomGrid.place_at`) | 0.014 (all bodies) | |
| the touches (`_touch`: `Actors.touching`, the props' `touched`) | 0.018 (all bodies) | |
| setting `global_position` | 0.009 (all bodies) | |

1p has the same shape: wizard 0.136 (think 0.039, caster 0.052, move 0.039), foes 0.091 (think 0.044, move 0.028).

What this says:

- **A wizard's body is about 0.1 ms a tick, a foe's about a third of it.** The foes are cheap because most sleep with their rooms (connected biomes CB3): about two are stepped a tick in these runs. A crowd of awake foes (an arena, a wave) is where the AI's think grows, and its share should be measured again there (SN3: "Built (SN3)").
- **The move is the largest path, and the one that is pure arithmetic on arrays:** its slides, hole tests and room lookup read the room grid's packed arrays and nothing else. The rest of the move (the dash held up, the fall, the touches) sends events or calls gameplay.
- **The caster's casts are Spells' runtime,** not a loop: hundreds of lines of GDScript making launches and shots, with events. They stay GDScript in this series; only `_push_place`'s wall clip (`clip_to_walls`, the room grid's) is arithmetic.
- **Much of a body's cost is calls, not work:** each component step, each service asked by its node, each signal. A kernel saves the call only where many small calls become one; one call a body that does what three or four did is the shape of SN1.

## The order

Each step moves a path whose work is a pure function of arrays, keeps the order in which the game does things today (owner's decision 1), and is measured main against the branch with `tick_hash.gd --profile-steps` at 1 to 4 players.

| PR | What moves to C++ | Where it runs | Why in this order |
|---|---|---|---|
| **SN1** | **A body's walk:** `Actor.move`'s grid work in one call (`BodyKernel.walk`: the slides over holes or the plain slide, the hole under the body's end and whether its circle reaches a hole) | each body's move, in id order as now | the largest pure path (above); one native call a body where there were up to five (three slides and two hole tests); the room it ends in (`find_room`) joins in SN2 |
| **SN2** | **Flow's waking** (`RoomLife.wake`'s first pass: every open body's place found where its node stands and set as its `room`, in one `BodyKernel.places` call), and a native-on/native-off compare in the regular suite | Flow's step, once a tick | moved up from SN5 by SN2's profile: the waking was 0.17 ms a tick at 4p, the largest single path left (below) |
| **SN3** | **The foes' look for their nearest foe** (`ProjectileManager.nearest_target`, which `AIBrain._find_target` asks ring by ring: `ShotKernel.nearest_target`) | each foe's think, in id order, as now | SN3's profile in a crowd (below): the target's search was the brain's largest part, not the perception |
| **SN4** | **The room grid's long rays** (`RoomGrid.wall_hit` and `_way_hit` past `NATIVE_RAY_CELLS`: an AI's line of fire, sight, walk and ground checks, `clear_run`, the harm exit's search; `BodyKernel.wall_hit`, `way_hit`, on `grid_ray.h`, which the shots' hit pass shares) | where they are asked, as now | the owner's decision of 2026-11-22 (below): the next pure kernels by profile, the game the same |
| SN5 | **Whatever the profile names next**, measured again after SN4 | | |
| later | **The body table, the foes' perception in two phases and the simulation's threads**, with the state off the nodes (the tick on its own thread): waiting for that step, by the owner's decision of 2026-11-22 | | |

Every step keeps the game exactly as it is. The two-phase step (later) is the one whose parallel part reads the state of the tick's start where today a foe reads what the bodies before it in id order did this tick: that changes the game (not the determinism), which the owner accepted (2026-11-22): SN4 records a new baseline.

## The data layout

The state that kernels read lives in **structure-of-arrays tables keyed by actor id**, as the actor table already keeps `still`, `asleep`, the holds and the touch boxes (`core/actors/actors.gd`), and as the projectile manager keeps its shots by slot:

- **The room grid** (`RoomGrid`, the manager's): walls, walk cells, the bodies' ground, holes, mouths, places. Already packed arrays; SN1 hands them to the kernel per call, as `slide_body` does.
- **The body table** (SN2, columns of `Actors`, sized `ACTORS`): `position: PackedVector2Array`, `velocity: PackedVector2Array`, `radius: PackedFloat32Array`, `walk_mask: PackedByteArray` (mouths passed), `team: PackedByteArray`, flags (`down`, `dying`, `spawning` as bits of one `PackedByteArray`). **One owner per datum:** a column is either the state (the node's member becomes a getter over it, DERIVED as a computed property, core/sim/README.md "Steps") or follows the node (DERIVED, written where the node changes and set up again in `rebuild_derived`), never both. SN2 starts with follow-the-node columns, so a snapshot and the hash stay exactly as they are; the columns become the state one by one as the tick-on-a-thread work needs it (the owner's later goal: then nothing a kernel reads lives on a node).
- **Results tables:** what a parallel part writes (SN4: a foe's perception) is a row of a results table of its own, by actor id, DERIVED (scratch refilled each tick before it is read, core/sim/README.md "Steps"), read by the body's own step. A part writes only its own row; nothing in a row is a sum over others.
- **The kernel reads with `get`, writes in place, keeps nothing** (native/README.md, "The object's arrays, in place"): the table sizes every array before a call; no copy of a column is kept by anyone.

## The parallel split and the merge order

| Step | Independent part | Reads | Writes | Merged |
|---|---|---|---|---|
| Projectiles' common and behaviour passes | one shot | its slot | its slot | already (`jobs::for_spans`, shot scale H5) |
| SN4's perception | one awake foe | the body table and the room grid as the bodies' step found them, the threat grid | its row of the perception table | nothing to merge: each foe reads its own row in its step, in id order |
| SN2's waking | one body | its node's place, the places | its `room` and its row of `_places` | the places awake worked out after, in id order, in GDScript (`keeps_awake` reads the bodies) |

Rules for every split: a part never reads what another part of the same pass writes; anything shared (counts, sums, events) is combined on the calling thread in id or slot order; a roll is `sim.chance` with the part's own key and counter; floats are never summed across parts in a thread-dependent order. The events a step sends stay GDScript, sent in id order from the merged results.

## Snapshots, the hash and the mirror

- **SN1 adds no state:** the kernel computes what `Actor.move` computed and the same members are written; nothing is walked differently.
- **Columns that follow the nodes are DERIVED** (and `rebuild_derived` writes them from the bodies after a restore), so the hash and the snapshot walk exactly what they walk now. A column made the state is walked as the table's packed array (one leaf of the engine's hash a column, cheaper than the bodies' members), and the node's member it replaces leaves the walk: the hash of a whole game then changes its value, not its meaning, so such a move is its own PR and compares main against branch by a state walk, not by the hash's value (a desync test of both sides' states, `Desync.compare`).
- **Results tables are DERIVED scratch**, refilled each tick before they are read: never in a snapshot, never hashed.
- **The mirror:** each kernel's GDScript twin stays where the code was (SN1: `RoomGrid.gd_walk_body`, the reference the C++ mirrors line by line), the kernel called when the module is loaded and the twin otherwise (`WallSlide`'s pattern); its side-by-side test steps both on the same arrays and compares every result byte for byte, every branch reached.

## The threading model

- **Where the threads come from** (the owner, 2026-11-22: "use the best solution"). **Inside a kernel's pass, the module's own pool:** `native/src/jobs.cpp`'s `jobs::for_spans` (spans of a fixed size on up to `width` threads, the caller's among them; the owner's choice of 2026-11-07 over the engine's `WorkerThreadPool`). A kernel called once for a whole pass splits it itself: one call from GDScript, no Variant per chunk, nothing of the engine touched on a worker, deterministic by construction (a span writes only its own; what spans share is merged after, in span order), every span run on its caller on the web (`threads=no`), and checked by `smbot.rules` (`NATIVE_THREADS_FILE`). It is already measured and tested on the shot passes. **`WorkerThreadPool` group tasks only where GDScript has several independent kernel calls to make at once** (a pass over two tables, each its own kernel call): there the engine's pool runs the calls side by side, each call on its own arrays, the results applied after in a fixed order on the calling thread; on the web it runs them one after the other, with the same result. A group task a chunk would instead pay the Variant call path once a chunk and run on threads the engine owns, for no gain over a span. SN1 needs neither.
- **Chunks:** fixed sizes per pass, never derived from the thread count (so the merge order is the same at any width): 64 bodies a span for the body passes (a tick has at most a few hundred awake bodies), as the shot passes have theirs.
- **How many:** the machine's cores less one on the desktop, at most 16; 1 on the web. This machine's setting, never a run's rule, since it changes no result (as `ShotKernel.threads`).
- **Proof:** SN6's test runs a scene at 1, 2, 4 and 8 threads, the state hash compared every tick; the four biomes compared main against branch at the default width and at 1.

## Measuring

`tick_hash.gd --profile-steps`, headless, native, main against the branch at 1 to 4 players (the four biomes' seeds), the same machine, one run after the other. Whole biomes take about two minutes a run here. The per-path timers of SN1's table are a patch kept out of the tree (a simulation script may not read the clock: core/sim/README.md, "The line").

## Built (SN1): a body's walk

- **One call a move.** `Actor.move` hands the grid its move, what of it crosses holes, its radius, whether it passes mouths and the reach its ground is looked at within (`RoomGrid.walk_body`); the answer is where it ends and the holes there (`WALKED_OVER_HOLE`, `WALKED_NEAR_HOLE`), which `_check_ground` reads in place of asking `is_hole` and `touches_hole` again. With the module loaded it is `BodyKernel.walk` (a new method of the class, no new class), else `RoomGrid.gd_walk_body`: main's `_move_over_holes` and the holes `_check_ground` asked, in the same order, through the grid's own `slide_body`, `is_hole` and `touches_hole`. A grid with nothing laid answers the whole way with no call. No member was added or moved: the state, the hash and the snapshots are as they were.
- **The same game.** The four biomes' state hash every tick (1p seed 11, 2p 23, 3p 37, 4p 11; 12,087 to 18,417 ticks each) is identical between main and this branch with the native module on, and identical between main and this branch with it off.
- **Tests:** `tests/core/test_body_walk.gd`: 12,000 walks in seeded rooms of walls, mouths, holes and the props' ground (with and without walls), a third of them on quarter pixels with whole radii so the comparisons' boundaries are met; the kernel against its twin run in GDScript all the way down (its slides `WallSlide.gd_slide`), byte for byte, and the twin against main's calls kept frozen in the test; every branch of the walk and every flag of its end reached. Two mutants of the C++ (a `<` made `<=` in the hole test, the void outside the grid made ground) each fail it. The wiring in the actor: `test_move_holes.gd`, `test_fall.gd`, and the hash compare.
- **Measured** (headless, native, `tick_hash.gd --profile-steps`, main → this, ms a tick, one run each; the other steps move by a few per cent between runs): the bodies 1p 0.293 → 0.259, 2p 0.375 → 0.357, 3p 0.468 → 0.440, 4p 0.606 → 0.551; the whole tick 1.162 → 1.052, 1.273 → 1.250, 1.407 → 1.369, 1.740 → 1.640.
- **Found on the way, on main:** with the native module off, main's own run of the four biomes parts from its run with the module on (1p at tick 820, 2p 1464, 3p 1033, 4p 889): some kernel or its fallback is not the same to the bit as its GDScript in play, though each side-by-side test passes. This branch changes neither side. A machine without the module never plays online today (every build has it), but a desync between the two is a mirror broken somewhere; to be found with the desync report (`Desync.compare` of the two runs at that tick) before SN2.

## Built (SN2): Flow's waking

- **Profiled first** (4p, seed 11, timers round each part of Flow's step, a patch kept out of the tree, ms a tick): the waking (`RoomLife.wake`) 0.171, of which its first pass 0.132 over about 46 open bodies a tick (2.9 us a body: `place_at` 1.4, the rest the lookups and `keeps_awake`); the teleports' tell 0.056, the locks 0.030, `forget_gone` 0.028, the doors 0.021, the runes 0.010. So the waking moved up from SN5.
- **One call a tick.** `RoomLife.wake`'s first pass is `RoomGrid.find_places`: the native module's `BodyKernel.places` reads each open body's node by the actor table's instance ids (in the tree, where it stands, its `room` and its manager), works out its place (the twin of `place_at`) and sets its `room` where it changed; else its twin `RoomLife.gd_find_places`, main's loop. `keeps_awake` is asked after, in id order, only of the bodies in places not yet awake (it reads only the body's own: dying, who drives it, still, its team, so asking it after every place is found gives what main gave). A body of another manager is handed back (`RoomGrid.ASK_GDSCRIPT`); a kernel that refuses its arrays, or a library built before the method, runs the twin (`find_places` false; `WallSlide` asks for `walk` and `places` and checks `NO_PLACE` and `ASK_GDSCRIPT` at `configure`). No member added or moved.
- **The same game.** The four biomes' state hash every tick identical to main's (3cd6147) with the module on and with it off.
- **Native on and off in the suite** (the orchestrator's ask after #916): `tests/core/test_determinism.gd` plays the fight and the storm with the kernels they reach on and with them off, every area every tick (it fails, at the storm's tick 12, with the manager's `_one` made state again); `tests/gameplay/flow/test_room_life.gd` compares the native places with the twin's over a biome's bodies scattered on rooms, bridges and the void (a third on whole 16 px cells), and plays `wake` itself with the module on and off (the places awake, the bodies asleep, every room). A mutant of the C++ (an overlapping place's `over` dropped) fails it.
- **Measured** (headless, native, `tick_hash.gd --profile-steps`, main → this, ms a tick): Flow 1p 0.325 → 0.266, 2p 0.324 → 0.291, 3p 0.314 → 0.309 and again 0.315 → 0.289, 4p 0.366 → 0.311; the whole tick moves with the other steps' noise (1p 1.112 → 1.004, 4p 1.641 → 1.553).

## Built (SN3): the foes' look for their nearest foe

- **Profiled in a crowd** (`tests/benchmark/ai_step.gd`: 200 awake staffed foes round four wizards, timers round the brain's parts, a patch kept out of the tree, ms a pass): one pass of their steps 15.6, their think 7.4, of which the target's tracking (`_track_target`: `_find_target`, `nearest_foe`) 3.4, the perception 0.94, the decision 0.47, the chase 0.41, the harm's steering 0.23. The look for the nearest foe is `ProjectileManager.nearest_target` asked ring by ring (160, 480, then the whole room), which walks every target in the cells it covers and passes over the foe's own crowd one by one. So SN3 is that search, and the body table with the two-phase perception moves to SN4.
- **One call a ring.** `nearest_target` searches in C++ when the module is loaded (`ShotKernel.nearest_target`, a new method of the class: `_query_cells`, `_query_match` and the team's rules on the manager's arrays, read through `MANAGER_FIELDS`), else `_gd_nearest_row`, main's loop. A library built before the method runs the GDScript (`_kernel_nearest`).
- **The same game.** The four biomes' state hash every tick identical to main's with the module on and with it off.
- **Tests:** `tests/core/test_native_kernel.gd` asks both managers the nearest targets between steps (small circles and the whole room, by a team or none, on one layer or both, again past the first found and past both: the skips change the answer) and from inside the hit pass (a chain's jump, the grid stale, rows taken away or grown since), and the native manager's kernel against its own GDScript on the same grid; a mutant (`skip_also` dropped) fails it.
- **Measured:** the crowd (`ai_step.gd`, median ms a pass) main 16.0, this with the kernels off (`--no-native`) 15.6, on 12.7. The biomes, headless (`tick_hash.gd --profile-steps`, main 74beba1 → this, ms a tick): 1p 1.067 → 1.057, 4p 1.586 → 1.535 (the bodies 0.544 → 0.529): about two foes are awake a tick there, so the search was little of it.

## Built (SN4): the room grid's long rays

- **Measured first** (after SN3, `ai_step.gd`, 200 awake foes, timers patched in, ms a pass): the step 14.2; the brain's think 5.0, of which the perception 0.98, the target's tracking (native since SN3) 0.85, the decision 0.50, the chase 0.44; the caster 1.7, the Mover 1.2, the rest mostly the looks (stepped each tick by the bench, left to the drawing by the game). So the two-phase perception would save at most about 0.7 ms on four threads in such a crowd and next to nothing in a biome, for a large refactor of the brain and a game changed: the owner chose (2026-11-22) to leave it, and the simulation's threads, for when the state is off the nodes, and to take the next pure kernels instead.
- **Built:** a ray that crosses more than `RoomGrid.NATIVE_RAY_CELLS` (4) cells is walked in C++ when the module is loaded (`BodyKernel.wall_hit`, `way_hit`): `wall_hit` past its fast paths and `_way_hit` past its checks, so `line_clear`, `clip_to_walls`, `sight_clear`, `ground_clear`, `walk_clear` and `clear_run` (an AI's line of fire, sight, walk and ground checks, the harm exit's search) take it. The walk is `native/src/grid_ray.h`, shared with the shots' hit pass (`HitPass::wall_hit` now calls it), mirrored from the grid's loops line by line. A shorter ray stays in GDScript, which costs less than the call. A refused grid (-2) walks in GDScript.
- **One ray, timed** (`line_clear` across an open room, us a ray, GDScript → native): 3 cells 1.69 → 1.77, 6 cells 2.68 → 1.47, 20 cells 6.2 → 1.4, 80 cells 16.9 → 1.6, 140 cells 24.2 → 1.3.
- **The same game.** The four biomes' state hash every tick identical to main's with the module on and with it off.
- **What it gains: nothing that shows yet.** The biomes (headless, `tick_hash.gd --profile-steps`, main 0b56604 → this, ms a tick): 1p 1.035 → 1.053, 4p 1.626 → 1.613, within the runs' spread. The crowd (`ai_step.gd`, median ms a pass, three pairs): main 12.5, 12.9, 14.6 against this 13.1, 13.7, 15.2, main's own runs spreading over 2 ms on this container. Most of the rays the game asks are short or meet a wall within a few cells, where the two cost the same; a ray across open ground (a long line of fire, a sight across a hall) costs a fifth to a twentieth. The walk shared with the shots' hit pass (one C++ copy of `wall_hit`, not two) stays worth keeping either way.
- **Left as they were, by the profile:** the touches (`Actors.touching`, 0.018 ms a tick at 4p for every body together: a native call a body costs as much) and the wizards' wall clip (`_push_place`'s `clip_to_walls` is a staff's length, one or two cells, already `wall_hit`'s fast path; its 0.043 ms is the calls round it).
- **Tests:** `tests/core/test_grid_rays.gd` (8,000 seeded rays, short and long, a third on whole cells, every query, native against GDScript to the bit; a mutant in `way_hit` fails it); `tests/core/test_native_kernel.gd` holds the hit pass to its GDScript through the shared walk.

## Answered by the owner (2026-11-22)

1. **The two-phase step was accepted** (later set aside by answer 3): a foe's perception is worked out from the state at the tick's start, so the game changes once. That PR records a new `tick_hash` baseline and says which replays and fixtures it records again; the game stays deterministic on every machine and at any thread count.
2. **Threads: the best solution**, as recommended: the module's own pool (`jobs::for_spans`) inside a kernel's passes, `WorkerThreadPool` only where GDScript has several independent kernel calls to make at once ("The threading model").
3. **SN4 by the profile (2026-11-22):** the two-phase perception skipped for now; the two-phase step and the simulation's threads wait for the state-off-the-nodes step; SN4 is the next pure, order-preserving kernels by profile.

## Open questions for the owner

None. (The parting found on main with the module off was the manager's `_one`, fixed in #916; the regular suite now plays native against GDScript, SN2.)
