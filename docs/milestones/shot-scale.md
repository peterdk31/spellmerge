# Shot scale: toward 100,000 live shots

**Status: approved by the owner on 2026-11-04,** with phase N's rules T1-T5 ("Determinism", below) and in one order with it ([online-ready.md](online-ready.md), "With shot scale"); the tasks are in the owner lane of [NEXT.md](../NEXT.md). The owner's direction of 2026-11-04: Asked by the owner on 2026-11-04 ("Can we optimize the hit logic per bullet to increase the amount to like 100000 bullets at a time?"), then: "Don't mind what has been decided earlier. Bundle hit events if needed and add threads!" ([DECISIONS.md](../DECISIONS.md), 2026-11-04). So bundled hit events (H3b) and threads in the kernel (H5) are in the plan, on the web too where the build supports threads (H5w). The owner answered the open questions on 2026-11-04 (end of this document). **The one hard requirement is that every shot deals the correct damage**: the same hits on the same targets for the same amounts. How hits are found, ordered, batched, shown or deferred may change freely to get there. Every part is measured before and after, and caps are raised only to what a measurement holds.

## Where we are

Facts from the code and [DECISIONS.md](../DECISIONS.md) (2026-11-02):

- **The hit test is already fast.** Targets sit in a grid of `GRID_CELL` (64 px) cells, each with a count and a bounding box, so an empty or far cell costs one check. A shot's path this step is tested as a segment against the cells it touches. The native `ShotKernel` runs this pass and the other common passes (native/README.md).
- **The manager's step:** 0.9–1.1 ms at 6,000 shots with hits in the crowd, 0.6–1.4 ms at 10,000. `update_draw` takes 0.77 ms at 6,000 and 1.5 ms at 10,000.
- **Caps:** 6,000 desktop and 1,000 web by default. The "Max shots" setting (`core/settings/shot_cap.gd`) already goes to 50,000, "far past what a frame holds today".
- **What holds the caps is the hits.** A hit costs about 40 µs of GDScript across Combat, Spells and Feel (Spells about 8 µs, Feel's impact about 13 µs, Combat's damage and its listeners, the actors). At 16.7 ms a frame, that means **a few hundred hits a step at most, whatever the shot count.**
- **The hit budget hides the limit.** `WORK_PER_STEP` is 6,000 units and a hit costs `HIT_WORK` (40), so about 150 hits a step. Past it, shots still move but aren't tested until a later step. With far more shots, more of them are deferred, and fast ones skip targets.
- **The GPU:** trails cost about 6 ms a frame at 3,000 shots with cards on an RTX A3000, and grow with the shot count.
- **Bundling, decided against on 2026-11-02 and reversed on 2026-11-04.** The earlier finding was that bundling saves only the signal calls (about 0.3 ms a frame) as long as each listener still handles hits one by one in order. That still holds, so H3b only pays where a listener actually shares work across a step's hits. That's why H3b's design below changes the order of effects within a step.

## H0: the baseline (2026-11-05)

`tests/benchmark/shot_scale.gd`, headless, with the native module, on main after the tails became motes (#562), on the owner's laptop (i7-12850HX, WSL; no GPU frame time headless: run it in a window, or the storm on the real GPU, for that). A plain bolt, a third of the shots piercing two; medians of 120 steps, in milliseconds, one run: compare parts and versions with each other, not with a frame on another machine. The manager times its own `step()` (`step_profile`, core/README.md), so the parts are the game's own step. "Past budget" is the shot slots the hit-work budget left untested for a later step. **crowd_all** is the crowd with the budget lifted: every shot tested every step, which is where H2's "no lost damage" leads.

| Scene, shots | Hits a step | Hand-backs a step | Past budget | Manager step | Kernel | Hand-backs and listeners | `update_draw` |
|---|---|---|---|---|---|---|---|
| storm 10k | 10 | 50 | 0 | 2.5 | 0.6 | 1.8 | 1.1 |
| storm 30k | 26 | 151 | 0 | 3.6 | 1.1 | 2.2 | 1.6 |
| storm 50k | 27 | 179 | 0 | 4.8 | 1.7 | 2.7 | 2.3 |
| storm 100k | 27 | 184 | 3,143 | 6.3 | 3.0 | 2.8 | 4.1 |
| crowd 10k | 100 | 141 | 9,414 | 6.5 | 0.7 | 5.5 | 1.1 |
| crowd 30k | 100 | 189 | 29,463 | 6.8 | 0.9 | 5.7 | 1.6 |
| crowd 50k | 100 | 207 | 49,452 | 7.3 | 0.9 | 6.0 | 2.3 |
| crowd 100k | 100 | 217 | 99,446 | 8.2 | 1.2 | 6.4 | 4.7 |
| crowd_all 10k | 343 | 369 | 0 | 19.5 | 2.7 | 16.6 | 1.2 |
| crowd_all 30k | 1,012 | 1,087 | 0 | 55.5 | 8.0 | 47.2 | 1.8 |
| crowd_all 50k | 1,684 | 1,813 | 0 | 95.6 | 14.0 | 81.6 | 2.7 |
| crowd_all 100k | 3,523 | 3,801 | 0 | 198.6 | 29.5 | 169.4 | 4.7 |

The target refresh, the common pass and the trail samples stay under 0.3 ms each at every count; Spells', Combat's and Feel's own steps under 0.7 ms together. The hits and damage are the same as on the base before the tails changed (the damage check holds), and the hits a step are the same as the first H0 run's on the cloud machine.

**With the tail shader's trails** (`--tails`, as before #562), the storm's `update_draw` is 2.3, 7.7, 13.5 and 25.5 ms at 10k, 30k, 50k and 100k, and the trail samples 0.2 to 1.1 ms: the motes take that away (1.1 to 4.1 ms). The first run of this benchmark, on a slower cloud machine with the trails, measured 85 ms at 100k.

The listeners, per step at 100k (a listener's time includes the events it sends in turn):

| Listener | storm | crowd | crowd_all |
|---|---|---|---|
| Combat's `projectile_hit` | 1.8 ms (56 calls, 32 µs) | 3.0 ms (98, 31 µs) | 78.0 ms (2,758, 28 µs) |
| Feel's `damage_dealt` | 1.0 ms (18 µs) | 1.7 ms (17 µs) | 40.2 ms (15 µs) |
| Feel's `projectile_impact` | 0.7 ms (13 µs) | 1.2 ms (12 µs) | 25.4 ms (9 µs) |
| Spells' `projectile_hit` | 0.2 ms (4 µs) | 0.4 ms (4 µs) | 10.9 ms (4 µs) |
| Feel's `projectile_expired` | 3.1 ms (500 calls, 6 µs) | 2.7 ms (480, 6 µs) | 1.7 ms (207, 8 µs) |
| Spells' `projectile_expired` | 0.8 ms (1.6 µs) | 0.8 ms (1.6 µs) | 0.5 ms (2.6 µs) |
| Feel's `hit_landed` | 0.1 ms | 0.1 ms | 2.5 ms |

What it says for the parts after it:

- **The hits are the cost, and the budget hides how much.** With the budget, a crowd step makes 100 hits whatever the count, and at 100k nearly every shot goes untested that step (a shot is tested about once in its 2 s life). Testing every shot (crowd_all) makes 3,500 hits a step at 100k and a 199 ms step, 169 ms of it the hand-backs and their listeners. That is H2's problem in numbers: deferred shots fly on untested, and making them deal their damage multiplies the hits by 35 at 100k.
- **H3 starts with Combat's hit, then Feel's `damage_dealt` and `projectile_impact`.** Per hit they cost about 28, 15 and 9 µs; Spells' hit 4 µs. Feel's `projectile_expired` leads only where few shots hit (the storm), at 6 µs an end. Together a hit costs about 48 µs of GDScript here; at 3,500 hits a step only bundling what the listeners share (H3b) or fewer hits per shot (Q1) brings a step near a frame.
- **The kernel is not small once every shot is tested:** 29.5 ms at 100k in crowd_all (3 ms in the storm, 1.2 ms in the budgeted crowd). H5's threads and H6 (shots-first queries) have that to win, after H3 and H3b take the listeners down.
- **H1 (fewer hand-backs):** 3,800 kernel calls a step at 100k in crowd_all, one per hit or end; their own cost is inside the 169 ms with the listeners and is measured by H1 itself.
- **Drawing is no longer the largest cost:** with tails as motes `update_draw` is 1.1 to 4.7 ms from 10k to 100k. H4 (draw cost by count) is dropped as planned once the tails became motes; the GPU frame on the target PC (Q3) is still to be measured.

## What 100,000 means

Shot count and hit count are separate costs:

- **Shots that fly:** cost is per shot per step, in C++ (move, walls, grid lookups) and on the GPU (drawing). This scales to 100,000 with the parts below.
- **Shots that hit:** cost is per hit, in GDScript. At roughly 40 µs a hit, 100,000 shots in a crowd would make thousands of hits a step, far past a frame. No optimisation of the hit test changes this. Only cheaper hits do (H3, H3b), or fewer hits per shot, which is a design question (Q1).

So the realistic goal is **100,000 shots in flight on a medium desktop PC (Q3), every one dealing its damage**. Expected from the numbers above: about 20,000–40,000 on desktop with everything hitting at full detail. With bundled hits (H3b), the per-hit cost drops to what each listener can't share, so the number rises with how much H0 shows is shareable. The web stays well below desktop: WASM scripts run 2–3× slower and the GPU is weaker. Threads (H5w) help only its C++ part.

## Parts

| # | Part | Paths | Delivers |
|---|---|---|---|
| H0 | **Measure at scale** | `tests/benchmark/`, `core/projectiles/` | A storm, a crowd and the crowd with every shot tested at 10k, 30k, 50k and 100k shots, timed part by part by the manager's own step profile: the kernel's passes, hand-backs, each hit listener, `update_draw`, GPU frame time. The baseline for everything else. |
| H1 | **Fewer hand-backs** | `native/src/shot_kernel.cpp`, `core/projectiles/` | The kernel hands back a run of hits in one call, in shot order, and GDScript sends their events one by one as now. Same events, same order, fewer crossings. |
| H2 | **The hit budget sized by measurement, and no lost damage** | `core/projectiles/`, `native/` | `WORK_PER_STEP` stays a fixed number of work units, sized once from H0's per-hit cost on the target PC (Q3) and written in the code, never measured at run time: every machine must defer the same hits (rule T1, below). A deferred shot keeps the start of the path it hasn't been tested on, and its next test sweeps the whole path since then, so a fast shot no longer skips a target (correct damage, Q1). A test checks no shot waits more than one step under a full crowd, and that a deferred fast shot through a row of targets hits each one. |
| H3 | **Cheaper hits** | `gameplay/combat/`, `gameplay/feel/`, `core/spells/` | Each listener's per-hit work, timed in H0, moved to once a frame where it can be shared (the bundling decision's own rule). Candidates: Feel's spray, burst and sound per target per frame; the manager's facts Feel reads; Combat's per-hit table lookups. Each listener has its own PR and before/after numbers. |
| H3b | **Bundled hit events** | `core/events/`, `core/projectiles/`, `gameplay/combat/`, `core/spells/`, `gameplay/feel/`, tests | The step's hits go out as one batch (packed arrays: caster, target, point, heading, tag, shot), resolved in phases. The design is below. Done if H3 leaves the hits as the largest part of a step. |
| H4 | **Draw cost by count** (dropped 2026-11-05) | `core/projectiles/`, `core/settings/` | ~~Above a count set by the effect-quality setting, the newest shots draw without trails and with a simpler look, and `PARTICLE_CAP` sparks go to hits first.~~ Dropped as planned once the tails became motes (#562): H0 measures `update_draw` at 4.7 ms at 100,000 without trail rows. Its first version is on branch `ccr-41535d9d-ldgucy-h4`, should trails come back. |
| H5 | **Threads in the kernel (desktop)** | `native/`, and the owner's `ci/smbot/rules.py` and `native/build_profile.json` | Approved by the owner on 2026-11-04. Both files are the owner's: the PR changes them with the owner's approval and the owner merges it. `WorkerThreadPool` goes in the build profile, and the rules allow it and nothing else (still no `std::thread`, no system calls). The common pass and the hit pass split into chunks of shots on Godot's `WorkerThreadPool`. Each chunk only reads the target grid and writes its own shots, and results merge in shot order, so they stay byte-identical to the GDScript (`test_native_kernel.gd`). The web runs one chunk. Rule T2 (below): fixed-size chunks, partial results combined in chunk order, the hit budget spent at the merge in shot order, and a test that compares one thread with several, bit for bit. |
| H5w | **Threads on the web** | `export_presets.cfg`, the owner's `ci/build/native.sh` | Only if the web build supports them (owner, 2026-11-04). It needs three things, each checked before H5w is built: the Web presets' `variant/thread_support=true` (with extensions); the native library built with `threads=yes` (`native.sh` builds `threads=no` today); and the page served cross-origin isolated (COOP/COEP headers, or Godot's PWA option that adds them), where the game is hosted. If any of the three fails, the web keeps one chunk and this part is dropped, noted in DECISIONS. The web stress run measures the difference, and a browser without isolation must still load the game. |
| H6 | **Shots-first queries** | `core/projectiles/`, `native/` | Only if H0 or H5 shows the target lookup still costs a lot when shots far outnumber targets: each target walks the shot grid (`_shot_head`, built for shields today) instead of each shot walking the target grid. Same hits, same order (sorted by shot), checked by the recording tests. |
| H7 | **Caps** | `core/projectiles/`, `core/settings/shot_cap.gd`, DECISIONS | The desktop and web defaults raised to what the stress run holds at 60 FPS. The slider's top raised past 50,000 if H0 shows a machine can use it. |

**Order:** the combined order with phase N is in [online-ready.md](online-ready.md), "With shot scale" (the two share the projectile manager and the shot kernel). Within this plan: H0 first. H1 and H2 in parallel after it (H4 is dropped). H3 one listener at a time, biggest first (by H0: Combat's hit, then Feel's `damage_dealt` and `projectile_impact`), then H3b if the hits still lead. H5 in parallel with H3, then H5w. H6 only if measured. H7 last. Each part is one PR that follows the native contract (native/README.md): the GDScript stays the reference, and the side-by-side tests pass byte for byte. Every part also passes a **damage check**: a scripted storm records each target's damage taken, and a part may change when or in what order hits land within a step, but not the totals.

## H3b: bundled hit events

Today each hit is one `projectile_hit` (and one `projectile_impact`), and Combat, Spells and Feel each handle it before the next hit goes out. Bundling only pays if a listener can share work across the step's hits, so the batch is resolved **in phases**, each over every hit of the step in hit order:

1. **Combat:** damage, statuses, reactions and kills, hit by hit in order, as today. A hit on a target killed earlier in the same batch is skipped, as it would be by a freed node. Lookups are shared across the batch (the target's row, its team, its hit profile).
2. **Spells:** on-hit cards, chains and payloads, in hit order. They read the state after all of the step's damage, not after their own hit. **This is the one rule change**, allowed by the owner as long as damage is correct (Q1): a reaction or trigger can see a status that a later hit in the same step applied. Shots spawned by on-hit cards fly from the next step, as they do now.
3. **Feel:** one look, sound and flash per target per batch (the strongest hit's), plus sparks up to its budget. Damage numbers show each target's total for the batch.

- **One entry point.** Every sender of hits (blasts, melee carriers, the manager) sends a batch, and a single hit is a batch of one, so no listener keeps two paths. `projectile_hit` and `projectile_impact` become `projectile_hits` and `projectile_impacts` in `core/events/events.gd`, with the batch's arrays reused, not allocated per step.
- **The native hit pass fills the batch.** It writes hits into the batch's arrays and hands back only for walls and ends, so H1 folds into it.
- **Tests.** The recording tests (`test_projectiles_step_exact.gd` and the hit traces) are recorded again, and the PR lists every changed trace with its reason. The card-rules tests (`test_card_rules.gd`, `test_card_rules_swarm.gd`) must still show no silent no-ops. A new test fires two hits in one step where the second applies a status the first one's reaction reads, and checks the new order.
- **One PR per listener after the event change**, so each is timed before and after: first the event and Combat, then Spells, then Feel and the rest.

## Determinism (with phase N, online-ready)

Online co-op will send inputs only, so every machine must play the same game from them ([online-ready.md](online-ready.md), phase N). Checked against this plan on 2026-11-04; it holds on five rules (the same text is in online-ready.md, "With shot scale"):

- **T1:** the hit budget is fixed work, never measured time (H2).
- **T2:** threads never change a result: fixed-size chunks, chunk-order merges, the budget at the merge, one thread against several compared bit for bit (H5, H5w).
- **T3:** the kernels' maths is phase N's `dmath.h`, threaded or not.
- **T4:** the caps are session rules (phase N, N11); H7 raises the defaults, a session takes the weakest machine's.
- **T5:** what changes only the look (H4, sparks, H3b's one look per target) stays view.

## Not in this plan

- **Compute shaders on the GPU.** The web renderer (`gl_compatibility`) has none, and hits would need reading back to the CPU every step.
- **A shot that skips card rules.** Every card works on every carrier with no silent no-ops ([M2-rules.md](M2-rules.md)). Making cheap shots that ignore cards would break that.

## The owner's answers

- **Q1 (design): answered** (owner, 2026-11-04): "as long as the shots deal the correct damage it is fine doing whatever." Damage is the requirement (the damage check above). Order, batching, looks and how hits are found are free.
- **Q2 (rules): answered** (owner, 2026-11-04): threads are allowed in the native module, through `WorkerThreadPool`, on desktop.
- **Q3 (targets): answered** (owner, 2026-11-04): "a desktop PC with medium specs." Taken as about a 6-core desktop CPU from the last five years, 16 GB of memory, and a GPU of the GeForce GTX 1660 or RTX 3050 class. H0 and H7 measure against that, and the desktop default cap is what it holds at 60 FPS. A slower machine lowers the "Max shots" setting.
