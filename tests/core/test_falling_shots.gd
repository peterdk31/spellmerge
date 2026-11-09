extends "res://tests/support/suite.gd"
## Falling shots in the projectile manager (`set_floor`, Skyfall; docs/milestones/carrier-modifiers.md
## Part 2): a shot falling onto its floor line touches nothing in the air, is an ordinary shot within
## FALL_BAND of the line, and ends at the line as at the end of its life, at any speed, with the
## native kernel and without it (the kernel hands every falling shot to `_hit_slot`).
##
## godot --headless --path . --script res://tests/core/test_falling_shots.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const DT: float = 1.0 / 60.0
## The floor line every test drops onto, and where the shot starts above it.
const FLOOR_Y: float = 200.0
const FROM := Vector2(100.0, 100.0)

var _mgr: ManagerScript
var _bus: EventsScript
var _hits: Array = []
var _expired: Array = []


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_mgr.set_cap(64)
	_mgr.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	_mgr.set_bounds(Rect2(0.0, 0.0, 400.0, 400.0))
	_hits.clear()
	_expired.clear()
	_bus.projectile_hit.connect(func(_caster: int, target: Node, _at: Vector2, _tag: int, _shot: int) -> void: _hits.append(target))
	_bus.projectile_expired.connect(func(_caster: int, at: Vector2, _tag: int, _shot: int) -> void: _expired.append(at))


func _target(at: Vector2, radius: float = 8.0) -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	node.global_position = at
	own(node)
	_mgr.add_target(node, radius, ManagerScript.LAYER_ENEMY)
	return node


func _drop(speed: float) -> int:
	var slot: int = _mgr.spawn(0, FROM, Vector2(0.0, speed), 5.0, 4.0)
	check(_mgr.set_floor(slot, FLOOR_Y), "the shot takes its floor line")
	return slot


func _run(steps: int) -> void:
	for i in steps:
		_mgr.step(DT)


func test_it_ends_at_its_floor_line_as_at_the_end_of_its_life() -> void:
	for native in [true, false]:
		_mgr.native = native
		_expired.clear()
		var slot: int = _drop(300.0)
		check(is_equal_approx(_mgr.get_floor_of(slot), FLOOR_Y), "it knows its floor line")
		_run(40)
		check(not _mgr.is_alive(slot), "native %s: it has ended" % native)
		check_equal(_expired.size(), 1, "native %s: as an expiry" % native)
		if _expired.size() == 1:
			check(absf((_expired[0] as Vector2).y - FLOOR_Y) < 0.5, "native %s: on the floor line (%s)" % [native, _expired[0]])


func test_it_hits_only_what_stands_close_to_the_line() -> void:
	for native in [true, false]:
		_mgr.native = native
		_mgr.clear()
		_hits.clear()
		var high: Node2D = _target(Vector2(FROM.x, FLOOR_Y - 50.0))
		var low: Node2D = _target(Vector2(FROM.x, FLOOR_Y - 2.0))
		_drop(300.0)
		_run(40)
		check(not _hits.has(high), "native %s: nothing up in the air is hit" % native)
		check(_hits.has(low), "native %s: what stands at the line is" % native)
		_mgr.remove_target(high)
		_mgr.remove_target(low)


func test_a_step_past_the_band_still_hits_what_stands_in_it() -> void:
	# 6,000 px a second: one step of 100 px from above the band to past the line.
	var low: Node2D = _target(Vector2(FROM.x, FLOOR_Y - 4.0))
	var slot: int = _drop(6000.0)
	_run(2)
	check(_hits.has(low), "the target in the band is hit")
	check(not _mgr.is_alive(slot), "and the shot ended at the line")


func test_it_passes_over_walls_in_the_air_and_meets_them_in_the_band() -> void:
	_mgr.set_walls([Rect2(80.0, 140.0, 40.0, 8.0)] as Array[Rect2])
	var low: Node2D = _target(Vector2(FROM.x, FLOOR_Y - 2.0))
	_drop(300.0)
	_run(40)
	check(_hits.has(low), "a wall up in the air does not stop it")
	_mgr.remove_target(low)
	_mgr.clear()
	_hits.clear()
	_mgr.set_walls([Rect2(80.0, FLOOR_Y - 8.0, 40.0, 4.0)] as Array[Rect2])
	var slot: int = _drop(300.0)
	var walls: int = _mgr.wall_hits
	_run(40)
	check(not _mgr.is_alive(slot) and _mgr.wall_hits == walls + 1, "a wall in the band stops it")


func test_only_a_flying_shot_falls() -> void:
	var still: int = _mgr.spawn(0, FROM, Vector2.ZERO, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	check(not _mgr.set_floor(still, FLOOR_Y), "a still shot takes no floor line")
	check(not _mgr.set_floor(_drop(10.0), INF), "nor a line that is not one")
	check_equal(_mgr.get_floor_of(still), INF, "a shot that is not falling has none")
