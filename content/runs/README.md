# content/runs: kinds of run

A run is defined as data (run generation, docs/milestones/run-generation.md): a run definition says which features the run has, and the game generates the complete run from it and the content there is, so no chain of rooms is made by hand. One file per kind of run, `<id>.tres`, a `RunDefinition` (`core/base/run_definition.gd` documents every field); the registry finds it by its `id` under `runs`.

## Contract

- **Its biomes** (`biomes`), in order, each a `MapRules` (`core/base/map_rules.gd`) of its own: the biome (`biome`, as rooms and enemies name it), how deep the map is (`depth_min`, `depth_max`), how wide a row after the first may be (`width_min`, `width_max`), how many rooms of the next row a room may lead to (`branches_min`, `branches_max`), which kinds of room may stand where (`kinds`), what a fight room's enemies cost at most together (`room_budget`, before the run's scaling), and how they come in (`spawning`, a `SpawnRules`, `core/base/spawn_rules.gd`; enemy spawning EA4): in groups of `group_share` of the room's scaled budget by cost, the next when the cost still standing drops to `refill_share` of it (below `group_share`), the bodies of a group `stagger` seconds apart; none: the whole list at once. One biome for now.
- **Its scaling** (`scaling`, a `RunScaling`, `core/base/run_scaling.gd`; run generation RG5): how much harder each room is, a curve per depth (`per_depth`: its `start` at the first row, its `end` at the deepest row the rules allow) times one per extra player (`per_player`: its `start` with one player, its `end` with four), each a `ScaleCurve` (`start`, `end`, `easing`: 1 evenly, above 1 most of the change early, below 1 late, as a card's speed curve). The scale multiplies a fight room's `room_budget` and every enemy's and boss's health (gameplay/difficulty); none: the same everywhere.
- **The map:** the first row is one room, where the party enters; every room links to one or more of the next row's, never crossing another's, so every room is reached from the first and leads to the last row.
- **The kind table** (`kinds`, `KindRule`, `core/base/kind_rule.gd`): one line per kind of room (a `RoomKind` id, content/room_kinds), the rows it may take (`first_row`, `last_row`: 0 is the first room; below 0 counts from the end, -1 the last row), its `weight` against the other kinds in a row, how many at most in a row (`max_per_row`) and in the run (`max_per_run`; 0 is no limit), the kinds that may not lead to it (`not_after`) and whether the run needs it (`required`). A line that is not required is left out when the biome's content cannot fill it, and a row only it could take is left out of the map.
- **Nothing names a room or an enemy:** the rooms of a biome are the templates that name it and host a kind (`RoomBase.biome`, `kinds`), its enemies the enemies that name it (`EnemyBase.biomes`, `cost`, `min_depth`), its bosses the bosses that do. New content joins every run of its biome by being added, and deleting it touches no run.
- **The map** is generated from it at the run's start (`RunGenerator`, gameplay/run/README.md).
- `RunDefinition.problems(content)` names what keeps a map from being made from the content there is; `Registry.validate_runs()` runs it on every run (warned at start in a debug build), and `tests/content/runs/test_runs.gd` holds it empty. The rules' own checks, on made-up content: `tests/core/test_run_rules.gd`.

| Run | Biomes | What it is |
| --- | --- | --- |
| `crypt` | `crypt`: 4 to 6 rows, 1 to 3 rooms a row, each leading to 1 or 2 | fights, then the boss in the last row (not required: with no crypt room hosting `boss` or no boss naming the crypt, the run ends at its deepest fight; both exist since boss plan OB6); 1.5 times harder by its deepest row, 1.3 times with four players (each extra player a tenth more); enemies in groups of 0.35 of the room's budget, the next at 0.15 still standing, 0.15 s apart (6 and 2 of the first room's 16 with one player) |

## Allowed files

`.tres`, plus `.uid` and `.license` files. Limit: 1 MB per file.
