extends RefCounted
## The geometry of a Voronoi split screen (connected biomes CB1 and CB6,
## docs/milestones/connected-biomes.md): pure functions, nothing drawn. The game's split screen
## (`split_camera.gd`) fills its cells with `fill` (nothing allocated); the camera spike
## (tests/benchmark/voronoi_views.gd) uses the static helpers.
##
## - **Sites** (`sites`): each wizard's place on the screen, the party's middle at the screen's
##   middle and the wizards spread as they stand (one scale both ways, so the line between two
##   cells is square to the line between their wizards: the bisector), scaled until the farthest
##   is `margin` from the edge. Sites closer than MIN_GAP are pushed apart, so every cell has room.
## - **Cells** (`cells`, `fill`): the screen cut by the bisectors: a site's cell is every point of
##   the screen nearer it than any other site, a convex polygon (the screen clipped by one
##   half-plane a neighbour), clockwise on screen. Together they cover the screen, without overlap.
## - **Each view's camera** (`camera_centre`): where a view looks so a wizard is drawn at a point.

const ScreenViewsScript := preload("res://core/display/screen_views.gd")

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


## Scratch corners for `fill` (two, clipped from one into the other).
var _from: PackedVector2Array = PackedVector2Array()
var _into: PackedVector2Array = PackedVector2Array()
## Scratch for a twin's owner's cell (`fill`'s `owner`): both parts' corners, and their hull.
var _hull_in: PackedVector2Array = PackedVector2Array()
var _hull_out: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	_from.resize(ScreenViewsScript.CORNERS_MOST)
	_into.resize(ScreenViewsScript.CORNERS_MOST)
	_hull_in.resize(ScreenViewsScript.CORNERS_MOST * 2)
	_hull_out.resize(ScreenViewsScript.CORNERS_MOST * 2 + 1)


## Fill `views`' cells for its `count` views from their anchors (`views.anchor`, screen pixels,
## at least MIN_GAP apart) on its screen: each the screen cut by the bisector to every other anchor,
## and to `blank` (a site no view owns, the equal split's empty quarter; Vector2.INF: none), whose
## own part of the screen is then no view's, unless view `owner` shows it (the equal split's twin of
## a pair's pane, which the blank's part shows with the pair's picture): that view's cell is then the
## hull of its own part and the blank's (the whole half, once they are settled). Nothing is allocated.
func fill(views: ScreenViewsScript, blank: Vector2 = Vector2.INF, owner: int = -1) -> void:
	var screen: Vector2 = views.screen
	for i in views.count:
		_from[0] = Vector2.ZERO
		_from[1] = Vector2(screen.x, 0.0)
		_from[2] = screen
		_from[3] = Vector2(0.0, screen.y)
		var n: int = 4
		var own: Vector2 = views.anchor[i]
		for j in views.count:
			if j == i or n == 0:
				continue
			var normal: Vector2 = views.anchor[j] - own
			if normal.length_squared() < EPSILON:
				continue
			n = _clip_into((own + views.anchor[j]) * 0.5, normal, n)
		if blank.is_finite() and n > 0 and (blank - own).length_squared() >= EPSILON:
			n = _clip_into((own + blank) * 0.5, blank - own, n)
		if i == owner and blank.is_finite():
			n = _with_blank(views, blank, n)
		for k in n:
			views.set_corner(i, k, _from[k])
		views.set_corners(i, n)


## The first `n` of `_from` joined with the blank's own part of the screen (cut by the bisector to
## every view's anchor): their convex hull, written back into `_from` (at most CORNERS_MOST corners,
## clockwise on screen as the cells are). Returns how many.
func _with_blank(views: ScreenViewsScript, blank: Vector2, n: int) -> int:
	var count: int = 0
	for k in n:
		_hull_in[count] = _from[k]
		count += 1
	var screen: Vector2 = views.screen
	_from[0] = Vector2.ZERO
	_from[1] = Vector2(screen.x, 0.0)
	_from[2] = screen
	_from[3] = Vector2(0.0, screen.y)
	var m: int = 4
	for j in views.count:
		if m == 0:
			break
		var normal: Vector2 = views.anchor[j] - blank
		if normal.length_squared() < EPSILON:
			continue
		m = _clip_into((blank + views.anchor[j]) * 0.5, normal, m)
	for k in m:
		_hull_in[count] = _from[k]
		count += 1
	# Sorted by x then y (insertion: a handful of points), then the monotone chain.
	for a in range(1, count):
		var p: Vector2 = _hull_in[a]
		var b: int = a - 1
		while b >= 0 and (_hull_in[b].x > p.x or (_hull_in[b].x == p.x and _hull_in[b].y > p.y)):
			_hull_in[b + 1] = _hull_in[b]
			b -= 1
		_hull_in[b + 1] = p
	var h: int = 0
	for a in count:
		while h >= 2 and (_hull_out[h - 1] - _hull_out[h - 2]).cross(_hull_in[a] - _hull_out[h - 2]) <= EPSILON:
			h -= 1
		_hull_out[h] = _hull_in[a]
		h += 1
	var lower: int = h + 1
	for a in range(count - 2, -1, -1):
		while h >= lower and (_hull_out[h - 1] - _hull_out[h - 2]).cross(_hull_in[a] - _hull_out[h - 2]) <= EPSILON:
			h -= 1
		_hull_out[h] = _hull_in[a]
		h += 1
	h = mini(h - 1, ScreenViewsScript.CORNERS_MOST)
	for k in h:
		_from[k] = _hull_out[k]
	return maxi(h, 0)


## `clip` on the scratch corners: the first `n` of `_from` cut to the near side of the line through
## `point` square to `normal`, written back into `_from`; the corners kept (at most CORNERS_MOST).
func _clip_into(point: Vector2, normal: Vector2, n: int) -> int:
	var out: int = 0
	for i in n:
		var a: Vector2 = _from[i]
		var b: Vector2 = _from[(i + 1) % n]
		var side_a: float = (a - point).dot(normal)
		var side_b: float = (b - point).dot(normal)
		var a_in: bool = side_a <= EPSILON
		var b_in: bool = side_b <= EPSILON
		if a_in and out < ScreenViewsScript.CORNERS_MOST:
			_into[out] = a
			out += 1
		if a_in != b_in and out < ScreenViewsScript.CORNERS_MOST:
			_into[out] = a.lerp(b, side_a / (side_a - side_b))
			out += 1
	for k in out:
		_from[k] = _into[k]
	return out
