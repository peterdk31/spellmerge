# Cover

## Purpose

The game's part of a room's ground cover (ground cover GC5, [docs/milestones/ground-cover.md](../../docs/milestones/ground-cover.md), rules 3 to 6): grass that fire lights, spreads and leaves ash, frost puts out, and that burns whoever stands in it; cobwebs that chill. What a kind of cover is (its states, triggers, look) is data, `CoverKind` (core/base, `content/cover/<id>/`); where it grows is `CoverLayout` (core/base); what it looks like is Feel's (`gameplay/feel/cover.gd`).

## Contract

- **Public entry script:** `gameplay/cover/cover.gd` (autoload `Cover`, after `Items` in project.godot's order). Other code uses only its events; tests and the AI's later look (GC7) read it.
- **One simulation area, never an actor a tuft** (W8c): it steps under `Tick.STEPS` "Cover", after the bodies (it reads where they stood after their move) and before the items; renewed at a run's start (`Tick.RUN_ORDER`, `begin_run`).
- **State:** each cell's state (its index in its kind's `states`, 0 at rest) and its seconds in it (packed arrays the layout's size; empty for a room with no cover), the cells not at rest in cell order, the touches heard since its last step, each harmed body's time to its next status (by actor id and key, in id order; dropped the tick it leaves or its id goes) and its roll counter. A room where nothing has happened hashes as arrays of zeros.
- **Derived:** the layout and the kinds, set by `room_built` (`CoverLayout.of` with the registry's kinds that are `CoverSketch.usable`, as Feel takes them; `use_kinds` gives its own, for tests), which never changes the state but to size it at rest when it is empty. What this machine's view was last told (`_said`).
- **Where a room starts:** `room_entered` (Flow's `_announce_room`: a run's start and each room the party goes on into; never a restore) puts every cell at rest and drops what is queued and who is harmed. So a snapshot's fire survives the `room_built` its restore sends (`tests/gameplay/cover/test_cover_rooms.gd`).
- **The kinds' moves as tables** (`cover_moves.gd`, derived, worked out with the layout; GC6): what each state of each kind does on each element, after how long, and what it spreads, read by the step's loops instead of the kinds' resources (a whole room may burn at once: tests/benchmark/cover_cost.gd).
- **The step**, in order:
  1. **Touches:** each queued `floor_touched`, in the order heard, fires the `element` trigger of every cell inside its circle (the cell it lands in, and each cell whose middle is within its radius), in cell order. Walls do not stop a touch's circle.
  2. **Cells:** each cell not at rest, in cell order, counts its seconds; its state's first `after` trigger whose seconds have passed moves it on (to rest: it leaves the list). A state that spreads (`spreads`, `spread_chance` a second) rolls once for each of its four neighbours (up, right, down, left) that its element would move to another state (a row naming the state it is in moves nothing, so costs no roll): `sim.chance(&"cover_spread", cell * 4 + direction, counter)`, the chance `spread_chance × delta`. The spreads rolled apply once every cell has stepped, so a cell lit by a spread this tick spreads from the next (one lit by a touch steps in the tick it is lit).
  3. **Bodies** (looked at only while a cell is out of rest, a kind with cells in the room harms at rest, or a body is still kept as harmed: GC6): every open actor with a body in the tree (props too), in actor id order, standing (its position) in a cell whose state gives a status is asked it through `status_requested` (by NO_PLAYER) at once and again every `status_every` seconds while it stays in such cover (one timer a body, whatever cover it moves between). Combat applies it by its own rules; a prop's `status` trigger lights a dust heap or a barrel.
  4. **Said:** that tick's changes, one `cover_changed`.
- **Said to the view:** `cover_changed(cells, states)` each tick something changed; after each `room_built`, every cell not at rest (Feel, an earlier autoload, hears `room_built` first and has laid the room at rest); after a restore (`rebuild_derived`), every cell whose state the view was told otherwise.
- **Dependency direction:** `core` ← `gameplay` ← `content`. It uses `core/` (the bus, the actor table, the registry, `CoverLayout`, `Sim`); it knows nothing of Spells, Combat, the HUD, the AI or `net/`, and calls none.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `cover_changed`, `status_requested`.
  - Listens to: `room_built` and `room_entered` (flow), `floor_touched` (core/spells).

## Allowed files

`.gd`, plus `.uid` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

- **A new kind of cover:** a content folder (`content/cover/<id>/`, GC8), never code here.
- **A new kind of trigger** (a trample that plays, `walked`): a `CoverTrigger.When` row and its firing in `cover.gd`'s step.

## Example to copy

The test grass, `tests/core/fixtures/cover_content/cover/test_grass/test_grass.tres` (the game's own kinds come with GC8's art).

## Validate

```sh
tools/ptest.sh 8 'test_cover|test_floor_touched|test_snapshot_game|test_content_determinism'
```

What it costs (GC6; the numbers are in docs/DECISIONS.md, 2026-11-16), not run in the build:

```sh
godot --headless --path . --script res://tests/benchmark/cover_cost.gd [-- --bodies=100 --ticks=300 --only=none,rest,burning,front]
```
