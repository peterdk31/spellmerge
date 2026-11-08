extends "res://tests/support/suite.gd"
## What a shot is drawn as and told as (`Projectiles.set_form`): every shot a card fired carries the
## card's id, so its impacts and its end are told as that card (`impact_form`, its card's impact
## look), and the body (`impact_body`) goes with them. A still shot may ask for a card's own body
## (a shader `register_body` numbered: a wall's stone), drawn by that shader's pair of batches; it
## is still a rune to the world, and a flying shot keeps its own batch. The manager is stepped by
## hand.
##
## godot --headless --path . --script res://tests/core/test_projectile_bodies.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const WarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const STONE: Shader = preload("res://content/spells/forms/wall/stone.gdshader")
const POOL: Shader = preload("res://content/spells/forms/pool/pool.gdshader")

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


func test_a_card_shader_is_numbered_once_and_given_a_pair_of_batches() -> void:
	check_equal(mgr.register_body(null), 0, "no shader is no body")
	var stone: int = mgr.register_body(STONE)
	check_equal(stone, 1, "the first shader is body 1")
	check_equal(mgr.register_body(STONE), stone, "asked again, the same body")
	check_equal(mgr.register_body(POOL), 2, "another is the next")
	check(mgr.body_shader(stone) == STONE, "a body knows its shader")
	check(WarmupScript._wanted.has(STONE) and WarmupScript._wanted.has(POOL), "both are warmed before the first room")
	check(ManagerScript.batch_on_enemy_layer(ManagerScript.body_batch(stone, true)) and not ManagerScript.batch_on_enemy_layer(ManagerScript.body_batch(stone, false)), "its pair: the hat ramps', then the enemy ramp's a layer up")
	check_equal(ManagerScript.batch_mesh(ManagerScript.body_batch(stone, false)), -1, "one quad a shot, as a rune")
	check_equal(mgr.batch_count(), ManagerScript.BATCH_BODY_FIRST + 4, "two bodies: the first five batches and two pairs")


func test_there_is_no_fixed_number_of_bodies() -> void:
	var grown: Array[int] = []
	mgr.batches_grown.connect(func(count: int) -> void: grown.append(count))
	for n in 20:
		var shader := Shader.new()
		shader.code = "shader_type canvas_item;\n// body %d\n" % n
		check_equal(mgr.register_body(shader), n + 1, "body %d is numbered" % (n + 1))
	check_equal(mgr.batch_count(), ManagerScript.BATCH_BODY_FIRST + 40, "each with its own pair of batches")
	check_equal(grown.size(), 20, "each told (batches_grown)")
	check_equal(grown[19], mgr.batch_count(), "with the count in all")


func test_a_still_shot_of_a_card_body_draws_in_its_batch() -> void:
	var stone: int = mgr.register_body(STONE)
	var slot: int = mgr.spawn(0, Vector2(100, 100), Vector2.ZERO, 1.0, 5.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	check_equal(mgr._batch_of(slot), ManagerScript.BATCH_ENEMY_RUNE, "a still shot of no actor is a rune of the enemy ramp")
	check(mgr.set_form(slot, &"wall", stone), "a card may name its body")
	check_equal(mgr._batch_of(slot), ManagerScript.body_batch(stone, true), "and it draws in that body's batch")
	check_equal(mgr._kind_of(slot), ManagerScript.KIND_RUNE, "still a rune to the world")


func test_a_flying_shot_keeps_its_own_batch() -> void:
	var stone: int = mgr.register_body(STONE)
	var slot: int = mgr.spawn(0, Vector2(100, 100), Vector2(50, 0), 1.0)
	mgr.set_form(slot, &"swap", stone)
	check_equal(mgr._batch_of(slot), ManagerScript.BATCH_ENEMY, "a card body draws only a still shot")
	check_equal(mgr._kind_of(slot), ManagerScript.KIND_BOLT, "a bolt's body")


func test_a_reused_slot_forgets_its_card() -> void:
	var stone: int = mgr.register_body(STONE)
	var slot: int = mgr.spawn(0, Vector2(100, 100), Vector2.ZERO, 0.05, 5.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	mgr.set_form(slot, &"wall", stone)
	for _i in 10:
		mgr.step(DT)
	var again: int = mgr.spawn(0, Vector2(100, 100), Vector2.ZERO, 1.0, 5.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	check_equal(again, slot, "the same slot is taken again")
	check_equal(mgr._batch_of(again), ManagerScript.BATCH_ENEMY_RUNE, "a rune again, not the stone before")
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
