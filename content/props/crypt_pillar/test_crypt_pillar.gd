extends "res://tests/support/suite.gd"
## The crypt pillar (crypt rework CR-G, content/props/crypt_pillar): a round column of 60 health that
## stands in the way and stops shots, casting nothing: the crypt's cover. The fight breaks it in
## stages, each played frame by frame from the last (docs/STYLE.md "Smooth"): below two thirds of
## its health it cracks (a crack runs down, a chip of its capital falls), below a third it splits
## (half its capital breaks off and falls), and its death brings it down drum by drum into rubble
## that nothing bumps into or hits.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const PropNames := preload("res://tests/content/props/prop_names.gd")
const PILLAR: PropBase = preload("res://content/props/crypt_pillar/crypt_pillar.tres")
## Its states in the order the fight breaks it.
const STAGES: Array[StringName] = [&"intact", &"cracked", &"split", &"rubble"]

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root)


func after_each() -> void:
	_world.free_all()


func _pillar() -> Actor:
	return _world.add(PropBody.make(PILLAR), Vector2(200, 200))


## Frame `i` of `layer`'s strip, as an image.
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


func test_it_is_sound() -> void:
	check_equal(PILLAR.problems(PropNames.known(_world.registry)), PackedStringArray(), "its data")
	check_equal(PILLAR.look_problems(), PackedStringArray(), "its looks")
	check(PILLAR.staffs.is_empty(), "it casts nothing")
	check(PILLAR.role == &"", "no role: it stands in the hub's prop yard too")


func test_the_fight_breaks_it_stage_by_stage() -> void:
	var pillar: Actor = _pillar()
	check(pillar.footprint.solid and pillar.hurtbox.is_on(), "it stands in the way and is hit")
	_world.combat.hit(ActorsScript.NONE, pillar, 15.0)
	check_equal(pillar.state_triggers.state_id(), &"intact", "a first hit: whole")
	_world.combat.hit(ActorsScript.NONE, pillar, 10.0)
	check_equal(pillar.state_triggers.state_id(), &"cracked", "below two thirds: cracked")
	check(pillar.footprint.solid and pillar.hurtbox.is_on(), "still cover")
	_world.combat.hit(ActorsScript.NONE, pillar, 17.0)
	check_equal(pillar.state_triggers.state_id(), &"split", "below a third: split")
	check(pillar.footprint.solid and pillar.hurtbox.is_on(), "still cover")
	_world.combat.hit(ActorsScript.NONE, pillar, 30.0)
	check_equal(pillar.state_triggers.state_id(), &"rubble", "its health gone: rubble")
	check(not pillar.footprint.solid and not pillar.hurtbox.registered, "rubble: walked over, never hit")
	check(not pillar.is_dying(), "it stays, as rubble")


func test_a_heavy_hit_goes_as_far_as_it_reaches() -> void:
	var pillar: Actor = _pillar()
	_world.combat.hit(ActorsScript.NONE, pillar, 45.0)
	check_equal(pillar.state_triggers.state_id(), &"split", "past both shares at once: split, not only cracked")
	var other: Actor = _world.add(PropBody.make(PILLAR), Vector2(300, 200))
	_world.combat.hit(ActorsScript.NONE, other, 100.0)
	check_equal(other.state_triggers.state_id(), &"rubble", "past its health: down at once")


func test_spells_chip_it() -> void:
	var pillar: Actor = _pillar()
	check_equal(_world.shoot(pillar, &"fire").slice(0, 1), [&"fire"] as Array[StringName], "a shot lands on its column")
	check(pillar.health.health < pillar.health.max_health, "and chips it")


## Every stage after the first plays at least 3 frames, starts on the look the stage before it
## rests on, and holds its own last frame (docs/STYLE.md "Smooth": stages hand over).
func test_each_crumble_hands_over_from_the_stage_before() -> void:
	for i in range(1, STAGES.size()):
		var before: PropLayer = PILLAR.look_of(STAGES[i - 1]).layers[0]
		var layer: PropLayer = PILLAR.look_of(STAGES[i]).layers[0]
		check(layer.frames >= 3 and layer.is_animated(), "%s: its crumble plays %d frames" % [STAGES[i], layer.frames])
		check_equal(layer.loop_from, layer.frames - 1, "%s: played once, its last frame held" % STAGES[i])
		check_equal(layer.frame_size(), before.frame_size(), "%s: frames the size of the stage before" % STAGES[i])
		check(_same(_frame(layer, 0), _frame(before, before.rest_frame())), "%s: its first frame is where %s rests" % [STAGES[i], STAGES[i - 1]])


func test_its_body_plays_the_crumble_then_rests() -> void:
	var pillar: Actor = _pillar()
	var sprite := pillar.get_node("Sprite") as Sprite2D
	var look := pillar.get_node("PropLook") as PropLook
	_world.combat.hit(ActorsScript.NONE, pillar, 100.0)
	check_equal(sprite.frame, 0, "the collapse from its first frame")
	look._process(0.25)
	check(sprite.frame > 0 and sprite.frame < sprite.hframes - 1, "midway down: frame %d" % sprite.frame)
	look._process(2.0)
	check_equal(sprite.frame, sprite.hframes - 1, "then the heap of rubble")
	check(not look.is_processing(), "at rest, nothing runs")


## Its sounds: a crack as it cracks and splits, a break as it comes down.
func test_its_sounds() -> void:
	var registry: Node = root.get_node("Registry")
	for state: StringName in [&"cracked", &"split"]:
		var cue: CueBase = registry.get_resource(&"cues", PILLAR.look_of(state).cue) as CueBase
		check(cue != null and cue.sound == &"pillar_crack", "%s sounds pillar_crack as it is entered" % state)
	var rubble: CueBase = registry.get_resource(&"cues", PILLAR.look_of(&"rubble").cue) as CueBase
	check(rubble != null and rubble.sound == &"pillar_break", "rubble sounds pillar_break as it is entered")
