extends "res://tests/support/suite.gd"
## A room's exit (run generation RG4, content/props/room_exit): a plate on the floor that nobody
## bumps into and no hit lands on, dark until the exits' rules light it (`ExitRules.LIT`, once the
## room is cleared and the run's map leads on from it); lit, its carvings glow, give off glimmers
## and light, and its cue plays. Where it is stood on is its own area.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const EXIT: PropBase = preload("res://content/props/room_exit/room_exit.tres")

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


func test_it_is_an_exit_walked_onto_and_never_hit() -> void:
	check_equal(EXIT.role, RoomBase.EXIT_ROLE, "it is a room's exit")
	var body: Actor = _world.add(PropBody.make(EXIT), Vector2(200, 200))
	check(body.is_still(), "it stands still, never stepped")
	check(not body.hurtbox.is_on(), "no hit lands on it")
	check(not body.footprint.solid, "nobody bumps into it")
	check_equal(body.state_triggers.state_id(), ExitRules.DARK, "dark at first")
	check_equal((body.get_node("Sprite") as Sprite2D).z_index, RoomBase.FLOOR_Z, "on the floor")


func test_it_lights_and_goes_dark() -> void:
	var body: Actor = _world.add(PropBody.make(EXIT), Vector2(200, 200))
	check_equal(_in_group(body, MoteSource.GROUP) + _in_group(body, LightSpot.GROUP), 0, "dark: no motes, no light")
	check(body.state_triggers.enter(ExitRules.LIT), "lit")
	check_equal(_cues.size(), 1, "its cue plays")
	check_equal(_in_group(body, MoteSource.GROUP), 1, "its carvings give off glimmers")
	check_equal(_in_group(body, LightSpot.GROUP), 1, "and light")
	check(body.state_triggers.enter(ExitRules.DARK), "dark again")
	check_equal(_in_group(body, MoteSource.GROUP) + _in_group(body, LightSpot.GROUP), 0, "no motes, no light")


func test_it_is_stood_on_where_its_art_lies() -> void:
	var ground: Rect2 = EXIT.area_rect()
	check_equal(ground, Rect2(-24, -24, 48, 48), "a 48 px box round its feet")
	for state in EXIT.states.list:
		check(not state.blocks, "%s: nobody bumps into it" % state.state_id)
		for layer in EXIT.look_of(state.state_id).layers:
			var size := Vector2(layer.frame_size())
			check_equal(Rect2(layer.drawn_at() - size * 0.5, size), ground, "%s: its art on its area" % state.state_id)


## The crypt's fight room leads on by two exits (a map's room leads to one or two).
func test_the_crypt_arena_has_two_exits() -> void:
	var arena: RoomBase = load("res://content/rooms/crypt/arena_01.tres") as RoomBase
	check_equal(arena.exit_count(), 2, "two exits")
