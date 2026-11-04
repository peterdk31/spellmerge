extends "res://tests/support/suite.gd"
## Motes (gameplay/feel/mote.gd; docs/milestones/spell-spectacle.md, P1a): a ring of rows cut into
## chunked batches. The ring wraps with nothing allocated and overwrites the oldest row; only the
## chunks written in a frame upload, a frame writes at most FRAME_ROWS, and a chunk with nothing
## alive is hidden. Kinds are data (`MoteKind`, content/motes) whose numbers the shader is handed,
## a shot sheds the kinds of its cards' look layers in its own ramp, and other colours (a room's
## walls, sampled from its art) go through the ramp table. `mote_land` is where the flight comes
## to rest. In Feel, a wall hit sheds the shot's motes and the wall's; with the "Particles"
## setting off there are no motes and no nodes, and the old chips effect shows instead.

const MotesScript := preload("res://gameplay/feel/mote.gd")
const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const TimedMotesScript := preload("res://tests/benchmark/timed_motes.gd")
const ARENA: StringName = &"arena_01"

## Look bits of the elements' layers (layer n is bit n - 1).
const FIRE_LOOK: int = 1 << 0
const FROST_LOOK: int = 1 << 1
const LIGHTNING_LOOK: int = 1 << 4
const BIGGER_LOOK: int = 1 << 6

var registry: RegistryScript


func before_each() -> void:
	registry = own(RegistryScript.new()) as RegistryScript
	registry.scan()


## A kind made here: falls like a chip, of layer `layer` (-1: a surface kind).
func _kind(id: StringName, layer: int = 0, gravity: float = 320.0) -> MoteKind:
	var kind := MoteKind.new()
	kind.id = id
	kind.gravity = gravity
	kind.bounce = 0.3
	kind.drag = 2.5
	if layer < 0:
		kind.surface = true
	else:
		kind.look_layers = PackedInt32Array([layer])
	return kind


func _pool(cap: int, kinds: Array[MoteKind] = []) -> MotesScript:
	if kinds.is_empty():
		kinds = [_kind(&"chip", -1), _kind(&"ember", 1, -12.0), _kind(&"spark", 0)]
	var motes: MotesScript = own(MotesScript.new(cap, 0, kinds)) as MotesScript
	root.add_child(motes)
	return motes


## One mote of kind 0 from `at`, thrown right and up, living `life` seconds.
func _chip(motes: MotesScript, at: Vector2, life: float = 3.0) -> void:
	motes.burst(0, at, Vector2.RIGHT, 1, Vector2(60.0, 60.0), 0.0, Vector2(50.0, 50.0), Vector2(life, life), 0, Color.WHITE, 4.0)


## `count` motes, a frame's worth (FRAME_ROWS) at a time, each frame stepped at `now`.
func _fill(motes: MotesScript, count: int, now: float = 0.0) -> void:
	var left: int = count
	while left > 0:
		var n: int = mini(left, MotesScript.FRAME_ROWS)
		motes.burst(0, Vector2.ZERO, Vector2.RIGHT, n, Vector2(10.0, 50.0), 360.0, Vector2(0.0, 20.0), Vector2(0.2, 1.0), 0, Color.WHITE)
		motes.step(now)
		left -= n


func _feel() -> Array:
	var bus: EventsScript = own(EventsScript.new()) as EventsScript
	var feel: FeelScript = own(FeelScript.new()) as FeelScript
	var preset := FeelPresetScript.new()
	preset.hit_sound = &""
	feel.events = bus
	feel.registry = registry
	feel.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	feel.projectiles = own(ProjectilesScript.new()) as ProjectilesScript
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)
	return [bus, feel]


## The kinds (by id) of the rows `from` to `to` (not included).
func _kinds_of_rows(motes: MotesScript, from: int, to: int) -> Array[StringName]:
	var found: Array[StringName] = []
	for row in range(from, to):
		var k: int = roundi(motes.row_data(row)[9] * MotesScript.KIND_CODE)
		var id: StringName = motes.kinds()[k].id
		if not found.has(id):
			found.append(id)
	return found


func test_the_ring_wraps_with_nothing_allocated() -> void:
	var motes: MotesScript = _pool(2048)
	# Every chunk's batch is made the first time a mote lands in it.
	_fill(motes, 2048)
	check_equal(motes.chunks_made(), 2, "both chunks made")
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for n in 100:
		motes.burst(1, Vector2(float(n), 0.0), Vector2.ZERO, 100, Vector2(10.0, 50.0), 360.0, Vector2(0.0, 20.0), Vector2(0.2, 1.0), 2, Color("e0592f"))
		motes.step(float(n) * 0.016)
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "10,000 more motes make no object")
	check_equal(motes.next_row(), (2048 + 10000) % 2048, "the ring wrapped")


func test_writing_past_the_cap_overwrites_the_oldest_row() -> void:
	var motes: MotesScript = _pool(1024)
	for n in 1024:
		_chip(motes, Vector2(0.0, 0.0))
		if n % 100 == 0:
			motes.step(0.0)
	check_equal(motes.next_row(), 0, "full: the next mote takes the first row")
	_chip(motes, Vector2(500.0, 300.0))
	var at: Vector3 = motes.mote_at(0, 0.0)
	check(Vector2(at.x, at.y).is_equal_approx(Vector2(500.0, 304.0)), "the oldest row is the newest mote now (its ground point 4 px below where it shows), got %s" % at)
	check_equal(motes.mote_at(1, 0.0).x, 0.0, "the next row is still the old mote")


func test_only_the_chunks_written_upload() -> void:
	var motes: MotesScript = _pool(8192)
	motes.step(0.0)
	check_equal(motes.uploads, 0, "nothing written, nothing uploaded")
	check_equal(motes.chunks_made(), 0, "and no batch made")
	_fill(motes, 150, 0.016)
	check_equal(motes.uploads, 1, "a burst of 150 in one chunk uploads it once")
	motes.step(0.032)
	check_equal(motes.uploads, 1, "a frame with no motes uploads nothing")
	_fill(motes, 750, 0.048)
	check_equal(motes.next_row(), 900, "900 written")
	var before: int = motes.uploads
	motes.burst(0, Vector2.ZERO, Vector2.UP, 200, Vector2(10.0, 50.0), 360.0, Vector2(0.0, 20.0), Vector2(1.0, 2.0), 0, Color.WHITE)
	motes.step(0.064)
	check_equal(motes.uploads - before, 2, "a burst across a chunk's end uploads both chunks")
	check_equal(motes.chunks_made(), 2, "two of the eight chunks made")


func test_a_frame_writes_at_most_its_rows() -> void:
	var motes: MotesScript = _pool(8192)
	motes.burst(0, Vector2.ZERO, Vector2.UP, MotesScript.FRAME_ROWS + 100, Vector2(10.0, 50.0), 360.0, Vector2(0.0, 20.0), Vector2(1.0, 2.0), 0, Color.WHITE)
	check_equal(motes.next_row(), MotesScript.FRAME_ROWS, "a flood is cut at the frame's rows")
	_chip(motes, Vector2.ZERO)
	check_equal(motes.next_row(), MotesScript.FRAME_ROWS, "and nothing more this frame")
	motes.step(0.016)
	_chip(motes, Vector2.ZERO)
	check_equal(motes.next_row(), MotesScript.FRAME_ROWS + 1, "the next frame writes again")
	check_equal(motes.written, MotesScript.FRAME_ROWS + 1, "every mote written is counted")
	check_equal(motes.cut, 2, "and each burst the frame's rows cut short or left out")


## P1c: a shot's motes cost nothing once only the rows the frame keeps for its moments (cues and
## reactions) are left (a storm sheds hundreds a frame past them), and the kinds of a look are
## worked out once.
func test_a_shed_past_the_frames_rows_writes_nothing() -> void:
	var motes: MotesScript = _pool(4096)
	var sheds: int = MotesScript.FRAME_ROWS - MotesScript.MOMENT_ROWS
	check(sheds > 0 and MotesScript.MOMENT_ROWS > 0, "the sheds and the moments both have rows")
	motes.burst(0, Vector2.ZERO, Vector2.UP, sheds, Vector2(10.0, 50.0), 360.0, Vector2(0.0, 20.0), Vector2(1.0, 2.0), 0, Color.WHITE)
	motes.shed(Vector2.ZERO, Vector2.LEFT, Color.WHITE, 0, FIRE_LOOK)
	motes.throw(motes.kind_index(&"chip"), Vector2.ZERO, Vector2.LEFT, 0, Color.WHITE)
	check_equal(motes.next_row(), sheds, "with only the moments' rows left, a shed and a wall's throw take none")
	check_equal(motes.cut, 2, "both counted as cut")
	motes.throw_part(motes.kind_index(&"ember"), Vector2.ZERO, Vector2.RIGHT, 0, Color.WHITE, 40, 0.0, 360.0, 1.0, false)
	check_equal(motes.next_row(), sheds + 40, "a cue's part still throws its motes")
	motes.burst(0, Vector2.ZERO, Vector2.UP, MotesScript.FRAME_ROWS, Vector2(10.0, 50.0), 360.0, Vector2(0.0, 20.0), Vector2(1.0, 2.0), 0, Color.WHITE)
	check_equal(motes.next_row(), MotesScript.FRAME_ROWS, "up to the frame's rows")
	motes.step(0.016)
	motes.shed(Vector2.ZERO, Vector2.LEFT, Color.WHITE, 0, FIRE_LOOK)
	check(motes.next_row() > MotesScript.FRAME_ROWS, "the next frame sheds again")


func test_a_looks_kinds_are_kept_and_its_flags_ignored() -> void:
	var motes: MotesScript = _pool(4096)
	var first: PackedInt32Array = motes.kinds_of_look(FIRE_LOOK | LIGHTNING_LOOK)
	check_equal(motes.kinds_of_look(FIRE_LOOK | LIGHTNING_LOOK), first, "asked again: the same kinds")
	check_equal(motes.kinds_of_look(FIRE_LOOK | MotesScript.LOOK_EXACT | MotesScript.LOOK_ENEMY_RAMP), motes.kinds_of_look(FIRE_LOOK), "a look's flags are not layers")
	check_equal(motes.kinds_of_look(0), PackedInt32Array([motes.kind_index(&"spark")]), "a look of no layer: layer 0's, kept apart")


func test_a_chunk_with_nothing_alive_is_hidden() -> void:
	var motes: MotesScript = _pool(4096)
	_chip(motes, Vector2.ZERO)
	motes.step(1.0)
	check_equal(motes.chunks_shown(), 1, "the chunk written is drawn")
	motes.step(2.9)
	check_equal(motes.chunks_shown(), 1, "while a mote in it can be alive (its life is 3 s)")
	motes.step(3.1)
	check_equal(motes.chunks_shown(), 0, "then hidden as its life ends, not LIFE_MAX after: no vertices")
	motes.step(3.2)
	motes.burst(0, Vector2.ZERO, Vector2.UP, 2, Vector2(10.0, 50.0), 360.0, Vector2.ZERO, Vector2(0.2, 0.5), 0, Color.WHITE)
	motes.step(3.3)
	check_equal(motes.chunks_shown(), 1, "a new burst shows it again")
	motes.step(3.75)
	check_equal(motes.chunks_shown(), 0, "for as long as that burst's longest life")
	_chip(motes, Vector2.ZERO)
	motes.step(6.0)
	check_equal(motes.chunks_shown(), 1, "and drawn again with a new mote")


func test_every_mote_kind_in_the_content_is_valid() -> void:
	var ids: Array[StringName] = registry.get_ids(&"motes")
	check(not ids.is_empty(), "the kinds are found")
	check(ids.size() <= MotesScript.MAX_KINDS, "no more than the shader holds")
	var plain: bool = false
	var surface: bool = false
	for id in ids:
		var kind := registry.get_resource(&"motes", id) as MoteKind
		check(kind != null, "%s is a MoteKind" % id)
		if kind == null:
			continue
		check_equal(kind.problems(), PackedStringArray(), "%s has no problems" % id)
		check_equal(kind.resource_path.get_file(), "%s.tres" % id, "%s is in its own file" % id)
		plain = plain or kind.look_layers.has(0)
		surface = surface or kind.surface
	check(plain, "a kind for a shot with no layer that has one")
	check(surface, "a kind for struck walls")
	var broken := MoteKind.new()
	broken.id = &"broken"
	broken.surface = true
	broken.look_layers = PackedInt32Array([1])
	broken.life = Vector2(2.0, 1.0)
	check_equal(broken.problems().size(), 2, "a surface kind with layers and a life backwards: %s" % [broken.problems()])


func test_the_shader_is_handed_each_kinds_numbers() -> void:
	var fast := _kind(&"fast", 0, 500.0)
	fast.drag = 7.0
	fast.wobble = 3.0
	fast.wobble_rate = 9.0
	fast.glow = 0.7
	fast.shade_from = 2
	var broken := _kind(&"", 0)
	var motes: MotesScript = _pool(1024, [_kind(&"first", 0), broken, fast])
	check_equal(motes.kinds().size(), 2, "a kind with problems is left out")
	var motion: PackedVector4Array = motes.shader_parameter(&"kind_motion")
	var sway: PackedVector4Array = motes.shader_parameter(&"kind_sway")
	check_equal(motion.size(), MotesScript.MAX_KINDS, "room for every kind")
	check_equal(motion[1], Vector4(500.0, 7.0, 0.3, 0.7), "gravity, drag, bounce, glow of the second kind")
	check_equal(sway[1], Vector4(3.0, 9.0, 2.0, 0.0), "its sway, rate and first shade")
	var code: String = FileAccess.get_file_as_string("res://gameplay/feel/mote.gdshader")
	check(code.contains("uniform vec4 kind_motion[%d];" % MotesScript.MAX_KINDS) and code.contains("uniform vec4 kind_sway[%d];" % MotesScript.MAX_KINDS), "the shader holds as many")
	var constants: Dictionary = (MotesScript as GDScript).get_script_constant_map()
	for name: String in ["LIFE_MAX", "SOURCE_CODE", "KIND_CODE", "HEIGHT_MAX", "EXACT_SOURCE", "TABLE_SOURCE"]:
		var mine: float = float(constants[name])
		check(code.contains("const float %s = %s;" % [name, ("%.2f" % mine).trim_suffix("0") if not is_equal_approx(mine, roundf(mine)) else "%.1f" % mine]), "the shader's %s is mote.gd's (%s)" % [name, mine])
	check(code.contains("const int SHAPE_SIZE = %d;" % MoteKind.SHAPE_SIZE), "the shader's SHAPE_SIZE is MoteKind's")
	check(code.contains("uniform vec4 kind_shape[%d];" % MotesScript.MAX_KINDS), "and holds every kind's shape")


func test_a_shape_is_its_frames_centred_on_the_mote() -> void:
	var kind := _kind(&"shaped")
	kind.shape = """
		##o

		.o.
		o#o
		.o.

		##
		##

		.
	"""
	var m: int = MoteKind.SHAPE_SIZE / 2
	var streak: PackedByteArray = kind.shape_pixels(0)
	check_equal(streak[m * MoteKind.SHAPE_SIZE + m - 1], MoteKind.PIXEL_BODY, "a streak: a pixel behind")
	check_equal(streak[m * MoteKind.SHAPE_SIZE + m], MoteKind.PIXEL_BODY, "its middle on the mote")
	check_equal(streak[m * MoteKind.SHAPE_SIZE + m + 1], MoteKind.PIXEL_HOT, "a bright head ahead")
	check_equal(streak.count(MoteKind.PIXEL_NONE), MoteKind.SHAPE_SIZE * MoteKind.SHAPE_SIZE - 3, "and nothing else")
	var plus: PackedByteArray = kind.shape_pixels(1)
	check_equal(plus[m * MoteKind.SHAPE_SIZE + m], MoteKind.PIXEL_BODY, "a plus: its middle on the mote")
	check_equal(plus[(m - 1) * MoteKind.SHAPE_SIZE + m], MoteKind.PIXEL_HOT, "its rim above")
	var chunk: PackedByteArray = kind.shape_pixels(2)
	check(chunk[m * MoteKind.SHAPE_SIZE + m] == MoteKind.PIXEL_BODY and chunk[(m + 1) * MoteKind.SHAPE_SIZE + m + 1] == MoteKind.PIXEL_BODY, "a 2x2 chunk: the mote and right and down of it")
	check_equal(kind.shape_pixels(3).count(MoteKind.PIXEL_NONE), MoteKind.SHAPE_SIZE * MoteKind.SHAPE_SIZE, "an empty frame (a blink)")
	check_equal(kind.shape_frames().size(), 4, "frames apart by blank lines, the indent and the lines round them left out")
	var ragged := _kind(&"ragged")
	ragged.shape = "o..\n#"
	var corner: PackedByteArray = ragged.shape_pixels(0)
	check(corner[m * MoteKind.SHAPE_SIZE + m - 1] == MoteKind.PIXEL_HOT and corner[(m + 1) * MoteKind.SHAPE_SIZE + m - 1] == MoteKind.PIXEL_BODY, "rows start at the left as written (the # under the o), the picture centred on its middle column: %s" % [corner])
	check_equal(kind.problems(), PackedStringArray(), "a fine shape")
	var motes: MotesScript = _pool(1024, [_kind(&"first", 0), kind])
	check_equal(motes.shape_value(1, 0, m + 1, m), MoteKind.PIXEL_HOT, "the atlas holds the kind's frames")
	check_equal(motes.shape_value(1, 1, m, m - 1), MoteKind.PIXEL_HOT, "each in its own square")
	check_equal(motes.shape_value(0, 0, m, m), MoteKind.PIXEL_BODY, "a kind with no shape of its own: one pixel")
	check(motes.shader_parameter(&"shape_atlas") is Texture2D, "the shader reads the atlas")


## P1c: a mote with no glow draws a quad only as big as its shape (most are a pixel or two), turned
## any way; the shader is handed each kind's reach.
func test_a_shapes_reach_is_as_far_as_its_pixels() -> void:
	var dot := _kind(&"dot")
	check_equal(MotesScript.reach_of(dot), 0, "one pixel: no reach")
	var chunk := _kind(&"chunk")
	chunk.shape = "#\n\n##\n##"
	check_equal(MotesScript.reach_of(chunk), 1, "a 2x2 frame: one pixel")
	var streak := _kind(&"streak")
	streak.shape = "##o"
	check_equal(MotesScript.reach_of(streak), 1, "a streak of three across")
	streak.shape_turns = true
	check_equal(MotesScript.reach_of(streak), 1, "turned 45 degrees it still ends a pixel out each way")
	var block := _kind(&"block")
	block.shape = "#####\n#####\n#####\n#####\n#####"
	check_equal(MotesScript.reach_of(block), 2, "the whole square")
	block.shape_turns = true
	check_equal(MotesScript.reach_of(block), 3, "turned, its corners reach past the square")
	var motes: MotesScript = _pool(1024, [dot, chunk, block])
	var sway: PackedVector4Array = motes.shader_parameter(&"kind_sway")
	check(sway[0].w == 0.0 and sway[1].w == 1.0 and sway[2].w == 3.0, "the shader is handed each kind's reach: %s" % [sway])
	var code: String = FileAccess.get_file_as_string("res://gameplay/feel/mote.gdshader")
	check(code.contains("reach = lit > 0.0 ? reach + GLOW_REACH : kind_sway[k].w;"), "and draws a mote with no glow that far")


func test_a_shapes_frames_play_as_its_kind_says() -> void:
	var looped := _kind(&"looped")
	looped.shape = "o\n\n#"
	looped.shape_play = "loop"
	looped.shape_rate = 12.0
	var turning := _kind(&"turning")
	turning.shape = "##o"
	turning.shape_play = "pick"
	turning.shape_turns = true
	var motes: MotesScript = _pool(1024, [looped, turning])
	var shapes: PackedVector4Array = motes.shader_parameter(&"kind_shape")
	check_equal(shapes[0], Vector4(2.0, 1.0, 12.0, 0.0), "two frames, looping 12 a second, not turning")
	check_equal(shapes[1], Vector4(1.0, 2.0, 8.0, 1.0), "one frame, picked, turning with its flight")


func test_a_broken_shape_is_named() -> void:
	var kind := _kind(&"broken")
	kind.shape = "######\n\nx\n\n.\n.\n.\n.\n.\n."
	kind.shape_play = "spin"
	check_equal(kind.problems().size(), 4, "too wide, an unknown mark, too many rows, an unknown play: %s" % [kind.problems()])
	kind.shape = "...\n\n."
	kind.shape_play = "life"
	check_equal(kind.problems().size(), 1, "a shape that draws nothing: %s" % [kind.problems()])
	kind.shape = "\n\n".join(PackedStringArray(["#", "#", "#", "#", "#", "#", "#", "#", "#"]))
	check_equal(kind.problems().size(), 1, "more frames than the atlas holds: %s" % [kind.problems()])


func test_a_shot_sheds_the_kinds_of_its_cards() -> void:
	var motes: MotesScript = _pool(4096)
	check_equal(motes.kinds_of_look(FIRE_LOOK), PackedInt32Array([motes.kind_index(&"ember")]), "fire's layer: embers")
	check_equal(motes.kinds_of_look(0), PackedInt32Array([motes.kind_index(&"spark")]), "no layer: the kinds of layer 0")
	check_equal(motes.kinds_of_look(BIGGER_LOOK), PackedInt32Array([motes.kind_index(&"spark")]), "a layer no kind names: layer 0's too")
	check_equal(motes.kinds_of_look(FIRE_LOOK | BIGGER_LOOK), PackedInt32Array([motes.kind_index(&"ember")]), "the layers that have kinds")
	check(not motes.kinds_of_look(FIRE_LOOK).has(motes.kind_index(&"chip")), "never a surface kind")
	motes.shed(Vector2.ZERO, Vector2.LEFT, Color("e0592f"), 2, FIRE_LOOK)
	var shed: int = motes.next_row()
	check(shed > 0, "a fire shot sheds")
	check_equal(_kinds_of_rows(motes, 0, shed), [&"ember"], "embers")
	var data: PackedFloat32Array = motes.row_data(0)
	check_equal(roundi(data[8] * MotesScript.SOURCE_CODE), 2, "in the ramp of its caster's shot")
	check(Color(data[12], data[13], data[14]).is_equal_approx(Color("e0592f")), "with its core colour")


func test_a_shot_of_two_layers_splits_its_motes() -> void:
	var content: Array[MoteKind] = []
	for found: Resource in registry.get_all(&"motes"):
		content.append(found as MoteKind)
	var motes: MotesScript = _pool(4096, content)
	var ember: MoteKind = motes.kinds()[motes.kind_index(&"ember")]
	motes.shed(Vector2.ZERO, Vector2.LEFT, Color("e0592f"), 0, FIRE_LOOK)
	check_equal(motes.next_row(), ember.count, "one kind: its whole burst")
	var before: int = motes.next_row()
	motes.shed(Vector2.ZERO, Vector2.LEFT, Color("e0592f"), 0, FIRE_LOOK | LIGHTNING_LOOK)
	var kinds: Array[StringName] = _kinds_of_rows(motes, before, motes.next_row())
	check(kinds.has(&"ember") and kinds.has(&"spark"), "fire and lightning: embers and sparks, got %s" % [kinds])
	var spark: MoteKind = motes.kinds()[motes.kind_index(&"spark")]
	check_equal(motes.next_row() - before, roundi(ember.count * 0.5) + roundi(spark.count * 0.5), "each half its burst")


func test_a_spells_source_is_its_casters_ramp_and_flags() -> void:
	check_equal(MotesScript.spell_source(2, 0), 2, "a hat ramp")
	check_equal(MotesScript.spell_source(ActorSeats.ActorsScript.RAMP_ENEMY, 0), MotesScript.ENEMY_SOURCE, "the enemies'")
	check_equal(MotesScript.spell_source(-1, 0), MotesScript.ENEMY_SOURCE, "no actor: the enemies'")
	check_equal(MotesScript.spell_source(1, MotesScript.LOOK_ENEMY_RAMP), MotesScript.ENEMY_SOURCE, "the enemy ramp's flag")
	check_equal(MotesScript.spell_source(3, MotesScript.LOOK_EXACT), 3 + MotesScript.EXACT_SOURCE, "an exact colour")
	check_equal(MotesScript.LOOK_ENEMY_RAMP, ProjectilesScript.LOOK_ENEMY_RAMP, "the projectile manager's enemy flag")
	check_equal(MotesScript.LOOK_EXACT, FeelScript.EXACT, "Feel's exact flag")


func test_other_colours_go_through_the_ramp_table() -> void:
	var motes: MotesScript = _pool(1024)
	var walls := PackedColorArray([Color("7a7694"), Color("4a4663"), Color("2b2840")])
	var source: int = motes.table_source(walls)
	check(source >= MotesScript.TABLE_SOURCE, "a row of the table")
	check_equal(motes.table_source(walls), source, "the same colours, the same row")
	check(motes.table_shade(source, 0).is_equal_approx(walls[0]) and motes.table_shade(source, 1).is_equal_approx(walls[0]), "white-hot and light: the lightest")
	check(motes.table_shade(source, 3).is_equal_approx(walls[2]), "shadow: the darkest")
	check(motes.table_source(PackedColorArray([Color.RED, Color.GREEN, Color.BLUE])) != source, "other colours, another row")
	check_equal(motes.table_source(PackedColorArray()), -1, "no colours, no source")
	check(motes.shader_parameter(&"ramp_table") is Texture2D, "the shader reads the table")


func test_a_room_sheds_the_colours_of_its_wall_art() -> void:
	var room := registry.get_resource(&"rooms", ARENA) as RoomBase
	check(room != null, "the crypt arena")
	if room == null:
		return
	var colours: PackedColorArray = room.surface_colors()
	check_equal(colours.size(), 3, "light, base, shadow: %s" % [colours])
	if colours.size() < 3:
		return
	check(colours[0].get_luminance() >= colours[1].get_luminance() and colours[1].get_luminance() >= colours[2].get_luminance(), "lightest first")
	var layout: Node = room.scene.instantiate()
	var floor_texture: Texture2D = (layout.get_node("Floor") as Sprite2D).texture
	layout.free()
	var floor_main := Color.hex(RoomBase._most_common(RoomBase._count_colours(floor_texture, {})))
	for colour in colours:
		check(not colour.is_equal_approx(floor_main), "never the floor's own colour %s (%s)" % [floor_main.to_html(false), colour.to_html(false)])
	var override := RoomBase.new()
	override.debris_colors = PackedColorArray([Color.BLACK, Color.WHITE])
	check_equal(override.surface_colors(), PackedColorArray([Color.WHITE, Color.WHITE, Color.BLACK]), "set colours win, lightest first")


func test_mote_land_is_where_its_flight_comes_to_rest() -> void:
	var motes: MotesScript = _pool(1024)
	motes.step(2.0)
	_chip(motes, Vector2(100.0, 100.0))
	var land: Vector3 = motes.mote_land(0)
	check(land.z > 2.0 and land.z < 2.0 + MotesScript.LIFE_MAX, "it comes to rest in its life, got %s" % land)
	var rest: Vector3 = motes.mote_at(0, land.z)
	check(is_zero_approx(rest.z) and Vector2(rest.x, rest.y).is_equal_approx(Vector2(land.x, land.y)), "on the floor where mote_land says, got %s" % rest)
	check(motes.mote_at(0, land.z + 0.5).is_equal_approx(rest), "and lies still")
	check(land.x > 100.0, "thrown right along the floor")
	check(motes.mote_at(0, 2.05).z > 0.0, "up in the air at first")
	var g: float = motes.kinds()[0].gravity
	var first: float = 2.0 + (50.0 + sqrt(50.0 * 50.0 + 2.0 * g * 4.0)) / g
	check(first < land.z, "it lands before it comes to rest")
	check(motes.mote_at(0, (first + land.z) * 0.5).z > 0.0, "it bounces up between")


func test_a_mote_that_never_lands_has_no_rest() -> void:
	var motes: MotesScript = _pool(1024)
	motes.burst(1, Vector2.ZERO, Vector2.ZERO, 1, Vector2(5.0, 5.0), 360.0, Vector2(20.0, 20.0), Vector2(2.0, 2.0), 0, Color.WHITE)
	check(is_inf(motes.mote_land(0).z), "a kind that rises never lands")
	_chip(motes, Vector2.ZERO, 0.05)
	check(is_inf(motes.mote_land(1).z), "one gone before it lands has no rest")


func test_a_wall_hit_sheds_the_shots_motes_and_the_walls() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var motes: MotesScript = feel.motes()
	check(motes != null and motes.cap() == MoteCap.default_cap(), "motes on at the platform's cap")
	check(motes.kind_index(&"chip") >= 0 and motes.kind_index(&"ember") >= 0, "the content's kinds")
	feel.projectiles.impact_look = FIRE_LOOK
	feel.projectiles.impact_core = Color("e0592f")
	bus.projectile_impact.emit(1, null, Vector2(96.0, 100.0), Vector2.RIGHT)
	check_equal(_kinds_of_rows(motes, 0, motes.next_row()), [&"ember"], "before any room: only the shot's own")
	check_equal(feel.effects_of(FeelScript.KIND_CHIPS), 0, "no chips effect besides")
	for row in motes.next_row():
		check(motes.row_data(row)[0] < 0.0, "mote %d flies back off the wall" % row)
	bus.room_entered.emit(ARENA)
	var before: int = motes.next_row()
	bus.projectile_impact.emit(1, null, Vector2(96.0, 100.0), Vector2.RIGHT)
	var kinds: Array[StringName] = _kinds_of_rows(motes, before, motes.next_row())
	check(kinds.has(&"ember") and kinds.has(&"chip"), "in a room: the shot's and the wall's, got %s" % [kinds])
	var chip_row: int = motes.next_row() - 1
	var source: int = roundi(motes.row_data(chip_row)[8] * MotesScript.SOURCE_CODE)
	var room := registry.get_resource(&"rooms", ARENA) as RoomBase
	check(source >= MotesScript.TABLE_SOURCE and motes.table_shade(source, 3).is_equal_approx(room.surface_colors()[2]), "the chips in the room's wall colours")
	feel.step(0.016)
	check_equal(motes.uploads, 1, "uploaded on the next frame")


func test_with_particles_off_there_are_no_motes_and_the_chips_effect_shows() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	bus.room_entered.emit(ARENA)
	bus.mote_cap_changed.emit(0)
	check(feel.motes() == null, "no motes")
	check(feel.get_node_or_null("Motes") == null, "and no nodes")
	check_equal(feel.mote_cap, 0, "the setting taken")
	bus.projectile_impact.emit(0, null, Vector2(96.0, 100.0), Vector2.RIGHT)
	check_equal(feel.effects_of(FeelScript.KIND_CHIPS), 1, "the chips effect instead")
	feel.step(0.016)
	bus.mote_cap_changed.emit(MoteCap.STOPS[1])
	check(feel.motes() != null and feel.motes().cap() == MoteCap.STOPS[1], "on again at the new cap")
	bus.projectile_impact.emit(0, null, Vector2(96.0, 100.0), Vector2.RIGHT)
	check(_kinds_of_rows(feel.motes(), 0, feel.motes().next_row()).has(&"chip"), "and the room's walls still shed")
	check_equal(feel.set_mote_cap(1 << 20), MoteCap.STOPS[-1], "never past the top stop")


## P1c: the benchmarks hand Feel a pool of their own (a timed one), which it then uses like its own.
func test_feel_takes_a_pool_handed_to_it() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	bus.room_entered.emit(ARENA)
	var timed: MotesScript = TimedMotesScript.new(MoteCap.STOPS[1], FeelScript.MOTE_Z, feel.motes().kinds())
	feel.use_motes(timed)
	check(feel.motes() == timed and feel.get_node_or_null("Motes") == timed, "the pool handed is Feel's motes")
	check_equal(feel.mote_cap, MoteCap.STOPS[1], "its cap is the setting's")
	bus.projectile_impact.emit(0, null, Vector2(96.0, 100.0), Vector2.RIGHT)
	check(_kinds_of_rows(timed, 0, timed.next_row()).has(&"chip"), "a wall hit sheds into it, in the room's colours")
	check(int(timed.get(&"usec")) >= 0 and timed.written > 0, "and it counts what it wrote")
	feel.use_motes(null)
	check(feel.motes() == null and feel.get_node_or_null("Motes") == null and feel.mote_cap == 0, "null turns the motes off")


# --- P1b: the sources ---------------------------------------------------------------------------


## The rows written by `call` (a Callable taking nothing), as the kinds (by id) they are.
func _shed_by(motes: MotesScript, call: Callable) -> Array[StringName]:
	var before: int = motes.next_row()
	call.call()
	motes.step(0.0)
	return _kinds_of_rows(motes, before, motes.next_row())


## A body that dies: a node with a `Sprite` of a 2x1 sheet whose shown frame is in `colours`.
func _body(colours: PackedColorArray) -> Node2D:
	var image := Image.create_empty(8, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.MAGENTA)
	for x in 4:
		for y in 4:
			image.set_pixel(4 + x, y, colours[mini(y, colours.size() - 1)])
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.hframes = 2
	sprite.frame = 1
	var body := Node2D.new()
	body.add_child(sprite)
	root.add_child(body)
	return own(body) as Node2D


func test_a_hit_on_a_body_sheds_the_shots_kinds_back_along_its_way() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var motes: MotesScript = feel.motes()
	feel.projectiles.impact_look = FROST_LOOK
	feel.projectiles.impact_core = Color("8fd3ff")
	var target: Node2D = _body(PackedColorArray([Color.GRAY]))
	var kinds: Array[StringName] = _shed_by(motes, func() -> void: bus.projectile_impact.emit(1, target, Vector2(50.0, 50.0), Vector2.RIGHT))
	check_equal(kinds, [&"fleck"], "a frost shot's flecks")
	for row in motes.next_row():
		check(motes.row_data(row)[0] <= 0.0, "mote %d flies back the way the shot came" % row)
	feel.particles_enabled = false
	check_equal(_shed_by(motes, func() -> void: bus.projectile_impact.emit(1, target, Vector2(50.0, 50.0), Vector2.RIGHT)), [] as Array[StringName], "none with particles off (the stress benchmark)")


func test_a_shot_whose_life_runs_out_puffs_its_kinds() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var motes: MotesScript = feel.motes()
	feel.projectiles.impact_body = ProjectilesScript.KIND_BOLT
	feel.projectiles.impact_look = FIRE_LOOK
	feel.projectiles.impact_heading = Vector2.DOWN
	check_equal(_shed_by(motes, func() -> void: bus.projectile_expired.emit(0, Vector2(20.0, 20.0), 0, -1)), [&"ember"], "a fire bolt puffs embers")
	feel.projectiles.expired_on_wall = true
	check_equal(_shed_by(motes, func() -> void: bus.projectile_expired.emit(0, Vector2(20.0, 20.0), 0, -1)), [] as Array[StringName], "one that ended on a wall already shed there")


func test_a_reaction_throws_a_ring_in_its_colour() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var motes: MotesScript = feel.motes()
	var kinds: Array[StringName] = _shed_by(motes, func() -> void: bus.reaction_triggered.emit(0, &"shatter", Vector2(64.0, 64.0), -1))
	check_equal(kinds, [&"spark"], "no shot: layer 0's kinds")
	var tint: Color = feel.preset.reaction_colors.get(&"shatter", Color.WHITE) as Color
	var speeds: Array[float] = []
	for row in motes.next_row():
		var data: PackedFloat32Array = motes.row_data(row)
		check(roundi(data[8] * MotesScript.SOURCE_CODE) >= MotesScript.EXACT_SOURCE, "in an exact colour")
		check(Color(data[12], data[13], data[14]).is_equal_approx(tint), "the reaction's")
		speeds.append(Vector2(data[0], data[4]).length())
	check(speeds.min() >= speeds.max() * 0.89, "a ring: all about as fast, got %s to %s" % [speeds.min(), speeds.max()])


func test_an_enemy_death_sheds_the_killing_shots_kinds_and_its_own_colours() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var motes: MotesScript = feel.motes()
	var shot: int = feel.projectiles.spawn(0, Vector2.ZERO, Vector2.RIGHT * 100.0, 1.0)
	feel.projectiles.set_look(shot, FIRE_LOOK)
	var art := PackedColorArray([Color("d8d0b8"), Color("a09478"), Color("5c5444")])
	var enemy: Node2D = _body(art)
	var before: int = motes.next_row()
	bus.enemy_died.emit(1, enemy, Vector2(40.0, 40.0), shot)
	var kinds: Array[StringName] = _kinds_of_rows(motes, before, motes.next_row())
	check(kinds.has(&"ember") and kinds.has(&"chip"), "the killing shot's embers and the body's chips, got %s" % [kinds])
	var chips: int = 0
	for row in range(before, motes.next_row()):
		var data: PackedFloat32Array = motes.row_data(row)
		if motes.kinds()[roundi(data[9] * MotesScript.KIND_CODE)].id != &"chip":
			continue
		chips += 1
		var source: int = roundi(data[8] * MotesScript.SOURCE_CODE)
		check(source >= MotesScript.TABLE_SOURCE and motes.table_shade(source, 1).is_equal_approx(art[0]) and motes.table_shade(source, 3).is_equal_approx(art[2]), "a chip in the colours of the frame the body shows, not the room's or the sheet's")
	var boss_cue: CueBase = registry.get_resource(&"cues", &"boss_death") as CueBase
	var death_cue: CueBase = registry.get_resource(&"cues", &"enemy_death") as CueBase
	check(chips > 0 and boss_cue != null and death_cue != null, "chips were thrown")


func test_the_dense_cues_throw_their_kinds() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var motes: MotesScript = feel.motes()
	bus.room_entered.emit(ARENA)
	for id: StringName in [&"blast", &"fireball", &"slam", &"quake", &"nova", &"enemy_death", &"boss_death"]:
		var before: int = motes.next_row()
		feel.play_cue(id, 0, Vector2(100.0, 100.0), Vector2.RIGHT, 48.0, Color.WHITE, FIRE_LOOK)
		var written: int = motes.next_row() - before
		var kinds: Array[StringName] = _kinds_of_rows(motes, before, motes.next_row())
		check(written >= 8, "%s throws motes, got %d" % [id, written])
		if id != &"quake" and id != &"nova":
			check(kinds.has(&"ember") and kinds.has(&"chip"), "%s: its cards' and the ground's, got %s" % [id, kinds])
		motes.step(0.0)
	feel.particles_enabled = false
	var at: int = motes.next_row()
	feel.play_cue(&"blast", 0, Vector2(100.0, 100.0), Vector2.RIGHT, 48.0)
	check_equal(motes.next_row(), at, "none with particles off")


func test_a_parts_reach_is_as_far_as_its_motes_glide() -> void:
	var motes: MotesScript = _pool(4096)
	var k: int = motes.kind_index(&"chip")
	motes.throw_part(k, Vector2.ZERO, Vector2.RIGHT, 0, Color.WHITE, 200, 40.0, 360.0, 1.0, false)
	var drag: float = motes.kinds()[k].drag
	var farthest: float = 0.0
	for row in motes.next_row():
		var data: PackedFloat32Array = motes.row_data(row)
		farthest = maxf(farthest, Vector2(data[0], data[4]).length() / drag)
	check(farthest <= 40.0 + 0.01 and farthest > 30.0, "they glide out to the reach at the most, got %s" % farthest)


func test_the_particle_amount_scales_every_burst() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var motes: MotesScript = feel.motes()
	var k: int = motes.kind_index(&"chip")
	motes.throw_part(k, Vector2.ZERO, Vector2.RIGHT, 0, Color.WHITE, 40, 0.0, -1.0, 1.0, false)
	check_equal(motes.next_row(), 40, "at Full, as many as asked")
	motes.step(0.0)
	bus.mote_density_changed.emit(2.0)
	check_equal(feel.mote_density, 2.0, "the setting taken")
	motes.throw_part(k, Vector2.ZERO, Vector2.RIGHT, 0, Color.WHITE, 40, 0.0, -1.0, 1.0, false)
	check_equal(motes.next_row(), 120, "at Double, twice")
	motes.step(0.0)
	bus.mote_density_changed.emit(0.5)
	var thrown: int = 0
	for i in 40:
		var at: int = motes.next_row()
		motes.throw_part(k, Vector2.ZERO, Vector2.RIGHT, 0, Color.WHITE, 3, 0.0, -1.0, 1.0, false)
		thrown += motes.next_row() - at
		motes.step(0.0)
	check(thrown > 40 and thrown < 80, "at Half, half on average (a share of a mote now and then), got %d of 120" % thrown)
	bus.mote_density_changed.emit(0.0)
	var at_none: int = motes.next_row()
	feel.play_cue(&"blast", 0, Vector2.ZERO, Vector2.RIGHT, 48.0)
	check_equal(motes.next_row(), at_none, "at None, none")
	bus.mote_cap_changed.emit(MoteCap.STOPS[1])
	check_equal(feel.motes().density, 0.0, "a new ring keeps the amount")
	check_equal(feel.set_mote_density(0.7), 0.5, "snapped to a stop")


func test_every_kind_a_cue_names_is_there() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	var motes: MotesScript = feel.motes()
	var named: int = 0
	for found: Resource in registry.get_all(&"cues"):
		var cue := found as CueBase
		for part: Dictionary in cue.parts:
			if StringName(part.get("part", "")) != &"motes":
				continue
			named += 1
			var kind: StringName = StringName(part.get("kind", "spell"))
			check(CueBase.MOTE_GROUPS.has(kind) or motes.kind_index(kind) >= 0, "%s names the mote kind '%s', which is in content/motes" % [cue.id, kind])
	check(named >= 7, "the cues throw motes, %d parts" % named)


func test_with_motes_on_a_cues_chips_effect_gives_way_to_its_motes() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	feel.play_cue(&"slam", 0, Vector2(100.0, 100.0), Vector2.RIGHT, 40.0)
	check_equal(feel.effects_of(FeelScript.KIND_CHIPS), 0, "no chips effect")
	check(feel.motes().next_row() > 0, "its motes instead")
	check_equal(feel.effects_of(FeelScript.KIND_BURST), 1, "its other flashes stay")
