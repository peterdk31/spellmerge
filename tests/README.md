# Tests

## Purpose

Tests for the whole game. The tree mirrors the code: a test for `gameplay/combat/` lives in `tests/gameplay/combat/`. Three special folders hold the checks that run on every build: `smoke/`, `benchmark/` and `bots/`.

## Contract

- Every code change comes with tests. Every bug fix comes with a regression test that would have caught it.
- Tests may depend on any area; no area depends on tests.
- Typed GDScript, like all code, and no banned APIs (AGENTS.md, hard rules).
- Tests never assume a single player: cover more than one player index where it matters.
- Tests are fast and deterministic: no real-time waits, and a fixed seed for any randomness.

## How to write a test: small and isolated

New tests extend `tests/support/suite.gd` (`extends "res://tests/support/suite.gd"`). Every `test_*` method is one test: it builds what it needs, checks one behaviour with `check(condition, message)` or `check_equal(actual, expected, message)`, and the suite frees whatever was handed to `own(object)`. Copy `tests/gameplay/ai/test_ai_telegraph.gd` (a fixture and many short tests) or `tests/core/test_svg_art.gd` (a data-driven check over many files).

- **One behaviour per test**, named for it. If the name needs "and", split it.
- **Shared setup goes in `before_each` or a fixture file** (not named `test_*`), never in leftover state from a test before.
- **Check behaviour, not looks or numbers:** no pixel colours, sprite sizes, child positions, decoration counts or tuning numbers unless that is the contract.
- **Look rules are checked once, for every file,** by a data-driven test.
- **Don't test one thing in two places.**
- Every unit test is a suite; only the runners that are not unit tests (`benchmark/`, `smoke/test_four_bot_smoke.gd`, `bots/test_room_balance.gd`) are `SceneTree` scripts of their own.
- A test on the game's bus waits for a command it sent with `await commands_applied()`.

## How the tests run

`ci/build/unit_tests.sh` runs them (for `build.sh --tests` and `tools/ptest.sh`), one Godot process per core, longest first, each with `--fixed-fps 60`: a test counts game time in frames or deltas, never on the clock.

- Suites run 8 to a process (`tests/support/run.gd`), each on a fresh game. A file that fails in its batch but passes alone still fails: a file before it left state behind; find and clear it. By hand: `godot --headless --path . --script res://tests/support/run.gd -- res://tests/<area>/test_<name>.gd`; a `SceneTree` runner is `--script res://tests/<area>/<name>.gd`.
- A file that needs a process of its own says `# unit-test-alone`; a long file says `# unit-test-shards: N`.
- A test that hashes state hashes only what it compares (the state hash is most of the suite's time).

### Tests that time the machine

A wall-time budget is never one reading of `Time.get_ticks_usec` against fixed milliseconds. Time it through `tests/support/wall_clock.gd` (`fastest_usec`, or `against` a reference workload: `gdscript_reference`, `native_reference`), with the usual multiple measured on a quiet machine times a slack of 1.5, native kernels on one thread. A PR that makes the work cheaper or dearer for good moves the multiple, with its numbers. A test that only reports a time fails nothing. Tests: `support/test_wall_clock.gd`.

## Folders

- `smoke/`: `boot_smoke.gd` (the menu comes up) and the 4-bot smoke test (`four_bot_smoke.gd`, checks in `four_bot_runner.gd`, run by `test_four_bot_smoke.gd`; exported: `build/linux-test/Spellmerge.x86_64 --headless -- --four-bot`). A build that fails a smoke test is broken. **The pinned seed:** it plays `REPLAY_SEED`, which must be a seed the bots win; a content change that loses it moves `REPLAY_SEED` to a won seed and says why, never loosening the checks. `smoke/renderer_shaders.gd` compiles every shader under a renderer (needs a display).
- `benchmark/`: the command lines of the performance runs and their tests; the runners and the bots ship in `bench/` (the main menu's Benchmark). They print `BENCH:` lines and gate nothing: `stress.gd`, `biome_frames.gd`, `play_frames.gd`, `tick_hash.gd` (a perf round's simulation numbers, `--profile-steps`), `hub_storm.gd`, `shot_gpu.gd`, `shot_scale.gd`, `split_views.gd`, `ai_step.gd`, `combat_hit.gd`, `prop_cost.gd`, `cover_cost.gd`, `fire_cap.gd`, `net_grid.gd`. A run the main menu starts on a user argument is listed in `build.json`. Arguments and outputs: the history file.
- `build.json`: build budgets (warnings only) and the runs `ci/build/build.sh` starts in the test exports. Only Claude's PRs change it; it must parse with `smbot.config.parse_build`.
- `bots/`: the bots' tests and `playtest.gd`; the bots are in `bench/bots/` ([tests/bots/README.md](bots/README.md)). A bot fills a seat's input frames like a device and never reads a spell field. `playtest.gd` plays a whole biome and prints a report: `godot --headless --fixed-fps 60 --path . --script res://tests/bots/playtest.gd -- --players=4 --seed=11` (more arguments: the history file). `test_spell_fuzz.gd` casts 300 seeded random staffs.
- `screenshots/`: `shot_*.gd` scripts extending `tests/support/screenshot.gd`, staging shots in `take()`. They wait in frames or `wait_for`, never on the clock. One script: `SHOTS_ONLY="shot_cards" ci/build/build.sh --quick --screenshots`.
- `clips/`: the clip recorder (`record.gd`, `stage.gd`, `scenarios.gd` reads scenarios from content; format read by `ci/smbot/clips.py`); clips are never committed. `test_clip_scenarios.gd`.
- `platforms/`: `replay_hashes_runner.gd`, the same state hashes on every platform (`tools/platform_hashes.py`).
- `net/`: online play tests (`net_pair.gd` links two scripted fights).
- `sound_room/`: a scene to listen to every sound (`godot --path . res://tests/sound_room/sound_room.tscn`); `test_sound_room.gd`.
- `support/`: `suite.gd`, `screenshot.gd`, `warm_up.gd`, `wall_clock.gd` and shared fixtures (`fresh_game.gd`, `replay_run.gd`, `fake_cards.gd`, `dev_hub.gd`). Nothing here is named `test_*` but the support's own tests. A fixture for one area lives next to its tests.
- Everything else mirrors the tree (`tests/core/...`, `tests/gameplay/...`).

### The seed sweep

`tests/smoke/four_bot_sweep.gd`: a balance signal that gates nothing and runs in no build; plays the 4-bot run for many seeds and prints `SWEEP RESULT`. `godot --headless --fixed-fps 60 --path . --script res://tests/smoke/four_bot_sweep.gd -- --seeds=1-100`; replay a lost seed with `four_bot_smoke.gd -- --replay-seed=N`.

## Allowed files

`.gd`, `.tscn`, `.tres`, `.json` and Godot's `.uid` files, and the sound room's fixture sounds (`sound_room/fixtures/`: `.ogg` and their `.import`, baked by `tools/sound_fixtures.py`). Limit: 1 MB per file.

## Steps

1. Use the mirrored path under `tests/` for your area.
2. Write the test as typed GDScript; more than one player index where it matters; fixed seed, no real-time waits.
3. For a bug fix, write the regression test first and check that it fails without the fix.
4. Run it, then the checks under "Validate".
5. Open a PR using the template.

## Example to copy

`tests/smoke/boot_smoke.gd`, the boot smoke test. Copy its structure for a new test.

## Run

```sh
ci/build/build.sh --quick        # downloads the pinned Godot once, imports, runs the editor smoke test
ci/build/build.sh --quick --tests  # the same, then every tests/**/test_*.gd and each card's own content/spells/**/test_<id>.gd
tools/ptest.sh 4 'test_staff'      # after one build: only the test files whose path matches, 4 processes at once
ci/build/build.sh --quick --screenshots  # the same, then every tests/screenshots/shot_*.gd on a virtual display
```

Rules every unit test follows:

- A suite reads the tree through its own members (`root`, `process_frame`, `physics_frame`, `paused`, `current_scene`, `call_group`); a helper that takes the `SceneTree` is handed `tree`, never `self`. A `SceneTree` runner starts `_initialize()` with `await process_frame`.
- Leave nothing behind: free what you add to `root` (`own()` it), stop a run you started, unpause the tree, restore static members and project settings.
- The real autoloads exist in the run. A test of "autoload missing" takes the node out of `root` and puts it back.
- Nodes the projectile manager must see as targets have to be in the tree.
- The log must have no line starting `ERROR:` or `SCRIPT ERROR:`. Free what you create and stop audio players before the end (`await create_timer(0.3).timeout`).
- Never `preload` a scene that is also an autoload (like `hud/panels/panels.tscn`); `load()` it inside the test.
- Compare typed arrays with typed arrays.
- Signal handlers must take every argument of the signal.

The Python tests for the CI scripts are in `ci/tests/` and are owner-maintained.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

Besides the general review (bugs, edge cases, 1–4 players, performance, clarity, fun):

- Does it cover more than one player index where it matters?
- Is it fast and deterministic (no real-time waits, fixed seed)?
- For a bug fix, does it fail without the fix?

History and reasons: [docs/history/tests-README.md](../docs/history/tests-README.md).
