extends "res://tests/support/suite.gd"
## The dust heap (boss plan OB5, content/props/dust_heap): a mound of swept-up dust that stands in the
## way and no hit hurts. A body walking into it scatters it (the `touched` trigger: a flat spread
## on the floor that blocks no more and stays where it is); fire on the heap or on the scattered dust
## blows it up (Fire · Blast · Pulse, hurting everything near) and leaves a scorch mark. The trigger's
## own rules: tests/gameplay/actor/test_prop_state_triggers.gd ("Touched").
##
## godot --headless --path . --script res://content/props/dust_heap/test_dust_heap.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const PropNames := preload("res://tests/content/props/prop_names.gd")
const HEAP: PropBase = preload("res://content/props/dust_heap/dust_heap.tres")

## Steps for a blast to go off and land.
const BLAST_STEPS: int = 20

var _world: Fixture
## The casts that left, by caster number.
var _left: Array[int] = []


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_cap(512)
	_left.clear()
	_world.bus.cast_left.connect(func(caster: int, _staff: int) -> void: _left.append(caster))


func after_each() -> void:
	_world.free_all()


func _heap(at: Vector2 = Vector2(200, 200)) -> Actor:
	return _world.add(PropBody.make(HEAP), at)


func _state(body: Actor) -> StringName:
	return body.state_triggers.state_id()


## A dummy that only stands and is hurt, `x` px right of the heap.
func _dummy(x: float) -> Actor:
	var body: Actor = _world.actor(Vector2(200.0 + x, 200.0), [&"health", &"hurtbox"], Fixture.Scripted.new())
	body.health.max_health = 1000.0
	body.health.reset(1000.0)
	return body


## A body walking right from `x` px left of the heap, stepped and moved `steps` times (the Tick's
## `tick_step`, so it touches what it overlaps).
func _walk_in(x: float, steps: int) -> Actor:
	var controller := Fixture.Scripted.new()
	controller.move = Vector2.RIGHT
	var walker: Actor = _world.actor(Vector2(200.0 - x, 200.0), [&"mover"], controller)
	for i in steps:
		walker.step(Fixture.STEP)
		walker.move(Fixture.STEP)
	return walker


func test_it_is_sound() -> void:
	check_equal(HEAP.problems(PropNames.known(_world.registry)), PackedStringArray(), "its data")
	check_equal(HEAP.look_problems(), PackedStringArray(), "its looks")
	check(HEAP.area_rect().encloses(HEAP.ground_rect().grow(4.0)), "its area reaches past its ground, so a body stopped by it touches it")


func test_a_body_walking_into_it_scatters_it() -> void:
	var heap: Actor = _heap()
	check(heap.footprint.solid and heap.hurtbox.is_on(), "a heap stands in the way and is hit")
	_walk_in(60.0, 3)
	check_equal(_state(heap), &"heap", "a body on its way: whole")
	_walk_in(60.0, 20)
	check_equal(_state(heap), &"scattered", "walked into: scattered")
	check(not heap.footprint.solid, "it blocks no more")
	check(heap.hurtbox.registered, "and fire still finds it")
	check(not heap.is_dying(), "it stays where it is")
	check_equal(_world.table.touch_area_of(heap.id), Rect2(), "scattered, it hears no touch")
	check(_left.is_empty(), "walking into it blows nothing up")


func test_fire_on_the_heap_blows_it_up() -> void:
	var heap: Actor = _heap()
	var near: Actor = _dummy(24.0)
	check_equal(_world.shoot(heap, &"fire").slice(0, 1), [&"fire"] as Array[StringName], "a fire hit")
	check_equal(_state(heap), &"burnt", "it blew")
	check(not heap.footprint.solid and not heap.hurtbox.registered, "a scorch mark: walked over, never hit")
	_world.run(BLAST_STEPS)
	check_equal(_left.count(heap.caster_number()), 1, "once")
	check(near.health.health < near.health.max_health, "hurting what stood near")


func test_fire_on_the_scattered_dust_blows_it_up() -> void:
	var heap: Actor = _heap()
	check(heap.state_triggers.enter(&"scattered"), "scattered")
	var near: Actor = _dummy(24.0)
	_world.shoot(heap, &"fire")
	check_equal(_state(heap), &"burnt", "it blew")
	_world.run(BLAST_STEPS)
	check_equal(_left.count(heap.caster_number()), 1, "once")
	check(near.health.health < near.health.max_health, "hurting what stood near")


func test_a_burn_put_on_it_blows_it_up() -> void:
	var heap: Actor = _heap()
	check(heap.state_triggers.enter(&"scattered"), "scattered")
	check(_world.combat.apply_status(ActorsScript.NONE, heap, &"burn", 3.0, 1.0), "a burning patch's burn")
	check_equal(_state(heap), &"burnt", "it blew")
	check_equal(_left.count(heap.caster_number()), 1, "once")


func test_other_hits_leave_it_be() -> void:
	var heap: Actor = _heap()
	_world.shoot(heap, &"")
	_world.combat.hit(ActorsScript.NONE, heap, 100.0)
	check_equal(_state(heap), &"heap", "a plain hit: still a heap")
	check_equal(heap.health.health, heap.health.max_health, "no hit hurts it")


func test_one_heap_sets_off_the_next() -> void:
	var first: Actor = _heap()
	var second: Actor = _heap(Vector2(224, 200))
	_world.shoot(first, &"fire")
	_world.run(BLAST_STEPS)
	check_equal(_state(second), &"burnt", "the blast's fire blew the heap beside it")
	check_equal(_left.count(first.caster_number()) + _left.count(second.caster_number()), 2, "each once")
