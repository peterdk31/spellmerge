extends "res://tests/support/suite.gd"
## Box hit shapes in the projectile manager (props, docs/milestones/props.md: "box hurt shapes"): a
## target registered with a `half` is hit where its box is (`HitShape`), by every test the manager
## has: a flying shot, a beam, a sweep (swings and blasts), the area queries (zaps, pulls, touch), a
## homing search and the shot that spares the body it started on. A long bench is hit at its ends,
## where a circle round its centre as deep as it would miss, and missed past them. The manager is
## stepped by hand; the native twin is held to these by tests/core/test_native_kernel.gd.
##
## godot --headless --path . --script res://tests/core/test_projectiles_boxes.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

const DT: float = 1.0 / 60.0
## The bench: 80 by 16, its box centred at CENTRE.
const CENTRE: Vector2 = Vector2(200.0, 100.0)
const HALF: Vector2 = Vector2(40.0, 8.0)

var bus: EventsScript
var mgr: ManagerScript
var bench: Node2D
## Every projectile_hit as [target name, point].
var _hits: Array = []


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.events = bus
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	root.add_child(mgr)
	bench = _body("bench", CENTRE, 0.0, HALF)
	_hits.clear()
	bus.projectile_hit.connect(func(_caster: int, target: Node, at: Vector2, _tag: int, _shot: int) -> void: _hits.append([String(target.name), at]))


func _body(name: String, at: Vector2, radius: float, half: Vector2 = Vector2.ZERO) -> Node2D:
	var node := own(Node2D.new()) as Node2D
	node.name = name
	root.add_child(node)
	node.global_position = at
	mgr.add_target(node, radius, ManagerScript.LAYER_ENEMY, EventsScript.NO_PLAYER, Vector2.ZERO, 0, half)
	return node


## A shot of radius 2 falling from above at `x`, stepped for a second.
func _drop_at(x: float) -> void:
	mgr.spawn(0, Vector2(x, 20.0), Vector2(0.0, 300.0), 1.0, 2.0)
	for n in 60:
		mgr.step(DT)


func test_a_shot_hits_a_box_at_its_end_and_misses_past_it() -> void:
	_drop_at(235.0)
	check_equal(_hits.size(), 1, "a shot falling onto the bench's end hits it")
	if _hits.size() == 1:
		var at: Vector2 = _hits[0][1]
		check(is_equal_approx(at.x, 235.0) and at.y >= 89.0 and at.y <= 92.0, "on its top edge, where it is drawn: %s" % at)
	_hits.clear()
	_drop_at(245.0)
	check(_hits.is_empty(), "one falling 5 px past its end misses it")


func test_a_beam_stops_where_it_goes_into_a_box() -> void:
	var got: float = mgr.ray(0, Vector2(100.0, 104.0), Vector2.RIGHT, 300.0)
	check(is_equal_approx(got, 60.0), "a beam along the bench stops at its end (%s)" % got)
	check(_hits.size() == 1 and (_hits[0][1] as Vector2).is_equal_approx(Vector2(160.0, 104.0)), "and hits it there: %s" % [_hits])
	_hits.clear()
	check(mgr.ray(0, Vector2(100.0, 112.0), Vector2.RIGHT, 300.0, 0, ManagerScript.LAYER_ENEMY, 0, 3.0) > 299.0 and _hits.is_empty(), "one 4 px under it, 3 wide, passes")


func test_a_sweep_meets_a_box_where_it_is() -> void:
	# A blast below the bench's middle: its long edge is 22 off.
	check_equal(mgr.sweep(0, Vector2(200.0, 130.0), Vector2.RIGHT, 1, -PI, PI, 20.0), 0, "a blast that falls short of it misses (its centre's circle round its corner would not)")
	check_equal(mgr.sweep(0, Vector2(200.0, 130.0), Vector2.RIGHT, 1, -PI, PI, 25.0), 1, "one that reaches it hits")
	# A narrow swing from 60 past its end: the box is seen within a few degrees either way of left.
	check_equal(mgr.sweep(0, Vector2(300.0, 100.0), Vector2.LEFT, 1, -0.1, 0.1, 70.0), 1, "a swing at its end hits it")
	if mgr.sweep(0, Vector2(300.0, 100.0), Vector2.LEFT, 1, -0.1, 0.1, 70.0) == 1:
		check(mgr.sweep_points[0].is_equal_approx(Vector2(240.0, 100.0)), "where its end is: %s" % mgr.sweep_points[0])
	check_equal(mgr.sweep(0, Vector2(300.0, 100.0), Vector2.LEFT, 1, 0.3, 0.5, 70.0), 0, "a swing turned off it misses")
	# Seen from there the box spans 7.6 degrees either way of left; a circle round its corners 24.
	check_equal(mgr.sweep(0, Vector2(300.0, 100.0), Vector2(-1.0, 0.1).normalized(), 1, -0.05, 0.05, 70.0), 1, "a swing turned 6 degrees off its middle still meets it")
	check_equal(mgr.sweep(0, Vector2(300.0, 100.0), Vector2(-1.0, 0.25).normalized(), 1, -0.05, 0.05, 70.0), 0, "one turned 14 degrees off misses (a circle round its corners would not)")
	# Counted the other way round: a wedge from 0.1 to 0.2 past left, clockwise on screen, turns up
	# (off the box); counterclockwise, down (still off it); from 0.0 either way it is on it.
	check_equal(mgr.sweep(0, Vector2(300.0, 160.0), Vector2.LEFT, 1, 0.75, 0.85, 120.0), 1, "a swing turning clockwise from below its end meets it")
	check_equal(mgr.sweep(0, Vector2(300.0, 160.0), Vector2.LEFT, -1, 0.75, 0.85, 120.0), 0, "the same wedge counted the other way misses")
	check_equal(mgr.sweep(0, Vector2(300.0, 40.0), Vector2.LEFT, -1, 0.75, 0.85, 120.0), 1, "and meets it from above")


func test_the_area_queries_find_a_box_by_its_edges() -> void:
	var found: Array[Node2D] = []
	check_equal(mgr.targets_in(Vector2(200.0, 120.0), 13.0, ManagerScript.LAYER_ENEMY, found), 1, "a circle over its long edge finds it")
	check_equal(mgr.targets_in(Vector2(250.0, 100.0), 9.0, ManagerScript.LAYER_ENEMY, found), 0, "one 10 off its end, 9 wide, does not")
	check_equal(mgr.targets_in(Vector2(250.0, 100.0), 11.0, ManagerScript.LAYER_ENEMY, found), 1, "11 wide does")
	check_equal(mgr.targets_in(Vector2(300.0, 60.0), 4.0, ManagerScript.LAYER_ENEMY, found, Vector2(300.0, 140.0)), 0, "a line past its end does not")
	check_equal(mgr.targets_in(Vector2(230.0, 0.0), 4.0, ManagerScript.LAYER_ENEMY, found, Vector2(250.0, 200.0)), 1, "a slant line across its corner does")
	check(mgr.nearest_target(Vector2(250.0, 100.0), 11.0, ManagerScript.LAYER_ENEMY) == bench, "the nearest within 11 of a point off its end is it")
	var near: Array[Node2D] = []
	var centres: PackedVector2Array = PackedVector2Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	check_equal(mgr.targets_near(Vector2(250.0, 100.0), 11.0, ManagerScript.LAYER_ENEMY, ActorsScript.NONE, near, centres, radii), 1, "a zap's reach finds it")
	if near.size() == 1:
		check(centres[0].is_equal_approx(CENTRE) and is_equal_approx(radii[0], HALF.length()), "at its centre, reaching to its corner (%s, %s)" % [centres[0], radii[0]])
	check(mgr.touches_target(bench, Vector2(250.0, 100.0), 10.5), "a circle 10 off its end, 10.5 wide, touches it")
	check(not mgr.touches_target(bench, Vector2(250.0, 100.0), 9.5), "9.5 wide does not")


func test_homing_finds_a_box_by_its_edge_and_stops_there() -> void:
	var goal: Vector2 = mgr.homing_point(0, Vector2(300.0, 100.0), Vector2.LEFT, PI, ManagerScript.LAYER_ENEMY, 65.0, 0, 1)
	check(goal.is_equal_approx(CENTRE), "a search 60 from its end finds it, its centre to steer at")
	check(is_equal_approx(mgr.homing_target_reach, HALF.x), "and it reaches 40 toward the search (%s)" % mgr.homing_target_reach)
	check(not mgr.homing_point(0, Vector2(300.0, 100.0), Vector2.LEFT, PI, ManagerScript.LAYER_ENEMY, 55.0, 0, 1).is_finite(), "one within 55 does not")
	mgr.homing_point(0, Vector2(200.0, 160.0), Vector2.UP, PI, ManagerScript.LAYER_ENEMY, 65.0, 0, 1)
	check(is_equal_approx(mgr.homing_target_reach, HALF.y), "from below it reaches 8 (%s)" % mgr.homing_target_reach)


func test_a_shot_cast_in_a_box_spares_it_until_clear() -> void:
	var slot: int = mgr.spawn(0, Vector2(235.0, 100.0), Vector2(0.0, 300.0), 0.5, 2.0)
	mgr.exclude(slot, bench)
	for n in 30:
		mgr.step(DT)
	check(_hits.is_empty(), "a shot cast from the bench's end leaves it unhit")
	mgr.spawn(0, Vector2(235.0, 100.0), Vector2(0.0, 300.0), 0.5, 2.0)
	mgr.step(DT)
	check_equal(_hits.size(), 1, "one cast there sparing nothing hits it at once")


func test_a_registered_box_widens_every_search() -> void:
	check_equal(mgr._max_target_reach, HALF.x, "the farthest a shape reaches along an axis: the bench's half length")
	mgr.add_target(bench, 3.0, ManagerScript.LAYER_ENEMY, EventsScript.NO_PLAYER, Vector2.ZERO, 0, Vector2(-5.0, 2.0))
	check_equal(mgr._target_half[0], Vector2(0.0, 2.0), "registered again: its new box, never less than none")
