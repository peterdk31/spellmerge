# Bench

## Purpose

The benchmark that ships in the game (D1; the owner's decision of 2026-11-22: the game is optimised for the Windows and Linux builds, measured on the owner's own PC), and the runners and bots it is made of, which the tests' benchmarks (`tests/benchmark/`) and the bot tests (`tests/bots/`) use too. `tests/` is never exported, so what a shipped build runs lives here.

**Running it** (any shipped build, Windows or Linux):

- Windows: in the game's folder, Shift + right-click, "Open in Terminal" (or a Command Prompt there), then `Spellmerge.exe -- --benchmark`. A shortcut works too: add ` -- --benchmark` after the target's quotes.
- Linux: `./Spellmerge.x86_64 -- --benchmark` in the game's folder.
- Options after it: `--picture=1280x720` draws the game's picture at that size (the default is the game's own 640×360, scaled up); `--only="1p near,4p apart equal"` runs those scenarios alone (the labels below, comma separated).

It plays, on the fixed clock (one simulation tick a drawn frame, the fights from a fixed script, so every run plays the same: `fixed_steps.gd`), the play frames' scenarios at the desktop's settings in a generated crypt biome of seed 11: `1p start` (one wizard where the run puts it), `1p near` (one wizard in a fight room with no foe), `1p far` (one wizard among foes, zoomed out), `2p apart dynamic` and `4p apart equal` (each wizard in a fight room of its own, the split screen in each mode); each warms up 3 s and is measured for 10 s of game time. Then it shows a results screen to screenshot and writes the same table to `user://benchmark.txt` (Windows: `%APPDATA%\Godot\app_userdata\Spellmerge\benchmark.txt`; Linux: `~/.local/share/godot/app_userdata/Spellmerge/benchmark.txt`; the screen names the path): the build, renderer and driver, GPU and its driver, OS, CPU and cores, window and picture, then a row a scenario: the frame's mean, 95th percentile and worst ms, the simulation's ms a frame (the Tick's steps), Feel's step, the GPU's and the renderer's CPU time where Godot reports them, and the draw calls and primitives a frame. Esc (or B) quits.

## Contract

- `benchmark.gd`: the shipped mode, started by the main menu on the user argument `--benchmark` (hud/menus/main_menu). It is `play_frames_runner.gd` with the default scenarios, and its end (`_finished`) shows `results_screen.gd` and writes the file in place of quitting. `machine_info.gd` reads what it ran on.
- `stress_runner.gd` → `biome_frames_runner.gd` → `play_frames_runner.gd`: the runners (each file's header says what it measures and its `BENCH:` lines). `biome_frames_runner.gd` keeps a summary a scenario (`summaries`), which `benchmark.gd` shows. Their command lines are in `tests/benchmark/` (`stress.gd`, `biome_frames.gd`, `play_frames.gd`, SceneTree scripts) and the main menu's `--stress` and `--split-views`.
- `fixed_steps.gd` (the fixed clock), `probe.gd` (a frame's parts), `draw_census.gd`, `tree_profile.gd`, `hash_label.gd`, `error_log.gd` (the errors logged while a runner runs), `pinned_run.gd` (a run on one room): the runners' tools.
- `bots/`: the bots that play a seat through its input frames (`bot.gd`, `bot_route.gd`, `bot_builds.gd`, `bot_hub.gd`, `staff_fuzzer.gd`, `bot_profile.tres`; tests/bots/README.md says how they play). Their tests stay in `tests/bots/`.
- Not game logic: nothing in the game reads this folder; it reads the game as a player and a profiler would (autoloads by name, events, input frames). File access only in `user://` (the results file, `--shots`' screens), no network, no programs started: the hard rules hold here as anywhere in the game.

## Allowed files

Claude only (it ships in every build and drives the game). Typed GDScript, `.tres`, and their `.uid` files.

## Steps

A new scenario is a row in `play_frames_runner.gd`'s `play_rows()` (or `biome_frames_runner.gd`'s); to run it by default in the shipped benchmark, add its label to `benchmark.gd`'s `DEFAULT_LABELS`.

## Example to copy

`benchmark.gd`: a runner that changes which scenarios run and what happens at the end.

## Validate

```sh
tools/check.sh
tools/ptest.sh 4 'bench|benchmark|bots'
xvfb-run -a -s "-screen 0 1280x720x24" build/godot/Godot_v4.7.2-stable_linux.x86_64 --path . -- --benchmark --only="1p near"
```
