extends "res://tests/support/suite.gd"
## A ray with `bounces` (`bounce · beam`) turns at a wall as a bouncing shot
## does and goes on for the length it has left: it hits what is on its later legs, sends an
## impact at every turn, and `ray_path` holds the path it walked. Without bounces it stops at
## the wall, as before. The manager is stepped by hand.
##
## godot --headless --path . --script res://tests/core/test_projectiles_ray_bounce.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const DIAGONAL: Vector2 = Vector2(0.70710678, 0.70710678)

var bus: EventsScript
var mgr: ManagerScript
## Every impact as [target, position].
var impacts: Array = []
var hits: Array[Node] = []


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.events = bus
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	impacts.clear()
	hits.clear()
	bus.projectile_impact.connect(func(_caster: int, target: Node, position: Vector2, _direction: Vector2) -> void:
		impacts.append([target, position]))
	bus.projectile_hit.connect(func(_caster: int, target: Node, _position: Vector2, _tag: int) -> void:
		hits.append(target))


func _target(position: Vector2) -> Node2D:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.global_position = position
	mgr.add_target(node, 10.0, ManagerScript.LAYER_ENEMY)
	return node


func test_without_bounces_a_ray_stops_at_the_wall() -> void:
	mgr.set_walls([Rect2(200.0, 0.0, 16.0, 360.0)] as Array[Rect2])
	var got: float = mgr.ray(0, Vector2(100.0, 100.0), DIAGONAL, 300.0)
	check(got > 140.0 and got < 142.0, "it got to the wall (%s)" % str(got))
	check_equal(mgr.ray_path_count, 2, "its path is its start and its end")
	check_equal(impacts.size(), 1, "one impact, on the wall")


func test_a_bouncing_ray_turns_off_the_wall_face_and_goes_on_for_its_length() -> void:
	mgr.set_walls([Rect2(200.0, 0.0, 16.0, 360.0)] as Array[Rect2])
	var got: float = mgr.ray(0, Vector2(100.0, 100.0), DIAGONAL, 300.0, 0, ManagerScript.LAYER_ENEMY, 0, 0.0, null, 1)
	check(absf(got - 300.0) < 1.0, "its whole length (%s)" % str(got))
	check_equal(mgr.ray_path_count, 3, "start, the turn, the end")
	if mgr.ray_path_count < 3:
		return
	var turn: Vector2 = mgr.ray_path[1]
	var end: Vector2 = mgr.ray_path[2]
	check(turn.x > 199.0 and turn.x < 200.0, "it turns just in front of the wall (%s)" % str(turn))
	check(end.x < turn.x and end.y > turn.y, "back off the wall, still going down (%s)" % str(end))
	check(end.is_equal_approx(mgr.ray_end), "`ray_end` is the path's end")
	check(mgr.ray_end_heading.x < 0.0 and mgr.ray_end_heading.y > 0.0, "heading away from the wall")
	check_equal(impacts.size(), 1, "an impact at the turn, none at the end in the open")


func test_a_bouncing_ray_hits_a_target_only_its_turned_leg_reaches() -> void:
	mgr.set_walls([Rect2(200.0, 0.0, 16.0, 360.0)] as Array[Rect2])
	var behind: Node2D = _target(Vector2(150.0, 250.0))
	mgr.ray(0, Vector2(100.0, 100.0), DIAGONAL, 300.0)
	check(not hits.has(behind), "a ray that stops at the wall misses it")
	mgr.ray(0, Vector2(100.0, 100.0), DIAGONAL, 300.0, 0, ManagerScript.LAYER_ENEMY, 0, 0.0, null, 1)
	check_equal(hits.size(), 1, "the turned ray hits it")
	check(hits.has(behind), "the target behind the turn")


func test_it_turns_no_more_than_its_bounces_and_then_ends_on_the_next_wall() -> void:
	mgr.set_walls([Rect2(0.0, 0.0, 640.0, 40.0), Rect2(0.0, 200.0, 640.0, 40.0)] as Array[Rect2])
	var got: float = mgr.ray(0, Vector2(100.0, 120.0), DIAGONAL, 400.0, 0, ManagerScript.LAYER_ENEMY, 0, 0.0, null, 1)
	check(got > 330.0 and got < 345.0, "down, then up to the top wall (%s)" % str(got))
	check_equal(mgr.ray_path_count, 3, "one turn")
	if mgr.ray_path_count == 3:
		check(mgr.ray_path[2].y >= 39.0 and mgr.ray_path[2].y <= 41.0, "it ends on the top wall (%s)" % str(mgr.ray_path[2]))
	check_equal(impacts.size(), 2, "an impact at the turn and one where it ended")
	for impact: Array in impacts:
		check(impact[0] == null, "wall impacts have no target")


func test_a_ray_spent_on_a_target_before_the_wall_does_not_turn() -> void:
	mgr.set_walls([Rect2(200.0, 0.0, 16.0, 360.0)] as Array[Rect2])
	var first: Node2D = _target(Vector2(150.0, 150.0))
	var got: float = mgr.ray(0, Vector2(100.0, 100.0), DIAGONAL, 300.0, 0, ManagerScript.LAYER_ENEMY, 0, 0.0, null, 1)
	check(hits.size() == 1 and hits[0] == first, "it hits the target")
	check(got < 71.0, "and ends on it (%s)" % str(got))
	check_equal(mgr.ray_path_count, 2, "a straight path")
	check_equal(impacts.size(), 1, "the hit's impact, no turn")


func test_a_corner_sends_it_back_the_way_it_came() -> void:
	mgr.set_walls([Rect2(200.0, 0.0, 16.0, 360.0), Rect2(0.0, 200.0, 640.0, 16.0)] as Array[Rect2])
	var got: float = mgr.ray(0, Vector2(100.0, 100.0), DIAGONAL, 200.0, 0, ManagerScript.LAYER_ENEMY, 0, 0.0, null, 1)
	check(absf(got - 200.0) < 1.0, "its whole length (%s)" % str(got))
	if mgr.ray_path_count == 3:
		check(mgr.ray_end_heading.is_equal_approx(-DIAGONAL), "straight back (%s)" % str(mgr.ray_end_heading))
	else:
		check_equal(mgr.ray_path_count, 3, "one turn, in the corner")


func test_a_curved_ray_turns_too() -> void:
	mgr.set_walls([Rect2(200.0, 0.0, 16.0, 360.0)] as Array[Rect2])
	var got: float = mgr.ray_curve(0, Vector2(100.0, 100.0), Vector2(180.0, 120.0), Vector2(260.0, 200.0), 0, ManagerScript.LAYER_ENEMY, 0, 0.0, null, false, 1)
	check(got > 0.0, "it got somewhere")
	check(mgr.ray_end.x < 200.0, "it never passes the wall (%s)" % str(mgr.ray_end))
	check(mgr.ray_end_heading.x < 0.0, "it comes back off it")
	check_equal(impacts.size(), 0, "a ray that does not hit sends nothing")


func test_bounces_are_not_capped_however_many_turns_a_long_beam_makes() -> void:
	const LONG: float = 2000.0
	var most: int = 0
	# A gap one and two cells wide, at every whole degree: a beam far longer than any card's turns
	# hundreds of times, more than its path holds at first, and still uses its whole length.
	for gap: float in [8.0, 16.0]:
		mgr.set_walls([Rect2(0.0, 0.0, 640.0, 96.0), Rect2(0.0, 96.0 + gap, 640.0, 200.0)] as Array[Rect2])
		for degrees in range(1, 91):
			impacts.clear()
			var way: Vector2 = Vector2.from_angle(deg_to_rad(float(degrees)))
			var got: float = mgr.ray(0, Vector2(100.0, 96.0 + gap * 0.5), way, LONG, 0, ManagerScript.LAYER_ENEMY, 0, 0.0, null, 1000000)
			most = maxi(most, mgr.ray_path_count - 2)
			var out_of_room: bool = mgr.ray_end.x < 0.0 or mgr.ray_end.x > 640.0
			if absf(got - LONG) > 1.0 and not out_of_room:
				check(false, "a %s px gap at %d degrees: it used its whole length (%s)" % [gap, degrees, got])
				return
	check(most > ManagerScript.RAY_PATH_START, "more turns than the path holds at first (%d)" % most)
	print("most turns in a tight gap: %d" % most)
