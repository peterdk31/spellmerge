# content/room_kinds: kinds of room

A kind of room is what a room of a run's map is for the game (run generation, docs/milestones/run-generation.md, "The model"): how it is filled and what ends it. One file per kind, `<id>.tres`, a `RoomKind` (`core/base/room_kind.gd`); the registry finds it by its `id` under `room_kinds` (a folder of its own, so the list of rooms never holds a kind). A room template names the kinds it can host (`RoomBase.kinds`) and a run's kind table where each may stand (`KindRule`, content/runs).

## Contract

- `fill`: how a room of the kind is filled, one of `RoomKind.FILLS`: `enemies` (an enemy budget spent on the biome's enemies whose `min_depth` the room has reached), `boss` (one of the biome's bosses) or `none` (nothing: a safe room).
- `ends`: what ends it, one of `RoomKind.ENDS`: `enemies_down`.
- A new kind (a reward room, a healing room) is a new file and a line in a run's kind table; a new way of filling or ending is engine work (one more of `FILLS` or `ENDS` and the behaviour it names), never a change to the generator.
- `RoomKind.problems()` must be empty (`tests/content/runs/test_runs.gd`, through `Registry.validate_runs()`).

| Kind | Fill | What it is |
| --- | --- | --- |
| `fight` | `enemies` | a fight: its enemies stand as it starts, and it is cleared when they are down |
| `boss` | `boss` | the boss's room |
| `start` | `none` | a biome's start room (connected biomes CB5, `MapRules.start_kind`): a small safe slab where the party arrives; hosted by no crypt template yet (CB13) |

## Allowed files

`.tres`, plus `.uid` and `.license` files. Limit: 1 MB per file.
