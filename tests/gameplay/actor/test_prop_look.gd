extends "res://tests/support/suite.gd"
## A prop's look (props W7, docs/milestones/props.md, "W7: the look"): `PropLook` on the shared
## prop body shows the look of the state it is in (`PropBase.looks`, `PropStateLook`, `PropLayer`):
## the body's own `Sprite` as its first layer, its other layers, a node giving off each of their
## `MoteSource`s (a mask reading its layer), a light spot, and its cue as a state is entered. The
## test exploding barrel (`fixtures/exploding_barrel.tres`, its art from `fixtures/exploding_barrel/`
## by tools/pixel_grid.py) idle, lit and broken; a snapshot giving a state back; an animated layer;
## Feel's source motes reading a prop's sources; the looks' problems.
##
## godot --headless --path . --script res://tests/gameplay/actor/test_prop_look.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const SourceMotesScript := preload("res://gameplay/feel/source_motes.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")
const EXPLODING_BARREL: PropBase = preload("res://tests/gameplay/actor/fixtures/exploding_barrel.tres")
const ART: String = "res://tests/gameplay/actor/fixtures/exploding_barrel/%s.svg"

var _world: Fixture
## [caster, cue] of every `cue_shown`.
var _cues: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_cap(512)
	_cues.clear()
	_world.bus.cue_shown.connect(func(caster: int, cue: StringName, _at: Vector2, _dir: Vector2, _size: float, _tint: Color, _look: int) -> void: _cues.append([caster, cue]))


func after_each() -> void:
	_world.free_all()


func _barrel(data: PropBase = EXPLODING_BARREL, at: Vector2 = Vector2(200, 200)) -> Actor:
	return _world.add(PropBody.make(data), at)


func _look(body: Actor) -> PropLook:
	return body.get_node("PropLook") as PropLook


func _body_art(body: Actor) -> String:
	var sprite := body.get_node("Sprite") as Sprite2D
	return sprite.texture.resource_path if sprite.texture != null else ""


## The look's nodes in a group (`MoteSource.GROUP`, `LightSpot.GROUP`), still in the tree.
func _in_group(body: Actor, group: StringName) -> Array[Node]:
	var found: Array[Node] = []
	for node in _look(body).get_children():
		if node.is_in_group(group) and not node.is_queued_for_deletion():
			found.append(node)
	return found


func _enter(body: Actor, state: StringName) -> void:
	var at: int = body.state_triggers.states.state_at(state)
	body.state_triggers._enter(at, 0)


func test_the_exploding_barrels_looks_are_sound() -> void:
	check_equal(EXPLODING_BARREL.look_problems(), PackedStringArray(), "every state has a sound look")
	for state in EXPLODING_BARREL.states.list:
		check(EXPLODING_BARREL.look_of(state.state_id) != null, "a look for %s" % state.state_id)


func test_it_shows_the_state_it_starts_in_with_its_body_sprite_first() -> void:
	var body: Actor = _barrel()
	check_equal(_body_art(body), ART % "idle", "the body's own Sprite shows the idle art")
	var sprite := body.get_node("Sprite") as Sprite2D
	check_equal(sprite.position, Vector2(0, -12), "a 16x24 picture stands on the feet")
	var mask := _look(body).get_node("Layer1") as Sprite2D
	check(mask != null and not mask.visible, "its mask layer is there, hidden")
	var sources: Array[Node] = _in_group(body, MoteSource.GROUP)
	check_equal(sources.size(), 1, "one mote source: the flame mark standing")
	check(MoteSource.art_of(sources[0]) == mask, "the mask source reads its own layer")
	check(MoteSource.of(sources[0]).stand, "it stands")
	check_equal(_in_group(body, LightSpot.GROUP).size(), 0, "no light while idle")
	check_equal(_cues, [], "no cue for the state it starts in")


func test_entering_a_state_shows_its_look_light_and_motes() -> void:
	var body: Actor = _barrel()
	_enter(body, &"fusing")
	check_equal(_body_art(body), ART % "fusing", "lit: the fusing art")
	var sources: Array[Node] = _in_group(body, MoteSource.GROUP)
	check_equal(sources.size(), 2, "its embers and the sparks off its fuse")
	var lights: Array[Node] = _in_group(body, LightSpot.GROUP)
	check_equal(lights.size(), 1, "a light")
	if lights.size() == 1:
		check(LightSpot.problems(lights[0]).is_empty(), "a sound light spot: %s" % [LightSpot.problems(lights[0])])
		check_equal((lights[0] as Node2D).position, Vector2(0, -22), "at its fuse")
		check_equal(LightSpot.reach_of(lights[0]), 40.0, "its reach")
	for source in sources:
		var art: Sprite2D = MoteSource.art_of(source)
		check(art != null and art.texture != null, "each source has art to read: %s" % source.name)
	_enter(body, &"broken")
	check_equal(_body_art(body), ART % "broken", "broken: the rubble")
	check_equal(_in_group(body, MoteSource.GROUP).size(), 1, "its dust")
	check_equal(_in_group(body, LightSpot.GROUP).size(), 0, "its light gone")
	check(_look(body).get_node_or_null("Layer1") == null, "the fusing look's mask gone")


func test_a_look_with_a_cue_plays_it_as_its_state_is_entered() -> void:
	var data: PropBase = EXPLODING_BARREL.duplicate()
	data.looks = EXPLODING_BARREL.looks.duplicate()
	var broken: PropStateLook = data.look_of(&"broken").duplicate()
	broken.cue = &"test_crumble"
	data.looks[2] = broken
	var body: Actor = _barrel(data)
	check_equal(_cues, [], "nothing at the start")
	_enter(body, &"broken")
	check_equal(_cues, [[body.id, &"test_crumble"]], "its cue, by the prop")


func test_a_snapshot_gives_back_the_look_of_the_state_it_gives_back() -> void:
	var body: Actor = _barrel()
	_enter(body, &"fusing")
	var snapshot := Snapshot.take(_areas(), root)
	check_equal(snapshot.problems, PackedStringArray(), "taken")
	_enter(body, &"broken")
	check_equal(_body_art(body), ART % "broken", "broken since")
	_cues.clear()
	check_equal(snapshot.restore(_areas(), root, func(made: Node) -> void: _world.add(made as Actor, (made as Actor).position)), PackedStringArray(), "restored")
	check_equal(body.state_triggers.state_id(), &"fusing", "lit again")
	check_equal(_body_art(body), ART % "fusing", "and it looks lit again")
	check_equal(_in_group(body, LightSpot.GROUP).size(), 1, "its light back")
	check_equal(_cues, [], "a state given back plays no cue")
	check(body.prop == EXPLODING_BARREL, "the body keeps its data as itself")


func test_a_layer_of_frames_plays_them_on_its_own_clock() -> void:
	var data: PropBase = EXPLODING_BARREL.duplicate()
	var look := PropStateLook.new()
	var layer := PropLayer.new()
	# The idle art's 16 px across as two 8 px frames.
	layer.texture = load(ART % "idle") as Texture2D
	layer.frames = 2
	layer.fps = 4.0
	look.layers = [layer]
	data.looks = [look]
	var body: Actor = _barrel(data)
	var sprite := body.get_node("Sprite") as Sprite2D
	check_equal(sprite.hframes, 2, "two frames")
	check(_look(body).is_processing(), "an animated look runs its clock")
	_look(body)._process(0.1)
	check_equal(sprite.frame, 0, "the first frame for a quarter second")
	_look(body)._process(0.2)
	check_equal(sprite.frame, 1, "then the second")
	var still: Actor = _barrel()
	check(not _look(still).is_processing(), "a still look runs nothing")


func test_feels_source_motes_read_a_props_sources() -> void:
	var body: Actor = _barrel()
	var sources := SourceMotesScript.new(RampTableScript.new())
	sources.take(self)
	check_equal(sources.source_count(), 1, "the idle flame mark")
	_enter(body, &"fusing")
	sources.watch(self)
	check_equal(sources.source_count(), 2, "the lit barrel's two")
	_enter(body, &"broken")
	sources.give_off(0.0, null)
	check_equal(sources.source_count(), 1, "left as the state is left; the rubble's read at the next frame")


func test_the_problems_of_looks() -> void:
	var data: PropBase = EXPLODING_BARREL.duplicate()
	var none := "\n".join(data.look_problems())
	check(none.is_empty(), "sound: %s" % none)
	data.looks = []
	check("\n".join(data.look_problems()).contains("has no look"), "a state with no look")
	var odd := PropStateLook.new()
	odd.state_id = &"nowhere"
	var masked := PropLayer.new()
	masked.texture = load(ART % "idle") as Texture2D
	masked.hidden = true
	odd.layers = [masked]
	odd.light_reach = 30.0
	odd.light_layer = 3
	data.looks = [odd, odd]
	var found := "\n".join(data.look_problems())
	for words: String in ["two looks for nowhere", "which it does not have", "first layer is the body", "layer 3"]:
		check(found.contains(words), "names %s: %s" % [words, found])
	var bad := PropLayer.new()
	bad.frames = 3
	bad.texture = load(ART % "idle") as Texture2D
	bad.offset = Vector2(0.5, 0)
	bad.motes = [MoteSource.new()]
	var lines := "\n".join(bad.problems("bad"))
	for words: String in ["not 3 frames", "whole pixels", "mote source 0"]:
		check(lines.contains(words), "names %s: %s" % [words, lines])


func _areas() -> Dictionary:
	var areas: Dictionary = {"Actors": _world.table, "Projectiles": _world.projectiles, "Spells": _world.spells, "Combat": _world.combat}
	for body in _world.actors:
		if is_instance_valid(body) and body.is_inside_tree() and body.id != ActorsScript.NONE:
			areas["actor %d" % body.id] = body
	return areas
