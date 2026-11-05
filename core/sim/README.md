# Sim

## Purpose

The simulation's own tools (online-ready, phase N, [docs/milestones/online-ready.md](../../docs/milestones/online-ready.md)): the same inputs must give the same game, to the bit, on every machine, so online co-op can send inputs only. N1 brings the state walker, the state hash, the desync report and the one source of a seed nobody chose; the tick, the `sim` service, input frames, replays and snapshots come in later parts (N2, N3, N10).

## The simulation folders

Every script in these folders, and every inner class of one, is a **simulation script** (`StateWalk.FOLDERS`; N9 will enforce the line):

| Folder | Why |
|---|---|
| `core/actors/` | the actor table: who an actor is |
| `core/projectiles/` | every shot, its hits and its trails' samples |
| `core/spells/` | the spell runtime, staffs, carriers |
| `gameplay/actor/` | bodies, their components and controllers |
| `gameplay/ai/` | brains, the team board, entities |
| `gameplay/combat/` | health, statuses, reactions |
| `gameplay/coop/` | joins, revives |
| `gameplay/flow/` | rooms, waves, the run's flow |
| `gameplay/horde/` | the horde director, the swarm, gems |
| `gameplay/player/` | a seat's body and its staffs |

`core/sim/` itself is not one: these tools read the simulation, they are not part of it. Everything else (Feel, the HUD, the camera, looks) is view: it may use real time and its own generators, as long as it only reads the game.

## Contract

- **State by default.** Every member of a simulation script is state, except what it lists:
  - `const DERIVED: Array[StringName]`: references to services, caches, scratch reused within a step, instance ids: anything set up again or rebuilt from state. Never walked.
  - `const VIEW: Array[StringName]`: what only the drawing reads and writes. Never walked.
  - `const REFS: Array[StringName]`: references to bodies it does not own that are state all the same (an AI's target, the body a shot is stuck to, the bodies a zap is due on, the row bodies of Combat). Walked as **who** they point at, never entered: an actor by its id, anything else by what it is, until N5 gives every body an identity of its own. In an array only the filled entries are walked, each with its index, so a slot-sized array that is nearly all empty costs one engine call.

  A list is named after its kind, or after its kind, `_` and a name of the script's own: a script that extends one with a `DERIVED` list cannot declare `DERIVED` again (GDScript forbids it), so it declares `DERIVED_BEAM`. The lists of a script and the scripts it extends are all read. A look or another view script inside a simulation folder says `const VIEW_ONLY: bool = true`; the walker never enters it, and a member that holds one is in VIEW or DERIVED.
- **What state may hold** (`state_walk.gd`, `StateWalk`): values, packed arrays, arrays (a typed array of plain values in one go), dictionaries (keys sorted; a key is a value, never an object), objects of scripts (walked member by member, once), a simulation node the holder owns (an actor's components: its descendants, with `position` and a body's `velocity`), a reference to a simulation node with an int `id` (an actor: its id), resources from files and scenes (their path: data cannot desync) and `RandomNumberGenerator`s (seed and state). Anything else is a problem, named with its path and the fix: a service (DERIVED), another body without an id (REFS), a Callable, a Signal, an RID, an engine object.
- **What the walker cannot see** is checked by reading the source (`tests/core/test_state_declared.gd`): a `static var` belongs to no object, so it is listed in DERIVED or VIEW (a cache, a test switch) and never holds state; and a simulation script reads no clock (`Time`, `OS.get_ticks_*`) and rolls no global dice (`randomize()`, `randf()`, `randi()`, `seed()`). A seed nobody chose (a horde's waves) comes from `SimSeed.fresh()` (`sim_seed.gd`), the one place the simulation reaches the engine's global generator; N11 makes it the session's seed. View-only scripts may do both.
- **The hash** (`sim_hash.gd`, `SimHash`): `SimHash.areas({name: object}, walk)` gives one 64-bit hash per area (problems in `walk.problems`), `SimHash.whole(hashes)` the game's, `SimHash.area(walk, name, object)` one area. The caller hands it the areas (the tick from N3, tests now); areas never reach into each other. A packed or typed array is hashed by the engine's `hash()` in one call, which hashes -0.0 as 0.0 and every NaN alike inside an array (a single value is hashed by its bytes). Its cost grows with the shot cap, not the live shots: the projectile manager and the actor table hash in about 2 ms at the desktop cap (6,000) and 15 ms at 100,000, on the owner's machine, headless.
- **The desync report** (`desync.gd`, `Desync`): `capture(areas)` after each tick records the hashes, and every leaf of one chosen tick (`Desync.new(tick)`), with paths for that tick only (a path per leaf every tick made a determinism test 3.5 times slower); `Desync.first_parting(a, b)` is the first tick two runs part, and `Desync.compare(a, b)` names that tick, its areas and each member that differs, with both values (a packed array's first differing index).
- **Never in a normal build's tick.** The walker, the hash and the report run in tests, tools, replays and later the netcode only.
- **Instance ids are not identities.** They differ between runs: a member that keys by one (`Combat._row_by_node`, `Actors._node`) is DERIVED until N5 gives identities without them.

## Allowed files

Claude only, like all of `core/`. Typed GDScript, no banned APIs.

## Steps

A new member of a simulation script, by what it holds:

| It holds | List | Examples |
|---|---|---|
| the game: a value, a packed array, an object of a simulation script, an actor it owns | none (state by default) | `Combat._health`, `Actor.intent` |
| a service, or a node the area sets up again | `DERIVED` | `events`, `projectiles`, `Flow.world` |
| a cache, scratch refilled within a step, an instance id | `DERIVED` | `Spells._zap_near`, `Combat._row_by_node` |
| another body the game would miss if it were lost | `REFS` | `AIBrain.target`, `ProjectileManager._stuck_to` |
| what only the drawing reads and writes | `VIEW` | `ProjectileManager._drawn_seq`, `Actor._looks` |

And around it:
- A `static var`: `DERIVED` (a cache, a test switch); it never holds state.
- A look or another script that only draws: `const VIEW_ONLY: bool = true`.
- Chance: a `RandomNumberGenerator` of the area's own, seeded by the game; a seed nobody chose: `SimSeed.fresh()`. Time: `delta` and `sim_time`, never a clock.
- A list sits above the script's first member, with its one-line comment (`## Not state: ...`, `## State as who they point at: ...`); a subclass of a script with a list names its own (`DERIVED_BEAM`).

The tests say what is missed: `tests/core/test_state_declared.gd` from the types and the source (every script and inner class), `tests/core/test_state_walked.gd` in running games (three scenes and every card), and `tests/core/test_determinism.gd` any member that parts between two runs of the same scene. Each names the file, the member and the list it belongs in.

## Example to copy

`gameplay/combat/combat.gd`'s DERIVED and REFS lists (services, instance-id keys; the body of each row).

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick --tests   # test_state_walk, test_state_declared, test_state_walked, test_determinism
```

## Review questions

- Is every name in DERIVED really rebuilt or set up again, not state that would be lost? A body the game would miss goes in REFS.
- Does a new scene in `tests/core/sim_scenes.gd` play the same twice?
