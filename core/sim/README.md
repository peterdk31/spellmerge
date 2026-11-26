# Sim

## Purpose

The simulation's tools, so the same inputs give the same game, to the bit, on every machine: `StateWalk`, `SimHash`, `Desync`, the autoload `Tick`, `Sim` (time, chance), `DMath`, `SimFresh`, `SessionRules`, `RunUnlocks`, `Snapshot`, and the input path (`InputFrame`, the autoload `Frames`, `Replay`, `LiveFeed`, `FrameSource`). Claude only, like all of `core/`.

## The simulation folders

Every script in these folders, and every inner class of one, is a **simulation script** (`StateWalk.FOLDERS`): simulation by default, so a new gameplay folder is covered the day it gets its first script (N9).

| Folder | Why |
|---|---|
| `core/actors/` | the actor table: who an actor is |
| `core/items/` | the item stacks an inventory holds (items I3) |
| `core/projectiles/` | every shot, its hits and its trails' samples |
| `core/spells/` | the spell runtime, staffs, carriers |
| `gameplay/` | every gameplay area (actor, ai, combat, coop, flow, player, and any new one), but `gameplay/feel/` |

`gameplay/feel/` is view as a whole (`StateWalk.VIEW_FOLDERS`); `core/sim/` is not simulation. View code may use real time and its own dice, and only reads the game.

## The line (N9)

`tests/core/test_sim_rules.gd` (`RULES`) fails a simulation script on: **the clock** (`Time`, `OS.get_ticks_*`, engine frame counters, time scale, timers, tweens, `await`, deferred calls, `_process`, `_physics_process`); **the dice** (`randf`, `randi`, `randomize`, `RandomNumberGenerator`); **engine maths** (`sin`, `atan2`, `pow`, `Vector2.rotated`, ...); **input** but the seat's frame (`Input`, `InputManager`, `LocalInput`, `PlayerInput`, the mouse); **the picture** (`get_viewport`, `Camera2D`; the room's size is `RoomBase.size_in`); **instance ids** kept as state. Drawing code in a simulation script is a function named in its `VIEW`, or a line marked `# view: why`; `tests/core/test_determinism.gd` fails one that writes state.

## Contract

- **State by default.** Every member of a simulation script is state, except what its lists name (a subclass names its own, `DERIVED_BEAM`):
  - `DERIVED`: services, caches, scratch, instance ids; never walked.
  - `VIEW`: read and written only by the drawing; never walked.
  - `REFS`: other bodies, walked as who they point at (an actor by its id).
  - `SPARES`: free lists of records set whole when taken; walked as their size.
  - `BY_ACTOR`: tables by actor id; state, hashed per id via `actor_parts() -> int`, `actor_part(id) -> Array` (and `actor_part_problems()`).
  - A view script in a simulation folder: `const VIEW_ONLY: bool = true`.
- **Made once, or waiting.** Never changed after it is made (compiled staffs, `HitProfile`, `AIBehaviour`): `const FROZEN: bool = true`, one leaf, kept as itself in a snapshot; never branch on which copy you hold. A per-row record that mostly waits: `func idle() -> bool`.
- **What state may hold:** values, arrays, dictionaries (keys are values), objects of scripts, owned simulation nodes, nodes with an int `id`, resources from files. A Callable, Signal, RID, engine object or service is a problem.
- A `static var` never holds state (DERIVED or VIEW; `tests/core/test_state_declared.gd`). A seed nobody chose: `SimSeed.fresh()` only.
- **The hash** (`SimHash`): `areas`, `whole`, `area`, `of`, `slice` (spread over ticks), over `Tick.state_areas()`. Only `SimHash` calls `actor_parts`/`actor_part`. **Desync:** `capture(areas)`, `first_parting(a, b)`, `compare(a, b)`.
- **Never in a normal build's tick:** walker, hash and report run in tests, tools, replays and the netcode.
- **Instance ids are not identities:** keep the actor's key (`Actors.key_of(id)`, `target_of_key`); an instance id only as a DERIVED lookup.

## The tick (N3a)

- The autoload `Tick` runs `Frames.tick`, then `Tick.STEPS` in order (bodies by actor id, `Tick.BODIES`), each with `Tick.DT` (1/60 s). The clock is `sim.tick` (state); never scale engine time.
- An area joins in `_ready`: `SimArea.join(self, &"Key")`, then `steps(key, call)` (key in `Tick.STEPS`), `renewed_by(begin_run)` or `fresh_because(reason)`, `takes_rules(take_rules)`. A new stepping area adds its key to `Tick.STEPS` (and `Tick.RUN_ORDER` if renewed).
- Still bodies (`Actor.is_still`) are not stepped. `Tick.set_ticking(node, on)`, `Actor.ticking` turn stepping off for tests. `ticked` is for followers outside the simulation only.

## Stops and holds (N4)

- `sim.hold(ticks)` and `sim.stop(reason)` / `sim.go(reason)`, in the sim's state (reasons: `Coop.MENU_OF`, `Coop.PAD_OF`, `BossIntroHold.STOP`); `steps(key, call, own_stops)` runs through its own area's stop. Nothing in the simulation reads the tree's pause.
- Local holds: Combat's `HitStop`, `Actors.hold`/`spend_hold`, `Projectiles.freeze_shot`; Feel only draws them.
- Nothing in the simulation reads the camera or knows of one.

## Chance (N3c)

`sim.chance(purpose, key, counter)` (`chance_int`, `chance_range`, `bits`) from the area's `sim` (DERIVED; `Sim.found(node)`, tests `Sim.seeded(7)`), with a counter of its rolls as state. No simulation script keeps a `RandomNumberGenerator`. A roll ignores the tick; name `sim.tick` if wanted.

## Maths (N7)

Simulation code calls `DMath` (`sin`, `cos`, `atan2`, `pow`, `ease`, `rotated`, ...), never the engine's; kernels call `native/src/dmath.h`, the same to the bit (`tests/core/test_dmath.gd`).

## Order (N3c)

Go through things in an order of your own (bodies by actor id, shots by slot, rows by row), never the tree's or a signal's connections.

## A run's start (N3b)

- `Tick.begin_run` resets the clock, takes seed, rules and unlocks from `Frames`, and calls each area's `begin_run` in `Tick.RUN_ORDER`. A `begin_run` is `clear()` then `SimFresh.renew(self)`.
- Session settings a run keeps: `const RUN_KEEPS`. A setting that changes the game is a `SessionRules` field (a row of `SessionRules.FIELDS`) taken in `take_rules`; one that only changes the look is VIEW; a change in a run is a command. Save flags: `sim.unlocks`.
- Scratch lists grown together are all DERIVED or all state; a DERIVED cache that follows the state is emptied by `clear`. `tests/core/test_tick.gd` fails an autoload not joined, renewed or excused.

## Snapshots (N10)

- `Snapshot.take(areas, world)` / `restore(areas, world)` save what `StateWalk` walks; no save code of your own.
- An area may give `rebuild_derived()` (DERIVED that follows the state), `remake_body(name) -> Node` (bodies built in code, matched by name as well as actor id, so the name says its row, e.g. Entities' `Decoy<row>`), `restore_nodes()`.
- Checked by `tests/core/test_snapshot.gd`, `tests/core/test_snapshot_game.gd`, `tests/core/test_content_determinism.gd`.

## Input (N2)

- Input is `InputFrame`s only: `frames.frame_of(seat)`. Devices, bots (`FrameSource`), replays and the network all make frames.
- A HUD request the simulation hears is a command: in `InputFrame.COMMAND_NAMES` (and `COMMAND_SHAPES`, at the end), heard through `Events.listen`, applied at the next tick's start; a body is named by `Actor.key`.
- Decoders are strict (`decode`; ids `[A-Za-z0-9_]`), never `bytes_to_var`. Replays: `Frames.record`, `play`, `play_live(feed)`, `restart`; files in `user://replays/` only.
- Seats: `seat_joined`/`seat_left` from `Frames` only; nothing in the simulation hears `device_joined`/`device_left`.

## Steps

A new member of a simulation script, by what it holds:

| It holds | List | Example |
|---|---|---|
| the game: a value, an object of a simulation script, an actor it owns | none (state) | `Combat._health` |
| a service, cache, scratch, instance id, `static var`, computed property | `DERIVED` | `Combat._row_by_node` |
| another body the game would miss | `REFS` | `AIBrain.target` |
| what only the drawing uses | `VIEW` | `Actor._looks` |
| spare records set whole when taken | `SPARES` | `Spells._pending_free` |
| a table by actor id | `BY_ACTOR` (state) | `Spells._installed` |
| a session setting a run keeps | `RUN_KEEPS` (state) | `ProjectileManager._cap` |
| a setting that changes the game | `SessionRules` field + `RUN_KEEPS` | `shot_cap` |
| a lookup that follows the state | `DERIVED` + `rebuild_derived()` ("Snapshots") | `ActorController._bound` |

A list sits above the first member with its one-line comment (`## Not state: ...`). Tests name what is missed: `tests/core/test_state_declared.gd`, `test_sim_rules.gd`, `test_state_walked.gd`, `test_determinism.gd`. Copy `gameplay/combat/combat.gd`'s lists; a command, `gameplay/flow/flow.gd`'s `run_requested`; an input source, `bench/bots/bot.gd`.

## Validate

`tools/check.sh`, then `ci/build/build.sh --quick --tests` (tests/core: test_state_*, test_determinism, test_input_frame, test_frames, test_*replay*, test_tick, test_sim_fresh, test_sim, test_snapshot*).

History and reasons: [docs/history/core-sim-README.md](../../docs/history/core-sim-README.md).
