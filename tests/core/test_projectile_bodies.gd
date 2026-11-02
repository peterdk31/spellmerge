extends "res://tests/support/suite.gd"
## What a shot is drawn as and told as (`Projectiles.set_form`): every shot a card fired carries the
## card's id, so its impacts and its end are told as that card (`impact_form`, its card's impact
## look), and the body (`impact_body`) goes with them; a still shot may ask for a still body of its
## own (a wall's stone, KIND_STONE), and any other ask keeps its motion's body. The manager is
## stepped by hand.
##
## godot --headless --path . --script res://tests/core/test_projectile_bodies.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const DT: float = 1.0 / 60.0

var bus: EventsScript
var mgr: ManagerScript
## The manager's [impact_form, impact_body] as each impact or expiry was sent.
var told: Array = []


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.events = bus
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	told.clear()
	bus.projectile_impact.connect(func(_caster: int, _target: Node, _position: Vector2, _direction: Vector2) -> void:
		told.append([mgr.impact_form, mgr.impact_body]))
	bus.projectile_expired.connect(func(_caster: int, _position: Vector2, _tag: int, _shot: int) -> void:
		told.append([mgr.impact_form, mgr.impact_body]))


func test_a_still_shot_can_be_a_stone() -> void:
	var slot: int = mgr.spawn(0, Vector2(100, 100), Vector2.ZERO, 1.0, 5.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	check_equal(mgr._kind_of(slot), ManagerScript.KIND_RUNE, "a still shot is a rune by its motion")
	check(mgr.set_form(slot, &"wall", ManagerScript.KIND_STONE), "a card may name it")
	check_equal(mgr._kind_of(slot), ManagerScript.KIND_STONE, "and a still shot is then the stone it asks for")


func test_a_flying_shot_keeps_its_own_body() -> void:
	var slot: int = mgr.spawn(0, Vector2(100, 100), Vector2(50, 0), 1.0)
	mgr.set_form(slot, &"swap", ManagerScript.KIND_STONE)
	check_equal(mgr._kind_of(slot), ManagerScript.KIND_BOLT, "a stone is no body for a flying shot: a bolt's")


func test_a_reused_slot_forgets_its_card() -> void:
	var slot: int = mgr.spawn(0, Vector2(100, 100), Vector2.ZERO, 0.05, 5.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	mgr.set_form(slot, &"wall", ManagerScript.KIND_STONE)
	for _i in 10:
		mgr.step(DT)
	var again: int = mgr.spawn(0, Vector2(100, 100), Vector2.ZERO, 1.0, 5.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	check_equal(again, slot, "the same slot is taken again")
	check_equal(mgr._kind_of(again), ManagerScript.KIND_RUNE, "a rune again, not the stone before")
	check_equal(mgr._form_of(again), &"rune", "told by its body again")


func test_an_impact_is_told_as_the_card_with_its_body() -> void:
	mgr.set_walls([Rect2(150.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	var slot: int = mgr.spawn(0, Vector2(100, 100), Vector2(240, 0), 5.0)
	mgr.set_form(slot, &"nova")
	for _i in 30:
		mgr.step(DT)
	check_equal(told.size(), 2, "it ended on the wall: its impact, then its end")
	for each: Array in told:
		check_equal(each[0], &"nova", "told as the nova it is, not a bolt")
		check_equal(each[1], ManagerScript.KIND_BOLT, "with its bolt's body")
	check_equal(mgr.impact_form, &"", "nothing told outside the event")
	check_equal(mgr.impact_body, 0, "no body outside the event")


func test_a_shot_no_card_named_is_told_by_its_body() -> void:
	var slot: int = mgr.spawn(0, Vector2(100, 100), Vector2.ZERO, 0.05, 5.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	check(slot >= 0, "spawned")
	for _i in 10:
		mgr.step(DT)
	check_equal(told.size(), 1, "its life ran out")
	if not told.is_empty():
		check_equal(told[0][0], &"rune", "told as a rune, by its body")
		check_equal(told[0][1], ManagerScript.KIND_RUNE, "with a rune's body")


func test_set_form_refuses_an_empty_slot() -> void:
	check(not mgr.set_form(-1, &"bolt"), "no slot -1")
	check(not mgr.set_form(3, &"bolt"), "nor a slot with no shot")
