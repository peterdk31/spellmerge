extends "res://tests/support/suite.gd"
## Ground cover's look (ground cover GC3, docs/milestones/ground-cover.md, rules 6 and 7): Feel lays
## one batch a cover kind, made by `Batches.multimesh()`, at the floor marks' z; its tufts are the
## layout's (the cells of its kind, scattered by `CoverTufts`) and the same the editor's preview
## draws (`CoverSketch`, `CoverPreview`, `CoverField`); a room built is heard (`room_built`) and laid,
## a new room lays its own; a cell's state picks its tufts' frames, and one that draws none folds
## them away; the shader is warmed; the preview is never in the room shown. The kinds are the test
## grass (tests/core/fixtures/cover_content) with a sheet made here, so the look is tested whether or
## not the game has cover yet.
const CoverScript := preload("res://gameplay/feel/cover.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const BatchesScript := preload("res://core/projectiles/batches.gd")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const FIXTURE_ROOT: String = "res://tests/core/fixtures/cover_content"
var fixture_grass: CoverKind = preload("res://tests/core/fixtures/cover_content/cover/test_grass/test_grass.tres")
const ARENA: StringName = &"arena_01"

var _registry: RegistryScript
## The cached test grass's sheet before a test gave it one (the editor's scan hands back the same
## resource, so a test that draws through it sets it and puts it back).
var _grass_sheet: Texture2D = null


func before_each() -> void:
	_registry = own(RegistryScript.new()) as RegistryScript
	_registry.scan()
	_grass_sheet = fixture_grass.sheet


func after_each() -> void:
	fixture_grass.sheet = _grass_sheet


## A sheet of `frames` tuft frames of 16×16, each a few blades of its own shade.
static func _sheet(frames: int = 6) -> Texture2D:
	var image := Image.create_empty(16 * frames, 16, false, Image.FORMAT_RGBA8)
	for frame in frames:
		var shade := Color(0.2, 0.4 + 0.08 * float(frame), 0.2)
		for blade in 3:
			var x: int = frame * 16 + 5 + blade * 3
			for y in range(6 + blade * 2, 16):
				image.set_pixel(x, y, shade)
	return ImageTexture.create_from_image(image)


## The test grass made to fill `biome`, with a sheet.
func _grass(biome: StringName, density: float = 0.08) -> CoverKind:
	var kind := fixture_grass.duplicate(true) as CoverKind
	kind.biomes = [biome] as Array[StringName]
	kind.fill_density = density
	kind.sheet = _sheet()
	return kind


## A layout 640×384: walls round the edge a tile thick, a player spawn at (100, 100).
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
	var spawns := Node2D.new()
	spawns.name = "PlayerSpawns"
	layout.add_child(spawns)
	var marker := Marker2D.new()
	marker.position = Vector2(100, 100)
	spawns.add_child(marker)
	return layout


func _field(layout: Node, rect: Rect2, kind_id: StringName, density: float = 1.0) -> CoverField:
	var field := CoverField.new()
	field.kind = kind_id
	field.density = density
	field.offset_left = rect.position.x
	field.offset_top = rect.position.y
	field.offset_right = rect.end.x
	field.offset_bottom = rect.end.y
	layout.add_child(field)
	return field


func _room(id: StringName, biome: StringName = &"test_meadow") -> RoomBase:
	var room := RoomBase.new()
	room.id = id
	room.biome = biome
	return room


func _cover() -> CoverScript:
	var cover: CoverScript = own(CoverScript.new(RoomBase.FLOOR_Z + 1)) as CoverScript
	root.add_child(cover)
	return cover


## A kind's rows as the editor's tufts are written (`CoverSketch.TUFT_STRIDE`), for kind `index`;
## only the rows shown.
func _rows(cover: CoverScript, kind_id: StringName, index: int = 0) -> PackedFloat32Array:
	var found := PackedFloat32Array()
	var rows: PackedFloat32Array = cover.rows_of(kind_id)
	for at in range(0, rows.size(), CoverScript.STRIDE):
		if rows[at + 11] < 0.5:
			continue
		found.append_array(PackedFloat32Array([float(index), rows[at + 3], rows[at + 7], roundf(rows[at + 12] * 255.0), rows[at]]))
	return found


## The foot of each row of a kind.
func _feet(cover: CoverScript, kind_id: StringName) -> PackedVector2Array:
	var found := PackedVector2Array()
	var rows: PackedFloat32Array = cover.rows_of(kind_id)
	for at in range(0, rows.size(), CoverScript.STRIDE):
		found.append(Vector2(rows[at + 3], rows[at + 7]))
	return found


func test_one_batch_a_kind_made_by_batches_at_the_marks_z() -> void:
	var cover: CoverScript = _cover()
	var moss := _grass(&"test_meadow")
	moss.id = &"test_moss"
	var bare := _grass(&"test_meadow")
	bare.id = &"test_bare"
	bare.sheet = null
	cover.lay(CoverLayout.of(_layout(), _room(&"meadow"), [_grass(&"test_meadow"), moss, bare] as Array[CoverKind]))
	check_equal(cover.z_index, RoomBase.FLOOR_Z + 1, "at the floor marks' z")
	check(cover.batch_of(&"test_bare") == null, "a kind with no sheet has no batch")
	for kind_id: StringName in [&"test_grass", &"test_moss"]:
		var batch: MultiMeshInstance2D = cover.batch_of(kind_id)
		check(batch != null and batch.visible, "%s has its batch" % kind_id)
		check_equal(batch.multimesh.custom_aabb, BatchesScript.WORLD, "%s's batch is made by Batches.multimesh(): never culled" % kind_id)
		check(batch.multimesh.use_colors and batch.multimesh.use_custom_data, "%s's rows carry a colour and custom data, as the warm-up draws a batch" % kind_id)
		check_equal((batch.material as ShaderMaterial).shader, CoverScript.SHADER, "drawn by the cover shader")
		check_equal((batch.material as ShaderMaterial).get_shader_parameter(&"sheet_size"), Vector2(96, 16), "told its sheet's size, to draw exactly a frame of it")
		check_equal((batch.material as ShaderMaterial).get_shader_parameter(&"frame_size"), Vector2(16, 16), "and its frames'")
		check(batch.multimesh.instance_count > 0, "%s has tufts" % kind_id)


func test_the_shader_is_warmed() -> void:
	_cover()
	check(ShaderWarmupScript.shaders().has(CoverScript.SHADER), "the cover shader is warmed before the first room")
	var feel := root.get_node_or_null("Feel") as FeelScript
	check(feel != null and feel.cover() != null, "the game's Feel has its cover")


## The tufts Feel lays are the layout's: each in a cell of its kind, as many as its cells × its tufts,
## and the very tufts the editor's preview draws (`CoverSketch.tufts`), in the same order.
func test_the_tufts_are_the_layouts_and_the_editors() -> void:
	var cover: CoverScript = _cover()
	var grass := _grass(&"test_meadow", 0.1)
	var layout_root: Node2D = _layout()
	_field(layout_root, Rect2(400, 200, 128, 96), &"test_grass")
	var laid: CoverLayout = CoverLayout.of(layout_root, _room(&"meadow"), [grass] as Array[CoverKind])
	cover.lay(laid)
	var batch: MultiMeshInstance2D = cover.batch_of(&"test_grass")
	check_equal(batch.multimesh.instance_count, laid.count(&"test_grass") * grass.tufts_per_cell, "a row a tuft, its cells' tufts")
	check_equal(cover.rows_of(&"test_grass").size(), batch.multimesh.instance_count * CoverScript.STRIDE, "its rows")
	for foot in _feet(cover, &"test_grass"):
		var cell: int = laid.cell_of(foot - Vector2(0.0, 0.5))
		check(laid.kind_at(cell) == grass, "a tuft at %s stands in a cell of grass" % foot)
		check(foot == foot.round(), "on a whole pixel")
		if laid.kind_at(cell) != grass:
			break
	var editor: PackedFloat32Array = CoverSketch.tufts(laid)
	check(editor.size() > 0, "the editor draws tufts")
	check_equal(_rows(cover, &"test_grass"), editor, "Feel's tufts are the editor's, foot, frame and mirror")
	# Laid again from a fresh build: the same tufts.
	var again: CoverScript = _cover()
	var other_root: Node2D = _layout()
	_field(other_root, Rect2(400, 200, 128, 96), &"test_grass")
	again.lay(CoverLayout.of(other_root, _room(&"meadow"), [grass] as Array[CoverKind]))
	check_equal(_rows(again, &"test_grass"), editor, "the same tufts every time")
	# Another room's are its own.
	var elsewhere: CoverScript = _cover()
	elsewhere.lay(CoverLayout.of(_layout(), _room(&"elsewhere"), [grass] as Array[CoverKind]))
	check(_rows(elsewhere, &"test_grass") != editor, "another room's tufts are its own")


## Feel hears a room built (`room_built`) and lays its cover from the registry's room; a new room lays
## its own, reusing its batches; a room with no cover shows none.
func test_a_room_built_is_heard_and_laid() -> void:
	var bus: EventsScript = own(EventsScript.new()) as EventsScript
	var cover: CoverScript = own(CoverScript.new(RoomBase.FLOOR_Z + 1)) as CoverScript
	cover.events = bus
	cover.registry = _registry
	root.add_child(cover)
	var room: RoomBase = _registry.get_resource(&"rooms", ARENA) as RoomBase
	check(room != null and room.biome != &"", "the arena is a room of a biome")
	cover.use_kinds([_grass(room.biome, 0.1)] as Array[CoverKind])
	var built: Node = own(room.build(null)) as Node
	bus.room_built.emit(ARENA, 0, built)
	var expected: CoverLayout = CoverLayout.of(built, room, cover.kinds())
	check(cover.layout != null and cover.layout.cells == expected.cells, "the arena's cover is laid, as CoverLayout.of works it out")
	var batch: MultiMeshInstance2D = cover.batch_of(&"test_grass")
	check(batch != null and batch.multimesh.instance_count == expected.count() * 3, "its tufts")
	check_equal(_rows(cover, &"test_grass"), CoverSketch.tufts(expected), "the tufts the editor draws in the arena")
	var nodes: int = cover.get_child_count()
	bus.room_built.emit(ARENA, 0, own(room.build(null)) as Node)
	check_equal(cover.get_child_count(), nodes, "a room laid again uses its batches again")
	cover.use_kinds([] as Array[CoverKind])
	bus.room_built.emit(ARENA, 0, own(room.build(null)) as Node)
	check(cover.batches().is_empty(), "a room with no cover kinds has no batch")
	check(not batch.visible and batch.multimesh.instance_count == 0, "and the last room's tufts are gone")
	cover.use_kinds(null)
	check_equal(cover.kinds().size(), _registry.get_all(&"cover").size(), "the registry's kinds again")


## A cell's state picks its tufts' frames (its custom data), its sway and bend; one that draws no
## frame folds them away; at rest again they are as laid.
func test_a_cells_state_picks_its_frames() -> void:
	var cover: CoverScript = _cover()
	var grass := _grass(&"test_meadow")
	var layout_root: Node2D = _layout()
	_field(layout_root, Rect2(200, 200, 64, 64), &"test_grass")
	var laid: CoverLayout = CoverLayout.of(layout_root, _room(&"meadow"), [grass] as Array[CoverKind])
	cover.lay(laid)
	var cell: int = laid.cell_of(Vector2(232, 232))
	check(laid.kind_at(cell) == grass, "the field's middle is grass")
	var laid_rows: PackedFloat32Array = cover.rows_of(&"test_grass").duplicate()
	var rows: Array[int] = []
	var feet: PackedVector2Array = _feet(cover, &"test_grass")
	for row in feet.size():
		if laid.cell_of(feet[row] - Vector2(0.0, 0.5)) == cell:
			rows.append(row)
	check_equal(rows.size(), grass.tufts_per_cell, "the cell's tufts")
	var burning: int = grass.state_at(&"burning")
	cover.show_state(cell, burning)
	check_equal(cover.shown_state(cell), burning, "it shows burning")
	var now: PackedFloat32Array = cover.rows_of(&"test_grass")
	for row in rows:
		var at: int = row * CoverScript.STRIDE
		var frame: int = roundi(now[at + 12] * 255.0)
		check(grass.states[burning].frames.has(frame), "a burning tuft draws a burning frame (%d)" % frame)
		check(is_equal_approx(now[at + 13], grass.sway * grass.states[burning].sway / CoverScript.SWAY_CODE), "with burning's sway")
		check_equal(now[at + 11], 1.0, "and is drawn")
	for at in now.size():
		if not rows.has(at / CoverScript.STRIDE) and now[at] != laid_rows[at]:
			check(false, "only the cell's own tufts change (row %d)" % (at / CoverScript.STRIDE))
			break
	var bare := CoverState.make(&"bare", [] as Array[CoverTrigger], PackedInt32Array())
	grass.states.append(bare)
	cover.show_state(cell, grass.states.size() - 1)
	now = cover.rows_of(&"test_grass")
	for row in rows:
		check_equal(now[row * CoverScript.STRIDE + 11], 0.0, "a state of no frames folds its tufts away")
	cover.show_state(cell, 0)
	check_equal(cover.rows_of(&"test_grass"), laid_rows, "at rest again: as laid")
	cover.show_state(laid.cell_of(Vector2(40, 40)), burning)
	check_equal(cover.rows_of(&"test_grass"), laid_rows, "a cell of no cover changes nothing")


## The wind's time is Feel's clock, set each frame: by the game's Feel too.
func test_feels_step_moves_the_wind() -> void:
	var feel := root.get_node_or_null("Feel") as FeelScript
	var layout_root: Node2D = _layout()
	_field(layout_root, Rect2(200, 200, 64, 64), &"test_grass")
	feel.cover().lay(CoverLayout.of(layout_root, _room(&"meadow"), [_grass(&"test_meadow")] as Array[CoverKind]))
	var material := feel.cover().batch_of(&"test_grass").material as ShaderMaterial
	feel.step(0.25)
	var first: float = material.get_shader_parameter(&"view_time")
	feel.step(0.5)
	check(is_equal_approx(float(material.get_shader_parameter(&"view_time")) - first, 0.5), "Feel's step moves the wind by its time")
	feel.cover().lay(CoverLayout.of(_layout(), _room(&"meadow"), [] as Array[CoverKind]))


## The wind's time is Feel's clock, set each frame.
func test_the_wind_follows_feels_clock() -> void:
	var cover: CoverScript = _cover()
	var layout_root: Node2D = _layout()
	_field(layout_root, Rect2(200, 200, 64, 64), &"test_grass")
	cover.lay(CoverLayout.of(layout_root, _room(&"meadow"), [_grass(&"test_meadow")] as Array[CoverKind]))
	cover.step(12.5)
	check_equal((cover.batch_of(&"test_grass").material as ShaderMaterial).get_shader_parameter(&"view_time"), 12.5, "the shader's wind time")


## The editor's drawing: a cover field draws the tufts of its rectangle, from the whole room's cover,
## and again when the room changes under it; with a preview in the scene the preview draws the whole
## room's and the field leaves its tufts to it. Both at the game's z.
func test_the_editor_draws_the_rooms_tufts() -> void:
	fixture_grass.sheet = _sheet()
	CoverSketch.forget()
	var layout_root: Node2D = _layout()
	root.add_child(layout_root)
	var field: CoverField = _field(layout_root, Rect2(200, 200, 96, 64), &"test_grass", 0.6)
	field.content_root = FIXTURE_ROOT
	field.draws_in_play = true
	field.queue_redraw()
	await root.get_tree().process_frame
	await root.get_tree().process_frame
	var laid: CoverLayout = CoverLayout.of(layout_root, null, CoverSketch.kinds(FIXTURE_ROOT))
	var every: int = CoverSketch.tufts(laid).size() / CoverSketch.TUFT_STRIDE
	check(every > 0, "the room has tufts")
	check_equal(field.drawn, CoverSketch.tufts(laid, Rect2(200, 200, 96, 64)).size() / CoverSketch.TUFT_STRIDE, "the field draws the tufts of its rectangle")
	check_equal(field.drawn, every, "here, all of them")
	check(not field.call("_changed"), "nothing changed since")
	var clearing: CoverField = _field(layout_root, Rect2(200, 200, 48, 64), &"")
	check(field.call("_changed"), "a field laid over it changes what it would draw: it draws again")
	layout_root.remove_child(clearing)
	clearing.free()
	var preview := CoverPreview.new()
	preview.content_root = FIXTURE_ROOT
	layout_root.add_child(preview)
	check(CoverSketch.previewed(layout_root), "the scene is previewed")
	field.queue_redraw()
	preview.queue_redraw()
	await root.get_tree().process_frame
	await root.get_tree().process_frame
	check_equal(preview.drawn, every, "the preview draws every tuft of the room")
	check_equal(field.drawn, 0, "and the field leaves its tufts to it")
	check_equal(CoverSketch.Z, RoomBase.FLOOR_Z + 1, "the cover's z in the game")
	check_equal(preview.z_index, 0, "set on the server alone: no scene saves it")
	layout_root.remove_child(preview)
	preview.free()


## A cover kind with problems is in no room's cover, the game's or the editor's.
func test_a_broken_kind_is_left_out() -> void:
	var broken := _grass(&"test_meadow")
	broken.states[0].frames = PackedInt32Array([40])
	check(not CoverSketch.usable(broken), "a kind drawing a frame its sheet lacks cannot be drawn")
	check(CoverSketch.usable(_grass(&"test_meadow")), "the test grass can")
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan(FIXTURE_ROOT)
	broken.id = &"test_broken"
	check(registry.add(&"cover", broken), "the broken kind is in the registry")
	var cover: CoverScript = _cover()
	cover.registry = registry
	var ids: Array[StringName] = []
	for kind in cover.kinds():
		ids.append(kind.id)
	check_equal(ids, [&"test_grass"] as Array[StringName], "the broken kind is left out, the sound one kept")


## A kind's tufts are drawn from the top of the room down, then from the left, across cells, so a
## tuft lower on the floor is drawn over one behind it; the editor draws them in the same order.
func test_the_tufts_are_drawn_from_the_back_forward() -> void:
	var cover: CoverScript = _cover()
	var layout_root: Node2D = _layout()
	_field(layout_root, Rect2(64, 64, 512, 256), &"test_grass")
	var laid: CoverLayout = CoverLayout.of(layout_root, _room(&"meadow"), [_grass(&"test_meadow")] as Array[CoverKind])
	cover.lay(laid)
	var feet: PackedVector2Array = _feet(cover, &"test_grass")
	check(feet.size() > 100, "a field of tufts")
	for at in range(1, feet.size()):
		var before: Vector2 = feet[at - 1]
		if feet[at].y < before.y or (feet[at].y == before.y and feet[at].x < before.x):
			check(false, "tuft %d at %s is drawn after %s, which stands in front of it" % [at, feet[at], before])
			break
	check_equal(_rows(cover, &"test_grass"), CoverSketch.tufts(laid), "the editor's in the same order")


## The preview places nothing (`RoomPlaces` passes over it) and is taken out of the room shown with
## the placements and zones; the rooms' no-scripts rule allows it. In every room of the game.
func test_the_preview_is_never_in_the_room_shown() -> void:
	var layout_root: Node2D = _layout()
	var preview := CoverPreview.new()
	layout_root.add_child(preview)
	var marker := Marker2D.new()
	preview.add_child(marker)
	var holder := Node2D.new()
	layout_root.add_child(holder)
	holder.add_child(CoverPreview.new())
	_field(layout_root, Rect2(200, 200, 64, 64), &"test_grass")
	var places: RoomPlaces = RoomPlaces.read(layout_root)
	check(places.problems().is_empty(), "a preview is no problem: %s" % "; ".join(places.problems()))
	check_equal(places.zone_rects.size(), 1, "the field is read, the preview places nothing")
	check_equal(RoomScan.scripts_below(layout_root), 0, "the rooms' no-scripts rule allows the preview and the field")
	RoomPlaces.strip(layout_root)
	check(layout_root.find_children("*", "RoomPreview", true, false).is_empty() and layout_root.find_children("*", "CoverField", true, false).is_empty(), "both are taken out")
	for room_id: StringName in _registry.get_ids(&"rooms"):
		var room: RoomBase = _registry.get_resource(&"rooms", room_id) as RoomBase
		var built: Node = own(room.build(null)) as Node
		built.add_child(CoverPreview.new())
		RoomPlaces.strip(built)
		check(built.find_children("*", "RoomPreview", true, false).is_empty(), "%s: no preview in the room shown" % room_id)
