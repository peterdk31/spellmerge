# Run

## Purpose

Run lifecycle: start, seed, the biome map, and later the end and the summary screen (M3). A run has one seed: the same seed gives the same map, rooms and rolls.

## The area

- **`run.gd`, the autoload `Run`:** on `run_begun(run_id, players)` (from Flow, after `Tick.begin_run` dealt the seed) it makes the biome map of run definition `run_id` (registry folder `runs`) once, with `BiomeGenerator.generate`, from `Registry.run_content()`, `Registry.run_shapes`, the run's chance (`Sim.found`) and its players. It then sends, in order: `run_stats_ruled`, one `run_room_filled(room, enemies, scale, group, refill_at, stagger, elites)` per room, then `run_biome_chosen(map)` (a copy), which Flow lays and plays.
- Rooms hold layout only; what fights in a room is the map's.
- **Scaling:** `BiomeMap.room_levels` / `level_of` (depth only; aim sharpens by it, never by player count) and `BiomeMap.room_scales` (`RunScaling.room_scale`: the definition's curve by depth up to `scale_depth`, times one per extra player). The scale grows the enemy budget (`RunScaling.scaled_budget`) and, through gameplay/difficulty (`run_room_scaled`), enemy and boss health. A wizard joining later plays the map as made.
- **Pace:** `group`, `refill_at`, `stagger` come from the biome's `MapRules.spawning` (`SpawnRules`) via `RoomFill.pace`; send plain numbers in `run_room_filled`, never the Resource.
- **State:** `map` (a `BiomeMap`) is run state, hashed and snapshotted; joins the Tick with no step, renewed at each run's start (`Tick.RUN_ORDER`). In the hub there is no map. Flow keeps its own copy (`BiomeWorld.map`).
- **Unlocks:** the map is made by `RunDefinition.changed_by(sim.unlocks)`. Unlocks are the run start's (`Sim.unlocks`, from the host's save in the replay header), never this machine's save during a run. `unlocks_now` (the frames service's source, `Frames.set_unlocks_source`) gives only the save's flags some `RunDefinition.flags` names.
- **No map:** an unknown definition or `BiomeMap.not_made` answers nothing, with a warning; Flow starts no run.
- Gone: `RunMap`, `RunNode`, `RunGenerator`, `run_way_taken`, `RunMap.start_at`, `run_map_changed`. Don't bring them back.

## The biome map

- **`BiomeMap`** (`biome_map.gd`): one biome as a continuous world: rooms (template id, place on the 32 px grid, mirroring, kind), bridges (walkway template, place, mirroring, `bridge_ends`), runes (`add_rune`), each room's depth (`work_out_depths`). Plain packed rows, hashed and snapshotted as is; a joining machine never makes its own.
- API: `problems(shapes)`, `room_scales`, `enemies_of`, `fill_room`, `style`, `not_made`, `is_made`, `room_elites`, `elites_of`, `reward_type_of`, `type_room`, `neighbours`, `joins_of`.
- Test maps: `tests/support/biome_maps.gd`.

## The biome generator

- **`BiomeGenerator.generate(definition, content, shapes, sim, players)`** (`biome_generator.gd`): a pure function to a `BiomeMap`; it reads no node. Steps are in the script's class doc: room count and `MapStyle`; kinds (`least`, `chance` up to `max_per_run`, by weight; boss deepest); the way (`way_share`, `fights_on_way`); rooms off it (`branch_chain`, `hub_pull`); loops (`loops`, `loop_pull`); extra entrances (step 5b, no roll; `entrance_pull` leans toward them; `joins_left` is 0 for a made map); the fill (`RoomFill`, elites by `elite_depth` / `elite_chance` / `elite_cards`, `RoomKind.FILL_ELITES`); reward types.
- Rolls only through `sim.chance(&"biome_map", ...)` via `MapDice`; secret ways under `SECRET_PURPOSE`, reward types under `REWARD_PURPOSE`, each keyed and counted so no other roll shifts.
- A seed with no placement retries (`ATTEMPTS`); a map not made, or a definition with problems (`RunDefinition.biome_problems`, `MapRules.biome_problems`), says why. `rule_problems(map, rules, content, shapes)` checks a made map.
- Rules every map keeps: places on the 32 px grid; a template once per biome (start room excepted); slab `GAP` clear of other rooms; a bridge over its two rooms only; every bridge's two ends meet two sockets facing each other; every socket without a bridge stays lip; boss deepest; enough fights on every way to it; each kind at a depth it takes; a secret room is a dead end that no loop or extra entrance joins; locked and gated rooms keep one door.
- **A reward room's type:** rooms of a kind with `RoomKind.typed_rewards` get a `RewardType` from the kind's `rewards` table (`BiomeGenerator.roll_type`), kept in `room_reward_items`, `room_reward_card_kinds`, `room_reward_elements`. Flow sends `room_rewards_due` and puts it on the layout (`RewardType.LAYOUT_META`).
- **Chance rooms' slots:** rolled in line order, slots within `rooms_max` given to lines with the fewest chance rooms first (`_chance_order`).
- **The crypt:** made from its own templates; its validator names nothing. `MapRules.start_only` makes the start room alone (a test's pinned room, `bench/pinned_run.gd`).

### Three ways into a secret room

A room of kind `RoomKind.DOOR_SECRET` is reached by a way rolled from `MapRules.secret_ways` / `secret_way_weights` (falling back in order to the others weighted above 0):
- **hidden bridge:** placed as any room;
- **wall to wall:** rectangles touching, never overlapping, joined by a seam (`RoomBase.seam`, 64 px; `MapRules.biome_seams`, never in `biome_walkways`), GAP waived;
- **rune:** joined by no piece (`BiomeMap.add_rune`; the socket stays free).
A rune counts as a join wherever joins are read. `rule_problems` names a seam or rune that leads into no secret room.

## Contract

- **Public entry script:** `gameplay/run/run.gd`, the autoload `Run`. Nothing else in the folder is public (tests may read the map scripts).
- **Dependency direction:** `core` ← `gameplay` ← `content`. Use `core/` and the registry only.
- **Events** (defined in `core/events/events.gd`; matches [gameplay/README.md](../README.md)):
  - Sends: `run_stats_ruled`, `run_room_filled`, `run_biome_chosen`; later `run_started`, `run_ended`.
  - Listens to: `run_begun`; later `room_cleared`, `player_downed`, `pause_requested`.
- Areas never call each other directly; they talk through events. Shared rules: [gameplay/README.md](../README.md).

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs.

## Example to copy

`run.gd` and `tests/gameplay/run/test_run.gd`; the map's scripts `biome_generator.gd`, `biome_map.gd` (shared: `map_dice.gd`, `room_fill.gd`). Steps and test layout: [gameplay/README.md](../README.md).

## Tests

- `tests/gameplay/run/test_run.gd`: map from the seed, fights told first, renewed per run, state, Flow laying it, players, unlocks.
- `tests/gameplay/run/test_biome_map.gd`: map rules, depths, copies, plain state.
- `tests/gameplay/run/test_biome_generator.gd` (on `tests/support/made_up_biome.gd`): every style sound over many seeds, determinism, fill, scaling, the crypt made (`test_the_crypt_is_made`), `test_every_bridge_meets_two_rooms_and_every_doorway_has_a_bridge`, `test_the_crypt_s_secret_rooms_take_every_way`, `test_the_styles_lean_toward_extra_entrances`.

```sh
tools/check.sh
ci/build/build.sh --quick
tools/ptest.sh 8 'test_run_rules|test_run_rule_changes|test_run_unlocks|test_runs|test_run\.gd|test_flow|test_biome'
```

## Review questions

- Is a run reproducible from its seed? Does it work for 1–4 players, and never wait for one?
- Does it keep to the dependency direction, without calling another area directly?

History and reasons: [docs/history/gameplay-run-README.md](../../docs/history/gameplay-run-README.md).
