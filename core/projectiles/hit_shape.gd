class_name HitShape
## A body's hit shape (props, box hurt shapes; docs/milestones/props.md): a box `half` either way of
## its centre, its edge rounded by a radius. A circle is the box of no size (`half` zero), so a
## circle and a box are one shape with one rule: what is within `r` of the shape is within `r` plus
## its radius of its box. A wizard's circle of 8 is `half` zero, radius 8; a bench 48 by 16 is `half`
## (24, 8), radius 0.
##
## Every hit test of the projectile manager (shots, beams, sweeps, homing, the area queries) and of
## Combat (touch) goes through these, and the manager's native twin (`ShotKernel`,
## native/src/shot_kernel.cpp) mirrors them to the bit. For a circle each answer is the same float
## as the circle's own test (`d.abs()` squares as `d`), so a world of circles plays as it did; the
## hot loops still test a circle their own way, a box through these.
##
##     var hit: bool = HitShape.gap_sq(point - centre, half) <= reach * reach
##
## Simulation code: its angles go through `DMath`, every scalar is a double and every vector single
## precision, as the kernel reads them.


## The square of how far `d` (a point less the shape's centre) lies off the box `half`: 0 on or in it.
static func gap_sq(d: Vector2, half: Vector2) -> float:
	return (d.abs() - half).max(Vector2.ZERO).length_squared()


## How far `d` (a point less the shape's centre) lies off the box `half` (`gap_sq`'s root, taken in
## the vector's floats as `Vector2.length` takes it): a circle's is `d.length()`, to the bit.
static func gap(d: Vector2, half: Vector2) -> float:
	return (d.abs() - half).max(Vector2.ZERO).length()


## Where along the path from `from` by `path` (0 to 1; `path_sq` its length squared) it comes nearest
## the box `half` round `centre`: where it goes in when it passes through the box (0 when it starts
## in it), else the nearest of its two ends and the points nearest the box's four corners, the first
## of them on a tie (the nearest pair of a segment and a box always has one of those). For a box of no
## size it is where the path comes nearest the centre, as a circle's test takes it.
static func along(from: Vector2, path: Vector2, path_sq: float, centre: Vector2, half: Vector2) -> float:
	if not (path_sq > 0.0):
		return 0.0
	var a: Vector2 = from - centre
	# The part of the path within the box on both axes, from `enter` to `leave`.
	var enter: float = 0.0
	var leave: float = 1.0
	if path.x == 0.0:
		if absf(a.x) > half.x:
			enter = 2.0
	else:
		var x0: float = (-half.x - a.x) / path.x
		var x1: float = (half.x - a.x) / path.x
		enter = maxf(enter, minf(x0, x1))
		leave = minf(leave, maxf(x0, x1))
	if path.y == 0.0:
		if absf(a.y) > half.y:
			enter = 2.0
	else:
		var y0: float = (-half.y - a.y) / path.y
		var y1: float = (half.y - a.y) / path.y
		enter = maxf(enter, minf(y0, y1))
		leave = minf(leave, maxf(y0, y1))
	if enter <= leave:
		return enter
	var best: float = 0.0
	var best_sq: float = gap_sq(a, half)
	var end_sq: float = gap_sq(a + path, half)
	if end_sq < best_sq:
		best = 1.0
		best_sq = end_sq
	for n in 4:
		var at: Vector2 = corner(half, n)
		var s: float = clampf((at - a).dot(path) / path_sq, 0.0, 1.0)
		var s_sq: float = gap_sq(a + path * s, half)
		if s_sq < best_sq or (s_sq == best_sq and s < best):
			best = s
			best_sq = s_sq
	return best


## The square of how far the line through `d` (a point less the shape's centre) going `way` passes
## off the box `half`: 0 when it crosses it.
static func line_gap_sq(d: Vector2, way: Vector2, half: Vector2) -> float:
	var way_sq: float = way.length_squared()
	if not (way_sq > 0.0):
		return gap_sq(d, half)
	var low: float = INF
	var high: float = -INF
	for n in 4:
		var side: float = (corner(half, n) - d).cross(way)
		low = minf(low, side)
		high = maxf(high, side)
	if low <= 0.0 and high >= 0.0:
		return 0.0
	var off: float = minf(absf(low), absf(high))
	return off * off / way_sq


## How far the shape reaches from its centre going `way` (a unit vector): to where that line leaves
## the box, and its radius on. A circle's is its radius.
static func reach_toward(half: Vector2, radius: float, way: Vector2) -> float:
	if half == Vector2.ZERO:
		return radius
	var out: float = INF
	if way.x != 0.0:
		out = half.x / absf(way.x)
	if way.y != 0.0:
		out = minf(out, half.y / absf(way.y))
	return (out if is_finite(out) else 0.0) + radius


## How far either side of the line from a point to the shape's centre the shape reaches, seen from
## that point `to` off the centre (the centre less the point), in radians: (the least, the most),
## counted clockwise on screen as `angle_difference` counts, in the vector's floats. A box's from its
## outermost corners, each rounded by `radius`; the point must be off the shape (a point on it sees
## it all round). A circle's is its width either way (`asin` of its radius over the distance).
static func sides(to: Vector2, half: Vector2, radius: float) -> Vector2:
	if half == Vector2.ZERO:
		var width: float = DMath.asin(radius / to.length())
		return Vector2(-width, width)
	var centre_angle: float = DMath.angle(to)
	var least: float = INF
	var most: float = -INF
	for n in 4:
		var at: Vector2 = to + corner(half, n)
		var side: float = angle_difference(centre_angle, DMath.angle(at))
		var round_by: float = DMath.asin(radius / at.length()) if radius > 0.0 else 0.0
		least = minf(least, side - round_by)
		most = maxf(most, side + round_by)
	return Vector2(least, most)


## Corner `n` (0 to 3: bit 1 the right, bit 2 the bottom) of the box `half`, from its centre.
static func corner(half: Vector2, n: int) -> Vector2:
	return Vector2(half.x if (n & 1) != 0 else -half.x, half.y if (n & 2) != 0 else -half.y)


## How far the shape reaches from its centre at most (its corner): the radius of the circle round
## it. A circle's is its radius.
static func outer_radius(half: Vector2, radius: float) -> float:
	return half.length() + radius


## How far the shape reaches from its centre along either axis at most: what a search round a point
## is widened by to find it.
static func axis_reach(half: Vector2, radius: float) -> float:
	return maxf(half.x, half.y) + radius
