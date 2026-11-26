# Cover

## Purpose

The game's part of a room's ground cover ([docs/milestones/ground-cover.md](../../docs/milestones/ground-cover.md), [docs/milestones/floor.md](../../docs/milestones/floor.md)): grass that fire lights and spreads, frost puts out, and that burns whoever stands in it; cobwebs that chill; the floor's water, lightning through it, ice. What a kind is (states, triggers, look) is data, `CoverKind` (core/base, `content/cover/<id>/`); where it grows is `CoverLayout` (core/base); its look is Feel's (`gameplay/feel/cover.gd`).

## Contract

- **Public entry script:** `gameplay/cover/cover.gd` (autoload `Cover`, after `Items`). Other code uses only its events; tests read it.
- **One simulation area, never an actor a tuft:** steps under `Tick.STEPS` "Cover", after the bodies and before the items; renewed at a run's start (`Tick.RUN_ORDER`, `begin_run`).
- **A cover a room:** every piece of the world laid (`room_built`) has its own `CoverRoom` (`cover_room.gd`), laid at the piece's place and mirrored with it (`CoverLayout.of_piece`). Each room's cells, rolls and changes are its own; a spread's roll key carries the room's number (`CoverRoom.ROOM_KEY_SHIFT`, the first room 0).
- **State** (`CoverRoom`): each cell's state index (0 at rest) and seconds in it (packed arrays; empty for a room with no cover), the cells not at rest in cell order, who lit each (`_active_actor`, `_active_tag`), its roll counter; the area's: touches heard since its last step, passing touches (`floor_passed`), each harmed body's time to its next status (by actor id and key, in id order; dropped once out after it leaves harmful cover, or when its id goes).
- **Derived:** each piece's layout and kinds, set by `room_built` (registry kinds that are `CoverSketch.usable`; `use_kinds` for tests; FIRST_ROOM begins the list again); rebound after a restore (`rebuild_derived`); `CoverRoom._said`.
- **Where a world starts:** `room_entered` of FIRST_ROOM puts every room's cells at rest and drops what is queued and who is harmed; a later room's first entry changes nothing; a snapshot's fire survives the restore's `room_built`.
- **The kinds' moves as tables** (`cover_moves.gd`, derived): the step reads them, never the kinds' resources.
- **Awake rooms step:** a room's cells count time only while its place is awake (`RoomGrid.is_awake`); a touch still lights a sleeping room; a sleeping body (`Actors.asleep`) is asked nothing and its status timer waits.
- **Looked at:** `cover_danger_looked(actor, at, reach, sight)` fills the asker's `CoverSight` at once (at most `CoverSight.SIDE`, 9, a side, clipped to the room), each cell marked where `CoverState.is_danger`; returns at once when no cell is danger (`_danger`, derived). Allocates nothing, changes no state, never asks Combat.
- **Said to the view:** `cover_changed(room, cells, states)` each tick something changed in a room; after each `room_built`, every cell of that room not at rest; after a restore, every cell the view was told otherwise.
- **Dependency direction:** `core` ← `gameplay` ← `content`. Uses `core/` only (the bus, the actor table, the registry, `CoverLayout`, `Sim`, the projectile manager's grid); knows nothing of Spells, Combat, the HUD, the AI or `net/`, and calls none.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `cover_changed`, `status_requested`, `floor_strike_requested`.
  - Listens to: `room_built` and `room_entered` (flow), `floor_touched` and `floor_passed` (core/spells), `cover_danger_looked` (ai).

## The step

In order, each tick:

1. **Touches:** each queued `floor_touched`, in the order heard, fires the `element` trigger of every cell inside its circle (its cell, and each cell whose middle is within its radius), in cell order, in every room it reaches (in number order); walls do not stop it. Then each `floor_passed` fires the cell under it alone (`room_at`). A row naming the cell's own state renews it (seconds from 0, lighter the toucher).
2. **Cells:** in each awake room (number order), each cell not at rest, in cell order, counts its seconds; its state's first `after` trigger whose seconds have passed moves it on (to rest: it leaves the list). A state that `spreads` rolls once for each of its four neighbours (up, right, down, left) its element would move: `sim.chance(&"cover_spread", room key + cell * 4 + direction, the room's counter)`, the chance `spread_chance × delta` (up to 60). Spreads apply once every cell has stepped.
3. **Bodies** (only while a cell gives something, `CoverState.gives`, or a body is still kept as harmed; rooms with `CoverRoom.harms_nobody` or no `has_active` are skipped): every open actor with a body that is not asleep, in actor id order, standing in a cell that gives something is asked its status through `status_requested` and, for a state with `strike_element`, struck through `floor_strike_requested`, both as the cell's lighter's (NO_PLAYER and 0 if nobody lit it), at once and again every `status_every` seconds (one timer a body).
4. **Said:** that tick's changes, one `cover_changed` a room that changed.

## Allowed files

`.gd`, plus `.uid` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

- **A new kind of cover:** a content folder (`content/cover/<id>/`), never code here.
- **A new kind of trigger:** a `CoverTrigger.When` row and its firing in `cover.gd`'s step.

## Example to copy

The game's kinds are content (content/cover/README.md); the tests' own grass is `tests/core/fixtures/cover_content/cover/test_grass/test_grass.tres`. A kind's test plays its states through this area with `tests/gameplay/cover/cover_kit.gd`.

## Validate

```sh
tools/ptest.sh 8 'test_cover|test_floor|test_ai_cover|test_snapshot_game|test_content_determinism|test_room_life'
```

Tests: `tests/gameplay/cover/` (`test_cover_rooms.gd`, `test_cover_biome.gd`, ...). Cost, not in the build: `godot --headless --path . --script res://tests/benchmark/cover_cost.gd`.

History and reasons: [docs/history/gameplay-cover-README.md](../../docs/history/gameplay-cover-README.md).
