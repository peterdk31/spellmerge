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

New tests extend `tests/support/suite.gd` (`extends "res://tests/support/suite.gd"`). Every method named `test_*` is one test: it builds what it needs, checks one behaviour with `check(condition, message)` or `check_equal(actual, expected, message)`, and the suite frees whatever was handed to `own(object)`. A failing test is reported by name and never changes the next test. Copy `tests/gameplay/ai/test_ai_telegraph.gd` (a fixture and many short tests) or `tests/core/test_svg_art.gd` (a data-driven check over many files).

- **One behaviour per test**, named for it (`test_a_wizard_who_steps_aside_is_not_hit`). If the name needs "and", split it.
- **Shared setup goes in `before_each` or a fixture file** (a script in `tests/support/` or next to the tests, not named `test_*`), never in leftover state from a test before.
- **Check behaviour, not looks or numbers.** Don't assert a pixel colour, a sprite's exact size, a child's position, a count of decorations or a tuning number (a speed, a damage) unless that is the contract. Check what has to stay true: the shot comes when the telegraph ends, the floor covers the room, a spawn can be reached. Then an art or balance change does not break a test.
- **Look rules are checked once, for every file,** by a data-driven test (`test_svg_art.gd` for SVGs), so a new asset is covered without a new test.
- **Don't test one thing in two places.** If a bigger test already covers it, split the big one instead of adding a copy.
- Old test files (one `_initialize` that runs every check) still work; when you touch one, move the part you touch to the suite (`docs/BACKLOG.md`).

## Folders

- `smoke/`: the boot smoke test (`boot_smoke.gd`), which starts the main scene and fails unless the menu comes up, and the 4-bot smoke test (`four_bot_smoke.gd`): four bots join and play the first room, bot 4 idles in its builder, and it passes only if `room_cleared` arrives, players 1–3 are alive or revived, bot 4's overlay stayed open, and the log has no `push_error`, no `ERROR:` line and no "the restart failed" warning. `error_log.gd` is its error logger (unit test `test_error_log.gd`). The checks live in the node `four_bot_runner.gd`; `four_bot_smoke.gd` (a `SceneTree` script) adds it to the root, and `test_four_bot_smoke.gd` runs that under `build.sh --quick --tests`. An exported binary hangs on `--script` while the autoloads start, so in the `Linux Test` export the main menu adds the same node when the user argument `--four-bot` is given and the file exists: `build/linux-test/Spellmerge.x86_64 --headless -- --four-bot`. A build that fails a smoke test is broken.
- `benchmark/`: the performance checks. `probe.gd` rides along in the 4-bot test and prints `BENCH:` lines (frame time, peak nodes, projectiles, memory, live hit particles); `projectile_timing_runner.gd` times the projectile manager at both caps with four players (`test_projectile_timing.gd` starts it from the command line). Both it and the stress run are also nodes the main menu adds in the Linux Test and Web Test exports on the user argument `--projectile-timing` or `--stress`, like `--four-bot` (`build/linux-test/Spellmerge.x86_64 --headless -- --stress`); in the web export they give the WASM numbers. `stress.gd` is the stress scene (from the command line: `godot --headless --path . --script res://tests/benchmark/stress.gd`; about a minute, longer in the web export): 4 bots with built spells on the real game, 100 enemies and 500 shots (web; the web cap, `DEFAULT_CAP_WEB`), then 200 and 3,000 (desktop), full effects; between them the web scenario runs again with the render loop off and with hit particles off, and each scenario prints `BENCH: frame parts` (physics steps per frame, physics, process and renderer time) and `BENCH: stress parts` (enemy step, combat lookups, Feel's step) to explain a slow web frame. It prints `BENCH:` lines and `STRESS OK`; `test_stress.gd` runs a short version in the build. They print and gate nothing: over a budget, and for a frame-time regression over 10%, the plan is a warning with likely fixes, never a broken build (docs/PLAN.md, "Gates are sparse"). Headless numbers (not web numbers) are in `docs/LOG.md`. `fire_cap.gd` (with `fire_cap_runner.gd`; a few minutes, not run in the build) sweeps the per-step fire pacing (`Spells.fire_shots_per_step`) over trigger-heavy staffs of the real cards and times what one payload fire costs (a burst of `on hit` shots against the same burst without, paced and not), for tuning that pacing; `fire_cap_view.gd` shows the same burst in a window on the real autoloads, with a graph of the step time (`godot --path . --script res://tests/benchmark/fire_cap_view.gd`; keys 1-3, P, T, Space) (owner, 2026-10-29).
- `build.json`: the build settings: the size and load-time budgets (they only warn), and which of these runs `ci/build/build.sh` starts in the `Linux Test` and `Web Test` exports: per run its user argument, the line its log must have on Linux and on the web, the web timeout, and whether its result lines go into the Daily log (`bench`); `ready` is the line the main menu prints. Add a run here when the main menu starts a new runner on an argument; only Claude's PRs may change the file, and the hard rules refuse a value `smbot.config.parse_build` can't read.
- `bots/`: the bots that play headless runs for smoke tests and playtest reports. `bot.gd` plays one slot through a virtual device and the real input path (`PlayerInput.send_virtual`): a fighter is a state machine (owner, 2026-11-01: APPROACH, ATTACK, DETOUR, UNSTICK, DODGE): it walks at the nearest enemy, walks round a wall in its line of fire (`AISight`, room walls and Wall cards alike) instead of firing into it, holds its attack staffs `staff_2` and `staff_3` (RT and LB) with the line clear, keeps a staff whose next cast puts up a wall (`Caster.next_cast_traits`, `BLOCKS`) for cover, tapped at a telegraphed shot with the right stick aimed at it, and else taps `staff_1` (RB, the dash staff) off the shot, an idler only taps `back` (B, its builder). A bot reads no spell field; the player calls the spell's one cast method. A bot can also build (`build_random(seed)`: a seeded random staff from `staff_fuzzer.gd`, sent slot by slot as `staff_change_requested` into staff 3) and open its builder (`open_builder()`, one press of B). `test_spell_fuzz.gd` compiles and casts 300 seeded random staffs (`staff_fuzzer.gd`) in the combo arena and fails on an error line, a cycle that runs away or a staff that never casts; shots dropped at the pool and slow steps are reported (with the costliest staffs), not failed, since there are no build limits.
- `screenshots/`: scripts named `shot_*.gd` that set up a scene and save 640×360 PNGs (and crops of them) to `user://screenshots/`. Each extends `tests/support/screenshot.gd` and stages its shots in `take()`, with the base's helpers (`need`, `settle`, `shot`, `snap`, `save_crop`, `tap`, `lay_floor`, `place`, `label`); before `take()` the base compiles the shaders as Play does (`support/warm_up.gd`: Flow's play tasks through `Loading`), so every shot is taken after the game's own start (a script that shows the load itself, `shot_loading.gd`, sets `warm_first = false` in `_init()`; the clip recorder warms up the same way); it is not a test and only fails when a staged state did not happen. The build copies the PNGs to `build/screenshots/`; they are posted on every bot PR and on the site's `/screenshots/` page by the daily build. The build runs up to 8 at once, each on its own `xvfb-run` display (or on `$DISPLAY` when `xvfb-run` is missing) and with `--fixed-fps 60`, so a frame is always 1/60 s of game time however busy the machine is: a script waits in frames or with `wait_for`, never on the clock. One script: `SHOTS_ONLY="shot_cards" ci/build/build.sh --quick --screenshots`, or `godot --path . --fixed-fps 60 --script res://tests/screenshots/shot_<name>.gd` on a display. `shot_cards.gd` finds every card through the registry, so a new card shows up on `cards_sheet` with no edit (the sheet goes on to `cards_sheet_2` and on when the cards fill a screen).
- `clips/`: the clip recorder (#245). `record.gd` casts one scripted scenario per clip on a stage (`stage.gd`: the real spell runtime, projectile manager, combat and Feel, fresh for each clip, stepped by hand 1/60 s at a time) and saves a frame sequence to `user://clips/<id>/`: `meta.json` (`{"id", "kind", "title", "fps"}`, fps 20) and `frame_0000.png` and up, 320×180 game pixels around the middle of the action, at most 240 frames and 3.5 MB per clip (the format is read by `ci/smbot/clips.py`). `ci/build/build.sh --quick --clips` runs it under `xvfb-run` (a headless run has no pixels), copies the folders to `build/clips/` and the pipeline turns them into animated PNGs. Clips are build output and are never committed. The user arguments are the ids to record (none means all; `--list` prints them): `CLIPS_ONLY="combo_shatter reaction_thaw" ci/build/build.sh --quick --clips`. `scenarios.gd` reads the scenarios from the content, so a new row or component is a clip with no code change:
  - `combo_<id>`: every combo file in `content/spells/combos/`, cast as the row says (`casts` as card rows, `imps`, `seconds`), the same scripted cast as `test_combos.gd`.
  - `form_<id>`, `element_<id>`, `modifier_<id>`, `trigger_<id>`: one per component in the registry, alone (a bolt for an element or a modifier, a bolt that holds a nova for a trigger), against three imps.
  - `reaction_<id>`: one per reaction in `reactions.tres`: a bolt of the element that gives the status, then 0.3 s later a bolt of the row's element. `reaction_<id>_coop`: the same with two players standing apart, one bolt each.

  `test_clip_scenarios.gd` (headless) checks the scenarios, that every reaction clip sets its reaction off and that a stage played twice gives the same simulation; the frames themselves need a display. Two takes of a clip are identical frame for frame, because Feel's hit sprays (CPU particles, which follow real frame time) are left out; to check, run the recorder twice and `diff -rq` the two `build/clips` folders (docs/DECISIONS.md, 2026-10-25).
- `support/`: the suite base class (`suite.gd`) and the screenshot base class (`screenshot.gd`) and the warm-up the screenshots and clips start with (`warm_up.gd`). Fixtures shared by several tests live here (`staff_kit.gd` for old recipe shapes as card rows; `fake_cards.gd`, any number of made-up cards behind a stand-in registry, for the radial builder's tests and screenshots); a fixture for one area lives next to its tests (`tests/gameplay/ai/ai_fixture.gd`, `tests/content/rooms/room_scan.gd`). Nothing here is named `test_*`, so the build does not run it as a test.
- Everything else mirrors the tree (`tests/core/...`, `tests/gameplay/...`).

## Allowed files

`.gd`, `.tscn`, `.tres`, `.json` and Godot's `.uid` files. Limit: 1 MB per file.

## Steps

1. Find the area your change is in and use the mirrored path under `tests/` (for example `tests/core/` for `core/`).
2. Write the test as typed GDScript. Cover more than one player index where it matters; use a fixed seed and no real-time waits.
3. For a bug fix, write the regression test first and check that it fails without the fix.
4. Run it (see "Run" below), then run the checks under "Validate".
5. Open a PR using the template.

## Example to copy

`tests/smoke/boot_smoke.gd`, the boot smoke test. Copy its structure for a new test.

## Run

```sh
ci/build/build.sh --quick        # downloads the pinned Godot once, imports, runs the editor smoke test
ci/build/build.sh --quick --tests  # the same, then every tests/**/test_*.gd (about a second each)
ci/build/build.sh --quick --screenshots  # the same, then every tests/screenshots/shot_*.gd on a virtual display
```

Rules every unit test script (a `SceneTree` script) follows, learned the hard way:

- Start `_initialize()` with `await process_frame`. The root joins the scene tree only after `_initialize` returns, so before that nodes added to `root` are not in the tree (no `_ready`, no `global_position`, no absolute `get_node` paths).
- The real autoloads exist in the run (`Events`, `Projectiles`, `Combat`, ...). A test of "autoload missing" takes the node out of `root` and puts it back.
- Nodes that the projectile manager must see as targets have to be in the tree.
- The log must have no line starting `ERROR:` or `SCRIPT ERROR:` (the build fails on it); warnings are fine. Free what you create and stop audio players before the end; wait a moment (`await create_timer(0.3).timeout`) so the audio server lets go, or the exit reports leaks and a resource in use.
- Do not `preload` a scene that is also an autoload (like `hud/panels/panels.tscn`): the autoload then fails to load at start. Use `load()` inside the test.
- Compare typed arrays with typed arrays: an `Array[StringName]` never equals an untyped `[&"a"]`.
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
