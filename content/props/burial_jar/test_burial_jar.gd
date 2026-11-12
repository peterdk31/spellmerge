extends "res://tests/support/suite.gd"
## The burial jar (props W9c, content/props/burial_jar): a lidded bone jar of 80 health, a void wisp
## seeping from its seal. A thaw on it (frost, then fire: Combat's reaction) or its death shatters
## it, and what was sealed in comes out: it casts Void · Pulse round itself. Its shards are walked
## over and never hit.
##
## godot --headless --path . --script res://content/props/burial_jar/test_burial_jar.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const PropNames := preload("res://tests/content/props/prop_names.gd")
const JAR: PropBase = preload("res://content/props/burial_jar/burial_jar.tres")

## Steps for its pulse to spread (0.4 s), and a few more.
const PULSE_STEPS: int = 10

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


func _jar() -> Actor:
	return _world.add(PropBody.make(JAR), Vector2(200, 200))


## A dummy that only stands and is hurt, `x` px right of the jar.
func _dummy(x: float) -> Actor:
	var body: Actor = _world.actor(Vector2(200.0 + x, 200.0), [&"health", &"hurtbox"], Fixture.Scripted.new())
	body.health.max_health = 1000.0
	body.health.reset(1000.0)
	return body


func test_it_is_sound() -> void:
	check_equal(JAR.problems(PropNames.known(_world.registry)), PackedStringArray(), "its data")
	check_equal(JAR.look_problems(), PackedStringArray(), "its looks")


func test_frost_then_fire_thaws_it_open() -> void:
	var jar: Actor = _jar()
	var near: Actor = _dummy(24.0)
	check_equal(_world.shoot(jar, &"fire").slice(0, 1), [&"fire"] as Array[StringName], "fire alone")
	check_equal(jar.state_triggers.state_id(), &"idle", "only scorches it")
	check(_world.combat.apply_status(ActorsScript.NONE, jar, &"chill", 3.0, 10.0), "chilled")
	check_equal(_world.shoot(jar, &"fire").slice(0, 1), [&"fire"] as Array[StringName], "then a fire hit")
	check_equal(jar.state_triggers.state_id(), &"shattered", "thaws it open")
	check_equal(_left.count(jar.caster_number()), 1, "what was sealed comes out")
	check(not jar.footprint.solid and not jar.hurtbox.registered, "its shards are walked over, never hit")
	_world.run(PULSE_STEPS)
	check(near.health.health < near.health.max_health, "its void pulse hurt what stood near")


func test_broken_it_shatters_too() -> void:
	var jar: Actor = _jar()
	_world.combat.hit(ActorsScript.NONE, jar, 50.0)
	check_equal(jar.state_triggers.state_id(), &"idle", "it holds")
	_world.combat.hit(ActorsScript.NONE, jar, 50.0)
	check_equal(jar.state_triggers.state_id(), &"shattered", "its health gone: shattered")
	check_equal(_left.count(jar.caster_number()), 1, "and what was sealed comes out, once")
