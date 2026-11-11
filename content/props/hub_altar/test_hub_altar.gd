extends "res://tests/support/suite.gd"
## The hub's multiplayer altar (props W8, content/props/hub_altar): a dais on the floor that nobody
## bumps into and no hit lands on, in one state. Standing on it is Flow's (`RoomBase.altar`).
##
## godot --headless --path . --script res://content/props/hub_altar/test_hub_altar.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ALTAR: PropBase = preload("res://content/props/hub_altar/hub_altar.tres")

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root)


func after_each() -> void:
	_world.free_all()


func test_it_is_walked_onto_and_never_hit() -> void:
	var body: Actor = _world.add(PropBody.make(ALTAR), Vector2(200, 200))
	check(body.is_still(), "it stands still, never stepped")
	check(not body.hurtbox.is_on(), "no hit lands on it")
	check(not body.footprint.solid, "nobody bumps into it")
	check(body.health.invincible, "invincible all the same")
	check_equal(ALTAR.states.list.size(), 1, "one state")
	var sprite := body.get_node("Sprite") as Sprite2D
	check_equal(sprite.texture, ALTAR.looks[0].layers[0].texture, "its dais drawn")
	check_equal(sprite.z_index, RoomBase.FLOOR_Z, "on the floor")
