# Performance plan: where a frame goes, and what would make the game 2x faster

**Status (2026-11-28): a research report, proposed.** Nothing here is built. The owner asked for far more than the few percent a targeted cut now gives (2026-11-28: "Improve performance! ... More c++ maybe? Or multimesh or any other tricks."). This file measures the frame end to end on main at 7cecf8fe (#984 to #992 merged), ranks the structural changes that would cut it most, and splits each into PRs. The decisions that are the owner's are at the end ("Open questions for the owner").

## The answer in short

- **In ordinary play the simulation is cheap and the drawn frame is the cost.** One player: the tick is 1.0 to 1.6 ms, Feel (everything drawn or heard only) 4.4 to 4.8 ms a frame. Once fights fill the screen the simulation catches up: in the 4-player benchmark fight the tick is 9.0 ms and Feel 8.9 ms. In the stress crowds the tick is 11.6 ms (web, 100 foes, 1,000 shots) and 24.9 ms (desktop, 200 foes, 6,000 shots).
- **Two things are most of the tick in every fight: the foes' bodies (half of it) and the GDScript half of the hit pass** (the work done for each hit after the C++ kernel has found it). Where the native module already runs, the C++ part is small: 0.7 of the 3.8 ms hit pass (web stress), 1.7 of 10.5 (desktop stress).
- **Over budget, the frame grows by more than the tick does.** Godot runs up to 3 ticks in one drawn frame to keep up with real time (`max_physics_steps_per_frame=3`), so a slow frame makes the next one slower. While a frame is over 16.7 ms, every ms cut from the tick saves about 2 ms of frame (the model is below).
- **2x on the desktop looks reachable**, with four structural changes: hits handled as one batch, the crowd's per-tick work in C++, Feel's frame in C++ and on threads, then the tick on a thread of its own beside the drawing. The web gets the first three. **5x is not shown by these numbers.** It would need decisions about the game itself (how often foes think, how much each hit shows) and the GPU's numbers from the owner's PC, which no cloud machine can give.

## How this was measured

- On this container: 4 cloud vCPUs, Linux, Godot 4.7.2, the native module built from main (`ci/build/build.sh --quick`, `ci/build/native.sh linux`). No GPU: a drawn run uses llvmpipe, Mesa's software rasteriser, and there is no Vulkan, so `--rendering-method mobile` falls back to OpenGL. Every GPU time and every renderer CPU time from this machine is meaningless and is not used below. Only the draw-call and primitive counts are kept.
- **Stress** (`tests/benchmark/stress.gd -- --only=web|desktop --profile [--no-native] [--profile-signals]`), headless, on the real clock. The signal timings come from a separate `--profile-signals` run, because that profile's proxies add a cost of their own.
- **The shipped benchmark's scenarios** (`tests/benchmark/play_frames.gd -- --only="1p near,1p far,4p apart equal" --profile --census`, under `xvfb-run`). These run on the fixed clock, one tick a drawn frame, at the desktop settings with the effects at high. They are the scenarios `Spellmerge.exe -- --benchmark` plays.
- **Whole biomes** (`tests/benchmark/tick_hash.gd -- --players=1|4 --seed=11 --sturdy --profile-steps`), headless. This runner does not read `--no-native`.
- **The web build** (`ci/build/build.sh --web`, then `PYTHONPATH=ci python3 -m smbot.websmoke build/web --page-args=--stress`). This is the WASM export in headless Chromium: one thread, SwiftShader drawing. Its "render loop off" scenario is pure game logic.
- **Section timers inside a body's step and the AI's think** (a patch to `actor.gd`, `brain.gd` and `tick.gd`, never committed). They ran in the web stress and in the "4p apart equal" fight. The timers add to what they time, so read their parts as shares.

Every number is ms on this machine unless marked **(estimate)**. A player's desktop CPU is likely faster per core (see "What the cloud cannot tell").

## Where a frame goes now

### Ordinary play and the benchmark's scenarios (desktop settings, native on)

ms a tick (the simulation) or ms a frame (everything else), main thread. The fixed clock runs one tick a drawn frame.

| | 1p near (no foes) | 1p far (12 foes) | 4p apart equal (48 foes, 4 views) |
|---|---|---|---|
| **the tick** | **1.63** | **2.96** | **8.99** |
| of it: bodies | 0.44 | 1.30 | 4.75 |
| Projectiles (hit pass; of it the kernel) | 0.23 (0.07; 0.01) | 0.45 (0.29; 0.04) | 1.64 (1.41; 0.08) |
| Spells | 0.13 | 0.27 | 0.98 |
| Flow, Cover, Combat, the rest | 0.85 | 0.94 | 1.62 |
| **Feel, a frame** | **4.42** | **4.84** | **8.93** |
| of it: camera and split | 0.37 | 0.38 | 2.05 |
| spectacle (motes, stirs, mist) | 1.65 | 1.69 | 3.20 |
| cover | 1.41 | 1.59 | 1.81 |
| rooms and sound | 0.55 | 0.54 | 0.65 |
| markers, flashes, beams, carriers, statuses, labels | 0.44 | 0.64 | 1.21 |
| the light grid's fill (reported on its own; not checked whether it is inside Feel's total) | 0.20 | 0.25 | 1.69 |
| bodies' looks (`Tick._process`) | 0.25 | 0.48 | 1.39 |
| shots' drawing (`ProjectileManager._process`) | 0.08 | 0.29 | 0.75 |
| HUD panels | 0.33 | 0.34 | 0.50 |
| **scripts a frame, total** (the profile's, less its runner) | **7.1** | **9.6** | **22.1** |
| draw calls, primitives a frame | 44, 5.8k | 91, 18k | 316, 94k |
| canvas items shown; mote rows drawn (alive) | 318; 2.5k (56%) | 419; 8.5k (23%) | 1,659; 34k (28%) in 218 mote MultiMeshes |

Whole biomes played by bots (tick_hash, 11,500 ticks each, most of them walking between fights) average **1.01 ms a tick at 1 player and 1.42 ms at 4**.

What this says:

- **With one player, Feel costs about three times the tick.** With four players in four fights the two are about equal (9 ms each), and Feel's per-view parts grow with the views: the camera and split go from 0.4 to 2.0 ms, the spectacle from 1.7 to 3.2.
- **The bodies are half the tick once foes are awake:** 4.75 of 8.99 ms in the 4-player fight. Inside a body's step (below), an awake foe is about 60 us a tick and a wizard about 210.
- **The 4-player fight already needs 22 ms of scripts a frame on this machine,** before the renderer and the GPU. That is over the 16.7 ms a 60 fps frame has.

### The stress crowds (headless, real clock)

| ms a tick, or a frame | web: 100 foes, 1,000 shots | web, native off | desktop: 200 foes, 6,000 shots | desktop, native off |
|---|---|---|---|---|
| **the tick** | **11.57** | **20.61** | **24.92** | **58.20** |
| bodies | 5.71 | 8.59 | 11.44 | 27.29 |
| Projectiles | 3.95 | 9.66 | 10.74 | 27.44 |
| of it: the hit pass (of it: the kernel) | 3.81 (0.74) | 9.29 | 10.47 (1.73) | 25.91 |
| hand-backs to GDScript a tick | 36 | | 129 | |
| Spells | 0.82 | 1.00 | 1.11 | 1.33 |
| Cover, Flow, Combat, the rest | 1.09 | 1.36 | 1.64 | 2.14 |
| **Feel, a frame** | **4.11** | 4.30 | **5.54** | 5.75 |
| bodies' looks | 2.11 | 2.15 | 3.61 | 4.16 |
| shots' drawing | 0.53 | 7.67 | 1.17 | 32.42 |
| HUD panels | 0.46 | 0.48 | 0.49 | 0.51 |
| ticks a drawn frame (measured) | 2.28 | 3.00 | 3.00 | 3.00 |
| **frame (mean, p95)** | **38.8, 61.7** | 82.6, 104.0 | **103.9, 127.3** | 247.9, 301.0 |
| nodes in the tree | 2,725 | | 4,276 | |
| draw calls a frame (the WASM run, peak) | 461 | | | |

### What a hit costs after the kernel found it (the hot events, `--profile-signals`)

ms a tick, the run's frames divided by its ticks a frame. Each listener runs inside the hit pass, so inside the tick.

| Listener | web stress | desktop stress | us a call (web, desktop) |
|---|---|---|---|
| `projectile_impact` → Feel's `_on_projectile_impact` (a hit's look) | 1.07 | 2.59 | 27, 16 |
| `projectile_hit` → Combat's `_on_projectile_hit` | 1.00 | 1.57 | 35, 13 |
| `damage_dealt` → Feel's `_on_damage_dealt` | 0.32 | 0.37 | 54, 48 |
| the other hit listeners (Spells, spectacle, mouths, Combat's impact, ...) | 0.25 | 0.80 | 1 to 3 each |
| **all the hit listeners** | **about 2.6** | **about 5.3** | |
| the hand-backs and the GDScript of the pass besides | about 0.5 to 1 | about 3.4 to 4.7 | |

There are about 39 impacts and 29 hits a tick in the web stress, and 165 and 124 in the desktop stress. **Feel's share, about 1.4 ms a tick (web) and 3 ms (desktop), is view work running inside the simulation's tick.**

### Inside a body's step (the timers; the 4p apart equal fight, 600 ticks)

| Part, ms a tick | the 4 wizards | the foes (about 65 bodies stepped a tick) |
|---|---|---|
| the controller's think | 0.11 | **1.57** |
| of it: perceive (read the staffs 0.11, line of fire 0.42, ground 0.05, threats and harm 0.15, team board and attack 0.04) | | 0.76 |
| decide | | 0.34 |
| steer off harm | | 0.29 |
| chase | | 0.15 |
| track the target | | 0.12 |
| the caster's step (`Caster.step`: place sent, casts) | **0.44** | 0.67 |
| the Mover's step | 0.06 | 0.33 |
| the rest of the step (health, hurtbox, inventory, holds) | 0.12 | 0.54 |
| the move (`Actor.move`: the walk kernel, room, touches) | 0.10 | 0.82 |
| **a body, us a tick** | **about 210** | **about 60** |

Foes think every third tick (`THINK_EVERY`): 24 thinks a tick in this fight. The web stress's imps give the same shape: 37 thinks a tick, of which 5 perceive and decide, at about 240 us each. A wizard's caster step is about 110 us. That is Spells' runtime for built staffs, the largest single part of a wizard.

Nobody counted GDScript calls one by one. At the 0.1 us a call that tonight's sessions measured, a foe's 60 us is the cost of about 600 calls a tick **(estimate)**. That is what "spread thinly" means: no one function holds the time.

### What the web pays (the WASM export in Chromium, one thread)

| ms a tick | x86 headless, native on | WASM, render loop off | ratio |
|---|---|---|---|
| the tick | 11.57 | 18.47 | 1.60 |
| bodies | 5.71 | 8.04 | 1.41 |
| Projectiles | 3.95 | 6.89 | 1.74 |
| Spells | 0.82 | 1.99 | 2.43 |

With the render loop off, the web frame is 79 ms at 3 ticks a frame; process scripts take 11.1 ms of it. **The web pays about 1.6 times the desktop for the same simulation on the same machine, and has no threads,** so nothing that moves work to a thread helps it. The web build does have the native module (`wasm32`, no threads). Drawn with SwiftShader, its frames say nothing about a real browser's GPU.

### How a slow frame becomes slower: the catch-up model

The frames service runs the ticks that real time says are due, at most 3 a drawn frame. With a tick of S ms and a frame's other work of V ms, a frame running f ticks takes F = f·S + V. At real speed f = F / 16.7, so **F = V / (1 − S / 16.7)** while that is above 16.7 ms. **(Estimate: a model, checked against the stress runs only roughly. It is a floor: slow frames bunch, so the measured runs are worse, at 2.3 ticks a frame in the web stress against the model's 1.4.)**

For the 4p apart equal fight on this machine (S = 9.0; V = 11.6, the frame's scripts less the tick and the runner, without the renderer): F = 25 ms, 40 fps. **The same frame with half the tick (S = 4.5) fits one tick a frame: 16.1 ms, 60 fps.** So each ms off the tick is worth about 2 ms of frame here. Cutting the view is worth one for one, until the frame fits the 16.7 ms.

## What the cloud cannot tell, and what the owner should run

These machines have no GPU, no Vulkan or Direct3D 12, and not the owner's CPU. So they cannot tell:

- **the GPU's time** for 316 draw calls, 94k primitives and 104k mote instances (only 28% of them alive) in the 4-player fight; whether the motes' dead rows, the 1,659 canvas items or the shaders cost anything on a real GPU;
- **the renderer's CPU time** with the Mobile renderer on Vulkan or Direct3D 12 (llvmpipe's 60 to 140 ms a frame here is the software rasteriser);
- **the owner's CPU**: how much faster a core is than these cloud vCPUs (a desktop core is often 1.3 to 2 times faster single-threaded **(estimate)**), and what the native thread pool gains with more cores;
- **a real browser's GPU and its WebGL cost.**

**What the owner should run** (Windows: in the game's folder, `Spellmerge.exe -- --benchmark`; the results screen and `%APPDATA%\Godot\app_userdata\Spellmerge\benchmark.txt` hold the table):

1. `Spellmerge.exe -- --benchmark`: the default scenarios. Its columns are the frame (mean, p95), the simulation's ms a frame, Feel's step, the GPU's and the renderer's ms, and the draw calls.
2. `Spellmerge.exe -- --benchmark --only="4p apart equal" --quality=each`: what the effects' rows cost there.
3. `Spellmerge.exe -- --benchmark --only="4p apart equal" --no-native`: what the native module buys on that CPU.

How to read the result: **if the GPU's column is near the frame and the sim plus Feel are well under it, the drawing is the work (change 5 below first).** If the sim plus Feel are most of the frame, changes 1 to 4 are, in the order below.

## The structural changes, ranked

Ranked by ms saved per unit of work, the 4-player fight and the stress crowds weighed together. Every saving is an **estimate** built on the measured parts named in its row; each PR measures its own.

| # | Change | Saves (estimate) | Work | Risk to the rules |
|---|---|---|---|---|
| 1 | **Hits as one batch a tick; Feel reads them in its frame** | web stress 1.5 to 2.5 ms a tick; desktop stress 4 to 6; 4p fight 0.5 to 1 | medium: 4 PRs | medium: the order hits are applied in |
| 2 | **The crowd's per-tick work in C++, on a body table** | 4p fight 2 to 2.5 ms a tick; web stress 3 to 4; desktop stress 6 to 8 | large: 6 PRs | high: native mirrors its GDScript, state ownership |
| 3 | **Feel's frame and the looks in C++ and on threads** | 4p fight 3 to 5 ms a frame; 1p 1.5 to 2 (less certain than 1 and 2) | medium to large: 5 PRs | low for determinism (view only); drawing must not change |
| 4 | **The tick on its own thread beside the drawing (desktop)** | the smaller of tick and view: about 9 ms a frame in the 4p fight; nothing on the web | very large: 8+ PRs, after 2 | high: no node read across threads; one clock |
| 5 | **The drawing batched** (bodies' sprites, mote chunks) | unknown here: decided by the owner's GPU and renderer columns | medium | low (view only) |

Together, on this machine, for the 4-player fight **(estimate)**: changes 1 to 3 take the tick from 9.0 to about 6 ms and the view from 11.6 to about 7.6 ms. The frame then fits one tick: about 13.6 ms instead of the model's 25, which is 1.8x. With change 4 on the desktop, the frame is the larger of the two, about 7.6 ms: 3.3x. On the web, changes 1 to 3 count 1.6 times over (it pays 1.6x for the same work), and the catch-up makes the frame's gain larger than the ms cut. Cutting the drawn work further is change 5, and it waits on the owner's numbers.

### 1. Hits as one batch a tick, Feel's hit looks in its frame

**Evidence.** In the web stress the kernel is 0.74 ms of the 3.81 ms hit pass; in the desktop stress, 1.73 of 10.47. The rest is GDScript: every hit sends `projectile_impact` and `projectile_hit` one by one to five to seven listeners each, about 2.6 ms a tick (web) and 5.3 (desktop), and 36 to 129 hits a tick go back to GDScript to be resolved. Feel's listeners (about 1.4 and 3 ms a tick) do view work inside the simulation's tick.

**The change.** The hit pass writes what it found into a hit table: packed arrays a tick, one row a merged hit or impact, in the order the hits are sent now. Then:

- Combat applies the table in one function, in row order;
- Spells' and the mouths' listeners read the same rows;
- Feel reads the tick's impact rows once a drawn frame, in its own step. On the desktop it hands the looks to its worker threads (`feel_jobs.gd`), and the work leaves the tick.

The kinds of hand-back that are only arithmetic (a wall end, the health ask) are answered in the kernel from a column Combat keeps: a body's health, whether it takes hits.

**Risk.** Determinism: the hits must be applied in exactly today's order, including what a listener changes in the middle of the pass (a death, a status that changes the next hit). `tick_hash.gd`'s four biomes must stay identical, native on and off. Feel must show the same thing in the same frame, and the hit shares (`hit_shares.gd`, `body_looks.gd`) count the same hits. Native: the hand-back answers in C++ need their GDScript twin and a byte test (`test_native_kernel.gd`). Allocations: the table is sized once, like the manager's slots.

**PRs.**

- (H1) the hit table and Combat applying it, the events kept as wrappers for the other listeners;
- (H2) Feel's hit, damage and death looks read from the table in its frame;
- (H3) Spells' and the others' listeners on the table, then the per-hit events removed;
- (H4) the wall-end and health-ask hand-backs answered in the kernel.

Each is measured on the stress (web and desktop) and the 4p fight.

### 2. The crowd's per-tick work in C++, on a body table

**Evidence.** Bodies are half the tick in every fight: 4.75 of 8.99 ms (4p fight), 5.71 of 11.57 (web stress), 11.44 of 24.92 (desktop stress). Each foe is a tree of about 13 script nodes and 3 or 4 sprites. Its 60 us a tick is spread over the move (0.82 ms for the foes), caster (0.67), rest of the step (0.54), Mover (0.33), steering off harm (0.29), chase (0.15) and tracking (0.12): about 2.9 of its 3.9 ms are the same small steps for every foe, every tick. The decisions (perceive and decide, 1.1 ms) are the AI's real logic and come less often.

**The change.** This is the "later" step of docs/milestones/sim-native.md, done for the foes first:

- the bodies' state that kernels read moves into structure-of-arrays columns of `Actors` (place, velocity, radius, team, flags);
- one native call a tick steps every awake foe's per-tick parts in id order: follow the plan (chase, steer, track), the Mover's velocity, the walk (`BodyKernel.walk`, already C++), the place sent to the manager and Spells. One call replaces 5 to 8 GDScript calls a foe;
- perception's rays (the line of fire, 0.42 ms, already partly `BodyKernel.wall_hit`) are asked for all the foes that perceive in a tick in one batch;
- decisions stay GDScript.

**Risk.** Native mirrors its GDScript to the bit: every part keeps its GDScript twin and a byte-for-byte test, which is the main cost of this change (see Q2). Simulation state: each column has one owner, the node's member becomes a computed property over it, and snapshots and the state hash stay the same (`test_state_declared.gd`, `test_snapshot*.gd`, `test_determinism.gd`). The order of the steps stays id order (the owner's decision 1 of 2026-11-22). Maths only through `DMath`, no fused multiply-add (`no_fma`).

**PRs.**

- (C1) the body table's columns following the nodes (DERIVED), with tests;
- (C2) the foes' Mover and move in one call for the crowd;
- (C3) chase, steer and track in it;
- (C4) the caster's place sent from it;
- (C5) perception's rays batched;
- (C6) the columns become the state, the nodes' members their views.

Each is measured on `tick_hash.gd` (1 to 4 players) and the two crowds.

### 3. Feel's frame and the looks in C++ and on threads

**Evidence.** Feel is the largest cost of ordinary play: 4.4 ms a frame with one player and no foe, three times the tick, and 8.9 ms in the 4p fight. Its parts that grow with the views (the camera and split, 0.4 to 2.0 ms; the spectacle, 1.7 to 3.2) are per-view loops in GDScript. The bodies' looks are 1.4 ms (4p fight) and 3.6 ms (desktop stress). The motes', flashes', stirs' and mist's hot loops are already C++ (#987, `MoteKernel`). What is left is the GDScript around them.

**The change.**

- First, a profile of Feel's frame by function: the spectacle, the cover, the camera and split. The section timers here stop at Feel's own parts; this PR finds which loops hold the time.
- Then the largest loops move to C++ and to `feel_jobs.gd`'s worker threads on the desktop: the per-view work (a view's cull and its mote chunks), the cover's look, the bodies' looks over the actor table (poses from the body's state, one call for all bodies).

**Risk.** Feel is view only, so determinism is untouched; the state hash never reads it. "Drawing never changes what is seen": each move compares frames pixel for pixel (`biome_frames.gd --held-shot`, `--gpu-compare`), and the native twin rule holds (`test_native_feel.gd`). Allocations: Feel's slots are sized once.

**PRs.**

- (F1) Feel's profile by function, at 1 and 4 views;
- (F2) the per-view loops;
- (F3) the cover's look;
- (F4) the bodies' looks in one call;
- (F5) on the workers.

The order after F1 follows its profile. Without F1 the saving is the least certain of the five changes.

### 4. The tick on its own thread, beside the drawing (desktop only)

**Evidence.** On the main thread today the frame is the tick plus the view: 9.0 + 11.6 ms in the 4p fight. On a thread of its own, the tick would run while the main thread draws the last tick's state, and the frame becomes the larger of the two. That is about 11.6 ms instead of 20.6 at one tick a frame, and the catch-up spiral of the model above goes away while the tick fits its 16.7 ms. On the web nothing changes: it has no threads.

**The change.** This is sim-native's "later" goal. Nothing the simulation writes lives on a node: the body table (change 2) for the bodies, the manager's arrays (already) for the shots, the other areas' state likewise. At the tick's end the view gets a copy of what it draws (double-buffered), and the nodes are set from it on the main thread.

**Risk.** It touches every simulation area. Godot's scene tree is not thread-safe, so the tick may touch no node. "One clock" holds, since the tick still steps in its written order. Determinism holds, since the code that steps is the same. Online play is unchanged: input frames go in at the tick's start. **This is the largest change in this file**, and it is worth doing only after 2, with the owner's decision (Q3).

**PRs** (after C6): one an area for its state off the nodes (Spells, Flow, Cover, Combat, Items, Rewards), then the view's copy, then the thread.

### 5. The drawing batched

**Evidence (counts only).** The 4p fight draws 1,659 canvas items, 316 draw calls and 94k primitives a frame. Its 218 mote MultiMeshes hold 104k instances, of which 28% are alive. The bodies are 361 Sprite2D and 69 faces. What these cost on a GPU, and in the Mobile renderer's CPU, is not measurable here.

**The change**, if the owner's benchmark says the GPU or the renderer is the frame:

- the bodies drawn in one MultiMesh per layer (body, face, outline) from the looks' rows, in place of a Sprite2D per part;
- the motes' chunks packed so that dead rows are not drawn: fewer chunks per view, and the views share them.

**Risk.** View only. The look must not change: pixel compares, the Smooth rule (whole pixels, the frames between looks), and draw order where bodies overlap.

### What does not make the top five

- **Thinking less often** (THINK_EVERY 3 to 6, or perceiving less often): a large, cheap saving (the think is 1.57 ms of the 4p fight) that changes how foes play. That is the owner's call (Q4).
- **Fewer nodes per body for its own sake:** 186 nodes process (in the 4p fight), out of 4,230. The nodes cost little in themselves; the calls between them do, and change 2 removes those.
- **The physics server:** the engine's own time a frame is about 0.9 ms headless (physics server, message queue, frees), and the game does not use the physics server for its bodies or shots.
- **The renderer setting:** the desktop already draws with Mobile (Vulkan or Direct3D 12) and the web with Compatibility. Whether Mobile beats Compatibility on the owner's PC is an extra row of the owner's benchmark (`--rendering-method gl_compatibility`), not a change.

## Open questions for the owner

1. **Which is the frame on your PC?** Run `Spellmerge.exe -- --benchmark` and send the table (or its screenshot). If the GPU's ms is most of the frame, the drawing (change 5) comes first. If the sim plus Feel are most of it, changes 1 to 3 do.
2. **Must every kernel keep its GDScript twin?** The web build has the native module too, so the GDScript runs only with `--no-native`, in the editor without a built module, and in the byte-for-byte tests. Keeping a twin roughly doubles the work of changes 2 to 4. Dropping it for the new kernels (C++ only, the same code on the web) would make them about half the work, but loses the fallback and the reference.
3. **The tick on its own thread (change 4):** worth its size (8+ PRs touching every simulation area) for the desktop only? It is the one change here that gives the desktop about 1.8x on its own.
4. **May the game change for speed?** For example, foes perceiving and deciding less often, or fewer of each hit's looks in a crowd. Each would be a measured trade, recorded as a new baseline, never silent.
5. **The web:** keep it on one thread, or try a threaded web build? A threaded build needs cross-origin isolation headers from the host, which itch.io offers as a setting. Or lower its caps (100 foes, 1,000 shots) to fit the 1.6x it pays?
