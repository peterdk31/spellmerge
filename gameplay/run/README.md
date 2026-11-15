# Run

## Purpose

Run lifecycle: start, seed, end and the summary screen.

Built in M3 (see "Gameplay sub-areas" in docs/PLAN.md).

A run has one seed, so the same seed gives the same rooms and rolls.

Run generation ([docs/milestones/run-generation.md](../../docs/milestones/run-generation.md)) builds it early: RG2 brings the map and its generator; RG3 the area itself (`run.gd`), which makes the map at the run's start and fills the rooms from it; RG4 the way on through it.

## The area (run generation RG3)

- **`run.gd`, the autoload `Run`:** when Flow begins a run of rooms (`run_begun(run_id)`, sent on the run's fresh state, after `Tick.begin_run` dealt its seed), it makes the map of the run definition `run_id` (registry folder `runs`, content/runs) from the content there is (`Registry.run_content()`) and the run's chance (`Sim.found`), once, and answers with the room the party enters, the map's first (`run_room_chosen(room_id, enemies, ways)`: a template id, the enemy and boss ids that stand in it, one per body, and the kinds of the rooms it leads to, left to right as its links), which Flow builds.
- **The way on (RG4):** when every standing wizard stands in a lit exit, Flow sends `run_way_taken(way)` (0 = the room's leftmost link); the area moves `at` on to the room that link names (a row deeper: the depth moves on with it) and names it the same way. A way the room has not moves nothing (a warning). The run's last room has no ways: cleared, Flow ends the run. Rooms hold layout only: what fights in a room is the map's.
- **State:** `map` (the `RunMap`) and `at` (the index of the room the party is in; `room_now()`) are the run's state, hashed and saved in snapshots, so a joining machine gets them from the snapshot. It joins the Tick with no step and is renewed at every run's start (`begin_run`, `Tick.RUN_ORDER`): out of a run of rooms (the hub, the sandbox) there is no map.
- **No map:** a definition the registry lacks, or a map that cannot be made (`RunMap.problems`), answers nothing, with a warning saying why; Flow then starts no run (from the hub's stone, the party goes back to the hub).
- **Tests:** `tests/gameplay/run/test_run.gd` (the map made from the run's seed and named to Flow, a way taken moving on to its room, the same seed the same map, renewed at a run's start, the map as state, Flow building the room the map names). A test that plays a room of its choosing pins it as a run of that one room (`tests/support/pinned_run.gd`).

## The map (run generation RG2)

- **`RunGenerator.generate(definition, content, sim)`** (`run_generator.gd`): one pure function from a run definition (`RunDefinition`, content/runs), the content there is (`RunContent`, `Registry.run_content()`) and the run's chance (`Sim`, its run's seed) to a `RunMap`. It reads no node and plays nothing, so the same three give the same map on every machine. Its four steps: the shape (the depth, each row's width, links from each room to an unbroken run of the next row's rooms, never crossing, so every room is reached and leads on; a room leads to fewer than `branches_min` only where uncrossed links run out), the kinds (the kind table by weight, within its limits, never after a kind a line may not follow, never one that would leave the rest of its row or a later row no line; a row is narrower than `width_min` only where the limits allow no more), the templates (a template of the biome hosting the kind with an exit for each of the room's links, `RunContent.templates_for`, never one a room leading to it has while another is left) and the fill (by the kind's `RoomKind.fill`: enemies of the biome's pool at the room's depth until the rules' `room_budget` is spent, one at least; a boss of the boss pool). Its rolls are `sim.chance(&"run_map", step and attempt, count)`. The limits never corner a map; `not_after` can (a room led to by kinds no one line may follow: the validator checks kinds, not links), and then the map is tried again with the next attempt's rolls (`ATTEMPTS`); a map not made has no rooms and says why (`RunMap.problems`), as does a definition with problems.
- **`RunMap`** (`run_map.gd`): its run and biome, its rooms (`nodes`, row by row, left to right) and `problems`; `rows()`, `row(at)`, `node(index)`, `first()`, `parents_of(index)`. **`RunNode`** (`run_node.gd`): its `index`, `row`, `depth` (the rules' row it stands for: its row unless a row before it was left out), `kind`, `room` (a template id), `links` (next row's rooms) and `enemies` (ids). Plain values and ids, never files: the map is state as it is (hashed, saved in snapshots), so a joining machine never makes its own.
- **Tests:** `tests/gameplay/run/test_run_generator.gd`: thousands of seeds through every rule on the crypt run and made-up runs, the same seed the same map, deleting any room, enemy or boss, a heavy limited kind, limits narrower than `width_min`, a `not_after` corner, and the map as state.

## Contract

- **Public entry script:** `gameplay/run/run.gd`, the autoload `Run` (registered in `project.godot`). Other code uses only this script and the events it sends and listens to; nothing else in the folder is public (the map's scripts are its own; tests read them).
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `run_room_chosen` (RG3); later `run_started` and `run_ended` (M3).
  - Listens to: `run_begun` (from flow, RG3), `run_way_taken` (from flow, RG4); later `room_cleared`, `player_downed` and `pause_requested` (from the HUD).
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

The area's entry script `run.gd` and its test `tests/gameplay/run/test_run.gd`; the map's scripts (`run_generator.gd`, `run_map.gd`, `run_node.gd`).

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
tools/ptest.sh 8 'test_run_generator|test_run_rules|test_runs|test_run\.gd|test_flow'
```

## Review questions

A good PR here changes how a run starts, ends or is summarised, keeps runs reproducible from their seed, and works for 1–4 players. Besides the general review:

- Is a run reproducible from its seed? Does the summary cover every player and never wait for one?
- Does it keep to the dependency direction, without calling another area directly?
