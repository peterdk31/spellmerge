extends "res://tests/support/suite.gd"
## The dust heap (boss plan OB5, content/props/dust_heap): a mound of swept-up dust that stands in the
## way and no hit hurts. A body walking into it scatters it (the `touched` trigger: a flat spread
## on the floor that blocks no more and stays where it is); fire on the heap or on the scattered dust
## blows it up (Fire · Blast · Pulse, hurting everything near) and leaves a scorch mark. The trigger's
## own rules: tests/gameplay/actor/test_prop_state_triggers.gd ("Touched").
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
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


## A body walking along `way` from `from` (the heap's feet at 200, 200).
func _walker(from: Vector2, way: Vector2) -> Actor:
	var controller := Fixture.Scripted.new()
	controller.move = way
	return _world.actor(from, [&"mover"], controller)


## `steps` of the Tick's own step of `walker` (its step, then its move: it touches what it overlaps).
func _walk(walker: Actor, steps: int) -> void:
	for i in steps:
		walker.tick_step(Fixture.STEP)


func test_it_is_sound() -> void:
	check_equal(HEAP.problems(PropNames.known(_world.registry)), PackedStringArray(), "its data")
	check_equal(HEAP.look_problems(), PackedStringArray(), "its looks")
	# The ground cells laid are those whose centres lie in its ground: up to half a cell past it.
	check(HEAP.area_rect().encloses(HEAP.ground_rect().grow(ProjectilesScript.WALL_CELL * 0.5)), "its area reaches past its ground, so a body stopped by it touches it")


func test_a_body_walking_into_it_scatters_it() -> void:
	var heap: Actor = _heap()
	check(heap.footprint.solid and heap.hurtbox.is_on(), "a heap stands in the way and is hit")
	var walker: Actor = _walker(Vector2(140.0, 200.0), Vector2.RIGHT)
	_walk(walker, 3)
	check_equal(_state(heap), &"heap", "a body on its way: whole")
	_walk(walker, 20)
	check_equal(_state(heap), &"scattered", "walked into: scattered")
	check(not heap.footprint.solid, "it blocks no more")
	check(heap.hurtbox.registered, "and fire still finds it")
	check(not heap.is_dying(), "it stays where it is")
	check_equal(_world.table.touch_area_of(heap.id), Rect2(), "scattered, it hears no touch")
	check(_left.is_empty(), "walking into it blows nothing up")


## A body its ground stops still touches it, from any side and any place against the 8 px cells
## its ground is laid in (its area reaches past them): straight in from off the grid, and slanting.
func test_a_body_its_ground_stops_still_scatters_it() -> void:
	var starts: Array[Vector2] = [Vector2(140.0, 203.0), Vector2(197.0, 150.0), Vector2(259.0, 196.0), Vector2(203.0, 240.0), Vector2(150.0, 160.0)]
	var ways: Array[Vector2] = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2(1.0, 1.0).normalized()]
	for i in starts.size():
		var heap: Actor = _heap()
		var walker: Actor = _walker(starts[i], ways[i])
		var blocked: bool = false
		for step in 40:
			var was: Vector2 = walker.global_position
			_walk(walker, 1)
			if _state(heap) != &"heap":
				break
			blocked = blocked or walker.global_position.is_equal_approx(was)
		check_equal(_state(heap), &"scattered", "from %s along %s" % [starts[i], ways[i]])
		check(not blocked, "touched before its ground held the body still (%s)" % starts[i])
		_world.actors.erase(heap)
		heap.free()
		_world.actors.erase(walker)
		walker.free()


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


## Its sounds (boss plan OB15): each state it breaks into plays its cue, naming its sound.
func test_its_sounds() -> void:
	var registry: Node = root.get_node("Registry")
	var scattered: CueBase = registry.get_resource(&"cues", HEAP.look_of(&"scattered").cue) as CueBase
	check(scattered != null and scattered.sound == &"dust_scatter", "its scattered state sounds dust_scatter as it is entered (boss plan OB15)")
	check_equal(HEAP.look_of(&"burnt").cue, &"", "its burnt state plays no cue of its own: its blast's fireball booms (the owner, 2026-11-18: one explosion sound, the blast's)")
