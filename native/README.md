# Native

## Purpose

Spellmerge's own C++, loaded by Godot as a GDExtension: faster versions of hot loops the game already has in GDScript. Where the module is not built, the GDScript it stands for runs.

| Class | What it runs | GDScript it stands for |
|---|---|---|
| `ShotKernel` (`src/shot_kernel.cpp`) | the projectile step's passes, the hit pass's eventless shots, draw batches, `nearest_target`, `trail_pass`, `field_pass`, `shot_places`, `region_counts`/`region_rows`, `ray_walks` (beams' rays between their hits, #972), the sparks shots give off (`give_off_sparks`, `src/spark_roll.cpp`: the manager's dice, PCG32 as the engine rolls it) | `core/projectiles/projectile_manager.gd` (and `draw_regions.gd`, `projectile_rays.gd`, `projectile_draw.gd`) |
| `MoteKernel` (`src/mote_kernel.cpp`; Feel's other loops in `src/feel_loops.cpp`) | the motes' trail births, settling marks, `region_rows`; the flashes' rows (`find_special`, `write_rows`), the world's stirs (`stir_step`), a room's mist parting (`part_work`) | `gameplay/feel/mote.gd` (`give_off`, `burst`), `gameplay/feel/mote_regions.gd`; `gameplay/feel/feel_flashes.gd` (`_find_special`, `_write_rows`), `gameplay/feel/stirs.gd` (`_read`, `_ease`), `gameplay/feel/mist_parting.gd` (`work`) |
| `LightKernel` (`src/light_grid.cpp`) | grid lighting: `light_grid_rows`, `light_grid_beam`, `light_grid_bake`, checked by `check_light_grid` | `gameplay/feel/light_grid.gd` |
| `GroundKernel` (`src/ground_kernel.cpp`) | a room's ground drawn from `GroundShape.spec` (`draw`) | `gameplay/feel/ground/ground_drawing.gd` (twin of `tools/ground_shape.py`) |
| `BodyKernel` (`src/body_kernel.cpp`) | a body's slide, `walk`, `walk_place` (the walk and the place it ends in, `Actor.move`'s), `wall_hit`/`way_hit` (`src/grid_ray.h`), `places`, `gather` (the body table's rows as the bodies' step starts) | `core/projectiles/wall_slide.gd` (`WallSlide.gd_slide`), `core/projectiles/room_grid.gd` (`RoomGrid.gd_walk_body`, `gd_walk_place`), `gameplay/flow/room_life.gd` (`RoomLife.gd_find_places`), `gameplay/actor/actor.gd` (`Actor.gd_gather_rows`) |
| `DMathKernel` (`src/dmath_kernel.cpp`, `src/dmath.h`) | deterministic maths | `core/sim/dmath.gd` (`DMath`) |

**The GDScript stays** as the reference, the fallback and the readable spec. Every exported build has the module; an export without it logs an error (`core/native/native.gd`).

**What stays GDScript** on purpose: anything that sends an event or calls gameplay (hit handlers, the move, stuck and shield passes, Combat's reads) and node work (looks, sprites, shader parameters). Profile first: `tests/benchmark/`, `stress.gd`.

This folder is Claude's and the owner's only (the owner's decision of 2026-11-02; `ci/smbot/rules.py`). Contributors can't add native code.

## Contract

- **Same results, to the bit.** Every kernel method does exactly what its GDScript does on the same arrays: same branches, same float rounding (GDScript `float` is double; `Vector2` and `PackedFloat32Array` single; `src/packed.h` has GDScript's helpers). Engine behaviour is called, not copied (`hash`, `wrapf`, `move_toward`, `RandomNumberGenerator`). A member the side-by-side compare leaves out is DERIVED or VIEW, never state (reviewed exceptions: `STATE_NOT_READ_BY_TYPE`).
- **The object's arrays, in place, for one call.** A kernel takes the object and reads its packed arrays with `get` (held objects through their own field table: `GRID_FIELDS`, `BATCH_FIELDS`, checked by `check_fields`). It writes through the shared buffers and keeps no reference once it returns. The object sizes every array before a call; a kernel never grows one. No object keeps a copy of an array another holds for a kernel. A buffer handed to the renderer is written with `ptrw`. Between calls a kernel keeps only numbers it worked out, never an array of the object's.
- **Hand back what needs GDScript.** Anything that sends an event stays in GDScript. The native hit pass hands back each shot that needs GDScript, in turn, so events go out in the same order; if it fails (logged) the manager finishes in GDScript. A dry run declines, writing nothing but its scratch, any shot GDScript must take (`HitPass::merge_hits`, `can_open`, `open_entry`); a shot whose hits wait only for Combat's answers (an ask is an event) is handed back for those alone (`YIELD_ASK`: the hit batch's `ask_target`), and the kernel takes up its hits when GDScript has asked.
- **Constants and members are checked when a kernel is switched on.** `CONSTANTS` in `src/shot_kernel.cpp` is compared with `native_constants` by `check`; members read are declared once with types (`MANAGER_FIELDS`, `GRID_FIELDS`, `BATCH_FIELDS`, `REGION_FIELDS`, `MOTE_FIELDS`, `MOTE_REGION_FIELDS`, `check_regions`) and checked by `check_fields`. A mismatch is an error and the GDScript runs: change the kernel with the member or constant.
- **Bodies read by a kernel** (`BodyKernel.places`, `gather`): a kernel may read a body through its node by the actor table's instance ids (`ObjectDB::get_instance`, typed `Node2D` calls, `get` of a member by name) and set a plain member by name (`room`), on the calling thread only, in id order; never a call of a script's method, never on a span (the owner's decision of 2026-11-22, AGENTS.md hard rule 4). Never, here or anywhere in the module: system calls, starting programs, files, the network, loading code, assembly, calls of a method by name (`call`, `callv`, `get_singleton`; the raw interface but `object_get_instance_from_id`), and any engine API in a span of `jobs::for_spans` but pure functions ("What a span may do" below).
- **No script runs while a kernel holds the arrays.** Kernels call engine methods only.
- **One loader.** `core/native/native.gd` is the only GDScript that asks whether the module is loaded and makes its classes, by literal name (`NATIVE_FILE` in the rules).
- **Nothing built is committed** (hard rule 2). `ci/build/native.sh` builds into `native/bin/` and writes `native/spellmerge.gdextension`; both are git-ignored, as are SCons' object files.

Tests, side by side, byte for byte: `tests/core/test_native_kernel.gd` (one thread and four), `tests/gameplay/feel/test_native_motes.gd`, `tests/gameplay/feel/test_native_feel.gd`, `tests/core/test_wall_slide.gd`, `tests/core/test_grid_rays.gd`, `tests/core/test_ray_walks.gd`, `tests/core/test_body_walk.gd`, `tests/core/test_body_move.gd`, `tests/gameplay/actor/test_body_table.gd` (the gather), `tests/gameplay/feel/test_light_grid.gd`, `tests/gameplay/feel/test_ground_drawing.gd`, `tests/gameplay/flow/test_room_life.gd`, `tests/core/test_draw_regions.gd`, `tests/core/test_spark_roll.gd`, `tests/core/test_draw_threads.gd` and `tests/core/test_step_threads.gd` (the drawing and the step past their one-thread thresholds, four threads and one), `tests/gameplay/feel/test_mote_regions.gd`, `tests/core/test_dmath.gd`; the recording `test_projectiles_step_exact.gd`; `test_determinism.gd`.

## Threads (shot scale H5)

Threads never change a result: the bits are the same on one thread or sixteen.

- **One place knows threads.** `src/jobs.h` (`jobs::for_spans`: fixed-size spans on up to `width` threads, the caller's among them). `src/jobs.cpp` is the pool (the module's own `std::thread`s) and the only file that may include a thread header or make a thread (`NATIVE_THREADS_FILE`). A kernel knows nothing of threads; the pool nothing of shots.
- **What a span may do.** A span writes only its own slots or row. What spans share is combined after, in span order, on the calling thread. A span calls no engine API but pure functions (`wrapf`): no Variant of an array or Object, no printing, no `ERR_` macro, no nested loop of its own.
- **The hit pass stays on one thread.**
- **Where else.** Any kernel's loop may run on `jobs::for_spans` where measured faster.
- **A loop wakes the workers only past its kernel's threshold** (`jobs::width_from`; below it the loop runs on the calling thread and no worker wakes): a worker's wake-up costs tens of microseconds, more than a cheap loop's whole share of it. Each kernel measures its own (`tests/benchmark/shot_scale.gd`'s storm, `--threads=1` against the default). The drawing (`count_draw`, `draw_shots`) from 32,768 slots (`DRAW_THREADS_FROM` in `src/shot_kernel.cpp`: `update_draw` 0.95 ms alone against 1.18 threaded at 24,000, 2.68 against 1.88 at 50,000); the step's common pass and a behaviour's members from 65,536 (`STEP_THREADS_FROM`: 0.008 ms alone against 0.030 at 1,000 shots, 0.087 against 0.103 at 24,000, even between 50,000 and 100,000), so a game's shots step on one thread. Tested past both on four threads and one: `tests/core/test_draw_threads.gd`, `tests/core/test_step_threads.gd` (the performance pass, 2026-11-28, four cores).
- **Feel's threads are the engine's.** `gameplay/feel/feel_jobs.gd` runs `LightKernel.light_grid_rows`/`light_grid_beam` a view a thread (`first_view`, `views`) with `WorkerThreadPool`; the kernel starts no thread for it and keeps nothing between calls; `check_light_grid` runs on the main thread first.
- **How many.** `ShotKernel.threads` (the manager's `native_threads`; 0 = cores less one, at most 16: `jobs::WIDTH_LIMIT`); at most 4 on the web, which is threaded only (`WEB_MAX_WIDTH`; the owner's decision of 2026-11-28: no single-threaded web build), whatever is asked, as a browser's threads are workers made before the game starts and one asked for past them would never start while the main thread waits for it: the Web preset's `threads/emscripten_pool_size` holds the engine's `threads/godot_pool_size`, its own few and the module's 3 (`tests/smoke/test_export_presets.gd`). 1 in a library built `threads=no` (none is shipped). A machine setting, never a run's.
- **Platforms.** Linux `-pthread`; Windows links MinGW's thread runtime statically (`native.sh` checks: no `libwinpthread` import).

## The same on every platform (online-ready N7)

What a kernel computes for the simulation uses `src/dmath.h` for every C-library function (sin, cos, tan, atan2, exp, log, pow, `from_angle`, `rotated`, `angle`, `angle_to`), never `std::sin` or the engine's `Vector2::rotated`. dmath.h uses only `+ - * /`, `sqrt`, `floor`, `fmod`. Everything is built with `-ffp-contract=off` and `-fno-fast-math`. GDScript the kernels mirror calls `DMath` where they call dmath.h (`tests/core/test_dmath.gd`). What only draws (`MoteKernel`, `GroundKernel`) may keep `std::` maths. A kernel may work a number out once where its GDScript works it out at every pixel (`GroundKernel`: a lattice's corners and each column's and row's fraction, a slab row's sums, a floor's slivers found as runs, a rock face's bottoms read row by row), or leave out a step that cannot change the result (a circle too far off along one axis), only when every number it hands back is the same; the twin tests compare the bytes (#972).

### The desktop builds optimised (the owner, 2026-11-22)

`-O3`; desktop libraries linked whole (`lto=full`, float flags passed to the link) for `x86-64-v2`; no AVX2 library. `ci/build/native.sh` refuses a desktop library holding any fused multiply-add or a call of `fma` (`no_fma`). `cpu=` is for measuring only.

## Building

```sh
ci/build/native.sh linux web windows     # the libraries and the .gdextension (build.sh runs it first)
```

- Pinned tools in `ci/build/godot.env` (godot-cpp, SCons's hash-checked wheel, Emscripten 4.0.20).
- Platforms: `linux.x86_64`, `web.wasm32` (`threads=yes`; the web is threaded only, the owner's decision of 2026-11-28), `windows.x86_64` (MinGW-w64; `native.sh` refuses a DLL that imports MinGW's runtime DLLs). macOS is not a target.
- Every build has the module; a platform that doesn't build fails the run. `SPELLMERGE_NATIVE=required` makes comparing tests fail if the module did not load. `NATIVE=0` is local only; CI refuses it. `native = false` on the manager (or `stress.gd -- --no-native`) runs the GDScript with the module loaded.

## Adding a kernel

1. Find the loop in a profile first (`tests/benchmark/`).
2. Write it in `src/` as a method of that object's kernel or a new class: add it to `register_types.cpp`, `NATIVE_CLASSES` in `ci/smbot/rules.py` and `core/native/native.gd`, and any engine class it calls to `build_profile.json`. Mirror the GDScript line by line, float types included.
3. Call it from GDScript where the loop was, keep the loop as the `else`, add its constants to `check`. Threads only for loops whose items write only their own, measured on one thread and several.
4. Cover it in the object's side-by-side test, every branch reached; prove the test fails when one rounding or branch in the C++ changes.

## Allowed files

`.cpp` and `.h` in `src/` (Claude's), `SConstruct` and `build_profile.json` (the owner's), this README. Nothing built.

The C++ is checked by `smbot.rules` (`check_native_source`): it includes only the engine classes in the profile (`NATIVE_CLASS_HEADERS`), godot-cpp's core and variant headers, a few standard headers (`NATIVE_STD_HEADERS`) and its own; it calls nothing that reaches the system (programs, files, sockets, loading code, assembly) or the engine by name (`call`, `get_singleton`, the raw interface but `object_get_instance_from_id`). Threads are `src/jobs.cpp`'s alone (`NATIVE_THREADS_FILE`): only it includes `thread`, `mutex`, `condition_variable` and `atomic` and makes a `std::thread`; no file calls `pthread_*`, `std::async` or the system's threads. It computes on the arrays the game hands it, and reads (and sets a plain member of) the bodies it is handed by instance id ("Bodies read by a kernel" above).

History and reasons: [docs/history/native-README.md](../docs/history/native-README.md).
