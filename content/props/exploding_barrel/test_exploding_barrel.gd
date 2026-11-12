extends "res://tests/support/suite.gd"
## The exploding barrel (props W9c, content/props/exploding_barrel): a powder keg of 10 health. A
## fire hit lights its fuse (sparks off its tip, a ring closing in for its second: its fuse staff's
## wind-up and `wind_cue`), then it blows (Fire · Blast · Pulse) and lies as rubble; shot apart, lit
## or not, it blows at once and its fuse is over. Every path, possession and chains:
## tests/gameplay/actor/test_prop_state_triggers.gd, which plays this barrel.
##
## godot --headless --path . --script res://content/props/exploding_barrel/test_exploding_barrel.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const PropNames := preload("res://tests/content/props/prop_names.gd")
const BARREL: PropBase = preload("res://content/props/exploding_barrel/exploding_barrel.tres")

## Steps of its fuse (1 s), and a few more.
const FUSE_STEPS: int = 20

var _world: Fixture
## The casts that left, by caster number.
var _left: Array[int] = []
## The cues of the wind-ups started.
var _winds: Array[StringName] = []


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_cap(512)
	_left.clear()
	_winds.clear()
	_world.bus.cast_left.connect(func(caster: int, _staff: int) -> void: _left.append(caster))
	_world.bus.cast_winding.connect(func(_caster: int, _staff: int, _card: StringName, _origin: Vector2, _dir: Vector2, _seconds: float, _tint: Color, _look: int, _tag: int, cue: StringName) -> void: _winds.append(cue))


func after_each() -> void:
	_world.free_all()


func _barrel() -> Actor:
	return _world.add(PropBody.make(BARREL), Vector2(200, 200))


## A dummy that only stands and is hurt, `x` px right of the barrel.
func _dummy(x: float) -> Actor:
	var body: Actor = _world.actor(Vector2(200.0 + x, 200.0), [&"health", &"hurtbox"], Fixture.Scripted.new())
	body.health.max_health = 1000.0
	body.health.reset(1000.0)
	return body


func test_it_is_sound() -> void:
	check_equal(BARREL.problems(PropNames.known(_world.registry)), PackedStringArray(), "its data")
	check_equal(BARREL.look_problems(), PackedStringArray(), "its looks")


func test_fire_lights_its_fuse_and_it_blows() -> void:
	var barrel: Actor = _barrel()
	var near: Actor = _dummy(24.0)
	check_equal(_world.shoot(barrel, &"fire").slice(0, 1), [&"fire"] as Array[StringName], "a fire hit")
	check_equal(barrel.state_triggers.state_id(), &"fusing", "lights its fuse")
	check_equal(_winds, [&"wind_area"] as Array[StringName], "its ring closes in as its fuse burns")
	_world.run(FUSE_STEPS)
	check_equal(barrel.state_triggers.state_id(), &"broken", "then it blew")
	check_equal(_left.count(barrel.caster_number()), 1, "once")
	check(near.health.health < near.health.max_health, "hurting what stood near")


## Shot apart while lit it blows at once, and its fuse's wind-up is over, so the ring Feel shows for
## it ends too (gameplay/feel reads `Spells.is_winding`: tests/gameplay/feel/test_feel_carrier_cues.gd).
func test_shot_apart_while_lit_it_blows_at_once_and_its_fuse_is_over() -> void:
	var barrel: Actor = _barrel()
	_world.shoot(barrel, &"fire")
	check(_world.spells.is_winding(barrel.caster_number(), 0), "its fuse winds")
	_world.combat.hit(ActorsScript.NONE, barrel, 100.0)
	check_equal(barrel.state_triggers.state_id(), &"broken", "blown at once")
	check_equal(_left.count(barrel.caster_number()), 1, "its blast")
	check(not _world.spells.is_winding(barrel.caster_number(), 0), "and its fuse is over")
	_world.run(FUSE_STEPS)
	check_equal(_left.count(barrel.caster_number()), 1, "it never blows twice")
