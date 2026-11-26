# content/room_kinds: kinds of room

A kind of room is what a room of a run's map is for the game (docs/milestones/run-generation.md, "The model"): how it is filled, how it is entered and what ends it. One file per kind, `<id>.tres`, a `RoomKind` (`core/base/room_kind.gd`), found by its `id` under `room_kinds`. A room template names the kinds it can host (`RoomBase.kinds`) and a run's kind table where each may stand (`KindRule`, content/runs).

## Contract

- `fill`, one of `RoomKind.FILLS`: `enemies` (an enemy budget spent on the biome's enemies whose `min_depth` the room has reached; elites from `MapRules.elite_depth` by `elite_chance`), `elites` (every enemy an elite), `boss` (one of the biome's bosses), `shop` (a shelf rolled from `shelf`, each item bought by the first wizard to step on it with its price in their own coins), `fountain` (a pool of healing shared by every hurt wizard in it) or `none` (a safe room).
- `ends`, one of `RoomKind.ENDS`: `enemies_down`.
- `door`, one of `RoomKind.DOORS`: none (free), `gather` (shut until every standing wizard is on its bridge), `gate` (the boss's: a gather door that also waits for sealed fights, then brings everyone), `key` (its key dropped in the room its bridge hangs off as that room is cleared) or `secret` (cracked rock broken by the element rolled for the room).
- `rewards`: the reward table (content/rewards) each player rolls from as a room of the kind is cleared; empty rewards nobody. `shelf`: a shop's table of items (each line's `price`).
- `portal_home`: a cleared room of the kind opens the portal home (at its template's zone `portal`, else its middle).
- **Look and sound** (each optional, drawn and heard only): `air` (an `Ambience`), `music` (a `MusicTrack`; a living boss's music still comes first), `light` (a palette material, docs/STYLE.md, never a player's or Blight; empty: the spark's), `light_tint` (0 to `RoomKind.LIGHT_TINT_MOST`), `air_motes` (a `MoteSource`, the rules of `RoomBase.problems_of_air`).
- **Its symbol:** `symbol`, a 7 × 7 picture as text, a row a line, `#` its light's lit shade, `+` its base shade, `.` none; shown on a bridge's mouth and the Y map. Empty: nothing told (a secret room). `problems()` names a symbol that is not 7 rows of 7 or has another character.
- **A new kind is a new file and a line in a run's kind table;** a new way of filling, entering or ending is engine work (one more of `FILLS`, `DOORS` or `ENDS` and its behaviour), never a change to the generator.
- `RoomKind.problems()` must be empty (`tests/content/runs/test_runs.gd`, through `Registry.validate_runs()`).

| Kind | Fill | What it is |
| --- | --- | --- |
| `fight` | `enemies` | a fight, cleared when its enemies are down; rewards from `clear` |
| `boss` | `boss` | the boss's room: its gate (`door = gate`) and, cleared, the portal home; rewards from `boss` |
| `start` | `none` | a biome's start room (`MapRules.start_kind`), cleared as it is entered |
| `reward` | `none` | each wizard's reward from `reward` as the party steps in |
| `shop` | `shop` | the shop: its shelf from `shelf` |
| `fountain` | `fountain` | a shared pool of healing |
| `treasure` | `none` | behind a key door: rewards from `treasure` |
| `secret` | `none` | behind cracked rock: rewards from `secret` |
| `challenge` | `elites` | behind a gather door: an elite fight, rewards from `challenge` |

## Allowed files

`.tres`, plus `.uid` and `.license` files. Limit: 1 MB per file.

## Example to copy

`fight.tres` (a plain fight) or `shop.tres` (a fill with a table).

History and reasons: [docs/history/content-room_kinds-README.md](../../docs/history/content-room_kinds-README.md).
