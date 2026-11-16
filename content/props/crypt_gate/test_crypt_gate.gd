extends "res://tests/support/suite.gd"
## The crypt's gate (crypt rework CR-G, content/props/crypt_gate): a room's exit (the role
## `room_exit`, `ExitRules`) as an archway players walk into: nobody bumps into it and no hit lands
## on it; dark until the exits' rules light it, when its runes light from the bottom and a veil of
## light rises to fill the arch, frame by frame (docs/STYLE.md "Smooth"), then ripples on; dark
## again, the light drains down. Where it is stood on is the mouth of its arch.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const GATE: PropBase = preload("res://content/props/crypt_gate/crypt_gate.tres")
const PropNames := preload("res://tests/content/props/prop_names.gd")

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


func _frame(layer: PropLayer, i: int) -> Image:
	var size: Vector2i = layer.frame_size()
	return layer.texture.get_image().get_region(Rect2i(size.x * i, 0, size.x, size.y))


## True when `a` and `b` draw the same: every pixel clear in both, or the same colour (the importer
## bleeds colour into clear pixels, which is never drawn).
func _same(a: Image, b: Image) -> bool:
	if a.get_size() != b.get_size():
		return false
	for y in a.get_height():
		for x in a.get_width():
			var p: Color = a.get_pixel(x, y)
			var q: Color = b.get_pixel(x, y)
			if (p.a > 0.0 or q.a > 0.0) and not p.is_equal_approx(q):
				return false
	return true


func test_it_is_an_exit_walked_into_and_never_hit() -> void:
	check_equal(GATE.problems(PropNames.known(_world.registry)), PackedStringArray(), "its data")
	check_equal(GATE.look_problems(), PackedStringArray(), "its looks")
	check_equal(GATE.role, RoomBase.EXIT_ROLE, "it is a room's exit")
	var body: Actor = _world.add(PropBody.make(GATE), Vector2(200, 200))
	check(body.is_still(), "it stands still, never stepped")
	check(not body.hurtbox.is_on(), "no hit lands on it")
	check(not body.footprint.solid, "nobody bumps into it: they walk into it")
	check_equal(body.state_triggers.state_id(), ExitRules.DARK, "dark at first")
	var sprite := body.get_node("Sprite") as Sprite2D
	check_equal(sprite.z_index, 0, "drawn among the bodies: a wizard in its arch is behind it")
	check_equal(sprite.frame, sprite.hframes - 1, "set up dark: at rest, closed, with no change played")


func test_it_lights_and_goes_dark() -> void:
	var body: Actor = _world.add(PropBody.make(GATE), Vector2(200, 200))
	var sprite := body.get_node("Sprite") as Sprite2D
	var look := body.get_node("PropLook") as PropLook
	check_equal(_in_group(body, MoteSource.GROUP) + _in_group(body, LightSpot.GROUP), 0, "dark: no motes, no light")
	check(body.state_triggers.enter(ExitRules.LIT), "lit")
	check_equal(sprite.frame, 0, "opening from its dark frame")
	check_equal(_cues.size(), 1, "its cue plays")
	check_equal(_in_group(body, MoteSource.GROUP), 1, "its veil gives off glimmers")
	check_equal(_in_group(body, LightSpot.GROUP), 1, "and light")
	var opening: PropLayer = GATE.look_of(ExitRules.LIT).layers[0]
	look._process(10.0)
	check(sprite.frame >= opening.loop_from, "then its light ripples round (frame %d)" % sprite.frame)
	check(look.is_processing(), "and keeps rippling")
	check(body.state_triggers.enter(ExitRules.DARK), "dark again")
	check_equal(sprite.frame, 0, "the light drains from full")
	look._process(2.0)
	check_equal(sprite.frame, sprite.hframes - 1, "down to dark")
	check(not look.is_processing(), "and rests")
	check_equal(_in_group(body, MoteSource.GROUP) + _in_group(body, LightSpot.GROUP), 0, "no motes, no light")


## Opening and closing hand over (docs/STYLE.md "Smooth"): the opening starts where the closing
## rests (dark), the closing starts on the opening's first full frame, each plays at least 3 frames.
func test_its_changes_hand_over() -> void:
	var opening: PropLayer = GATE.look_of(ExitRules.LIT).layers[0]
	var closing: PropLayer = GATE.look_of(ExitRules.DARK).layers[0]
	check(opening.loop_from >= 3 and closing.frames >= 3, "each change plays at least 3 frames")
	check_equal(closing.loop_from, closing.frames - 1, "dark holds its last frame")
	check(_same(_frame(opening, 0), _frame(closing, closing.rest_frame())), "the opening starts dark")
	check(_same(_frame(closing, 0), _frame(opening, opening.rest_frame())), "the closing starts full")
	check(not _same(_frame(closing, 0), _frame(closing, closing.rest_frame())), "and they differ")


## Stood on in the mouth of its arch: a box round its threshold, inside the arch's width, so a
## wizard who walks into the light is in it.
func test_it_is_stood_on_in_its_arch() -> void:
	var area: Rect2 = GATE.area_rect()
	check(area.has_point(Vector2(0, -8)) and area.has_point(Vector2(0, 4)), "the threshold and just inside the arch")
	var art: Vector2 = Vector2(GATE.look_of(ExitRules.DARK).layers[0].frame_size())
	check(area.size.x < art.x * 0.6, "narrower than the arch's posts")
	check(area.position.y + area.size.y <= 8.0, "never far in front of it")


## The exits' rules light it as they light a plate exit.
func test_the_exits_rules_read_it() -> void:
	for state: StringName in [ExitRules.DARK, ExitRules.LIT]:
		check(GATE.states.state_at(state) >= 0, "it has the state %s" % state)
	check_equal(GATE.states.list[0].state_id, ExitRules.DARK, "and starts dark")
