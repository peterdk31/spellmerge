extends "res://tests/support/suite.gd"
## The fountain (content/props/fountain): a stone basin with a spout that nothing hurts. Every
## 2.4 s in its `still` state (a `timer` row, on the simulation's clock) it wells up for 0.6 s (its
## first staff's wind-up, the telegraph: the water bulges out of its bowl, a closing ring), then
## bursts: Water · Nova · Spray, eight jets of water round it, and Water · Pulse, a ring that wets
## the floor round it. What its water hits is soaked, a burn on it put out. A prop with a timer row
## is stepped, so its pools refill and it bursts for ever; its casts are a quarter of their power
## (its stats), so a fountain soaks and shoves far more than it hurts.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const PropNames := preload("res://tests/content/props/prop_names.gd")
const FOUNTAIN: PropBase = preload("res://content/props/fountain/fountain.tres")

## Steps a second (the fixture's STEP is 1/16 s).
const PER_SECOND: int = 16
## Steps of one cycle: 2.4 s still, then 0.6 s welling.
const CYCLE: int = 48

var _world: Fixture
## The casts that left, as [caster number, staff].
var _left: Array = []
## The floor's touches, as [element, radius].
var _touched: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_cap(512)
	_left.clear()
	_touched.clear()
	_world.bus.cast_left.connect(func(caster: int, staff: int) -> void: _left.append([caster, staff]))
	_world.bus.floor_touched.connect(func(_caster: int, element: StringName, _at: Vector2, radius: float, _tag: int) -> void: _touched.append([element, radius]))


func after_each() -> void:
	_world.free_all()


func _fountain() -> Actor:
	return _world.add(PropBody.make(FOUNTAIN), Vector2(200, 200))


## The casts `fountain`'s staff `staff` (0 or 1) made.
func _casts(fountain: Actor, staff: int) -> int:
	return _left.count([fountain.caster_number(), staff])


## A dummy that only stands and is hurt, `x` px right of the fountain.
func _dummy(x: float) -> Actor:
	var body: Actor = _world.actor(Vector2(200.0 + x, 200.0), [&"health", &"hurtbox"], Fixture.Scripted.new())
	body.health.max_health = 1000.0
	body.health.reset(1000.0)
	return body


func test_it_is_sound() -> void:
	check_equal(FOUNTAIN.problems(PropNames.known(_world.registry)), PackedStringArray(), "its data")
	check_equal(FOUNTAIN.look_problems(), PackedStringArray(), "its looks")
	check(FOUNTAIN.role == &"", "no role: it stands in the hub's prop yard")


func test_it_keeps_time_so_it_is_stepped() -> void:
	var fountain: Actor = _fountain()
	check(fountain.state_triggers.keeps_time(), "a timer row: it keeps time")
	check(not fountain.is_still(), "so it is not still")
	check_equal(_world.table.still[fountain.id], 0, "and the actor table steps it")
	check(fountain.footprint.solid and fountain.health.invincible, "it stands in the way, and nothing hurts it")


func test_it_wells_up_then_bursts_on_its_timer() -> void:
	var fountain: Actor = _fountain()
	check_equal(fountain.state_triggers.state_id(), &"still", "it starts still")
	_world.run(2 * PER_SECOND)
	check_equal(fountain.state_triggers.state_id(), &"still", "still for two seconds")
	check_equal(_casts(fountain, 0), 0, "no burst yet")
	_world.run(PER_SECOND / 2)
	check_equal(fountain.state_triggers.state_id(), &"welling", "at 2.4 s it wells up")
	check(fountain.caster.is_winding(0), "its burst winds up: the telegraph")
	_world.run(PER_SECOND / 2)
	check_equal(_casts(fountain, 0), 1, "then the jets burst")
	check_equal(_casts(fountain, 1), 1, "and the spill with them")
	check_equal(fountain.state_triggers.state_id(), &"still", "and it is still again")


func test_it_bursts_for_ever_its_pools_refilling() -> void:
	var fountain: Actor = _fountain()
	_world.run(20 * CYCLE)
	check_equal(_casts(fountain, 0), 20, "twenty bursts in twenty cycles")
	check_equal(_casts(fountain, 1), 20, "and twenty spills")
	check_equal(fountain.state_triggers.state_id(), &"still", "still between bursts")


func test_its_water_soaks_and_puts_out_what_burns_round_it() -> void:
	var fountain: Actor = _fountain()
	var wet: Actor = _dummy(30.0)
	var burning: Actor = _dummy(-30.0)
	_world.combat.apply_status(-1, burning, &"burn", 30.0, 1.0)
	check(_world.combat.has_status(burning, &"burn"), "one dummy burns")
	# The burst at the cycle's end, and the 0.4 s its spill's ring grows.
	_world.run(CYCLE + 10)
	check(_world.combat.has_status(wet, &"soak"), "the burst soaked what stood by it")
	check(not _world.combat.has_status(burning, &"burn"), "and put the burning one out")
	check(wet.health.health > wet.health.max_health - 2.0, "it barely hurts (%s lost)" % (wet.health.max_health - wet.health.health))
	check(_touched.any(func(row: Array) -> bool: return row[0] == &"water" and float(row[1]) > 24.0), "its spill's water touched the floor round it: %s" % [_touched])


func test_a_lit_barrel_by_it_is_doused() -> void:
	var fountain: Actor = _fountain()
	var barrel: Actor = _world.add(PropBody.make(load("res://content/props/exploding_barrel/exploding_barrel.tres") as PropBase), Vector2(164, 200))
	_world.run(CYCLE - 10)
	_world.shoot(barrel, &"fire")
	check_equal(barrel.state_triggers.state_id(), &"fusing", "a fire hit lights the barrel's fuse, just before a burst")
	_world.run(12)
	check(is_instance_valid(fountain), "the fountain stands")
	check_equal(barrel.state_triggers.state_id(), &"idle", "its water put the fuse out before it blew")


func _areas() -> Dictionary:
	var areas: Dictionary = {"Actors": _world.table, "Projectiles": _world.projectiles, "Spells": _world.spells, "Combat": _world.combat}
	for body in _world.actors:
		if is_instance_valid(body) and body.is_inside_tree() and body.id != ActorsScript.NONE:
			areas["actor %d" % body.id] = body
	return areas


func test_a_snapshot_keeps_its_clock() -> void:
	var fountain: Actor = _fountain()
	_world.run(PER_SECOND)
	var snapshot := Snapshot.take(_areas(), root)
	check_equal(snapshot.problems, PackedStringArray(), "taken without problems")
	_world.run(CYCLE)
	check_equal(_casts(fountain, 0), 1, "it burst")
	check_equal(snapshot.restore(_areas(), root, _world.prepare), PackedStringArray(), "restored without problems")
	check_equal(fountain.state_triggers.clock, 1.0, "its clock as it was")
	_world.run(CYCLE - PER_SECOND - 1)
	check_equal(_casts(fountain, 0), 1, "not yet again a step early")
	_world.run(1)
	check_equal(_casts(fountain, 0), 2, "and again at the same step")
