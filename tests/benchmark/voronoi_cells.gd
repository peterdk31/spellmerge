extends RefCounted
## The geometry of a Voronoi split screen (connected biomes CB1, docs/milestones/connected-biomes.md):
## pure functions, nothing drawn. The camera spike (`voronoi_views.gd`) draws one view a cell with
## them; CB6 builds the game's camera, and may take these into Feel.
##
## - **Sites** (`sites`): each wizard's place on the screen, the party's middle at the screen's
##   middle and the wizards spread as they stand (one scale both ways, so the line between two
##   cells is square to the line between their wizards: the bisector), scaled until the farthest
##   is `margin` from the edge. Sites closer than MIN_GAP are pushed apart, so every cell has room.
## - **Cells** (`cells`): the screen cut by the bisectors: a site's cell is every point of the
##   screen nearer it than any other site, a convex polygon (the screen clipped by one half-plane a
##   neighbour). Together they cover the screen, without overlap.
## - **Each view's camera** (`camera_centre`): its wizard is drawn at its cell's middle, so the view
##   leans toward the others (the wizard is off the screen's middle toward the edge its cell owns).

## Sites closer than this (screen pixels) are pushed apart.
const MIN_GAP: float = 1.0
## How far a point may be outside a half-plane and still count as on its line (pixels).
const EPSILON: float = 0.0001


## The screen places of the wizards at `world` (world pixels) on a screen of `screen` pixels: the
## party's middle at the screen's middle, the spread scaled by one factor until the farthest is
## `margin` from an edge. One wizard is at the middle; wizards that stand together are pushed apart,
## each toward its own side (by index), at least MIN_GAP from every other.
static func sites(world: PackedVector2Array, screen: Vector2, margin: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count: int = world.size()
	if count == 0:
		return out
	var middle := Vector2.ZERO
	for point in world:
		middle += point
	middle /= float(count)
	var reach := Vector2.ZERO
	for point in world:
		reach = reach.max((point - middle).abs())
	var room: Vector2 = (screen * 0.5 - Vector2.ONE * margin).max(Vector2.ONE)
	var scale: float = INF
	if reach.x > EPSILON:
		scale = minf(scale, room.x / reach.x)
	if reach.y > EPSILON:
		scale = minf(scale, room.y / reach.y)
	if scale == INF:
		scale = 1.0
	var centre: Vector2 = screen * 0.5
	for point in world:
		out.append(centre + (point - middle) * scale)
	return _apart(out)


## `points` with each one closer than MIN_GAP to an earlier one moved off it, toward its own
## direction (its index's share of a turn), until it is clear of every earlier one.
static func _apart(points: PackedVector2Array) -> PackedVector2Array:
	var count: int = points.size()
	for i in count:
		var away := Vector2.from_angle(TAU * float(i) / float(count)) * MIN_GAP
		var moved: bool = true
		var tries: int = 0
		while moved and tries < count * 4:
			moved = false
			tries += 1
			for j in i:
				if points[i].distance_to(points[j]) < MIN_GAP:
					points[i] += away
					moved = true
	return points


## The cell of each site in `points` on the screen `screen` (a rectangle): the polygon, clockwise
## on screen as Godot's y points down, of every point nearer that site than any other.
static func cells(points: PackedVector2Array, screen: Rect2) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var whole := PackedVector2Array([screen.position, Vector2(screen.end.x, screen.position.y), screen.end, Vector2(screen.position.x, screen.end.y)])
	for i in points.size():
		var cell: PackedVector2Array = whole.duplicate()
		for j in points.size():
			if j == i or cell.is_empty():
				continue
			var normal: Vector2 = points[j] - points[i]
			if normal.length_squared() < EPSILON:
				continue
			cell = clip(cell, (points[i] + points[j]) * 0.5, normal)
		out.append(cell)
	return out


## The convex polygon `polygon` cut to the half-plane on the near side of the line through `point`
## square to `normal` (the side `normal` points away from), the line itself kept (Sutherland-Hodgman).
static func clip(polygon: PackedVector2Array, point: Vector2, normal: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count: int = polygon.size()
	for i in count:
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % count]
		var side_a: float = (a - point).dot(normal)
		var side_b: float = (b - point).dot(normal)
		var a_in: bool = side_a <= EPSILON
		var b_in: bool = side_b <= EPSILON
		if a_in:
			out.append(a)
		if a_in != b_in:
			out.append(a.lerp(b, side_a / (side_a - side_b)))
	return out


## The area of `polygon` (positive either way round).
static func area(polygon: PackedVector2Array) -> float:
	return absf(_twice_signed_area(polygon)) * 0.5


## The middle of `polygon` (its centre of area; its first point when it has none).
static func centroid(polygon: PackedVector2Array) -> Vector2:
	if polygon.is_empty():
		return Vector2.ZERO
	var twice: float = _twice_signed_area(polygon)
	if absf(twice) < EPSILON:
		return polygon[0]
	var sum := Vector2.ZERO
	var count: int = polygon.size()
	for i in count:
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % count]
		sum += (a + b) * a.cross(b)
	return sum / (3.0 * twice)


static func _twice_signed_area(polygon: PackedVector2Array) -> float:
	var twice: float = 0.0
	var count: int = polygon.size()
	for i in count:
		twice += polygon[i].cross(polygon[(i + 1) % count])
	return twice


## Where a view's camera looks (its centre, world pixels) so its wizard at `wizard` (world pixels)
## is drawn at `cell_middle` (screen pixels) on a screen of `screen` pixels at `zoom`.
static func camera_centre(wizard: Vector2, cell_middle: Vector2, screen: Vector2, zoom: float) -> Vector2:
	return wizard - (cell_middle - screen * 0.5) / maxf(zoom, EPSILON)
