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
const MarksScript := preload("res://gameplay/feel/marks.gd")
## The settles left after a quiet room's blast of 100 chips (test_settles_are_budgeted_and_take_rows).
const SETTLE_LEFT_AFTER_100: int = MotesScript.SETTLE_MOST - 100
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


## The kinds (by id) of the motes written since `since` (a `Motes.mark`).
func _kinds_since(motes: MotesScript, since: Vector3i = Vector3i.ZERO) -> Array[StringName]:
	var found: Array[StringName] = []
	for mote: Dictionary in motes.motes_since(since):
		var id: StringName = motes.kinds()[int(mote.kind)].id
		if not found.has(id):
			found.append(id)
	return found


func test_the_ring_wraps_with_nothing_allocated() -> void:
	var motes: MotesScript = _pool(2048)
	# Every chunk's batch is made the first time a mote lands in it.
	# A ring of 16-mote rows: 2048 motes' rows, two chunks of CHUNK quads.
	_fill(motes, 2048)
	check_equal(motes.chunks_made(), 2, "both chunks made")
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for n in 100:
		motes.burst(1, Vector2(float(n), 0.0), Vector2.ZERO, 100, Vector2(10.0, 50.0), 360.0, Vector2(0.0, 20.0), Vector2(0.2, 1.0), 2, Color("e0592f"))
		motes.step(float(n) * 0.016)
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "10,000 more motes make no object")
	var rows: int = motes.ring_rows(MotesScript.BURSTS)
	check_equal(motes.next_row(MotesScript.BURSTS), motes.mark().z % rows, "the ring wrapped")
	check(motes.mark().z > rows, "past its rows: %d of %d" % [motes.mark().z, rows])


func test_writing_past_the_cap_overwrites_the_oldest_row() -> void:
	var motes: MotesScript = _pool(1024)
	var rows: int = motes.ring_rows(MotesScript.SINGLES)
	check_equal(rows, 1024 / MotesScript.SINGLES_SHARE, "a one-mote burst's ring")
	for n in rows:
		_chip(motes, Vector2(0.0, 0.0))
		if n % 50 == 0:
			motes.step(0.0)
	check_equal(motes.next_row(MotesScript.SINGLES), 0, "full: the next mote takes the first row")
	_chip(motes, Vector2(500.0, 300.0))
	var at: Vector3 = motes.mote_at(MotesScript.SINGLES, 0, 0, 0.0)
	check(Vector2(at.x, at.y).is_equal_approx(Vector2(500.0, 304.0)), "the oldest row is the newest mote now (its ground point 4 px below where it shows), got %s" % at)
	check_equal(motes.mote_at(MotesScript.SINGLES, 1, 0, 0.0).x, 0.0, "the next row is still the old mote")


func test_only_the_chunks_written_upload() -> void:
	var motes: MotesScript = _pool(8192)
	motes.step(0.0)
	check_equal(motes.uploads, 0, "nothing written, nothing uploaded")
	check_equal(motes.chunks_made(), 0, "and no batch made")
	_fill(motes, 150, 0.016)
	check_equal(motes.uploads, 1, "a burst of 150 in one chunk uploads it once")
	motes.step(0.032)
	check_equal(motes.uploads, 1, "a frame with no motes uploads nothing")
	# 16-mote rows: CHUNK / 16 rows a chunk.
	_fill(motes, MotesScript.CHUNK - 150 - 32 - 10, 0.048)
	check_equal(motes.next_row(MotesScript.BURSTS), MotesScript.CHUNK / MotesScript.BURST_QUADS - 2, "a chunk's rows but two written")
	var before: int = motes.uploads
	motes.burst(0, Vector2.ZERO, Vector2.UP, 64, Vector2(10.0, 50.0), 360.0, Vector2(0.0, 20.0), Vector2(1.0, 2.0), 0, Color.WHITE)
	motes.step(0.064)
	check_equal(motes.uploads - before, 2, "a burst across a chunk's end uploads both chunks")
	check_equal(motes.chunks_made(), 2, "two chunks made")


func test_a_frame_writes_at_most_its_rows() -> void:
	var motes: MotesScript = _pool(8192)
	var most: int = MotesScript.FRAME_ROWS * MotesScript.BURST_QUADS
	motes.burst(0, Vector2.ZERO, Vector2.UP, most + 100, Vector2(10.0, 50.0), 360.0, Vector2(0.0, 20.0), Vector2(1.0, 2.0), 0, Color.WHITE)
	check_equal(motes.mark(), Vector3i(0, 0, MotesScript.FRAME_ROWS), "a flood is cut at the frame's rows")
	check_equal(motes.written, most, "BURST_QUADS motes a row")
	_chip(motes, Vector2.ZERO)
	check_equal(motes.written, most, "and nothing more this frame")
	motes.step(0.016)
	_chip(motes, Vector2.ZERO)
	check_equal(motes.mark(), Vector3i(1, 0, MotesScript.FRAME_ROWS), "the next frame writes again")
	check_equal(motes.written, most + 1, "every mote written is counted")
	check_equal(motes.cut, 2, "and each burst the frame's rows cut short or left out")


## P1c: a shot's motes cost nothing once only the rows the frame keeps for its moments (cues and
## reactions) are left (a storm sheds hundreds a frame past them), and the kinds of a look are
## worked out once.
func test_a_shed_past_the_frames_rows_writes_nothing() -> void:
	var motes: MotesScript = _pool(4096)
	var sheds: int = MotesScript.FRAME_ROWS - MotesScript.MOMENT_ROWS
	check(sheds > 0 and MotesScript.MOMENT_ROWS > 0, "the sheds and the moments both have rows")
	motes.burst(0, Vector2.ZERO, Vector2.UP, sheds * MotesScript.BURST_QUADS, Vector2(10.0, 50.0), 360.0, Vector2(0.0, 20.0), Vector2(1.0, 2.0), 0, Color.WHITE)
	var written: int = motes.written
	motes.shed(Vector2.ZERO, Vector2.LEFT, Color.WHITE, 0, FIRE_LOOK)
	motes.throw(motes.kind_index(&"chip"), Vector2.ZERO, Vector2.LEFT, 0, Color.WHITE)
	check_equal(motes.written, written, "with only the moments' rows left, a shed and a wall's throw take none")
	check_equal(motes.cut, 2, "both counted as cut")
	motes.throw_part(motes.kind_index(&"ember"), Vector2.ZERO, Vector2.RIGHT, 0, Color.WHITE, 40, 0.0, 360.0, 1.0, false)
	check_equal(motes.written, written + 40, "a cue's part still throws its motes")
	check_equal(motes.mark().z, sheds + 3, "in three rows")
	motes.burst(0, Vector2.ZERO, Vector2.UP, MotesScript.FRAME_ROWS * MotesScript.BURST_QUADS, Vector2(10.0, 50.0), 360.0, Vector2(0.0, 20.0), Vector2(1.0, 2.0), 0, Color.WHITE)
	check_equal(motes.mark().z, MotesScript.FRAME_ROWS, "up to the frame's rows")
	motes.step(0.016)
	written = motes.written
	motes.shed(Vector2.ZERO, Vector2.LEFT, Color.WHITE, 0, FIRE_LOOK)
	check(motes.written > written, "the next frame sheds again")


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
		# Every card a kind names by id is a card (spell-spectacle-2.md, S2).
		for card in kind.cards:
			check(registry.get_resource(&"spells", card) != null, "%s names the card %s, which exists" % [id, card])
	check(plain, "a kind for a shot with no layer that has one")
	check(surface, "a kind for struck walls")
	var broken := MoteKind.new()
	broken.id = &"broken"
	broken.surface = true
	broken.look_layers = PackedInt32Array([1])
	broken.life = Vector2(2.0, 1.0)
	check_equal(broken.problems().size(), 2, "a surface kind with layers and a life backwards: %s" % [broken.problems()])
	broken.look_layers = PackedInt32Array()
	broken.life = Vector2(1.0, 2.0)
	broken.cards = [&"fire"]
	check_equal(broken.problems().size(), 1, "a surface kind naming a card: %s" % [broken.problems()])
	var named := _kind(&"named", 0)
	named.look_layers = PackedInt32Array()
	check_equal(named.problems(), PackedStringArray(), "a kind that names nothing is fine: only what names it throws it")


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
	var table: Texture2D = motes.shader_parameter(&"kind_table")
	check(table != null and table.get_width() == MotesScript.KIND_COLUMNS and table.get_height() >= 2, "a row a kind, KIND_COLUMNS across")
	check_equal(motes.kind_numbers(1)[0], Vector4(500.0, 7.0, 0.3, 0.7), "gravity, drag, bounce, glow of the second kind")
	check_equal(motes.kind_numbers(1)[1], Vector4(3.0, 9.0, 2.0, 0.0), "its sway, rate and first shade")
	check_equal(table.get_image().get_format(), Image.FORMAT_RGBAF, "in full floats, as the GDScript flight reads them")
	var code: String = FileAccess.get_file_as_string("res://gameplay/feel/mote.gdshader")
	check(code.contains("uniform sampler2D kind_table") and code.contains("const int MAX_KINDS = %d;" % MotesScript.MAX_KINDS), "the shader reads the table, and MAX_KINDS is mote.gd's")
	check(MotesScript.KIND_CODE + 1.0 >= float(MotesScript.MAX_KINDS), "a row's kind code tells every kind apart")
	var constants: Dictionary = (MotesScript as GDScript).get_script_constant_map()
	for name: String in ["LIFE_MAX", "SOURCE_CODE", "KIND_CODE", "HEIGHT_MAX", "EXACT_SOURCE", "TABLE_SOURCE"]:
		var mine: float = float(constants[name])
		check(code.contains("const float %s = %s;" % [name, ("%.2f" % mine).trim_suffix("0") if not is_equal_approx(mine, roundf(mine)) else "%.1f" % mine]), "the shader's %s is mote.gd's (%s)" % [name, mine])
	check(code.contains("const int SHAPE_SIZE = %d;" % MoteKind.SHAPE_SIZE), "the shader's SHAPE_SIZE is MoteKind's")
	check(code.contains("vec4 shape = texelFetch(kind_table, ivec2(2, k), 0);"), "and reads every kind's shape from its row")


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
	var reaches: Array[float] = [motes.kind_numbers(0)[1].w, motes.kind_numbers(1)[1].w, motes.kind_numbers(2)[1].w]
	check_equal(reaches, [0.0, 1.0, 3.0] as Array[float], "the shader is handed each kind's reach")
	var code: String = FileAccess.get_file_as_string("res://gameplay/feel/mote.gdshader")
	check(code.contains("reach = lit > 0.0 ? reach + GLOW_REACH : sway.w;"), "and draws a mote with no glow that far")


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
	check_equal(motes.kind_numbers(0)[2], Vector4(2.0, 1.0, 12.0, 0.0), "two frames, looping 12 a second, not turning")
	check_equal(motes.kind_numbers(1)[2], Vector4(1.0, 2.0, 8.0, 1.0), "one frame, picked, turning with its flight")


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
	check(motes.written > 0, "a fire shot sheds")
	check_equal(_kinds_since(motes), [&"ember"], "embers")
	var mote: Dictionary = motes.motes_since()[0]
	check_equal(mote.source, 2, "in the ramp of its caster's shot")
	check((mote.core as Color).is_equal_approx(Color("e0592f")), "with its core colour")


func test_a_shot_of_two_layers_splits_its_motes() -> void:
	var content: Array[MoteKind] = []
	for found: Resource in registry.get_all(&"motes"):
		content.append(found as MoteKind)
	var motes: MotesScript = _pool(4096, content)
	var ember: MoteKind = motes.kinds()[motes.kind_index(&"ember")]
	motes.shed(Vector2.ZERO, Vector2.LEFT, Color("e0592f"), 0, FIRE_LOOK)
	check_equal(motes.written, ember.count, "one kind: its whole burst")
	var before: Vector3i = motes.mark()
	motes.shed(Vector2.ZERO, Vector2.LEFT, Color("e0592f"), 0, FIRE_LOOK | LIGHTNING_LOOK)
	var kinds: Array[StringName] = _kinds_since(motes, before)
	check(kinds.has(&"ember") and kinds.has(&"spark"), "fire and lightning: embers and sparks, got %s" % [kinds])
	var spark: MoteKind = motes.kinds()[motes.kind_index(&"spark")]
	check_equal(motes.written - ember.count, roundi(ember.count * 0.5) + roundi(spark.count * 0.5), "each half its burst")


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
	var single: int = MotesScript.SINGLES
	var land: Vector3 = motes.mote_land(single, 0, 0)
	check(land.z > 2.0 and land.z < 2.0 + MotesScript.LIFE_MAX, "it comes to rest in its life, got %s" % land)
	var rest: Vector3 = motes.mote_at(single, 0, 0, land.z)
	check(is_zero_approx(rest.z) and Vector2(rest.x, rest.y).is_equal_approx(Vector2(land.x, land.y)), "on the floor where mote_land says, got %s" % rest)
	check(motes.mote_at(single, 0, 0, land.z + 0.5).is_equal_approx(rest), "and lies still")
	check(land.x > 100.0, "thrown right along the floor")
	check(motes.mote_at(single, 0, 0, 2.05).z > 0.0, "up in the air at first")
	var g: float = motes.kinds()[0].gravity
	var first: float = 2.0 + (50.0 + sqrt(50.0 * 50.0 + 2.0 * g * 4.0)) / g
	check(first < land.z, "it lands before it comes to rest")
	check(motes.mote_at(single, 0, 0, (first + land.z) * 0.5).z > 0.0, "it bounces up between")
	# A burst row: every mote lands where its flight says.
	motes.burst(0, Vector2(50.0, 80.0), Vector2.UP, 16, Vector2(20.0, 90.0), 300.0, Vector2(10.0, 60.0), Vector2(3.0, 3.5), 0, Color.WHITE, 6.0)
	for q in 16:
		var landed: Vector3 = motes.mote_land(MotesScript.BURSTS, 0, q)
		var there: Vector3 = motes.mote_at(MotesScript.BURSTS, 0, q, landed.z + 0.01)
		check(is_zero_approx(there.z) and Vector2(there.x, there.y).distance_to(Vector2(landed.x, landed.y)) < 0.01, "mote %d of a row rests where mote_land says: %s, %s" % [q, landed, there])


func test_a_mote_that_never_lands_has_no_rest() -> void:
	var motes: MotesScript = _pool(1024)
	motes.burst(1, Vector2.ZERO, Vector2.ZERO, 1, Vector2(5.0, 5.0), 360.0, Vector2(20.0, 20.0), Vector2(2.0, 2.0), 0, Color.WHITE)
	check(is_inf(motes.mote_land(MotesScript.SINGLES, 0, 0).z), "a kind that rises never lands")
	_chip(motes, Vector2.ZERO, 0.05)
	check(is_inf(motes.mote_land(MotesScript.SINGLES, 1, 0).z), "one gone before it lands has no rest")


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
	check_equal(_kinds_since(motes), [&"ember"], "before any room: only the shot's own")
	for mote: Dictionary in motes.motes_since():
		check((mote.vel as Vector2).x < 0.0, "mote %d flies back off the wall" % mote.q)
	bus.room_entered.emit(ARENA)
	var before: Vector3i = motes.mark()
	bus.projectile_impact.emit(1, null, Vector2(96.0, 100.0), Vector2.RIGHT)
	var kinds: Array[StringName] = _kinds_since(motes, before)
	check(kinds.has(&"ember") and kinds.has(&"chip"), "in a room: the shot's and the wall's, got %s" % [kinds])
	var source: int = -1
	for mote: Dictionary in motes.motes_since(before):
		if motes.kinds()[int(mote.kind)].id == &"chip":
			source = mote.source
	var room := registry.get_resource(&"rooms", ARENA) as RoomBase
	check(source >= MotesScript.TABLE_SOURCE and motes.table_shade(source, 3).is_equal_approx(room.surface_colors()[2]), "the chips in the room's wall colours")
	feel.step(0.016)
	check_equal(motes.uploads, 1, "uploaded on the next frame")


## S3: there is no Off. The smallest "Particles" stop is a Minimal ring, and a 0 (a cap saved as
## Off before S3) is taken as it: the motes, and nothing drawn instead of them, always.
func test_particles_has_no_off_its_least_is_a_minimal_ring() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	bus.room_entered.emit(ARENA)
	check_equal(MoteCap.STOPS[0], 2048, "the Minimal stop")
	check_equal(MoteCap.word_of(0), "Minimal", "a saved 0 reads as Minimal")
	bus.mote_cap_changed.emit(0)
	check(feel.motes() != null and feel.motes().cap() == MoteCap.STOPS[0], "a 0 is the Minimal ring")
	check_equal(feel.mote_cap, MoteCap.STOPS[0], "the setting taken")
	bus.projectile_impact.emit(0, null, Vector2(96.0, 100.0), Vector2.RIGHT)
	check(_kinds_since(feel.motes()).has(&"chip"), "a wall still sheds its chips as motes")
	check_equal(feel.live_effects(), 1, "and only the shot's burst is an effect")
	feel.step(0.016)
	bus.mote_cap_changed.emit(MoteCap.STOPS[1])
	check(feel.motes() != null and feel.motes().cap() == MoteCap.STOPS[1], "on again at the new cap")
	bus.projectile_impact.emit(0, null, Vector2(96.0, 100.0), Vector2.RIGHT)
	check(_kinds_since(feel.motes()).has(&"chip"), "and the room's walls still shed")
	check_equal(feel.set_mote_cap(1 << 20), MoteCap.STOPS[-1], "never past the top stop")


## P1c: the benchmarks hand Feel a pool of their own (a timed one), which it then uses like its own.
func test_feel_takes_a_pool_handed_to_it() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	bus.room_entered.emit(ARENA)
	var timed: MotesScript = TimedMotesScript.new(MoteCap.STOPS[1], FeelScript.MOTE_Z, feel.motes().kinds())
	feel.use_motes(timed)
	check(feel.motes() == timed and feel.find_child("Motes", true, false) == timed, "the pool handed is Feel's motes")
	check_equal(feel.mote_cap, MoteCap.STOPS[1], "its cap is the setting's")
	bus.projectile_impact.emit(0, null, Vector2(96.0, 100.0), Vector2.RIGHT)
	check(_kinds_since(timed).has(&"chip"), "a wall hit sheds into it, in the room's colours")
	check(int(timed.get(&"usec")) >= 0 and timed.written > 0, "and it counts what it wrote")


# --- P1b: the sources ---------------------------------------------------------------------------


## The rows written by `call` (a Callable taking nothing), as the kinds (by id) they are.
func _shed_by(motes: MotesScript, call: Callable) -> Array[StringName]:
	var before: Vector3i = motes.mark()
	call.call()
	motes.step(0.0)
	return _kinds_since(motes, before)


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
	for mote: Dictionary in motes.motes_since():
		check((mote.vel as Vector2).x <= 0.0, "mote %d flies back the way the shot came" % mote.q)
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
	# Two rings: the puff's sparks (S3: motes, thrown with its flash) and the reaction's own, each
	# its own rows.
	var puff: int = feel.preset.puff_mote_count
	check(motes.written > puff, "the puff's sparks, then the reaction's ring")
	# A row holds one burst's motes: every row's motes are about as fast.
	var rows: Dictionary = {}
	for mote: Dictionary in motes.motes_since():
		check(int(mote.source) >= MotesScript.EXACT_SOURCE, "in an exact colour")
		check((mote.core as Color).is_equal_approx(tint), "the reaction's")
		var key: Vector2i = Vector2i(mote.ring, mote.row)
		if not rows.has(key):
			rows[key] = [] as Array[float]
		(rows[key] as Array[float]).append((mote.vel as Vector2).length())
	check(rows.size() >= 2, "the two rings' rows: %d" % rows.size())
	for key: Vector2i in rows:
		var speeds: Array[float] = rows[key]
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
	var before: Vector3i = motes.mark()
	bus.enemy_died.emit(1, enemy, Vector2(40.0, 40.0), shot)
	var kinds: Array[StringName] = _kinds_since(motes, before)
	check(kinds.has(&"ember") and kinds.has(&"chip"), "the killing shot's embers and the body's chips, got %s" % [kinds])
	var chips: int = 0
	for mote: Dictionary in motes.motes_since(before):
		if motes.kinds()[int(mote.kind)].id != &"chip":
			continue
		chips += 1
		var source: int = mote.source
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
		var before: Vector3i = motes.mark()
		var was: int = motes.written
		feel.play_cue(id, 0, Vector2(100.0, 100.0), Vector2.RIGHT, 48.0, Color.WHITE, FIRE_LOOK)
		var written: int = motes.written - was
		var kinds: Array[StringName] = _kinds_since(motes, before)
		check(written >= 8, "%s throws motes, got %d" % [id, written])
		if id != &"quake" and id != &"nova":
			check(kinds.has(&"ember") and kinds.has(&"chip"), "%s: its cards' and the ground's, got %s" % [id, kinds])
		motes.step(0.0)
	feel.particles_enabled = false
	var at: int = motes.written
	feel.play_cue(&"blast", 0, Vector2(100.0, 100.0), Vector2.RIGHT, 48.0)
	check_equal(motes.written, at, "none with particles off")


func test_a_parts_reach_is_as_far_as_its_motes_glide() -> void:
	var motes: MotesScript = _pool(4096)
	var k: int = motes.kind_index(&"chip")
	motes.throw_part(k, Vector2.ZERO, Vector2.RIGHT, 0, Color.WHITE, 200, 40.0, 360.0, 1.0, false)
	var drag: float = motes.kinds()[k].drag
	var farthest: float = 0.0
	for mote: Dictionary in motes.motes_since():
		farthest = maxf(farthest, (mote.vel as Vector2).length() / drag)
	check(farthest <= 40.0 + MotesScript.SPEED_STEP / drag and farthest > 30.0, "they glide out to the reach at the most, got %s" % farthest)


func test_the_particle_amount_scales_every_burst() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var motes: MotesScript = feel.motes()
	var k: int = motes.kind_index(&"chip")
	motes.throw_part(k, Vector2.ZERO, Vector2.RIGHT, 0, Color.WHITE, 40, 0.0, -1.0, 1.0, false)
	check_equal(motes.written, 40, "at Full, as many as asked")
	motes.step(0.0)
	bus.mote_density_changed.emit(2.0)
	check_equal(feel.mote_density, 2.0, "the setting taken")
	motes.throw_part(k, Vector2.ZERO, Vector2.RIGHT, 0, Color.WHITE, 40, 0.0, -1.0, 1.0, false)
	check_equal(motes.written, 120, "at Double, twice")
	motes.step(0.0)
	bus.mote_density_changed.emit(0.5)
	var thrown: int = 0
	for i in 40:
		var at: int = motes.written
		motes.throw_part(k, Vector2.ZERO, Vector2.RIGHT, 0, Color.WHITE, 3, 0.0, -1.0, 1.0, false)
		thrown += motes.written - at
		motes.step(0.0)
	check(thrown > 40 and thrown < 80, "at Half, half on average (a share of a mote now and then), got %d of 120" % thrown)
	bus.mote_density_changed.emit(0.0)
	var at_none: int = motes.written
	feel.play_cue(&"blast", 0, Vector2.ZERO, Vector2.RIGHT, 48.0)
	check_equal(motes.written, at_none, "at None, none")
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


func test_a_cues_chips_are_its_motes() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	feel.play_cue(&"slam", 0, Vector2(100.0, 100.0), Vector2.RIGHT, 40.0)
	check(feel.motes().written > 0, "its motes")
	check_equal(feel.effects_of(FeelScript.KIND_BURST), 1, "its other flashes stay")


## Trail particles as motes (spell spectacle P1d): each birth the projectile manager hands out is
## one mote of its look kind's layer (layer 0's for a kind with none, a plain shot's twinkle too),
## given off back along the shot slower than a burst, in the shot's own ramp and core colour.
func test_a_trails_births_are_one_mote_each() -> void:
	var motes: MotesScript = _pool(4096)
	var stride: int = MotesScript.BIRTH_STRIDE
	check_equal(stride, ProjectilesScript.SPARK_BIRTH_STRIDE, "the manager's layout")
	var births := PackedFloat32Array()
	births.resize(stride * 3)
	var kinds: Array[int] = [ProjectilesScript.LOOK_EMBERS, ProjectilesScript.LOOK_DRIFT, 0]
	for n in 3:
		var i: int = n * stride
		births[i + ProjectilesScript.SPARK_X] = 10.0 * n
		births[i + ProjectilesScript.SPARK_Y] = 20.0
		births[i + ProjectilesScript.SPARK_BACK_X] = -1.0
		births[i + ProjectilesScript.SPARK_KIND] = float(kinds[n])
		births[i + ProjectilesScript.SPARK_RAMP] = 2.0
		births[i + ProjectilesScript.SPARK_LOOK] = float(FIRE_LOOK)
		births[i + ProjectilesScript.SPARK_CORE] = 0.9
		births[i + ProjectilesScript.SPARK_CORE + 1] = 0.3
		births[i + ProjectilesScript.SPARK_CORE + 2] = 0.1
	motes.give_off(births, 3)
	check_equal(motes.mark(), Vector3i(3, 0, 0), "one mote a birth, a single row each")
	var given: Array[Dictionary] = motes.motes_since()
	var ids: Array[StringName] = []
	for mote: Dictionary in given:
		ids.append(motes.kinds()[int(mote.kind)].id)
	check_equal(ids, [&"ember", &"spark", &"spark"] as Array[StringName], "fire's embers; a layer with no kind, and a twinkle: layer 0's")
	var ember: MoteKind = motes.kinds()[motes.kind_index(&"ember")]
	var first: Dictionary = given[0]
	check((first.vel as Vector2).x <= 0.0, "given off back along the shot")
	check((first.vel as Vector2).length() <= ember.speed.y * MotesScript.TRAIL_SPEED + MotesScript.SPEED_STEP, "slower than a burst")
	check_equal(first.source, 2, "in the ramp of its caster")
	check((first.core as Color).is_equal_approx(Color(0.9, 0.3, 0.1)), "with its core colour")
	motes.give_off(births, 0)
	check_equal(motes.written, 3, "no births, no motes")


## A chunk only the trails write to stays drawn while their motes live (it was hidden on the next
## step once P1c's chunks were hidden by their bursts' lives, which `give_off` did not keep).
func test_a_chunk_of_trail_motes_is_drawn_while_they_live() -> void:
	var motes: MotesScript = _pool(4096)
	var stride: int = MotesScript.BIRTH_STRIDE
	var births := PackedFloat32Array()
	births.resize(stride)
	births[ProjectilesScript.SPARK_BACK_X] = -1.0
	births[ProjectilesScript.SPARK_KIND] = float(ProjectilesScript.LOOK_EMBERS)
	births[ProjectilesScript.SPARK_RAMP] = 2.0
	births[ProjectilesScript.SPARK_LOOK] = float(FIRE_LOOK)
	births[ProjectilesScript.SPARK_CORE] = 1.0
	motes.step(10.0)
	motes.give_off(births, 1)
	var life: float = motes.motes_since()[0].life
	var longest: float = motes.kinds()[motes.kind_index(&"ember")].life.y
	motes.step(10.05)
	check_equal(motes.chunks_shown(), 1, "drawn the step after it is written")
	motes.step(10.0 + life * 0.9)
	check_equal(motes.chunks_shown(), 1, "and while its mote lives")
	motes.step(10.0 + longest + 0.1)
	check_equal(motes.chunks_shown(), 0, "then hidden, as a burst's chunk is: after the longest life its kind gives")


## Feel takes the trails' particles while it has motes, and hands them back to the shader when
## Particles is off.
func test_feel_takes_the_trails_particles_while_it_has_motes() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	var shots: ProjectilesScript = feel.projectiles
	root.add_child(shots)
	shots.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	for i in 10:
		var slot: int = shots.spawn(0, Vector2(20.0 + 30.0 * i, 100.0), Vector2(60.0, 0.0), 10.0)
		shots.set_look(slot, FIRE_LOOK)
	feel.step(1.0 / 60.0)
	check(shots.spark_motes, "Feel takes them")
	var before: int = feel.motes().written
	var births: int = 0
	for n in 20:
		shots.step(1.0 / 60.0)
		shots.update_draw(1.0)
		births += shots.spark_birth_count
		feel.step(1.0 / 60.0)
	check(births > 0, "the trails gave off particles: %d" % births)
	check_equal(feel.motes().written - before, births, "each a mote")
	feel.particles_enabled = false
	before = feel.motes().written
	for n in 5:
		shots.step(1.0 / 60.0)
		shots.update_draw(1.0)
		feel.step(1.0 / 60.0)
	check(shots.spark_motes, "with particles off (the stress benchmark's \"no particles\") the trails keep no particle slots")
	check_equal(feel.motes().written, before, "and none are thrown: no trail particles at all")
	feel.particles_enabled = true


## A birth for `give_off` (BIRTH_STRIDE floats) at `at`, given off back along `back`, of the look
## kind `layer`, from a shot of the caster's `ramp`, the look `look` and the core colour `core`.
func _births(at: Array[Vector2], layer: int, ramp: int, look: int, core: Color) -> PackedFloat32Array:
	var given := PackedFloat32Array()
	given.resize(at.size() * MotesScript.BIRTH_STRIDE)
	for n in at.size():
		var b: int = n * MotesScript.BIRTH_STRIDE
		given[b + ProjectilesScript.SPARK_X] = at[n].x
		given[b + ProjectilesScript.SPARK_Y] = at[n].y
		given[b + ProjectilesScript.SPARK_BACK_X] = -1.0
		given[b + ProjectilesScript.SPARK_KIND] = float(layer)
		given[b + ProjectilesScript.SPARK_RAMP] = float(ramp)
		given[b + ProjectilesScript.SPARK_LOOK] = float(look)
		given[b + ProjectilesScript.SPARK_CORE] = core.r
		given[b + ProjectilesScript.SPARK_CORE + 1] = core.g
		given[b + ProjectilesScript.SPARK_CORE + 2] = core.b
	return given


## A trail's mote is a one-mote burst (one place writes every row, so the two never drift apart:
## P1d's own writer once kept no chunk life and settled nothing).
func test_a_trail_mote_is_written_as_a_bursts() -> void:
	var trail: MotesScript = _pool(1024)
	var thrown: MotesScript = _pool(1024)
	var ember: MoteKind = trail.kinds()[1]
	var core := Color(0.9, 0.4, 0.1)
	trail.step(2.0)
	thrown.step(2.0)
	trail.give_off(_births([Vector2(40.0, 30.0)] as Array[Vector2], ProjectilesScript.LOOK_EMBERS, 2, FIRE_LOOK, core), 1)
	thrown.burst(1, Vector2(40.0, 30.0), Vector2.LEFT, 1, ember.speed * MotesScript.TRAIL_SPEED, ember.spread, ember.up * MotesScript.TRAIL_SPEED, ember.life, MotesScript.spell_source(2, FIRE_LOOK), core, ember.height)
	var a: PackedFloat32Array = trail.row_data(MotesScript.SINGLES, 0)
	var b: PackedFloat32Array = thrown.row_data(MotesScript.SINGLES, 0)
	# Each pool rolls its own seed; every other number is the same.
	a[MotesScript.ROW_SEED] = 0.0
	b[MotesScript.ROW_SEED] = 0.0
	check_equal(a, b, "the same row")
	check_equal(trail.written, 1, "counted as written")
	check_equal(trail.births, 1, "and as a birth")


## "Particle amount" at Double throws two motes a birth, all at the births handed over (it once
## read on past them, into births of earlier frames).
func test_double_the_particle_amount_doubles_each_birth() -> void:
	var motes: MotesScript = _pool(1024)
	motes.density = 2.0
	var at: Array[Vector2] = [Vector2(10.0, 20.0), Vector2(300.0, 40.0)]
	motes.give_off(_births(at, ProjectilesScript.LOOK_EMBERS, 0, FIRE_LOOK, Color.WHITE), 2)
	check_equal(motes.written, 4, "two motes a birth")
	for mote: Dictionary in motes.motes_since():
		var ground: Vector2 = (mote.ground as Vector2) - Vector2(0.0, mote.height)
		check(ground.is_equal_approx(at[0]) or ground.is_equal_approx(at[1]), "row %d at a birth handed over: %s" % [mote.row, ground])
	motes.density = 0.5
	motes.step(1.0)
	var before: int = motes.written
	var many: Array[Vector2] = []
	for n in 200:
		many.append(Vector2(n, 0.0))
	motes.give_off(_births(many, ProjectilesScript.LOOK_EMBERS, 0, FIRE_LOOK, Color.WHITE), 200)
	var half: int = motes.written - before
	check(half > 60 and half < 140, "at Half about one in two: %d of 200" % half)


## A shed or a wall's throw leaves the frame's last MOMENT_ROWS to the moments, even when it starts
## with a few more left than that.
func test_a_shed_never_writes_into_the_moments_rows() -> void:
	var motes: MotesScript = _pool(4096)
	motes.burst(2, Vector2.ZERO, Vector2.RIGHT, (MotesScript.FRAME_ROWS - MotesScript.MOMENT_ROWS - 1) * MotesScript.BURST_QUADS, Vector2(10.0, 50.0), 360.0, Vector2.ZERO, Vector2(0.2, 1.0), 0, Color.WHITE)
	var written: int = motes.written
	motes.shed(Vector2.ZERO, Vector2.RIGHT, Color.WHITE, 0, FIRE_LOOK, 20.0)
	check_equal(motes.written - written, MotesScript.BURST_QUADS, "the shed writes the one row past the reserve")
	written = motes.written
	motes.throw(0, Vector2.ZERO, Vector2.RIGHT, 0, Color.WHITE, 20.0)
	check_equal(motes.written - written, 0, "a wall's throw then writes none")
	motes.throw_part(0, Vector2.ZERO, Vector2.RIGHT, 0, Color.WHITE, MotesScript.MOMENT_ROWS * MotesScript.BURST_QUADS, 0.0, -1.0, 1.0, false)
	check_equal(motes.written - written, MotesScript.MOMENT_ROWS * MotesScript.BURST_QUADS, "and a moment has all of its rows")


## The settled marks a frame: SETTLE_ROWS more each frame, kept up to SETTLE_MOST, each taking a
## row of the frame's as well (a settle costs about a row), the rest counted as skipped: a flood of
## chips costs a bounded time, a quiet blast settles them all.
func test_settles_are_budgeted_and_take_rows() -> void:
	var chip := _kind(&"chip", -1)
	chip.settles = &"speck"
	var motes: MotesScript = _pool(4096, [chip, _kind(&"spark", 0)])
	var speck := MarkKind.new()
	speck.id = &"speck"
	speck.form = "speck"
	var marks: MarksScript = own(MarksScript.new(-1, [speck] as Array[MarkKind])) as MarksScript
	root.add_child(marks)
	marks.enter(Rect2(-100.0, -100.0, 800.0, 600.0), null, 8.0)
	marks.step(0.0)
	motes.settle_into(marks)
	motes.step(0.0)
	var chips: Callable = func() -> void:
		motes.burst(0, Vector2(100.0, 100.0), Vector2.RIGHT, 100, Vector2(10.0, 50.0), 360.0, Vector2(10.0, 40.0), Vector2(3.0, 3.0), 0, Color.WHITE, 4.0)
	chips.call()
	check_equal(motes.settles, 100, "a quiet room's blast of 100 chips settles them all")
	var rows: int = motes.mark().z
	check_equal(rows, 7, "in seven rows")
	motes.burst(1, Vector2.ZERO, Vector2.RIGHT, MotesScript.FRAME_ROWS * MotesScript.BURST_QUADS, Vector2(10.0, 50.0), 360.0, Vector2.ZERO, Vector2(1.0, 1.0), 0, Color.WHITE)
	check_equal(motes.mark().z - rows, MotesScript.FRAME_ROWS - 7 - 100, "each settle took a row of the frame's")
	var counts: Array[int] = []
	for frame in 3:
		motes.step(0.1 * (frame + 1))
		var before: int = motes.settles
		chips.call()
		counts.append(motes.settles - before)
	check_equal(counts, [SETTLE_LEFT_AFTER_100 + MotesScript.SETTLE_ROWS, MotesScript.SETTLE_ROWS, MotesScript.SETTLE_ROWS] as Array[int], "then SETTLE_ROWS a frame in a flood (what was left kept)")
	check(motes.settles_skipped > 0, "the rest skipped: %d" % motes.settles_skipped)
	for frame in 20:
		motes.step(1.0 + 0.1 * frame)
	var again: int = motes.settles
	chips.call()
	check_equal(motes.settles - again, 100, "quiet frames fill it up again, up to SETTLE_MOST")


## The shader's flight and `Motes.flight` (and `rest_time`, which `mote_land` and the settled marks
## use) are the same sums: each pair below is one line of each. A change to one fails here until
## the other changes with it.
func test_the_flight_is_the_shaders_line_for_line() -> void:
	var shader: String = FileAccess.get_file_as_string("res://gameplay/feel/mote.gdshader")
	var script: String = FileAccess.get_file_as_string("res://gameplay/feel/mote.gd")
	var pairs: Array[PackedStringArray] = [
		PackedStringArray(["land = (vz + sqrt(vz * vz + 2.0 * g * max(h0, 0.0))) / g;", "land = (vz + sqrt(vz * vz + 2.0 * g * maxf(h0, 0.0))) / g"]),
		PackedStringArray(["rebound = (g * land - vz) * motion.z;", "rebound = (g * land - vz) * kind.bounce"]),
		PackedStringArray(["rest = land + 2.0 * rebound / g;", "rest = land + 2.0 * rebound / g"]),
		PackedStringArray(["float tm = min(max(t, 0.0), rest);", "var tm: float = minf(maxf(t, 0.0), rest)"]),
		PackedStringArray(["h = h0 + vz * tm - 0.5 * g * tm * tm;", "h = h0 + vz * tm - 0.5 * g * tm * tm"]),
		PackedStringArray(["h = rebound * q - 0.5 * g * q * q;", "h = rebound * s - 0.5 * g * s * s"]),
		PackedStringArray(["float along = drag > 0.0 ? (1.0 - exp(-drag * tm)) / drag : tm;", "var along: float = (1.0 - exp(-drag * tm)) / drag if drag > 0.0 else tm"]),
		PackedStringArray(["float phase = s * 6.2832;", "var phase: float = seed * 6.2832"]),
		PackedStringArray(["ground.x += sway.x * (sin(tm * sway.y + phase) - sin(phase));", "ground.x += kind.wobble * (sin(tm * kind.wobble_rate + phase) - sin(phase))"]),
	]
	for pair in pairs:
		check(shader.contains(pair[0]), "the shader's mote_flight has: %s" % pair[0])
		check(script.contains(pair[1]), "and Motes.flight its twin: %s" % pair[1])
	check(script.contains("return land + 2.0 * rebound / g"), "rest_time ends where the flight comes to rest")
	# `_land` (mote_land and the settled marks) writes the flight out at its rest: the same sums.
	var land: String = script.substr(script.find("func _land("), script.find("## Row `row` of ring") - script.find("func _land("))
	for line: String in ["var land: float = (vz + sqrt(vz * vz + 2.0 * g * maxf(h0, 0.0))) / g", "var rebound: float = (g * land - vz) * kind.bounce", "var rest: float = land + 2.0 * rebound / g", "var along: float = ((1.0 - exp(-drag * rest)) / drag if drag > 0.0 else rest) * speed", "kind.wobble * (sin(rest * kind.wobble_rate + phase) - sin(phase))"]:
		check(land.contains(line), "_land has the flight's line: %s" % line)


## Numbers kept in two places agree: the trails' moments a second (the manager's rolls, the trail
## shader's BIRTHS), the look layers (the manager's look kinds), the longest life (MoteKind's), and
## the sources (a table row is past every spell's).
func test_the_numbers_shared_with_core_agree() -> void:
	check(ProjectilesScript.SPARK_STREAK < 0, "a dash's streak is no look layer (S5)")
	check_equal(MotesScript.LOOK_LAYERS, ProjectilesScript.LOOK_COUNT - 1, "a layer for every look kind past the plain shot")
	check_equal(MotesScript.LIFE_MAX, MoteKind.LIFE_MAX, "the longest life")
	check(MotesScript.TABLE_SOURCE >= MotesScript.ENEMY_SOURCE + 1 + MotesScript.EXACT_SOURCE, "a table row is past every spell's source (the enemies' exact one included)")
	check_equal(ProjectilesScript.SPARK_TAG, ProjectilesScript.SPARK_CORE + 3, "a birth's tag follows its core colour")
	check_equal(MotesScript.BIRTH_STRIDE, ProjectilesScript.SPARK_TAG + 2, "and a birth ends with its tag's two floats")
	check(ProjectilesScript.SPARK_TAG_BITS < 24 and (SpellTag.FLAG << 1) >> ProjectilesScript.SPARK_TAG_BITS < 1 << 24, "each of the tag's floats holds its part whole")


## S3: a hit's spray and a puff throw their sparks as motes (the effect draws only the flash): the
## preset's count of its kind along the hit's way, or all round as a ring; a staff's poof (a puff
## with the POOF bit) throws none, and a spray leaves the moments' rows alone, as a shed does.
func test_a_sprays_and_a_puffs_sparks_are_motes() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	var motes: MotesScript = feel.motes()
	feel.show_effect(FeelScript.KIND_SPRAY, Vector2(50.0, 50.0), Vector2.RIGHT, Color.WHITE, 0, 0, 1, FeelScript.SPRAY_SECONDS)
	check_equal(motes.written, feel.preset.spray_mote_count, "a spray's sparks")
	check_equal(_kinds_since(motes), [feel.preset.spray_mote_kind], "of the preset's kind")
	for mote: Dictionary in motes.motes_since():
		check((mote.vel as Vector2).x > 0.0, "spark %d flies on along the hit" % mote.q)
	motes.step(0.0)
	var before: Vector3i = motes.mark()
	var was: int = motes.written
	feel.show_effect(FeelScript.KIND_PUFF, Vector2(50.0, 50.0), Vector2.RIGHT, Color.WHITE, 0, 0, 2, FeelScript.PUFF_SECONDS)
	check_equal(motes.written - was, feel.preset.puff_mote_count, "a puff's sparks")
	var left: int = 0
	for mote: Dictionary in motes.motes_since(before):
		left += 1 if (mote.vel as Vector2).x < 0.0 else 0
	check(left > 0 and left < feel.preset.puff_mote_count, "all round")
	was = motes.written
	feel.show_effect(FeelScript.KIND_PUFF, Vector2(50.0, 50.0), Vector2.RIGHT, Color.WHITE, 0, FeelScript.POOF, 2, FeelScript.POOF_SECONDS)
	check_equal(motes.written, was, "a poof throws none")
	motes.step(0.0)
	motes.burst(2, Vector2.ZERO, Vector2.RIGHT, (MotesScript.FRAME_ROWS - MotesScript.MOMENT_ROWS) * MotesScript.BURST_QUADS, Vector2(10.0, 50.0), 360.0, Vector2.ZERO, Vector2(0.2, 1.0), 0, Color.WHITE)
	was = motes.written
	feel.show_effect(FeelScript.KIND_SPRAY, Vector2(50.0, 50.0), Vector2.RIGHT, Color.WHITE, 0, 0, 1, FeelScript.SPRAY_SECONDS)
	check_equal(motes.written, was, "a spray leaves the moments' rows alone")


## S3: a dead body breaks into motes of its own art (the white-hot copy that fell apart pixel by
## pixel before): about the preset's share of its pixels, each a surface mote in its art's colours,
## shown where that pixel was (inside the body's frame), resting on its feet; a bigger body more,
## up to the preset's most; at its rest scale even when killed mid-squash.
func test_a_dead_body_breaks_into_motes_of_its_art() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var motes: MotesScript = feel.motes()
	var husk: Texture2D = load("res://content/enemies/bone_husk/idle.svg") as Texture2D
	var body := _body_of(husk, Vector2(200.0, 150.0), 1.0)
	var pixels: int = RoomBase.pixels_of_art(husk).size()
	check(pixels > 50, "the husk's art has pixels: %d" % pixels)
	var before: Vector3i = motes.mark()
	var was: int = motes.written
	feel.spectacle().break_body(body, body.get_global_transform(), feel.preset.death_mote_kind, feel.preset.death_mote_share, feel.preset.death_mote_most, feel.preset.death_mote_speed, feel.preset.death_mote_up)
	var made_count: int = motes.written - was
	check_equal(made_count, roundi(float(pixels) * feel.preset.death_mote_share), "its share of the art's pixels")
	check_equal(_kinds_since(motes, before), [feel.preset.death_mote_kind], "of the preset's kind")
	var source: int = feel.spectacle().body_source(body)
	var frame := Rect2(Vector2(200.0, 150.0) - Vector2(16.0, 16.0), Vector2(32.0, 32.0))
	for mote: Dictionary in motes.motes_since(before):
		check_equal(mote.source, source, "mote %d in the art's colours" % mote.row)
		var shown: Vector3 = motes.mote_at(mote.ring, mote.row, mote.q, mote.born)
		check(frame.grow(0.5).has_point(Vector2(shown.x, shown.y - shown.z)), "mote %d shown where its pixel was: %s" % [mote.row, shown])
	body.get_parent().free()
	motes.step(0.0)
	var big := _body_of(husk, Vector2(300.0, 150.0), 2.0)
	was = motes.written
	feel.spectacle().break_body(big, big.get_global_transform(), feel.preset.death_mote_kind, feel.preset.death_mote_share, feel.preset.death_mote_most, feel.preset.death_mote_speed, feel.preset.death_mote_up)
	check_equal(motes.written - was, mini(roundi(float(pixels) * feel.preset.death_mote_share * 4.0), feel.preset.death_mote_most), "twice as big: four times the motes, up to the most")
	big.get_parent().free()
	# Through the event, killed mid-squash: from the rest scale.
	motes.step(0.0)
	var squashed := _body_of(husk, Vector2(100.0, 100.0), 1.0)
	bus.damage_dealt.emit(0, squashed.get_parent(), 1, Vector2.ZERO)
	feel.step(0.015625)
	check(squashed.scale != Vector2.ONE, "squashed when it is killed")
	was = motes.written
	bus.enemy_died.emit(0, squashed.get_parent(), Vector2(100.0, 100.0), -1)
	check(feel.spectacle().broken_from() == husk, "the death broke the body's art")
	check((feel.spectacle().broken_at() as Vector2).is_equal_approx(Vector2(100.0, 100.0)), "where it stood")
	check(motes.written - was >= roundi(float(pixels) * feel.preset.death_mote_share), "at its rest scale, not the squashed one's fewer")
	squashed.get_parent().free()


## A body showing `texture` at `at`, drawn `scale` times as big (its `Sprite`).
func _body_of(texture: Texture2D, at: Vector2, scale: float) -> Sprite2D:
	var body := Node2D.new()
	body.global_position = at
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.scale = Vector2.ONE * scale
	body.add_child(sprite)
	root.add_child(body)
	return sprite
