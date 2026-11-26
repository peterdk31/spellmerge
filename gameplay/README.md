# Gameplay

## Purpose

The rules of the game, in 13 sub-areas: `actor` (the shared body kit), `player`, `combat`, `feel`, `coop`, `ai`, `items`, `cover`, `run`, `flow`, `rewards`, `difficulty` and `progression`. Each has its own README (docs/PLAN.md, "Gameplay sub-areas"). This file holds the text they share.

## Contract shared by every sub-area

- **Entry script:** `gameplay/<area>/<area>.gd`. Other code uses only that script and the area's events.
- **Dependency direction:** `core` ← `gameplay` ← `content`. A sub-area may use `core/` and the registry. Areas never call each other directly; they talk through events. The one exception: every area may use the public scripts of `gameplay/actor`.
- **Events:** `core/events` owns the definitions. A sub-area README lists only the events its area sends and listens to; each event has exactly one sender. The lists must match `core/events/events.gd` and the table below.
- **Actors and seats:** what acts is keyed by its actor id (`core/actors`); a seat (0–3) is a human, and only HUD, input and co-op rules take seats. Caster-keyed events name the actor id (`caster`, `NO_PLAYER` for none), seat-keyed ones the seat (`player`). Nothing assumes a single player; nobody waits for another player.
- **Simulation:** every script under `gameplay/` but `feel/` is simulation (AGENTS.md; core/sim/README.md): no clock, dice or `_process` of its own; join the tick.
- **Performance:** no per-frame allocations; use the pools and the projectile manager from `core/`; respect the particle limits.

## Events at a glance

One table for all sub-areas, so "each event has exactly one sender" is checked in one place. Names and senders match `core/events/events.gd`; the listener column is kept by hand. The per-area lists must match it. A HUD row is a player-intent request (a command where marked); the area checks it and announces the result as a state event.

| Event | Sender | Listeners |
| --- | --- | --- |
| `device_joined`, `device_left` | `core/input` | the frames service (`core/sim`) |
| `seat_joined`, `seat_left` | the frames service (`core/sim`) | `coop` |
| `spell_cast` | `player` | `feel` |
| `actor_cast` | `actor` (the Caster) | nobody yet |
| `staff_shown` | `actor` (the Caster) | `feel` |
| `projectile_hit` | `core/projectiles` | `combat` |
| `projectile_impact` | `core/projectiles` | `feel` |
| `carrier_shown` | `core/spells` | `feel` |
| `aim_locked` | `ai` | `feel` |
| `projectile_expired` | `core/projectiles` | `core/spells`, `feel` |
| `build_refused` | `player` | `hud` |
| `bag_changed` | `player` | `hud` |
| `staff_cards_requested` | `hud` | `player` |
| `staff_hand_requested`, `bag_drop_requested` | `hud` (commands) | `player` |
| `bag_use_requested` | `hud` (a command) | `player` |
| `quick_bind_requested` | `hud` (a command) | `player` |
| `quick_use_requested` | `hud` (a command) | `player` |
| `quick_bound` | `player` | `hud` |
| `item_recharging` | `player` | `hud` |
| `inventory_refused` | `player` | `hud` |
| `inventory_announced` | `player` | `hud` |
| `staff_changed` | `player` | `hud` |
| `staff_cast` | `player` | nobody now |
| `caster_move_requested` | `core/spells` | `actor` (the Mover) |
| `mana_reserved` | `core/spells` | none |
| `mana_refund_requested` | `core/spells` | `actor` (the Caster) |
| `target_move_requested`, `entity_spawn_requested`, `entity_end_requested` | `core/spells` | `ai`; `target_move_requested` also `actor` (the Mover) |
| `caster_move_finished` | `actor` (the Mover) | `core/spells` |
| `entity_ended` | `ai` (Entities) | `core/spells` |
| `shot_blocked` | `core/projectiles` | `core/spells` |
| `barrier_changed` | `combat` | `feel` |
| `shield_blocked`, `kill_landed`, `actor_hurt`, `reaction_landed` | `combat` | `core/spells` |
| `hit_landed` | `combat` | `feel` |
| `heal_dealt` | `combat` | `feel` |
| `wizard_shield_requested`, `pull_requested` | `core/spells` | `combat` |
| `possess_requested` | `core/spells` | `actor` (`Possession.begin`) |
| `carry_ended` | `core/spells` (Plow) | `combat`, `actor` (the Mover) |
| `possess_started`, `possess_ended` | `actor` (the Possession) | `feel` |
| `reaction_triggered` | `combat` | `feel` |
| `discharge_arc` | `combat` | `feel` |
| `damage_dealt` | `combat` | `feel`, `ai` (`DummyLook` only) |
| `status_applied` | `combat` | `feel` |
| `cast_left` | `core/spells` | `actor` (`PropStateTriggers`), `feel` |
| `prop_state_changed` | `actor` (`PropStateTriggers`) | none yet |
| `enemy_died` | `combat` | `feel`, `flow`, `rewards` |
| `player_downed` | `player` (Downed) | `combat`, `feel`, `flow`, `run` |
| `player_revived` | `player` (Downed) | `combat`, `flow` |
| `revive_progress` | `coop` | `player` (Downed) |
| `player_stats_changed` | `player` | `hud` |
| `player_joined`, `player_left` | `coop` | `difficulty`, `flow`, `hud` |
| `run_started`, `run_ended` | `run` | `run_started`: `difficulty`, `flow`; `run_ended`: `progression` |
| `run_begun` | `flow` | `run` |
| `run_room_filled` | `run` | `flow` |
| `run_biome_chosen` | `run` | `flow` |
| `run_room_scaled` | `flow` | `difficulty` |
| `enemy_standing` | `flow` | `difficulty` |
| `adds_requested` | `actor` (`Phases`) | `flow` |
| `crumble_requested` | `flow` | `combat` |
| `gather_door_shown` | `flow` | `feel` |
| `room_left` | `flow` | `core/spells` |
| `room_entered` | `flow` | `ai`, `coop`, `difficulty`, `hud`, `rewards`, `feel` |
| `room_built` | `flow` | `feel`, `cover` |
| `floor_touched` | `core/spells` | `cover`, `flow`, `feel` |
| `floor_passed` | `core/spells` | `cover` |
| `cover_changed` | `cover` | `feel` |
| `status_requested` | `core/spells`, `cover` | `combat` |
| `floor_strike_requested` | `cover` | `combat`, `core/spells` |
| `room_cleared` | `flow` | `run` |
| `room_rewards_due` | `flow` | `rewards` |
| `special_room_opened` | `flow` | `rewards` |
| `key_door_shown`, `secret_rock_shown`, `key_shown` | `flow` | `feel` |
| `secret_rune_shown` | `flow` | `feel` |
| `shelf_changed`, `fountain_changed` | `rewards` | `feel` |
| `rooms_seen` | `flow` | `feel` |
| `rooms_cleared`, `rooms_opened` | `flow` | `feel` |
| `rooms_rewards_left` | `rewards` | `feel` |
| `door_voted` | `flow` | none yet |
| `difficulty_changed` | `difficulty` | none yet |
| `reward_rolled`, `rewards_waiting_changed` | `rewards` | `hud` |
| `reward_taken` | `rewards` | none yet (tests) |
| `reward_refused` | `rewards` | `hud` |
| `reward_rerolled` | `rewards` | `hud` |
| `reward_reroll_refused` | `rewards` | `hud` |
| `coin_changed` | `rewards` | `feel` |
| `item_picked_up` | `rewards`, `items`, `flow` | `feel` |
| `run_stats_ruled` | `run` | `rewards` |
| `health_gift_requested` | `rewards`, `player` | `combat` |
| `unlock_gained`, `currency_changed` | `progression` | none yet |
| `play_requested` | HUD | `flow` |
| `hub_requested` | HUD | `flow`, `core/input` |
| `run_requested` | HUD (a command) | `flow` |
| `start_stone_changed` | `flow` | `hud`, `feel` |
| `staff_change_requested` | HUD | `player` |
| `reward_pick_requested` | HUD | `rewards` |
| `reward_reroll_requested` | HUD (a command) | `rewards` |
| `map_teleport_requested` | HUD (a command) | `flow` |
| `map_pick_changed` | HUD (view only) | `feel` |
| `map_frame_shown` | `feel` (view only) | `hud` |
| `teleport_rooms_shown` | `flow` (view only) | `hud` |
| `wizard_teleported` | `flow` | `feel` |
| `join_held` | `flow` (view only) | `hud` |
| `door_vote_requested` | HUD | `flow` |
| `pause_requested` | HUD | `run` |
| `pad_wait_requested` | `core/input` (a command) | `coop` |
| `pad_wait_changed` | `coop` | `hud` |
| `item_take_requested` | HUD (a command) | `items` |
| `shelf_buy_requested` | HUD (a command) | `rewards` |
| `shelf_near_changed`, `shelf_refused` | `rewards` | HUD |
| `reward_item_changed` | `rewards` | `feel` |
| `reward_near_changed` | `rewards` | HUD |
| `run_stats_told` | `rewards` | `feel` |
| `room_items_placed` | `flow` | `items` |
| `item_drop_requested` | `actor` (an Inventory) | `items` |
| `cover_danger_looked` | `ai` | `cover` |
| `ground_looked`, `actor_take_requested` | `ai` | `items` |
| `ground_item_changed` | `items` | `feel` |
| `item_near_changed`, `item_refused` | `items` | `hud` |
| `play_load_requested` | net | `flow` |

What each event carries and means: `core/events/events.gd`, and the full notes per row in the history file.

## Allowed files

`.gd`, `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. `gameplay/` is script-only: no scenes. The scenes gameplay scripts drive live with their content in `content/` and in `hud/`; gameplay gets scenes through `core/registry`. Typed GDScript only; no banned APIs (AGENTS.md, hard rules).

## Steps

1. Read the area's README and make one focused change.
2. Add or update tests in `tests/gameplay/<area>/` (layout: `tests/README.md`).
3. Run the checks below, then open a PR using the template. For gameplay changes, add a short GIF or video.

## Validate

```sh
tools/check.sh                   # hard rules, on your changes
ci/build/build.sh --quick        # import and smoke test in Godot
```

History and reasons: [docs/history/gameplay-README.md](../docs/history/gameplay-README.md).
