# Shot scale: toward 100,000 live shots

**Status: proposed, waiting for the owner.** Asked by the owner on 2026-11-04 ("Can we optimize the hit logic per bullet to increase the amount to like 100000 bullets at a time?"). Nothing below is scheduled until the owner answers the open questions at the end. No rule, damage or card behaviour changes. Every part is measured before and after, and caps are raised only to what a measurement holds.

## Where we are

Facts from the code and [DECISIONS.md](../DECISIONS.md) (2026-11-02):

- **The hit test is already fast.** Targets sit in a grid of `GRID_CELL` (64 px) cells, each with a count and a bounding box, so an empty or far cell costs one check. A shot's path this step is tested as a segment against the cells it touches. The native `ShotKernel` runs this pass and the other common passes (native/README.md).
- **The manager's step:** 0.9–1.1 ms at 6,000 shots with hits in the crowd, 0.6–1.4 ms at 10,000. `update_draw` takes 0.77 ms at 6,000 and 1.5 ms at 10,000.
- **Caps:** 6,000 desktop and 1,000 web by default. The "Max shots" setting (`core/settings/shot_cap.gd`) already goes to 50,000, "far past what a frame holds today".
- **What holds the caps is the hits.** A hit costs about 40 µs of GDScript across Combat, Spells and Feel (Spells about 8 µs, Feel's impact about 13 µs, Combat's damage and its listeners, the actors). At 16.7 ms a frame, that means **a few hundred hits a step at most, whatever the shot count.**
- **The hit budget hides the limit.** `WORK_PER_STEP` is 6,000 units and a hit costs `HIT_WORK` (40), so about 150 hits a step. Past it, shots still move but aren't tested until a later step. With far more shots, more of them are deferred, and fast ones skip targets.
- **The GPU:** trails cost about 6 ms a frame at 3,000 shots with cards on an RTX A3000, and grow with the shot count.
- **The owner's decision on bundling (2026-11-02):** hit events stay one event per hit. Bundling saves only the signal call (about 0.3 ms a frame), because hits depend on each other in order (a kill, a status a reaction reads, an on-hit card's shots). The rule instead: a listener with costly per-hit work keeps the hit and does the work once a frame. **This plan keeps that decision.**

## What 100,000 means

Shot count and hit count are separate costs:

- **Shots that fly:** cost is per shot per step, in C++ (move, walls, grid lookups) and on the GPU (drawing). This scales to 100,000 with the parts below.
- **Shots that hit:** cost is per hit, in GDScript. At roughly 40 µs a hit, 100,000 shots in a crowd would make thousands of hits a step, far past a frame. No optimisation of the hit test changes this. Only cheaper hits do (H3), or fewer hits per shot, which is a design question (Q1).

So the realistic goal is **100,000 shots in flight on desktop, with hits capped by a budget that keeps the frame**. Expected from the numbers above: about 20,000–40,000 on desktop with everything hitting at full detail. The web stays near its cap: it has no threads, WASM scripts run 2–3× slower, and the GPU is weaker.

## Parts

| # | Part | Paths | Delivers |
|---|---|---|---|
| H0 | **Measure at scale** | `tests/benchmark/` | A storm and a crowd at 10k, 30k, 50k and 100k shots, timed part by part: the kernel's passes, hand-backs, each hit listener, `update_draw`, GPU frame time. The baseline for everything else. |
| H1 | **Fewer hand-backs** | `native/src/shot_kernel.cpp`, `core/projectiles/` | The kernel hands back a run of hits in one call, in shot order, and GDScript sends their events one by one as now. Same events, same order, fewer crossings. |
| H2 | **The hit budget by time** | `core/projectiles/` | `WORK_PER_STEP` is sized from H0's per-hit cost, so the budget means the same milliseconds as shots grow. A test checks no shot waits more than one step under a full crowd. |
| H3 | **Cheaper hits** | `gameplay/combat/`, `gameplay/feel/`, `core/spells/` | Each listener's per-hit work, timed in H0, moved to once a frame where it can be shared (the bundling decision's own rule). Candidates: Feel's spray, burst and sound per target per frame; the manager's facts Feel reads; Combat's per-hit table lookups. Each listener has its own PR and before/after numbers. |
| H4 | **Draw cost by count** | `core/projectiles/`, `core/settings/` | Above a count set by the effect-quality setting, the newest shots draw without trails and with a simpler look, and `PARTICLE_CAP` sparks go to hits first. One batch per kind, as now. Measured on a real GPU. |
| H5 | **Threads in the kernel (desktop)** | `native/`, and the owner's `ci/smbot/rules.py` and `native/build_profile.json` | Needs the owner (Q2): both files are the owner's. The common pass and the hit pass split into chunks of shots on Godot's `WorkerThreadPool`. Each chunk only reads the target grid and writes its own shots, and results merge in shot order, so they stay byte-identical to the GDScript (`test_native_kernel.gd`). The web runs one chunk. |
| H6 | **Shots-first queries** | `core/projectiles/`, `native/` | Only if H0 or H5 shows the target lookup still costs a lot when shots far outnumber targets: each target walks the shot grid (`_shot_head`, built for shields today) instead of each shot walking the target grid. Same hits, same order (sorted by shot), checked by the recording tests. |
| H7 | **Caps** | `core/projectiles/`, `core/settings/shot_cap.gd`, DECISIONS | The desktop and web defaults raised to what the stress run holds at 60 FPS. The slider's top raised past 50,000 if H0 shows a machine can use it. |

**Order:** H0 first. H1, H2 and H4 in parallel after it. H3 one listener at a time, biggest first. H5 after the owner's answer. H6 only if measured. H7 last. Each part is one PR that follows the native contract (native/README.md): the GDScript stays the reference, and the side-by-side and recording tests pass byte for byte.

## Not in this plan

- **Bundled hit events.** The owner decided against them (2026-11-02). If H0 shows the signal calls themselves matter at this scale, that's a new question for the owner, with the numbers.
- **Compute shaders on the GPU.** The web renderer (`gl_compatibility`) has none, and hits would need reading back to the CPU every step.
- **A shot that skips card rules.** Every card works on every carrier with no silent no-ops ([M2-rules.md](M2-rules.md)). Making cheap shots that ignore cards would break that.

## Open questions for the owner

- **Q1 (design):** 100,000 shots, or 100,000 hits? Shots in flight are reachable on desktop. Hits are bounded by a frame (above). Are many shots that mostly miss, or spells that make fewer, bigger shots, what you're after? Is that much on screen still readable for 1–4 players in 32×32 pixel art ([DESIGN.md](../DESIGN.md))?
- **Q2 (rules):** may the native module use threads (Godot's `WorkerThreadPool`, desktop only)? Today `check_native_source` forbids threads, and `WorkerThreadPool` isn't in `native/build_profile.json`. H5 depends on this answer.
- **Q3 (targets):** what does 60 FPS have to hold on? Desktop and web defaults, and the GPU to measure H4 on.
