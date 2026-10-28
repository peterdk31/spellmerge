# Flow

## Purpose

Room sequence, door voting, transitions and waiting for builders.

Built in M3 (see "Gameplay sub-areas" in docs/PLAN.md).

Players in the spell builder never block the others: the rest keep playing.

## Contract

- **Public entry script:** `gameplay/flow/flow.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. It is the autoload `Flow` (registered in `project.godot`).
- **What exists (M1 slice):** on `play_requested` it asks `core/registry` for the room and enemy named by `room_id_to_play` and `enemy_id_to_play` (defaults `arena_01`, `ember_imp`; players come from `wizard_scene`) and the four staffs of the build channel (`staffs_for_channel()`: the starter heads `STARTER_HEADS`, curl, star, moon and crystal, one per button, under `wizard` in the registry; in `dev` and `preview` builds each a copy with the `dev` staff's numbers; a missing one starts no run: it logs a warning and stays idle). `start_cards` are four lists of card ids (default: A `dash`, X `fire bolt`, Y and B empty); every player gets the staffs and copies of the cards and builds them itself, so flow holds no spell (staffs A6a), and builds one world node (room scene, a camera, a player for every player slot that has a device, the fixed wave) that becomes the current scene. It sends `room_entered`, and `room_cleared` when the last enemy of the wave has died. When every player is down it restarts the room after `RESTART_DELAY` (2 seconds): new world, full health, new wave, no shots left, and `Spells.clear()` (every cooldown and build is forgotten; the new players build the start staffs again). A player who leaves and rejoins mid-run gets the start staffs again. The restart also happens when the last enemy dies after everyone is down. If a restart cannot start (content missing) it logs an error and flow goes idle, so Play can start again. Play with the mouse joins the keyboard as P1 only when nobody has joined; anyone already joined (for example a gamepad) plays as they are. A second `play_requested` while a run is on is ignored. `stop_run()` ends the run (tests use it). Mid-run joins and leaves: on `player_joined` a player is added at that slot's spawn, on `player_left` it is removed (the camera, which `coop` drives, has limits set to the room). Door voting, the room sequence and the run lifecycle arrive in M3, which replaces this slice. `run_started` and `door_vote_requested` are not used yet.
- **The intro (living staffs H6, `intro.gd`):** on a new save (`save`, a `SaveFile`, without the `INTRO_SEEN` flag) `play_requested` shows the intro first (state `INTRO`, the node `Intro` as the current scene; `wants_intro()`, `play_intro(requester)`): one staff dropped per joined player (`drops()`, `drop_time`, `hit_time`), `LENGTH` 14.5 s whatever the number of players. Any joined player's accept, back, pause or staff button skips it at once for everyone (press counts, so no tap is lost); played out or skipped, the save gets `INTRO_SEEN` and the run starts as above. Flow's `step` steps it, so tests drive it with fixed deltas. It plays only for people: `intro_enabled` is false when a test script is the main loop or the game was started with user arguments (`--four-bot`, `--stress`, the timing run); a test switches it on with a save of its own. The sandbox never shows it. `stop_run()` ends an intro too. Its captions are in `intro.gd` until `content/story` has a schema for cutscenes (M3).
- **Waves (M1 slice):** wave 1 is `WAVE` (8 imps); `BUILD_BREAK` (12 s, a fixed build break: nobody's building holds it back or speeds it up; `build_break_started(seconds)` follows `room_cleared`, `build_break_left()` reads it) after each `room_cleared` the next wave stands in the same world with `WAVE_GROWTH` (2) more enemies, up to `WAVE_MAX` (24). Shots in flight are cleared, downed players are revived and protected. `wave_started(wave)` is sent for every wave, including wave 1 right after `room_entered`; `Flow.wave` holds the number. A lost room restarts after `RESTART_DELAY` (1.5 s) at wave 1.
- **Sandbox (staffs B7):** `sandbox_requested` (the main menu's Sandbox button, shown in `dev` and `preview` builds) starts a run in the room `sandbox` (`SANDBOX_ROOM_ID`) instead: no waves and no `wave_started`; the dummies `DUMMY_IDS` (`training_dummy`, `shooting_dummy`, from `enemies` in the registry) stand at the room's `dummy_spawns`; `sandbox_changed(true)` follows `room_entered` (every other run start sends `sandbox_changed(false)`, and `stop_run()` of a sandbox too). `sandbox_action_requested(player, action)`: `imp_wave` adds imps the size of wave 1, while fewer than `WAVE_MAX` are up; `reset_dummies` frees the dummies and stands fresh ones; anything out of the sandbox is ignored. Clearing the imps sends no `room_cleared` and starts no break. When every player is down, after `RESTART_DELAY` they all stand up where they are, protected, with their staffs kept (no restart). `Flow.sandbox`, `dummies()`.
- **Known gaps:** no reward, no next room and no way back to the menu (M3); the numbers are constants in `flow.gd`, tuned at C1.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `room_entered`, `room_cleared`, `wave_started`, `build_break_started`, `sandbox_changed`, `door_voted`.
  - Listens to: `enemy_died`, `run_started`, `player_downed`, `player_joined`, `player_left`, and from the HUD `play_requested`, `sandbox_requested`, `sandbox_action_requested` and `door_vote_requested` (`door_voted` is flow's announced result of the vote; `room_entered` follows `play_requested`).
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

`gameplay/flow/flow.gd` and its test `tests/gameplay/flow/test_flow.gd` (run with `godot --headless --path . --script res://tests/gameplay/flow/test_flow.gd`). The test runs on the real autoloads, drives time through `Flow.step(delta)` and covers 1, 2 and 4 players.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

A good PR here changes room order, door voting or transitions, and keeps the no-waiting pillar: one player in the builder never stalls the rest. Besides the general review:

- Does a player idling in the builder block anyone? Does voting work for 1–4 players?
- Does it keep to the dependency direction, without calling another area directly?
