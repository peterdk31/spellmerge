# Gameplay

## Purpose

The rules of the game, in 10 sub-areas: `player`, `combat`, `feel`, `coop`, `ai`, `run`, `flow`, `rewards`, `difficulty` and `progression`. Each has its own README with its job, when it is built and when it opens for PRs (docs/PLAN.md, "Gameplay sub-areas"). This file holds the text they share.

Which sub-areas are open for PRs is in docs/ROADMAP.md ("Opens for PRs"). A PR to a closed area may still be merged, but it's a gamble.

## Contract shared by every sub-area

- **Entry script:** `gameplay/<area>/<area>.gd`. Other code uses only that script and the area's events.
- **Dependency direction:** `core` ← `gameplay` ← `content`. A sub-area may use `core/` and the registry. Areas never call each other directly; they talk through events.
- **Events:** `core/events` owns the event definitions. A sub-area README only lists which events the area sends and which it listens to, and each event has exactly one sender. The lists must match `core/events/events.gd` and the table below.
- **Players:** everything that acts per player takes a player index 0–3. Nothing assumes a single player, and nobody ever waits for another player.
- **Performance:** no per-frame allocations; use the pools and the projectile manager from `core/`; respect the particle limits.

## Events at a glance

One table for all sub-areas, so "each event has exactly one sender" can be checked in one place. The event names and senders match `core/events/events.gd`; the listener column is kept by hand, because `events.gd` records only the HUD's receivers. The per-area lists must match this table.

| Event | Sender | Listeners |
| --- | --- | --- |
| `device_joined`, `device_left` | `core/input` | `coop` |
| `spell_cast` | `player` | `feel` |
| `wizard_cast` | `player` | `feel` |
| `projectile_hit` | `core/projectiles` | `combat` |
| `projectile_impact` | `core/projectiles` | `feel` |
| `projectile_expired` | `core/projectiles` | none yet (`core/spells` from M2 part 6) |
| `spell_changed`, `build_refused` | `player` | none yet (`hud`, M2 part 16) |
| `reaction_triggered` | `combat` | `feel` |
| `damage_dealt` | `combat` | `feel`, `player` |
| `status_applied` | `combat` | none yet |
| `enemy_died` | `combat` | `feel`, `flow` |
| `player_downed` | `player` | `ai`, `feel`, `flow`, `run` |
| `player_revived` | `player` | none yet |
| `revive_progress` | `coop` | `player` |
| `player_stats_changed` | `player` | `hud` |
| `player_joined`, `player_left` | `coop` | `difficulty`, `flow`, `hud` |
| `run_started`, `run_ended` | `run` | `run_started`: `difficulty`, `flow`; `run_ended`: `progression` |
| `room_entered` | `flow` | `ai`, `coop`, `difficulty`, `hud` |
| `room_cleared` | `flow` | `rewards`, `run` |
| `wave_started` | `flow` | `hud` |
| `door_voted` | `flow` | none yet |
| `difficulty_changed` | `difficulty` | none yet |
| `reward_rolled`, `reward_taken` | `rewards` | none yet |
| `unlock_gained`, `currency_changed` | `progression` | none yet |
| `play_requested` | HUD | `flow` |
| `build_change_requested`, `spell_swap_requested` | HUD | `player` |
| `reward_pick_requested` | HUD | `rewards` |
| `door_vote_requested` | HUD | `flow` |
| `pause_requested` | HUD | `run` |

`device_joined` and `device_left` come from `core/input` (a button press joins or leaves; `device` is the device id from `core/input/input_manager.gd`); `coop` turns them into `player_joined` and `player_left`. The last five rows (the `build_change_requested` row holds two events) are the HUD's player-intent requests (see `hud/README.md`); each carries a player index 0–3. The gameplay area checks the request and announces the result as a state event: `door_voted` is flow's result of `door_vote_requested`, and `reward_taken` is rewards' result of `reward_pick_requested`. `play_requested` (the Play button) carries the index of the player who pressed it (0 if the pointer is not tied to a player) and makes `flow` load the first room and send `room_entered`.

## Allowed files

`.gd`, `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. This list follows the Areas table in docs/PLAN.md. `gameplay/` is script-only: it has no scenes. The scenes that gameplay scripts drive live with their content in `content/` (the wizard in `content/wizard/base/`, enemies in `content/enemies/`, rooms in `content/rooms/`) and in `hud/`; the scene's root node carries the gameplay script, and gameplay gets scenes through `core/registry`. Typed GDScript only (types on every variable, parameter and return); no banned APIs (see AGENTS.md, hard rules).

## Steps (once the area is open)

1. Pick an issue labelled `now` in the area and comment `/claim`.
2. Read the area's README and make one focused change.
3. Add or update tests in `tests/gameplay/<area>/`. The test runner and file naming are documented in `tests/README.md`, which is written by a later task; until it exists, don't invent a layout.
4. Run the checks below, then open a PR using the template. For gameplay changes, add a short GIF or video.

## Validate

```sh
tools/check.sh                   # hard rules, on your changes
ci/build/build.sh --quick        # import and smoke test in Godot
```
