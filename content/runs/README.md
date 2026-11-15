# content/runs: kinds of run

A run is defined as data (run generation, docs/milestones/run-generation.md): a run definition says which features the run has, and the game generates the complete run from it and the content there is, so no chain of rooms is made by hand. One file per kind of run, `<id>.tres`, a `RunDefinition` (`core/base/run_definition.gd` documents every field); the registry finds it by its `id` under `runs`.

## Contract

- **Its biomes** (`biomes`), in order, each a `MapRules` (`core/base/map_rules.gd`) of its own: the biome (`biome`, as rooms and enemies name it), how deep the map is (`depth_min`, `depth_max`), how wide a row after the first may be (`width_min`, `width_max`), how many rooms of the next row a room may lead to (`branches_min`, `branches_max`), which kinds of room may stand where (`kinds`), and what a fight room's enemies cost at most together (`room_budget`, before the run's scaling). One biome for now.
- **The map:** the first row is one room, where the party enters; every room links to one or more of the next row's, never crossing another's, so every room is reached from the first and leads to the last row.
- **The kind table** (`kinds`, `KindRule`, `core/base/kind_rule.gd`): one line per kind of room (a `RoomKind` id, content/room_kinds), the rows it may take (`first_row`, `last_row`: 0 is the first room; below 0 counts from the end, -1 the last row), its `weight` against the other kinds in a row, how many at most in a row (`max_per_row`) and in the run (`max_per_run`; 0 is no limit), the kinds that may not lead to it (`not_after`) and whether the run needs it (`required`). A line that is not required is left out when the biome's content cannot fill it, and a row only it could take is left out of the map.
- **Nothing names a room or an enemy:** the rooms of a biome are the templates that name it and host a kind (`RoomBase.biome`, `kinds`), its enemies the enemies that name it (`EnemyBase.biomes`, `cost`, `min_depth`), its bosses the bosses that do. New content joins every run of its biome by being added, and deleting it touches no run.
- **The map** is generated from it at the run's start (`RunGenerator`, gameplay/run/README.md).
- `RunDefinition.problems(content)` names what keeps a map from being made from the content there is; `Registry.validate_runs()` runs it on every run (warned at start in a debug build), and `tests/content/runs/test_runs.gd` holds it empty. The rules' own checks, on made-up content: `tests/core/test_run_rules.gd`.

| Run | Biomes | What it is |
| --- | --- | --- |
| `crypt` | `crypt`: 4 to 6 rows, 1 to 3 rooms a row, each leading to 1 or 2 | fights, then the boss in the last row (not required: until a boss names the crypt, the run ends at its deepest fight) |

## Allowed files

`.tres`, plus `.uid` and `.license` files. Limit: 1 MB per file.
