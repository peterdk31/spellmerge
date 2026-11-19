# content/room_kinds: kinds of room

A kind of room is what a room of a run's map is for the game (run generation, docs/milestones/run-generation.md, "The model"): how it is filled and what ends it. One file per kind, `<id>.tres`, a `RoomKind` (`core/base/room_kind.gd`); the registry finds it by its `id` under `room_kinds` (a folder of its own, so the list of rooms never holds a kind). A room template names the kinds it can host (`RoomBase.kinds`) and a run's kind table where each may stand (`KindRule`, content/runs).

## Contract

- `fill`: how a room of the kind is filled, one of `RoomKind.FILLS`: `enemies` (an enemy budget spent on the biome's enemies whose `min_depth` the room has reached), `boss` (one of the biome's bosses) or `none` (nothing: a safe room).
- `ends`: what ends it, one of `RoomKind.ENDS`: `enemies_down`.
- `door` (connected biomes CB7): how a room of the kind is entered in a biome, one of `RoomKind.DOORS`: none (free), `gather` (a gather door: shut until every standing wizard is on its bridge, then the standing ones come in together; a challenge room, CB11) or `gate` (the boss's: a gather door that also waits while any sealed fight holds a wizard, and then brings everyone, downed or far away).
- `portal_home` (CB7): true when a room of the kind, cleared, opens the portal home on its floor (at its template's zone `portal`, else its middle): every standing wizard in it ends the run, won, back in the hub.
- **Its look and sound** (connected biomes CB12, decision 30; the inspector's "Look and sound" group, each optional, drawn and heard only): `air`, an `Ambience` (its bed and accents, heard in place of the room's own while the music follows a room of the kind: the room this machine's wizards are in, the most intense of them); `music`, a `MusicTrack` played then in place of the room's (a living boss's music still comes first); `light`, the palette material (docs/STYLE.md, never a player's or Blight) the mouths into a room of the kind shimmer in and its seals' runes glow in (empty: the spark's). The boss's light is the fire's.
- A new kind (a reward room, a healing room) is a new file and a line in a run's kind table; a new way of filling or ending is engine work (one more of `FILLS` or `ENDS` and the behaviour it names), never a change to the generator.
- `RoomKind.problems()` must be empty (`tests/content/runs/test_runs.gd`, through `Registry.validate_runs()`).

| Kind | Fill | What it is |
| --- | --- | --- |
| `fight` | `enemies` | a fight: its enemies stand as it starts, and it is cleared when they are down |
| `boss` | `boss` | the boss's room: in a biome its gate (`door = gate`) and, cleared, the portal home |
| `start` | `none` | a biome's start room (connected biomes CB5, `MapRules.start_kind`): a small safe slab where the party arrives; hosted by `crypt_start` (CB8), cleared as it is entered |

## Allowed files

`.tres`, plus `.uid` and `.license` files. Limit: 1 MB per file.
