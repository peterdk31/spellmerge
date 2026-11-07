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

**With the tail shader's trails** (`--tails`, as before #562; the option went with them in #563), the storm's `update_draw` is 2.3, 7.7, 13.5 and 25.5 ms at 10k, 30k, 50k and 100k, and the trail samples 0.2 to 1.1 ms: the motes take that away (1.1 to 4.1 ms). The first run of this benchmark, on a slower cloud machine with the trails, measured 85 ms at 100k.

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
| H1 | **Fewer hand-backs** (dropped 2026-11-05) | `native/src/shot_kernel.cpp`, `core/projectiles/` | ~~The kernel hands back a run of hits in one call, in shot order, and GDScript sends their events one by one as now. Same events, same order, fewer crossings.~~ Dropped by the owner after measuring it: a hand-back costs about 3-4 us (1.8 us for the call itself, the rest reading the target arrays), about 12-15 ms of the 211 ms step of crowd_all at 100,000 and under 1 ms in a budgeted step, and a run of hits in the same order needs the kernel to scan ahead and undo whenever a hit handler changes a target or a later shot. H3b folds it in (its hit pass hands back only walls and ends). |
| H2 | **The hit budget sized by measurement, and no lost damage** | `core/projectiles/`, `native/` | `WORK_PER_STEP` stays a fixed number of work units, sized once from H0's per-hit cost on the target PC (Q3) and written in the code, never measured at run time: every machine must defer the same hits (rule T1, below). A deferred shot keeps the start of the path it hasn't been tested on, and its next test sweeps the whole path since then, so a fast shot no longer skips a target (correct damage, Q1). A test checks no shot waits more than one step under a full crowd, and that a deferred fast shot through a row of targets hits each one. |
| H3 | **Cheaper hits** | `gameplay/combat/`, `gameplay/feel/`, `core/spells/` | Each listener's per-hit work, timed in H0, moved to once a frame where it can be shared (the bundling decision's own rule). Candidates: Feel's spray, burst and sound per target per frame; the manager's facts Feel reads; Combat's per-hit table lookups. Each listener has its own PR and before/after numbers. |
| H3b | **Bundled hit events** | `core/events/`, `core/projectiles/`, `gameplay/combat/`, `core/spells/`, `gameplay/feel/`, tests | The step's hits go out as one batch (packed arrays: caster, target, point, heading, tag, shot), resolved in phases. The design is below. Done if H3 leaves the hits as the largest part of a step. |
| H4 | **Draw cost by count** (dropped 2026-11-05) | `core/projectiles/`, `core/settings/` | ~~Above a count set by the effect-quality setting, the newest shots draw without trails and with a simpler look, and `PARTICLE_CAP` sparks go to hits first.~~ Dropped as planned once the tails became motes (#562): H0 measures `update_draw` at 4.7 ms at 100,000 without trail rows. Its first version is on branch `ccr-41535d9d-ldgucy-h4`, should trails come back. |
| H5 | **Threads in the kernel (desktop)** (done 2026-11-07) | `native/`, and the owner's `ci/smbot/rules.py` and `native/SConstruct` | Approved by the owner on 2026-11-04; on 2026-11-07 the owner chose the module's own `std::thread` pool over `WorkerThreadPool` ("You can use std::thread if it's faster!"). One file makes threads (`native/src/jobs.cpp`, the rules allow it there only); every loop over every shot (the common pass, the behaviour passes but return's, the drawing) runs on it in fixed spans, what they share combined in span order. The hit pass stays on one thread: measured, no faster on several (below). Rule T2: a test compares one thread with four, bit for bit. |
| H5w | **Threads on the web** | `export_presets.cfg`, the owner's `ci/build/native.sh` | Only if the web build supports them (owner, 2026-11-04). It needs three things, each checked before H5w is built: the Web presets' `variant/thread_support=true` (with extensions); the native library built with `threads=yes` (`native.sh` builds `threads=no` today); and the page served cross-origin isolated (COOP/COEP headers, or Godot's PWA option that adds them), where the game is hosted. If any of the three fails, the web keeps one chunk and this part is dropped, noted in DECISIONS. The web stress run measures the difference, and a browser without isolation must still load the game. |
| H6 | **Shots-first queries** | `core/projectiles/`, `native/` | Only if H0 or H5 shows the target lookup still costs a lot when shots far outnumber targets: each target walks the shot grid (`_shot_head`, built for shields today) instead of each shot walking the target grid. Same hits, same order (sorted by shot), checked by the recording tests. |
| H7 | **Caps** | `core/projectiles/`, `core/settings/shot_cap.gd`, DECISIONS | The desktop and web defaults raised to what the stress run holds at 60 FPS. The slider's top raised past 50,000 if H0 shows a machine can use it. |

**H2 done (2026-11-05).** What the budget did before H2: with a hit priced at 40 units, a budget of 6,000 went mostly on hits, so in a crowd most shots went untested, and a shot that went untested skipped what it passed. Measured on the benchmark's own window (crowd: the budget; crowd_all: none), the crowd at the desktop cap dealt **47%** of its damage (133,780 of 280,915), at 10,000 shots 30% and at 30,000 10%; even the storm at 30,000, deferring only in busy steps, dealt half (51,945 of 101,970). Now:

- **Priced by measurement:** a unit is one target examined by the native hit pass (about 0.13 us on the owner's laptop) and a hit costs `HIT_WORK` = 400 (its listeners, about 50 us; H0). `WORK_PER_STEP` is 150,000: a full crowd at the desktop cap asks about 93,500 in the median step and more in a busy one, and at 150,000 no shot there waits more than one step (at 120,000 thousands do). Fixed in the code (T1).
- **No lost damage:** a shot the budget passes over is marked `F_DEFERRED` and keeps where its untested path starts (`_untested`); its next test sweeps the whole path since then, and a deferred shot that ends (its life out, a wall, out of the bounds, vanishing) is tested first whatever the budget. The GDScript and the native hit pass do it alike (the step-exact recording holds both).
- **What it costs:** the hits the budget dropped now happen, so a full crowd at the desktop cap costs what crowd_all costs: a manager step of about 13 ms (6 ms before, when half the hits were dropped) on the owner's laptop. Since no damage is lost, the hits a step average what the shots make whatever the budget: the budget only spreads a burst over a step or two, and **the caps bound the cost** (H7), with cheaper hits (H3, H3b).
- **Checked:** `tests/core/test_hit_budget.gd` (GDScript and native alike): a fast shot tested every other step hits every body of a row; a deferred shot that expires or leaves the bounds is tested first; over their whole flight, shots under a budget of one hit the very bodies they hit with none; in a full crowd at the desktop cap no shot waits more than one step. With still bodies a budget changes no hit at all; with moving ones a deferred shot sweeps its old path against where the bodies are now, so which body it hits can differ, and the totals over whole flights stayed within 0.01% (61,207 hits against 61,203 at 6,000 shots). The benchmark's fixed window is not a damage check once shots wait: its first 6,000 shots spawn and expire together, so a step's delay moves part of a pulse in or out of the window (the crowd at 6,000 counts 260 hits a step in the window against crowd_all's 209, and over the first 170 steps 31,770 hits against 31,782). The recorded scenes (`test_projectiles_step_exact.gd`, `test_projectiles_targets.gd`) take a budget of their own so they still run it out, and were recorded again.

**H5 done (2026-11-07).** `native/src/jobs.h` runs a loop in spans of a fixed size on up to `ShotKernel.threads` threads (the machine's cores less one; the manager's `native_threads`), and `ShotKernel` runs on it the common pass, the behaviour passes but return's, `count_draw` and `draw_shots` (heads, stones and each tail's plan; the tails' births under their caps and every float sum in slot order, as the GDScript adds them). Measured on the cloud machine (4 cores, headless, 100,000 shots, the storm; medians of 100 steps, the kernel's own time, one thread against four):

| Part | 1 thread | 2 threads | 4 threads |
|---|---|---|---|
| common pass | 0.57 ms | 0.42 ms | 0.34 ms |
| `count_draw` | 0.54 ms | 0.41 ms | 0.45 ms |
| `draw_shots` | 4.47 ms | 3.75 ms | 3.30 ms |

In the benchmark's own parts (two runs each, all three scenes at 100,000), the common pass went from 0.46–0.74 ms to 0.28–0.33 ms and `update_draw` from 7.3–10.6 ms to 6.1–7.4 ms; the hits and damage hashes are the same on one, two and four threads. The loops are memory-bound (a few nanoseconds of work per shot), so they gain less than the cores; a desktop's faster memory and more cores should gain more, measured there with `shot_scale.gd -- --threads=N`. What stays on one thread in `draw_shots` is its pass in slot order (each group's shots and asks, the tails' sums and births): the next part to share out if the drawing leads.

**The hit pass stays on one thread, measured.** A call of `hits` ends at every hit, so its shots can't be cut into chunks merged at the end. A version that looked at the shots ahead of their turn on every thread (the read-only half of each test, for a window of the shots to come) and took the looks in shot order, dropping one whose shot or target had changed since, was built, held to the bit by the tests and measured: in crowd_all at 100,000 the looks took the test from about 2.0 s to 1.6 s over the same 100,000 calls (0.7 s of looks on four threads, 0.95 s of taking them), and the rest of the pass grew by as much (the look records handed between cores, the shots' arrays read again on the stepping thread), so the pass was no faster; dropped (DECISIONS, 2026-11-07). Where the hit pass's kernel time goes instead: each of a crowd's 3,700 calls a step reads about 45 of the manager's arrays by name before it tests anything, about half the kernel's time in crowd_all (7.5 of 14 us a call on the cloud machine), and the hits' GDScript is about seven times the kernel (H3, H3b). Fewer calls (H3b's hit pass hands back only walls and ends) is what would make the kernel's share smaller.

**H3, Combat's hit (2026-11-07).** Timed inside the crowd with every shot tested (crowd_all, 30,000 shots, frost bolts, a timer round each part of `_on_projectile_hit`): of about 60 us a hit, about 25 us is Feel's `damage_dealt` and 2 us Feel's `hit_landed`, sent from inside it; Combat's own share is about 20 us, spread over parts of 1-3 us (the profile and row lookups, the hold, the team, the reaction lookup, the statuses). Changed, with the same hits and damage (the crowd's damage hash unchanged): the reaction lookup takes the element's rows lined up with `REACTING_STATUSES` from the table (`ReactionTable.in_order`) and the target's statuses as one mask (`_status_bits`) instead of a `match` call a status (2.8 to 1.4 us on an elemental hit; written out status by status it was 1.0 us, but the order and the reads then lived in two places; test_combat_reactions.gd holds it to the plain rule for every element and mix of statuses, through Combat's own calls), `_hit` takes the team `_apply_spell` already read, and a hit with no status and no reaction skips the element loop. `combat_hit.gd`, fastest of 15 passes, two runs each: plain 10.0 to 8.4-9.0 us, frost on frozen 15.1-16.7 to 11.5-11.7 us (fire on burning and storm on hexed within this machine's noise). crowd_all at 30,000 frost bolts: Combat's listener 57.1 to 52.6 us a hit (one run each). What leads now is Feel: `damage_dealt` (20-25 us) and `projectile_impact` (17-22 us), the next H3 parts.

**H3, Feel's hit flashes (2026-11-07).** Timed the same way, Feel's `damage_dealt` spends about 16 us of its 26 in the cue `hit`, 7 us of it the spray's flash; its `projectile_impact` spends as much on the impact's flash. A crowd's 800 hits a step ask for 1,600 flashes, and the effect slots hold 256, so all but the last 256 were written only to be overwritten before they were drawn. A frame's hit flashes (the spray and the impact, `_hit_flash`) now stop at three quarters of the slots (`HIT_FLASH_RESERVE`), before any of their work, and the rest stay free for casts, kills and statuses, which take the oldest slot as before. Under the share nothing changes. crowd_all at 30,000 plain bolts (one run each): Feel's `damage_dealt` 26.5 to 19.3 us a hit, `projectile_impact` 22.4 to 15.7 us, the damage hash unchanged (Feel is view, T5). test_feel_impacts.gd holds the share and its reset at the step.

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
- **Q2 (rules): answered** (owner, 2026-11-04): threads are allowed in the native module, through `WorkerThreadPool`, on desktop. Changed on 2026-11-07 (owner: "You can use std::thread if it's faster!"): the module's own `std::thread` pool, in one file (`native/src/jobs.cpp`; DECISIONS, 2026-11-07).
- **Q3 (targets): answered** (owner, 2026-11-04): "a desktop PC with medium specs." Taken as about a 6-core desktop CPU from the last five years, 16 GB of memory, and a GPU of the GeForce GTX 1660 or RTX 3050 class. H0 and H7 measure against that, and the desktop default cap is what it holds at 60 FPS. A slower machine lowers the "Max shots" setting.
