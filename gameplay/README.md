# Gameplay

## Purpose

The rules of the game, in 13 sub-areas: `actor` (the shared body kit, actors G4), `player`, `combat`, `feel`, `coop`, `ai`, `items` (what lies on the ground, items I6), `cover` (the ground cover's game: fire, frost and what it does to bodies, ground cover GC5), `run`, `flow`, `rewards`, `difficulty` and `progression`. Each has its own README with its job and when it is built (docs/PLAN.md, "Gameplay sub-areas"). This file holds the text they share.

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
| `device_joined`, `device_left` | `core/input` | the frames service (`core/sim`) |
| `seat_joined`, `seat_left` | the frames service (`core/sim`) | `coop` |
| `spell_cast` | `player` | `feel` |
| `actor_cast` | `actor` (the Caster, every actor's cast; actors G8) | nobody yet (a body's cast movement is its carrier's `staff_pose`, drawn by its look) |
| `staff_shown` | `actor` (the Caster, another staff put on show; living staffs H4) | `feel` (the poof) |
| `projectile_hit` | `core/projectiles` | `combat` |
| `projectile_impact` | `core/projectiles` | `feel` |
| `carrier_shown` | `core/spells` | `feel` |
| `aim_locked` | `ai` (an enemy's AI stops following its target with the cast it winds up: its profile's `aim_lock`; boss plan OB14) | `feel` (a beat on the cast's lane) |
| `projectile_expired` | `core/projectiles` | `core/spells` (on expire), `feel` |
| `build_refused` | `player` | `hud` (the builders) |
| `bag_changed` | `player` | `hud` (the builders) |
| `staff_cards_requested` | `hud` (the radial builder) | `player` |
| `staff_hand_requested`, `bag_drop_requested` | `hud` (the inventory; commands, items I7) | `player` |
| `inventory_refused` | `player` | `hud` (the inventory's note) |
| `inventory_announced` | `player` (before a wizard's whole inventory is said anew) | `hud` (the builder, the inventory forget the earlier wizard's staffs) |
| `staff_changed` | `player` | `hud` (the builders) |
| `staff_cast` | `player` | nobody now (Feel sounds every cast on `cast_left`) |
| `caster_move_requested` | `core/spells` | `actor` (the Mover), each for its own actor id |
| `mana_reserved` | `core/spells` (to the seat that drives the caster) | none (the Caster reads `Spells.reserved_mana`, actors G7) |
| `mana_refund_requested` | `core/spells` (for every actor) | `actor` (the Caster), each for its own actor id |
| `target_move_requested`, `entity_spawn_requested`, `entity_end_requested` | `core/spells` (staffs B2) | `ai`; `target_move_requested` also `actor` (the Mover) |
| `caster_move_finished` | `actor` (the Mover), each with its own actor id | `core/spells` (`walled`: a wall ended it, so its `on wall` fires; boss plan OB12) |
| `entity_ended` | `ai` (Entities) | `core/spells` |
| `shot_blocked` | `core/projectiles` | `core/spells` (on block) |
| `barrier_changed` | `combat` (a barrier given, grown, blocking, run out or cleared) | `feel` (the barrier's bubble) |
| `shield_blocked`, `kill_landed`, `actor_hurt`, `reaction_landed` | `combat` (for every actor: `actor_hurt` and `shield_blocked` name the hurt or shielded actor) | `core/spells` (on block, on kill, on hurt, on reaction) |
| `hit_landed` | `combat` | `feel` |
| `heal_dealt` | `combat` | `feel` |
| `wizard_shield_requested`, `pull_requested` | `core/spells` (staffs B2) | `combat` |
| `possess_requested` | `core/spells` (actors G9) | `actor` (each actor, for its own id: `Possession.begin`) |
| `carry_ended` | `core/spells` (Plow, boss plan OB11) | `combat` (the pin or the shove), `actor` (the Mover of the body that carried it, for its own id: a pin ends its dash) |
| `possess_started`, `possess_ended` | `actor` (the Possession) | `feel` (a ring in the driver's ramp) |
| `reaction_triggered` | `combat` | `feel` |
| `discharge_arc` | `combat` | `feel` |
| `damage_dealt` | `combat` | `feel`, `ai` (`DummyLook` only; an actor's own components hear its `Actor.damaged`, which Combat sends with it) |
| `status_applied` | `combat` | `feel` (an actor's own components hear its `Actor.status_gained`, and a reaction on it its `Actor.reacted`, which Combat sends with them) |
| `cast_left` | `core/spells` (a cast leaving, before its shots) | `actor` (a prop's `PropStateTriggers`, for its `cast` triggers), `feel` (the staff's cast cue, the cast's carrier sounds and infusion hints) |
| `prop_state_changed` | `actor` (a prop's `PropStateTriggers`, props W6) | none yet (tests; a prop's own look hears its component directly) |
| `enemy_died` | `combat` (every foe of the players, never a prop: `Actors.is_foe`) | `feel`, `flow`, `rewards` (its coins) |
| `player_downed` | `player` (Downed) | `combat`, `feel`, `flow`, `run` |
| `player_revived` | `player` (Downed) | `combat`, `flow` |
| `revive_progress` | `coop` | `player` (Downed) |
| `player_stats_changed` | `player` (the seat's own body, also while it is away) | `hud` |
| `player_joined`, `player_left` | `coop` | `difficulty`, `flow`, `hud` |
| `run_started`, `run_ended` | `run` | `run_started`: `difficulty`, `flow`; `run_ended`: `progression` |
| `run_begun` | `flow` (a run of rooms begins, on its fresh state, with the seats joined at its start) | `run` (makes the run's map for them) |
| `run_room_scaled` | `run` (how much harder the room the party enters is: its depth and the run's players; before `run_room_chosen`) | `difficulty` (the level) |
| `run_room_paced` | `run` (how the enemies of the room the party enters come in: a group's cost, the cost standing that calls the next, the seconds between a group's bodies; enemy spawning EA4; after `run_room_scaled`, before `run_room_chosen`) | `flow` (`RoomSpawning`) |
| `run_room_chosen` | `run` (the map's room the party enters, what stands in it and the kinds of the rooms it leads to) | `flow` (builds it) |
| `enemy_standing` | `flow` (an enemy or boss body about to stand, not yet in the tree) | `difficulty` (scales it to the room: `Actor.stat_scale`) |
| `adds_requested` | `actor` (a body's `Phases`: its phase's burst or a wave of adds; boss plan OB13) | `flow` (stands them, for a body it stood) |
| `crumble_requested` | `flow` (an add whose caller died; boss plan OB13) | `combat` (it dies with no hit, nobody's kill) |
| `run_way_taken` | `flow` (every standing wizard in a lit exit) | `run` (moves on through the map) |
| `room_exits_shown` | `flow` (the lit exits of a cleared room, and the kind behind each) | `feel` (the kind's name over each) |
| `room_left` | `flow` (the party goes on to the next room of the run; a biome's world goes, `Events.ALL_ROOMS`) | `core/spells` (what was cast in the room ends quietly) |
| `room_entered` | `flow` (by room number: a biome's each room the first time; `Events.FIRST_ROOM` is a new world, connected biomes CB3) | `ai`, `coop`, `difficulty`, `hud`, `rewards` (a new world clears the coins), `feel` (its walls' colours for motes; the party camera jumps to the new room) |
| `room_built` | `flow` | `feel` (ground cover GC3: the cover's look, `cover.gd`) and `cover` (GC5): the room's cover worked out from its layout, `CoverLayout.of` |
| `floor_touched` | `core/spells` (a blast, a pulse's ring, a pool lying and on its ticks, a shot's end; ground cover GC5) | `cover` (the `element` triggers of the cells inside its circle, at its next step) |
| `cover_changed` | `cover` (each tick's changes; after a `room_built` or a restore, the cells the view was told otherwise) | `feel` (the tufts' look) |
| `status_requested` | `core/spells` (a portal's infusion) and `cover` (a status of the cover a body stands in, ground cover GC5 rule 4: asked as any status is) | `combat` |
| `room_cleared` | `flow` | `rewards` (a roll per player), `run` |
| `door_voted` | `flow` | none yet |
| `difficulty_changed` | `difficulty` (a difficulty setting's level, M3; never the room's scale, `run_room_scaled`) | none yet (enemy AI AI10: `ai`, the TeamBoard's skill) |
| `reward_rolled`, `rewards_waiting_changed` | `rewards` (a player's own offer on a clear; the offers a seat has waiting, connected biomes CB10) | `hud` (the reward menu, the corner panel's unspent count) |
| `reward_taken` | `rewards` | none yet (tests) |
| `coin_changed` | `rewards` (a coin on the floor laid or gone) | `feel` (the coins' look) |
| `wallet_changed` | `rewards` (a seat's coins) | `hud` (the corner panel) |
| `run_stats_ruled` | `run` (the run's own changes of the run stats, as a run of rooms begins) | `rewards` |
| `health_gift_requested` | `rewards` (a reward of healing or more most health) | `combat` (it keeps an actor's health) |
| `unlock_gained`, `currency_changed` | `progression` | none yet |
| `play_requested` | HUD | `flow` |
| `hub_requested` | HUD | `flow`, `core/input` |
| `run_requested` | HUD (a command) | `flow` |
| `start_stone_changed` | `flow` | `hud`, `feel` |
| `staff_change_requested` | HUD | `player` |
| `reward_pick_requested` | HUD | `rewards` |
| `door_vote_requested` | HUD | `flow` |
| `pause_requested` | HUD | `run` |
| `pad_wait_requested` | `core/input` (a command) | `coop` (the game stops while a seat waits for its unplugged gamepad) |
| `pad_wait_changed` | `coop` | `hud` (the pad line, the pause menu) |
| `item_take_requested` | HUD (a command) | `items` (A by an item in reach) |
| `room_items_placed` | `flow` | `items` (what the room's scene places lies there) |
| `item_drop_requested` | `actor` (an Inventory) | `items` (a card given back to a full bag, or what the inventory menu drops, lands beside the body) |
| `cover_danger_looked` | `ai` (every brain, as it walks and at each decision, ground cover GC7) | `cover` (fills the look at once: where the floor would harm) |
| `ground_looked`, `actor_take_requested` | `ai` (a brain whose profile takes items, I9) | `items` (fills the look at once; gives the item to the actor's Inventory) |
| `ground_item_changed` | `items` | `feel` (the look on the ground) |
| `item_near_changed`, `item_refused` | `items` | `hud` (the hint, its red shake) |
| `play_load_requested` | net | `flow` (loads `play_tasks` ahead of a run two machines start together) |

`device_joined` and `device_left` come from `core/input` (a button press joins or leaves; `device` is the device id from `core/input/input_manager.gd`); the frames service turns them into the simulation's `seat_joined` and `seat_left` (offline at once; while a replay plays, only as its frames say), and `coop` turns those into `player_joined` and `player_left`. The rows sent by the HUD are its player-intent requests (see `hud/README.md`); each carries a player index 0–3. The gameplay area checks the request and announces the result as a state event: `door_voted` is flow's result of `door_vote_requested`, and `reward_taken` is rewards' result of `reward_pick_requested`. `hub_requested` (the Play button) carries the index of the player who pressed it (0 if the pointer is not tied to a player) and makes `flow` load the hub and send `room_entered`; `play_requested` starts a run at once (the tests, the bots, the online spike's Host/Join).

## Allowed files

`.gd`, `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. This list follows the Areas table in docs/PLAN.md. `gameplay/` is script-only: it has no scenes. The scenes that gameplay scripts drive live with their content in `content/` (the player in `content/wizard/base/`, enemies in `content/enemies/`, rooms in `content/rooms/`) and in `hud/`; the scene's root node carries the gameplay script, and gameplay gets scenes through `core/registry`. Typed GDScript only (types on every variable, parameter and return); no banned APIs (see AGENTS.md, hard rules).

## Steps

1. Read the area's README and make one focused change.
2. Add or update tests in `tests/gameplay/<area>/`. The test runner and file naming are documented in `tests/README.md`, which is written by a later task; until it exists, don't invent a layout.
3. Run the checks below, then open a PR using the template. For gameplay changes, add a short GIF or video.

## Validate

```sh
tools/check.sh                   # hard rules, on your changes
ci/build/build.sh --quick        # import and smoke test in Godot
```
