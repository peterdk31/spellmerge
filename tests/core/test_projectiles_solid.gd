extends "res://tests/support/suite.gd"
## A solid shot (`set_solid`, the Wall card, rules R4 F6) is a wall while it lives: it lies in the
## wall grid (shots end on it), it is a static body on the walls' physics layer (bodies cannot
## walk through it), its own payloads leave it, and all of it goes when it ends, leaving the
## room's walls as they were. The manager is stepped by hand.
##
## godot --headless --path . --script res://tests/core/test_projectiles_solid.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const DT: float = 1.0 / 60.0

var bus: EventsScript
var mgr: ManagerScript


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.events = bus
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	root.add_child(mgr)


## A wall of five stones 9 px apart across the x axis at `at`, living `seconds`.
func _wall(at: Vector2, seconds: float = 1.0) -> int:
	var slot: int = mgr.spawn(0, at, Vector2.ZERO, seconds, 5.0, ManagerScript.LAYER_ENEMY, 1 << 30, 1, ManagerScript.MOTION_STILL)
	check(mgr.set_solid(slot, Vector2.DOWN, 5, 9.0), "the still shot becomes solid")
	return slot


## A body of radius 6 on the walls' mask at `at`, as an actor's.
func _body(at: Vector2) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.collision_layer = 0
	body.collision_mask = ManagerScript.WALL_LAYER
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6.0
	shape.shape = circle
	body.add_child(shape)
	root.add_child(body)
	own(body)
	body.global_position = at
	return body


func test_a_body_cannot_walk_through_it_while_it_stands() -> void:
	_wall(Vector2(200.0, 100.0))
	var body: CharacterBody2D = _body(Vector2(170.0, 100.0))
	await physics_frame
	check(body.test_move(body.global_transform, Vector2(60.0, 0.0)), "the wall stops the body")
	check(not body.test_move(body.global_transform, Vector2(0.0, 60.0)), "beside it the way is open")
	for i in 70:
		mgr.step(DT)
	await physics_frame
	check(not body.test_move(body.global_transform, Vector2(60.0, 0.0)), "once it is gone the body walks on")


func test_a_shot_ends_on_it() -> void:
	_wall(Vector2(200.0, 100.0))
	var shot: int = mgr.spawn(1, Vector2(150.0, 110.0), Vector2(300.0, 0.0), 2.0)
	for i in 20:
		mgr.step(DT)
	check(not mgr.is_alive(shot), "the shot ended on the wall")
	check_equal(mgr.wall_hits, 1, "a wall end")


func test_its_own_payload_leaves_it() -> void:
	var wall: int = _wall(Vector2(200.0, 100.0))
	var payload: int = mgr.spawn(0, Vector2(200.0, 100.0), Vector2(300.0, 0.0), 2.0)
	check(payload >= 0, "a shot born in the row is made")
	mgr.set_caster_shot(payload, wall)
	var stranger: int = mgr.spawn(1, Vector2(200.0, 104.0), Vector2(300.0, 0.0), 2.0)
	for i in 10:
		mgr.step(DT)
	check(mgr.is_alive(payload) and mgr.get_position_of(payload).x > 230.0, "the wall's payload flew out of it")
	check(not mgr.is_alive(stranger), "a shot it did not cast ends on it")


func test_a_beam_it_casts_leaves_it() -> void:
	# Rules R4 F8: the same rule for a ray: one its wall casts walks out through it.
	var wall: int = _wall(Vector2(200.0, 100.0))
	check_equal(mgr.ray(0, Vector2(200.0, 100.0), Vector2.RIGHT, 100.0), 0.0, "a ray born in a wall it was not cast by gets nowhere")
	mgr.ray_cast_by(wall)
	check_equal(mgr.ray(0, Vector2(200.0, 100.0), Vector2.RIGHT, 100.0), 100.0, "the wall's own ray walks out of it")
	check_equal(mgr.ray(0, Vector2(200.0, 100.0), Vector2.RIGHT, 100.0), 0.0, "for that ray only")
	check(mgr.clip_to_walls(Vector2(150.0, 100.0), Vector2(250.0, 100.0)) != Vector2(250.0, 100.0), "the wall stands after it")


func test_the_room_walls_stay_when_it_ends() -> void:
	mgr.set_walls([Rect2(192.0, 0.0, 16.0, 96.0)] as Array[Rect2])
	_wall(Vector2(200.0, 100.0), 0.2)
	check(mgr.clip_to_walls(Vector2(150.0, 110.0), Vector2(250.0, 110.0)) != Vector2(250.0, 110.0), "the wall stands")
	for i in 20:
		mgr.step(DT)
	check_equal(mgr.clip_to_walls(Vector2(150.0, 110.0), Vector2(250.0, 110.0)), Vector2(250.0, 110.0), "its row is gone")
	check(mgr.clip_to_walls(Vector2(150.0, 90.0), Vector2(250.0, 90.0)) != Vector2(250.0, 90.0), "the room wall it lay on is still there")


func test_it_hits_along_its_row() -> void:
	var hit: Array[Node] = []
	bus.projectile_hit.connect(func(_caster: int, target: Node, _at: Vector2, _tag: int) -> void: hit.append(target))
	var target := Node2D.new()
	root.add_child(target)
	own(target)
	target.global_position = Vector2(210.0, 118.0)
	mgr.add_target(target, 6.0, ManagerScript.LAYER_ENEMY)
	_wall(Vector2(200.0, 100.0))
	for i in 10:
		mgr.step(DT)
	check_equal(hit.size(), 1, "the target at the row's end is hit, once while it stays")
