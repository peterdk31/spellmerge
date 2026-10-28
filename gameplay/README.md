# Gameplay

## Purpose

The rules of the game, in 11 sub-areas: `actor` (the shared body kit, actors G4), `player`, `combat`, `feel`, `coop`, `ai`, `run`, `flow`, `rewards`, `difficulty` and `progression`. Each has its own README with its job and when it is built (docs/PLAN.md, "Gameplay sub-areas"). This file holds the text they share.

## Contract shared by every sub-area

- **Entry script:** `gameplay/<area>/<area>.gd`. Other code uses only that script and the area's events.
- **Dependency direction:** `core` ← `gameplay` ← `content`. A sub-area may use `core/` and the registry. Areas never call each other directly; they talk through events. The one stated exception is the actor kit: every area may use the public scripts of `gameplay/actor` (see its README).
- **Events:** `core/events` owns the event definitions. A sub-area README only lists which events the area sends and which it listens to, and each event has exactly one sender. The lists must match `core/events/events.gd` and the table below.
- **Actors and seats:** what acts (casts, is hit, moves) is keyed by its actor id (`core/actors`, actors G3); a seat (0–3) is a human, and only HUD, input and co-op rules take seats. Caster-keyed events name the actor id (`caster`), seat-keyed ones the seat (`player`); see `core/events/events.gd`. Nothing assumes a single player, and nobody ever waits for another player.
- **Performance:** no per-frame allocations; use the pools and the projectile manager from `core/`; respect the particle limits.

## Events at a glance

One table for all sub-areas, so "each event has exactly one sender" can be checked in one place. Since actors G3b every caster-keyed event names the actor id as `caster` (`NO_PLAYER` only where no actor did it), and `wizard_hurt` is `actor_hurt` (the victim's actor id); the HUD, devices, builder, stats, downed and joined events stay keyed by seat (`player`). The event names and senders match `core/events/events.gd`; the listener column is kept by hand, because `events.gd` records only the HUD's receivers. The per-area lists must match this table.

| Event | Sender | Listeners |
| --- | --- | --- |
| `device_joined`, `device_left` | `core/input` | `coop` |
| `spell_cast` | `player` | `feel` |
| `wizard_cast` | `player` | `feel` |
| `projectile_hit` | `core/projectiles` | `combat` |
| `projectile_impact` | `core/projectiles` | `feel` |
| `form_shown` | `core/spells` | `feel` |
| `projectile_expired` | `core/projectiles` | `core/spells` (on expire), `feel` |
| `build_refused` | `player` | `hud` (the builders) |
| `bag_changed` | `player` | `hud` (the builders) |
| `card_move_requested` | `hud` (the builders) | `player` |
| `staff_cards_requested` | `hud` (the radial builder) | `player` |
| `staff_changed` | `player` | `hud` (the builders) |
| `staff_cast` | `player` | `hud` (the corner panel) |
| `caster_move_requested` | `core/spells` | `player`, `ai`, `actor` (the Mover), each for its own actor id |
| `mana_reserved` | `core/spells` (to the seat that drives the caster) | `player` |
| `mana_refund_requested` | `core/spells` (for every actor) | `player`, `ai`, `actor` (the Caster), each for its own actor id |
| `area_hit_requested` | `core/spells` | `combat` |
| `target_move_requested`, `entity_spawn_requested`, `entity_end_requested` | `core/spells` (staffs B2) | `ai`; `target_move_requested` also `actor` (the Mover) |
| `caster_move_finished` | `player`, `ai`, `actor` (the Mover), each with its own actor id | `core/spells`, `feel` (where a dash lands) |
| `entity_ended`, `familiar_cast_requested` | `ai` | none yet (`core/spells`, staffs B2) |
| `shot_blocked` | `core/projectiles` | none yet (`core/spells`, staffs B1) |
| `shield_blocked`, `kill_landed`, `actor_hurt`, `reaction_landed` | `combat` | `core/spells` (on block, on kill, on hurt, on reaction) |
| `hit_landed` | `combat` | `feel` |
| `heal_dealt` | `combat` | `feel`, `player` |
| `wizard_shield_requested`, `pull_requested`, `area_hit_requested` | `core/spells` (staffs B2) | `combat` |
| `reaction_triggered` | `combat` | `feel` |
| `discharge_arc` | `combat` | `feel` |
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
| `wave_started`, `build_break_started` | `flow` | `hud` |
| `sandbox_changed` | `flow` | `hud` |
| `door_voted` | `flow` | none yet |
| `difficulty_changed` | `difficulty` | none yet |
| `reward_rolled`, `reward_taken` | `rewards` | none yet |
| `unlock_gained`, `currency_changed` | `progression` | none yet |
| `play_requested` | HUD | `flow` |
| `staff_change_requested` | HUD | `player` |
| `reward_pick_requested` | HUD | `rewards` |
| `door_vote_requested` | HUD | `flow` |
| `pause_requested` | HUD | `run` |
| `sandbox_requested`, `sandbox_action_requested` | HUD | `flow` |

`device_joined` and `device_left` come from `core/input` (a button press joins or leaves; `device` is the device id from `core/input/input_manager.gd`); `coop` turns them into `player_joined` and `player_left`. The rows sent by the HUD are its player-intent requests (see `hud/README.md`); each carries a player index 0–3. The gameplay area checks the request and announces the result as a state event: `door_voted` is flow's result of `door_vote_requested`, and `reward_taken` is rewards' result of `reward_pick_requested`. `play_requested` (the Play button) carries the index of the player who pressed it (0 if the pointer is not tied to a player) and makes `flow` load the first room and send `room_entered`.

## Allowed files

`.gd`, `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. This list follows the Areas table in docs/PLAN.md. `gameplay/` is script-only: it has no scenes. The scenes that gameplay scripts drive live with their content in `content/` (the wizard in `content/wizard/base/`, enemies in `content/enemies/`, rooms in `content/rooms/`) and in `hud/`; the scene's root node carries the gameplay script, and gameplay gets scenes through `core/registry`. Typed GDScript only (types on every variable, parameter and return); no banned APIs (see AGENTS.md, hard rules).

## Steps

1. Read the area's README and make one focused change.
2. Add or update tests in `tests/gameplay/<area>/`. The test runner and file naming are documented in `tests/README.md`, which is written by a later task; until it exists, don't invent a layout.
3. Run the checks below, then open a PR using the template. For gameplay changes, add a short GIF or video.

## Validate

```sh
tools/check.sh                   # hard rules, on your changes
ci/build/build.sh --quick        # import and smoke test in Godot
```
