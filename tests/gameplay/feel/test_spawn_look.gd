extends "res://tests/support/suite.gd"
## The look of an enemy spawning (enemy spawning EA2, docs/milestones/enemy-spawning.md, "The look"):
## a mark grows on the floor in at least 3 frames, the body rises out of it by whole pixels in at
## least 3, and the mark closes in at least 3 as it lands, each stage ending where the next begins
## (docs/STYLE.md, "Smooth"); it is drawn from the body's state alone (a body set mid-spawn by hand,
## as a restored snapshot is, is drawn where it is), cut at its feet while it rises and given its own
## drawing back once it stands; its rise plays the cue `enemy_spawn` once, its sound at most every
## `SOUND_EVERY`; a frame of it allocates nothing; and the game's Feel steps it.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const Motion := preload("res://gameplay/feel/spawn_motions/spawn_motion.gd")
const Rise := preload("res://gameplay/feel/spawn_motions/rise.gd")

var _world: Fixture
var _look: SpawnLook
## The style the look draws when it has no lookup: `rise`'s numbers (`SpawnStyle.DEFAULT`).
var _style: SpawnStyle = SpawnStyle.from_default()
## Every cue the look played, as [at, weighted], and the cues' ids.
var _cues: Array = []
var _cue_ids: Array[StringName] = []


func before_each() -> void:
	_world = Fixture.new(root)
	_look = SpawnLook.new()
	root.add_child(_look)
	_cues.clear()
	_cue_ids.clear()
	_look.play_cue = func(cue: StringName, at: Vector2, weighted: bool) -> void:
		_cues.append([at, weighted])
		_cue_ids.append(cue)


func after_each() -> void:
	_look.free()
	_world.free_all()


## An enemy at `at` (a hurt circle 12 high), spawning `share` of the way through (set by hand), in
## the style of id `style`.
func _spawning(at: Vector2, share: float, style: StringName = SpawnStyle.DEFAULT["id"]) -> Actor:
	var body := Actor.new()
	body.add_child(Hurtbox.new())
	body.spawn(_style.seconds, style)
	_world.add(body, at)
	_set_share(body, share)
	return body


## One frame as the game draws it: Feel's step, then the cut just before the frame is drawn.
func _frame(delta: float) -> void:
	_look.step(_world.table, delta)
	_look.cut()


func _set_share(body: Actor, share: float) -> void:
	body.spawn_left = _style.seconds * (1.0 - share)


## The distinct values `value(share)` takes over the shares `from` to `to` in 200 steps, in order.
func _frames(value: Callable, from: float, to: float) -> Array:
	var seen: Array = []
	for n in 201:
		var v: Variant = value.call(lerpf(from, to, float(n) / 200.0))
		if seen.is_empty() or seen[-1] != v:
			seen.append(v)
	return seen


func test_the_mark_grows_in_four_frames_from_a_dot_and_closes_in_three() -> void:
	var grow: Array = _frames(func(share: float) -> int: return SpawnLook.mark_radius(7.0, share, _style), 0.0, _style.mark_end - 0.001)
	check_equal(grow, [1, 3, 5, 7], "from a dot to the footprint's width, by whole pixels")
	check_equal(SpawnLook.mark_radius(7.0, _style.mark_end, _style), 7, "held as the rise begins: the mark ends where the rise starts")
	var close: Array = _frames(func(share: float) -> int: return SpawnLook.mark_radius(7.0, share, _style), _style.close_from - 0.01, 0.999)
	check_equal(close, [7, 5, 3, 1], "closing in three frames, down to a dot")
	check_equal(SpawnLook.mark_radius(7.0, 1.0, _style), 0, "none once it stands")
	check(_style.mark_frames >= 3 and _style.close_frames >= 3, "at least 3 frames a stage")


func test_the_body_rises_by_whole_pixels_from_its_height_to_its_feet() -> void:
	var height: float = 26.0
	check_equal(Rise.shift(height, 0.0, _style), height, "all under the floor through the mark")
	check_equal(Rise.shift(height, _style.mark_end, _style), height, "the rise starts where the mark left it")
	var rise: Array = _frames(func(share: float) -> float: return Rise.shift(height, share, _style), _style.mark_end, 1.0)
	check(rise.size() >= 5, "at least 5 frames: %d" % rise.size())
	for n in rise.size():
		check_equal(rise[n], roundf(rise[n]), "whole pixels")
		if n > 0:
			check(rise[n] < rise[n - 1] and rise[n - 1] - rise[n] <= 1.0, "up a pixel at a time")
	check_equal(rise[-1], 0.0, "standing at the end")
	check(Rise.shift(4.0, 0.7, _style) <= 4.0, "a small body too")


func test_its_height_counts_its_sprite_its_hurt_shape_and_its_size() -> void:
	var body := Actor.new()
	var hurtbox := Hurtbox.new()
	hurtbox.radius = 12.0
	hurtbox.offset = Vector2(0.0, -14.0)
	body.add_child(hurtbox)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	var art := PlaceholderTexture2D.new()
	art.size = Vector2(16.0, 40.0)
	sprite.texture = art
	sprite.position = Vector2(0.0, -14.0)
	body.add_child(sprite)
	_world.add(body, Vector2(100.0, 100.0))
	check_equal(Motion.body_height(body), 34.0 + Motion.HEIGHT_MARGIN, "its sprite's top (14 + 20) and the margin")
	body.set_size(2.0)
	check_equal(Motion.body_height(body), 68.0 + Motion.HEIGHT_MARGIN, "twice as tall at twice its size")


func test_it_is_drawn_from_its_state_alone_and_put_back_once_it_stands() -> void:
	var marking: Actor = _spawning(Vector2(100.0, 100.0), 0.25)
	var rising: Actor = _spawning(Vector2(200.5, 140.0), 0.6)
	var standing := Actor.new()
	_world.add(standing, Vector2(300.0, 100.0))
	_frame(0.016)
	check_equal(_look.drawn(), 2, "the two spawning bodies are drawn spawning")
	check_equal(marking.clip_children, CanvasItem.CLIP_CHILDREN_ONLY, "a body still under the floor is cut")
	check_equal(rising.clip_children, CanvasItem.CLIP_CHILDREN_ONLY, "a rising one is cut at its feet")
	check_equal(standing.clip_children, CanvasItem.CLIP_CHILDREN_DISABLED, "a standing body is left alone")
	check_equal(_look.marks(), 2, "a mark under each")
	var first: Vector3 = _look.mark(0)
	var second: Vector3 = _look.mark(1)
	check_equal(Vector2(first.x, first.y), Vector2(100.0, 100.0), "at its feet")
	check_equal(int(first.z), SpawnLook.mark_radius(marking.wall_radius(), marking.spawn_share(), _style), "as wide as its share says")
	check_equal(Vector2(second.x, second.y), Vector2(201.0, 140.0), "on whole pixels")
	check_equal(marking.global_position, Vector2(100.0, 100.0), "its place untouched")
	check_equal(_look.shift_of(marking), Rise.shift(Motion.body_height(marking), marking.spawn_share(), _style), "still under the floor: shifted its whole height")
	check_equal(_look.shift_of(rising), Rise.shift(Motion.body_height(rising), rising.spawn_share(), _style), "rising: shifted as far as its share says")
	check(_look.shift_of(rising) > 0.0 and _look.shift_of(rising) < Motion.body_height(rising), "part way up: %s" % _look.shift_of(rising))
	check_equal(_look.shift_of(standing), -1.0, "a standing body is not shifted")
	check_equal(_cues.size(), 1, "the rising body's cue played once")
	check_equal(_cues[0], [rising.global_position, true], "at its feet, with its sound")
	check_equal(_cue_ids[0], &"enemy_spawn", "the style's cue")
	_frame(0.016)
	check_equal(_cues.size(), 1, "and not again")
	_set_share(marking, 0.5)
	_frame(0.2)
	check_equal(_cues.size(), 2, "the other's as it starts to rise")
	check_equal(_cues[1][1], true, "its sound too: more than 0.1 s after the first")
	rising.spawn_left = 0.0
	_frame(0.016)
	check_equal(_look.drawn(), 1, "a body that stands is no longer drawn spawning")
	check_equal(rising.clip_children, CanvasItem.CLIP_CHILDREN_DISABLED, "its own drawing back")
	check_equal(_look.shift_of(rising), -1.0, "no longer shifted")
	_world.actors.erase(marking)
	marking.free()
	_frame(0.016)
	check_equal(_look.drawn(), 0, "a body gone is forgotten")
	check_equal(_look.marks(), 0, "no marks")


func test_a_group_rising_together_sounds_once() -> void:
	for n in 4:
		_spawning(Vector2(100.0 + 30.0 * n, 100.0), 0.5)
	_frame(0.016)
	check_equal(_cues.size(), 4, "a cue for each body's dust")
	var weighted: int = 0
	for cue: Array in _cues:
		weighted += 1 if cue[1] else 0
	check_equal(weighted, 1, "one sound for the four")


func test_a_frame_allocates_nothing() -> void:
	var bodies: Array[Actor] = []
	for n in 12:
		bodies.append(_spawning(Vector2(60.0 + 40.0 * (n % 6), 100.0 + 60.0 * (n / 6)), float(n) / 12.0))
	_frame(0.016)
	_frame(0.016)
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for frame in 100:
		for body in bodies:
			_set_share(body, fmod(body.spawn_share() + 0.005, 0.99))
		_frame(0.016)
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "100 frames of twelve bodies spawning make no object")


## The game's Feel holds the look and steps it, and the cue it plays is in the registry, sound named.
func test_feel_steps_it_and_its_cue_is_there() -> void:
	var feel := root.get_node_or_null("Feel")
	check(feel != null, "the game's Feel")
	if feel == null:
		return
	var look := feel.get("_spawn_look") as SpawnLook
	check(look != null and look.get_parent() == feel, "Feel holds a spawn look")
	check(look.play_cue.is_valid(), "and plays its cue")
	check(look.style_of.is_valid(), "and looks its styles up")
	var rise: SpawnStyle = look.style_of.call(&"rise") as SpawnStyle
	check(rise != null and rise.resource_path == "res://content/spawn_styles/rise/rise.tres", "in the registry: content/spawn_styles/rise")
	check(look.style_of.call(&"no_such_style") == null, "and none for an id there is none of")
	var cue := root.get_node("Registry").call("get_resource", &"cues", _style.cue) as CueBase
	check(cue != null, "the cue enemy_spawn is in the registry")
	if cue != null:
		check_equal(cue.sound, &"enemy_spawn", "its soft sound")
		check_equal(cue.problems(), PackedStringArray(), "no problems")


## The rows of a body's art under its feet (a spitter's frame reaches 2 px below them) are kept by the
## cut and lifted by the rise, so nothing of it appears in one jump as it lands.
func test_art_under_its_feet_rises_with_it() -> void:
	var body := Actor.new()
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	var art := PlaceholderTexture2D.new()
	art.size = Vector2(16.0, 32.0)
	sprite.texture = art
	sprite.position = Vector2(0.0, -14.0)
	body.add_child(sprite)
	body.spawn(_style.seconds, _style.id)
	_world.add(body, Vector2(100.0, 100.0))
	check_equal(Motion.body_bottom(body), 2.0, "its frame reaches 2 px under its feet")
	_set_share(body, 0.1)
	_frame(0.016)
	check_equal(_look.shift_of(body), Motion.body_height(body) + 2.0, "through the mark it is under the line, those rows too")
	_set_share(body, 0.999)
	_frame(0.016)
	check_equal(_look.shift_of(body), 0.0, "all of it up by the end of the rise")


## A body added after Feel's step (a run that starts as a load ends, in a later `_process`) is cut
## before the frame is drawn: never drawn whole for a frame.
func test_a_body_added_after_the_step_is_cut_before_the_draw() -> void:
	_look.step(_world.table, 0.016)
	var late: Actor = _spawning(Vector2(100.0, 100.0), 0.0)
	check_equal(late.clip_children, CanvasItem.CLIP_CHILDREN_DISABLED, "not cut yet")
	_look.cut()
	check_equal(late.clip_children, CanvasItem.CLIP_CHILDREN_ONLY, "cut just before the draw")
	check_equal(_look.shift_of(late), Motion.body_height(late), "all of it under the floor")
	check(RenderingServer.frame_pre_draw.is_connected(_look.cut), "the cut runs before every frame is drawn")


## A body with a sprite whose frame reaches 2 px under its feet (a spitter's), spawning at `at`; with
## `hurt_radius`, its hurt shape that wide (20: its top above the sprite's).
func _spawning_with_art(at: Vector2, share: float, hurt_radius: float = -1.0) -> Actor:
	var body := Actor.new()
	var hurtbox := Hurtbox.new()
	if hurt_radius > 0.0:
		hurtbox.radius = hurt_radius
	body.add_child(hurtbox)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	var art := PlaceholderTexture2D.new()
	art.size = Vector2(16.0, 32.0)
	sprite.texture = art
	sprite.position = Vector2(0.0, -14.0)
	body.add_child(sprite)
	body.spawn(_style.seconds, _style.id)
	_world.add(body, at)
	_set_share(body, share)
	return body


## The part of a body's height its size moves (its body's centre, its hurt shape: `size_top`) is
## worked out when it is first cut, kept while it spawns in, worked out again if its size changes
## mid-spawn and forgotten once it lands or goes; its sprite's terms are read at every cut, so its
## look's bob (its art moved while it spawns in) is followed; its shift and its mask are what a fresh
## count gives.
func test_the_part_of_its_height_its_size_moves_is_worked_out_once() -> void:
	# Its hurt shape the tallest of it, so its shift follows the part kept.
	var body: Actor = _spawning_with_art(Vector2(100.0, 100.0), 0.6, 20.0)
	var other: Actor = _spawning_with_art(Vector2(200.0, 100.0), 0.3)
	check(is_nan(_look.size_top_kept(body)), "nothing kept before its first cut")
	_frame(0.016)
	check(Motion.size_top(body) + Motion.HEIGHT_MARGIN > Motion.body_height(other), "its hurt shape stands above its art: %s" % Motion.size_top(body))
	check_equal(Motion.body_height(body), ceilf(Motion.size_top(body) + Motion.HEIGHT_MARGIN), "its height is its hurt shape's")
	check_equal(_look.size_top_kept(body), Motion.size_top(body), "kept as a fresh count gives it")
	check_equal(_look.size_tops_kept(), 2, "one for each body cut")
	check_equal(Motion.body_bottom(body), 2.0, "its frame reaches 2 px under its feet")
	_check_fresh(body, "first cut")
	# Its look's bob: its art 1 px up (the sprite's offset), as CreatureLook lifts it while it spawns in.
	var sprite := body.get_node(^"Sprite") as Sprite2D
	sprite.offset.y -= 1.0
	_set_share(body, 0.7)
	_frame(0.016)
	check_equal(_look.bottom_of(body), 1.0, "its mask follows its art up")
	_check_fresh(body, "bobbed")
	# Not counted again each frame: its hurt shape's top is only ever moved by its size.
	var kept: float = _look.size_top_kept(body)
	body.hurtbox.offset.y -= 50.0
	_frame(0.016)
	check_equal(_look.size_top_kept(body), kept, "the same, not counted again")
	body.hurtbox.offset.y += 50.0
	body.set_size(1.5)
	_frame(0.016)
	check(_look.size_top_kept(body) != kept, "its size moves it: %s" % _look.size_top_kept(body))
	check_equal(_look.size_top_kept(body), Motion.size_top(body), "counted again at its new size")
	_check_fresh(body, "grown")
	body.spawn_left = 0.0
	_frame(0.016)
	check(is_nan(_look.size_top_kept(body)), "forgotten once it lands")
	check_equal(_look.size_tops_kept(), 1, "only the other is kept")
	_world.actors.erase(other)
	other.free()
	_frame(0.016)
	check_equal(_look.size_tops_kept(), 0, "a body gone is forgotten")


## `body`'s shift and mask at its last cut are what a fresh `body_height` and `body_bottom` give.
func _check_fresh(body: Actor, when: String) -> void:
	var bottom: float = Motion.body_bottom(body)
	check_equal(_look.bottom_of(body), bottom, "%s: its mask at its lowest row" % when)
	var size: float = absf(body.size)
	check_equal(Rise.mask_rect(bottom, size), Rect2(-Rise.MASK_HALF_WIDTH, -Rise.MASK_TALL, 2.0 * Rise.MASK_HALF_WIDTH, Rise.MASK_TALL + bottom / size), "%s: everything above that line, in its own pixels" % when)
	check_equal(_look.shift_of(body), Rise.shift(Motion.body_height(body) + bottom, body.spawn_share(), _style), "%s: shifted as a fresh count says" % when)


## Feel draws every motion a style may name, and no other (`SpawnStyle.MOTIONS` is the list in core,
## `SpawnLook.MOTIONS` the code for each, as `ModifierBase.RULES` and its kits are split).
func test_its_motions_are_the_styles_motions() -> void:
	var names: Array[StringName] = []
	names.assign(SpawnLook.MOTIONS.keys())
	names.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var listed: Array[StringName] = SpawnStyle.MOTIONS.duplicate()
	listed.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	check_equal(names, listed, "the same names")
	check(SpawnLook.MOTIONS.has(SpawnLook.FALLBACK_MOTION), "and the one a motion it lacks is drawn by")
	for motion: StringName in SpawnLook.MOTIONS:
		check(_look.motion_named(motion) != null, "it holds one %s" % motion)


## The look draws by the style its lookup gives: the style's stages and frames for the mark and the
## motion, and its cue; a style it does not find is the default's numbers.
func test_it_draws_by_the_style_it_looks_up() -> void:
	var slow: SpawnStyle = SpawnStyle.from_default()
	slow.mark_end = 0.6
	slow.close_from = 0.8
	slow.cue = &"fixture_cue"
	var asked: Array[StringName] = []
	_look.style_of = func(id: StringName) -> SpawnStyle:
		asked.append(id)
		return slow
	var body: Actor = _spawning(Vector2(100.0, 100.0), 0.5)
	_frame(0.016)
	check_equal(asked, [&"rise"] as Array[StringName], "it asked for rise, the body's style, once")
	check_equal(int(_look.mark(0).z), SpawnLook.mark_radius(body.wall_radius(), 0.5, slow), "its mark by the style's frames")
	check_equal(_look.shift_of(body), Motion.body_height(body), "at 0.5 still under the floor: its mark ends at 0.6")
	check(_cues.is_empty(), "no cue before its motion starts")
	_set_share(body, 0.7)
	_frame(0.016)
	check_equal(_look.shift_of(body), Rise.shift(Motion.body_height(body), 0.7, slow), "rising by the style's numbers")
	check_equal(_cue_ids, [&"fixture_cue"] as Array[StringName], "the style's cue, as the motion starts")
	_frame(0.016)
	check_equal(asked.size(), 1, "looked up once, not every frame")
	_set_share(body, 0.85)
	_frame(0.016)
	check(int(_look.mark(0).z) < roundi(body.wall_radius()), "closing from the style's 0.8")
	_look.style_of = func(_id: StringName) -> SpawnStyle: return null
	_frame(0.016)
	check_equal(_look.shift_of(body), Rise.shift(Motion.body_height(body), 0.85, _style), "a style not found: the default's numbers")


## A style whose motion the look does not have (a newer machine's) is drawn as `rise`, so the body is
## never drawn whole mid-spawn.
func test_a_motion_it_does_not_have_is_drawn_as_rise() -> void:
	var odd: SpawnStyle = SpawnStyle.from_default()
	odd.motion = &"no_such_motion"
	_look.style_of = func(_id: StringName) -> SpawnStyle: return odd
	var body: Actor = _spawning(Vector2(100.0, 100.0), 0.2)
	_frame(0.016)
	check_equal(body.clip_children, CanvasItem.CLIP_CHILDREN_ONLY, "cut")
	check_equal(_look.shift_of(body), Motion.body_height(body), "under the floor through the mark, as rise draws it")
	check_equal(_look.drawn(), 1, "one body drawn")


## A style of `rise`'s numbers but these, named `id`.
func _fixture_style(id: StringName, mark_end: float, cue: StringName, motion: StringName = &"rise") -> SpawnStyle:
	var style: SpawnStyle = SpawnStyle.from_default()
	style.id = id
	style.mark_end = mark_end
	style.cue = cue
	style.motion = motion
	return style


## Each body is drawn by its own style (`Actor.spawn_style`, spawn styles AS2): its mark, its motion's
## numbers and its cue; an id the lookup does not find is drawn as the lookup's `rise`, not as the
## default (the two are held together by test_spawn_style.gd, but the registry's is the game's).
func test_each_body_is_drawn_by_its_own_style() -> void:
	var slow: SpawnStyle = _fixture_style(&"slow", 0.7, &"slow_cue")
	var rise: SpawnStyle = _fixture_style(&"rise", 0.3, &"rise_cue")
	var asked: Array[StringName] = []
	_look.style_of = func(id: StringName) -> SpawnStyle:
		asked.append(id)
		return {&"slow": slow, &"rise": rise}.get(id) as SpawnStyle
	var slow_body: Actor = _spawning(Vector2(100.0, 100.0), 0.5, &"slow")
	var rise_body: Actor = _spawning(Vector2(200.0, 100.0), 0.5, &"rise")
	var lost_body: Actor = _spawning(Vector2(300.0, 100.0), 0.5, &"no_such_style")
	_frame(0.016)
	check_equal(_look.style_for(slow_body), slow, "the slow body's style is slow")
	check_equal(_look.style_for(rise_body), rise, "the rise body's rise")
	check_equal(_look.style_for(lost_body), rise, "an id not found: the lookup's rise")
	check_equal(_look.shift_of(slow_body), Motion.body_height(slow_body), "slow: at 0.5 still under the floor (its mark ends at 0.7)")
	check_equal(_look.shift_of(rise_body), Rise.shift(Motion.body_height(rise_body), 0.5, rise), "rise: rising by its own numbers")
	check_equal(_look.shift_of(lost_body), Rise.shift(Motion.body_height(lost_body), 0.5, rise), "the lost one as rise")
	check_equal(_cue_ids, [&"rise_cue", &"rise_cue"] as Array[StringName], "the cue of each body whose motion started")
	_set_share(slow_body, 0.75)
	_frame(0.016)
	check_equal(_cue_ids.slice(2), [&"slow_cue"] as Array[StringName], "the slow one's own cue as its motion starts")
	asked.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	check_equal(asked, [&"no_such_style", &"rise", &"slow"] as Array[StringName], "each id looked up once")


## A body whose style's motion changes mid-spawn (a snapshot restored over it, or another machine's
## state) is put back by the motion that drew it before the new one draws it, and the new one puts it
## back as it lands (`cut`).
func test_a_body_whose_motion_changes_is_handed_from_one_motion_to_the_other() -> void:
	var other := Recording.new()
	_look._motions[&"fixture_motion"] = other
	var odd: SpawnStyle = _fixture_style(&"odd", 0.4, &"", &"fixture_motion")
	_look.style_of = func(id: StringName) -> SpawnStyle: return odd if id == &"odd" else null
	var body: Actor = _spawning(Vector2(100.0, 100.0), 0.6)
	_frame(0.016)
	check_equal(body.clip_children, CanvasItem.CLIP_CHILDREN_ONLY, "drawn by rise: cut")
	check(_look.shift_of(body) > 0.0, "and shifted")
	body.spawn_style = &"odd"
	_frame(0.016)
	check_equal(body.clip_children, CanvasItem.CLIP_CHILDREN_DISABLED, "rise put it back: no cut")
	check_equal(_look.shift_of(body), -1.0, "and no shift")
	check_equal(other.applied, 1, "the other motion drew it")
	check_equal(other.put_back_count, 0, "and has not put it back")
	check_equal(_look.drawn(), 1, "one body drawn")
	body.spawn_style = &"rise"
	_frame(0.016)
	check_equal(other.put_back_count, 1, "back to rise: the other put it back")
	check_equal(body.clip_children, CanvasItem.CLIP_CHILDREN_ONLY, "and rise cuts it again")
	body.spawn_style = &"odd"
	_frame(0.016)
	body.spawn_left = 0.0
	_frame(0.016)
	check_equal(other.put_back_count, 2, "landed: the motion drawing it puts it back")
	check_equal(_look.drawn(), 0, "none drawn")
	check_equal(body.clip_children, CanvasItem.CLIP_CHILDREN_DISABLED, "and rise never cut it again")


## A motion that counts what it is asked (the motion-change test).
class Recording extends Motion:
	var applied: int = 0
	var put_back_count: int = 0

	func apply(_body: Actor, _share: float, _style: SpawnStyle) -> void:
		applied += 1

	func put_back(key: int, _body: Actor) -> void:
		put_back_count += 1
		forget(key)
