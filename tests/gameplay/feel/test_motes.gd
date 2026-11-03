extends "res://tests/support/suite.gd"
## Motes (gameplay/feel/mote.gd; docs/milestones/spell-spectacle.md, P1a): a ring of rows cut into
## chunked batches. The ring wraps with nothing allocated and overwrites the oldest row; only the
## chunks written in a frame upload, and a chunk with nothing alive is hidden. The kinds' table
## and the flight are the shader's (`mote.gdshader`), and `mote_land` is where that flight comes
## to rest. In Feel, a shot ending on a wall throws stone chips and a few sparks of its own as
## motes; with the "Particles" setting off there are no motes and no nodes, and the old chips
## effect shows instead.

const MotesScript := preload("res://gameplay/feel/mote.gd")
const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const SHADER_PATH: String = "res://gameplay/feel/mote.gdshader"
const PALETTE_PATH: String = "res://core/projectiles/shot_palette.gdshaderinc"

## The shader's table for each of mote.gd's.
const TABLES: Dictionary = {
	"K_GRAVITY": MotesScript.GRAVITY,
	"K_DRAG": MotesScript.DRAG,
	"K_BOUNCE": MotesScript.BOUNCE,
	"K_WOBBLE": MotesScript.WOBBLE,
	"K_WOBBLE_RATE": MotesScript.WOBBLE_RATE,
	"K_GLOW": MotesScript.GLOW,
	"K_SHADE_FROM": MotesScript.SHADE_FROM,
}


func _pool(cap: int) -> MotesScript:
	var motes: MotesScript = own(MotesScript.new(cap, 0)) as MotesScript
	root.add_child(motes)
	return motes


## One chip from `at`, thrown right and up, living `life` seconds.
func _chip(motes: MotesScript, at: Vector2, life: float = 3.0) -> void:
	motes.burst(MotesScript.CHIP, at, Vector2.RIGHT, 1, Vector2(60.0, 60.0), 0.0, Vector2(50.0, 50.0), Vector2(life, life), MotesScript.RAMP_STONE, 4.0)


## `count` sparks, a frame's worth (FRAME_ROWS) at a time, each frame stepped at `now`.
func _fill(motes: MotesScript, count: int, now: float = 0.0) -> void:
	var left: int = count
	while left > 0:
		var n: int = mini(left, MotesScript.FRAME_ROWS)
		motes.burst(MotesScript.SPARK, Vector2.ZERO, Vector2.RIGHT, n, Vector2(10.0, 50.0), 360.0, Vector2(0.0, 20.0), Vector2(0.2, 1.0), 0)
		motes.step(now)
		left -= n


## The numbers of `const float <name>[n] = float[](...)` in `code`.
func _shader_floats(code: String, name: String) -> PackedFloat64Array:
	var found := PackedFloat64Array()
	var regex := RegEx.create_from_string("const float " + name + "\\[\\d+\\] = float\\[\\]\\(([^)]*)\\);")
	var hit: RegExMatch = regex.search(code)
	if hit == null:
		return found
	for part in hit.get_string(1).split(","):
		found.append(float(part.strip_edges()))
	return found


## The number of `const float <name> = <number>;` in `code`, or NAN.
func _shader_const(code: String, name: String) -> float:
	var hit: RegExMatch = RegEx.create_from_string("const float " + name + " = ([-0-9.]+);").search(code)
	return float(hit.get_string(1)) if hit != null else NAN


func _feel() -> Array:
	var bus: EventsScript = own(EventsScript.new()) as EventsScript
	var feel: FeelScript = own(FeelScript.new()) as FeelScript
	var preset := FeelPresetScript.new()
	preset.hit_sound = &""
	feel.events = bus
	feel.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)
	return [bus, feel]


func test_the_ring_wraps_with_nothing_allocated() -> void:
	var motes: MotesScript = _pool(2048)
	# Every chunk's batch is made the first time a mote lands in it.
	_fill(motes, 2048)
	check_equal(motes.chunks_made(), 2, "both chunks made")
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for n in 100:
		motes.burst(MotesScript.EMBER, Vector2(float(n), 0.0), Vector2.ZERO, 100, Vector2(10.0, 50.0), 360.0, Vector2(0.0, 20.0), Vector2(0.2, 1.0), MotesScript.RAMP_FIRE)
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
	motes.burst(MotesScript.CHIP, Vector2.ZERO, Vector2.UP, 300, Vector2(10.0, 50.0), 360.0, Vector2(0.0, 20.0), Vector2(1.0, 2.0), MotesScript.RAMP_STONE)
	motes.step(0.016)
	check_equal(motes.uploads, 1, "a burst of 300 in one chunk uploads it once")
	motes.step(0.032)
	check_equal(motes.uploads, 1, "a frame with no motes uploads nothing")
	_fill(motes, 600, 0.048)
	check_equal(motes.next_row(), 900, "900 written")
	var before: int = motes.uploads
	motes.burst(MotesScript.CHIP, Vector2.ZERO, Vector2.UP, 200, Vector2(10.0, 50.0), 360.0, Vector2(0.0, 20.0), Vector2(1.0, 2.0), MotesScript.RAMP_STONE)
	motes.step(0.064)
	check_equal(motes.uploads - before, 2, "a burst across a chunk's end uploads both chunks")
	check_equal(motes.chunks_made(), 2, "two of the eight chunks made")


func test_a_frame_writes_at_most_its_rows() -> void:
	var motes: MotesScript = _pool(8192)
	motes.burst(MotesScript.CHIP, Vector2.ZERO, Vector2.UP, MotesScript.FRAME_ROWS + 100, Vector2(10.0, 50.0), 360.0, Vector2(0.0, 20.0), Vector2(1.0, 2.0), MotesScript.RAMP_STONE)
	check_equal(motes.next_row(), MotesScript.FRAME_ROWS, "a flood is cut at the frame's rows")
	_chip(motes, Vector2.ZERO)
	check_equal(motes.next_row(), MotesScript.FRAME_ROWS, "and nothing more this frame")
	motes.step(0.016)
	_chip(motes, Vector2.ZERO)
	check_equal(motes.next_row(), MotesScript.FRAME_ROWS + 1, "the next frame writes again")


func test_a_chunk_with_nothing_alive_is_hidden() -> void:
	var motes: MotesScript = _pool(4096)
	_chip(motes, Vector2.ZERO)
	motes.step(1.0)
	check_equal(motes.chunks_shown(), 1, "the chunk written is drawn")
	motes.step(1.0 + MotesScript.LIFE_MAX * 0.5)
	check_equal(motes.chunks_shown(), 1, "while a mote in it can be alive")
	motes.step(1.0 + MotesScript.LIFE_MAX + 0.1)
	check_equal(motes.chunks_shown(), 0, "then hidden: no vertices")
	_chip(motes, Vector2.ZERO)
	motes.step(6.0)
	check_equal(motes.chunks_shown(), 1, "and drawn again with a new mote")


func test_the_shader_has_the_kinds_table() -> void:
	var code: String = FileAccess.get_file_as_string(SHADER_PATH)
	check(not code.is_empty(), "the shader is read")
	for name: String in TABLES:
		var mine: Array[float] = TABLES[name]
		var theirs: PackedFloat64Array = _shader_floats(code, name)
		check_equal(theirs.size(), MotesScript.KIND_NAMES.size(), "%s has a number for every kind" % name)
		for k in mini(theirs.size(), mine.size()):
			check(is_equal_approx(theirs[k], mine[k]), "%s of %s: shader %s, mote.gd %s" % [name, MotesScript.KIND_NAMES[k], theirs[k], mine[k]])
	check_equal(_shader_const(code, "LIFE_MAX"), MotesScript.LIFE_MAX, "the same longest life")
	check_equal(_shader_const(code, "CODE"), MotesScript.CODE, "the same code")
	check(code.contains("const int KINDS = %d;" % MotesScript.KIND_NAMES.size()), "the same number of kinds")
	check(code.contains("const int RAMP_STONE = %d;" % MotesScript.RAMP_STONE), "the same ramps")


func test_the_material_shades_are_the_palettes() -> void:
	var code: String = FileAccess.get_file_as_string(PALETTE_PATH)
	var hit: RegExMatch = RegEx.create_from_string("const vec3 SHADES\\[18\\] = vec3\\[\\]\\(([^;]*)\\);").search(code)
	check(hit != null, "the palette's SHADES are read")
	if hit == null:
		return
	var shades: Array[RegExMatch] = RegEx.create_from_string("vec3\\(([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\\)").search_all(hit.get_string(1))
	check_equal(shades.size(), MotesScript.MATERIAL_SHADES.size(), "as many shades")
	for i in mini(shades.size(), MotesScript.MATERIAL_SHADES.size()):
		var theirs := Color(float(shades[i].get_string(1)), float(shades[i].get_string(2)), float(shades[i].get_string(3)))
		check(theirs.is_equal_approx(MotesScript.MATERIAL_SHADES[i]), "shade %d: palette %s, mote.gd %s" % [i, theirs, MotesScript.MATERIAL_SHADES[i]])


func test_a_core_colour_picks_its_ramp() -> void:
	check_equal(MotesScript.ramp_of_core(Color.WHITE, 2), 2, "a plain shot: its caster's hat ramp")
	check_equal(MotesScript.ramp_of_core(Color.WHITE, ActorSeats.ActorsScript.RAMP_ENEMY), MotesScript.RAMP_ENEMY, "an enemy's: the enemies' ramp")
	check_equal(MotesScript.ramp_of_core(Color.WHITE, -1), MotesScript.RAMP_ENEMY, "no caster: the enemies' ramp")
	check_equal(MotesScript.ramp_of_core(Color("e0592f"), 0), MotesScript.RAMP_FIRE, "a fire core: Fire")
	check_equal(MotesScript.ramp_of_core(Color("c4f6f2"), 0), MotesScript.RAMP_ICE, "an ice core: Ice")
	check_equal(MotesScript.ramp_of_core(Color("b4e82a"), 3), MotesScript.RAMP_ARC, "a lightning core: Arc")


func test_mote_land_is_where_its_flight_comes_to_rest() -> void:
	var motes: MotesScript = _pool(1024)
	motes.step(2.0)
	_chip(motes, Vector2(100.0, 100.0))
	var land: Vector3 = motes.mote_land(0)
	check(land.z > 2.0 and land.z < 2.0 + MotesScript.LIFE_MAX, "it comes to rest in its life, got %s" % land)
	var rest: Vector3 = motes.mote_at(0, land.z)
	check(is_zero_approx(rest.z) and Vector2(rest.x, rest.y).is_equal_approx(Vector2(land.x, land.y)), "on the floor where mote_land says, got %s" % rest)
	var later: Vector3 = motes.mote_at(0, land.z + 0.5)
	check(later.is_equal_approx(rest), "and lies still")
	check(land.x > 100.0, "thrown right along the floor")
	var flying: Vector3 = motes.mote_at(0, 2.05)
	check(flying.z > 0.0, "up in the air at first")
	# One bounce: down on the floor, then up again before it lies.
	var first: float = 2.0 + (50.0 + sqrt(50.0 * 50.0 + 2.0 * MotesScript.GRAVITY[MotesScript.CHIP] * 4.0)) / MotesScript.GRAVITY[MotesScript.CHIP]
	check(first < land.z, "it lands before it comes to rest")
	check(motes.mote_at(0, (first + land.z) * 0.5).z > 0.0, "it bounces up between")


func test_a_mote_that_never_lands_has_no_rest() -> void:
	var motes: MotesScript = _pool(1024)
	motes.burst(MotesScript.EMBER, Vector2.ZERO, Vector2.ZERO, 1, Vector2(5.0, 5.0), 360.0, Vector2(20.0, 20.0), Vector2(2.0, 2.0), MotesScript.RAMP_FIRE)
	check(is_inf(motes.mote_land(0).z), "an ember rises and never lands")
	_chip(motes, Vector2.ZERO, 0.05)
	check(is_inf(motes.mote_land(1).z), "a chip gone before it lands has no rest")


func test_a_wall_hit_throws_chips_and_sparks_as_motes() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	check(feel.motes() != null and feel.motes().cap() == MoteCap.default_cap(), "motes on at the platform's cap")
	bus.projectile_impact.emit(1, null, Vector2(96.0, 100.0), Vector2.RIGHT)
	var motes: MotesScript = feel.motes()
	check_equal(motes.next_row(), FeelScript.WALL_CHIP_MOTES + FeelScript.WALL_SPARK_MOTES, "chips and sparks")
	check_equal(feel.effects_of(FeelScript.KIND_CHIPS), 0, "no chips effect besides")
	for row in FeelScript.WALL_CHIP_MOTES:
		var data: PackedFloat32Array = motes.row_data(row)
		check(data[0] < 0.0, "chip %d flies back off the wall" % row)
		check_equal(roundi(data[8] * MotesScript.CODE), MotesScript.CHIP, "a chip")
		check_equal(roundi(data[9] * MotesScript.CODE), MotesScript.RAMP_STONE, "of stone")
	var spark: PackedFloat32Array = motes.row_data(FeelScript.WALL_CHIP_MOTES)
	check_equal(roundi(spark[8] * MotesScript.CODE), MotesScript.SPARK, "then sparks")
	check_equal(roundi(spark[9] * MotesScript.CODE), 1, "in the caster's hat ramp")
	feel.step(0.016)
	check_equal(motes.uploads, 1, "uploaded on the next frame")


func test_with_particles_off_there_are_no_motes_and_the_chips_effect_shows() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	bus.mote_cap_changed.emit(0)
	check(feel.motes() == null, "no motes")
	check(feel.get_node_or_null("Motes") == null, "and no nodes")
	check_equal(feel.mote_cap, 0, "the setting taken")
	bus.projectile_impact.emit(0, null, Vector2(96.0, 100.0), Vector2.RIGHT)
	check_equal(feel.effects_of(FeelScript.KIND_CHIPS), 1, "the chips effect instead")
	feel.step(0.016)
	bus.mote_cap_changed.emit(MoteCap.STOPS[1])
	check(feel.motes() != null and feel.motes().cap() == MoteCap.STOPS[1], "on again at the new cap")
	check_equal(feel.set_mote_cap(1 << 20), MoteCap.STOPS[-1], "never past the top stop")
