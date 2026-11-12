extends "res://tests/support/suite.gd"
## The fire pit (props W9c, content/props/fire_pit): a ring of stones round crossed logs, on the
## floor, that nobody bumps into and nothing hurts. A fire hit lights it (flames, embers, light); a
## frost hit puts it out. It casts nothing yet: its fire was to be cast at whoever comes near, by a
## prop state event the owner put off (2026-11-12, "skip the prop near for now").
##
## godot --headless --path . --script res://content/props/fire_pit/test_fire_pit.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const PropNames := preload("res://tests/content/props/prop_names.gd")
const PIT: PropBase = preload("res://content/props/fire_pit/fire_pit.tres")

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root)


func after_each() -> void:
	_world.free_all()


## The look's nodes in `group`, still in the tree.
func _in_group(body: Actor, group: StringName) -> int:
	var count: int = 0
	for node in body.get_node("PropLook").get_children():
		if node.is_in_group(group) and not node.is_queued_for_deletion():
			count += 1
	return count


func test_it_is_sound() -> void:
	check_equal(PIT.problems(PropNames.known(_world.registry)), PackedStringArray(), "its data")
	check_equal(PIT.look_problems(), PackedStringArray(), "its looks")
	check(PIT.staffs.is_empty(), "it casts nothing yet")


func test_it_is_walked_over_and_lies_on_the_floor() -> void:
	var pit: Actor = _world.add(PropBody.make(PIT), Vector2(200, 200))
	check(not pit.footprint.solid, "nobody bumps into it")
	check(pit.hurtbox.is_on(), "but hits land on it")
	check(pit.health.invincible, "and hurt it not")
	check_equal((pit.get_node("Sprite") as Sprite2D).z_index, RoomBase.FLOOR_Z, "its ring on the floor")


func test_fire_lights_it_and_frost_puts_it_out() -> void:
	var pit: Actor = _world.add(PropBody.make(PIT), Vector2(200, 200))
	check_equal(_in_group(pit, LightSpot.GROUP), 0, "cold: no light")
	check_equal(_world.shoot(pit, &"frost").slice(0, 1), [&"frost"] as Array[StringName], "a frost hit")
	check_equal(pit.state_triggers.state_id(), &"unlit", "puts out nothing")
	check_equal(_world.shoot(pit, &"fire").slice(0, 1), [&"fire"] as Array[StringName], "a fire hit")
	check_equal(pit.state_triggers.state_id(), &"lit", "lights it")
	check_equal(_in_group(pit, LightSpot.GROUP), 1, "its light")
	check_equal(_in_group(pit, MoteSource.GROUP), 1, "its embers")
	check(not pit.footprint.solid, "lit, still walked over")
	check_equal(_world.shoot(pit, &"fire").slice(0, 1), [&"fire"] as Array[StringName], "more fire")
	check_equal(pit.state_triggers.state_id(), &"lit", "it burns on")
	check_equal(_world.shoot(pit, &"frost").slice(0, 1), [&"frost"] as Array[StringName], "a frost hit")
	check_equal(pit.state_triggers.state_id(), &"unlit", "puts it out")
	check_equal(_in_group(pit, LightSpot.GROUP), 0, "dark again")
