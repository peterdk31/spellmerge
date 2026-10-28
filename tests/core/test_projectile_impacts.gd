extends "res://tests/support/suite.gd"
## `Events.projectile_impact` from core/projectiles: every shot that ends on a wall or pillar
## and every shot that hits a target says where it stopped and which way it flew, so
## `gameplay/feel` can show it. The manager is stepped by hand.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const DT: float = 1.0 / 60.0
const NO_PLAYER_SHOT: int = -1

var bus: EventsScript
var mgr: ManagerScript
## Every impact as [player, target, position, direction], and every hit as the same order of events.
var impacts: Array = []
var order: Array[String] = []
## The manager's `impact_form` as each impact was sent.
var forms: Array[StringName] = []


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.events = bus
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	impacts.clear()
	order.clear()
	forms.clear()
	bus.projectile_impact.connect(func(player: int, target: Node, position: Vector2, direction: Vector2) -> void:
		forms.append(mgr.impact_form)
		impacts.append([player, target, position, direction])
		order.append("impact"))
	bus.projectile_hit.connect(func(_player: int, _target: Node, _position: Vector2, _tag: int) -> void: order.append("hit"))


func test_a_shot_that_ends_on_a_wall_says_where_and_which_way() -> void:
	mgr.set_walls([Rect2(96.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	mgr.spawn(2, Vector2(50.0, 100.0), Vector2(120.0, 0.0), 5.0)
	for _i in 60:
		mgr.step(DT)
	check_equal(impacts.size(), 1, "one impact for one shot")
	if impacts.is_empty():
		return
	check_equal(impacts[0][0], 2, "the player who fired it")
	check(impacts[0][1] == null, "a wall has no target")
	check((impacts[0][2] as Vector2).x >= 88.0 and (impacts[0][2] as Vector2).x <= 100.0, "at the wall's face, not past it")
	check((impacts[0][3] as Vector2).is_equal_approx(Vector2.RIGHT), "flying right")


func test_every_direction_is_reported() -> void:
	mgr.set_walls([Rect2(0.0, 0.0, 640.0, 32.0), Rect2(0.0, 328.0, 640.0, 32.0)] as Array[Rect2])
	mgr.spawn(0, Vector2(300.0, 100.0), Vector2(0.0, -200.0), 5.0)
	mgr.spawn(1, Vector2(300.0, 250.0), Vector2(0.0, 200.0), 5.0)
	for _i in 120:
		mgr.step(DT)
	check_equal(impacts.size(), 2, "both shots ended on a wall")
	var seen: Array[Vector2] = []
	for impact: Array in impacts:
		seen.append(impact[3] as Vector2)
	check(seen.has(Vector2.UP) and seen.has(Vector2.DOWN), "up and down are both reported (%s)" % str(seen))


func test_a_piercing_shot_is_reported_once_on_the_wall() -> void:
	mgr.set_walls([Rect2(300.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	mgr.spawn(0, Vector2(50.0, 100.0), Vector2(600.0, 0.0), 5.0, 4.0, ManagerScript.LAYER_ENEMY, 5)
	for _i in 60:
		mgr.step(DT)
	check_equal(impacts.size(), 1, "the shot ends once, so it is reported once")


func test_an_enemy_shot_reports_no_player() -> void:
	mgr.set_walls([Rect2(96.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	mgr.spawn(EventsScript.NO_PLAYER, Vector2(50.0, 100.0), Vector2(120.0, 0.0), 5.0)
	for _i in 60:
		mgr.step(DT)
	check_equal(impacts.size(), 1, "one impact")
	if not impacts.is_empty():
		check_equal(impacts[0][0], EventsScript.NO_PLAYER, "the enemy's shot has no player")


func test_a_shot_born_in_a_wall_shows_no_impact() -> void:
	mgr.set_walls([Rect2(96.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	var slot: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2(0.0, 200.0), 5.0)
	check_equal(slot, -1, "the shot is refused")
	check_equal(impacts.size(), 0, "no shot existed, so nothing struck")


func test_a_hit_on_a_target_says_which_way_the_shot_flew_before_the_hit() -> void:
	var target: Node2D = own(Node2D.new()) as Node2D
	root.add_child(target)
	target.global_position = Vector2(200.0, 100.0)
	mgr.add_target(target, 10.0, ManagerScript.LAYER_ENEMY)
	mgr.spawn(1, Vector2(100.0, 100.0), Vector2(600.0, 0.0), 5.0)
	for _i in 30:
		mgr.step(DT)
	check_equal(impacts.size(), 1, "one impact for one hit")
	if impacts.is_empty():
		return
	check(impacts[0][1] == target, "the target that was hit")
	check_equal(impacts[0][0], 1, "the shooter")
	check((impacts[0][3] as Vector2).is_equal_approx(Vector2.RIGHT), "flying right")
	check_equal(order, ["impact", "hit"] as Array[String], "the impact comes first, so the damage that follows `projectile_hit` can use it")


func test_each_impact_names_the_form_of_its_own_shot() -> void:
	mgr.set_walls([Rect2(96.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	var target := own(Node2D.new()) as Node2D
	root.add_child(target)
	target.global_position = Vector2(30.0, 300.0)
	mgr.add_target(target, 10.0, ManagerScript.LAYER_ENEMY)
	mgr.spawn(0, Vector2(50.0, 100.0), Vector2(120.0, 0.0), 5.0)
	mgr.spawn(NO_PLAYER_SHOT, Vector2(50.0, 120.0), Vector2(120.0, 0.0), 5.0)
	mgr.spawn(1, Vector2(30.0, 300.0), Vector2.ZERO, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	mgr.ray(2, Vector2(50.0, 140.0), Vector2.RIGHT, 300.0)
	for _i in 60:
		mgr.step(DT)
	var names: Array[String] = []
	for form in forms:
		names.append(String(form))
	names.sort()
	check_equal(names, ["beam", "bolt", "bolt", "rune"] as Array[String], "a beam, a rune and two bolts (an enemy's shot is drawn as a bolt too since staffs F9b), each its own")
	check_equal(mgr.impact_form, &"", "no form once the impacts are sent")


func test_a_miss_reports_nothing() -> void:
	mgr.spawn(0, Vector2(100.0, 100.0), Vector2(100.0, 0.0), 0.2)
	for _i in 30:
		mgr.step(DT)
	check(impacts.is_empty(), "a shot that just ends in the air is no impact")
