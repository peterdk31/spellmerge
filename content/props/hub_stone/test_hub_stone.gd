extends "res://tests/support/suite.gd"
## The hub's teleporter stone (props W8, content/props/hub_stone): a slab on the floor that nobody
## bumps into and no hit lands on, dark until Flow lights it (`Flow.STONE_LIT` as every wizard
## stands on it, `STONE_UNLIT` as one steps off); lit, its runes glow, give off glimmers and light,
## and the stone's cue plays.
##
## godot --headless --path . --script res://content/props/hub_stone/test_hub_stone.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const STONE: PropBase = preload("res://content/props/hub_stone/hub_stone.tres")

var _world: Fixture
var _cues: Array[StringName] = []


func before_each() -> void:
	_world = Fixture.new(root)
	_cues.clear()
	_world.bus.cue_shown.connect(func(_caster: int, cue: StringName, _at: Vector2, _dir: Vector2, _size: float, _tint: Color, _look: int) -> void: _cues.append(cue))


func after_each() -> void:
	_world.free_all()


## The look's nodes in `group`, still in the tree.
func _in_group(body: Actor, group: StringName) -> int:
	var count: int = 0
	for node in body.get_node("PropLook").get_children():
		if node.is_in_group(group) and not node.is_queued_for_deletion():
			count += 1
	return count


func test_it_is_walked_onto_and_never_hit() -> void:
	var body: Actor = _world.add(PropBody.make(STONE), Vector2(200, 200))
	check(body.is_still(), "it stands still, never stepped")
	check(not body.hurtbox.is_on(), "no hit lands on it")
	check(not body.footprint.solid, "nobody bumps into it")
	check(body.health.invincible, "invincible all the same")
	check_equal(body.state_triggers.state_id(), HubRules.UNLIT, "dark at first")
	check_equal((body.get_node("Sprite") as Sprite2D).z_index, RoomBase.FLOOR_Z, "on the floor")


func test_it_lights_and_goes_out() -> void:
	var body: Actor = _world.add(PropBody.make(STONE), Vector2(200, 200))
	check_equal(_in_group(body, MoteSource.GROUP), 0, "dark: no motes")
	check_equal(_in_group(body, LightSpot.GROUP), 0, "and no light")
	check(body.state_triggers.enter(HubRules.LIT), "lit")
	check_equal(_cues, [&"stone_lit"] as Array[StringName], "the stone's cue")
	check_equal(_in_group(body, MoteSource.GROUP), 1, "its runes give off glimmers")
	check_equal(_in_group(body, LightSpot.GROUP), 1, "and light")
	check(not body.hurtbox.is_on() and not body.footprint.solid, "lit, still walked onto")
	check(body.state_triggers.enter(HubRules.UNLIT), "out")
	check_equal(_cues.size(), 1, "no cue going out")
	check_equal(_in_group(body, MoteSource.GROUP) + _in_group(body, LightSpot.GROUP), 0, "dark again")


## Self-contained (props W8b/W8c): where it is stood on is its own area, a 96×96 box round its
## feet, apart from any ground that blocks (it has none that blocks), and its art lies on it in
## every state.
func test_it_is_stood_on_where_its_art_lies() -> void:
	var ground: Rect2 = STONE.area_rect()
	check_equal(ground, Rect2(-48, -48, 96, 96), "a 96 px box round its feet")
	for state in STONE.states.list:
		check(not state.blocks, "%s: nobody bumps into it" % state.state_id)
		for layer in STONE.look_of(state.state_id).layers:
			var size := Vector2(layer.frame_size())
			check_equal(Rect2(layer.drawn_at() - size * 0.5, size), ground, "%s: its art on its area" % state.state_id)
