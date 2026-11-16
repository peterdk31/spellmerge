extends "res://tests/support/suite.gd"
## Animated ground cover (docs/STYLE.md, "Smooth"; ground cover GC9, docs/milestones/ground-cover.md):
## a state's tufts play `animation_frames` frames side by side in the sheet from their first, at
## `animation_fps`, once (holding the last) or looping from each tuft's own place, timed from when its
## cell began to show the state (Feel's clock: `shown_at`, the view grid's green). Its numbers ride in
## the rows' colour; `Cover.frame_at` is the shader's sum, mirrored; a frame of a sheet an animation
## runs past is named. Feel's look only.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_cover_animation.gd

const CoverScript := preload("res://gameplay/feel/cover.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
var fixture_grass: CoverKind = preload("res://tests/core/fixtures/cover_content/cover/test_grass/test_grass.tres")

## The field of grass every test lays: cells (12, 12) to (15, 15) of a room 640×384.
const FIELD := Rect2(192, 192, 64, 64)
## The test grass's burning plays 4 frames from 3 or 7 at 10 a second, looping.
const COUNT: int = 4
const FPS: int = 10


## A sheet of `frames` 16×16 frames.
static func _sheet(frames: int) -> Texture2D:
	var image := Image.create_empty(16 * frames, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.5, 0.2))
	return ImageTexture.create_from_image(image)


## The test grass with a sheet of twelve frames, its burning animated (`loops`).
func _grass(loops: bool = true) -> CoverKind:
	var kind := fixture_grass.duplicate(true) as CoverKind
	kind.biomes = [] as Array[StringName]
	kind.sheet = _sheet(12)
	var burning: CoverState = kind.states[kind.state_at(&"burning")]
	burning.frames = PackedInt32Array([3, 7])
	burning.animation_frames = COUNT
	burning.animation_fps = FPS
	burning.animation_loops = loops
	return kind


func _cover(kind: CoverKind) -> CoverScript:
	var layout := own(Node2D.new()) as Node2D
	var field := CoverField.new()
	field.kind = &"test_grass"
	field.density = 1.0
	field.offset_left = FIELD.position.x
	field.offset_top = FIELD.position.y
	field.offset_right = FIELD.end.x
	field.offset_bottom = FIELD.end.y
	layout.add_child(field)
	var room := RoomBase.new()
	room.id = &"meadow"
	var cover: CoverScript = own(CoverScript.new(RoomBase.FLOOR_Z + 1)) as CoverScript
	root.add_child(cover)
	cover.lay(CoverLayout.of(layout, room, [kind] as Array[CoverKind]))
	return cover


func test_a_states_animation_rides_in_its_rows() -> void:
	var cover: CoverScript = _cover(_grass())
	var rows: PackedFloat32Array = cover.rows_of(&"test_grass")
	check(rows.size() > 0, "rows laid")
	check_equal(roundi(rows[9] * 255.0), 1, "a still state plays one frame")
	var cell: int = cover.layout.cell_of(Vector2(200, 200))
	cover.show_state(cell, cover.layout.kinds[0].state_at(&"burning"))
	rows = cover.rows_of(&"test_grass")
	var animated: int = 0
	for at in range(0, rows.size(), CoverScript.STRIDE):
		if roundi(rows[at + 9] * 255.0) == COUNT:
			animated += 1
			check_equal(roundi(rows[at + 10] * 255.0), FPS + 128, "its fps, and 128 for a loop")
	check_equal(animated, cover.layout.kinds[0].tufts_per_cell, "the cell's tufts play its frames")
	cover.show_state(cell, 0)
	rows = cover.rows_of(&"test_grass")
	for at in range(0, rows.size(), CoverScript.STRIDE):
		check_equal(roundi(rows[at + 9] * 255.0), 1, "back at rest, still")


func test_a_change_is_timed_from_feels_clock() -> void:
	var cover: CoverScript = _cover(_grass())
	var cell: int = cover.layout.cell_of(Vector2(200, 200))
	check_equal(cover.shown_at(cell), 0.0, "a cell as laid shows its state since the room was laid (Feel's clock then), so a loop steps evenly")
	cover.step(7.5)
	cover.show_state(cell, cover.layout.kinds[0].state_at(&"burning"))
	check_equal(cover.shown_at(cell), 7.5, "a change heard begins at the clock of the last step")
	cover.step(7.6)
	var texture := (cover.batch_of(&"test_grass").material as ShaderMaterial).get_shader_parameter(&"cell_times") as Texture2D
	check(texture != null and texture.get_size() == Vector2(cover.layout.columns, cover.layout.rows), "the shader reads the grid, a texel a cell")
	check_equal(cover.walked_at(cell), CoverScript.NEVER, "a change walks nothing: the walk is the grid's red, the change its green")
	var body := own(Node2D.new()) as Node2D
	root.add_child(body)
	body.global_position = Vector2(200, 200)
	var table := own(ActorsScript.new()) as ActorsScript
	table.set_node(table.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY), body)
	cover.step(8.0, table, Vector2.ZERO)
	check_equal(cover.walked_at(cell), 8.0, "a walk")
	check_equal(cover.shown_at(cell), 7.5, "keeps when the cell's state began")
	cover.lay(cover.layout)
	check_equal(cover.shown_at(cell), 8.0, "a room laid again starts from when it was laid")


func test_once_it_steps_through_and_holds_its_last_frame() -> void:
	var burning: CoverState = _grass(false).states[1]
	var rolled: int = 0
	var first: int = CoverTufts.frame(rolled, burning.frames)
	check_equal(CoverScript.frame_at(burning, rolled, 0.0), first, "its first frame at once")
	check_equal(CoverScript.frame_at(burning, rolled, 0.15), first + 1, "a frame each 1/fps")
	check_equal(CoverScript.frame_at(burning, rolled, 0.35), first + 3, "to its last")
	check_equal(CoverScript.frame_at(burning, rolled, 50.0), first + 3, "which it holds")
	check_equal(CoverScript.frame_at(burning, rolled, -1.0e6), first, "never before its first")


func test_a_loop_wraps_from_each_tufts_own_place() -> void:
	var burning: CoverState = _grass(true).states[1]
	var starts: Dictionary = {}
	for rolled in 64:
		var first: int = CoverTufts.frame(rolled, burning.frames)
		var at: int = CoverScript.frame_at(burning, rolled, 0.0)
		check(at >= first and at < first + COUNT, "within its own frames")
		check_equal(CoverScript.frame_at(burning, rolled, float(COUNT) / float(FPS)), at, "a whole loop on, the same frame")
		var offset: int = roundi(CoverTufts.phase(rolled) * 255.0)
		check_equal(at, first + offset % COUNT, "from its own place: its sway's start")
		starts[at - first] = true
	check(starts.size() > 1, "so the tufts of a field do not flicker as one")


func test_a_still_state_draws_its_frame() -> void:
	var rest: CoverState = _grass().states[0]
	for rolled in 8:
		check_equal(CoverScript.frame_at(rest, rolled, 3.0), CoverTufts.frame(rolled, rest.frames), "one frame, whatever the time")


func test_an_animation_past_the_sheet_is_named() -> void:
	var kind: CoverKind = _grass()
	kind.sheet = _sheet(9)
	check("\n".join(kind.problems()).contains("draws frame 10"), "frame 7's four frames run past a sheet of 9: %s" % "\n".join(kind.problems()))
	kind.sheet = _sheet(11)
	check(not "\n".join(kind.problems()).contains("which its sheet"), "a sheet that holds them all is sound")
	var burning: CoverState = kind.states[kind.state_at(&"burning")]
	burning.animation_fps = 0
	check("\n".join(kind.problems()).contains("0 frames a second"), "a speed the shader cannot play is named")
	burning.animation_fps = 200
	check("\n".join(kind.problems()).contains("200 frames a second"), "too fast too")
	burning.animation_fps = FPS
	burning.animation_frames = 17
	check("\n".join(kind.problems()).contains("plays 17 frames a tuft"), "and too long a strip")
