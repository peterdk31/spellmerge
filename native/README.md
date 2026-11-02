# Native

## Purpose

Spellmerge's own C++, loaded by Godot as a GDExtension: faster versions of hot loops the game already has in GDScript. The game runs the same without it: where the module is not built, the GDScript it stands for runs.

| Class | What it runs | GDScript it stands for |
|---|---|---|
| `ShotKernel` (`src/shot_kernel.cpp`) | the step's common pass, the hit pass's shots that need no event, the behaviour passes growth, linger, orbit, return, homing (with its search) and spiral, trail sampling, the draw batches' writing, the threat grid | `core/projectiles/projectile_manager.gd` |
| `SwarmKernel` (`src/swarm_kernel.cpp`) | the horde swarm's spacing and its move onto the floor, its look's step and batch writing | `gameplay/horde/swarm.gd`, `swarm_look.gd` |

What stays GDScript on purpose: anything that sends an event or calls gameplay (hit handlers, the move, stuck and shield passes, the swarm's chase and Combat's reads), and node work (actor looks, sprites, shader parameters), which costs the same from C++. Profile first: `tests/benchmark/`, and the parts lines of `stress.gd`.

The owner lifted hard rule 4's ban on native code for this module (2026-11-02, docs/DECISIONS.md). Contributors still can't add native code: this folder is Claude's and the owner's only (`ci/smbot/rules.py`).

## Contract

- **Same results, to the bit.** Every kernel method does exactly what the GDScript it stands for does, on the same arrays: same branches, same float rounding (a GDScript `float` variable is a double; `Vector2` and `PackedFloat32Array` are single precision; see the top of `src/shot_kernel.cpp`; `src/packed.h` has GDScript's helpers). Engine behaviour is called, not copied: the random pick's `hash`, `wrapf`, `move_toward`, a `RandomNumberGenerator`'s draws. The GDScript stays as the reference and the fallback. Each kernel has a test that steps both side by side and compares every packed array byte for byte: `tests/core/test_native_kernel.gd` (with the draw buffers and the threat answers), `tests/gameplay/horde/test_native_swarm.gd` (with node positions and the batches). The recording tests hold both to their recordings: `test_projectiles_step_exact.gd`, `test_swarm_steps.gd`.
- **The object's arrays, in place, for one call.** A kernel method takes the object (the manager, the swarm, the look) and reads its packed arrays with `get`. It writes through their buffers, which it shares with the object's members, and keeps no reference once it returns. A reference kept past the call would make every later GDScript write copy the array. Nothing else may keep a copy of those arrays and expect it to stay as it was. The object sizes every array before a call; a kernel never grows one, since growing would give the kernel its own copy. A buffer handed to the renderer is the exception: it is written with `ptrw`, so one the renderer still holds is copied, not overwritten.
- **Hand back what needs GDScript.** Anything that sends an event stays in GDScript. The native hit pass walks the shots that need nothing of GDScript and hands back each one that does (a hit, a wall, an end, a wait for a pass other than its homing search), in turn, so events go out in the same order. The manager then calls it again from the next shot. A homing shot that waited for its search is searched, turned and hit-tested by the kernel itself. A pass whose shot circles or returns to another shot leaves it waiting for GDScript, as before.
- **Constants are checked or handed over.** `ShotKernel` holds copies of the manager's constants; `ShotKernel.check` compares them when the manager starts, and a mismatch is an error and runs the GDScript. When a constant changes in GDScript, change it here too and add it to the check. `SwarmKernel` is handed the numbers it needs instead (`configure`: the swarm's wall cell, the Face's and CreatureLook's numbers), so they live in GDScript only.
- **One loader.** `core/native/native.gd` is the only GDScript that asks whether the module is loaded and makes its classes, by literal name (`NATIVE_FILE` in the rules).
- **Nothing built is committed** (hard rule 2 still holds). `ci/build/native.sh` builds the libraries into `native/bin/` and writes `native/spellmerge.gdextension` naming the ones that exist. Both are ignored by git, so are SCons' object files.

## Building

```sh
ci/build/native.sh linux web windows     # the libraries and the .gdextension (build.sh runs it first)
```

- **Pinned tools** (`ci/build/godot.env`, kept in `~/.cache/spellmerge-native`): godot-cpp 10.0.0 at its commit, built for the 4.7 API and only for the engine classes in `build_profile.json`, so a build takes seconds; SCons from its hash-checked wheel; Emscripten 4.0.20 for the web. That is the version Godot 4.7's own web templates were built with (godotengine/build-containers, branch 4.7). A side module from any other version may not load.
- **Platforms:** Linux (`linux.x86_64`), the web (`web.wasm32`, no threads) and Windows (`windows.x86_64`, cross-built with MinGW-w64, the C++ runtime linked in). The Web presets use the extension-capable template (`variant/extensions_support=true`), which adds about 1 MB to the download. macOS is not a target.
- **CI** keeps the tools between runs: `native-web-*` for the jobs that build the web (preview, the daily build, the bisect), `native-linux-*` for the quick ones (clips, the bot's sessions), keyed on `ci/build/godot.env`. `native.sh` checks the pins again after a restore: the commits, the wheel's hash, no edited sources. SCons is unpacked fresh into `build/` on every run.
- **Every build has the module** (owner, 2026-11-02). `ci/build/build.sh` builds Linux for `--quick`, the web for `--web`, and all three for a full build. A platform that doesn't build fails the run, and so does an export without its library or an exported test run that ran without it. Once the Linux library is built, `SPELLMERGE_NATIVE=required` makes the comparing tests fail if the module did not load. `NATIVE=0` leaves it out for a local look at the GDScript only; CI refuses it. A full build here needs MinGW-w64 (`x86_64-w64-mingw32-g++`; on Ubuntu `g++-mingw-w64-x86-64-posix`, which the workflows install).
- `native = false` on the manager, a `Swarm` or a `SwarmLook` (or `stress.gd -- --no-native` for all three) runs the GDScript with the module loaded. `test_projectile_timing.gd` times both.

## Adding a kernel

1. Find the loop in a profile first. Most time in a crowd is elsewhere; see `tests/benchmark/`.
2. Write it in `src/` as a method of the kernel for that object, or a new class: add it to `register_types.cpp`, `NATIVE_CLASSES` in `ci/smbot/rules.py` and `core/native/native.gd`, and any engine class it calls to `build_profile.json`. Mirror the GDScript line by line, including the float types.
3. Call it from GDScript where the loop was, keep the loop as the `else`, and add the constants it reads to `check` (or hand them over).
4. Cover it in the object's side-by-side test, every branch reached (force a branch today's content never takes, on both sides). Prove the test can fail by changing one rounding or branch in the C++ and watching it fail; a change that survives means a branch the test does not reach.

## Allowed files

`.cpp` and `.h` in `src/`, `SConstruct`, `build_profile.json`, this README. Nothing built.
