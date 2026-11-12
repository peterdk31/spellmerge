extends "res://tests/support/suite.gd"
## The crate (props W9c, content/props/crate): a plank crate of 30 health that stands in the way and
## casts nothing. A hit below half its health cracks it (a split plank, grit trickling); its death
## breaks it to rubble that nothing bumps into or hits, dust rising for its first seconds.
##
## godot --headless --path . --script res://content/props/crate/test_crate.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const PropNames := preload("res://tests/content/props/prop_names.gd")
const CRATE: PropBase = preload("res://content/props/crate/crate.tres")

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root)


func after_each() -> void:
	_world.free_all()


func _crate() -> Actor:
	return _world.add(PropBody.make(CRATE), Vector2(200, 200))


func test_it_is_sound() -> void:
	check_equal(CRATE.problems(PropNames.known(_world.registry)), PackedStringArray(), "its data")
	check_equal(CRATE.look_problems(), PackedStringArray(), "its looks")
	check(CRATE.staffs.is_empty(), "it casts nothing")


func test_it_cracks_below_half_then_breaks_to_rubble() -> void:
	var crate: Actor = _crate()
	check(crate.footprint.solid and crate.hurtbox.is_on(), "it stands in the way and is hit")
	_world.combat.hit(ActorsScript.NONE, crate, 10.0)
	check_equal(crate.state_triggers.state_id(), &"idle", "a first hit: whole")
	_world.combat.hit(ActorsScript.NONE, crate, 10.0)
	check_equal(crate.state_triggers.state_id(), &"cracked", "below half: cracked")
	check(crate.footprint.solid, "still in the way")
	_world.combat.hit(ActorsScript.NONE, crate, 10.0)
	check_equal(crate.state_triggers.state_id(), &"broken", "its health gone: broken")
	check(not crate.footprint.solid and not crate.hurtbox.registered, "rubble: walked over, never hit")
	check(not crate.is_dying(), "it stays, as rubble")


func test_one_hit_through_both_breaks_it() -> void:
	var crate: Actor = _crate()
	_world.combat.hit(ActorsScript.NONE, crate, 100.0)
	check_equal(crate.state_triggers.state_id(), &"broken", "cracked, then broken by the same hit")


func test_a_fire_bolt_hits_it() -> void:
	var crate: Actor = _crate()
	check_equal(_world.shoot(crate, &"fire").slice(0, 1), [&"fire"] as Array[StringName], "a shot lands on its box")
	check(crate.health.health < crate.health.max_health, "and hurts it")
