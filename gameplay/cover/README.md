# Cover

## Purpose

The game's part of a room's ground cover (ground cover GC5, [docs/milestones/ground-cover.md](../../docs/milestones/ground-cover.md), rules 3 to 6): grass that fire lights, spreads and leaves ash, frost puts out, and that burns whoever stands in it; cobwebs that chill. What a kind of cover is (its states, triggers, look) is data, `CoverKind` (core/base, `content/cover/<id>/`); where it grows is `CoverLayout` (core/base); what it looks like is Feel's (`gameplay/feel/cover.gd`).

## Contract

- **Public entry script:** `gameplay/cover/cover.gd` (autoload `Cover`, after `Items` in project.godot's order). Other code uses only its events (the AI's look among them, `cover_danger_looked`, GC7); tests read it.
- **One simulation area, never an actor a tuft** (W8c): it steps under `Tick.STEPS` "Cover", after the bodies (it reads where they stood after their move) and before the items; renewed at a run's start (`Tick.RUN_ORDER`, `begin_run`).
- **A cover a room** (connected biomes CB3b, [docs/milestones/connected-biomes.md](../../docs/milestones/connected-biomes.md)): every piece of the world laid (`room_built`, by its number: a row run's one room, a biome's rooms then bridges) has its own cover in play, a `CoverRoom` (`cover_room.gd`), laid at the piece's place and mirrored with it (`CoverLayout.of_piece`: the template's cells mirrored in whole cells and moved to its place; Feel draws its tufts again there, never flipped, decision 6). Each room's cells, rolls and changes are its own; a spread's roll key carries the room's number past its cell's (`CoverRoom.ROOM_KEY_SHIFT`), the first room's 0, so a row run rolls as it did. Every piece's cover is worked out as the world is laid, once a piece (measured: about 4 ms a crypt room to work out and 4 ms to draw, against about 1.3 s for the whole twelve-room biome's start; `tests/gameplay/cover/test_cover_biome.gd` prints it).
- **State:** each room's (`CoverRoom`: each cell's state (its index in its kind's `states`, 0 at rest) and its seconds in it (packed arrays the layout's size; empty for a room with no cover), the cells not at rest in cell order and its roll counter); the area's: the touches heard since its last step, each harmed body's time to its next status (by actor id and key, in id order; dropped once that time is out after it leaves harmful cover (GC8), or the tick its id goes). A room where nothing has happened hashes as arrays of zeros.
- **Derived:** each piece's layout and the kinds, set by `room_built` (`CoverLayout.of_piece` with the registry's kinds that are `CoverSketch.usable`, as Feel takes them; `use_kinds` gives its own, for tests; a new world's first piece, FIRST_ROOM, begins the list again), which never changes a room's state but to size it at rest when it is empty. After a restore each room is bound to its piece's layout again (`rebuild_derived`). What this machine's view was last told (`CoverRoom._said`).
- **Where a world starts:** `room_entered` of FIRST_ROOM (Flow's `_announce_room`: a run's start and each row room the party goes on into, a biome's start; never a restore) puts every room's cells at rest and drops what is queued and who is harmed. A biome's later room's first entry changes nothing: what burnt there before anyone came in stays burnt. So a snapshot's fire survives the `room_built` its restore sends (`tests/gameplay/cover/test_cover_rooms.gd`).
- **The kinds' moves as tables** (`cover_moves.gd`, derived, worked out with the layout; GC6): what each state of each kind does on each element, after how long, and what it spreads, read by the step's loops instead of the kinds' resources (a whole room may burn at once: tests/benchmark/cover_cost.gd).
- **Awake rooms step** (connected biomes CB3b): a room's cells count time only while its place is awake (`RoomGrid.is_awake`, the projectile manager's grid, which Flow's room life tells each tick and again after a restore; always in a world with no places), so a sleeping room's fire waits as if no time had passed. A touch lights a sleeping room's cover all the same (it counts no time), and a sleeping body (`Actors.asleep`) is asked nothing and its time to its next status waits.
- **The step**, in order:
  1. **Touches:** each queued `floor_touched`, in the order heard, fires the `element` trigger of every cell inside its circle (the cell it lands in, and each cell whose middle is within its radius), in cell order, in every room its circle reaches (in number order). Walls do not stop a touch's circle.
  2. **Cells:** in each awake room (in number order), each cell not at rest, in cell order, counts its seconds; its state's first `after` trigger whose seconds have passed moves it on (to rest: it leaves the list). A state that spreads (`spreads`, `spread_chance` a second) rolls once for each of its four neighbours (up, right, down, left) that its element would move to another state (a row naming the state it is in moves nothing, so costs no roll): `sim.chance(&"cover_spread", room key + cell * 4 + direction, the room's counter)`, the chance `spread_chance × delta`. The spreads rolled apply once every cell has stepped, so a cell lit by a spread this tick spreads from the next (one lit by a touch steps in the tick it is lit).
  3. **Bodies** (looked at only while a cell of some room is out of rest, a kind with cells in a room harms at rest, or a body is still kept as harmed: GC6): every open actor with a body in the tree (props too) that is not asleep, in actor id order, standing (its position; its room the grid's place there, `room_at`) in a cell whose state gives a status is asked it through `status_requested` (by NO_PLAYER) at once and again every `status_every` seconds while it stays in such cover (one timer a body, whatever cover it moves between; it runs on after the body leaves and the body is dropped once it is out, GC8, so stepping in and out is asked no oftener than standing in it). Combat applies it by its own rules; a prop's `status` trigger lights a dust heap or a barrel.
  4. **Said:** that tick's changes, one `cover_changed` a room that changed.
- **Looked at** (rule 8, GC7): `cover_danger_looked(actor, at, reach, sight)` fills the asker's `CoverSight` (core/base) at once (`look`): a window of the cells within `reach` of `at` (at most `CoverSight.SIDE`, 9, a side, clipped to the room `at` is in; its `offset` the room's grid corner in the world), each marked where its state gives a status (the cells step 3 asks a status for: burning grass, cobwebs; ash and grass at rest not). It returns at once, marking nothing, when no cell is in a state that harms (a count kept with each change and counted again from the state as a room is laid, entered or restored: `_harming`, derived; the states' harm a table of `cover_moves.gd`) or the room has no cover. Allocates nothing; changes no state. Whether the body would shrug it off is Combat's, never asked.
- **Said to the view:** `cover_changed(room, cells, states)` (the room's number, its cells) each tick something changed in it; after each `room_built`, every cell of that room not at rest (Feel, an earlier autoload, hears `room_built` first and has laid the room at rest); after a restore (`rebuild_derived`), every cell whose state the view was told otherwise.
- **Dependency direction:** `core` ← `gameplay` ← `content`. It uses `core/` (the bus, the actor table, the registry, `CoverLayout`, `Sim`, the projectile manager's grid for where a place is and whether it is awake); it knows nothing of Spells, Combat, the HUD, the AI or `net/`, and calls none.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `cover_changed`, `status_requested`.
  - Listens to: `room_built` and `room_entered` (flow), `floor_touched` (core/spells), `cover_danger_looked` (ai).

## Allowed files

`.gd`, plus `.uid` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

- **A new kind of cover:** a content folder (`content/cover/<id>/`, GC8), never code here.
- **A new kind of trigger** (a trample that plays, `walked`): a `CoverTrigger.When` row and its firing in `cover.gd`'s step.

## Example to copy

The game's kinds are content (`content/cover/`, GC8: the hub's grass, the crypt's cobwebs; content/cover/README.md); the test grass, `tests/core/fixtures/cover_content/cover/test_grass/test_grass.tres`, is the tests' own. A kind's test plays its states through this area with `tests/gameplay/cover/cover_kit.gd`.

## Validate

```sh
tools/ptest.sh 8 'test_cover|test_ai_cover|test_floor_touched|test_snapshot_game|test_content_determinism|test_room_life'
```

What it costs (GC6; the numbers are in docs/DECISIONS.md, 2026-11-16), not run in the build:

```sh
godot --headless --path . --script res://tests/benchmark/cover_cost.gd [-- --bodies=100 --ticks=300 --only=none,rest,burning,front]
```
