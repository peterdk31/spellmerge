# Tests

## Purpose

Tests for the whole game. The tree mirrors the code: a test for `gameplay/combat/` lives in `tests/gameplay/combat/`. Three special folders hold the checks that run on every build: `smoke/`, `benchmark/` and `bots/`.

**Outside PRs are accepted only as tests that accompany content.** A contributor who adds content may add a test at the mirrored path; it is welcome but never required (Claude adds a missing test in a follow-up). Claude owns the rest of the tree.

## Contract

- Every code change comes with tests. Every bug fix comes with a regression test that would have caught it.
- Tests may depend on any area; no area depends on tests.
- Typed GDScript, like all code, and no banned APIs (AGENTS.md, hard rules).
- Tests never assume a single player: cover more than one player index where it matters.
- Tests are fast and deterministic: no real-time waits, and a fixed seed for any randomness.

## Folders

- `smoke/`: the boot smoke test (`boot_smoke.gd`), which starts the main scene and fails unless the menu comes up. The 4-bot smoke test (M1) goes here too. A build that fails a smoke test is broken.
- `benchmark/`: the stress benchmark. A frame-time regression over 10% counts as a broken build.
- `bots/`: the bots that play headless runs for smoke tests and playtest reports.
- `screenshots/`: scripts named `shot_*.gd` that set up a scene and save 640×360 PNGs to `user://screenshots/` (they check nothing). The build copies them to `build/screenshots/`; they are posted on every bot PR and on the site's `/screenshots/` page by the daily build. Needs `xvfb-run`.
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

## Rating questions

Besides the standard criteria (fit, fun, quality, value, performance, risk, scope):

- Does it cover more than one player index where it matters?
- Is it fast and deterministic (no real-time waits, fixed seed)?
- For a bug fix, does it fail without the fix?
