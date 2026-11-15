class_name CoverTufts
extends RefCounted
## Where a covered cell's tufts stand and how each is drawn (ground cover GC3,
## docs/milestones/ground-cover.md, rule 6): one seed-free scatter, so Feel's batches and the editor's
## preview (`CoverSketch`, `CoverField`, `CoverPreview`) draw the same tufts. A tuft's every pick
## comes from one roll, `CoverLayout.hash4(room, kind, cell, ROLL_TUFT + tuft)`, never `sim.chance`:
## the look moves no roll of the run.
##
## A tuft is drawn from its foot (the bottom middle of its frame), a whole pixel in its cell; the
## tufts of a cell stand in bands from its top down. A kind's tufts are drawn in the order of their
## feet (`draw_key`: from the top of the room down, then from the left), so a tuft lower on the
## floor is drawn over one behind it, across cells too. (Across kinds a batch is drawn whole: one
## kind's batch over another's.)

## How far from a cell's side a foot keeps, in pixels, so a tuft's foot never lies on its neighbour.
const EDGE: int = 1


## The roll of tuft `tuft` of cell `cell` of `layout`, whose kind's key is `kind_key`
## (`CoverLayout.name_hash` of its id).
static func roll(layout: CoverLayout, kind_key: int, cell: int, tuft: int) -> int:
	return CoverLayout.hash4(layout.room_key, kind_key, cell, CoverLayout.ROLL_TUFT + tuft)


## The foot of tuft `tuft` of `per_cell` in cell `cell` of `layout`, from its roll `rolled`, in room
## pixels (whole).
static func foot(layout: CoverLayout, cell: int, tuft: int, per_cell: int, rolled: int) -> Vector2:
	var corner: Vector2 = layout.cell_rect(cell).position
	var across: int = CoverLayout.CELL - 2 * EDGE
	var band: int = maxi(CoverLayout.CELL / maxi(per_cell, 1), 1)
	var x: int = EDGE + (rolled % across)
	var y: int = mini(band * tuft + 1 + ((rolled >> 8) % band), CoverLayout.CELL)
	return corner + Vector2(float(x), float(y))


## The frame of its kind's sheet a tuft of roll `rolled` draws in a state drawing `frames`; -1 when
## the state draws none (cover burnt to bare floor).
static func frame(rolled: int, frames: PackedInt32Array) -> int:
	if frames.is_empty():
		return -1
	return frames[(rolled >> 16) % frames.size()]


## True when a tuft of roll `rolled` is drawn mirrored (left for right).
static func mirrored(rolled: int) -> bool:
	return (rolled >> 24) & 1 == 1


## Where in the wind's sway a tuft of roll `rolled` starts (0-1 of a sway), so the tufts of a field
## do not sway as one: the roll hashed again, so it is not tied to the foot's place.
static func phase(rolled: int) -> float:
	return float(hash(rolled) & 255) / 255.0


## The key a tuft is drawn in order of (smaller first): its foot's row, then its column, then
## `slot`, its place in the cells' order (so ties keep that order). A foot is at most 2^20 pixels
## across and `slot` below 2^20.
static func draw_key(foot: Vector2, slot: int) -> int:
	return (int(foot.y) << 40) | (int(foot.x) << 20) | slot


## The slot a `draw_key` was made with.
static func slot_of(key: int) -> int:
	return key & ((1 << 20) - 1)
