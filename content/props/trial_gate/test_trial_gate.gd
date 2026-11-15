extends "res://tests/support/suite.gd"
## The hub's trial gate (boss OB2, content/props/trial_gate): a slab on the floor that nobody bumps
## into and no hit lands on, dark until the hub's rules light it (`HubRules.LIT` while every wizard
## stands in it and all of them picked the same room, `HubRules.UNLIT` otherwise); lit, its archway
## and runes glow, give off embers and light.
##
## godot --headless --path . --script res://content/props/trial_gate/test_trial_gate.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const GATE: PropBase = preload("res://content/props/trial_gate/trial_gate.tres")

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


func test_it_is_the_hubs_trial_gate_walked_onto_and_never_hit() -> void:
	check_equal(GATE.role, HubRules.ROLE_TRIAL_GATE, "the hub's rules know it as the trial gate")
	var body: Actor = _world.add(PropBody.make(GATE), Vector2(200, 200))
	check(body.is_still(), "it stands still, never stepped")
	check(not body.hurtbox.is_on(), "no hit lands on it")
	check(not body.footprint.solid, "nobody bumps into it")
	check(body.health.invincible, "invincible all the same")
	check_equal(body.state_triggers.state_id(), HubRules.UNLIT, "dark at first")
	check_equal((body.get_node("Sprite") as Sprite2D).z_index, RoomBase.FLOOR_Z, "on the floor")


func test_it_lights_and_goes_out() -> void:
	var body: Actor = _world.add(PropBody.make(GATE), Vector2(200, 200))
	check_equal(_in_group(body, MoteSource.GROUP) + _in_group(body, LightSpot.GROUP), 0, "dark: no motes, no light")
	check(body.state_triggers.enter(HubRules.LIT), "lit")
	check_equal(_in_group(body, MoteSource.GROUP), 1, "its doorway gives off embers")
	check_equal(_in_group(body, LightSpot.GROUP), 1, "and light")
	check(not body.hurtbox.is_on() and not body.footprint.solid, "lit, still walked onto")
	check(body.state_triggers.enter(HubRules.UNLIT), "out")
	check_equal(_in_group(body, MoteSource.GROUP) + _in_group(body, LightSpot.GROUP), 0, "dark again")


## Self-contained (props W8c): where it is stood in is its own area, a 96×96 box round its feet,
## and its art lies on it in every state.
func test_it_is_stood_in_where_its_art_lies() -> void:
	var ground: Rect2 = GATE.area_rect()
	check_equal(ground, Rect2(-48, -48, 96, 96), "a 96 px box round its feet: room for four")
	for state in GATE.states.list:
		check(not state.blocks, "%s: nobody bumps into it" % state.state_id)
		for layer in GATE.look_of(state.state_id).layers:
			var size := Vector2(layer.frame_size())
			check_equal(Rect2(layer.drawn_at() - size * 0.5, size), ground, "%s: its art on its area" % state.state_id)
