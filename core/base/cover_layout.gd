class_name CoverLayout
extends RefCounted
## Where a room's ground cover grows (ground cover GC2, docs/milestones/ground-cover.md, rule 1): a
## grid of cells (`CELL` pixels, half a tile), each holding a cover kind or none, worked out from the
## room and never state. `of` is a pure function of the built room's layout, its `RoomBase` and the
## cover kinds there are, so the game (Flow's layout, heard through `room_built`), the editor's preview
## and every machine work out the same cover, and no roll of the run moves.
##
## Two sources, in order:
##
## 1. **The biome's fill** (when the room's `cover_fill` is on): each kind whose `biomes` names the
##    room's `biome`, in id order, fills the open floor by its own numbers: a cell starts a clump with
##    the chance `fill_density`, a clump reaches between half its `clump_size` and all of it (a disc
##    of cells), keeping `wall_gap` cells from a wall and `keep_gap` from a door, a spawn or a
##    placement. A cell keeps the first kind that fills it.
## 2. **The room's fields** (`CoverField`, its data a `CoverPatch`), in the tree's order, each
##    deciding the cells whose middles lie in its rectangle: its kind with the chance of its
##    `density`, else none (a field of no kind clears them).
##
## No source ever covers a cell under a wall or a hole (one a wall's or a hole's rectangle overlaps;
## a hole is blocked as a wall, `BLOCKED_WALL`, hub rework HR-H2) or
## the cell of a door, a spawn or a placement. The chances come from `hash4`, keyed by the room's id,
## the kind's id, the cell and what the roll is for (`ROLL_*`); never `sim.chance`.

## A cell's side, in pixels: half a tile.
const CELL: int = 16
## What a roll of `hash4` is for (its fourth key), so the rolls of one cell never repeat each other.
## Feel's tuft scatter (GC3) takes its own from `ROLL_TUFT` on.
const ROLL_CLUMP: int = 0
const ROLL_REACH: int = 1
const ROLL_FIELD: int = 2
const ROLL_TUFT: int = 16
## A roll's chance is out of this (the low bits of `hash4`).
const ROLL_RANGE: int = 65536

## The room's key in every roll of its cover (`name_hash` of its id; 0 with no room), Feel's tufts'
## and the editor's included (`CoverTufts`).
var room_key: int = 0
## Its size in cells.
var columns: int = 0
var rows: int = 0
## The kinds it was worked out with, in id order; a cell's kind is `kinds[cells[cell] - 1]`.
var kinds: Array[CoverKind] = []
## Each cell's kind, row by row from the top left: 0 for none, else its index in `kinds` plus one.
var cells: PackedByteArray = PackedByteArray()
## Each cell's place in the room: 0 open floor, `BLOCKED_WALL` under a wall, `BLOCKED_POINT` a door's,
## spawn's or placement's.
var blocked: PackedByteArray = PackedByteArray()
var _problems: PackedStringArray = PackedStringArray()

const BLOCKED_WALL: int = 1
const BLOCKED_POINT: int = 2


## The cover of `layout_root`, the layout `room` built (an instance, in the tree or not, its
## placements and zones still in it; left as it is), with the cover kinds `all_kinds` (the registry's
## folder `cover`, in any order). It runs in the editor too: it reads only `room`'s properties (a
## `RoomBase` is not an editor script, so its methods do not run there) and calls the kinds' methods,
## which are editor scripts for that.
static func of(layout_root: Node, room: RoomBase, all_kinds: Array[CoverKind]) -> CoverLayout:
	var made := CoverLayout.new()
	for kind in all_kinds:
		if kind != null and kind.id != &"":
			made.kinds.append(kind)
	made.kinds.sort_custom(func(a: CoverKind, b: CoverKind) -> bool: return String(a.id) < String(b.id))
	var places: RoomPlaces = RoomPlaces.read(layout_root)
	made.columns = ceili(places.size.x / float(CELL))
	made.rows = ceili(places.size.y / float(CELL))
	made.cells.resize(made.columns * made.rows)
	made.blocked.resize(made.columns * made.rows)
	# A hole is blocked as a wall is (hub rework HR-H2): no cover grows over one, and a kind keeps its
	# `wall_gap` from a crack's lip as from a wall.
	var blocking: Array[Rect2] = RoomPlaces.wall_rects(layout_root)
	blocking.append_array(RoomPlaces.hole_rects(layout_root))
	made._block(blocking, places)
	made.room_key = name_hash(room.id) if room != null else 0
	if room != null and room.cover_fill and room.biome != &"":
		made._fill(made.room_key, room.biome)
	made._lay_fields(made.room_key, places)
	return made


## The engine's hash of the four keys (integer code, the same on every machine and in the editor).
static func hash4(a: int, b: int, c: int, d: int) -> int:
	return hash(Vector4i(a, b, c, d))


## A name as a key of `hash4`: the hash of its string.
static func name_hash(name: StringName) -> int:
	return String(name).hash()


## True for a roll of `hash4(a, b, c, d)` under `chance` (0-1).
static func rolls(chance: float, a: int, b: int, c: int, d: int) -> bool:
	return (hash4(a, b, c, d) % ROLL_RANGE) < int(chance * float(ROLL_RANGE))


## The kind of cell `cell` (null for none or a cell outside it).
func kind_at(cell: int) -> CoverKind:
	if cell < 0 or cell >= cells.size() or cells[cell] == 0:
		return null
	return kinds[cells[cell] - 1]


## The cell at room pixel `at`, -1 outside the grid.
func cell_of(at: Vector2) -> int:
	var x: int = floori(at.x / float(CELL))
	var y: int = floori(at.y / float(CELL))
	if x < 0 or y < 0 or x >= columns or y >= rows:
		return -1
	return y * columns + x


## The rectangle of cell `cell`, in room pixels.
func cell_rect(cell: int) -> Rect2:
	return Rect2(Vector2(float((cell % columns) * CELL), float((cell / columns) * CELL)), Vector2(CELL, CELL))


## How many cells hold the kind `kind_id` (any kind: &"").
func count(kind_id: StringName = &"") -> int:
	var found: int = 0
	for cell in cells.size():
		if cells[cell] != 0 and (kind_id == &"" or kinds[cells[cell] - 1].id == kind_id):
			found += 1
	return found


## What is wrong with the room's cover, one line each (empty when nothing is): a field naming a kind
## there is none of.
func problems() -> PackedStringArray:
	return _problems


## Mark the cells under `walls` and those of the doors, spawns and placements of `places`.
func _block(walls: Array[Rect2], places: RoomPlaces) -> void:
	for wall in walls:
		var x0: int = maxi(floori(wall.position.x / float(CELL)), 0)
		var y0: int = maxi(floori(wall.position.y / float(CELL)), 0)
		var x1: int = mini(ceili(wall.end.x / float(CELL)), columns)
		var y1: int = mini(ceili(wall.end.y / float(CELL)), rows)
		for y in range(y0, y1):
			for x in range(x0, x1):
				blocked[y * columns + x] = BLOCKED_WALL
	for list: PackedVector2Array in [places.player_spawns, places.enemy_spawns, places.doors, places.joiner_spawns, places.placed_at]:
		for at in list:
			var cell: int = cell_of(at)
			if cell >= 0 and blocked[cell] == 0:
				blocked[cell] = BLOCKED_POINT


## How far each cell is from the nearest cell that is `what` (Chebyshev, in cells; the room's edge
## counts as a wall's), by two passes.
func _distance_to(what: int) -> PackedInt32Array:
	var far: int = columns + rows
	var distance := PackedInt32Array()
	distance.resize(cells.size())
	for cell in cells.size():
		distance[cell] = 0 if blocked[cell] == what else far
	for y in rows:
		for x in columns:
			var cell: int = y * columns + x
			var best: int = distance[cell]
			if what == BLOCKED_WALL and (x == 0 or y == 0):
				best = mini(best, 1)
			if x > 0:
				best = mini(best, distance[cell - 1] + 1)
			if y > 0:
				best = mini(best, distance[cell - columns] + 1)
				if x > 0:
					best = mini(best, distance[cell - columns - 1] + 1)
				if x < columns - 1:
					best = mini(best, distance[cell - columns + 1] + 1)
			distance[cell] = best
	for y in range(rows - 1, -1, -1):
		for x in range(columns - 1, -1, -1):
			var cell: int = y * columns + x
			var best: int = distance[cell]
			if what == BLOCKED_WALL and (x == columns - 1 or y == rows - 1):
				best = mini(best, 1)
			if x < columns - 1:
				best = mini(best, distance[cell + 1] + 1)
			if y < rows - 1:
				best = mini(best, distance[cell + columns] + 1)
				if x < columns - 1:
					best = mini(best, distance[cell + columns + 1] + 1)
				if x > 0:
					best = mini(best, distance[cell + columns - 1] + 1)
			distance[cell] = best
	return distance


## The biome's fill (rule 1's first source): each kind filling `biome`, in id order, its clumps on the
## open floor it keeps to.
func _fill(room: int, biome: StringName) -> void:
	var from_wall: PackedInt32Array = _distance_to(BLOCKED_WALL)
	var from_point: PackedInt32Array = _distance_to(BLOCKED_POINT)
	for index in kinds.size():
		var kind: CoverKind = kinds[index]
		if not kind.fills(biome) or kind.fill_density <= 0.0:
			continue
		var kind_key: int = name_hash(kind.id)
		var mark: int = index + 1
		for centre in cells.size():
			if not _keeps(kind, centre, from_wall, from_point):
				continue
			if not rolls(kind.fill_density, room, kind_key, centre, ROLL_CLUMP):
				continue
			var most: int = maxi(kind.clump_size, 0)
			var least: int = (most + 1) / 2
			var reach: int = least + (hash4(room, kind_key, centre, ROLL_REACH) % (most - least + 1))
			var cx: int = centre % columns
			var cy: int = centre / columns
			for y in range(maxi(cy - reach, 0), mini(cy + reach + 1, rows)):
				for x in range(maxi(cx - reach, 0), mini(cx + reach + 1, columns)):
					var dx: int = x - cx
					var dy: int = y - cy
					# A disc a little rounder than its reach squared: a reach of 1 is a 3×3 square, 2 a round clump.
					if dx * dx + dy * dy > reach * reach + reach:
						continue
					var cell: int = y * columns + x
					if cells[cell] == 0 and _keeps(kind, cell, from_wall, from_point):
						cells[cell] = mark


## True when `kind`'s fill may cover `cell`: open floor, far enough from a wall and from a door, a
## spawn or a placement.
func _keeps(kind: CoverKind, cell: int, from_wall: PackedInt32Array, from_point: PackedInt32Array) -> bool:
	return blocked[cell] == 0 and from_wall[cell] > kind.wall_gap and from_point[cell] > kind.keep_gap


## The room's fields (rule 1's second source), in the tree's order, over the fill.
func _lay_fields(room: int, places: RoomPlaces) -> void:
	for at in places.zones_of(CoverPatch):
		var patch := places.zone_data[at] as CoverPatch
		var rect: Rect2 = places.zone_rects[at]
		var mark: int = 0
		var kind_key: int = 0
		if patch.kind != &"":
			for index in kinds.size():
				if kinds[index].id == patch.kind:
					mark = index + 1
			if mark == 0:
				_problems.append("a cover field names the kind '%s', which there is none of." % patch.kind)
				continue
			kind_key = name_hash(patch.kind)
		for cell in cells.size():
			if blocked[cell] != 0:
				continue
			if not rect.has_point(cell_rect(cell).get_center()):
				continue
			cells[cell] = mark if mark != 0 and rolls(patch.density, room, kind_key, cell, ROLL_FIELD) else 0
