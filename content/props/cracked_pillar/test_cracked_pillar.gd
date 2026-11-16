extends "res://tests/support/suite.gd"
## The cracked pillar (boss plan OB5, content/props/cracked_pillar): a tall stone pillar of 32 health
## that stands in the way and casts nothing: cover. A hit below half its health cracks it (a crack
## down its shaft, grit trickling); its death brings it down to rubble that nothing bumps into or
## hits, dust rising for its first seconds.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const PropNames := preload("res://tests/content/props/prop_names.gd")
const PILLAR: PropBase = preload("res://content/props/cracked_pillar/cracked_pillar.tres")

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root)


func after_each() -> void:
	_world.free_all()


func _pillar() -> Actor:
	return _world.add(PropBody.make(PILLAR), Vector2(200, 200))


func test_it_is_sound() -> void:
	check_equal(PILLAR.problems(PropNames.known(_world.registry)), PackedStringArray(), "its data")
	check_equal(PILLAR.look_problems(), PackedStringArray(), "its looks")
	check(PILLAR.staffs.is_empty(), "it casts nothing")


func test_it_cracks_below_half_then_falls_to_rubble() -> void:
	var pillar: Actor = _pillar()
	check(pillar.footprint.solid and pillar.hurtbox.is_on(), "it stands in the way and is hit")
	_world.combat.hit(ActorsScript.NONE, pillar, 12.0)
	check_equal(pillar.state_triggers.state_id(), &"intact", "a first hit: whole")
	_world.combat.hit(ActorsScript.NONE, pillar, 8.0)
	check_equal(pillar.state_triggers.state_id(), &"cracked", "below half: cracked")
	check(pillar.footprint.solid and pillar.hurtbox.is_on(), "still cover")
	_world.combat.hit(ActorsScript.NONE, pillar, 12.0)
	check_equal(pillar.state_triggers.state_id(), &"rubble", "its health gone: rubble")
	check(not pillar.footprint.solid and not pillar.hurtbox.registered, "rubble: walked over, never hit")
	check(not pillar.is_dying(), "it stays, as rubble")


func test_one_hit_through_both_brings_it_down() -> void:
	var pillar: Actor = _pillar()
	_world.combat.hit(ActorsScript.NONE, pillar, 100.0)
	check_equal(pillar.state_triggers.state_id(), &"rubble", "cracked, then down by the same hit")


func test_spells_chip_it() -> void:
	var pillar: Actor = _pillar()
	check_equal(_world.shoot(pillar, &"fire").slice(0, 1), [&"fire"] as Array[StringName], "a shot lands on its box")
	check(pillar.health.health < pillar.health.max_health, "and chips it")


## Its sounds (boss plan OB15): each state it breaks into plays its cue, naming its sound.
func test_its_sounds() -> void:
	var registry: Node = root.get_node("Registry")
	var cracked: CueBase = registry.get_resource(&"cues", PILLAR.look_of(&"cracked").cue) as CueBase
	check(cracked != null and cracked.sound == &"pillar_crack", "its cracked state sounds pillar_crack as it is entered (boss plan OB15)")
	var rubble: CueBase = registry.get_resource(&"cues", PILLAR.look_of(&"rubble").cue) as CueBase
	check(rubble != null and rubble.sound == &"pillar_break", "its rubble state sounds pillar_break as it is entered (boss plan OB15)")
