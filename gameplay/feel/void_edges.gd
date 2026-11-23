extends RefCounted
## Where a biome's laid piece shows the void inside its own rectangle (the owner, 2026-11-23: no
## background of a room's own round its edge, "the real background" there instead): a floating
## room's, a bridge's or a seam's slab does not fill its rectangle, and what lies off it is the
## void, so the void's motes are given off there as between the pieces (`AirMotes.is_void`).
##
## Off its slab is where a piece's ground has its edge walls (`PieceShape.laid_ground_walls`: the
## invisible wall over the dark its shape draws no floor under), kept by piece as each is laid
## (`lay_piece`, from `room_built`; a new world forgets the last one's). A wall of the room's own (a
## sarcophagus, a wall of bones against the rim) is none of them, and a ground that draws its walls
## (a tiled hall's wall art) has none. A cell opened since (a bridge's lip cut into a room's edge)
## is asked of the grid as it is now (`shows`).
##
## View only: nothing in the game reads it. Nothing is allocated after a piece is laid.

## By piece number (the grid's place): its ground's edge walls, world pixels.
var _walls: Array[Array] = []


## Piece `number` of the world was laid (`room_built`'s `layout_root`): its edge walls kept. A first
## room (`first`) is a new world.
func lay_piece(number: int, layout_root: Node, first: bool) -> void:
	if first:
		_walls.clear()
	if number < 0:
		return
	while _walls.size() <= number:
		_walls.append([] as Array[Rect2])
	_walls[number] = PieceShape.laid_ground_walls(layout_root)


## Whether world point `at`, in `grid`'s place `place` (`RoomGrid.place_at`), shows the void: off the
## piece's slab as laid, and a room wall there still (no mouth, no cell cut open).
func shows(at: Vector2, place: int, grid: RoomGrid) -> bool:
	if place < 0 or place >= _walls.size():
		return false
	var cell: int = grid.cell_at(at)
	if (cell & RoomGrid.ROOM_CELL) == 0 or (cell & RoomGrid.MOUTH_CELL) != 0:
		return false
	var walls: Array[Rect2] = _walls[place]
	for wall in walls:
		if wall.has_point(at):
			return true
	return false


## How many edge walls piece `place` has (for tests).
func count(place: int) -> int:
	return _walls[place].size() if place >= 0 and place < _walls.size() else 0
