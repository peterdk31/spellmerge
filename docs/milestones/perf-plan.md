# Performance plan: where a frame goes, and what would make the game 2x faster

**Status (2026-11-28): a research report, proposed.** Nothing here is built. The owner asked for far more than the few percent a targeted cut now gives (2026-11-28: "Improve performance! ... More c++ maybe? Or multimesh or any other tricks."). This file does three things:

- it measures the frame end to end on main at 7cecf8fe (#984 to #992 merged);
- it ranks the structural changes that would cut the frame most;
- it splits each change into PRs.

The decisions that are the owner's are at the end ("Open questions for the owner").

## The answer in short

- **In ordinary play the drawn frame is the cost, not the simulation.**
  - One player with no foe: the tick is 1.6 ms, and Feel (everything drawn or heard only) is 4.4 ms a frame. Whole biomes played by bots average 1.0 ms a tick.
  - In fights the tick catches up. In the 4-player benchmark fight the tick is 9.0 ms and Feel 8.9 ms.
  - In the stress crowds, natively on x86, the tick is 11.6 ms at the web's caps (100 foes, 1,000 shots) and 24.9 ms at the desktop's (200 foes, 6,000 shots). The real web build, in WASM, pays 18.5 ms for the first.
- **Once foes are awake, two things are most of the tick.**
  - The foes' bodies are half of it.
  - The GDScript part of the hit pass is the next largest: the work done for each hit after the C++ kernel has found it. The kernel itself is 0.7 of the 3.8 ms hit pass in the web stress, and 1.7 of 10.5 in the desktop stress.
- **Over budget, the frame grows by more than the tick does.**
  - Godot runs up to 3 ticks in one drawn frame to keep up with real time (`max_physics_steps_per_frame=3`), so a slow frame makes the next one slower.
  - In the 4-player fight, each ms cut from the tick saves about 2 ms of frame (the model is below).
- **What the changes would give (estimates, CPU ms of the simulation and the scripts a frame, before the renderer and the GPU):**
  - Feel's frame in C++ and on threads, the crowd's per-tick work in C++, and hits handled as one batch: about 1.7x in the 4-player fight.
  - The tick on a thread of its own beside the drawing (desktop only): about 3x.
  - These are ratios of ms, not of fps. The game is capped at 60 fps, and the renderer's and the GPU's share is unknown until the owner runs the benchmark.
  - The web gets the first three changes, but not the thread.
- **5x is not shown by these numbers.** It would need decisions about the game itself (how often foes think, how much each hit shows) and the GPU's numbers from the owner's PC, which no cloud machine can give.

## How this was measured

**This container.**

- 4 cloud vCPUs, Linux, Godot 4.7.2, with the native module built from main (`ci/build/build.sh --quick`, `ci/build/native.sh linux`).
- No GPU. A drawn run uses llvmpipe, Mesa's software rasteriser.
- No Vulkan, so `--rendering-method mobile` falls back to OpenGL.
- So every GPU time and every renderer CPU time from this machine is meaningless and is not used below. Only the draw-call and primitive counts are kept.

**The runs.**

- **Stress** (`tests/benchmark/stress.gd -- --only=web|desktop --profile [--no-native]`): headless, on the real clock, natively on x86, at the web's or the desktop's caps. The hot events' listeners were timed in separate runs (`--profile-signals`). Those runs' proxies add a cost of their own: their hit pass is 10 to 15% slower.
- **The shipped benchmark's scenarios** (`tests/benchmark/play_frames.gd -- --only="1p near,1p far,4p apart equal" --profile --census`, under `xvfb-run`): the scenarios `Spellmerge.exe -- --benchmark` plays. They run on the fixed clock, one tick a drawn frame, at the desktop settings with the effects at high.
- **Whole biomes** (`tests/benchmark/tick_hash.gd -- --players=1|4 --seed=11 --sturdy --profile-steps`): headless. This runner does not read `--no-native`.
- **The web build** (`ci/build/build.sh --web`, then `PYTHONPATH=ci python3 -m smbot.websmoke build/web --page-args=--stress`): the WASM export in headless Chromium, on one thread, drawn with SwiftShader. Its "render loop off" scenario is pure game logic.
- **Section timers** inside a body's step and the AI's think: a patch to `actor.gd`, `brain.gd` and `tick.gd`, never committed. They ran in the "4p apart equal" fight. The timers add to what they time: their parts sum to a little more than the whole (the think's parts are 1.66 ms against a measured think of 1.57). Read them as shares.

Every number is ms on this machine unless marked **(estimate)**. A player's desktop CPU is likely faster per core (see "What the cloud cannot tell").

## Where a frame goes now

### Ordinary play and the benchmark's scenarios (desktop settings, native on)

The fixed clock runs one tick a drawn frame. All on the main thread.

**The tick, ms a tick:**

| | 1p near (no foes) | 1p far (12 foes) | 4p apart equal (48 foes, 4 views) |
|---|---|---|---|
| **the tick** (`Tick.STEPS`) | **1.63** | **2.96** | **8.99** |
| bodies | 0.44 | 1.30 | 4.75 |
| Flow | 0.46 | 0.46 | 0.63 |
| Projectiles (hit pass; of it the kernel) | 0.23 (0.07; 0.01) | 0.45 (0.29; 0.04) | 1.64 (1.41; 0.08) |
| Spells | 0.13 | 0.27 | 0.98 |
| Cover, Combat, the rest | 0.38 | 0.48 | 0.99 |

**Feel's step, ms a frame (its parts sum to its total):**

| | 1p near | 1p far | 4p apart equal |
|---|---|---|---|
| **Feel** | **4.42** | **4.84** | **8.93** |
| camera and split | 0.37 | 0.38 | 2.05 |
| spectacle (motes, stirs, mist) | 1.65 | 1.69 | 3.20 |
| cover | 1.41 | 1.59 | 1.81 |
| rooms and sound | 0.55 | 0.54 | 0.65 |
| markers, flashes, beams, carriers, statuses, labels | 0.44 | 0.64 | 1.21 |

**The other scripts a frame, and what is drawn:**

| | 1p near | 1p far | 4p apart equal |
|---|---|---|---|
| bodies' looks (`Tick._process`) | 0.25 | 0.48 | 1.39 |
| shots' drawing (`ProjectileManager._process`) | 0.08 | 0.29 | 0.75 |
| HUD panels | 0.33 | 0.34 | 0.50 |
| the rest (audio, coins, doors, ...) | about 0.3 | about 0.3 | about 0.3 |
| **scripts a frame, total** (the profile's, less the benchmark's runner) | **7.1** | **9.6** | **22.1** |
| draw calls, primitives a frame | 44, 5.8k | 91, 18k | 316, 94k |
| canvas items shown | 318 | 419 | 1,659 |
| mote rows drawn (alive) | 2.5k (56%) | 8.5k (23%) | 34k (28%), in 218 mote MultiMeshes of 104k instances |

The "total" row comes from the tree profile, so it does not add up row by row:

- it counts Feel as 8.71 ms (4p), its own clock against the runner's 8.93;
- it holds the tick as `fixed_steps`: 10.43 ms in the 4p fight, against the 8.99 of the tick's steps. The 1.44 ms between them is the benchmark's own work in the same call, mostly its state hash spread over the ticks, which it measures at 1.13 ms a tick there. It is not part of the game.

The light grid's fill (0.20, 0.25 and 1.69 ms) is reported apart by the runner and is not in Feel's parts. Its time is in the "total" row.

Whole biomes played by bots (tick_hash, about 11,500 ticks each, most of them walking between fights) average **1.01 ms a tick at 1 player and 1.42 ms at 4**.

What this says:

- **In ordinary play Feel is the cost.** With one player and no foe it is 2.7 times the tick (4.4 against 1.6 ms), and in whole biomes about 4 times the average tick.
- **Feel's per-view parts grow with the views.** With four players in four fights, Feel's step and the tick are about equal (9 ms each). The camera and split go from 0.4 to 2.0 ms, the spectacle from 1.7 to 3.2.
- **The bodies are half the tick once foes are awake:** 4.75 of 8.99 ms in the 4-player fight.
- **Flow is the largest step of a one-player tick** with no foe awake (0.46 ms, the rooms' waking). No change below touches it; it is small next to Feel.
- **The 4-player fight already needs about 20 ms of the game's scripts a frame on this machine,** before the renderer and the GPU. A 60 fps frame has 16.7.

### The stress crowds (headless, real clock, x86)

| ms a tick, or a frame | web's caps: 100 foes, 1,000 shots | the same, native off | desktop's caps: 200 foes, 6,000 shots | the same, native off |
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

### What a hit costs after the kernel found it (the hot events)

Measured in the `--profile-signals` runs, whose ticks are a little slower: a hit pass of 4.40 ms (web caps) and 11.73 (desktop caps), against 3.81 and 10.47 in the plain runs. The listeners ran at 2.6 ticks a frame (web caps) and 3 (desktop caps); the profile's ms a frame are divided by those. Each listener runs inside the hit pass, so inside the tick.

| Listener, ms a tick | web's caps | desktop's caps | us a call (web, desktop caps) |
|---|---|---|---|
| `projectile_impact` → Feel's `_on_projectile_impact` (a hit's look) | 1.07 | 2.59 | 27, 16 |
| `projectile_hit` → Combat's `_on_projectile_hit` | 1.00 | 1.57 | 35, 13 |
| `damage_dealt` → Feel's `_on_damage_dealt` | 0.32 | 0.37 | 54, 48 |
| the other hit listeners (Spells, spectacle, mouths, Combat's impact, ...) | 0.25 | 0.80 | 1 to 3 each |
| **all the hit listeners** | **2.64** | **5.33** | |
| the hit pass less its kernel and listeners (the hand-backs, the sending) | 0.93 | 4.64 | |

- There are about 39 impacts and 29 hits a tick at the web's caps, and 165 and 124 at the desktop's.
- **Feel's share (1.4 ms a tick at the web's caps, 3.0 at the desktop's) is view work running inside the simulation's tick.**
- The listeners were not profiled in the 4-player fight. There the hit pass is 1.41 ms, with 0.08 in its kernel.

### Inside a body's step (the timers; the 4p apart equal fight, 600 ticks)

| Part, ms a tick | the 4 wizards | the other bodies stepped (about 65 a tick) |
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

Reading the table:

- **The 65 bodies stepped are more than the 48 foes the fight holds.** The rest are other bodies that step: props that keep time, summons and the like (not broken down). So a foe is between 60 us (spread over all 65) and 80 us a tick (all of it on the 48).
- **The think runs every third tick** (`THINK_EVERY`): 24 thinks a tick here. The steering, chase and tracking are inside the think, so they too run on a third of the ticks. The table's figures are averages over all ticks.
- **A wizard's caster step is about 110 us,** the largest single part of a wizard. That is Spells' runtime for built staffs.

Nobody counted GDScript calls one by one. Tonight's performance PRs (#984 to #992) reported a GDScript call at about 0.1 us and a signal sent at about 0.35 us; this report did not measure them again. At that rate, a foe's 60 us is the cost of about 600 calls a tick **(estimate)**. That is what "spread thinly" means: no one function holds the time.

### What the web pays (the WASM export in Chromium, one thread)

| ms a tick, web's caps | x86 headless, native on | WASM, render loop off | ratio |
|---|---|---|---|
| the tick | 11.57 | 18.47 | 1.60 |
| bodies | 5.71 | 8.04 | 1.41 |
| Projectiles | 3.95 | 6.89 | 1.74 |
| Spells | 0.82 | 1.99 | 2.41 |

- With the render loop off, the web frame is 79 ms at 3 ticks a frame; process scripts take 11.1 ms of it.
- **The web pays about 1.6 times the desktop for the same simulation on the same machine, and it has no threads,** so nothing that moves work to a thread helps it.
- The web build does have the native module (`wasm32`, no threads).
- Drawn with SwiftShader, its frames say nothing about a real browser's GPU.
- The web was not run in the benchmark's fights.

### How a slow frame becomes slower: the catch-up model

The model **(estimate: a model, checked against the stress runs only roughly)**:

- The frames service runs the ticks that real time says are due, at most 3 a drawn frame.
- Take S as the tick's ms and V as the frame's other work. A frame running f ticks takes F = f·S + V.
- At real speed f = F / 16.7, so **F = V / (1 − S / 16.7)** while F is above 16.7 ms. Below that, F = S + V.
- The model is a floor. Slow frames bunch, so the measured runs are worse: the web's caps ran 2.3 ticks a frame against the model's 1.4.

For the 4p apart equal fight on this machine, before the renderer and the GPU:

- S = 8.99, the tick's steps.
- V = 11.8: Feel 8.93, the bodies' looks 1.39, the shots' drawing 0.75, the HUD 0.50 and the rest about 0.3.

| | S | V | F | fps (60 at most) |
|---|---|---|---|---|
| today | 9.0 | 11.8 | 25.6 | 39 |
| half the tick | 4.5 | 11.8 | 16.3 (one tick a frame) | 60 if the renderer fits in the 0.4 ms left |
| changes 1 to 3 (below, estimate) | 6.5 | 8.3 | 14.8 | 60 if the renderer fits in the 1.9 ms left |
| and change 4 (desktop; estimate) | 6.5 | 8.3 | 8.3 (the larger) | 60 with 8 ms left for the renderer |

So in this fight each ms off the tick is worth about 2 ms of frame, until the frame fits.

## What the cloud cannot tell, and what the owner should run

These machines have no GPU, no Vulkan or Direct3D 12, and not the owner's CPU. So they cannot tell:

- **the GPU's time** in the 4-player fight: 316 draw calls, 94k primitives, and 34k mote rows drawn of which 28% are alive. Nor whether the 1,659 canvas items or the shaders cost anything on a real GPU.
- **the renderer's CPU time** with the Mobile renderer on Vulkan or Direct3D 12. Here llvmpipe's 13 to 140 ms a frame is the software rasteriser.
- **the owner's CPU**: how much faster a core is than these cloud vCPUs (a desktop core is often 1.3 to 2 times faster single-threaded **(estimate)**), and what the native thread pool gains with more cores.
- **a real browser's GPU and its WebGL cost.**

**What the owner should run.** On Windows, in the game's folder:

1. `Spellmerge.exe -- --benchmark`: the default scenarios. Its columns are the frame (mean, p95), the simulation's ms a frame, Feel's step, the GPU's and the renderer's ms, and the draw calls.
2. `Spellmerge.exe -- --benchmark --only="4p apart equal" --quality=each`: what each row of the "Effects" setting costs there.
3. `Spellmerge.exe -- --benchmark --only="4p apart equal" --no-native`: what the native module buys on that CPU.

The results screen shows the table, and `%APPDATA%\Godot\app_userdata\Spellmerge\benchmark.txt` keeps it.

**How to read the result:**

- If the GPU's column is near the frame, and the simulation plus Feel are well under it, the drawing is the work: change 5 first.
- If the simulation plus Feel are most of the frame, changes 1 to 4 are the work, in the order below.

## The structural changes, ranked

**How they are ranked.**

- The first criterion is ms saved per PR in the 4-player fight, the heaviest scenario the shipped benchmark plays.
- The stress crowds come second.
- Then dependency: change 4 needs change 2.
- Change 5 cannot be ranked until the owner's GPU numbers arrive.

Every saving below is an **estimate** built on the measured parts named in its section; each PR measures its own.

| # | Change | Saves in the 4p fight (estimate) | Saves in the stress crowds (estimate) | Work | Risk to the rules |
|---|---|---|---|---|---|
| 1 | **Feel's frame and the looks in C++ and on threads** | 3 to 4 ms a frame (1p: 1.5 to 2); the least certain, F1 measures it first | 1 to 2 ms a frame | medium to large: 5 PRs | low for determinism (view only); drawing must not change |
| 2 | **The crowd's per-tick work in C++, on a body table** | 1.5 to 2 ms a tick | web's caps 2 to 2.5; desktop's 4 to 5 | large: 6 PRs | high: native mirrors its GDScript; state ownership |
| 3 | **Hits as one batch a tick; Feel reads them in its frame** | about 0.5 ms a tick (no listener profile there) | out of the tick: web's caps 2 to 2.5, desktop's 5 to 6; of it moved to the frame: 1.4 and 3.0 | medium: 4 PRs | medium: the order hits are applied in |
| 4 | **The tick on its own thread beside the drawing (desktop)** | the smaller of tick and view: 6.5 to 9 ms a frame; nothing on the web | the same rule | very large: 8+ PRs, after 2 | high: no node read across threads |
| 5 | **The drawing batched** (bodies' sprites, mote chunks) | unknown here | unknown here | medium | low (view only) |

Per PR in the 4p fight that is roughly: change 1 0.6 to 0.8 ms, change 2 0.3, change 3 0.1. In the crowds, change 3 is about 0.5 to 1.5 ms a PR, the best there.

**Changes 1 and 3 overlap in Feel's hit looks.** Change 3 moves them out of the tick into Feel's frame. Change 1's F-PRs then make them cheaper there, and on the desktop take them off the main thread. The combined row of the model's table counts them once: in the view's 8.3 ms.

**One-player play gains from change 1 only.** Changes 2 and 3 cut the tick, which is 1.0 to 1.6 ms there; the bodies are 0.44 ms and the hit pass 0.07.

### 1. Feel's frame and the looks in C++ and on threads

**Evidence.**

- Feel is the largest cost of ordinary play: 4.4 ms a frame with one player and no foe, and 8.9 ms in the 4p fight.
- Its parts that grow with the views are per-view loops in GDScript: the camera and split go from 0.4 to 2.0 ms, the spectacle from 1.7 to 3.2.
- The bodies' looks are 1.4 ms in the 4p fight and 3.6 ms at the desktop's caps.
- The motes', flashes', stirs' and mist's hot loops are already C++ (#987, `MoteKernel`). What is left is the GDScript around them, and nobody has yet measured which loops hold it.

**The change.**

- First, a profile of Feel's frame by function: the spectacle, the cover, the camera and split. The timers here stop at Feel's own parts.
- Then the largest loops move to C++, and to `feel_jobs.gd`'s worker threads on the desktop: the per-view work (a view's cull and its mote chunks), the cover's look, and the bodies' looks over the actor table (poses from the body's state, one call for all bodies).
- The saving assumes that about half of Feel's GDScript and of the looks goes **(estimate)**. F1 replaces that guess with a measurement.

**Risk.**

- Feel is view only, so determinism is untouched; the state hash never reads it.
- Drawing must not change what is seen. Each move compares frames pixel for pixel (`biome_frames.gd --held-shot`, `--gpu-compare`).
- The native twin rule holds (`test_native_feel.gd`).
- No allocations a frame: Feel's slots are sized once.

**PRs.**

- (F1) Feel's profile by function, at 1 and 4 views;
- (F2) the per-view loops;
- (F3) the cover's look;
- (F4) the bodies' looks in one call;
- (F5) on the workers.

The order after F1 follows its profile.

**F1's profile (2026-11-28, `play_frames.gd`, desktop settings, xvfb; ms a frame, 1 view and 4).**

- **The per-view cost was the light's readers' copies** (`view_readers.gd`), 0.43 and 6.20 ms: each copy for the third and fourth views followed twice a frame (in Feel's step and at the pre-draw, the second outside Feel's timer), and every uniform of every reader's material read and copied to each view's material a frame. It is node and shader-parameter work, which the module may not do (`native/build_profile.json` holds no canvas class), so it stays GDScript. F2 made it follow once, and only what changed: 0.18 and 2.97 ms (Feel's "camera and split" 2.13 to 0.88 at 4 views).
- What is left at 4 views: the light's grid at the pre-draw (2.65, already native), the readers' uniforms (1.9: 1,760 reads a frame, 120 changed), the cover's step (1.5 to 1.8 at any number of views), the bodies' looks (0.28 and 1.41), and in the spectacle the shadows (0.24, 0.75), the mists (0.17, 0.49), the stirs (0.09, 0.45), the source motes (0.23, 0.34), the motes' step (0.16, 0.40), the floor marks (0.05, 0.33) and the blockers (0.27).
- **Next, by that profile:** (F3) the cover's look; (F2b) the readers' uniforms set where they are set (the light's numbers handed to each view's material by the light itself, not read back a frame); (F4) the bodies' looks in one call; (F5) on the workers.

### 2. The crowd's per-tick work in C++, on a body table

**Evidence.**

- Bodies are half the tick in every fight: 4.75 of 8.99 ms in the 4p fight, 5.71 of 11.57 at the web's caps, 11.44 of 24.92 at the desktop's.
- Each foe is a tree of about 13 script nodes and 3 or 4 sprites.
- What C2 to C5 would cover, in the 4p fight:

| PR | Measured parts it replaces (ms a tick) |
|---|---|
| C2 | the move 0.82, the Mover 0.33 |
| C3 | chase 0.15, steering off harm 0.29, tracking 0.12 |
| C4 | the caster's place sent: part of its 0.67, not timed apart (0.3 assumed) |
| C5 | the line of fire's rays: part of their 0.42 |

That is about 2.0 to 2.3 ms covered. Neither the decisions (decide 0.34, the rest of perceive) nor the rest of the step (health, hurtbox, inventory, holds: 0.54) are covered.

**The change.** This is the "later" step of docs/milestones/sim-native.md, done for the foes first:

- The bodies' state that kernels read moves into structure-of-arrays columns of `Actors`: place, velocity, radius, team, flags.
- One native call a tick steps the covered parts of every awake foe, in id order.
- Perception's rays are asked for all the foes that perceive in a tick, in one batch.
- Decisions stay GDScript.
- The saving assumes the C++ is 5 to 10 times faster than the GDScript it replaces **(estimate; the native kernels of tonight's PRs gained about that on their loops)**: 1.5 to 2 of the 2.0 to 2.3 ms.
- At the crowds' caps, the same share of the bodies (about 40%) gives the figures in the table **(estimate: the crowds' bodies were not broken down)**.

**Risk.**

- Native mirrors its GDScript to the bit. Every part keeps its GDScript twin and a byte-for-byte test, which is this change's main cost (Q2).
- Simulation state: each column has one owner, and the node's member becomes a computed property over it.
- Snapshots and the state hash stay the same (`test_state_declared.gd`, `test_snapshot*.gd`, `test_determinism.gd`).
- The order of the steps stays id order (the owner's decision 1 of 2026-11-22).
- Maths go only through `DMath`, with no fused multiply-add (`no_fma`).

**PRs.**

- (C1) the body table's columns, following the nodes (DERIVED), with tests;
- (C2) to (C5) as in the table above;
- (C6) the columns become the state, and the nodes' members their views.

Each is measured on `tick_hash.gd` (1 to 4 players) and both crowds.

**Built (C1, 2026-11-28): the body table's columns, following the nodes.**

- `Actors.places`, `velocities`, `radii`, `body_flags` (`FLAG_BODY`, `FLAG_DOWN`, `FLAG_DYING`, `FLAG_SPAWNING`, `FLAG_FALLING`) by actor id, beside `teams()`. DERIVED: the hash, the snapshots and the game are as they were (the whole game's state hash every tick, 4p seed 11, 12,423 ticks: identical to main).
- The body is the one writer (core/actors/README.md, "The body table"): flags and radius where they change, so always current; place and velocity after its own tick, at a swap, and for every open body as the bodies' step starts (`Actor.gather_rows`, the Tick's).
- Cost: the gather alone 0.064 ms a tick at 112 bodies (web stress), 0.083 at 144 (desktop stress), timed by a patch kept out of the tree; a call a body (the first try) cost 0.20 to 0.25. Main against branch, alternating: `tick_hash` bodies +0.01 to +0.04 ms (1p and 4p, two runs each); web stress tick within the swing (-0.27 to +0.31 ms over three runs); desktop stress bodies +0.25 ms on a 21 ms tick over four quiet runs (9.88 against 10.13, each run's spread ±0.4).
- What it showed for the next steps:
  - **C2** gathers the rows in its own native call (it reads the bodies anyway), and the GDScript gather goes.
  - A kernel reads, for a body after it in id order, its row as the step started; the live node differs only where another body's step set its place or velocity mid-step other than by a swap (none known today). C3's chase and steering read other bodies: they keep that in mind.
  - **C6:** the nodes' places are written in about ten places outside the actor (Flow's placements, the map's teleport, room contents, Entities' decoys, the prop yard, the snapshot's restore of a node's position); each writes the column once the column is the state, and the node's `position` becomes the column's view, set after the tick.
  - **Change 4** needs every simulation read of a body's node off it: about 110 reads of `global_position` in the simulation folders (56 in the AI, 32 in the actor kit), besides the members C6 moves.

### 3. Hits as one batch a tick, Feel's hit looks in its frame

**Evidence.**

- At the web's caps the kernel is 0.74 ms of the 3.81 ms hit pass; at the desktop's, 1.73 of 10.47.
- The rest is GDScript. Each hit sends `projectile_impact` and `projectile_hit` one at a time, to five to seven listeners each: 2.6 ms a tick (web's caps) and 5.3 (desktop's), in the slower profiled runs.
- 36 to 129 hand-backs a tick go back to GDScript to be resolved.
- Feel's listeners (1.4 and 3.0 ms a tick) do view work inside the simulation's tick.
- Nobody measured how much of a listener's 13 to 35 us a call is the sending and how much is work that a batch would still do.

**The change.**

- The hit pass writes what it found into a hit table: packed arrays a tick, one row for each merged hit or impact, in the order the hits are sent now.
- Combat applies the table in one function, in row order. Spells' and the mouths' listeners read the same rows.
- Feel reads the tick's impact rows once a drawn frame, in its own step.
- The hand-backs that are only arithmetic (a wall end, the health ask) are answered in the kernel, from a column Combat keeps: a body's health, and whether it takes hits.

**What it saves, and where.**

- **Out of the tick:** all of Feel's 1.4 and 3.0 ms, plus part of Combat's listener and the hand-backs.
- **Of that, moved, not removed:** Feel's work still runs in the frame. On the web it stays on the main thread. On the desktop it goes to Feel's workers (change 1's F5).
- **The tick's figures in the ranking table are what leaves the tick.** The frame on the web gains less: about 0.5 to 1 ms at the web's caps **(estimate)**, plus the catch-up's multiplier while the frame is over budget.

**Risk.**

- Determinism: the hits must be applied in exactly today's order. That includes what a listener changes in the middle of the pass, such as a death, or a status that changes the next hit.
- `tick_hash.gd`'s four biomes must stay identical, native on and off.
- Feel must show the same thing in the same frame, and the hit shares (`hit_shares.gd`, `body_looks.gd`) must count the same hits.
- The kernel's answers need their GDScript twin and a byte test (`test_native_kernel.gd`).
- The table is sized once, like the manager's slots.

**PRs.**

- (H1) the hit table, and Combat applying it, with the events kept as wrappers for the other listeners;
- (H2) Feel's hit, damage and death looks read from the table in its frame;
- (H3) Spells' and the other listeners on the table, then the per-hit events removed;
- (H4) the wall-end and health-ask hand-backs answered in the kernel.

H1 starts with the listeners' profile in the 4p fight, which this report lacks.

### 4. The tick on its own thread, beside the drawing (desktop only)

**Evidence.**

- On the main thread today the frame is the tick plus the view: 9.0 + 11.8 ms in the 4p fight.
- On a thread of its own, the tick would run while the main thread draws the last tick's state. The frame becomes the larger of the two: 11.8 ms instead of 20.8 at one tick a frame, about 1.8x on its own.
- The catch-up spiral goes away while the tick fits its 16.7 ms.
- On the web nothing changes: it has no threads.

**The change.** This is sim-native's "later" goal:

- Nothing the simulation writes lives on a node: the body table (change 2) for the bodies, the manager's arrays (already) for the shots, and the other areas' state likewise.
- At the tick's end the view gets a copy of what it draws (double-buffered), and the nodes are set from it on the main thread.

**Risk.**

- It touches every simulation area.
- Godot's scene tree is not thread-safe, so the tick may touch no node.
- "One clock" holds: the tick still steps in its written order.
- Determinism holds: the code that steps is the same.
- Online play is unchanged: input frames go in at the tick's start.
- **This is the largest change in this file.** It is worth doing only after change 2, with the owner's decision (Q3).

**PRs** (after C6): one an area for its state off the nodes (Spells, Flow, Cover, Combat, Items, Rewards), then the view's copy, then the thread.

### 5. The drawing batched

**Evidence (counts only).**

- The 4p fight draws 1,659 canvas items, 316 draw calls and 94k primitives a frame.
- It draws 34k mote rows a frame, of which 28% are alive, in 218 mote MultiMeshes holding 104k instances.
- The bodies are 361 Sprite2D and 69 faces.
- What these cost on a GPU, and in the Mobile renderer's CPU, is not measurable here.

**The change**, if the owner's benchmark says the GPU or the renderer is the frame:

- the bodies drawn in one MultiMesh per layer (body, face, outline) from the looks' rows, in place of a Sprite2D per part;
- the motes' chunks packed so that dead rows are not drawn: fewer chunks per view, and the views share them.

**Risk.** View only, but the look must not change:

- pixel compares;
- the Smooth rule (whole pixels, the frames between looks);
- draw order where bodies overlap.

### What does not make the top five

- **Thinking less often** (THINK_EVERY 3 to 6): cheap to do, but it changes how foes play, and it saves less than change 2. It would remove at most about half of the think's 1.57 ms in the 4p fight, about 0.8 ms a tick. That is the owner's call (Q4).
- **Fewer nodes per body for its own sake:** 186 of the fight's 4,230 nodes process. What a body's nodes cost apart from the calls between them was not measured here; change 2 removes the calls.
- **The physics server:** the engine's own time a frame is about 0.9 ms headless (the physics server, the message queue, the frees). The game does not use the physics server for its bodies or shots.
- **The renderer setting:** the desktop already draws with Mobile (Vulkan or Direct3D 12) and the web with Compatibility. Whether Mobile beats Compatibility on the owner's PC can be one more run of the owner's benchmark (`--rendering-method gl_compatibility`). It is not a change.

## Open questions for the owner

- **Q1. Which is the frame on your PC?** Run `Spellmerge.exe -- --benchmark` and send the table, or its screenshot. If the GPU's ms is most of the frame, the drawing (change 5) comes first. If the simulation plus Feel are most of it, changes 1 to 3 come first.
- **Q2. Must every kernel keep its GDScript twin?** The web build has the native module too. So the GDScript runs only with `--no-native`, in the editor without a built module, and in the byte-for-byte tests. Keeping a twin is a large part of the work of changes 2 to 4 (most of a kernel PR's tests and review, **estimate**). Dropping it for the new kernels (C++ only, the same code on the web) would cut that work, but it loses the fallback and the reference.
- **Q3. The tick on its own thread (change 4):** is it worth its size, 8+ PRs touching every simulation area, for the desktop only? It is the one change here that gives the desktop about 1.8x on its own.
- **Q4. May the game change for speed?** For example, foes perceiving and deciding less often, or fewer looks for each hit in a crowd. Each would be a measured trade, recorded as a new baseline, never a silent change.
- **Q5. The web:** should it stay on one thread, or should we try a threaded web build? A threaded build needs cross-origin isolation headers from the host, which itch.io offers as a setting. Or should its caps (100 foes, 1,000 shots) be lowered to fit the 1.6x it pays?
