extends "res://tests/support/suite.gd"
## A swap with a prop (props W6, docs/milestones/props.md, "For W6"): the caster goes to the prop's
## place, on its ground, and the ground pushes it out; the prop, which never moves (no Mover), stays
## where it stood. Real wizard scene, real Spells and the `swap` card; a stand-in prop
## (`ActorFixture.prop_body`).
##
## godot --headless --path . --script res://tests/gameplay/actor/test_swap_prop.gd

const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const ActorFixture := preload("res://tests/gameplay/actor/actor_fixture.gd")

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_cap(512)


func after_each() -> void:
	_world.free_all()


func test_a_swap_with_a_prop_moves_only_the_caster_and_its_ground_pushes_it_out() -> void:
	var wizard: Actor = _world.wizard(0, Vector2.ZERO, [[&"swap"], [], [], []])
	var prop: Actor = ActorFixture.prop_body()
	prop.position = Vector2(0.0, 60.0)
	_world.add(prop)
	var stands: Vector2 = prop.global_position
	_world.hold(0, &"staff_1")
	_world.release(0, &"staff_1")
	_world.run(40)
	check_equal(prop.global_position, stands, "the prop stands where it stood")
	check(wizard.global_position.distance_to(stands) < 24.0, "the caster went to its place (%s)" % [wizard.global_position])
	check(not _world.projectiles.circle_blocked(wizard.global_position, wizard.wall_radius()), "and is pushed off its ground (%s)" % [wizard.global_position])
