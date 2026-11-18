extends RefCounted
## Where a room's mist lies thick and where it is gone (docs/milestones/atmosphere.md, F): a small
## image of the room, a texel a CELL px square from its corner, worked out once a room from its walls
## and its holes as the layout was built (`RoomPlaces.wall_rects`, `hole_rects`), read by
## `mist.gdshader` with bilinear filtering (RGBA8: filtered on every renderer, WebGL 2 included).
##
## - **red:** how far an open cell is from the room's edge (the void round a floating room's slab or
##   the hub's island, or with no void round it, the nearest wall), over REACH (1 at REACH or further):
##   a low wall standing in the room is no edge (rule 6: thin over the fight). The mist thickens toward
##   the edge within its `edge_reach`.
## - **green:** how far a cell is from the nearest pit (a hole), over REACH. It thickens toward a pit
##   within its `pit_reach`; over the pit itself (0) it lies thickest, pouring in.
## - **blue:** how deep a wall cell lies in its wall, over SPILL (0 on open floor and over pits). The
##   mist spills its `spill` px over a wall's edge, then is gone. The void outside the room's walls
##   (open cells joined to the grid's edge) counts as wall.
##
## Distances are a chamfer's (straight steps 1, diagonal steps 1.414 cells) between cell middles: a
## few px off a true distance, which soft mist does not show. Built once a room: its arrays are made
## then, never a frame.

## The mask's cell (px), and the distances its channels are over (px): RoomMist.REACH_MOST and the
## most a mist spills.
const CELL: float = 8.0
const REACH: float = RoomMist.REACH_MOST
const SPILL: float = 64.0
## The most cells a side (a bigger room is masked by bigger cells, so a mask is never more than this
## squared).
const MOST_CELLS: int = 256
const DIAGONAL: float = 1.41421356


## The mask of a room of `size` (px, from the origin) with `walls` and `holes` (world px): an
## RGBA8 image (see the top), and how many px each of its texels covers (`cell_of` it).
static func build(size: Vector2, walls: Array[Rect2], holes: Array[Rect2]) -> Image:
	var cell: float = cell_of(size)
	var w: int = maxi(ceili(size.x / cell), 1)
	var h: int = maxi(ceili(size.y / cell), 1)
	var wall := PackedByteArray()
	wall.resize(w * h)
	var hole := PackedByteArray()
	hole.resize(w * h)
	_lay(wall, w, h, cell, walls)
	_lay(hole, w, h, cell, holes)
	# A wall wins where both cover a cell (RoomPlaces.hole_rects).
	for i in w * h:
		if wall[i] != 0:
			hole[i] = 0
	var outside: PackedByteArray = _wall_outside(wall, hole, w, h)
	var open := PackedByteArray()
	open.resize(w * h)
	for i in w * h:
		open[i] = 1 if wall[i] == 0 else 0
	# The mist thickens toward the room's edge: the void round it where there is one (a low wall
	# standing in the room, a sarcophagus, is no edge: rule 6, thin over the fight), else every wall.
	var to_wall: PackedFloat32Array = distances(outside if not outside.is_empty() else wall, w, h, true)
	var to_hole: PackedFloat32Array = distances(hole, w, h, false)
	var into_wall: PackedFloat32Array = distances(open, w, h, false)
	var bytes := PackedByteArray()
	bytes.resize(w * h * 4)
	for i in w * h:
		var near_hole: float = to_hole[i] if hole[i] == 0 else 0.0
		bytes[i * 4] = _byte(to_wall[i] * cell / REACH if wall[i] == 0 else 0.0)
		bytes[i * 4 + 1] = _byte(near_hole * cell / REACH)
		bytes[i * 4 + 2] = _byte(into_wall[i] * cell / SPILL if wall[i] != 0 else 0.0)
		bytes[i * 4 + 3] = 255
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)


## How many px a texel of the mask of a room of `size` covers: CELL, or more for a room wider than
## MOST_CELLS of them.
static func cell_of(size: Vector2) -> float:
	var most: float = maxf(size.x, size.y)
	return maxf(CELL, ceilf(most / float(MOST_CELLS)))


## Each cell's distance in cells to the nearest cell set in `marked` (0 on one; `w` x `h`; `edge`: past
## the grid's edge counts as set, else as far away), by two chamfer passes.
static func distances(marked: PackedByteArray, w: int, h: int, edge: bool) -> PackedFloat32Array:
	var far: float = float(w + h) * 2.0
	var out := PackedFloat32Array()
	out.resize(w * h)
	for i in w * h:
		out[i] = 0.0 if marked[i] != 0 else far
	if edge:
		# Past the edge is a wall half a cell beyond the outer cells' middles.
		for y in h:
			for x in w:
				var i: int = y * w + x
				var border: float = float(mini(mini(x, w - 1 - x), mini(y, h - 1 - y))) + 1.0
				out[i] = minf(out[i], border)
	for y in h:
		for x in w:
			var i: int = y * w + x
			var d: float = out[i]
			if d == 0.0:
				continue
			if x > 0:
				d = minf(d, out[i - 1] + 1.0)
			if y > 0:
				d = minf(d, out[i - w] + 1.0)
				if x > 0:
					d = minf(d, out[i - w - 1] + DIAGONAL)
				if x < w - 1:
					d = minf(d, out[i - w + 1] + DIAGONAL)
			out[i] = d
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i: int = y * w + x
			var d: float = out[i]
			if d == 0.0:
				continue
			if x < w - 1:
				d = minf(d, out[i + 1] + 1.0)
			if y < h - 1:
				d = minf(d, out[i + w] + 1.0)
				if x < w - 1:
					d = minf(d, out[i + w + 1] + DIAGONAL)
				if x > 0:
					d = minf(d, out[i + w - 1] + DIAGONAL)
			out[i] = d
	return out


## The void outside a room's walls is wall too: open cells joined to the grid's edge through open
## cells (a floating room's dark round its slab's edge walls, the hub's void round its island) are
## set in `wall`, so no mist lies out over the dark; returned (empty for none). A room whose floor runs
## to its edge with no wall round it (most of its open floor joined to the edge), or that is walled to
## its edge, is left as it is.
static func _wall_outside(wall: PackedByteArray, hole: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var outside := PackedByteArray()
	outside.resize(w * h)
	var queue := PackedInt32Array()
	queue.resize(w * h)
	var count: int = 0
	for i in w * h:
		var x: int = i % w
		var y: int = i / w
		if (x == 0 or y == 0 or x == w - 1 or y == h - 1) and wall[i] == 0 and hole[i] == 0:
			outside[i] = 1
			queue[count] = i
			count += 1
	var at: int = 0
	while at < count:
		var i: int = queue[at]
		at += 1
		var x: int = i % w
		var y: int = i / w
		for next: int in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w if y > 0 else -1, i + w if y < h - 1 else -1]:
			if next >= 0 and outside[next] == 0 and wall[next] == 0 and hole[next] == 0:
				outside[next] = 1
				queue[count] = next
				count += 1
	var open: int = 0
	for i in w * h:
		if wall[i] == 0:
			open += 1
	if count == 0 or count * 10 > open * 9:
		return PackedByteArray()
	for i in w * h:
		if outside[i] != 0:
			wall[i] = 1
	return outside


## Set every cell of `cells` (`w` x `h`, `cell` px) whose middle lies in one of `rects`.
static func _lay(cells: PackedByteArray, w: int, h: int, cell: float, rects: Array[Rect2]) -> void:
	for rect in rects:
		var x0: int = maxi(ceili(rect.position.x / cell - 0.5), 0)
		var y0: int = maxi(ceili(rect.position.y / cell - 0.5), 0)
		var x1: int = mini(ceili(rect.end.x / cell - 0.5), w)
		var y1: int = mini(ceili(rect.end.y / cell - 0.5), h)
		for y in range(y0, y1):
			for x in range(x0, x1):
				cells[y * w + x] = 1


static func _byte(share: float) -> int:
	return clampi(roundi(clampf(share, 0.0, 1.0) * 255.0), 0, 255)
