class_name RoomGrid
extends RefCounted
## The grid of the room's cells (WALL_CELL pixels a side, over the projectile manager's bounds): the
## room's walls and the solid shots' stones on them, its mouths (connected biomes CB2, below), its
## holes, and the ground of the bodies that cannot move (their footprints); and what is asked of them:
## where a shot meets a wall (`wall_hit`, `clip_to_walls`, `line_clear`), what is in sight (`sight_clear`), where a
## body slides (`slide_body`), stands (`circle_blocked`, `nearest_ground`) or walks (`ground_clear`,
## `walk_clear`, `clear_run`), and where it would fall (`is_hole`, `touches_hole`). The projectile
## manager's (hit batch B1, docs/milestones/hit-batch.md): it sizes the grid with its bounds
## (`size_to`), lays the walls and holes of a room as Flow hands them (`set_walls`, `add_wall_body`,
## `add_hole_body`, `set_holes_outside`; a biome's pieces as `BiomeWorld` lays them: `add_wall`,
## `add_hole`, `cut`, `add_mouth`, `wall_outside`), and marks its solid shots' cells (`lay_solid`,
## `mark_cells`). The game asks the grid itself, through `grid()` (hit batch B2); the manager's
## one-line forwards of the same names are kept for the tests.
##
## **A mouth** (connected biomes CB2, docs/milestones/connected-biomes.md, "Cells"): the doorway
## where a bridge meets a room, MOUTH_CELL in the wall grid. It is a wall to shots (`wall_hit`, and
## the native hit pass, which reads any byte but 0 as a wall), to a body not driven by a wizard and
## to whatever stands, lands or runs up (`circle_blocked`, `clear_run`) and to an AI's line of fire
## (`line_clear`: a shot ends there); it is open to a wizard's walk (`slide_body`'s
## `through_mouths`) and to sight (`sight_clear`).
##
## **Places and seals** (connected biomes CB3, "Room life"): a biome's rooms and bridges are its
## places (`add_place`, by number: the rooms first, then the bridges, as `BiomeWorld` lays them), so
## what stands or flies anywhere knows which place it is in (`place_at`; -1 outside them all, and
## everywhere in a world with none: a row run's room). A place may be sealed (`set_sealed`: a fight
## under way in a room, Flow's state, told here again after a restore): nothing leaves a sealed place,
## a wizard's walk neither (`Actor.passes_mouths`), nor a movement spell, a swap or a portal
## (`may_cross`); from outside, a wizard still walks in (the seal is one way). A place is awake or
## asleep as Flow's room life says (`set_awake`, told each tick and again after a restore), for the
## areas that step a place's own things only while it is awake (the cover, connected biomes CB3b). A move across a mouth
## goes along a way a body could walk (`walk_way_clear`: no wall but mouths on its segment).
##
## **The room's layers are not state** (connected biomes CB2, "The wall grid"): a biome-wide grid
## would put megabytes into every hash and snapshot. The walls, mouths and holes are laid from the
## room or the biome map, which are state, by whoever lays them (Flow, `BiomeWorld`), and laid again
## by them after a snapshot where the place differs; so they are DERIVED, with the grids worked out
## from the state (the walking grid, the footprints' counts). What changes in play is state: each
## footprint (`set_footprint`) and each solid shot's cells (the manager's `Solid.cells`). After a
## restore `rebuild_derived` takes the solid shots' counts out of the wall grid and lays the
## footprints again, and the manager lays its solid shots' cells back (`relay_solid`). The native
## hit pass reads its wall cells (`ShotKernel`, `GRID_FIELDS`), and `WallSlide` is handed them for a
## body's move.

const ActorsScript := preload("res://core/actors/actors.gd")

const ACTORS: int = ActorsScript.ACTORS
## The cell size in pixels. Walls are rounded out to whole cells, so they are exact when their
## edges are multiples of it (room tiles are 32 px).
const WALL_CELL: float = 8.0
## How many rings of cells `nearest_ground` looks out (12 cells: 96 px).
const NEAREST_GROUND_RINGS: int = 12
## A room wall's mark in the wall grid.
const ROOM_CELL: int = 128
## A mouth's mark in the wall grid (connected biomes CB2): a wall to shots and to bodies no wizard
## drives, open to a wizard's walk and to sight.
const MOUTH_CELL: int = 64
## The bits below the two marks count the solid shots on a cell, up to this many.
const SOLID_MOST: int = 63
## The bits a wizard's walk and sight see as walls: all but the mouth's.
const PAST_MOUTHS: int = 255 & ~MOUTH_CELL

## `walk_body`'s handing of the grid to the native kernel (sim-native SN1): what the grid has laid.
const WALK_WALLS: int = 1
const WALK_FOOTPRINTS: int = 2
const WALK_HOLES: int = 4
## `walk_body`'s answer (its z): the body's end is over a hole (`is_hole`), or, not over one, its
## circle of `reach` there touches a hole (`touches_hole`).
const WALKED_OVER_HOLE: int = 1
const WALKED_NEAR_HOLE: int = 2

## Not state: the room's layers (its bounds, walls, mouths and holes), laid from the room or the biome
## map by whoever lays them, and the grids worked out from the state (the footprints' counts, the
## walking grid), set up again in `rebuild_derived` (see the class doc).
## The places, their seals and their sleep too (`add_place`, `set_sealed`, `set_awake`): laid from
## the biome map and Flow's room state by whoever lays them.
const DERIVED: Array[StringName] = [&"_bounds", &"_wall_w", &"_wall_h", &"_wall_cells", &"_has_walls", &"_has_mouths", &"_ground_cells", &"_footprint_missed", &"_hole_cells", &"_has_holes", &"_walk_cells", &"_place_rects", &"_sealed", &"_asleep", &"_place_w", &"_place_h", &"_place_cells", &"_place_over", &"_place_mixed", &"_place_touched", &"_place_whole", &"_whole_due"]
## What `place_at` answers outside every place (and everywhere in a world with none).
const NO_PLACE: int = -1
## The side of a cell of the places' lookup (`place_at`), in pixels: a biome's pieces stand on the
## 32 px grid (`PieceShape.GRID`), so nearly every cell lies in one place.
const PLACE_CELL: float = 32.0
## `whole_places`' code for a square whose points `place_at` must be asked about one by one.
const WHOLE_ASK: int = 255

## The area the grid covers: the projectile manager's bounds (`size_to`).
var _bounds: Rect2 = Rect2(-1024.0, -1024.0, 2048.0, 2048.0)
## The wall grid over the bounds: one byte per WALL_CELL cell, 0 for open: ROOM_CELL for a room
## wall, plus one for every solid shot lying on it (`set_solid`).
var _wall_w: int = 1
var _wall_h: int = 1
var _wall_cells: PackedByteArray = PackedByteArray()
var _has_walls: bool = false
## True while a mouth lies in the wall grid (`add_mouth`).
var _has_mouths: bool = false
## The ground (`set_footprint`): per wall cell, how many footprints lie on it; per actor, its
## footprint's centre and half its size (a circle: its radius twice, and `_footprint_round` 1;
## nothing laid: no size); how many are laid (the walk asks it first); and the cells a footprint
## could not count when it was laid (255 already on them), by actor, so it never takes them out
## either and the counts stay exact (empty but on a crowded cell).
var _ground_cells: PackedByteArray = PackedByteArray()
var _footprint_at: PackedVector2Array = PackedVector2Array()
var _footprint_half: PackedVector2Array = PackedVector2Array()
var _footprint_round: PackedByteArray = PackedByteArray()
var _footprints_laid: int = 0
var _footprint_missed: Dictionary = {}
## The holes (`set_holes`, hub rework HR-H1: a room's `RoomBase.HOLE_LAYER` bodies): per wall cell, 1
## where the room has a hole (a wall over one wins: walking and every move stop at the wall, and
## `is_hole` says no); whether there are any. And the grid a walk slides on (`slide_body`): per cell,
## 1 where there is ground (`_ground_cells`) or a hole, kept up to date wherever either changes, so
## the native kernel is handed one grid of each and stays as it is. All state, as the wall and
## ground grids are (Flow lays nothing again when a snapshot is restored into the room it is in).
var _hole_cells: PackedByteArray = PackedByteArray()
var _has_holes: bool = false
var _walk_cells: PackedByteArray = PackedByteArray()
## The places (`add_place`): each one's world rectangle, by number, and 1 where it is sealed.
var _place_rects: Array[Rect2] = []
var _sealed: PackedByteArray = PackedByteArray()
## 1 where a place sleeps (Flow's room life, `set_awake`).
var _asleep: PackedByteArray = PackedByteArray()
## The places by PLACE_CELL square over the bounds (its middle's place, plus one; 0 for none), so
## `place_at` asks one cell (a body's move, every shot of a tick) and only checks that place.
var _place_w: int = 0
var _place_h: int = 0
var _place_cells: PackedByteArray = PackedByteArray()
## 1 for a place that wins where it overlaps another (`add_place`'s `over`: a bridge over a room's
## lip, connected biomes CB8), and 1 for a PLACE_CELL square such a place reaches into at all (there
## `place_at` asks those places first).
var _place_over: PackedByteArray = PackedByteArray()
var _place_mixed: PackedByteArray = PackedByteArray()
## 1 for a PLACE_CELL square any place reaches into at all: a point in a square no place reaches is in
## no place, answered at once (a shot over the void between the rooms, every tick; the performance
## pass, 2026-11-20: it walked every place twice).
var _place_touched: PackedByteArray = PackedByteArray()
## By PLACE_CELL square, what `place_at` answers for every point in it (`whole_places`): 0 no place,
## a place plus one (places 0 to 253; a later one is always asked) when the square lies wholly in the place `place_at` finds there, or
## WHOLE_ASK when its points may differ; worked out when first asked after the places changed.
var _place_whole: PackedByteArray = PackedByteArray()
var _whole_due: bool = true

func _init() -> void:
	_footprint_at.resize(ACTORS)
	_footprint_half.resize(ACTORS)
	_footprint_round.resize(ACTORS)
	size_to(_bounds)


## The grid over `rect` (the manager's `set_bounds`): every wall and hole gone; the footprints laid
## again in the new grid (they keep their place in the world).
func size_to(rect: Rect2) -> void:
	_bounds = rect
	_wall_w = maxi(ceili(rect.size.x / WALL_CELL), 1)
	_wall_h = maxi(ceili(rect.size.y / WALL_CELL), 1)
	_wall_cells.resize(_wall_w * _wall_h)
	_hole_cells.resize(_wall_w * _wall_h)
	_hole_cells.fill(0)
	_has_holes = false
	_walk_cells.resize(_wall_w * _wall_h)
	clear_places()
	clear_walls()
	_ground_cells.resize(_wall_w * _wall_h)
	_ground_cells.fill(0)
	_walk_cells.fill(0)
	_footprint_missed.clear()
	if _footprints_laid > 0:
		for actor in ACTORS:
			if _footprint_laid(actor):
				_lay_footprint(actor)


## Every wall (and every solid shot's stone) and every hole gone: a room's holes are laid with its
## walls (`set_holes`). The manager forgets which cells its solid shots lay on (they lay themselves
## again at their next step).
func clear_walls() -> void:
	_wall_cells.fill(0)
	_has_walls = false
	_has_mouths = false
	clear_places()
	_drop_holes()


## After a snapshot was restored (core/sim/README.md, "Snapshots"): the grids worked out from the
## state set up again. The solid shots' counts are taken out of the wall grid (the manager lays its
## solid shots' cells back after, `relay_solid`), and the footprints' ground and the walking grid are
## laid again from the footprints. The room's layers are the restored world's own, laid by whoever
## lays the room (the same room: as they were).
func rebuild_derived() -> void:
	if _wall_cells.size() != _wall_w * _wall_h:
		size_to(_bounds)
	var marks: int = ROOM_CELL | MOUTH_CELL
	for cell in _wall_cells.size():
		_wall_cells[cell] &= marks
	_ground_cells.fill(0)
	_footprint_missed.clear()
	for cell in _walk_cells.size():
		_walk_cells[cell] = _hole_cells[cell]
	for actor in ACTORS:
		if _footprint_laid(actor):
			_lay_footprint(actor)


## Lay a solid shot's `cells` back after a restore (`rebuild_derived`): one more on each. Cells this
## grid does not have (a world still sized for another room, which whoever lays it sizes again and
## relays: `BiomeWorld`) are left out.
func relay_solid(cells: PackedInt32Array) -> void:
	if cells.is_empty():
		return
	var size: int = _wall_cells.size()
	for cell in cells:
		if cell >= 0 and cell < size:
			_wall_cells[cell] += 1
	_has_walls = true


## True while anything lies in the wall grid (a room wall, a solid shot's stone).
func has_walls() -> bool:
	return _has_walls


## A solid shot's stone from `a` to `b`, `reach` pixels round the segment, laid on every cell whose
## centre is within it and not already full of stones: each one counted and appended to `cells`, which
## is returned (packed arrays are copied when handed over: the caller keeps what comes back).
func lay_solid(a: Vector2, b: Vector2, reach: float, cells: PackedInt32Array) -> PackedInt32Array:
	var low: Vector2 = a.min(b) - Vector2(reach, reach) - _bounds.position
	var high: Vector2 = a.max(b) + Vector2(reach, reach) - _bounds.position
	for y in range(maxi(floori(low.y / WALL_CELL), 0), mini(ceili(high.y / WALL_CELL), _wall_h)):
		for x in range(maxi(floori(low.x / WALL_CELL), 0), mini(ceili(high.x / WALL_CELL), _wall_w)):
			var centre: Vector2 = _bounds.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * WALL_CELL
			if Geometry2D.get_closest_point_to_segment(centre, a, b).distance_squared_to(centre) > reach * reach:
				continue
			var cell: int = y * _wall_w + x
			if (_wall_cells[cell] & SOLID_MOST) < SOLID_MOST:
				_wall_cells[cell] += 1
				cells.append(cell)
	_has_walls = _has_walls or not cells.is_empty()
	return cells


## Add `by` (1 or -1) to the count of every cell in `cells` (a solid shot's stone).
func mark_cells(cells: PackedInt32Array, by: int) -> void:
	for cell in cells:
		_wall_cells[cell] += by


## Make these world rectangles holes (hub rework HR-H1, docs/milestones/hub-rework.md, "Holes"),
## replacing any set before: the cells whose any part they cover, as a wall's. A walk stops at a
## hole's lip (`slide_body`); a move done to a body or a dash crosses it (`slide_body`'s `crossing`);
## shots, rays, sight and the walls' checks never see it. Parts outside the bounds are ignored.
## Call it after `set_walls` or `clear_walls`, which remove the holes.
func set_holes(rects: Array[Rect2]) -> void:
	_drop_holes()
	for rect in rects:
		add_hole(rect)


## Take every hole out: the walking grid is the ground alone again.
func _drop_holes() -> void:
	if not _has_holes:
		return
	_hole_cells.fill(0)
	_has_holes = false
	for cell in _walk_cells.size():
		_walk_cells[cell] = 1 if _ground_cells[cell] != 0 else 0


## The world rectangle `rect` a hole (parts outside the grid ignored).
func add_hole(rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var x0: int = maxi(floori((rect.position.x - _bounds.position.x) / WALL_CELL), 0)
	var y0: int = maxi(floori((rect.position.y - _bounds.position.y) / WALL_CELL), 0)
	var x1: int = mini(ceili((rect.end.x - _bounds.position.x) / WALL_CELL), _wall_w)
	var y1: int = mini(ceili((rect.end.y - _bounds.position.y) / WALL_CELL), _wall_h)
	for y in range(y0, y1):
		for x in range(x0, x1):
			_hole_cells[y * _wall_w + x] = 1
			_walk_cells[y * _wall_w + x] = 1
			_has_holes = true


## Make every cell of the grid whose middle lies outside `room` a hole, in a room with holes (hub
## rework HR-H2, docs/milestones/hub-rework.md, question 9: outside the room is the void, so a long
## dash off the edge falls). Nothing in a room with no holes. Flow calls it after laying the room's
## holes; the margin round the room the bounds keep for shots is the void too.
func set_holes_outside(room: Rect2) -> void:
	if not _has_holes:
		return
	for cy in _wall_h:
		for cx in _wall_w:
			var middle: Vector2 = _bounds.position + (Vector2(cx, cy) + Vector2(0.5, 0.5)) * WALL_CELL
			if not room.has_point(middle):
				_hole_cells[cy * _wall_w + cx] = 1
				_walk_cells[cy * _wall_w + cx] = 1


## True when the room has a hole (`set_holes`) at `point` that no wall covers (a wall over a hole
## wins: a Wall card's stones over a crack are a wall while they stand). Outside the grid: a hole in
## a room with holes (question 9: the void goes on), none in a room with none.
func is_hole(point: Vector2) -> bool:
	if not _has_holes:
		return false
	var cx: int = floori((point.x - _bounds.position.x) / WALL_CELL)
	var cy: int = floori((point.y - _bounds.position.y) / WALL_CELL)
	if cx < 0 or cx >= _wall_w or cy < 0 or cy >= _wall_h:
		return true
	var cell: int = cy * _wall_w + cx
	return _hole_cells[cell] != 0 and _wall_cells[cell] == 0


## True when a circle of `radius` at `center` reaches over a hole cell no wall covers (`is_hole`): it
## overlaps the cell, not only touches it, as the walk's slide finds an overlap (`WallSlide`).
func touches_hole(center: Vector2, radius: float) -> bool:
	if not _has_holes:
		return false
	var r: float = maxf(radius, 0.0)
	var x0: int = maxi(floori((center.x - r - _bounds.position.x) / WALL_CELL), 0)
	var x1: int = mini(floori((center.x + r - _bounds.position.x) / WALL_CELL), _wall_w - 1)
	var y0: int = maxi(floori((center.y - r - _bounds.position.y) / WALL_CELL), 0)
	var y1: int = mini(floori((center.y + r - _bounds.position.y) / WALL_CELL), _wall_h - 1)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var cell: int = cy * _wall_w + cx
			if _hole_cells[cell] == 0 or _wall_cells[cell] != 0:
				continue
			var low: Vector2 = _bounds.position + Vector2(cx, cy) * WALL_CELL
			if center.distance_squared_to(center.clamp(low, low + Vector2(WALL_CELL, WALL_CELL))) < r * r:
				return true
	return false


## True while the room has holes (`set_holes`): a body's move is then slid in two parts
## (`Actor.move`).
func has_holes() -> bool:
	return _has_holes


## The world rectangle `rect` a wall (parts outside the grid ignored).
func add_wall(rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var x0: int = maxi(floori((rect.position.x - _bounds.position.x) / WALL_CELL), 0)
	var y0: int = maxi(floori((rect.position.y - _bounds.position.y) / WALL_CELL), 0)
	var x1: int = mini(ceili((rect.end.x - _bounds.position.x) / WALL_CELL), _wall_w)
	var y1: int = mini(ceili((rect.end.y - _bounds.position.y) / WALL_CELL), _wall_h)
	for y in range(y0, y1):
		for x in range(x0, x1):
			_wall_cells[y * _wall_w + x] |= ROOM_CELL
			_has_walls = true


## The world rectangle `rect` a mouth (connected biomes CB2; parts outside the grid ignored): a wall
## to shots and to bodies no wizard drives, open to a wizard's walk and to sight (see the class doc).
func add_mouth(rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var x0: int = maxi(floori((rect.position.x - _bounds.position.x) / WALL_CELL), 0)
	var y0: int = maxi(floori((rect.position.y - _bounds.position.y) / WALL_CELL), 0)
	var x1: int = mini(ceili((rect.end.x - _bounds.position.x) / WALL_CELL), _wall_w)
	var y1: int = mini(ceili((rect.end.y - _bounds.position.y) / WALL_CELL), _wall_h)
	for y in range(y0, y1):
		for x in range(x0, x1):
			# A cell that is a wall already stays one (no mouth): a gather door opened
			# (`shut_mouth`) never opens a wall.
			if (_wall_cells[y * _wall_w + x] & ROOM_CELL) != 0:
				continue
			_wall_cells[y * _wall_w + x] |= MOUTH_CELL
			_has_walls = true
			_has_mouths = true


## Shut the mouth cells in the world rectangle `rect`, or open them again (connected biomes CB7: a
## gather door, Flow's state, told here again after a restore). A shut mouth is a room wall as well
## (ROOM_CELL over its MOUTH_CELL): nothing walks, flies or is moved through it, a wizard neither.
## Only cells that are mouths change; parts outside the grid are ignored. The bodies' move and the
## shots read the same bytes, so the native kernels need nothing of it.
func shut_mouth(rect: Rect2, shut: bool) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var x0: int = maxi(floori((rect.position.x - _bounds.position.x) / WALL_CELL), 0)
	var y0: int = maxi(floori((rect.position.y - _bounds.position.y) / WALL_CELL), 0)
	var x1: int = mini(ceili((rect.end.x - _bounds.position.x) / WALL_CELL), _wall_w)
	var y1: int = mini(ceili((rect.end.y - _bounds.position.y) / WALL_CELL), _wall_h)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var cell: int = y * _wall_w + x
			if (_wall_cells[cell] & MOUTH_CELL) == 0:
				continue
			if shut:
				_wall_cells[cell] |= ROOM_CELL
			else:
				_wall_cells[cell] &= ~ROOM_CELL


## True when the cell at `point` is a shut mouth (`shut_mouth`).
func is_shut_mouth(point: Vector2) -> bool:
	return (cell_at(point) & (MOUTH_CELL | ROOM_CELL)) == (MOUTH_CELL | ROOM_CELL)


## True while a mouth lies in the grid (`add_mouth`).
func has_mouths() -> bool:
	return _has_mouths


## True when the cell at `point` is a mouth (`add_mouth`; outside the grid: no).
func is_mouth(point: Vector2) -> bool:
	return (cell_at(point) & MOUTH_CELL) != 0


## Open the world rectangle `rect` (connected biomes CB2: a room's lip where a bridge meets it, laid
## before the bridge): its room walls, mouths and holes taken out, the cells whose any part it covers
## (parts outside the grid ignored). Solid shots' stones and footprints stay.
func cut(rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var x0: int = maxi(floori((rect.position.x - _bounds.position.x) / WALL_CELL), 0)
	var y0: int = maxi(floori((rect.position.y - _bounds.position.y) / WALL_CELL), 0)
	var x1: int = mini(ceili((rect.end.x - _bounds.position.x) / WALL_CELL), _wall_w)
	var y1: int = mini(ceili((rect.end.y - _bounds.position.y) / WALL_CELL), _wall_h)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var cell: int = y * _wall_w + x
			_wall_cells[cell] &= SOLID_MOST
			_hole_cells[cell] = 0
			_walk_cells[cell] = 1 if _ground_cells[cell] != 0 else 0


## Make every cell of the grid whose middle lies in none of `pieces` (world rectangles) a room wall
## (connected biomes CB2: the dark between a biome's rooms and bridges, where nothing stands or flies).
func wall_outside(pieces: Array[Rect2]) -> void:
	var inside := PackedByteArray()
	inside.resize(_wall_w * _wall_h)
	for piece: Rect2 in pieces:
		# The cells whose middle lies in it: from ceil(low - 0.5) to ceil(high - 0.5), not with it.
		var low: Vector2 = (piece.position - _bounds.position) / WALL_CELL
		var high: Vector2 = (piece.end - _bounds.position) / WALL_CELL
		for cy in range(maxi(ceili(low.y - 0.5), 0), mini(ceili(high.y - 0.5), _wall_h)):
			for cx in range(maxi(ceili(low.x - 0.5), 0), mini(ceili(high.x - 0.5), _wall_w)):
				inside[cy * _wall_w + cx] = 1
	for cell in inside.size():
		if inside[cell] == 0:
			_wall_cells[cell] |= ROOM_CELL
			_has_walls = true


## The room's walls as an image (FORMAT_L8), one pixel a WALL_CELL square from the corner of
## `bounds()`: white for a room wall, black for open (solid shots are left out). Made each call,
## for what is built once a room (Feel's floor marks).
## With `holes`, a hole is white too (hub rework HR-H2: Feel lays no floor mark over a hole).
func wall_image(holes: bool = false) -> Image:
	var bytes := PackedByteArray()
	bytes.resize(_wall_w * _wall_h)
	for i in mini(bytes.size(), _wall_cells.size()):
		bytes[i] = 255 if (_wall_cells[i] & ROOM_CELL) != 0 or (holes and _has_holes and _hole_cells[i] != 0) else 0
	return Image.create_from_data(_wall_w, _wall_h, false, Image.FORMAT_L8, bytes)


## Place number `place` (the next one: places are added in order) is the world rectangle `rect`
## (connected biomes CB3; see the class doc), unsealed. Returns its number. Where places overlap the
## first added holds the point, but one added `over` holds it over every other (a bridge over the lip
## of the room its end meets, past the room's mouth: a body crosses from a bridge into a room only by
## its mouth, connected biomes CB8).
func add_place(rect: Rect2, over: bool = false) -> int:
	_place_rects.append(rect)
	_sealed.append(0)
	_asleep.append(0)
	_place_over.append(1 if over else 0)
	var number: int = _place_rects.size() - 1
	_whole_due = true
	if _place_cells.is_empty():
		_place_w = maxi(ceili(_bounds.size.x / PLACE_CELL), 1)
		_place_h = maxi(ceili(_bounds.size.y / PLACE_CELL), 1)
		_place_cells.resize(_place_w * _place_h)
		_place_cells.fill(0)
		_place_mixed.resize(_place_w * _place_h)
		_place_mixed.fill(0)
		_place_touched.resize(_place_w * _place_h)
		_place_touched.fill(0)
	var tx0: int = maxi(floori((rect.position.x - _bounds.position.x) / PLACE_CELL), 0)
	var ty0: int = maxi(floori((rect.position.y - _bounds.position.y) / PLACE_CELL), 0)
	var tx1: int = mini(ceili((rect.end.x - _bounds.position.x) / PLACE_CELL), _place_w)
	var ty1: int = mini(ceili((rect.end.y - _bounds.position.y) / PLACE_CELL), _place_h)
	for y in range(ty0, ty1):
		for x in range(tx0, tx1):
			_place_touched[y * _place_w + x] = 1
	if over:
		var ox0: int = maxi(floori((rect.position.x - _bounds.position.x) / PLACE_CELL), 0)
		var oy0: int = maxi(floori((rect.position.y - _bounds.position.y) / PLACE_CELL), 0)
		var ox1: int = mini(ceili((rect.end.x - _bounds.position.x) / PLACE_CELL), _place_w)
		var oy1: int = mini(ceili((rect.end.y - _bounds.position.y) / PLACE_CELL), _place_h)
		for y in range(oy0, oy1):
			for x in range(ox0, ox1):
				_place_mixed[y * _place_w + x] = 1
	if number < 255:
		var x0: int = maxi(floori((rect.position.x - _bounds.position.x) / PLACE_CELL), 0)
		var y0: int = maxi(floori((rect.position.y - _bounds.position.y) / PLACE_CELL), 0)
		var x1: int = mini(ceili((rect.end.x - _bounds.position.x) / PLACE_CELL), _place_w)
		var y1: int = mini(ceili((rect.end.y - _bounds.position.y) / PLACE_CELL), _place_h)
		for y in range(y0, y1):
			for x in range(x0, x1):
				var middle: Vector2 = _bounds.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * PLACE_CELL
				if rect.has_point(middle) and _place_cells[y * _place_w + x] == 0:
					_place_cells[y * _place_w + x] = number + 1
	return number


## Every place gone (a row run's room has none): `place_at` is NO_PLACE everywhere.
func clear_places() -> void:
	_place_rects.clear()
	_sealed.resize(0)
	_asleep.resize(0)
	_place_over.resize(0)
	_place_cells.resize(0)
	_place_mixed.resize(0)
	_place_touched.resize(0)
	_place_whole.resize(0)
	_whole_due = true
	_place_w = 0
	_place_h = 0


## How many places are laid (0 in a world with none).
func places() -> int:
	return _place_rects.size()


## The world rectangle of place `place` (empty for none).
func place_rect(place: int) -> Rect2:
	return _place_rects[place] if place >= 0 and place < _place_rects.size() else Rect2()


## The places' squares (PLACE_CELL across, from `place_origin()`, `place_columns()` by
## `place_rows()`), each what `place_at` answers for every point in it: 0 for no place, a place plus
## one, or WHOLE_ASK where `place_at` must be asked (a square an `over` place reaches, one cut by a
## place's edge). For a loop over many points (every shot of a tick, `shot_places`), which asks
## `place_at` only for a WHOLE_ASK square or a point outside them. Read only.
func whole_places() -> PackedByteArray:
	if _whole_due:
		_whole_due = false
		_work_out_whole()
	return _place_whole


func place_origin() -> Vector2:
	return _bounds.position


func place_columns() -> int:
	return _place_w


func place_rows() -> int:
	return _place_h


## `_place_whole` from the places, by `place_at`'s own rules: a square no place reaches is in none;
## one no `over` place reaches, lying wholly in the place its middle is in, is in that place.
func _work_out_whole() -> void:
	_place_whole.resize(_place_cells.size())
	for y in _place_h:
		for x in _place_w:
			var at: int = y * _place_w + x
			if _place_touched[at] == 0:
				_place_whole[at] = 0
				continue
			_place_whole[at] = WHOLE_ASK
			var guess: int = _place_cells[at] - 1
			if _place_mixed[at] != 0 or guess < 0 or guess + 1 >= WHOLE_ASK:
				continue
			# The square's points run from its corner up to (not including) its far edges, in doubles
			# as `place_at` works out the square (a point's square is exact there); the rect's end in
			# single precision, as `Rect2.has_point` works it out.
			var left: float = _bounds.position.x + float(x) * PLACE_CELL
			var top: float = _bounds.position.y + float(y) * PLACE_CELL
			var rect: Rect2 = _place_rects[guess]
			var end: Vector2 = rect.end
			if rect.position.x <= left and rect.position.y <= top and left + PLACE_CELL <= end.x and top + PLACE_CELL <= end.y:
				_place_whole[at] = guess + 1


## Every open body's place made current in one native call (sim-native SN2, Flow's room life: the
## twin is `RoomLife.gd_find_places`): for each of the first `count` actor ids in `ids`, the body whose
## instance id `nodes` keeps there (the actor table's `nodes()`), its `room` set where it stands
## (`place_at`) when it keeps the manager `projectiles` names (an instance id), and `places[n]` its
## `room` after (NO_PLACE for no body; -2, `RoomLife.ASK_GDSCRIPT`, for one of another manager). False,
## and nothing done, without the native module: the caller runs its twin.
func find_places(nodes: PackedInt64Array, ids: PackedInt32Array, count: int, projectiles: int, places: PackedInt32Array) -> bool:
	if not WallSlide.native_on():
		return false
	WallSlide.places(nodes, ids, count, projectiles, _place_rects, _place_cells, _place_over, _place_mixed, _place_touched, _place_w, _place_h, PLACE_CELL, _bounds.position, places)
	return true


## The place `point` is in (the first whose rectangle holds it), or NO_PLACE.
func place_at(point: Vector2) -> int:
	if _place_rects.is_empty():
		return NO_PLACE
	var x: int = floori((point.x - _bounds.position.x) / PLACE_CELL)
	var y: int = floori((point.y - _bounds.position.y) / PLACE_CELL)
	if x >= 0 and x < _place_w and y >= 0 and y < _place_h:
		if _place_mixed[y * _place_w + x] != 0:
			for place in _place_rects.size():
				if _place_over[place] != 0 and _place_rects[place].has_point(point):
					return place
		var guess: int = _place_cells[y * _place_w + x] - 1
		if guess >= 0 and _place_rects[guess].has_point(point):
			return guess
		if _place_touched[y * _place_w + x] == 0:
			return NO_PLACE
	for place in _place_rects.size():
		if _place_over[place] != 0 and _place_rects[place].has_point(point):
			return place
	for place in _place_rects.size():
		if _place_rects[place].has_point(point):
			return place
	return NO_PLACE


## Seal place `place` or open it (Flow's room state: a fight under way; see the class doc).
func set_sealed(place: int, on: bool) -> void:
	if place >= 0 and place < _sealed.size():
		_sealed[place] = 1 if on else 0


## True while place `place` is sealed.
func is_sealed(place: int) -> bool:
	return place >= 0 and place < _sealed.size() and _sealed[place] != 0


## Wake place `place` or put it to sleep (Flow's room life; see the class doc).
func set_awake(place: int, on: bool) -> void:
	if place >= 0 and place < _asleep.size():
		_asleep[place] = 0 if on else 1


## True while place `place` is awake (always for a place out of them all, and in a world with none).
func is_awake(place: int) -> bool:
	return place < 0 or place >= _asleep.size() or _asleep[place] == 0


## True when `point` is in a sealed place: nothing there leaves it.
func sealed_at(point: Vector2) -> bool:
	return is_sealed(place_at(point))


## True when something at `from` may be put at `to` (a teleport, a swap, a portal's exit; connected
## biomes CB3, decision 11): always within one place and in a world with no places; across places
## only out of a place that is not sealed (into a sealed one is allowed: the seal is one way).
func may_cross(from: Vector2, to: Vector2) -> bool:
	if _place_rects.is_empty():
		return true
	var start: int = place_at(from)
	return start == place_at(to) or not is_sealed(start)


## True when the segment from `from` to `to` meets no wall but mouths (a way a body could walk
## across a doorway, decision 11: no wall, no void and no solid shot's stone on it; the ground of
## bodies that cannot move and holes are not minded, as a dash crosses them).
func walk_way_clear(from: Vector2, to: Vector2) -> bool:
	return _way_hit(from, to, PAST_MOUTHS, false, false) < 0.0


## The point where the segment from `from` to `to` first meets a wall that is no mouth (as
## `clip_to_walls`, past doorways: a teleport a wizard drives across a mouth), or `to`.
func clip_past_mouths(from: Vector2, to: Vector2) -> Vector2:
	var t: float = _way_hit(from, to, PAST_MOUTHS, false, false)
	return to if t < 0.0 else from.lerp(to, t)


## The point where the segment from `from` to `to` first meets a wall, or `to` when
## it is clear. If `from` is inside a wall, that is `from`.
func clip_to_walls(from: Vector2, to: Vector2) -> Vector2:
	var t: float = wall_hit(from, to)
	if t < 0.0:
		return to
	return from.lerp(to, t)


## True when nothing in the wall grid lies on the segment from `from` to `to`: no room wall, no
## mouth and no solid shot (a Wall card's, whoever cast it), as a shot along it would find. Walks the
## whole segment, however long (an AI's line of fire, `gameplay/ai/sight.gd`: a shot ends at a mouth,
## so the AI fires through none).
func line_clear(from: Vector2, to: Vector2) -> bool:
	return wall_hit(from, to) < 0.0


## True when nothing but a mouth in the wall grid lies on the segment from `from` to `to` (connected
## biomes CB2, "Cells": sight sees through a doorway, though no shot crosses it): for what only looks
## (a room seen past a mouth, CB3's), never a line of fire. As `line_clear` where there are no mouths.
func sight_clear(from: Vector2, to: Vector2) -> bool:
	if not _has_mouths:
		return wall_hit(from, to) < 0.0
	return _way_hit(from, to, PAST_MOUTHS, false, false) < 0.0


## True when no ground of a body that cannot move (`set_footprint`: a pillar's) lies on the segment
## from `from` to `to`: where a body walking along it would not be held up by one (boss plan OB14,
## decision 36: an AI walks round a blocking prop). Walks the whole segment.
func ground_clear(from: Vector2, to: Vector2) -> bool:
	return _footprints_laid == 0 or _way_hit(from, to, 0, true, false) < 0.0


## True when neither the ground of a body that cannot move nor a hole (`set_holes`) lies on the
## segment from `from` to `to`: where a walk along it would not stop at a pillar or a hole's lip
## (hub rework HR-H1; the AI's walking checks take it in HR-H2, its line of fire never). Walks the
## whole segment.
func walk_clear(from: Vector2, to: Vector2) -> bool:
	return _way_hit(from, to, 0, true, true) < 0.0


## How far (pixels, at most `most`) a walk from `from` along `way` goes before the first cell of a
## wall, a solid shot or a blocking body's ground (`most` when none), cell by cell: how long a move
## along that line could run (boss plan OB14, an AI's run-up). ZERO `way`: 0.
func clear_run(from: Vector2, way: Vector2, most: float) -> float:
	if way == Vector2.ZERO or most <= 0.0:
		return 0.0
	var t: float = _way_hit(from, from + way.normalized() * most, 255, true, false)
	return most if t < 0.0 else t * most


## True when a circle of `radius` at `center` is out of the bounds or touches a wall cell or
## the ground of a body that cannot move (checked at the centre and eight points on its rim, each
## in its 8-pixel cell): where a body could not stand (a teleport checks the body with it). With
## `holes` a hole cell blocks too (hub rework HR-H2: where a body could not stand without falling, the
## AI's run-up, an item laid; a teleport's back-off never minds holes).
func circle_blocked(center: Vector2, radius: float, holes: bool = false) -> bool:
	var with_holes: bool = holes and _has_holes
	var ground: PackedByteArray = _walk_cells if with_holes else _ground_cells
	for n in 9:
		var point: Vector2 = center
		if n > 0:
			point += DMath.from_angle(float(n - 1) * TAU / 8.0) * radius
		if not _bounds.has_point(point):
			return true
		if not _has_walls and _footprints_laid == 0 and not with_holes:
			continue
		var cx: int = floori((point.x - _bounds.position.x) / WALL_CELL)
		var cy: int = floori((point.y - _bounds.position.y) / WALL_CELL)
		if cx >= 0 and cx < _wall_w and cy >= 0 and cy < _wall_h and (_wall_cells[cy * _wall_w + cx] != 0 or ground[cy * _wall_w + cx] != 0):
			return true
	return false


## The nearest place to `point` where a circle of `radius` stands on the ground (hub rework HR-H2):
## `point` itself when the circle is clear there (`circle_blocked` with holes on), else the middle of
## the nearest cell, ring by ring of cells out to NEAREST_GROUND_RINGS, the first clear one in a
## fixed order (the same on every machine); past them, the nearest clear cell of the whole grid (a
## body far over the void); `point` when there is none. What is put back on the ground
## asks it: the boss its jump left over a hole, an add's spot on a ring, an item dropped over one, a
## body back from a fall with no ground of its own yet.
func nearest_ground(point: Vector2, radius: float) -> Vector2:
	if not circle_blocked(point, radius, true):
		return point
	var cx: int = floori((point.x - _bounds.position.x) / WALL_CELL)
	var cy: int = floori((point.y - _bounds.position.y) / WALL_CELL)
	for ring in range(1, NEAREST_GROUND_RINGS + 1):
		var best: Vector2 = Vector2.INF
		var best_distance: float = INF
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var middle: Vector2 = _bounds.position + (Vector2(cx + dx, cy + dy) + Vector2(0.5, 0.5)) * WALL_CELL
				var distance: float = middle.distance_squared_to(point)
				if distance < best_distance and not circle_blocked(middle, radius, true):
					best_distance = distance
					best = middle
		if best != Vector2.INF:
			return best
	# Nothing near (a body far over the void): the nearest clear cell of the whole grid.
	var far: Vector2 = point
	var far_distance: float = INF
	for y in _wall_h:
		for x in _wall_w:
			var middle: Vector2 = _bounds.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * WALL_CELL
			var distance: float = middle.distance_squared_to(point)
			if distance < far_distance and not circle_blocked(middle, radius, true):
				far_distance = distance
				far = middle
	return far


## Where a body (a circle of `radius` at `from`) ends when it moves by `motion`, sliding along the
## walls it meets, the room's and the solid shots', and the ground of the bodies that cannot move
## (online-ready N6: the actors' move, in place of the engine's physics; `WallSlide`), and, unless
## the move is `crossing` (a dash, or a move done to the body: hub rework HR-H1, `Actor.move`), the
## room's holes, whose lip a walk stops at; and, unless it goes `through_mouths` (a body a wizard
## drives: connected biomes CB2, `Actor.passes_mouths`), the mouths. The kernel is handed the walls,
## the bits of them it minds, and one other grid: the ground and the holes merged for a walk
## (`_walk_cells`), the ground alone for a crossing. Mirrored in `walk_body`'s flags and mask and in
## `BodyKernel.walk`'s `slide_on` (native/src/body_kernel.cpp): change them together.
func slide_body(from: Vector2, motion: Vector2, radius: float, crossing: bool = false, through_mouths: bool = false) -> Vector2:
	var holes: bool = _has_holes and not crossing
	if not _has_walls and _footprints_laid == 0 and not holes:
		return from + motion
	var minded: int = PAST_MOUTHS if through_mouths and _has_mouths else 255
	return WallSlide.slide(_wall_cells, _walk_cells if holes else _ground_cells, _wall_w, _wall_h, WALL_CELL, _bounds.position, from, motion, radius, minded)


## A body's whole walk over the grid (sim-native SN1, docs/milestones/sim-native.md): `Actor.move`'s
## grid work in one call. A circle of `radius` at `from` moves by `motion`, of which `crossed` crosses
## holes (the Mover's `crossing` for this move); in a room with holes what crosses is slid first, then
## the walk (`slide_body`; the rules are `gd_walk_body`'s comment), and the end is looked at for holes: the
## answer's x and y are where it ends, its z `WALKED_OVER_HOLE` when that is over a hole, else
## `WALKED_NEAR_HOLE` when a circle of `reach` there touches one, else 0 (always 0 with no holes).
## Runs the native module's `BodyKernel.walk` when it is loaded (`WallSlide.native_on`), else
## `gd_walk_body`, the reference it mirrors (tests/core/test_body_walk.gd compares them to the bit).
func walk_body(from: Vector2, motion: Vector2, crossed: Vector2, radius: float, through_mouths: bool, reach: float) -> Vector3:
	if not _has_walls and _footprints_laid == 0 and not _has_holes:
		# Nothing laid: the whole way, as `slide_body` goes, with no call made.
		var whole: Vector2 = from + motion
		return Vector3(whole.x, whole.y, 0.0)
	if WallSlide.native_on():
		var flags: int = (WALK_WALLS if _has_walls else 0) | (WALK_FOOTPRINTS if _footprints_laid != 0 else 0) | (WALK_HOLES if _has_holes else 0)
		var minded: int = PAST_MOUTHS if through_mouths and _has_mouths else 255
		return WallSlide.walk(_wall_cells, _walk_cells, _ground_cells, _hole_cells, _wall_w, _wall_h, WALL_CELL, _bounds.position, flags, minded, from, motion, crossed, radius, reach)
	return gd_walk_body(from, motion, crossed, radius, through_mouths, reach)


## `walk_body` in GDScript: the reference `BodyKernel.walk` mirrors line by line, and the fallback.
func gd_walk_body(from: Vector2, motion: Vector2, crossed: Vector2, radius: float, through_mouths: bool, reach: float) -> Vector3:
	if not _has_holes:
		var slid: Vector2 = slide_body(from, motion, radius, false, through_mouths)
		return Vector3(slid.x, slid.y, 0.0)
	# In a room with holes (hub rework HR-H1, docs/milestones/hub-rework.md, "Holes" 2 and 3) the move
	# is slid in two parts: first what crosses holes (the Mover's `crossing`: its dashes and what is
	# done to it), then its own walk, which stops at a hole's lip. One slide of the sum could not tell
	# the parts apart. The walk:
	# - from over a hole crosses: it is not pushed back out, so a jump onto a hole (a teleport, a
	#   swap, a portal's exit) or a push into one keeps the body there (falling is HR-H2's);
	# - while something crosses and the circle already reaches over a lip, is slid against the ground
	#   alone, so it never pushes the body back out against the push, and is dropped if it would set
	#   the centre over a hole: it never steps in;
	# - while something crosses and the body does not walk, is not slid (a still walk would push it
	#   back off the lip it is carried over);
	# - otherwise stops at the lip, as at a wall.
	var at: Vector2 = from
	if crossed != Vector2.ZERO:
		at = slide_body(from, crossed, radius, true, through_mouths)
	var walk: Vector2 = motion - crossed
	var to: Vector2 = at
	if walk == Vector2.ZERO and crossed != Vector2.ZERO:
		to = at
	elif is_hole(at):
		to = slide_body(at, walk, radius, true, through_mouths)
	elif crossed != Vector2.ZERO and touches_hole(at, radius):
		var walked: Vector2 = slide_body(at, walk, radius, true, through_mouths)
		to = at if is_hole(walked) else walked
	else:
		to = slide_body(at, walk, radius, false, through_mouths)
	var found: int = 0
	if is_hole(to):
		found = WALKED_OVER_HOLE
	elif touches_hole(to, reach):
		found = WALKED_NEAR_HOLE
	return Vector3(to.x, to.y, float(found))


## The body of the actor `actor` cannot move, and stands on this ground from now on (props W4: its
## `Footprint`), in place of any before: a box `size` across round `centre`, or with no size a
## circle of `radius`; neither: none. The cells laid are those whose centres lie in it. Bodies that
## walk slide along it (`slide_body`) and cannot stand on it (`circle_blocked`); nothing else sees
## it. Laying the same again changes nothing (a body made again from a snapshot). Ids outside the
## table are ignored.
func set_footprint(actor: int, centre: Vector2, size: Vector2, radius: float) -> void:
	if actor < 0 or actor >= ACTORS:
		return
	if _footprint_laid(actor):
		_mark_footprint(actor, -1)
		_footprint_missed.erase(actor)
		_footprints_laid -= 1
	var is_round: bool = size == Vector2.ZERO
	var half: Vector2 = Vector2(radius, radius) if is_round else size.abs() * 0.5
	if not centre.is_finite() or not half.is_finite() or half.x <= 0.0 or half.y <= 0.0:
		half = Vector2.ZERO
	_footprint_at[actor] = centre if half != Vector2.ZERO else Vector2.ZERO
	_footprint_half[actor] = half
	_footprint_round[actor] = 1 if is_round and half != Vector2.ZERO else 0
	if half != Vector2.ZERO:
		_footprints_laid += 1
		_lay_footprint(actor)


## The ground the body of `actor` stands on (`set_footprint`) as the box round it, empty for none.
func footprint_of(actor: int) -> Rect2:
	if not _footprint_laid(actor):
		return Rect2()
	return Rect2(_footprint_at[actor] - _footprint_half[actor], _footprint_half[actor] * 2.0)


## True while the body of `actor` has ground laid.
func _footprint_laid(actor: int) -> bool:
	return actor >= 0 and actor < ACTORS and _footprint_half[actor].x > 0.0


## Lay the footprint of `actor` (newly set, or in a new grid): one more on each of its cells, those
## it could not count kept apart (`_footprint_missed`).
func _lay_footprint(actor: int) -> void:
	var missed := PackedInt32Array()
	for cell in _footprint_cells(actor):
		if _ground_cells[cell] < 255:
			_ground_cells[cell] += 1
			_walk_cells[cell] = 1
		else:
			missed.append(cell)
	if not missed.is_empty():
		_footprint_missed[actor] = missed


## Take the footprint of `actor` out (`by` -1) or put it back (1) on the cells it counted.
func _mark_footprint(actor: int, by: int) -> void:
	var missed: PackedInt32Array = _footprint_missed.get(actor, PackedInt32Array())
	for cell in _footprint_cells(actor):
		if missed.is_empty() or not missed.has(cell):
			_ground_cells[cell] += by
			_walk_cells[cell] = 1 if _ground_cells[cell] != 0 or _hole_cells[cell] != 0 else 0


## The cells of the footprint of `actor` in the grid as it is now: those whose centres lie in its
## box, or in its circle. Made each call (a footprint is laid when a body enters or changes, never
## each step).
func _footprint_cells(actor: int) -> PackedInt32Array:
	var cells := PackedInt32Array()
	var centre: Vector2 = _footprint_at[actor]
	var half: Vector2 = _footprint_half[actor]
	var low: Vector2 = (centre - half - _bounds.position) / WALL_CELL
	var high: Vector2 = (centre + half - _bounds.position) / WALL_CELL
	# A cell's centre is at its index and a half: in the box from ceil(low - 0.5) on, up to (not
	# with) ceil(high - 0.5).
	var is_round: bool = _footprint_round[actor] != 0
	var radius_sq: float = half.x * half.x
	for y in range(maxi(ceili(low.y - 0.5), 0), mini(ceili(high.y - 0.5), _wall_h)):
		for x in range(maxi(ceili(low.x - 0.5), 0), mini(ceili(high.x - 0.5), _wall_w)):
			if is_round and (_bounds.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * WALL_CELL).distance_squared_to(centre) >= radius_sq:
				continue
			cells.append(y * _wall_w + x)
	return cells


## How far along `from`->`to` (0 to 1) the path first enters a solid cell, or -1.0
## when it does not. Walks the cells the path crosses (Amanatides and Woo), at
## most |dx| + |dy| + 1 of them, in cells.
func wall_hit(from: Vector2, to: Vector2) -> float:
	if not _has_walls:
		return -1.0
	var start: Vector2 = (from - _bounds.position) / WALL_CELL
	var delta: Vector2 = (to - from) / WALL_CELL
	var cx: int = floori(start.x)
	var cy: int = floori(start.y)
	var end_x: int = floori(start.x + delta.x)
	var end_y: int = floori(start.y + delta.y)
	if cx == end_x and cy == end_y:
		# The usual step stays in one cell.
		if cx >= 0 and cx < _wall_w and cy >= 0 and cy < _wall_h and _wall_cells[cy * _wall_w + cx] != 0:
			return 0.0
		return -1.0
	if absi(end_x - cx) <= 1 and absi(end_y - cy) <= 1 and mini(cx, end_x) >= 0 and maxi(cx, end_x) < _wall_w and mini(cy, end_y) >= 0 and maxi(cy, end_y) < _wall_h:
		# A short path (a shot's step, a staff from the feet to its tip) only crosses the up to four
		# cells of its corners: when none is solid it meets no wall, without the walk below
		# (performance pass, 2026-10-28).
		var row0: int = cy * _wall_w
		var row1: int = end_y * _wall_w
		if _wall_cells[row0 + cx] == 0 and _wall_cells[row0 + end_x] == 0 and _wall_cells[row1 + cx] == 0 and _wall_cells[row1 + end_x] == 0:
			return -1.0
	var step_x: int = 1 if delta.x > 0.0 else -1
	var step_y: int = 1 if delta.y > 0.0 else -1
	var next_x: float = INF
	var next_y: float = INF
	var per_x: float = INF
	var per_y: float = INF
	if delta.x != 0.0:
		per_x = absf(1.0 / delta.x)
		next_x = (float(cx + (1 if step_x > 0 else 0)) - start.x) / delta.x
	if delta.y != 0.0:
		per_y = absf(1.0 / delta.y)
		next_y = (float(cy + (1 if step_y > 0 else 0)) - start.y) / delta.y
	var t: float = 0.0
	# Every cell the path crosses, however fast the shot (no cap: owner, 2026-11-09): a wall it
	# reaches is hit, and open air is never taken for one.
	var full: int = absi(end_x - cx) + absi(end_y - cy) + 1
	for _n in full:
		if cx >= 0 and cx < _wall_w and cy >= 0 and cy < _wall_h and _wall_cells[cy * _wall_w + cx] != 0:
			return t
		if next_x < next_y:
			t = next_x
			next_x += per_x
			cx += step_x
		else:
			t = next_y
			next_y += per_y
			cy += step_y
		if t > 1.0:
			return -1.0
	return -1.0


## The first cell of the ground (`set_footprint`) when `ground`, of the wall grid's bits in
## `wall_mask` (0: none; 255: every wall, a mouth too; PAST_MOUTHS: sight's) and with `holes` of the
## holes (`set_holes`), on the path from `from` to `to`, as `wall_hit` finds a wall: t in [0, 1] where
## the path enters it, -1 when there is none. Not a shot's (shots hit a blocking body, they do not stop
## on its ground): an AI's walk and sight (`ground_clear`, `walk_clear`, `clear_run`, `sight_clear` past
## a mouth), so it has none of `wall_hit`'s fast paths, and the native kernels have no copy of it.
func _way_hit(from: Vector2, to: Vector2, wall_mask: int, ground: bool, holes: bool) -> float:
	var with_holes: bool = holes and _has_holes
	var walls: bool = wall_mask != 0 and _has_walls
	var with_ground: bool = with_holes or (ground and _footprints_laid > 0)
	if not walls and not with_ground:
		return -1.0
	var grid: PackedByteArray = _walk_cells if with_holes else _ground_cells
	var start: Vector2 = (from - _bounds.position) / WALL_CELL
	var delta: Vector2 = (to - from) / WALL_CELL
	var cx: int = floori(start.x)
	var cy: int = floori(start.y)
	var step_x: int = 1 if delta.x > 0.0 else -1
	var step_y: int = 1 if delta.y > 0.0 else -1
	var next_x: float = INF
	var next_y: float = INF
	var per_x: float = INF
	var per_y: float = INF
	if delta.x != 0.0:
		per_x = absf(1.0 / delta.x)
		next_x = (float(cx + (1 if step_x > 0 else 0)) - start.x) / delta.x
	if delta.y != 0.0:
		per_y = absf(1.0 / delta.y)
		next_y = (float(cy + (1 if step_y > 0 else 0)) - start.y) / delta.y
	var t: float = 0.0
	var full: int = absi(floori(start.x + delta.x) - cx) + absi(floori(start.y + delta.y) - cy) + 1
	for _n in full:
		if cx >= 0 and cx < _wall_w and cy >= 0 and cy < _wall_h:
			var cell: int = cy * _wall_w + cx
			if (with_ground and grid[cell] != 0) or (walls and (_wall_cells[cell] & wall_mask) != 0):
				return t
		if next_x < next_y:
			t = next_x
			next_x += per_x
			cx += step_x
		else:
			t = next_y
			next_y += per_y
			cy += step_y
		if t > 1.0:
			return -1.0
	return -1.0


## The wall grid's byte at `point` (0 outside the grid).
func cell_at(point: Vector2) -> int:
	var x: int = floori((point.x - _bounds.position.x) / WALL_CELL)
	var y: int = floori((point.y - _bounds.position.y) / WALL_CELL)
	return _wall_cells[y * _wall_w + x] if x >= 0 and x < _wall_w and y >= 0 and y < _wall_h else 0
