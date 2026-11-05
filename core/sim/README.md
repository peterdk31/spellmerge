# Sim

## Purpose

The simulation's own tools (online-ready, phase N, [docs/milestones/online-ready.md](../../docs/milestones/online-ready.md)): the same inputs must give the same game, to the bit, on every machine, so online co-op can send inputs only. N1 brings the state walker, the state hash and the desync report; the tick, the `sim` service, input frames, replays and snapshots come in later parts (N2, N3, N10).

## The simulation folders

Every script in these folders is a **simulation script** (`StateWalk.FOLDERS`; N9 will enforce the line):

| Folder | Why |
|---|---|
| `core/actors/` | the actor table: who an actor is |
| `core/projectiles/` | every shot, its hits and its trails' samples |
| `core/sim/` | these tools |
| `core/spells/` | the spell runtime, staffs, carriers |
| `gameplay/actor/` | bodies, their components and controllers |
| `gameplay/ai/` | brains, the team board, entities |
| `gameplay/combat/` | health, statuses, reactions |
| `gameplay/coop/` | joins, revives |
| `gameplay/flow/` | rooms, waves, the run's flow |
| `gameplay/horde/` | the horde director, the swarm, gems |
| `gameplay/player/` | a seat's body and its staffs |

Everything else (Feel, the HUD, the camera, looks) is view: it may use real time and its own generators, as long as it only reads the game.

## Contract

- **State by default.** Every member of a simulation script is state, except what it lists in `const DERIVED: Array[StringName]` (caches, references to services and nodes, instance ids, anything set up again or rebuilt from state) or `const VIEW: Array[StringName]` (what only the drawing reads and writes). A look or another view script inside a simulation folder says `const VIEW_ONLY: bool = true`; the walker never enters it, and a member that holds one is in VIEW or DERIVED. A script that extends one with a list cannot declare the same constant again: its own names go in the base's list, or it is split.
- **What state may hold** (`state_walk.gd`, `StateWalk`): values, packed arrays, arrays (a typed array of plain values in one go), dictionaries (keys sorted), objects of scripts (walked member by member, once), a simulation node the holder owns (an actor's components: its descendants, with `position` and a body's `velocity`), a reference to a simulation node with an int `id` (an actor: its id), resources from files and scenes (their path: data cannot desync) and `RandomNumberGenerator`s (seed and state). Anything else is a problem, named with its path and the fix: a service or another area's node, a Callable, a Signal, an RID, an engine object.
- **The hash** (`sim_hash.gd`, `SimHash`): `SimHash.areas({name: object})` gives one 64-bit hash per area, `SimHash.whole(hashes)` the game's. The caller hands it the areas (the tick from N3, tests now); areas never reach into each other. A packed array is hashed by the engine's `hash()` in one call. About 4 ms for 5,000 shots and 200 bodies (projectiles, Combat, the actor table) on the cloud test machine.
- **The desync report** (`desync.gd`, `Desync`): `capture(areas)` after each tick records the hashes, and every leaf of one chosen tick (`Desync.new(tick)`); `Desync.first_parting(a, b)` is the first tick two runs part, and `Desync.compare(a, b)` names that tick, its areas and each member that differs, with both values (a packed array's first differing index).
- **Never in a normal build's tick.** The walker, the hash and the report run in tests, tools, replays and later the netcode only.
- **Instance ids are not identities.** They differ between runs: a member that keys by one (`Combat._row_by_node`, `Actors._node`) is DERIVED until N5 gives identities without them.

## Allowed files

Claude only, like all of `core/`. Typed GDScript, no banned APIs.

## Steps

A new member of a simulation script needs nothing: it is state. A cache, a reference to a node or service, or an instance id goes in DERIVED, and something only the drawing uses in VIEW; `tests/core/test_state_declared.gd` names any that cannot be state, and `tests/core/test_determinism.gd` any that parts between two runs of the same scene.

## Example to copy

`gameplay/combat/combat.gd`'s DERIVED list (services, node references, instance-id keys).

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick --tests   # test_state_walk, test_state_declared, test_determinism
```

## Review questions

- Is every name in DERIVED really rebuilt or set up again, not state that would be lost?
- Does a new scene in `tests/core/sim_scenes.gd` play the same twice?
