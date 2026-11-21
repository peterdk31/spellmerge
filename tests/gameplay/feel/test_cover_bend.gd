extends "res://tests/support/suite.gd"
## Bodies bend ground cover and trample it (ground cover GC4, docs/milestones/ground-cover.md, rule 6
## and decision 4): Feel's look only. Each frame the cover takes the actor table's bodies, keeps the
## `BODIES` nearest the camera's middle and hands them to every batch's shader; the cells under their
## `FOOTPRINT` (theirs and the row in front), covered ones only, are walked in Feel's view grid (the
## shader's `cell_times` texture, its red), flat while walked and their kind's hold after, then
## springing back; a state's trampled frames ride in its rows' colour; and a frame of it allocates
## nothing (in the style of the motes' tests).
const CoverScript := preload("res://gameplay/feel/cover.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
var fixture_grass: CoverKind = preload("res://tests/core/fixtures/cover_content/cover/test_grass/test_grass.tres")

## The field of grass every test lays: cells (12, 12) to (15, 15) of a room 640×384.
const FIELD := Rect2(192, 192, 64, 64)


## The test grass's trample, its own numbers (not `CoverKind`'s defaults), so the cover is seen to
## read its kind's.
const HOLD: float = 2.0
const SPRING: float = 3.0


## A sheet of `frames` 16×16 frames.
static func _sheet(frames: int) -> Texture2D:
	var image := Image.create_empty(16 * frames, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.5, 0.2))
	return ImageTexture.create_from_image(image)


## The test grass with a sheet of seven frames, its resting state drawing frame 6 trampled.
func _grass() -> CoverKind:
	var kind := fixture_grass.duplicate(true) as CoverKind
	kind.biomes = [] as Array[StringName]
	kind.sheet = _sheet(7)
	kind.states[0].trampled_frames = PackedInt32Array([6])
	kind.trample_hold = HOLD
	kind.trample_spring = SPRING
	return kind


## A room 640×384, walls round the edge a tile thick, and a field of grass over `FIELD`.
func _layout() -> Node2D:
	var layout := own(Node2D.new()) as Node2D
	var walls := StaticBody2D.new()
	walls.collision_layer = RoomBase.WALL_LAYER
	layout.add_child(walls)
	for box: Rect2 in [Rect2(0, 0, 640, 32), Rect2(0, 352, 640, 32), Rect2(0, 0, 32, 384), Rect2(608, 0, 32, 384)]:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = box.size
		shape.shape = rect
		shape.position = box.get_center()
		walls.add_child(shape)
	var field := CoverField.new()
	field.kind = &"test_grass"
	field.density = 1.0
	field.offset_left = FIELD.position.x
	field.offset_top = FIELD.position.y
	field.offset_right = FIELD.end.x
	field.offset_bottom = FIELD.end.y
	layout.add_child(field)
	return layout


func _room() -> RoomBase:
	var room := RoomBase.new()
	room.id = &"meadow"
	return room


func _cover() -> CoverScript:
	var cover: CoverScript = own(CoverScript.new(RoomBase.FLOOR_Z + 1)) as CoverScript
	root.add_child(cover)
	cover.lay(CoverLayout.of(_layout(), _room(), [_grass()] as Array[CoverKind]))
	return cover


## An actor table of a body at each of `places`, in id order.
func _table(places: PackedVector2Array) -> ActorsScript:
	var table := own(ActorsScript.new()) as ActorsScript
	for at in places:
		var body := own(Node2D.new()) as Node2D
		root.add_child(body)
		body.global_position = at
		var id: int = table.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
		table.set_node(id, body)
	return table


func test_the_bodies_nearest_the_camera_are_handed_to_every_batch() -> void:
	var cover: CoverScript = _cover()
	check(cover.layout.count(&"test_grass") > 0, "the field is laid")
	var places := PackedVector2Array()
	# 40 bodies along a line from the camera's middle at (0, 0): the 32 nearest are the first 32,
	# given in an order that is not theirs.
	for n in 40:
		places.append(Vector2(float((n * 7) % 40) * 10.0, 0.0))
	var table: ActorsScript = _table(places)
	cover.step(1.0, table, Vector2.ZERO)
	check_equal(cover.body_count(), CoverScript.BODIES, "at most BODIES bodies")
	var given: PackedVector2Array = cover.bodies()
	for at in cover.body_count():
		check(given[at].x < 320.0, "only the nearest bodies are handed over, got %s" % given[at])
	var material := cover.batch_of(&"test_grass").material as ShaderMaterial
	check_equal(material.get_shader_parameter(&"body_count"), CoverScript.BODIES, "the shader is told how many")
	var held: PackedVector2Array = material.get_shader_parameter(&"bodies")
	check_equal(held, given, "and where they are")
	check_equal(material.get_shader_parameter(&"bend_reach"), CoverScript.BEND_REACH, "the bend's numbers are Feel's")
	check_equal(material.get_shader_parameter(&"trample_hold"), HOLD, "the trample's are its kind's")
	check_equal(material.get_shader_parameter(&"trample_spring"), SPRING, "both")


## The performance pass (2026-11-21): a view switched off (unseen_rooms.gd) hands its batches
## nothing a frame, but keeps its cells walked, and the frame it is shown again it is handed that
## frame's clock and bodies before it is drawn, as if it had been handed them every frame.
func test_a_view_switched_off_hands_nothing_until_it_is_shown() -> void:
	var cover: CoverScript = _cover()
	var material := cover.batch_of(&"test_grass").material as ShaderMaterial
	var table: ActorsScript = _table(PackedVector2Array([Vector2(10, 10)]))
	cover.step(1.0, table, Vector2.ZERO)
	check_equal(material.get_shader_parameter(&"view_time"), 1.0, "shown: handed the clock")
	cover.visible = false
	var body := table.node_of(0) as Node2D
	body.global_position = Vector2(200, 200)
	cover.step(2.0, table, Vector2.ZERO)
	check_equal(material.get_shader_parameter(&"view_time"), 1.0, "off: not handed the clock")
	check_equal((material.get_shader_parameter(&"bodies") as PackedVector2Array)[0], Vector2(10, 10), "nor the bodies")
	# The other rooms' views and the mist read the first room's bodies, which may be switched off
	# (the review's: they were frozen at the last frame it was shown).
	check_equal(cover.bodies()[0], Vector2(200, 200), "but the bodies it hands the other rooms are this frame's")
	var cell: int = cover.layout.cell_of(Vector2(200, 200))
	check(cover.walked_at(cell) >= 2.0, "but the cell it stands in is walked, off as on")
	cover.visible = true
	check_equal(material.get_shader_parameter(&"view_time"), 2.0, "shown again: handed the frame's clock at once")
	check_equal((material.get_shader_parameter(&"bodies") as PackedVector2Array)[0], Vector2(200, 200), "and its bodies")


## The performance pass (2026-11-21, round C): a view switched off that no body found reaches
## (`found_box`) walks none of them and takes none (a biome's 27 views each walked the 32 bodies a
## frame); shown again, it takes the finding view's bodies of that frame before it is drawn. One
## that a body reaches walks it, off as on.
func test_a_view_switched_off_out_of_reach_takes_the_bodies_only_when_shown() -> void:
	var lead: CoverScript = _cover()
	var other: CoverScript = _cover()
	var material := other.batch_of(&"test_grass").material as ShaderMaterial
	var table: ActorsScript = _table(PackedVector2Array([Vector2(3000, 3000), Vector2(3100, 2900)]))
	lead.step(1.0, table, Vector2.ZERO)
	check_equal(lead.found_box(), Rect2(3000, 2900, 100, 100), "the box round the bodies found")
	other.visible = false
	other.step_with(lead.bodies(), lead.body_count(), 1.0, null, Rect2(), -1, Callable(), lead.found_box())
	check_equal(other.body_count(), 0, "out of reach and off: no body taken")
	other.visible = true
	check_equal(other.body_count(), 2, "shown: the frame's bodies taken at once")
	check_equal((material.get_shader_parameter(&"bodies") as PackedVector2Array)[0], Vector2(3000, 3000), "and handed to its batches")
	check_equal(material.get_shader_parameter(&"body_count"), 2, "all of them")
	# A body in reach of the off view's cells walks them.
	other.visible = false
	var body := table.node_of(0) as Node2D
	body.global_position = Vector2(200, 200)
	lead.step(2.0, table, Vector2.ZERO)
	other.step_with(lead.bodies(), lead.body_count(), 2.0, null, Rect2(), -1, Callable(), lead.found_box())
	check(other.walked_at(other.layout.cell_of(Vector2(200, 200))) >= 2.0, "in reach: walked though off")
	check_equal((material.get_shader_parameter(&"bodies") as PackedVector2Array)[0], Vector2(3000, 3000), "its batches not told while off")
	other.visible = true
	check_equal((material.get_shader_parameter(&"bodies") as PackedVector2Array)[0], Vector2(200, 200), "shown: told the frame's bodies")
	check_equal((own(CoverScript.new(0)) as CoverScript).found_box(), CoverScript.NOWHERE, "a view that found none: nowhere")


func test_with_no_camera_the_first_bodies_bend_it_and_none_without_a_table() -> void:
	var cover: CoverScript = _cover()
	cover.step(1.0, _table(PackedVector2Array([Vector2(10, 10), Vector2(20, 20)])))
	check_equal(cover.body_count(), 2, "every body when they are few")
	cover.step(2.0, null)
	check_equal(cover.body_count(), 0, "none without a table")
	check_equal((cover.batch_of(&"test_grass").material as ShaderMaterial).get_shader_parameter(&"body_count"), 0, "and the shader is told")


func test_a_body_walks_the_covered_cell_it_stands_in() -> void:
	var cover: CoverScript = _cover()
	var inside := Vector2(200, 200)
	var bare := Vector2(40, 40)
	var table: ActorsScript = _table(PackedVector2Array([inside, bare]))
	var cell: int = cover.layout.cell_of(inside)
	var bare_cell: int = cover.layout.cell_of(bare)
	check_equal(cover.walked_at(cell), CoverScript.NEVER, "a cell never walked")
	check_equal(cover.flatness(cell, 0.0), 0.0, "stands up")
	cover.step(5.0, table, Vector2.ZERO)
	check_equal(cover.walked_at(cell), 5.0, "the covered cell a body stands in is walked at Feel's clock")
	check_equal(cover.walked_at(bare_cell), CoverScript.NEVER, "a cell with no cover is not")
	check_equal(cover.walked_at(cover.layout.cell_of(inside + Vector2(0, 10))), 5.0, "nor only that one: its feet reach the row in front, whose tufts would stand over a one-cell trail (GC9)")
	check_equal(cover.walked_at(cover.layout.cell_of(inside + Vector2(0, 26))), CoverScript.NEVER, "but no farther")
	check_equal(cover.walked_at(cover.layout.cell_of(inside + Vector2(16, 0))), CoverScript.NEVER, "nor a cell beside it its feet miss")
	check_equal(cover.flatness(cell, 5.0), 1.0, "flat while walked")
	check_equal(cover.flatness(cell, 5.0 + HOLD), 1.0, "and its kind's hold after")
	var half: float = cover.flatness(cell, 5.0 + HOLD + SPRING * 0.5)
	check(is_equal_approx(half, 0.5), "springing back over its kind's spring, got %f" % half)
	check(cover.flatness(cell, 5.0 + HOLD + SPRING + 0.01) == 0.0, "and up again")
	check_equal(cover.flatness(bare_cell, 5.0), 0.0, "a cell of no cover is never flat")
	var texture := (cover.batch_of(&"test_grass").material as ShaderMaterial).get_shader_parameter(&"cell_times") as Texture2D
	check(texture != null and texture.get_size() == Vector2(cover.layout.columns, cover.layout.rows), "the shader reads the grid, a texel a cell")
	(table.node_of(0) as Node2D).global_position = Vector2(40, 200)
	cover.step(6.0, table, Vector2.ZERO)
	check_equal(cover.walked_at(cell), 5.0, "a cell left keeps when it was last walked")
	cover.lay(CoverLayout.of(_layout(), _room(), [_grass()] as Array[CoverKind]))
	check_equal(cover.walked_at(cell), CoverScript.NEVER, "a room laid again starts never walked")


## A body beside the piece (its middle off it) walks the edge cell its feet reach; one whose feet
## all miss the piece walks nothing (the performance pass passes such a body by with one test).
func test_a_body_beside_the_piece_walks_the_edge_cell_its_feet_reach() -> void:
	var cover: CoverScript = _cover()
	var edge: int = 5 * cover.layout.columns
	cover.layout.cells[edge] = 1
	var corner: Vector2 = cover.layout.cell_rect(edge).position
	cover.step(5.0, _table(PackedVector2Array([corner + Vector2(-7.0, 2.0)])), Vector2.ZERO)
	check_equal(cover.walked_at(edge), CoverScript.NEVER, "feet a pixel short of the piece walk nothing")
	cover.step(6.0, _table(PackedVector2Array([corner + Vector2(-5.0, 2.0)])), Vector2.ZERO)
	check_equal(cover.walked_at(edge), 6.0, "a foot a pixel onto the piece walks its edge cell")


## The footprint's reach each way (the walk's quick test of a body off the piece) is FOOTPRINT's.
func test_the_footprints_reach_is_its_feet() -> void:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for foot in CoverScript.FOOTPRINT:
		low = low.min(foot)
		high = high.max(foot)
	check_equal(CoverScript.FOOT_REACH_LOW, low, "the least of each way")
	check_equal(CoverScript.FOOT_REACH_HIGH, high, "the most")


func test_a_states_trampled_frames_ride_in_its_rows() -> void:
	var cover: CoverScript = _cover()
	var rows: PackedFloat32Array = cover.rows_of(&"test_grass")
	check(rows.size() > 0, "rows laid")
	for at in range(0, rows.size(), CoverScript.STRIDE):
		check_equal(roundi(rows[at + 8] * 255.0), 7, "a resting tuft draws frame 6 trampled (its code 7)")
	var cell: int = cover.layout.cell_of(Vector2(200, 200))
	cover.show_state(cell, cover.layout.kinds[0].state_at(&"burning"))
	rows = cover.rows_of(&"test_grass")
	var plain: int = 0
	for at in range(0, rows.size(), CoverScript.STRIDE):
		if roundi(rows[at + 8] * 255.0) == 0:
			plain += 1
	check_equal(plain, cover.layout.kinds[0].tufts_per_cell, "a state with no trampled frames is pressed flat instead (code 0)")


## A frame of it, bodies moving through the grass, makes no object. (A packed array copied on
## write is no object: the two arrays the bodies go in, in turn, are not caught here.)
func test_a_frame_allocates_nothing() -> void:
	var cover: CoverScript = _cover()
	var places := PackedVector2Array()
	for n in 48:
		places.append(Vector2(200.0 + float(n % 8) * 6.0, 200.0 + float(n / 8) * 6.0))
	var table: ActorsScript = _table(places)
	cover.step(0.0, table, Vector2(220, 220))
	cover.step(0.016, table, Vector2(220, 220))
	var cell: int = cover.layout.cell_of(Vector2(200, 200))
	cover.show_state(cell, 1)
	cover.show_state(cell, 0)
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for frame in 200:
		for id in 48:
			var body := table.node_of(id) as Node2D
			body.global_position += Vector2(0.5, 0.25)
		cover.show_state(cell, frame % 2)
		cover.step(0.032 + float(frame) * 0.016, table, Vector2(220, 220))
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "200 frames of bodies through the grass, a cell changing each, make no object")
	check_equal(cover.body_count(), CoverScript.BODIES, "the nearest bodies still handed over")


## Feel hands its actor table and the camera's middle to the cover each frame.
func test_feels_step_bends_the_cover() -> void:
	var feel := root.get_node_or_null("Feel") as FeelScript
	check(feel != null, "the game's Feel")
	if feel == null:
		return
	var table: ActorsScript = _table(PackedVector2Array([Vector2(200, 200)]))
	var actors_before: Variant = feel.actors
	feel.actors = table
	feel.cover().lay(CoverLayout.of(_layout(), _room(), [_grass()] as Array[CoverKind]))
	feel.step(0.016)
	check_equal(feel.cover().body_count(), 1, "the actor table's body bends it")
	check(feel.cover().walked_at(feel.cover().layout.cell_of(Vector2(200, 200))) > CoverScript.NEVER, "and tramples its cell")
	feel.actors = actors_before
	feel.cover().lay(CoverLayout.of(_layout(), _room(), [] as Array[CoverKind]))


## The shader compiles with the uniforms the cover sets (a shader that fails to compile lists none:
## a regression test for a name the shading language keeps, such as `flat`).
func test_the_shader_compiles_with_its_uniforms() -> void:
	var names := PackedStringArray()
	for uniform: Dictionary in CoverScript.SHADER.get_shader_uniform_list():
		names.append(String(uniform[&"name"]))
	for wanted: String in ["view_time", "frame_size", "sheet_size", "bodies", "body_count", "bend_reach", "bend_pixels", "trample_hold", "trample_spring", "flatten", "cell_times"]:
		check(names.has(wanted), "the cover shader compiles and has '%s' (got %s)" % [wanted, names])


## The shader reads each tuft's walk from the cell it was scattered in (`Cover.foot_cell`, the
## shader's expression mirrored), a foot on its cell's bottom edge included.
func test_every_tuft_reads_its_own_cells_walk() -> void:
	var cover: CoverScript = _cover()
	var laid: CoverLayout = cover.layout
	var kind: CoverKind = laid.kinds[0]
	var key: int = CoverLayout.name_hash(kind.id)
	var checked: int = 0
	for cell in laid.cells.size():
		if laid.cells[cell] == 0:
			continue
		for tuft in kind.tufts_per_cell:
			var foot: Vector2 = CoverTufts.foot(laid, cell, tuft, kind.tufts_per_cell, CoverTufts.roll(laid, key, cell, tuft))
			check_equal(CoverScript.foot_cell(foot), Vector2i(cell % laid.columns, cell / laid.columns), "a tuft of cell %d at %s" % [cell, foot])
			checked += 1
	check(checked > 0, "tufts checked")
	var corner: Vector2 = laid.cell_rect(laid.columns + 1).position
	check_equal(CoverScript.foot_cell(corner + Vector2(1.0, float(CoverLayout.CELL))), Vector2i(1, 1), "a foot on its cell's bottom edge is its own cell's")
	check_equal(CoverScript.foot_cell(corner + Vector2(1.0, 1.0)), Vector2i(1, 1), "and one a pixel below its top")
