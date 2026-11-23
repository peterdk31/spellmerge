extends RefCounted
## Where a biome's laid piece shows the void inside its own rectangle (the owner, 2026-11-23: no
## background of a room's own round its edge, "the real background" there instead): a floating
## room's, a bridge's or a seam's slab does not fill its rectangle, and what lies off it is the
## void, so the void's motes are given off there as between the pieces (`AirMotes.is_void`).
##
## Read from the grid's walls alone, once a world (`lay`): a piece's cells off its slab are its room
## walls joined to the edge of its rectangle through room walls (its invisible wall over the dark;
## a wall standing on the floor, a sarcophagus, is not: the same line `LightBlockers.standing`
## draws). A mouth is never one, open or shut (a gather door stands on the floor). A cell opened
## since (a hidden way found) is asked of the grid as it is now (`shows`).
##
## View only: nothing in the game reads it. Nothing is allocated after `lay`.

const RoomHearingScript := preload("res://gameplay/feel/room_hearing.gd")

const CELL: float = RoomGrid.WALL_CELL

## Feel's room hearing (null: none): a new world laid is told by it (`world`).
var pieces: RoomHearingScript = null
## The grid read (null: none laid).
var _grid: RoomGrid = null
## By place: its rectangle's corner, its cells across, and its cells off its slab (1), row by row.
var _origins: PackedVector2Array = PackedVector2Array()
var _widths: PackedInt32Array = PackedInt32Array()
var _cells: Array[PackedByteArray] = []
var _laid_places: int = -1
var _laid_world: int = -1


## Once a frame, from `grid` (null: no places): the pieces read again for a new biome (a new world,
## a restore's).
func lay(grid: RoomGrid) -> void:
	var places: int = grid.places() if grid != null else 0
	var world: int = pieces.world() if pieces != null else 0
	if places == _laid_places and world == _laid_world and grid == _grid:
		return
	_laid_places = places
	_laid_world = world
	_grid = grid
	_origins.resize(places)
	_widths.resize(places)
	_cells.resize(places)
	for place in places:
		var rect: Rect2 = grid.place_rect(place)
		var across: int = ceili(rect.size.x / CELL)
		_origins[place] = rect.position
		_widths[place] = across
		_cells[place] = _off_slab(grid, rect.position, across, ceili(rect.size.y / CELL))


## Whether world point `at`, in the place `place` (`RoomGrid.place_at`), shows the void: off the
## piece's slab as laid, and a wall still.
func shows(at: Vector2, place: int) -> bool:
	if place < 0 or place >= _cells.size():
		return false
	var cells: PackedByteArray = _cells[place]
	var across: int = _widths[place]
	var x: int = floori((at.x - _origins[place].x) / CELL)
	var y: int = floori((at.y - _origins[place].y) / CELL)
	if across <= 0 or x < 0 or x >= across or y < 0:
		return false
	var cell: int = y * across + x
	return cell < cells.size() and cells[cell] != 0 and _is_edge_wall(_grid.cell_at(at))


## How many cells of `place` lie off its slab (for tests).
func count(place: int) -> int:
	return _cells[place].count(1) if place >= 0 and place < _cells.size() else 0


## A room wall that is no mouth.
static func _is_edge_wall(cell: int) -> bool:
	return (cell & RoomGrid.ROOM_CELL) != 0 and (cell & RoomGrid.MOUTH_CELL) == 0


## The cells (`across` by `down`, from `origin`) that are edge walls joined to the rectangle's edge
## through edge walls (4 ways): 1 each, row by row.
static func _off_slab(grid: RoomGrid, origin: Vector2, across: int, down: int) -> PackedByteArray:
	var found := PackedByteArray()
	found.resize(across * down)
	var reach := PackedInt32Array()
	for y in down:
		for x in across:
			if x == 0 or y == 0 or x == across - 1 or y == down - 1:
				_take(grid, origin, across, x, y, found, reach)
	while not reach.is_empty():
		var cell: int = reach[reach.size() - 1]
		reach.resize(reach.size() - 1)
		var x: int = cell % across
		var y: int = cell / across
		if x > 0:
			_take(grid, origin, across, x - 1, y, found, reach)
		if x < across - 1:
			_take(grid, origin, across, x + 1, y, found, reach)
		if y > 0:
			_take(grid, origin, across, x, y - 1, found, reach)
		if y < down - 1:
			_take(grid, origin, across, x, y + 1, found, reach)
	return found


## Cell (`x`, `y`) marked and queued when it is an edge wall not yet marked.
static func _take(grid: RoomGrid, origin: Vector2, across: int, x: int, y: int, found: PackedByteArray, reach: PackedInt32Array) -> void:
	var cell: int = y * across + x
	if found[cell] != 0 or not _is_edge_wall(grid.cell_at(origin + Vector2(float(x) + 0.5, float(y) + 0.5) * CELL)):
		return
	found[cell] = 1
	reach.append(cell)
