# Sim

## Purpose

The simulation's own tools (online-ready, phase N, [docs/milestones/online-ready.md](../../docs/milestones/online-ready.md)): the same inputs must give the same game, to the bit, on every machine, so online co-op can send inputs only. N1 brings the state walker, the state hash, the desync report and the one source of a seed nobody chose; N2 the one input path (input frames, the frames service, replays); N3a the one clock (the Tick); N3b a run's start from a fresh game's state; N3c the `sim` service (time and chance by hash); snapshots come in a later part (N10).

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

`core/sim/` itself is not one: these tools read the simulation and feed it its input, they are not part of it. Everything else (Feel, the HUD, the camera, looks) is view: it may use real time and its own generators, as long as it only reads the game.

## Contract

- **State by default.** Every member of a simulation script is state, except what it lists:
  - `const DERIVED: Array[StringName]`: references to services, caches, scratch reused within a step, instance ids: anything set up again or rebuilt from state. Never walked.
  - `const VIEW: Array[StringName]`: what only the drawing reads and writes. Never walked.
  - `const REFS: Array[StringName]`: references to bodies it does not own that are state all the same (an AI's target, the body a shot is stuck to, the bodies a zap is due on, the row bodies of Combat). Walked as **who** they point at, never entered: an actor by its id, anything else by what it is, until N5 gives every body an identity of its own. In an array only the filled entries are walked, each with its index, so a slot-sized array that is nearly all empty costs one engine call.
  - `const SPARES: Array[StringName]`: free lists of spare records, each set whole when it is taken (Spells' spare launches): walked as their size alone (N3c).

  A list is named after its kind, or after its kind, `_` and a name of the script's own: a script that extends one with a `DERIVED` list cannot declare `DERIVED` again (GDScript forbids it), so it declares `DERIVED_BEAM`. The lists of a script and the scripts it extends are all read. A look or another view script inside a simulation folder says `const VIEW_ONLY: bool = true`; the walker never enters it, and a member that holds one is in VIEW or DERIVED.
- **Made once, or waiting** (N3c, for the hash's cost): a script whose objects are made whole and never changed after (a compiled staff, its casts, groups and spells, a cast's sense) says `const FROZEN: bool = true`; wherever one is met it is one leaf, the hash of its members, worked out once (`tests/core/test_state_walked.gd` walks every card with `verify_frozen`, which names one that changed). A record a carrier keeps per row, nearly all waiting (a dash's or a beam leg's homing), has `func idle() -> bool`, true while its state is a fresh one's: it is one leaf then.
- **What state may hold** (`state_walk.gd`, `StateWalk`): values, packed arrays, arrays (a typed array of plain values in one go; in one with empty slots, only the filled ones, each after its index: a carrier's per-actor table is mostly empty), dictionaries (keys sorted, StringNames by their text: the engine's own sort orders them by address, which differs between machines; a key is a value, never an object), objects of scripts (walked member by member, once), a simulation node the holder owns (an actor's components: its descendants, with `position` and a body's `velocity`), a reference to a simulation node with an int `id` (an actor: its id), resources from files and scenes (their path: data cannot desync) and `RandomNumberGenerator`s (seed and state). Anything else is a problem, named with its path and the fix: a service (DERIVED), another body without an id (REFS), a Callable, a Signal, an RID, an engine object.
- **What the walker cannot see** is checked by reading the source (`tests/core/test_state_declared.gd`): a `static var` belongs to no object, so it is listed in DERIVED or VIEW (a cache, a test switch) and never holds state; and a simulation script reads no clock (`Time`, `OS.get_ticks_*`) and rolls no global dice (`randomize()`, `randf()`, `randi()`, `seed()`). A seed nobody chose (a horde's waves) comes from `SimSeed.fresh()` (`sim_seed.gd`), the one place the simulation reaches the engine's global generator; N11 makes it the session's seed. View-only scripts may do both.
- **The hash** (`sim_hash.gd`, `SimHash`): `SimHash.areas({name: object}, walk)` gives one 64-bit hash per area (problems in `walk.problems`), `SimHash.whole(hashes)` the game's, `SimHash.area(walk, name, object)` one area. The caller hands it the areas: the game's are named by the Tick (`Tick.state_areas()`: "Sim", the simulation's autoloads, every actor's body by id), a test world's by the test; areas never reach into each other. The walk appends an area's leaves to one array (`StateWalk.values`, no call per leaf; a member declared a plain value is appended as it is), hashed by its bytes in one call; a packed or typed array in it stands as its type, size and the engine's `hash()` of it, which hashes -0.0 as 0.0 and every NaN alike inside an array (a single value is hashed by its bytes). Its cost grows with the shot cap, not the live shots: the projectile manager and the actor table hash in about 2 ms at the desktop cap (6,000) and 15 ms at 100,000, on the owner's machine, headless. The whole game's grows with its bodies (each walked member by member: about 0.2 us a plain member, a few us an object or a reference; the stress runs' numbers are in docs/milestones/online-ready.md, N3c), so a check of it is spread over ticks: `Tick.state_slice(slice, slices)` is one part, a service one to a part and a body by its id, every machine hashing the same part at the same tick.
- **The desync report** (`desync.gd`, `Desync`): `capture(areas)` after each tick records the hashes, and every leaf of one chosen tick (`Desync.new(tick)`), with paths for that tick only (a path per leaf every tick made a determinism test 3.5 times slower); `Desync.first_parting(a, b)` is the first tick two runs part, and `Desync.compare(a, b)` names that tick, its areas and each member that differs, with both values (a packed array's first differing index).
- **Never in a normal build's tick.** The walker, the hash and the report run in tests, tools, replays and later the netcode only.
- **Instance ids are not identities** (N5). They differ between machines and runs, so the simulation never keeps one as state. A body's identity is its actor's **key** (`Actors.key_of(id)`: the id and its birth, the count of opens this run, so an id handed out again is another key; the births count from 0 at each run's start). The projectile manager names each target by it (`_target_key`, handed over by Combat; `key_of(node)`, `target_of_key(key)`), and what a shot or a spell keeps of "that body" is the key: a homing target, the hit memory, the body a payload spares, a chain's last body, a zap's rolls, an AI's target and the team board's attacks. A swarm promotion keeps the actor's key, so none of these is remapped. An instance id may still find a node by equality, as a DERIVED lookup (`Actors._node`, `Combat._row_by_node`, the manager's `_target_id`, the swarm's `_row_by_node`), never as state, an order or a seed.

## The tick (N3a)

- **One driver.** The autoload `Tick` (`tick.gd`) runs every tick, in a written order: the input frames (`Frames.tick`), then the services (the projectile manager, Spells, Combat, Entities), the horde's swarm, every actor's body by actor id (`Actor.tick_step`: its step, then its move), then the run's rules and timers (Flow's, Coop's `step_rules`, the horde director's `step_timers`). It is the order the scene tree gave them before, so the game plays as it did; only the bodies go by id now, not by when they joined the tree.
- **No callbacks in the simulation.** No area and no body has a `_physics_process` or a `_process` for the game; drawing stays in `_process` (view: the projectile manager's `update_draw`, Coop's camera, the looks). A new area that steps is called from the tick, at its place in the order.
- **What the tick steps:** an area or body whose physics processing is on (the timers: processing) and that can process (`Node.can_process`: the tree's pause and its process mode, as before). The flag is only "the tick steps me": a test or another area that steps a body itself turns it off (`set_physics_process(false)`).
- **Time:** every step gets the physics step's delta, `Tick.DT` (1/60 s; `tests/core/test_tick.gd`), except while Feel's stops scale the engine's time (A1, N4). A slow frame runs up to `max_physics_steps_per_frame` ticks, each of `DT`.
- **Nothing in the simulation reads the camera.** The camera eases as it is drawn, on real time; Coop works out the view it is fitted to on the tick and sends it (`view_fitted`), and the horde spawns outside that.

## Chance (N3c)

- **One source.** The simulation's chance comes from `sim` (`sim.gd`, `Sim`): the Tick owns the game's (`Tick.sim`: the tick, and the run's seed, dealt by `SimSeed.fresh()` at each run's start, a replay's while one records or plays). An area or a body holds it as a member `sim` (DERIVED), set by whoever makes it, else found (`Sim.found(node)`: the Tick's in the tree, else a shared one at seed 0); a test hands its own (`Sim.seeded(7)`). No simulation script keeps a `RandomNumberGenerator` (`tests/core/test_state_declared.gd`).
- **A roll is named, not drawn.** `sim.chance(purpose, key, counter)` (and `chance_int`, `chance_range`, `bits`) is a hash of the run's seed, the purpose (`&"scatter"`), the key (whose: a cast, a seat, an actor) and the counter (which of its rolls). No generator holds state, so a new roll in one system never shifts another's; the counters a caller keeps are its state, reset with it at a run's start. The same name gives the same roll, so a caller counts its rolls. The hash is the engine's of a `Vector4i` (murmur3), integer code, the same on every platform.
- **The tick is not in it.** A roll is the same whenever it is made, so an area a test steps by hand rolls as it does in the game; a caller that rolls once a tick names `sim.tick` itself.
- **Who rolls:** Spells' scatter and spread (`&"scatter"`, keyed by the cast; a later firing by its launch), the AI brain (`&"brain"`, keyed by its actor), the horde director (`&"horde_kind"`, `&"horde_spot"`, `&"horde_offer"` by seat), the swarm's row seeds (`&"swarm_row"`). Zaps, homing picks and the tails' hashes were already hashes of the shot (`Spells.zap_hash`, `tail_hash`): they stay so.

## Maths (N7)

- **The same bits on every platform.** The engine's `sin`, `cos`, `atan2`, `exp`, `log`, `pow`, `ease`, `Vector2.from_angle`, `rotated`, `angle` and `angle_to` call the platform's C library, which differs between Linux, Windows and the web in the last digit now and then (N2b found exactly that), and a game played online would part there. Simulation code calls `DMath` (`dmath.gd`) instead: the same functions, built from `+ - * /` and `sqrt` (and the exact `floor` and `fmod`), which IEEE 754 rounds the same everywhere.
- **Native, with a twin.** Each `DMath` function runs the native module's (`DMathKernel`, `native/src/dmath.h`) when it is loaded, else its GDScript twin, the same operations in the same order: `tests/core/test_dmath.gd` compares the two to the bit and both to the engine (within 2 units in the last place; tan, asin and acos 4). The kernels call `dmath.h` directly where the GDScript they stand for calls `DMath`. A Vector2 helper works in doubles and rounds to the vector's floats once.
- **Checked from the source:** `tests/core/test_state_declared.gd` fails on engine maths in a simulation script. A view-only script keeps the engine's; a line in a simulation script that only draws says so, `# view: why` (the horde gems' pulse).
- **Not covered here:** `+ - * /` and `sqrt` inside the engine's own code (a Vector2's `normalized`, `length`, `lerp`) are correctly rounded everywhere already; a node's `rotation` turns its transform with the engine's sin and cos (a solid shot's physics body: the bodies' moves leave the engine in N6).

## Order (N3c)

What the simulation goes through, it goes through in an order of its own, never the tree's or a signal's connections': the bodies by actor id (the Tick), the shots by slot, Combat's rows by row, Entities' rows by birth, Coop's wizards by actor id. An event several simulation areas hear goes to autoloads, in the project's autoload order; one a body hears (a mover's `target_move_requested`, a caster's `mana_spend_requested`, an actor's `possess_requested`) names the one body that acts on it.

## A run's start (N3b)

- **Every run starts from a fresh game's state.** When a run starts (Flow's `start_run`, once the last run's world is gone and before the new one is made), `Tick.begin_run` counts the clock from 0 again and calls `begin_run` on each area of `Tick.FRESH_AT_RUN`: Entities first (it frees the last run's decoys, bodies outside Flow's world that the manager and Combat still hold), then the other services, then the horde director. No area is renewed while a body that leaves later is still registered in it. A run then plays the same whatever ran before it in the game, and a replay recorded in any run plays the same in any other (`tests/core/test_replay_game.gd`, "after other runs").
- **An area's `begin_run`** ends what it holds and renews itself, nothing more:

  ```gdscript
  func begin_run() -> void:
  	clear()                 # its shots, rows, entities end (their events go out)
  	SimFresh.renew(self)    # every state member as a new object of its script has it
  ```

  `SimFresh.renew` (`sim_fresh.gd`) resets what `StateWalk` walks, so a member added later is reset too, with no list to keep. Its rules, in its class doc: `RUN_KEEPS` stay; an object held by a member or in a dictionary (a carrier, the AI board every brain shares) stays the same object and is renewed in turn; an array is the blank's, its objects too (a pool), and references into it follow (`Spells._ray` is the first of `_rays` again); DERIVED and VIEW are left alone. A blank deals the run no seeds (`SimSeed.aside`).
- **Settings stay:** what is the session's, not the run's (the shot cap, a dev slider, a benchmark's budget, the horde's curve), a script lists in `const RUN_KEEPS: Array[StringName]`, read like DERIVED (`tests/core/test_state_declared.gd` checks each name is a state member).
- **Lists that grow together are listed together.** Scratch kept in several lists grown at once, by a check on one of them (a ray's lists per nesting level, a sweep's results), is all DERIVED or all state: a run's start empties state and keeps DERIVED, so a split leaves the check saying there is room the others no longer have (N3c's stress runs found two).
- **What fails loudly:** a simulation autoload neither in `Tick.FRESH_AT_RUN` nor in `Tick.RENEWED_OTHERWISE` with its reason (`test_tick.gd`); an area in `FRESH_AT_RUN` with no `begin_run`; a node out of the tree that `renew` would drop (a pool of bodies: free it before, as Entities frees its decoys).
- **What it cannot see:** a cache in DERIVED that follows the state must be emptied by the area's `clear`; an object in an array that something outside the area holds on to is replaced, so keep such an object in a member or a dictionary. A cache that would carry a run's answer into the next (a compiled staff outlives a run) is DERIVED.
- **Feel**, which is view, still decides some holds on real time until N4 (A1): its rests and repeats start again at `room_entered`.

## Input (N2)

- **One input path.** The simulation takes input from `InputFrame`s only (`input_frame.gd`): one seat's input for one tick, its move (a signed byte per axis), its aim (a 16-bit angle, or keep), the staff buttons held and pressed, captured (an overlay of the seat is open), and the tick's commands. A seat's `PlayerController` builds its actor's intent from its frame; nothing in the simulation reads a device, the mouse or the camera. Devices (`LocalInput`, core/input), bots (`FrameSource`, `frame_source.gd`), replays and later the network all produce frames.
- **The frames service** (`frames.gd`, the autoload `Frames`): the Tick calls its `tick` first in every tick, so it is the tick's start. It builds each seat's frame (from the replay played, the seat's source, or its device; captured holds a source still), records it when a replay records, and applies the frame's commands. `frame_of(seat)` is the tick's frame, read only.
- **Commands at the tick's start.** The HUD's requests the simulation hears (`InputFrame.COMMAND_NAMES`) are commands: the bus hands each to the frames service (`Events.command_sink`), which puts it into its seat's next frame and applies it when that tick starts (`Events.apply_command`); the simulation hears them through `Events.listen`, never by connecting to the signal. A frame speaks for its own seat only (the seat is not in the command). A device's join and leave are in the frame too (JOIN, LEAVE): they happen as the device joins (Flow and Coop read the joined seats at a run's start), and a replay played joins and leaves its seats at their tick. The requests that start a run (`play_requested`, `sandbox_requested`, `horde_requested`) are not commands: they are a replay's start.
- **The bytes** (`InputFrame.to_bytes`, `Replay.to_bytes`) have strict decoders: every size and value is checked, an id is letters, digits and `_` only (never a path), nothing is left over, no `bytes_to_var`; a bad frame or file is rejected whole and says why (`decode`).
- **Replays** (`replay.gd`): a run's build, content (a hash of every content id), seed, start (the request and the seat) and seats, then every tick's frames, inputs only. `Frames.record(start, starter, run_seed)` starts a run and records it (a random seed when `run_seed` is 0); `Frames.play(replay)` joins its seats, starts its run the same way and feeds its frames until they run out (live input and commands are dropped meanwhile). Each tick says whether the game stood paused: a paused tick plays while the game stands paused (the horde's level-up break), a pause of the recording's own (the pause menu) is skipped through at once with its commands, and a pause while playing holds the replay (N4 makes a stop part of the state). Files live in `user://replays/` only (`save(name)`, `open(name)`). While one records or plays, the seeds nobody chose are dealt from its seed (`SimSeed.begin`), and the horde director and the swarm take a new one at each run's start.
- **What a replay does not hold yet.** Feel's real-time stops (A1, N4) still run on real time; `tests/core/test_replay_game.gd` freezes them. A bot reads the game through queries that fill the services' caches, and those count as state (the projectile manager's threat grid and target table), so a bot's run replays exactly with the bot watching again (a source set while a replay plays is asked each tick and its frame dropped); a person's input reads nothing of the game but where the hand is. Shots keep homing targets and skips by instance id (`_home_target`, `_skip_id`, A5): a run with homing parts until N5.

## Allowed files

Claude only, like all of `core/`. Typed GDScript, no banned APIs.

## Steps

A new member of a simulation script, by what it holds:

| It holds | List | Examples |
|---|---|---|
| the game: a value, a packed array, an object of a simulation script, an actor it owns | none (state by default) | `Combat._health`, `Actor.intent` |
| a service, or a node the area sets up again | `DERIVED` | `events`, `projectiles`, `Flow.world` |
| a cache, scratch refilled within a step, an instance id, a switch that gives the same game either way | `DERIVED` | `Spells._zap_near`, `Combat._row_by_node`, `ProjectileManager.native` |
| another body the game would miss if it were lost | `REFS` | `AIBrain.target`, `ProjectileManager._stuck_to` |
| what only the drawing reads and writes | `VIEW` | `ProjectileManager._drawn_seq`, `Actor._looks` |
| a free list of spare records, each set whole when taken | `SPARES` | `Spells._pending_free` |
| a setting of the session a new run keeps (in an area with `begin_run`) | `RUN_KEEPS` (it stays state) | `ProjectileManager._cap`, `Horde.curve` |

And around it:
- A `static var`: `DERIVED` (a cache, a test switch); it never holds state.
- A look or another script that only draws: `const VIEW_ONLY: bool = true`.
- A script whose objects are made whole and never changed after: `const FROZEN: bool = true`. A per-row record that waits most of the time: `func idle() -> bool`.
- Chance: `sim.chance(purpose, key, counter)` with a counter of its rolls as state (above, "Chance"); a `sim` member in DERIVED. Time: `delta` and `sim_time`, never a clock.
- Angles, curves and turns: `DMath` (above, "Maths"), never the engine's `sin`, `pow` or `Vector2.rotated`.
- A list sits above the script's first member, with its one-line comment (`## Not state: ...`, `## State as who they point at: ...`); a subclass of a script with a list names its own (`DERIVED_BEAM`).

The tests say what is missed: `tests/core/test_state_declared.gd` from the types and the source (every script and inner class), `tests/core/test_state_walked.gd` in running games (three scenes and every card), and `tests/core/test_determinism.gd` any member that parts between two runs of the same scene. Each names the file, the member and the list it belongs in.

## Example to copy

`gameplay/combat/combat.gd`'s DERIVED and REFS lists (services, instance-id keys; the body of each row). A new HUD request the simulation hears: its name and shape in `InputFrame.COMMAND_NAMES` and `COMMAND_SHAPES` (at the end), its listener through `Events.listen` (`gameplay/flow/flow.gd`'s sandbox page). A new input source: a `FrameSource` (`tests/bots/bot.gd`).

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick --tests   # test_state_walk, test_state_declared, test_state_walked, test_determinism,
                                    # test_input_frame, test_frames, test_replay, test_replay_game,
                                    # test_tick, test_sim_fresh, test_sim
```

## Review questions

- Is every name in DERIVED really rebuilt or set up again, not state that would be lost? A body the game would miss goes in REFS.
- Does a new scene in `tests/core/sim_scenes.gd` play the same twice?
- Does any simulation code read a device, the mouse or the camera, or connect to a command's signal instead of `Events.listen`?
- Does new simulation maths go through `DMath`, and a kernel's through `dmath.h`, the two the same to the bit?
- Is a new area that keeps state between runs made fresh at a run's start (`begin_run` calling `SimFresh.renew`, in `Tick.FRESH_AT_RUN`), and is each name in its `RUN_KEEPS` a setting, not the run's state?
