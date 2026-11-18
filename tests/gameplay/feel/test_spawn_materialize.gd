extends "res://tests/support/suite.gd"
## The spawn motion `materialize` (spawn styles AS3, docs/milestones/spawn-styles.md;
## gameplay/feel/spawn_motions/materialize.gd): a body built up out of light. Its stages (the pad, the
## scan, the landing) are each drawn in at least 3 frames at 60 fps by whole pixels; behind the scan
## line the rows show every 4th, then every 2nd, then all, each set at least 3 frames, lit in the
## light shade, then the base shade, then their own colours; the line sweeps up and goes out in 3
## looks; the glitch is whole pixels, at most 2, and settles to 0 before the body is whole; the pad's
## rim runs round in the style's colours and its cue plays once as the body is whole; it is drawn from
## the body's state alone (a fresh look draws it the same); a body that lands, goes or changes motion
## is put back; and a frame of it allocates nothing.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const Materialize := preload("res://gameplay/feel/spawn_motions/materialize.gd")
const Rise := preload("res://gameplay/feel/spawn_motions/rise.gd")

const FPS: float = SpawnStyle.CHECK_FPS

var _world: Fixture
var _look: SpawnLook
## The game's materialize style (content/spawn_styles/materialize), and the cues the look played.
var _style: SpawnStyle
var _cue_ids: Array[StringName] = []


func before_each() -> void:
	_world = Fixture.new(root)
	_style = root.get_node("Registry").call("get_resource", SpawnStyle.FOLDER, &"materialize") as SpawnStyle
	check(_style != null and _style.motion == &"materialize", "content/spawn_styles/materialize is there")
	_look = SpawnLook.new()
	root.add_child(_look)
	var style: SpawnStyle = _style
	_look.style_of = func(id: StringName) -> SpawnStyle: return style if id == &"materialize" else null
	_cue_ids.clear()
	_look.play_cue = func(cue: StringName, _at: Vector2, _weighted: bool) -> void: _cue_ids.append(cue)


func after_each() -> void:
	_look.free()
	_world.free_all()


func _motion() -> Materialize:
	return _look.motion_named(&"materialize") as Materialize


## A body with a 16 x 32 sprite whose frame reaches 2 px under its feet, materializing at `at`,
## `share` of the way through.
func _spawning(at: Vector2, share: float, style: StringName = &"materialize") -> Actor:
	var body := Actor.new()
	body.add_child(Hurtbox.new())
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	var art := PlaceholderTexture2D.new()
	art.size = Vector2(16.0, 32.0)
	sprite.texture = art
	sprite.position = Vector2(0.0, -14.0)
	body.add_child(sprite)
	body.spawn(_style.seconds, style)
	_world.add(body, at)
	_set_share(body, share)
	return body


func _set_share(body: Actor, share: float) -> void:
	body.spawn_left = _style.seconds * (1.0 - share)


func _frame() -> void:
	_look.step(_world.table, 1.0 / FPS)
	_look.cut()


## The frames of a spawn at 60 fps, as shares (the last before it lands).
func _shares() -> PackedFloat32Array:
	var shares := PackedFloat32Array()
	var frames: int = ceili(_style.seconds * FPS)
	for n in frames:
		shares.append(float(n) / (_style.seconds * FPS))
	return shares


func test_each_stage_is_drawn_in_three_frames_at_least() -> void:
	var body: Actor = _spawning(Vector2(100.0, 100.0), 0.0)
	var stages: PackedFloat32Array = _motion().stages(_style)
	check_equal(stages.size(), 4, "the pad, the scan and the landing")
	var looks: Array = []
	looks.resize(stages.size() - 1)
	for s in looks.size():
		looks[s] = []
	for share: float in _shares():
		_set_share(body, share)
		_frame()
		var seen: Array = [_look.mark(0).z if _look.marks() > 0 else 0.0, _look.mark_rim_share(0) if _look.marks() > 0 else 0.0, _motion().look_of(body)]
		for s in looks.size():
			if share >= stages[s] and share < stages[s + 1] and not looks[s].has(seen):
				looks[s].append(seen)
	for s in looks.size():
		check(looks[s].size() >= SpawnStyle.MIN_FRAMES, "stage %d (%.2f to %.2f) is drawn in %d looks" % [s, stages[s], stages[s + 1], looks[s].size()])


func test_the_rows_show_every_fourth_then_every_second_then_all() -> void:
	var at: Vector3 = Materialize.timings(_style)
	var rows: int = 30
	for row: int in [0, 7, 15, 29]:
		var strides: Array[int] = []
		var frames_in: Dictionary[int, int] = {}
		var frame: float = 0.0
		while frame < at.y:
			var stride: int = Materialize.row_stride(row, rows, frame, at.x)
			if strides.is_empty() or strides[-1] != stride:
				strides.append(stride)
			frames_in[stride] = frames_in.get(stride, 0) + 1
			frame += 1.0
		var expected: Array[int] = [4, 2, 1]
		if row > 0:
			expected.push_front(0)
		check_equal(strides, expected, "row %d: none, every 4th, every 2nd, all" % row)
		check(frames_in.get(4, 0) >= 3 and frames_in.get(2, 0) >= 3, "row %d: each set at least 3 frames: %s" % [row, frames_in])
	for row in rows:
		check(Materialize.row_shown(row, rows, at.y, at.x), "row %d shown once it is whole" % row)
	var ghost: int = 0
	for row in rows:
		ghost += 1 if Materialize.row_shown(row, rows, at.x * 0.1, at.x) else 0
	check(ghost >= 1, "a few rows show just after the scan starts: %d" % ghost)
	check_equal(Materialize.row_shade(4), 0, "every 4th: the light shade")
	check_equal(Materialize.row_shade(2), 1, "every 2nd: the base shade")
	check_equal(Materialize.row_shade(1), -1, "all: its own colours")


func test_the_line_sweeps_up_and_goes_out_in_three_looks() -> void:
	var at: Vector3 = Materialize.timings(_style)
	var rows: int = 30
	var last_row: int = -1
	var widths: Array[int] = []
	var frame: float = 0.0
	while frame <= at.z:
		var row: int = Materialize.line_row(rows, frame, at.x)
		var width: int = Materialize.line_width(13, frame, at.x)
		if row >= 0:
			check(row >= last_row, "it only goes up: %d after %d" % [row, last_row])
			last_row = row
		if widths.is_empty() or widths[-1] != width:
			widths.append(width)
		frame += 1.0
	check_equal(Materialize.line_row(rows, 0.0, at.x), 0, "from its art's lowest row")
	check_equal(last_row, rows - 1, "to its top")
	check_equal(widths, [13, 9, 4, 1, 0] as Array[int], "as wide as the mark, then out in 3 looks")
	check_equal(Materialize.line_row(rows, -1.0, at.x), -1, "none through the pad")
	check_equal(Materialize.line_row(rows, at.y, at.x), -1, "none once the body is whole")


func test_the_glitch_is_whole_pixels_and_settles() -> void:
	var at: Vector3 = Materialize.timings(_style)
	var moved: int = 0
	for seed in 40:
		var frame: float = 0.0
		while frame <= at.z:
			var by: int = Materialize.glitch(seed, frame, at.y)
			check(absi(by) <= Materialize.GLITCH_MOST, "at most 2 pixels: %d" % by)
			if at.y - frame < Materialize.SETTLE_ONE:
				check(absi(by) <= 1, "settling: %d" % by)
			if at.y - frame < Materialize.SETTLE_NONE:
				check_equal(by, 0, "still before it is whole")
			moved += 1 if by != 0 else 0
			frame += 1.0
	check(moved > 0, "now and then it glitches")


func test_the_pad_rim_runs_round_in_its_colours_and_its_cue_plays_as_it_is_whole() -> void:
	var body: Actor = _spawning(Vector2(100.0, 100.0), 0.0)
	var rims: Array[float] = []
	for share: float in _shares():
		if share >= _style.mark_end:
			break
		_set_share(body, share)
		_frame()
		if rims.is_empty() or rims[-1] != _look.mark_rim_share(0):
			rims.append(_look.mark_rim_share(0))
	check(rims.size() >= 4, "the rim runs round in 4 frames or more: %s" % [rims])
	for n in range(1, rims.size()):
		check(rims[n] > rims[n - 1], "round, never back")
	check_equal(rims[-1], 1.0, "all the way round by the pad's end")
	var light: PackedColorArray = Palette.shades_of(_style.colours)
	check_equal(_look.mark_rim(0), light[2], "its rim the light shade of the style's colours (%s)" % _style.colours)
	check_equal(_look.mark_fill(0), SpawnLook.NO_FLOOR[2].darkened(SpawnLook.MARK_DARKEN), "a hole in the floor inside")
	var whole: float = _motion().cue_share(_style)
	check(whole > _style.mark_end and whole < 1.0, "the cue plays after the scan, before it lands: %s" % whole)
	_set_share(body, whole - 0.01)
	_frame()
	check(_cue_ids.is_empty(), "not before it is whole")
	_set_share(body, whole + 0.001)
	_frame()
	_frame()
	check_equal(_cue_ids, [_style.cue] as Array[StringName], "the style's cue, once, as it is whole")
	var look: PackedInt32Array = _motion().look_of(body)
	check_equal(look[0], -1, "no line once it is whole")
	check_equal(look[2], 0, "no glitch")


## A rise style (the floor's colours) keeps its look: a full rim, the floor's light shade.
func test_a_floor_style_keeps_rises_mark() -> void:
	var rise := SpawnStyle.from_default()
	_look.style_of = func(_id: StringName) -> SpawnStyle: return rise
	_spawning(Vector2(100.0, 100.0), 0.1, &"rise")
	_frame()
	check_equal(_look.mark_rim_share(0), 1.0, "its whole rim")
	check_equal(_look.mark_rim(0), SpawnLook.NO_FLOOR[0], "in the floor's light shade")
	check_equal(_look.mark_fill(0), SpawnLook.NO_FLOOR[2].darkened(SpawnLook.MARK_DARKEN), "a hole inside")


func test_it_is_drawn_from_its_state_alone() -> void:
	var bodies: Array[Actor] = []
	for n in 6:
		bodies.append(_spawning(Vector2(60.0 + 40.0 * n, 100.0), 0.0))
	var shares: PackedFloat32Array = _shares()
	for at in shares.size():
		for n in bodies.size():
			_set_share(bodies[n], shares[mini(at + 5 * n, shares.size() - 1)])
		_frame()
	var fresh := SpawnLook.new()
	root.add_child(fresh)
	fresh.style_of = _look.style_of
	fresh.step(_world.table, 0.0)
	fresh.cut()
	for body in bodies:
		check(not _motion().look_of(body).is_empty(), "drawn")
		check_equal((fresh.motion_named(&"materialize")).look_of(body), _motion().look_of(body), "a fresh look draws it the same at %.2f" % body.spawn_share())
	fresh.free()


func test_it_is_put_back_once_it_lands_goes_or_changes_motion() -> void:
	var landing: Actor = _spawning(Vector2(100.0, 100.0), 0.5)
	var going: Actor = _spawning(Vector2(200.0, 100.0), 0.5)
	var changing: Actor = _spawning(Vector2(300.0, 100.0), 0.5)
	var rise := SpawnStyle.from_default()
	var style: SpawnStyle = _style
	_look.style_of = func(id: StringName) -> SpawnStyle: return style if id == &"materialize" else rise
	_frame()
	check_equal(_motion().lines_kept(), 3, "a line each")
	for body: Actor in [landing, going, changing]:
		check_equal(body.clip_children, CanvasItem.CLIP_CHILDREN_ONLY, "cut")
	landing.spawn_left = 0.0
	_world.actors.erase(going)
	going.free()
	changing.spawn_style = &"rise"
	_frame()
	check_equal(_motion().lines_kept(), 0, "every line freed")
	check_equal(landing.clip_children, CanvasItem.CLIP_CHILDREN_DISABLED, "the landed body's own drawing back")
	check(_motion().look_of(landing).is_empty(), "and forgotten")
	check_equal(_motion().size_tops_kept(), 0, "nothing kept")
	check_equal(changing.clip_children, CanvasItem.CLIP_CHILDREN_ONLY, "the changed one cut by rise now")
	check(_look.shift_of(changing) >= 0.0, "rise draws it")
	check_equal(_look.drawn(), 1, "one body drawn")


func test_a_frame_allocates_nothing() -> void:
	var bodies: Array[Actor] = []
	for n in 12:
		bodies.append(_spawning(Vector2(60.0 + 40.0 * (n % 6), 100.0 + 60.0 * (n / 6)), float(n) / 12.0))
	_frame()
	_frame()
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for frame in 100:
		for body in bodies:
			_set_share(body, fmod(body.spawn_share() + 0.005, 0.99))
		_frame()
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "100 frames of twelve bodies materializing make no object")


## The storm fork names materialize, and its cue is there with its sparks and its sound id.
func test_the_storm_fork_materializes() -> void:
	var fork := root.get_node("Registry").call("get_resource", &"enemies", &"storm_fork") as EnemyBase
	check(fork != null and fork.spawn_style == &"materialize", "the storm fork's own style")
	var cue := root.get_node("Registry").call("get_resource", &"cues", _style.cue) as CueBase
	check(cue != null, "its cue %s is there" % _style.cue)
	if cue != null:
		check_equal(cue.sound, &"enemy_materialize", "its sound id")
		check_equal(cue.problems(), PackedStringArray(), "no problems")


## A look that goes (or leaves the tree) mid-spawn puts its bodies back: their own drawing, and its
## light's canvas items freed, so nothing it drew stays on a body.
func test_a_look_that_goes_mid_spawn_puts_its_bodies_back() -> void:
	var body: Actor = _spawning(Vector2(100.0, 100.0), 0.6)
	_frame()
	check_equal(_motion().lines_kept(), 1, "a line kept")
	var motion: Materialize = _motion()
	root.remove_child(_look)
	check_equal(motion.lines_kept(), 0, "freed as it leaves the tree")
	check_equal(body.clip_children, CanvasItem.CLIP_CHILDREN_DISABLED, "the body's own drawing back")
	root.add_child(_look)
	_frame()
	check_equal(motion.lines_kept(), 1, "drawn again once back")
	var other := SpawnLook.new()
	other.style_of = _look.style_of
	other.step(_world.table, 0.0)
	other.cut()
	var other_motion: Materialize = other.motion_named(&"materialize") as Materialize
	check_equal(other_motion.lines_kept(), 1, "a look out of the tree draws it too")
	other.free()
	check_equal(other_motion.lines_kept(), 0, "and frees its light as it goes")


## A row of the art is lit where the sprite draws it: its own row band, flipped as the sprite flips.
func test_a_lit_row_is_where_the_sprite_draws_it() -> void:
	var body: Actor = _spawning(Vector2(100.0, 100.0), 0.6)
	var sprite := body.get_node(^"Sprite") as Sprite2D
	var bottom: float = Materialize.body_bottom(body)
	check_equal(Materialize.lit_place(sprite, 0, bottom, 1.0), Rect2(-8.0, 15.0, 16.0, 1.0), "its lowest row, in the sprite's own pixels")
	check_equal(Materialize.lit_place(sprite, 31, bottom, 1.0), Rect2(-8.0, -16.0, 16.0, 1.0), "its top row")
	check_equal(Materialize.lit_place(sprite, 32, bottom, 1.0).size.y, 0.0, "none above its art")
	sprite.flip_h = true
	check_equal(Materialize.lit_place(sprite, 0, bottom, 1.0), Rect2(-8.0, 15.0, -16.0, 1.0), "flipped: the same place, a negative width, as Sprite2D draws it")
