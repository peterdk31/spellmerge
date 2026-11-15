# Run

## Purpose

Run lifecycle: start, seed, end and the summary screen.

Built in M3 (see "Gameplay sub-areas" in docs/PLAN.md).

A run has one seed, so the same seed gives the same rooms and rolls.

Run generation ([docs/milestones/run-generation.md](../../docs/milestones/run-generation.md)) builds it early: RG2 brings the map and its generator; RG3 the area itself (`run.gd`), which makes the map at the run's start and fills the rooms from it.

## The map (run generation RG2)

- **`RunGenerator.generate(definition, content, sim)`** (`run_generator.gd`): one pure function from a run definition (`RunDefinition`, content/runs), the content there is (`RunContent`, `Registry.run_content()`) and the run's chance (`Sim`, its run's seed) to a `RunMap`. It reads no node and plays nothing, so the same three give the same map on every machine. Its four steps: the shape (the depth, each row's width, links from each room to an unbroken run of the next row's rooms, never crossing, so every room is reached and leads on; a room leads to fewer than `branches_min` only where uncrossed links run out), the kinds (the kind table by weight, within its limits, never after a kind a line may not follow, never one that would leave the rest of its row or a later row no line; a row is narrower than `width_min` only where the limits allow no more), the templates (a template of the biome hosting the kind, never one a room leading to it has while another is left) and the fill (by the kind's `RoomKind.fill`: enemies of the biome's pool at the room's depth until the rules' `room_budget` is spent, one at least; a boss of the boss pool). Its rolls are `sim.chance(&"run_map", step and attempt, count)`. The limits never corner a map; `not_after` can (a room led to by kinds no one line may follow: the validator checks kinds, not links), and then the map is tried again with the next attempt's rolls (`ATTEMPTS`); a map not made has no rooms and says why (`RunMap.problems`), as does a definition with problems.
- **`RunMap`** (`run_map.gd`): its run and biome, its rooms (`nodes`, row by row, left to right) and `problems`; `rows()`, `row(at)`, `node(index)`, `first()`, `parents_of(index)`. **`RunNode`** (`run_node.gd`): its `index`, `row`, `depth` (the rules' row it stands for: its row unless a row before it was left out), `kind`, `room` (a template id), `links` (next row's rooms) and `enemies` (ids). Plain values and ids, never files: the map is state as it is (hashed, saved in snapshots), so a joining machine never makes its own.
- **Tests:** `tests/gameplay/run/test_run_generator.gd`: thousands of seeds through every rule on the crypt run and made-up runs, the same seed the same map, deleting any room, enemy or boss, a heavy limited kind, limits narrower than `width_min`, a `not_after` corner, and the map as state.

## Contract

- **Public entry script:** `gameplay/run/run.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. The script arrives with RG3; until then the map's scripts are used by their tests only.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `run_started`, `run_ended`.
  - Listens to: `room_cleared`, `player_downed` and `pause_requested` (from the HUD).
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

The map's scripts (`run_generator.gd`, `run_map.gd`, `run_node.gd`); the area's entry script arrives with RG3.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
tools/ptest.sh 8 'test_run_generator|test_run_rules|test_runs'
```

## Review questions

A good PR here changes how a run starts, ends or is summarised, keeps runs reproducible from their seed, and works for 1–4 players. Besides the general review:

- Is a run reproducible from its seed? Does the summary cover every player and never wait for one?
- Does it keep to the dependency direction, without calling another area directly?
