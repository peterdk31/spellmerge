extends "res://tests/support/suite.gd"
## A body's hit shape (`HitShape`, core/projectiles/hit_shape.gd; props, box hurt shapes): a box
## `half` either way of its centre, rounded by a radius, a circle being the box of no size. For a
## circle every answer is the circle's own sum to the bit, so a world of circles plays as it did;
## for a box: how far a point is off it, where a path comes nearest it (where it goes in, or the
## nearest end or corner), how far a line passes off it, and how far it reaches.
##
## godot --headless --path . --script res://tests/core/test_hit_shape.gd

## A bench: 80 by 16.
const BENCH: Vector2 = Vector2(40.0, 8.0)


func test_a_circle_is_the_circle_s_own_sum_to_the_bit() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var differ: int = 0
	for n in 2000:
		var point := Vector2(rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0))
		var centre := Vector2(rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0))
		if var_to_bytes(HitShape.gap_sq(point - centre, Vector2.ZERO)) != var_to_bytes(point.distance_squared_to(centre)):
			differ += 1
		if var_to_bytes(HitShape.gap(point - centre, Vector2.ZERO)) != var_to_bytes(point.distance_to(centre)):
			differ += 1
		var from := Vector2(rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0))
		var path: Vector2 = point - from
		var path_sq: float = path.length_squared()
		var own: float = clampf((centre - from).dot(path) / path_sq, 0.0, 1.0) if path_sq > 0.0 else 0.0
		if absf(HitShape.along(from, path, path_sq, centre, Vector2.ZERO) - own) > 1e-5:
			differ += 1
	check_equal(differ, 0, "a circle's gap and its root are the same floats as its distance, and where a path comes nearest it is its centre's")
	check_equal(HitShape.reach_toward(Vector2.ZERO, 8.0, Vector2.RIGHT), 8.0, "a circle reaches its radius every way")
	check_equal(HitShape.outer_radius(Vector2.ZERO, 8.0), 8.0, "and at most its radius")
	check_equal(HitShape.axis_reach(Vector2.ZERO, 8.0), 8.0, "along an axis too")


func test_how_far_a_point_is_off_a_box() -> void:
	check_equal(HitShape.gap_sq(Vector2(30.0, -5.0), BENCH), 0.0, "in it: none")
	check_equal(HitShape.gap_sq(Vector2(40.0, 8.0), BENCH), 0.0, "on its corner: none")
	check_equal(HitShape.gap(Vector2(10.0, 20.0), BENCH), 12.0, "above its middle: to its long edge")
	check_equal(HitShape.gap(Vector2(-55.0, 0.0), BENCH), 15.0, "beside it: to its short edge")
	check_equal(HitShape.gap(Vector2(43.0, 12.0), BENCH), 5.0, "past a corner: to the corner")


func test_where_a_path_comes_nearest_a_box() -> void:
	var centre := Vector2(100.0, 50.0)
	# Down through its right end: in where it crosses the top edge, 8 above the centre line.
	check(is_equal_approx(HitShape.along(Vector2(130.0, 0.0), Vector2(0.0, 100.0), 10000.0, centre, BENCH), 0.42), "a path through it: where it goes in")
	check_equal(HitShape.along(Vector2(110.0, 50.0), Vector2(100.0, 0.0), 10000.0, centre, BENCH), 0.0, "one starting in it: its start")
	# Down past its right end, 5 off: nearest beside the edge, level with the box.
	var past: float = HitShape.along(Vector2(145.0, 0.0), Vector2(0.0, 100.0), 10000.0, centre, BENCH)
	check(past >= 0.42 and past <= 0.58, "one passing beside it: level with its side (%s)" % past)
	check(is_equal_approx(HitShape.gap(Vector2(145.0, 0.0) + Vector2(0.0, 100.0) * past - centre, BENCH), 5.0), "5 off it there")
	# Slant past its top right corner (140, 42), never in it: nearest at the corner's foot, halfway.
	var from := Vector2(132.0, 30.0)
	var path := Vector2(20.0, 20.0)
	check_equal(HitShape.along(from, path, path.length_squared(), centre, BENCH), 0.5, "one passing a corner: the corner's foot on it")
	# Along its top edge, 4 above, from 20 before its left end: every point over it is as near;
	# the first is taken, over its left corner.
	check(is_equal_approx(HitShape.along(Vector2(40.0, 38.0), Vector2(120.0, 0.0), 14400.0, centre, BENCH), 1.0 / 6.0), "one along an edge: the first point as near as any")
	check_equal(HitShape.along(Vector2(200.0, 50.0), Vector2(100.0, 0.0), 10000.0, centre, BENCH), 0.0, "one going away: its start")
	check_equal(HitShape.along(Vector2(200.0, 50.0), Vector2.ZERO, 0.0, centre, BENCH), 0.0, "one that does not move: where it is")


func test_how_far_a_line_passes_off_a_box() -> void:
	check_equal(HitShape.line_gap_sq(Vector2(0.0, 30.0), Vector2(1.0, -1.0), BENCH), 0.0, "a line through it: none")
	check(is_equal_approx(HitShape.line_gap_sq(Vector2(-100.0, 20.0), Vector2(1.0, 0.0), BENCH), 144.0), "a line along it 12 above: 12, squared")
	check(is_equal_approx(HitShape.line_gap_sq(Vector2(0.0, 20.0), Vector2(-3.0, 0.0), BENCH), 144.0), "either way along it")


func test_how_far_a_box_reaches() -> void:
	check_equal(HitShape.reach_toward(BENCH, 0.0, Vector2.RIGHT), 40.0, "along its length: half of it")
	check_equal(HitShape.reach_toward(BENCH, 0.0, Vector2.UP), 8.0, "across: half its depth")
	check(is_equal_approx(HitShape.reach_toward(BENCH, 2.0, Vector2(0.6, 0.8)), 12.0), "slant: to where the line leaves its edge, and its rounding on")
	check(is_equal_approx(HitShape.outer_radius(BENCH, 0.0), Vector2(40.0, 8.0).length()), "at most to its corner")
	check_equal(HitShape.axis_reach(BENCH, 1.0), 41.0, "along an axis: its longer half and its rounding")


func test_how_wide_a_box_is_seen_from_a_point() -> void:
	# From 100 left of the bench's centre, its near corners (60 off, 8 up and down) bound what is seen.
	var seen: Vector2 = HitShape.sides(Vector2(100.0, 0.0), BENCH, 0.0)
	var corner: float = atan2(8.0, 60.0)
	check(is_equal_approx(seen.x, -corner) and is_equal_approx(seen.y, corner), "its near corners either way: %s" % seen)
	var rounded: Vector2 = HitShape.sides(Vector2(100.0, 0.0), BENCH, 2.0)
	check(rounded.y > seen.y and rounded.x < seen.x, "rounded, a little wider")
	# From above its right end the box is seen mostly one way round.
	var above: Vector2 = HitShape.sides(Vector2(-30.0, 50.0), BENCH, 0.0)
	check(above.x < 0.0 and above.y > 0.0 and absf(above.x) > absf(above.y), "off its end: more of it one way than the other: %s" % above)
	var circle: Vector2 = HitShape.sides(Vector2(100.0, 0.0), Vector2.ZERO, 8.0)
	check(is_equal_approx(circle.y, DMath.asin(8.0 / 100.0)), "a circle: its own width either way")
	check_equal(circle.x, -circle.y, "the same both ways")
