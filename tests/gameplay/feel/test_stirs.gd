extends "res://tests/support/suite.gd"
## A world that notices (docs/milestones/atmosphere.md, E): the world's stirs (gameplay/feel/stirs.gd)
## read from the shots' births and Feel's blasts, eased on Feel's clock and bounded; the room's lights
## ducking and leaning away from a shot passing close and out from a blast, easing back and handing
## the rows as placed back once at rest (spot_stirs.gd, SpellLight.show_spots); the ground cover and
## the stirred motes handed the same stirs, their shaders reading them by the same numbers
## (stir.gdshaderinc, by text: headless runs compile no shader); no object made a frame; and nothing
## of the lights with spell light off. How it looks is checked by eye
## (tests/screenshots/shot_atmosphere_reactions.gd).

const StirsScript := preload("res://gameplay/feel/stirs.gd")
const SpotStirsScript := preload("res://gameplay/feel/spot_stirs.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const CoverScript := preload("res://gameplay/feel/cover.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const FIXTURE_GRASS: CoverKind = preload("res://tests/core/fixtures/cover_content/cover/test_grass/test_grass.tres")

const FRAME: float = 1.0 / 60.0
const VIEW := Rect2(0.0, 0.0, 640.0, 360.0)
const STRIDE: int = ProjectilesScript.SPARK_BIRTH_STRIDE

var _births: PackedFloat32Array = PackedFloat32Array()
var _count: int = 0
var _clock: float = 0.0


func before_each() -> void:
	_births.resize(ProjectilesScript.SPARK_BIRTHS_MAX * STRIDE)
	_births.fill(0.0)
	_count = 0
	_clock = 0.0


## A birth at `at` of a shot flying along `way`.
func _birth(at: Vector2, way: Vector2) -> void:
	var i: int = _count * STRIDE
	var back: Vector2 = -way.normalized()
	_births[i + ProjectilesScript.SPARK_X] = at.x
	_births[i + ProjectilesScript.SPARK_Y] = at.y
	_births[i + ProjectilesScript.SPARK_BACK_X] = back.x
	_births[i + ProjectilesScript.SPARK_BACK_Y] = back.y
	_count += 1


## The births a shot flying along `way` lays this frame round `at` (one every 2 px over 6 px).
func _shot(at: Vector2, way: Vector2) -> void:
	for k in 3:
		_birth(at - way.normalized() * 2.0 * float(k), way)


func _step(stirs: StirsScript, frames: int = 1) -> void:
	for frame in frames:
		_clock += FRAME
		stirs.step(_clock, _births, _count, VIEW)
		_count = 0


# --- The shots' wake ------------------------------------------------------------------------------

func test_a_shot_drags_its_wake_along_its_way_easing_in_and_out() -> void:
	var stirs := StirsScript.new()
	var at := Vector2(200.0, 150.0)
	var shown: Array[float] = []
	for frame in 10:
		_shot(at, Vector2.RIGHT)
		_step(stirs)
		shown.append(stirs.shown_at_cell(at).x)
	check(shown[0] > 0.0 and shown[0] <= StirsScript.SHOWN_RATE * FRAME + 0.0001, "the first frame shows at most a frame's share (%.3f)" % shown[0])
	check(shown[2] < 1.0, "not full before the fourth frame")
	check(shown[9] > 0.9, "a held stream of shots drags it fully (%.3f)" % shown[9])
	check(stirs.shown_at_cell(at).y == 0.0, "along the shots' way")
	check(stirs.shown_at_cell(at).length() <= 1.0 + 0.0001, "never more than 1")
	var last: float = shown[9]
	var frames: int = 0
	while stirs.live_cells() > 0 and frames < 600:
		_step(stirs)
		var now: float = stirs.shown_at_cell(at).x
		check(now <= last + 0.0001 and last - now <= StirsScript.SHOWN_RATE * FRAME + 0.0001, "it eases back, never jumping (frame %d)" % frames)
		last = now
		frames += 1
	check(frames >= 6 and frames < 600, "and is still again after a while (%d frames)" % frames)
	check_equal(stirs.shown_at_cell(at), Vector2.ZERO, "still: nothing")


func test_the_wake_is_read_bilinear_and_nothing_outside_the_window() -> void:
	var stirs := StirsScript.new()
	var at := Vector2(200.0, 150.0)
	for frame in 20:
		_shot(at, Vector2.DOWN)
		_step(stirs)
	var cell_middle: Vector2 = (Vector2(floorf(at.x / StirsScript.CELL), floorf(at.y / StirsScript.CELL)) + Vector2(0.5, 0.5)) * StirsScript.CELL
	check(stirs.wake_at(cell_middle).distance_to(stirs.shown_at_cell(at)) < 0.0001, "a cell's middle reads the cell")
	var beside: Vector2 = stirs.wake_at(cell_middle + Vector2(StirsScript.CELL * 0.5, 0.0))
	check(beside.y > 0.0 and beside.y < stirs.shown_at_cell(at).y, "halfway to the next cell, half of it")
	check_equal(stirs.wake_at(Vector2(-5000.0, 0.0)), Vector2.ZERO, "outside the window: nothing")


func test_the_window_follows_the_view_keeping_the_wake_where_it_is() -> void:
	var stirs := StirsScript.new()
	var at := Vector2(300.0, 180.0)
	for frame in 20:
		_shot(at, Vector2.RIGHT)
		_step(stirs)
	var before: Vector2 = stirs.wake_at(at)
	var origin: Vector2 = stirs.origin
	_clock += FRAME
	stirs.step(_clock, _births, 0, Rect2(VIEW.position + Vector2(40.0, 24.0), VIEW.size))
	check(stirs.origin != origin, "the window moved with the view")
	var after: Vector2 = stirs.wake_at(at)
	check(after.x > 0.0 and absf(after.x - before.x) < 0.1, "the wake stayed where it was in the world (%.3f, %.3f)" % [before.x, after.x])
	check_equal(stirs.origin, Vector2(StirsScript.corner_for(Rect2(VIEW.position + Vector2(40.0, 24.0), VIEW.size))) * StirsScript.CELL, "by whole cells")


func test_a_flood_of_births_is_read_a_few_at_a_time() -> void:
	var stirs := StirsScript.new()
	for k in ProjectilesScript.SPARK_BIRTHS_MAX:
		_birth(Vector2(20.0 + float(k % 600), 40.0 + float(k / 600) * 30.0), Vector2.LEFT)
	_step(stirs)
	check(stirs.read > 0 and stirs.read <= StirsScript.BIRTHS_READ, "at most BIRTHS_READ read (%d)" % stirs.read)
	_birth(Vector2(100.0, 100.0), Vector2.ZERO)
	_step(stirs)
	check_equal(stirs.read, 0, "a still shot's birth (no way) drags nothing")


func test_the_shots_near_a_point_say_which_side_they_pass() -> void:
	var stirs := StirsScript.new()
	_shot(Vector2(100.0, 100.0), Vector2.RIGHT)
	_step_keep(stirs)
	var above: Vector3 = stirs.shots_near(Vector2(98.0, 90.0), 30.0)
	check(above.y < 0.0 and absf(above.x) < absf(above.y), "a point above the shot is pushed up, away from it")
	check(above.z > 0.0 and above.z < 1.0, "as much as it is near")
	check_equal(stirs.shots_near(Vector2(98.0, 160.0), 30.0), Vector3.ZERO, "nothing past the reach")


## One frame keeping this frame's births in view (for `shots_near`).
func _step_keep(stirs: StirsScript) -> void:
	_clock += FRAME
	stirs.step(_clock, _births, _count, VIEW)


# --- The blasts -----------------------------------------------------------------------------------

func test_a_blast_pushes_out_as_its_wave_passes_and_sways_back_to_rest() -> void:
	var stirs := StirsScript.new()
	var at := Vector2(200.0, 200.0)
	stirs.blast(at, 24.0, 0.0)
	check_equal(stirs.blast_count(), 1, "one blast")
	var near := at + Vector2(10.0, 0.0)
	var far := at + Vector2(60.0, 0.0)
	var reach: float = 24.0 * StirsScript.BLAST_REACH + StirsScript.BLAST_PAD
	var last := Vector2.ZERO
	var most: float = 0.0
	var first_near: float = -1.0
	var first_far: float = -1.0
	var swung: bool = false
	var t: float = 0.0
	while t < StirsScript.blast_seconds(reach) + 0.1:
		var push: Vector2 = stirs.blast_push(near, t)
		check(absf(push.y) < 0.0001, "out from the middle, never aside")
		check(push.distance_to(last) <= 1.5 * FRAME / StirsScript.RISE + 0.01, "never jumping a frame (%.3f at %.3f s)" % [push.distance_to(last), t])
		most = maxf(most, push.x)
		swung = swung or push.x < -0.01
		if first_near < 0.0 and push.x > 0.0:
			first_near = t
		if first_far < 0.0 and stirs.blast_push(far, t).x > 0.0:
			first_far = t
		last = push
		t += FRAME
	check(most > 0.5 and most <= 1.0, "pushed out strongly near its middle (%.2f)" % most)
	check(swung, "swaying back past rest")
	check(last.length() < 0.0001, "and still at the end")
	check(first_far > first_near, "the wave reaches the far point later")
	check_equal(stirs.blast_push(at + Vector2(reach + 1.0, 0.0), 0.2), Vector2.ZERO, "nothing past its reach")
	check(StirsScript.blast_envelope(0.0) == 0.0 and absf(StirsScript.blast_envelope(StirsScript.RISE) - 1.0) < 0.0001 and absf(StirsScript.blast_envelope(StirsScript.RISE + StirsScript.FALL)) < 0.0001, "out to 1 over RISE, back to 0 over FALL")


func test_an_explosions_two_parts_are_one_blast_and_old_ones_go() -> void:
	var stirs := StirsScript.new()
	stirs.blast(Vector2(100.0, 100.0), 16.0, 1.0)
	stirs.blast(Vector2(102.0, 100.0), 30.0, 1.0)
	check_equal(stirs.blast_count(), 1, "the shell and the fireball are one blast")
	for k in StirsScript.BLASTS + 4:
		stirs.blast(Vector2(20.0 * float(k), 300.0), 16.0, 1.1)
	check_equal(stirs.blast_count(), StirsScript.BLASTS, "never more than BLASTS")
	_clock = 20.0
	stirs.step(_clock, _births, 0, VIEW)
	check_equal(stirs.blast_count(), 0, "every one over is let go")


func test_with_every_blast_pushing_a_new_one_cuts_none_short() -> void:
	var stirs := StirsScript.new()
	# Sixteen blasts far enough apart that each point is pushed by one.
	var places := PackedVector2Array()
	for k in StirsScript.BLASTS:
		places.append(Vector2(200.0 * float(k % 4), 200.0 * float(k / 4)))
		stirs.blast(places[k], 24.0, 0.0)
	var points := PackedVector2Array()
	for at in places:
		points.append(at + Vector2(20.0, 0.0))
	var last := PackedVector2Array()
	last.resize(points.size())
	var t: float = 0.0
	for frame in 40:
		if frame == 3:
			stirs.blast(places[0] + Vector2(30.0, 0.0), 24.0, t)
		for n in points.size():
			var push: Vector2 = stirs.blast_push(points[n], t)
			check(push.distance_to(last[n]) <= 1.5 * FRAME / StirsScript.RISE + 0.01, "no point's push jumps (point %d, frame %d)" % [n, frame])
			last[n] = push
		t += FRAME
	check_equal(stirs.blast_count(), StirsScript.BLASTS, "the seventeenth was let go")


func test_blasts_side_by_side_push_no_further_than_one() -> void:
	var stirs := StirsScript.new()
	for k in 5:
		stirs.blast(Vector2(100.0 + 20.0 * float(k), 100.0), 30.0, 0.0)
	var most: float = 0.0
	var t: float = 0.0
	while t < 1.5:
		for x in range(40, 260, 10):
			most = maxf(most, stirs.blast_push(Vector2(float(x), 130.0), t).length())
		t += FRAME
	check(most > 0.5 and most <= 1.0 + 0.0001, "the sum is at most 1 long (%.3f)" % most)


func test_the_widest_view_is_covered_and_the_texture_is_half_floats() -> void:
	var stirs := StirsScript.new()
	var wide := Rect2(0.0, 0.0, 1280.0, 720.0)
	for frame in 10:
		_shot(Vector2(1270.0, 712.0), Vector2.LEFT)
		_shot(Vector2(8.0, 6.0), Vector2.RIGHT)
		_clock += FRAME
		stirs.step(_clock, _births, _count, wide)
		_count = 0
	check(stirs.wake_at(Vector2(1270.0, 712.0)).x < 0.0, "a shot in the zoomed-out view's corner drags its wake")
	check(stirs.wake_at(Vector2(8.0, 6.0)).x > 0.0, "and in the opposite corner")
	var window := Rect2(stirs.origin, Vector2(StirsScript.FIELD_W, StirsScript.FIELD_H) * StirsScript.CELL)
	check(window.encloses(wide.grow(64.0)), "the window holds the widest view and a margin")
	check_equal(stirs.texture.get_format(), Image.FORMAT_RGH, "half floats: filtered on WebGL 2 and GLES 3")


# --- The room's lights ----------------------------------------------------------------------------

## A spell light with one candle at `at` in the tree, its spots drawn.
func _light(at: Vector2) -> SpellLightScript:
	var spot := Marker2D.new()
	spot.position = at
	spot.add_to_group(LightSpot.GROUP)
	spot.set_meta(LightSpot.REACH, 48.0)
	spot.set_meta(LightSpot.STRENGTH, 0.8)
	spot.set_meta(LightSpot.TINT, Color(1.0, 0.6, 0.2))
	root.add_child(own(spot))
	var light := SpellLightScript.new(null, 0)
	root.add_child(own(light))
	light.draw_spots()
	return light


func _drawn_row(light: SpellLightScript, float_at: int) -> float:
	return light.spots.multimesh.buffer[float_at]


func test_a_candle_ducks_and_leans_away_from_a_shot_passing_and_eases_back() -> void:
	var at := Vector2(200.0, 150.0)
	var light: SpellLightScript = _light(at)
	var stirs := StirsScript.new()
	var spots := SpotStirsScript.new()
	var placed: PackedFloat32Array = light.spot_rows().duplicate()
	var last := Vector2.ZERO
	# A shot passing 8 px below it, left to right.
	for frame in 8:
		_shot(Vector2(170.0 + 8.0 * float(frame), at.y + 8.0), Vector2.RIGHT)
		_clock += FRAME
		stirs.step(_clock, _births, _count, VIEW)
		_count = 0
		spots.step(light, stirs, _clock)
		check(spots.leans[0].distance_to(last) <= SpotStirsScript.LEAN_IN * FRAME + 0.0001, "the lean never jumps (frame %d)" % frame)
		last = spots.leans[0]
	check(spots.leans[0].y < -1.0, "it leans up, away from the shot below (%s)" % spots.leans[0])
	check(spots.leans[0].length() <= SpotStirsScript.LEAN_MOST + 0.0001, "no more than LEAN_MOST")
	check(spots.ducks[0] > 0.05 and spots.ducks[0] <= SpotStirsScript.DUCK_MOST, "it ducks (%.2f)" % spots.ducks[0])
	var x: int = SpellLightScript.ROW_X
	var y: int = SpellLightScript.ROW_Y
	var g: int = SpellLightScript.SPOT_ROW_GROUND
	var s: int = SpellLightScript.SPOT_ROW_STRENGTH
	check(absf(_drawn_row(light, y) - (placed[y] + spots.leans[0].y)) < 0.001, "its drawn middle leans")
	check(absf(_drawn_row(light, y) + _drawn_row(light, g + 1) - (placed[y] + placed[g + 1])) < 0.001 and absf(_drawn_row(light, x) + _drawn_row(light, g) - (placed[x] + placed[g])) < 0.001, "where it stands on the floor stays (what blocks it)")
	check(_drawn_row(light, s) < placed[s], "and it is dimmer")
	check_equal(light.spot_rows(), placed, "the rows as placed are kept (the shadows fall from them)")
	var frames: int = 0
	while spots.stirred and frames < 600:
		_clock += FRAME
		stirs.step(_clock, _births, 0, VIEW)
		spots.step(light, stirs, _clock)
		check(spots.leans[0].distance_to(last) <= SpotStirsScript.LEAN_OUT * FRAME + 0.0001, "easing back slower, never jumping (frame %d)" % frames)
		last = spots.leans[0]
		frames += 1
	check(frames >= 10 and frames < 600, "back at rest after a while (%d frames)" % frames)
	check_equal(light.spots.multimesh.buffer, placed, "at rest: the rows as placed are drawn again")


func test_a_candle_leans_out_from_a_blast_and_nothing_far_away_stirs_it() -> void:
	var at := Vector2(200.0, 150.0)
	var light: SpellLightScript = _light(at)
	var stirs := StirsScript.new()
	var spots := SpotStirsScript.new()
	_shot(Vector2(400.0, 300.0), Vector2.RIGHT)
	_clock += FRAME
	stirs.step(_clock, _births, _count, VIEW)
	spots.step(light, stirs, _clock)
	check(not spots.stirred, "a shot far off stirs nothing")
	stirs.blast(at + Vector2(-20.0, 0.0), 20.0, _clock)
	var most: float = 0.0
	for frame in 20:
		_clock += FRAME
		stirs.step(_clock, _births, 0, VIEW)
		spots.step(light, stirs, _clock)
		most = maxf(most, spots.leans[0].x)
	check(most > 1.0, "it leans out from the blast (%.2f px)" % most)


func test_spots_changed_start_at_rest() -> void:
	var light: SpellLightScript = _light(Vector2(100.0, 100.0))
	var stirs := StirsScript.new()
	var spots := SpotStirsScript.new()
	stirs.blast(Vector2(90.0, 100.0), 20.0, 0.0)
	for frame in 5:
		_clock += FRAME
		stirs.step(_clock, _births, 0, VIEW)
		spots.step(light, stirs, _clock)
	check(spots.stirred, "stirred")
	var spot := Marker2D.new()
	spot.position = Vector2(300.0, 100.0)
	spot.add_to_group(LightSpot.GROUP)
	root.add_child(own(spot))
	light.draw_spots()
	spots.step(light, stirs, _clock)
	check_equal(spots.leans.size(), 2, "the new spots are taken")


# --- The cover and the motes ----------------------------------------------------------------------

func test_the_shaders_read_the_stirs_by_the_same_numbers() -> void:
	var include: String = FileAccess.get_file_as_string("res://gameplay/feel/stir.gdshaderinc")
	check(include.contains("const float STIR_CELL = %.1f;" % StirsScript.CELL), "the cell")
	check(include.contains("const vec2 STIR_CELLS = vec2(%.1f, %.1f);" % [StirsScript.FIELD_W, StirsScript.FIELD_H]), "the window")
	check(include.contains("const int STIR_BLASTS = %d;" % StirsScript.BLASTS) and include.contains("stir_blasts[%d]" % StirsScript.BLASTS), "the blasts")
	check(include.contains("const float STIR_WAVE_SPEED = %.1f;" % StirsScript.WAVE_SPEED), "the wave's speed")
	check(include.contains("const float STIR_RISE = %s;" % str(StirsScript.RISE)) and include.contains("const float STIR_FALL = %s;" % str(StirsScript.FALL)), "the push's rise and fall")
	check(include.contains("uniform sampler2D stir_field : hint_default_black, filter_linear, repeat_disable;"), "the wake reads black with none handed over")
	# The functions' bodies, line for line with the GDScript.
	var script: String = FileAccess.get_file_as_string("res://gameplay/feel/stirs.gd")
	for pair: Array in [
		["return r * r * (3.0 - 2.0 * r);", "return r * r * (3.0 - 2.0 * r)"],
		["float t = min((age - STIR_RISE) / STIR_FALL, 1.0);", "var t: float = minf((age - RISE) / FALL, 1.0)"],
		["return (1.0 - t) * (1.0 - t) * cos(t * 3.14159265 * 1.5);", "return (1.0 - t) * (1.0 - t) * cos(t * PI * 1.5)"],
		["if (far >= b.z || far < 0.5) {", "if far >= held.z or far < 0.5:"],
		["float age = now - b.w - far / STIR_WAVE_SPEED;", "var age: float = now - held.w - far / WAVE_SPEED"],
		["push += away / far * (strength * (1.0 - far / b.z) * stir_envelope(age));", "push += away / far * (strength * (1.0 - far / held.z) * blast_envelope(age))"],
		["return most > 1.0 ? push / most : push;", "return push / most if most > 1.0 else push"],
		["vec2 at = (p - stir_origin) / STIR_CELL;", "var at: Vector2 = (point - origin) / CELL - Vector2(0.5, 0.5)"],
		["if (at.x < 0.0 || at.y < 0.0 || at.x > STIR_CELLS.x || at.y > STIR_CELLS.y) {", "if at.x < -0.5 or at.y < -0.5 or at.x > float(FIELD_W) - 0.5 or at.y > float(FIELD_H) - 0.5:"],
		["return textureLod(stir_field, at / STIR_CELLS, 0.0).rg;", "return top.lerp(bottom, fy)"],
	]:
		check(include.contains(pair[0]) and script.contains(pair[1]), "the shader and Stirs agree: %s" % pair[0])
	var cover: String = FileAccess.get_file_as_string("res://gameplay/feel/cover.gdshader")
	check(cover.contains("#include \"res://gameplay/feel/stir.gdshaderinc\""), "the cover reads the stirs")
	check(cover.contains("const float STIR_SHOT_PIXELS = %s;" % str(CoverScript.STIR_SHOT_PIXELS)) and cover.contains("const float STIR_BLAST_PIXELS = %s;" % str(CoverScript.STIR_BLAST_PIXELS)), "by Cover's numbers")
	check(cover.contains("lean += (stir_wake(foot) * STIR_SHOT_PIXELS + stir_blasts_at(foot, view_time) * STIR_BLAST_PIXELS) * bend;"), "as far as its state bends")
	var mote: String = FileAccess.get_file_as_string("res://gameplay/feel/mote.gdshader")
	check(mote.contains("#include \"res://gameplay/feel/stir.gdshaderinc\""), "the motes read the stirs")
	check(mote.contains("const float STIR_SHOT_PIXELS = %s;" % str(MotesScript.STIR_SHOT_PIXELS)) and mote.contains("const float STIR_BLAST_PIXELS = %s;" % str(MotesScript.STIR_BLAST_PIXELS)), "by the motes' numbers")
	check(mote.contains("if (light_of.y > 0.0) {"), "only a stirred kind's")


func test_the_cover_is_handed_the_stirs_when_they_change() -> void:
	var cover := CoverScript.new(0)
	root.add_child(own(cover))
	var kind := (FIXTURE_GRASS.duplicate(true) as CoverKind)
	kind.biomes = [] as Array[StringName]
	var image := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	kind.sheet = ImageTexture.create_from_image(image)
	var layout := own(Node2D.new()) as Node2D
	var field := CoverField.new()
	field.kind = kind.id
	field.density = 1.0
	field.offset_left = 64.0
	field.offset_top = 64.0
	field.offset_right = 128.0
	field.offset_bottom = 128.0
	layout.add_child(field)
	var room := RoomBase.new()
	room.id = &"meadow"
	cover.lay(CoverLayout.of(layout, room, [kind] as Array[CoverKind]))
	var stirs := StirsScript.new()
	stirs.blast(Vector2(10.0, 10.0), 20.0, 0.0)
	cover.step(0.0, null, Vector2.INF, null, Rect2(), stirs.version, stirs.hand_to)
	var batch: MultiMeshInstance2D = cover.batch_of(kind.id)
	check(batch != null, "a batch")
	if batch == null:
		return
	var material := batch.material as ShaderMaterial
	check(material.get_shader_parameter(&"stir_field") == stirs.texture, "the wake's texture")
	check_equal((material.get_shader_parameter(&"stir_blasts") as PackedVector4Array)[0], Vector4(10.0, 10.0, 20.0 * StirsScript.BLAST_REACH + StirsScript.BLAST_PAD, 0.0), "the blast")
	stirs.blast(Vector2(50.0, 10.0), 20.0, 0.5)
	cover.step(0.5, null, Vector2.INF, null, Rect2(), stirs.version, stirs.hand_to)
	check_equal((material.get_shader_parameter(&"stir_blasts") as PackedVector4Array)[1].x, 50.0, "a new blast is handed over")


func test_the_air_and_the_shafts_dust_is_stirred_and_the_table_says_so() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	check_equal(MoteKind.new().stirred, 0.0, "a kind is not stirred by default")
	for id: StringName in [&"air_dust", &"air_glimmer", &"falling_dust"]:
		var kind := registry.get_resource(&"motes", id) as MoteKind
		check(kind != null and kind.stirred > 0.0, "%s is stirred" % id)
	var dust := MoteKind.new()
	dust.id = &"stirred_here"
	dust.stirred = 0.5
	dust.life = Vector2(1.0, 1.0)
	var motes: MotesScript = own(MotesScript.new(1024, 0, [dust] as Array[MoteKind])) as MotesScript
	root.add_child(motes)
	var table: Texture2D = motes.draw_material().get_shader_parameter(&"kind_table")
	var image: Image = table.get_image()
	check(absf(image.get_pixel(3, motes.kind_index(&"stirred_here")).g - 0.5) < 0.01, "its share is in the kind table's light texel")


# --- In Feel --------------------------------------------------------------------------------------

func _feel() -> Array:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var bus: EventsScript = own(EventsScript.new()) as EventsScript
	var table: Node = own(ActorSeats.table()) as Node
	var manager: ProjectilesScript = own(ProjectilesScript.new()) as ProjectilesScript
	manager.events = bus
	manager.actors = table
	root.add_child(manager)
	var feel: FeelScript = own(FeelScript.new()) as FeelScript
	var preset := FeelPresetScript.new()
	preset.hit_sound = &""
	feel.events = bus
	feel.registry = registry
	feel.actors = table
	feel.projectiles = manager
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)
	return [bus, feel]


func test_feel_pushes_from_an_explosion_and_hands_the_motes_the_stirs() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	bus.spell_light_changed.emit(true)
	var spectacle: Node = feel.spectacle()
	var stirs: StirsScript = spectacle.get("stirs")
	feel.show_flash(&"fireball", Vector2(100.0, 100.0), Vector2.RIGHT, Color.WHITE, 0, 0, 12, 0.4)
	check_equal(stirs.blast_count(), 1, "an explosion's part pushes")
	feel._process(FRAME)
	var pool: MotesScript = spectacle.get("pool")
	check(pool.draw_material().get_shader_parameter(&"stir_field") == stirs.texture, "the motes are handed the stirs")
	check_equal(pool.draw_material().get_shader_parameter(&"stir_strength")[0], stirs.get("_blast_strength")[0], "and the blast")


func test_with_spell_light_off_the_room_s_lights_take_no_notice() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var spot := Marker2D.new()
	spot.position = Vector2(100.0, 100.0)
	spot.add_to_group(LightSpot.GROUP)
	root.add_child(own(spot))
	bus.spell_light_changed.emit(false)
	var spectacle: Node = feel.spectacle()
	feel.show_flash(&"fireball", Vector2(90.0, 100.0), Vector2.RIGHT, Color.WHITE, 0, 0, 12, 0.4)
	for frame in 10:
		feel._process(FRAME)
	var spots: SpotStirsScript = spectacle.get("spot_stirs")
	check(not spots.stirred and spots.leans.is_empty(), "no light, no spot stirred")
	bus.spell_light_changed.emit(true)
	# The spots are written just before a draw (none headless): written here.
	(spectacle.get("light") as SpellLightScript).draw_spots()
	feel.show_flash(&"fireball", Vector2(90.0, 100.0), Vector2.RIGHT, Color.WHITE, 0, 0, 12, 0.4)
	for frame in 4:
		feel._process(FRAME)
	spots = spectacle.get("spot_stirs")
	check(spots.stirred, "spell light on: the candle leans from the blast")


func test_a_frame_makes_no_object() -> void:
	var light: SpellLightScript = _light(Vector2(200.0, 150.0))
	var stirs := StirsScript.new()
	var spots := SpotStirsScript.new()
	var frames: Callable = func(count: int) -> void:
		for frame in count:
			_shot(Vector2(150.0 + 4.0 * float(frame % 40), 158.0), Vector2.RIGHT)
			if frame % 25 == 0:
				stirs.blast(Vector2(220.0, 150.0), 20.0, _clock)
			_clock += FRAME
			var view := Rect2(VIEW.position + Vector2(float(frame % 50), 0.0), VIEW.size)
			stirs.step(_clock, _births, _count, view)
			_count = 0
			spots.step(light, stirs, _clock)
	frames.call(30)
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	frames.call(100)
	check(spots.stirred or stirs.live_cells() > 0, "it was stirred")
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "100 frames of stirs make no object")
