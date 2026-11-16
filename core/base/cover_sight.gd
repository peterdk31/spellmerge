class_name CoverSight
extends RefCounted
## Where the floor round a body would harm it (ground cover GC7, docs/milestones/ground-cover.md, rule
## 8): the answer to `cover_danger_looked`, which the cover area (gameplay/cover) fills at once, so an
## area that wants to keep its bodies off burning ground (the AI) asks through the bus and never calls
## the cover area, as `GroundSight` answers `ground_looked`.
##
## A window of the room's cover cells (`CoverLayout.CELL`, 16 px) round the place asked about, at most
## SIDE a side: each cell marked when a body standing in it would be given a status (the state it is
## in has one: burning grass, cobwebs; the same cells the cover area asks a status for). Whether the
## body shrugs it off is Combat's, never asked here. Cells outside the window, and every cell when
## nothing is marked, read as safe.
##
## One is made once per asker and filled again at each look (`clear`, `open`, `mark`), so a look
## allocates nothing. Scratch: whoever holds one lists it as DERIVED (core/sim/README.md); it is filled
## and read within one step.

## The most cells a side the window holds (a reach of up to 64 px round the place asked about).
const SIDE: int = 9
const CELL: int = CoverLayout.CELL

## The window's first cell (its column and row in the room's cover) and its size in cells.
var origin: Vector2i = Vector2i.ZERO
var columns: int = 0
var rows: int = 0
## How many of its cells are marked.
var count: int = 0
## By window cell (row by row, SIDE a row): 1 where a body would be harmed.
var _harms: PackedByteArray = PackedByteArray()


func _init() -> void:
	_harms.resize(SIDE * SIDE)


## Nothing seen: no window, every cell safe.
func clear() -> void:
	if count > 0:
		_harms.fill(0)
	count = 0
	columns = 0
	rows = 0
	origin = Vector2i.ZERO


## The window of the cells within `reach` of `at` (at most SIDE a side, centred on `at`'s cell),
## clipped to a room of `room_columns` by `room_rows` cells; every cell safe. Returns whether any of
## the room is in it.
func open(at: Vector2, reach: float, room_columns: int, room_rows: int) -> bool:
	clear()
	var half: int = SIDE / 2
	var centre: Vector2i = cell_at(at)
	var x0: int = maxi(floori((at.x - reach) / float(CELL)), centre.x - half)
	var x1: int = mini(floori((at.x + reach) / float(CELL)), centre.x + half)
	var y0: int = maxi(floori((at.y - reach) / float(CELL)), centre.y - half)
	var y1: int = mini(floori((at.y + reach) / float(CELL)), centre.y + half)
	x0 = maxi(x0, 0)
	y0 = maxi(y0, 0)
	x1 = mini(x1, room_columns - 1)
	y1 = mini(y1, room_rows - 1)
	if x1 < x0 or y1 < y0:
		return false
	origin = Vector2i(x0, y0)
	columns = x1 - x0 + 1
	rows = y1 - y0 + 1
	return true


## The room cell at column `x`, row `y` (inside the window) would harm a body.
func mark(x: int, y: int) -> void:
	var at: int = (y - origin.y) * SIDE + (x - origin.x)
	if _harms[at] == 0:
		_harms[at] = 1
		count += 1


## True when a body standing at room pixel `at` would be harmed (false outside the window).
func harms(at: Vector2) -> bool:
	return count > 0 and harms_cell(cell_at(at))


## True when the room cell `cell` (its column and row) would harm a body (false outside the window).
func harms_cell(cell: Vector2i) -> bool:
	var x: int = cell.x - origin.x
	var y: int = cell.y - origin.y
	if count == 0 or x < 0 or y < 0 or x >= columns or y >= rows:
		return false
	return _harms[y * SIDE + x] != 0


## True when a cell the segment from `from` to `to` passes through, but the one `from` is in, would
## harm a body: every cell it crosses, walked in order along it (a corner clipped counts), so a body
## walking it steps in no harmful cell. Cells outside the window read as safe.
func harms_along(from: Vector2, to: Vector2) -> bool:
	if count == 0:
		return false
	var cell: Vector2i = cell_at(from)
	var last: Vector2i = cell_at(to)
	var way: Vector2 = to - from
	var step_x: int = 1 if way.x > 0.0 else -1
	var step_y: int = 1 if way.y > 0.0 else -1
	var size: float = float(CELL)
	# How far along (0 to 1) the next column's and row's edge is, and how far one cell is.
	var next_x: float = INF
	var next_y: float = INF
	var delta_x: float = INF
	var delta_y: float = INF
	if way.x != 0.0:
		next_x = (float(cell.x + (1 if step_x > 0 else 0)) * size - from.x) / way.x
		delta_x = size / absf(way.x)
	if way.y != 0.0:
		next_y = (float(cell.y + (1 if step_y > 0 else 0)) * size - from.y) / way.y
		delta_y = size / absf(way.y)
	var left: int = absi(last.x - cell.x) + absi(last.y - cell.y)
	while left > 0:
		if next_x < next_y:
			cell.x += step_x
			next_x += delta_x
		else:
			cell.y += step_y
			next_y += delta_y
		left -= 1
		if harms_cell(cell):
			return true
	return false


## The room cell (column and row) room pixel `at` is in.
static func cell_at(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / float(CELL)), floori(at.y / float(CELL)))


## The middle of the room cell `cell` (column and row), in room pixels.
static func middle(cell: Vector2i) -> Vector2:
	return Vector2((float(cell.x) + 0.5) * float(CELL), (float(cell.y) + 0.5) * float(CELL))
