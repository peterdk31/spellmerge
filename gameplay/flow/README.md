# Flow

## Purpose

Room sequence, door voting, transitions and waiting for builders.

**Closed until M5.** Built in M3, opens for PRs in M5 (see "Gameplay sub-areas" in docs/PLAN.md and "Opens for PRs" in docs/ROADMAP.md). Until then Claude maintains it; an outside PR is a gamble.

Players in the spell builder never block the others: the rest keep playing.

## Contract

- **Public entry script:** `gameplay/flow/flow.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. It is the autoload `Flow` (registered in `project.godot`).
- **What exists (M1 slice):** on `play_requested` it asks `core/registry` for the room, enemy and spell named by `room_id_to_play`, `enemy_id_to_play` and `spell_id_to_play` (defaults `arena_01`, `ember_imp`, `bolt`; wizards come from `wizard_scene`), and builds one world node (room scene, a camera, a wizard for every player slot that has a device, the fixed wave) that becomes the current scene. It sends `room_entered`, and `room_cleared` when the last enemy of the wave has died. When every wizard is down it restarts the room after `RESTART_DELAY` (2 seconds): new world, full health, new wave, no shots left, and `reset_cooldowns()` on the bolt (the registry shares one bolt resource between all holders). The restart also happens when the last enemy dies after everyone is down. If a restart cannot start (content missing) it logs an error and flow goes idle, so Play can start again. Play with the mouse joins the keyboard as P1 only when nobody has joined; anyone already joined (for example a gamepad) plays as they are. A second `play_requested` while a run is on is ignored. `stop_run()` ends the run (tests use it). Mid-run joins and leaves: on `player_joined` a wizard is added at that slot's spawn, on `player_left` it is removed (the camera, which `coop` drives, has limits set to the room). Door voting, the room sequence and the run lifecycle arrive in M3, which replaces this slice. `run_started` and `door_vote_requested` are not used yet.
- **Waves (M1 slice):** wave 1 is `WAVE` (8 imps); `NEXT_WAVE_DELAY` (3 s) after each `room_cleared` the next wave stands in the same world with `WAVE_GROWTH` (2) more enemies, up to `WAVE_MAX` (24). Shots in flight are cleared, downed wizards are revived and protected. `wave_started(wave)` is sent for every wave, including wave 1 right after `room_entered`; `Flow.wave` holds the number. A lost room restarts after `RESTART_DELAY` (1.5 s) at wave 1.
- **Known gaps:** no reward, no next room and no way back to the menu (M3); the numbers are constants in `flow.gd`, tuned at C1.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `room_entered`, `room_cleared`, `wave_started`, `door_voted`.
  - Listens to: `enemy_died`, `run_started`, `player_downed`, `player_joined`, `player_left`, and from the HUD `play_requested` and `door_vote_requested` (`door_voted` is flow's announced result of the vote; `room_entered` follows `play_requested`).
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Not open yet. When it opens, follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

`gameplay/flow/flow.gd` and its test `tests/gameplay/flow/test_flow.gd` (run with `godot --headless --path . --script res://tests/gameplay/flow/test_flow.gd`). The test runs on the real autoloads, drives time through `Flow.step(delta)` and covers 1, 2 and 4 players.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

A good PR here changes room order, door voting or transitions, and keeps the no-waiting pillar: one player in the builder never stalls the rest. Besides the standard criteria:

- Does a player idling in the builder block anyone? Does voting work for 1–4 players?
- Does it keep to the dependency direction, without calling another area directly?
