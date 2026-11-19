class_name PieceShape
extends RefCounted
## A template as a biome lays it (connected biomes CB2, docs/milestones/connected-biomes.md, "The
## model"): its size, its walls and holes and its sockets (`RoomSocket`), read from its layout and
## mirrored either way (decision 6), and the rules a biome's pieces keep:
##
## - **The 32 px rule** (decision 2): a template's size and its sockets sit on the GRID, so a piece
##   placed on it never shifts the 8 px wall cells or the 32 px tiles by part of a cell.
## - **Sockets on the lip:** in front of a socket, the LANDING strip inside it as wide as its mouth
##   is open floor; a room's socket has the slab end just past it (a wall or a hole within LANDING
##   out from it: the lip wanders), and a walkway's (`RoomBase.walkway`: a bridge) lies on its own edge, at an end.
## - **Every socket reaches every other** over the piece's open floor, by ways WAY cells wide.
##
## Where a biome joins a socket, the piece is cut open from the socket to its edge (`cut_rect`: a
## room's lip, so the bridge's floor goes on) and a mouth is laid just outside the socket
## (`mouth_rect`, on the bridge's floor: `RoomGrid.MOUTH_CELL`). Plain data, worked out from a layout
## (`of`, `of_room`); the art is not read (the ground is drawn from the mirrored shape at layout,
## connected biomes CB4).

## The placement grid (decision 2), in pixels: template sizes, sockets and places in a biome.
const GRID: float = 32.0
## The wall grid's cell (`RoomGrid.WALL_CELL`).
const CELL: float = 8.0
## How far inside a socket its landing reaches, in pixels: open floor there, across the mouth.
const LANDING: float = 16.0
## How deep a mouth is, out from its socket, in pixels (one wall cell: shots and walks are walked
## cell by cell, so one is enough to stop them).
const MOUTH_DEPTH: float = 8.0
## How many cells across a way between two sockets is at least (`problems`): 16 px, wider than a
## wizard (its footprint's circle is 12 px across).
const WAY: int = 2
## The mirror bits (decision 6): across (x) and up and down (y).
const MIRROR_X: int = 1
const MIRROR_Y: int = 2
## The four mirrorings.
const MIRRORINGS: PackedInt32Array = [0, MIRROR_X, MIRROR_Y, MIRROR_X | MIRROR_Y]

## The meta a laid piece's layout carries for the view, how it is placed (`Vector2i`, x or y 1 where
## mirrored): Feel's `GroundShape.MIRROR_META` (connected biomes CB4), which draws its ground so.
const GROUND_MIRROR_META: StringName = &"ground_mirror"

## The template's id (`RoomBase.id`), whether it is a walkway, and its mirroring.
var id: StringName = &""
var walkway: bool = false
var mirror: int = 0
## Its size from (0, 0), in pixels.
var size: Vector2 = Vector2.ZERO
## Its walls' and holes' rectangles, in its own pixels (`RoomPlaces.wall_rects`, `hole_rects`).
var walls: Array[Rect2] = []
var holes: Array[Rect2] = []
## Its sockets: where each is and the way it faces (`RoomSocket.Facing`), in its own pixels.
var socket_at: PackedVector2Array = PackedVector2Array()
var socket_facing: PackedInt32Array = PackedInt32Array()


## How the piece whose layout is `layout_root` is placed (MIRROR_X, MIRROR_Y, both or 0), from its
## GROUND_MIRROR_META (none: 0, as the template is).
static func mirror_of(layout_root: Node) -> int:
	if layout_root == null or not layout_root.has_meta(GROUND_MIRROR_META):
		return 0
	var flip: Vector2i = layout_root.get_meta(GROUND_MIRROR_META, Vector2i.ZERO) as Vector2i
	return (MIRROR_X if flip.x != 0 else 0) | (MIRROR_Y if flip.y != 0 else 0)


## The walls of a laid piece (`layout_root`, as `room_built` hands it) where the world has them:
## its layout's own (`RoomPlaces.wall_rects`, template pixels) mirrored as it is placed (`mirror_of`)
## and moved to where its node stands. The layout's wall bodies are never moved: they are the
## template's, read so by everyone who mirrors them.
static func laid_walls(layout_root: Node) -> Array[Rect2]:
	return _laid(layout_root, RoomPlaces.wall_rects(layout_root))


## Its holes (`RoomPlaces.hole_rects`) where the world has them, as `laid_walls`.
static func laid_holes(layout_root: Node) -> Array[Rect2]:
	return _laid(layout_root, RoomPlaces.hole_rects(layout_root))


static func _laid(layout_root: Node, rects: Array[Rect2]) -> Array[Rect2]:
	var mirror: int = mirror_of(layout_root)
	var shape: PieceShape = of(layout_root) if mirror != 0 else null
	var piece := layout_root as Node2D
	var at: Vector2 = piece.position if piece != null else Vector2.ZERO
	for i in rects.size():
		var rect: Rect2 = shape.flip_rect(rects[i], mirror) if shape != null else rects[i]
		rects[i] = Rect2(rect.position + at, rect.size)
	return rects


## The shape of `room`'s default layout, mirrored by `mirror`; null for a room with no scene.
static func of_room(room: RoomBase, mirror: int = 0) -> PieceShape:
	if room == null:
		return null
	var layout: Node = room.build()
	if layout == null:
		return null
	var shape: PieceShape = of(layout, room.id, room.walkway)
	layout.free()
	return shape.mirrored(mirror)


## The shape of `layout` (a template's layout, in the tree or not; left as it is), unmirrored.
static func of(layout: Node, template: StringName = &"", is_walkway: bool = false) -> PieceShape:
	var shape := PieceShape.new()
	shape.id = template
	shape.walkway = is_walkway
	var places: RoomPlaces = RoomPlaces.read(layout)
	shape.walls = RoomPlaces.wall_rects(layout)
	shape.holes = RoomPlaces.hole_rects(layout)
	shape.size = _extent(layout, shape.walls, shape.holes)
	shape.socket_at = places.socket_at.duplicate()
	shape.socket_facing = places.socket_facing.duplicate()
	return shape


## The template's own extent from (0, 0): its `Floor` sprite and its walls' and holes' rectangles (a
## room's camera size, `RoomPlaces.size`, is at least a screen; a walkway is smaller).
static func _extent(layout: Node, wall_rects: Array[Rect2], hole_rects: Array[Rect2]) -> Vector2:
	var most := Vector2.ZERO
	var floor_sprite := layout.get_node_or_null("Floor") as Sprite2D
	if floor_sprite != null and floor_sprite.texture != null:
		var extent: Vector2 = floor_sprite.region_rect.size if floor_sprite.region_enabled else floor_sprite.texture.get_size()
		most = most.max(floor_sprite.position + extent)
	for rect: Rect2 in wall_rects + hole_rects:
		most = most.max(rect.end)
	return most


## This shape mirrored by `by` (MIRROR_X, MIRROR_Y, both or 0), on top of its own mirroring: a new
## shape (0: a copy).
func mirrored(by: int) -> PieceShape:
	var out := PieceShape.new()
	out.id = id
	out.walkway = walkway
	out.mirror = mirror ^ by
	out.size = size
	for rect: Rect2 in walls:
		out.walls.append(flip_rect(rect, by))
	for rect: Rect2 in holes:
		out.holes.append(flip_rect(rect, by))
	for i in socket_at.size():
		out.socket_at.append(flip_point(socket_at[i], by))
		out.socket_facing.append(RoomSocket.mirrored(socket_facing[i], by))
	return out


## `rect` (in this shape's pixels) mirrored by `by` within its size: where the mirror image of what
## covers it lies (a wall's box, a sprite's drawn box; a point's rectangle of no size is the point).
func flip_rect(rect: Rect2, by: int) -> Rect2:
	var at: Vector2 = rect.position
	if (by & MIRROR_X) != 0:
		at.x = size.x - rect.end.x
	if (by & MIRROR_Y) != 0:
		at.y = size.y - rect.end.y
	return Rect2(at, rect.size)


## `point` (in this shape's pixels) mirrored by `by` within its size.
func flip_point(point: Vector2, by: int) -> Vector2:
	return Vector2(size.x - point.x if (by & MIRROR_X) != 0 else point.x, size.y - point.y if (by & MIRROR_Y) != 0 else point.y)


## How many sockets it has.
func sockets() -> int:
	return socket_at.size()


## The way socket `i` faces, as a unit vector.
func way_of(i: int) -> Vector2:
	return RoomSocket.way(socket_facing[i])


## The rectangle across socket `i`'s mouth, from `from` to `to` pixels out along the way it faces
## (negative: inside), in its own pixels.
func strip(i: int, from: float, to: float) -> Rect2:
	var at: Vector2 = socket_at[i]
	var way: Vector2 = way_of(i)
	var side: Vector2 = Vector2(absf(way.y), absf(way.x)) * RoomSocket.MOUTH * 0.5
	var a: Vector2 = at + way * from - side
	var b: Vector2 = at + way * to + side
	return Rect2(a.min(b), (b - a).abs())


## What a biome cuts open where socket `i` is joined, in its own pixels: from LANDING inside the
## socket out to its edge (a room's lip and the dark round it: the bridge's floor goes on there). A
## walkway's socket is on its edge: nothing is cut.
func cut_rect(i: int) -> Rect2:
	if walkway:
		return Rect2()
	return strip(i, -LANDING, _out_to_edge(i))


## Where a biome lays the mouth of socket `i` when it is joined, in its own pixels: MOUTH_DEPTH out
## from the socket, across its mouth (a room's: on the bridge's floor past its lip; a walkway's:
## just inside its end).
func mouth_rect(i: int) -> Rect2:
	if walkway:
		return strip(i, -MOUTH_DEPTH, 0.0)
	return strip(i, 0.0, MOUTH_DEPTH)


## How far from socket `i` to the shape's edge along the way it faces, in pixels.
func _out_to_edge(i: int) -> float:
	var at: Vector2 = socket_at[i]
	match socket_facing[i]:
		RoomSocket.Facing.NORTH:
			return at.y
		RoomSocket.Facing.EAST:
			return size.x - at.x
		RoomSocket.Facing.SOUTH:
			return size.y - at.y
	return at.x


## Its rectangle at `place` (a biome's world pixels).
func rect_at(place: Vector2) -> Rect2:
	return Rect2(place, size)


## The shape's cells (CELL squares from its corner, `ceil(size.x / CELL)` across): 1 where a wall or
## a hole covers any part of the cell, as the room grid lays them; 0 for open floor.
func blocked_cells() -> PackedByteArray:
	var w: int = ceili(size.x / CELL)
	var h: int = ceili(size.y / CELL)
	var cells := PackedByteArray()
	cells.resize(w * h)
	for rect: Rect2 in walls + holes:
		var x0: int = maxi(floori(rect.position.x / CELL), 0)
		var y0: int = maxi(floori(rect.position.y / CELL), 0)
		var x1: int = mini(ceili(rect.end.x / CELL), w)
		var y1: int = mini(ceili(rect.end.y / CELL), h)
		for y in range(y0, y1):
			for x in range(x0, x1):
				cells[y * w + x] = 1
	return cells


## What breaks the rules (the class doc), one line each, mirroring named; empty when it keeps them.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	var named: String = "%s (mirrored %d)" % [id, mirror]
	if fmod(size.x, GRID) != 0.0 or fmod(size.y, GRID) != 0.0:
		found.append("%s is %s: a template's size is whole %d px steps; size its room to them." % [named, size, int(GRID)])
	var w: int = ceili(size.x / CELL)
	var h: int = ceili(size.y / CELL)
	var blocked: PackedByteArray = blocked_cells()
	for i in sockets():
		var at: Vector2 = socket_at[i]
		var what: String = "%s's socket %d at %s facing %s" % [named, i, at, RoomSocket.name_of(socket_facing[i])]
		if fmod(at.x, GRID) != 0.0 or fmod(at.y, GRID) != 0.0:
			found.append("%s is off the %d px grid: move it onto it." % [what, int(GRID)])
			continue
		if not Rect2(Vector2.ZERO, size).grow(0.5).has_point(at):
			found.append("%s lies outside the template: move it onto its lip." % what)
			continue
		if _any(blocked, w, h, strip(i, -LANDING, 0.0)):
			found.append("%s has a wall or a hole on its landing (%d px inside it, %d px across): move it onto the lip, in front of open floor." % [what, int(LANDING), int(RoomSocket.MOUTH)])
		if walkway:
			if _out_to_edge(i) != 0.0:
				found.append("%s is not on the walkway's edge: a walkway's sockets are at its ends." % what)
		elif not _any(blocked, w, h, strip(i, 0.0, minf(LANDING, _out_to_edge(i)))):
			found.append("%s has open floor for %d px past it: a socket is on the slab's lip, where the slab ends." % [what, int(LANDING)])
	found.append_array(_reach_problems(blocked, w, h, named))
	return found


## True when a cell `rect` (its own pixels) covers is blocked in `cells` (a wall or a hole).
func _any(cells: PackedByteArray, w: int, h: int, rect: Rect2) -> bool:
	var x0: int = maxi(floori(rect.position.x / CELL), 0)
	var y0: int = maxi(floori(rect.position.y / CELL), 0)
	var x1: int = mini(ceili(rect.end.x / CELL), w)
	var y1: int = mini(ceili(rect.end.y / CELL), h)
	for y in range(y0, y1):
		for x in range(x0, x1):
			if cells[y * w + x] != 0:
				return true
	return false


## Every socket reaches every other over open floor a wizard fits through: a flood from the first
## socket's landing over the cells whose square of WAY cells is open (WAY cells is wider than any
## wizard's body, so a one-cell gap is no way).
func _reach_problems(cells: PackedByteArray, w: int, h: int, named: String) -> PackedStringArray:
	var found := PackedStringArray()
	if sockets() < 2:
		return found
	var blocked := PackedByteArray()
	blocked.resize(w * h)
	for cy in h:
		for cx in w:
			var shut: int = 0
			for dy in WAY:
				for dx in WAY:
					if cx + dx >= w or cy + dy >= h or cells[(cy + dy) * w + cx + dx] != 0:
						shut = 1
			blocked[cy * w + cx] = shut
	var seen := PackedByteArray()
	seen.resize(w * h)
	var queue := PackedInt32Array()
	var first: Rect2 = strip(0, -LANDING, 0.0)
	for cell in _cells_in(first, w, h):
		if blocked[cell] == 0 and seen[cell] == 0:
			seen[cell] = 1
			queue.append(cell)
	var head: int = 0
	while head < queue.size():
		var cell: int = queue[head]
		head += 1
		var cx: int = cell % w
		var cy: int = cell / w
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cx + step.x
			var ny: int = cy + step.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var next: int = ny * w + nx
			if blocked[next] == 0 and seen[next] == 0:
				seen[next] = 1
				queue.append(next)
	for i in range(1, sockets()):
		var reached: bool = false
		for cell in _cells_in(strip(i, -LANDING, 0.0), w, h):
			if seen[cell] != 0:
				reached = true
				break
		if not reached:
			found.append("%s's socket %d cannot be walked to from socket 0: open the floor between them." % [named, i])
	return found


func _cells_in(rect: Rect2, w: int, h: int) -> PackedInt32Array:
	var cells := PackedInt32Array()
	for y in range(maxi(floori(rect.position.y / CELL), 0), mini(ceili(rect.end.y / CELL), h)):
		for x in range(maxi(floori(rect.position.x / CELL), 0), mini(ceili(rect.end.x / CELL), w)):
			cells.append(y * w + x)
	return cells
