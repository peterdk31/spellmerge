extends "res://tests/support/suite.gd"
## Draw cost by count (shot scale H4, docs/milestones/shot-scale.md): at most `trail_cap` shots draw
## a trail at once; the newest past it draw without one, and the trail rows (and so the trail
## texture, sent whole each time the trails take their points) are sized by the smaller of the cap
## and `trail_cap`. The setting changes only the look: the shots fly and hit as before.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

var _bus: EventsScript
var _mgr: ManagerScript


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	var actors: ActorSeats.ActorsScript = own(ActorSeats.table()) as ActorSeats.ActorsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.actors = actors
	_mgr.events = _bus
	root.add_child(_mgr)
	_mgr.set_physics_process(false)
	_mgr.set_process(false)
	_mgr.set_cap(500)
	_mgr.set_bounds(Rect2(-1000.0, -1000.0, 2000.0, 2000.0))


func test_past_the_trail_cap_the_newest_shots_draw_without_a_trail() -> void:
	_mgr.set_trail_cap(100)
	var slots: PackedInt32Array = PackedInt32Array()
	for i in 150:
		slots.append(_spawn(i))
	var trailed: int = 0
	for i in slots.size():
		if _mgr._trail[slots[i]] >= 0:
			trailed += 1
			check(i < 100, "shot %d past the cap has no trail" % i)
	check_equal(trailed, 100, "the first 100 shots have trails")
	check_equal(_mgr.get_count(), 150, "every shot flies")


func test_an_ended_trailed_shot_lets_a_new_one_have_a_trail() -> void:
	_mgr.set_trail_cap(10)
	var first: PackedInt32Array = PackedInt32Array()
	for i in 10:
		first.append(_spawn(i))
	check_equal(_mgr._trail[_spawn(10)], -1, "the eleventh has none")
	_mgr._kill(first[0])
	check(_mgr._trail[_spawn(11)] >= 0, "after one ends, the next spawned has a trail")


func test_the_trail_rows_follow_the_smaller_count() -> void:
	check_equal(_mgr._trail_free.size(), ManagerScript.trail_rows(500, _mgr.trail_cap), "the rows at the default")
	_mgr.set_trail_cap(250)
	check_equal(_mgr._trail_free.size(), 250 * ManagerScript.TRAIL_ROWS_PER_SLOT, "250 trailed shots: their rows")
	_mgr.set_trail_cap(20000)
	check_equal(_mgr._trail_free.size(), 500 * ManagerScript.TRAIL_ROWS_PER_SLOT, "never more than the cap needs")


func test_a_new_count_drops_the_tails_but_not_the_shots() -> void:
	for i in 50:
		_spawn(i)
	_mgr.step(1.0 / 60.0)
	_bus.shot_trails_changed.emit(250)
	check_equal(_mgr.trail_cap, 250, "the event sets the count")
	check_equal(_mgr.get_count(), 50, "the shots fly on")
	var any: bool = false
	for slot in _mgr._high:
		any = any or _mgr._trail[slot] >= 0
	check(not any, "the tails in the air are gone")
	check(_mgr._trail[_spawn(50)] >= 0, "a new shot takes a new row")
	_mgr.step(1.0 / 60.0)
	_mgr.update_draw(1.0)
	check_equal(_mgr.drawn, 51, "every shot is drawn, with a trail or without")


func test_the_trail_cap_changes_no_hit() -> void:
	var hits: Array[int] = []
	for trailed: int in [500, 1]:
		var body := own(Node2D.new()) as Node2D
		body.position = Vector2(60.0, 0.0)
		root.add_child(body)
		_mgr.clear()
		_mgr.set_trail_cap(trailed)
		_mgr.add_target(body, 8.0, ManagerScript.LAYER_ENEMY)
		var count: Array[int] = [0]
		var on_hit := func(_c: int, _t: Node, _p: Vector2, _tag: int, _s: int) -> void: count[0] += 1
		_bus.projectile_hit.connect(on_hit)
		for i in 40:
			_mgr.spawn(_mgr.actors.actor_of_seat(0), Vector2(0.0, float(i % 5) - 2.0), Vector2.RIGHT * 300.0, 1.0, 3.0, ManagerScript.LAYER_ENEMY, 0)
		for i in 30:
			_mgr.step(1.0 / 60.0)
		_bus.projectile_hit.disconnect(on_hit)
		_mgr.remove_target(body)
		hits.append(count[0])
	check(hits[0] > 0, "the shots hit")
	check_equal(hits[1], hits[0], "the same hits with one trail as with every one")


func test_the_setting_stops() -> void:
	check(TrailCap.STOPS.has(TrailCap.default_cap()), "the platform's count is a stop")
	check_equal(TrailCap.snap(1), TrailCap.STOPS[0], "a small number snaps to the bottom")
	check_equal(TrailCap.snap(1_000_000), TrailCap.STOPS[-1], "a large one to the top")


func _spawn(i: int) -> int:
	return _mgr.spawn(_mgr.actors.actor_of_seat(i % 4), Vector2.ZERO, Vector2.from_angle(float(i)) * 50.0, 5.0)
