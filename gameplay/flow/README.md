# Flow

## Purpose

Room sequence, the hub, a biome's rooms, doors, transitions and the run's start and end. Players in the spell builder never block the others: the rest keep playing.

## Contract

- **Public entry script:** `gameplay/flow/flow.gd`, the autoload `Flow`. Other code uses only it and its events. Its helpers (`BiomeWorld`, `RoomLife`, `RoomSpawning`, `RoomAdds`, `RoomContents`, `GatherDoors`, `LockDoors`, `SecretRunes`, `PartyMap`, `MapTeleport`, `JoinGate`, `LeftPlayers`, `HubRules`, `Departure`, `BossIntroHold`, `PropYard`, `SpecialPlaces`, `intro.gd`) are Flow's own; their members are state unless listed otherwise.
- **Flow never makes the map and holds no spell.** On `run_begun(run_id, players)` the run area answers with `run_room_filled` (each `RoomFight`) and `run_biome_chosen` (the map); those events are all Flow knows of the run. Rooms hold layout only; what fights in a room is the map's.
- **Starting:** `play_requested` (`run_id_to_play`) or `hub_requested` (`HUB_ROOM_ID`); a run the registry cannot make (`Registry.run_problems`) starts nothing; `stop_run()`; `start_biome(requester, map, fights)` for a test's map.
- **Modes:** `Flow.mode` is `MODE_RUN` (also when idle) or `MODE_HUB`; `staffs_for_mode()`, `bag_for_mode()`, `restart_delay()`. Each mode's staff files are used as they are, never copied or changed. Every player gets staffs and card copies and builds itself.
- **Every run ends back in the hub**, lost (everyone down, `RESTART_DELAY`) or won (portal home, `RUN_WON_DELAY`), through a `Departure` (`Departure.TICKS`) and `Frames.restart` (or Flow itself with no frames service). Nothing a run gathered comes back.
- **The world's camera is always the current one** (`_make_current`, `_make_current_later`; `tests/gameplay/flow/test_camera_current.gd`).
- **A room's fight:** each enemy is told to difficulty before it enters the tree (`enemy_standing`) and counted for the wizards in play (`Actor.players`, `count_players`). A boss stands at once; the rest spawn in (`Actor.spawn`, `spawn_style_for`) in groups by cost (`RoomSpawning`: `group`, `refill_at`, `stagger`; no timers), never over a hole or near a wizard. An id that cannot stand is dropped, so a room is never stuck uncleared. `stand_all_now()` for tests.
- **A phase's adds:** `adds_requested` → stood by Flow as the room's own (`RoomAdds.ring`); they crumble through Combat (`crumble_requested`) when their caller dies.
- **A boss's intro** (`BossIntroHold`): opens as the boss room's fight starts if `SessionRules.boss_intros`; stops the game (`Sim.stop`); the command `boss_intro_next_requested(player, page)` turns a page once however many seats press; closing drops carried presses (`Frames.drop_presses`). Never in the hub, for adds, or twice a room. Intros are off for automation (`CommandLine.automated()`, `intro_enabled`) and under a replay.
- **The intro** (`intro.gd`): on a save without `INTRO_SEEN`; any player's button skips it for all.
- **Joins and leaves:** a leaving seat's whole inventory and its staffs' mana and recharges are kept once (`LeftPlayers`, `Inventory.loadout`, `take_loadout`, `set_staff_mana`, `set_recharges`). In a biome past the start room a joiner is held (`JoinGate`, `join_held`) until the next world. Joiners spawn at `RoomBase.joiner_spawns`.
- **Map teleport:** command `map_teleport_requested(player, room)` to a cleared room, only for a standing, driven wizard in no fight (`MapTeleport.calm`, `MapTeleport.arrive`); nobody else moves or waits.
- **The hub:** free joins and leaves; a downed wizard stands up by itself (`RoomBase.stand_up_after`). The command `run_requested` on the lit stone (`HubRules`, `start_stone_changed`) departs for a run, carrying the whole player (`PartyLoadout`, `PlayerController.loadout_of`, `Frames.set_party_source`). The command `all_cards_requested` fills only the sender's wizard's bag, only in a running hub.
- **A biome laid out** (`BiomeWorld`): every room and bridge at its place, the grid over the whole biome; nodes and grid layers are laid again from the map, never saved (`rebuild_derived`). A room is entered only through its mouth.
- **Room life** (`RoomLife`): a fight starts as a wizard's own body first stands in the room, which seals; cleared when no enemy no seat drives is left. Empty places sleep (`RoomGrid.find_places`, native twin `RoomLife.gd_find_places`).
- **Doors** (`GatherDoors`, `LockDoors`, `SecretRunes`): gather doors, the boss's gate, the portal home, key doors (keys are a seat's own items), secret rocks (`floor_touched`), runes; laid again from state after a restore; chance only through the run's purposes (`KEY_PURPOSE`, ...).
- **Special rooms:** a cleared room's reward table goes out as `room_rewards_due`; a shop or fountain sends `special_room_opened`; the Rewards area does the rest. Elites stand with their card (`Actor.elite_card`).
- **The party's map** (`PartyMap`): rooms unseen, shown or entered; `rooms_seen` to the view.
- **View-only messages** (`*_shown`, `rooms_seen`, `join_held`) are sent as they change and again after a restore.
- **Room size:** `room_size(room, layout)` (static), at least 640×360.
- **Dependency direction:** `core` ← `gameplay` ← `content`. Areas never call each other directly; they talk through events ([gameplay/README.md](../README.md)).
- **Events** (defined in `core/events/events.gd`):
  - Sends: `boss_intro_opened`, `boss_intro_paged`, `boss_intro_closed`, `crumble_requested`, `room_built`, `run_begun`, `enemy_standing`, `room_left`, `gather_door_shown`, `key_door_shown`, `secret_rock_shown`, `key_shown`, `secret_rune_shown`, `rooms_opened`, `room_entered`, `room_cleared`, `room_rewards_due`, `special_room_opened`, `cue_shown` (`room_start`, `stone_lit`), `start_stone_changed`, `run_departure_changed`, `door_voted`, `teleport_rooms_shown`, `wizard_teleported`, `join_held`, `rooms_seen`, `key_needed_shown`, `prop_state_requested`.
  - Listens to: `run_room_filled`, `run_biome_chosen`, `run_stats_ruled`, `adds_requested`, `floor_touched`, `enemy_died`, `run_started`, `player_downed`, `player_joined`, `player_left`, `main_menu_requested` (not a command: `stop_run`), `door_vote_requested`; the commands `play_requested`, `hub_requested`, `run_requested`, `boss_intro_next_requested`, `map_teleport_requested`, `all_cards_requested`.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. 1 MB per file. Typed GDScript only; no banned APIs.

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

`gameplay/flow/flow.gd` and `tests/gameplay/flow/test_flow.gd` (the real autoloads, time through `Flow.step(delta)`, 1, 2 and 4 players).

## Tests

`tests/gameplay/flow/`: `test_flow.gd`, `test_camera_current.gd`, `test_boss_intro_hold.gd`, `test_rejoin.gd`, `test_map_teleport.gd`, `test_biome_world.gd`, `test_room_life.gd`, `test_gather_doors.gd`, `test_special_rooms.gd`, `test_secret_ways.gd`, `test_party_map.gd`; `tests/support/spawning.gd`; `tests/core/test_content_determinism.gd`.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

- Does a player idling in the builder block anyone? Does it work for 1–4 players?
- Does it keep to the dependency direction, without calling another area directly?

History and reasons: [docs/history/gameplay-flow-README.md](../../docs/history/gameplay-flow-README.md).
