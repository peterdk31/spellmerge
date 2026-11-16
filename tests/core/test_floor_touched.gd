extends "res://tests/support/suite.gd"
## Where an element touches the floor (ground cover GC5, rule 5, core/spells): `floor_touched`, one
## event an element of the spell, in its infusions' order, where a shot ends (a hit that spends it,
## its life; with its radius), where a blast goes off (with the blast's radius, not twice, for a shot
## or a ring), as a pool lies, on each of its ticks and as it ends, and where a pulse's ring goes off
## (at its widest: a returning ring where it turns home); never by a shot in flight, and never by a
## spell of no element.
##
## godot --headless --path . --script res://tests/core/test_floor_touched.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")

var _world: Fixture
## Every `floor_touched` heard: [caster, element, at, radius].
var _touched: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_cap(512)
	_touched.clear()
	_world.bus.floor_touched.connect(func(caster: int, element: StringName, at: Vector2, radius: float) -> void: _touched.append([caster, element, at, radius]))


func after_each() -> void:
	_world.free_all()


## A caster at (100, 100) aiming right with `cards` on its one staff, cast once.
func _cast(cards: Array[StringName]) -> Actor:
	var caster: Actor = _world.actor(Vector2(100.0, 100.0), [&"caster"], Fixture.Scripted.new(), [cards])
	caster.aim = Vector2.RIGHT
	check(caster.caster.cast(0), "cast %s" % [cards])
	return caster


func _elements() -> Array[StringName]:
	var found: Array[StringName] = []
	for heard: Array in _touched:
		found.append(heard[1])
	return found


func test_a_fire_bolt_touches_where_it_ends_on_a_body() -> void:
	var body: Actor = _world.prop(Vector2(220.0, 100.0))
	check_equal(_world.shoot(body, &"fire").slice(0, 1), [&"fire"] as Array[StringName], "it hit")
	check_equal(_elements(), [&"fire"] as Array[StringName], "once, its fire")
	check(absf((_touched[0][2] as Vector2).x - 220.0) < 24.0, "where it hit (%s)" % _touched[0][2])
	check(float(_touched[0][3]) > 0.0 and float(_touched[0][3]) < 16.0, "within the shot's radius (%s)" % _touched[0][3])


func test_a_shot_in_flight_touches_nothing() -> void:
	var caster: Actor = _cast([&"fire", &"bolt"])
	_world.run(4)
	check(_touched.is_empty(), "in flight: nothing")
	_world.run(120)
	check_equal(_touched.size(), 1, "then once, where it ended")
	check_equal(_touched[0][0], caster.caster_number(), "by its caster")


func test_a_bolt_running_out_touches_where_it_ends() -> void:
	_cast([&"fire", &"bolt"])
	_world.run(120)
	check_equal(_elements(), [&"fire"] as Array[StringName], "once, as its life ran out")
	check((_touched[0][2] as Vector2).x > 140.0, "far along its way")


func test_a_plain_bolt_touches_nothing() -> void:
	_cast([&"bolt"])
	_world.run(120)
	check(_touched.is_empty(), "no element: nothing")


func test_each_element_touches_in_its_infusions_order() -> void:
	_cast([&"frost", &"fire", &"bolt"])
	_world.run(120)
	check_equal(_elements(), [&"frost", &"fire"] as Array[StringName], "one event an element, in order")


func test_a_blast_touches_with_its_radius_once() -> void:
	_cast([&"fire", &"blast", &"bolt"])
	_world.run(120)
	check_equal(_elements(), [&"fire"] as Array[StringName], "once: the blast, not the shot's end too")
	check(float(_touched[0][3]) >= 16.0, "the blast's radius (%s)" % _touched[0][3])


func test_a_pool_touches_as_it_lies_and_on_each_tick() -> void:
	_cast([&"fire", &"pool"])
	_world.run(1)
	check_equal(_touched.size(), 1, "as it lies")
	var at: Vector2 = _touched[0][2]
	# The fixture's step is a sixteenth of a second: the pool's half-second tick is 8 of them.
	_world.run(int(ceil(SpellLimits.POOL_TICK / Fixture.STEP)) + 1)
	check_equal(_touched.size(), 2, "again on its tick")
	check(at.distance_to(_touched[1][2]) < 1.0, "where it lies")


func test_a_pulse_touches_where_its_ring_goes_off() -> void:
	_cast([&"fire", &"pulse"])
	_world.run(80)
	check_equal(_elements(), [&"fire"] as Array[StringName], "once")
	check(float(_touched[0][3]) > 16.0, "as wide as its ring (%s)" % _touched[0][3])


func test_a_pulse_with_a_blast_touches_once_as_its_blast() -> void:
	_cast([&"fire", &"blast", &"pulse"])
	_world.run(80)
	check_equal(_elements(), [&"fire"] as Array[StringName], "once: the blast, not the ring too")


func test_a_returning_pulse_touches_once_where_it_turns_home() -> void:
	_cast([&"fire", &"return", &"pulse"])
	_world.run(120)
	check_equal(_elements(), [&"fire"] as Array[StringName], "once, where it was widest")
	check(float(_touched[0][3]) > 16.0, "as wide as its ring then (%s)" % _touched[0][3])


func test_a_pools_end_touches_where_it_lay() -> void:
	_cast([&"fire", &"pool"])
	_world.run(1)
	var at: Vector2 = _touched[0][2]
	_world.run(200)
	check(_world.spells.carrier(&"pool").call(&"pool_count") == 0, "it ran out")
	var last: Array = _touched[_touched.size() - 1]
	check(at.distance_to(last[2]) < 1.0, "its last touch where it lay")
