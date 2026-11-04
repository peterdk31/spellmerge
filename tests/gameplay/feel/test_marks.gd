extends "res://tests/support/suite.gd"
## Floor marks (gameplay/feel/marks.gd; docs/milestones/spell-spectacle.md, P2a): the room's mark
## layer, a viewport that is never cleared until the room ends and renders only on a frame a
## stamp lands. A cue's mark part queues one stamp at its point, as big as its reach, in the
## mark of its cards with `cards`; a frame draws the queue in one batch and empties it, a flood
## waits for later frames. A new room wipes the layer and fits it to the room's bounds, walls and
## floor colours. Kinds are data (`MarkKind`, content/marks); every mark a cue names exists. The
## layer lies over the room's floor and under every body; with the "Floor marks" setting off
## there is no layer and no nodes.

const MarksScript := preload("res://gameplay/feel/marks.gd")
const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const BatchesScript := preload("res://core/projectiles/batches.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ARENA: StringName = &"arena_01"
## The arena's bounds as Flow sets them (its 640 x 384 floor and a 32 px margin).
const BOUNDS := Rect2(-32.0, -32.0, 704.0, 448.0)
## A wall along the top of the room.
const TOP_WALL := Rect2(0.0, 0.0, 640.0, 32.0)
## Look bits of the elements' layers (layer n is bit n - 1).
const FIRE_LOOK: int = 1 << 0
const FROST_LOOK: int = 1 << 1

var registry: RegistryScript


func before_each() -> void:
	registry = own(RegistryScript.new()) as RegistryScript
	registry.scan()


func _kind(id: StringName, layer: int = -1) -> MarkKind:
	var kind := MarkKind.new()
	kind.id = id
	if layer >= 0:
		kind.look_layers = PackedInt32Array([layer])
	return kind


func _layer(kinds: Array[MarkKind] = []) -> MarksScript:
	if kinds.is_empty():
		kinds = [_kind(&"scorch"), _kind(&"frost", 2)]
	var marks: MarksScript = own(MarksScript.new(-1, kinds)) as MarksScript
	root.add_child(marks)
	marks.enter(BOUNDS, null, 8.0)
	return marks


## Feel with a bus, the registry and a projectile manager in the arena's bounds with a wall along
## the top, told it entered the arena.
func _feel() -> Array:
	var bus: EventsScript = own(EventsScript.new()) as EventsScript
	var feel: FeelScript = own(FeelScript.new()) as FeelScript
	var preset := FeelPresetScript.new()
	preset.hit_sound = &""
	feel.events = bus
	feel.registry = registry
	feel.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	var projectiles: ProjectilesScript = own(ProjectilesScript.new()) as ProjectilesScript
	projectiles.set_bounds(BOUNDS)
	projectiles.set_walls([TOP_WALL] as Array[Rect2])
	feel.projectiles = projectiles
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)
	bus.room_entered.emit(ARENA)
	return [bus, feel]


func test_every_mark_kind_is_valid_and_every_cue_names_one() -> void:
	var ids: Array[StringName] = registry.get_ids(&"marks")
	for id: StringName in [&"scorch", &"crack", &"frost"]:
		check(ids.has(id), "the %s mark is there" % id)
	for id in ids:
		var kind: MarkKind = registry.get_resource(&"marks", id) as MarkKind
		check(kind != null, "%s is a MarkKind" % id)
		if kind != null:
			check_equal(kind.problems(), PackedStringArray(), "%s has no problems" % id)
			check_equal(kind.resource_path.get_file(), "%s.tres" % id, "%s is in its own file" % id)
	check(ids.size() <= MarksScript.MAX_KINDS, "the shader holds every kind")
	var named: int = 0
	for cue_id: StringName in registry.get_ids(&"cues"):
		var cue: CueBase = registry.get_resource(&"cues", cue_id) as CueBase
		for part: Dictionary in cue.parts:
			if StringName(part.get("part", "")) == &"mark":
				named += 1
				check(ids.has(StringName(part["mark"])), "%s names the mark '%s', which exists" % [cue_id, part["mark"]])
	check(named >= 3, "the blast, fireball, slam and quake cues leave marks (%d parts)" % named)
	for cue_id: StringName in [&"blast", &"slam"]:
		var parts: Array[Dictionary] = (registry.get_resource(&"cues", cue_id) as CueBase).parts
		check(parts.any(func(p: Dictionary) -> bool: return StringName(p.get("part", "")) == &"mark"), "%s leaves a mark" % cue_id)


func test_problems_name_what_is_wrong() -> void:
	var kind := _kind(&"broken")
	kind.form = "smear"
	kind.body_shade = "light"
	kind.edge_from = "sky"
	kind.look_layers = PackedInt32Array([30])
	check_equal(kind.problems().size(), 4, "a form, a shade (light is not a mark's), a source and a layer: %s" % [kind.problems()])
	var cue := CueBase.new()
	cue.id = &"broken"
	cue.parts = [{"part": &"mark"}, {"part": &"mark", "mark": &"scorch", "zoom": 2, "rot": &"spin", "radius": 0.0}]
	check_equal(cue.problems().size(), 4, "no mark; an unknown key, an unknown rot and a radius of 0: %s" % [cue.problems()])
	cue.parts = [{"part": &"mark", "mark": &"scorch", "reach": 0.9, "cards": true, "rot": &"aim"}]
	check_equal(cue.problems(), PackedStringArray(), "a fine mark part (it takes no effect)")


func test_the_shader_is_handed_each_kinds_numbers() -> void:
	var crack := _kind(&"crack")
	crack.form = "crack"
	crack.rough = 0.7
	crack.lines = 6
	crack.edge_from = "floor"
	var broken := _kind(&"")
	var marks: MarksScript = _layer([_kind(&"first"), broken, crack])
	check_equal(marks.kinds().size(), 2, "a kind with problems is left out")
	var forms: PackedVector4Array = marks.shader_parameter(&"kind_form")
	var colours: PackedVector4Array = marks.shader_parameter(&"kind_colour")
	check_equal(forms.size(), MarksScript.MAX_KINDS, "room for every kind")
	check(forms[1].is_equal_approx(Vector4(1.0, 0.7, 0.5, 6.0)), "the crack's form, rough, fill and lines: %s" % [forms[1]])
	check_equal(colours[1], Vector4(0.0, 1.0, 0.0, 1.0), "its body and edge from the floor, both in shadow")
	check_equal(colours[0], Vector4(0.0, 1.0, 1.0, 1.0), "a default kind: the floor's shadow, the spell's shadow at its edge")
	var code: String = FileAccess.get_file_as_string("res://gameplay/feel/mark.gdshader")
	check(code.contains("uniform vec4 kind_form[%d];" % MarksScript.MAX_KINDS) and code.contains("uniform vec4 kind_colour[%d];" % MarksScript.MAX_KINDS), "the shader holds as many")
	for name: String in ["KIND_CODE", "SOURCE_CODE"]:
		check(code.contains("const float %s = %.1f;" % [name, float((MarksScript as GDScript).get_script_constant_map()[name])]), "the shader's %s is marks.gd's" % name)
	check(code.contains("const float EXACT_SOURCE = %.1f;" % float(MotesScript.EXACT_SOURCE)), "and its EXACT_SOURCE the motes'")
	check(code.contains("const int MAX_KINDS = %d;" % MarksScript.MAX_KINDS), "and MAX_KINDS")
	for i in MarkKind.FORMS.size():
		check(code.contains("%d %s" % [i, MarkKind.FORMS[i]]), "the shader says form %d is %s" % [i, MarkKind.FORMS[i]])


func test_a_stamp_waits_for_the_frame_and_draws_once() -> void:
	var marks: MarksScript = _layer()
	check(marks.viewport() != null and marks.sprite() != null and marks.batch() != null, "a layer once it has a room")
	check_equal(marks.layer_size(), Vector2i(704, 448), "as big as the room's bounds, a texel a pixel")
	check_equal(marks.origin(), BOUNDS.position, "from its corner")
	check_equal(marks.sprite().position, BOUNDS.position, "shown there")
	check_equal(marks.texture_bytes(), 704 * 448 * 4, "RGBA8: about 1.2 MB for the arena")
	check_equal(marks.viewport().render_target_clear_mode, SubViewport.CLEAR_MODE_ONCE, "a new room is wiped once")
	marks.step()
	marks.step()
	check_equal(marks.viewport().render_target_update_mode, SubViewport.UPDATE_DISABLED, "after the wipe, nothing renders")
	check_equal(marks.batch().multimesh.custom_aabb, BatchesScript.WORLD, "its batch is made by Batches (never culled)")
	check(marks.batch().get_parent() == marks.viewport(), "and draws into the layer")
	var renders: int = marks.renders
	marks.stamp(0, Vector2(100.4, 60.6), 20.0, 0.5, 2, Color("e0592f"))
	check_equal(marks.pending(), 1, "a stamp waits for the frame")
	check_equal(marks.renders, renders, "and renders nothing yet")
	var row: PackedFloat32Array = marks.pending_row(0)
	check_equal(Vector2(row[3], row[7]), Vector2(132.0, 93.0), "at its point in the layer, on a whole pixel")
	check_equal(row[0], 20.0, "its radius")
	check(is_equal_approx(row[4], 0.5), "its turn")
	check_equal(roundi(row[8] * MarksScript.KIND_CODE), 0, "its kind")
	check_equal(roundi(row[9] * MarksScript.SOURCE_CODE), 2, "its spell's source")
	check(Color(row[12], row[13], row[14]).is_equal_approx(Color("e0592f")), "and its core colour")
	marks.step()
	check_equal(marks.pending(), 0, "the frame takes it")
	check_equal(marks.drawn(), 1, "the batch draws it alone")
	check_equal(marks.renders, renders + 1, "in one render")
	check_equal(marks.viewport().render_target_update_mode, SubViewport.UPDATE_ONCE, "this frame only")
	marks.step()
	check_equal(marks.renders, renders + 1, "a frame with no stamps renders nothing")
	check_equal(marks.viewport().render_target_update_mode, SubViewport.UPDATE_DISABLED, "its viewport reads UPDATE_DISABLED")


func test_a_flood_waits_for_later_frames() -> void:
	var marks: MarksScript = _layer()
	for i in MarksScript.STAMPS_PER_FRAME + 10:
		marks.stamp(0, Vector2(i % 600, 100.0), 4.0, 0.0, 0, Color.WHITE)
	marks.step()
	check_equal(marks.drawn(), MarksScript.STAMPS_PER_FRAME, "a frame draws STAMPS_PER_FRAME")
	check_equal(marks.pending(), 10, "the rest wait")
	marks.step()
	check_equal(marks.drawn(), 10, "and are drawn the next frame")
	for i in MarksScript.PENDING_MAX + 3:
		marks.stamp(0, Vector2(10.0, 10.0), 4.0, 0.0, 0, Color.WHITE)
	check_equal(marks.pending(), MarksScript.PENDING_MAX, "at most PENDING_MAX wait")
	check_equal(marks.left_out, 3, "the ones past it are counted")
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for frame in 20:
		for i in 300:
			marks.stamp(0, Vector2(i, frame), 4.0, 0.0, 0, Color.WHITE)
		marks.step()
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "nothing is made while stamping")


func test_a_new_room_wipes_the_layer() -> void:
	var marks: MarksScript = _layer()
	marks.stamp(0, Vector2(10.0, 10.0), 4.0, 0.0, 0, Color.WHITE)
	marks.step()
	marks.stamp(0, Vector2(20.0, 10.0), 4.0, 0.0, 0, Color.WHITE)
	var viewport: SubViewport = marks.viewport()
	marks.enter(BOUNDS, null, 8.0)
	check(marks.viewport() == viewport, "the same size: the same viewport")
	check_equal(marks.pending(), 0, "the waiting stamps go")
	check_equal(marks.drawn(), 0, "the wipe draws no stamp again")
	check_equal(viewport.render_target_clear_mode, SubViewport.CLEAR_MODE_ONCE, "it is cleared once")
	check_equal(viewport.render_target_update_mode, SubViewport.UPDATE_ONCE, "in one render")
	marks.enter(Rect2(0.0, 0.0, 1344.0, 784.0), null, 8.0)
	check_equal(marks.layer_size(), Vector2i(1344, 784), "a bigger room: a bigger layer (the horde's, about 4.2 MB)")
	marks.enter(Rect2(0.0, 0.0, 9000.0, 300.0), null, 8.0)
	check_equal(marks.layer_size(), Vector2i(MarksScript.MAX_SIDE, 300), "at most MAX_SIDE across")


func test_the_walls_clip_the_marks() -> void:
	var projectiles: ProjectilesScript = own(ProjectilesScript.new()) as ProjectilesScript
	projectiles.set_bounds(BOUNDS)
	projectiles.set_walls([TOP_WALL] as Array[Rect2])
	check_equal(projectiles.bounds(), BOUNDS, "the manager's bounds")
	var walls: Image = projectiles.wall_image()
	check_equal(walls.get_size(), Vector2i(88, 56), "a pixel a wall cell over the bounds")
	check(walls.get_pixel(4, 4).r > 0.5, "the top wall is white")
	check(walls.get_pixel(4, 3).r < 0.5 and walls.get_pixel(4, 8).r < 0.5, "above it (the margin) and under it is open")
	var marks: MarksScript = _layer()
	marks.enter(projectiles.bounds(), walls, ProjectilesScript.WALL_CELL)
	check(marks.shader_parameter(&"floor_mask") is Texture2D, "the shader reads the walls")
	check_equal(marks.shader_parameter(&"mask_size"), Vector2(88.0, 56.0), "its size in cells")
	check_equal(marks.shader_parameter(&"mask_cell"), ProjectilesScript.WALL_CELL, "and a cell's pixels")


func test_a_cue_stamps_its_mark_as_big_as_its_reach() -> void:
	var pair: Array = _feel()
	var feel: FeelScript = pair[1]
	var marks: MarksScript = feel.marks()
	check(marks != null, "Feel has a mark layer")
	if marks == null:
		return
	check_equal(marks.layer_size(), Vector2i(704, 448), "fitted to the room it entered")
	check(marks.shader_parameter(&"mask_size") == Vector2(88.0, 56.0), "with its walls")
	var floor_ramp: PackedVector3Array = marks.shader_parameter(&"floor_ramp")
	check_equal(marks.shader_parameter(&"floor_known"), 1.0, "and its floor's colours")
	var shadow: Color = Color("2b2840") * Color(0.72, 0.7, 0.86)
	check(Color(floor_ramp[2].x, floor_ramp[2].y, floor_ramp[2].z).is_equal_approx(Color(shadow.r, shadow.g, shadow.b)), "the crypt floor's shadow, sampled from its art and tinted as the floor is: %s" % [floor_ramp[2]])
	var blast: CueBase = feel.cue_of(&"blast")
	var part: Dictionary = {}
	for p: Dictionary in blast.parts:
		if StringName(p.get("part", "")) == &"mark":
			part = p
	feel.play_cue(&"blast", 0, Vector2(200.0, 150.0), Vector2.RIGHT, 40.0)
	check_equal(marks.pending(), 1, "a blast queues one stamp")
	var row: PackedFloat32Array = marks.pending_row(0)
	check_equal(Vector2(row[3], row[7]), Vector2(232.0, 182.0), "where it went off")
	check_equal(row[0], roundf(40.0 * float(part["reach"])), "its size times the part's reach")
	check_equal(roundi(row[8] * MarksScript.KIND_CODE), marks.kind_index(&"scorch"), "a scorch")
	feel.step(0.016)
	check_equal(marks.pending(), 0, "Feel's frame draws it")
	check_equal(marks.drawn(), 1, "in the batch")
	feel.play_cue(&"blast", 0, Vector2(200.0, 150.0), Vector2.RIGHT, 40.0, Color("4fd6dc"), FROST_LOOK)
	check_equal(roundi(marks.pending_row(0)[8] * MarksScript.KIND_CODE), marks.kind_index(&"frost"), "a frost blast leaves frost (its cards' mark)")
	feel.play_cue(&"blast", 0, Vector2(200.0, 150.0), Vector2.RIGHT, 40.0, Color("e0592f"), FIRE_LOOK)
	check_equal(roundi(marks.pending_row(1)[8] * MarksScript.KIND_CODE), marks.kind_index(&"scorch"), "a fire blast: fire has no mark, so the scorch")
	feel.play_cue(&"slam", 0, Vector2(300.0, 150.0), Vector2.RIGHT, 30.0, Color("4fd6dc"), FROST_LOOK)
	check_equal(roundi(marks.pending_row(2)[8] * MarksScript.KIND_CODE), marks.kind_index(&"crack"), "a slam cracks the floor whatever its cards")
	check_equal(marks.pending(), 3, "one stamp a cue")
	feel.play_cue(&"nova", 0, Vector2(300.0, 150.0))
	check_equal(marks.pending(), 3, "a cue with no mark part stamps nothing")


func test_a_new_room_and_the_setting() -> void:
	var pair: Array = _feel()
	var bus: EventsScript = pair[0]
	var feel: FeelScript = pair[1]
	feel.play_cue(&"slam", 0, Vector2(300.0, 150.0), Vector2.RIGHT, 30.0)
	feel.step(0.016)
	feel.play_cue(&"slam", 0, Vector2(300.0, 150.0), Vector2.RIGHT, 30.0)
	bus.room_entered.emit(ARENA)
	check_equal(feel.marks().pending(), 0, "a new room: the marks so far go")
	check_equal(feel.marks().viewport().render_target_clear_mode, SubViewport.CLEAR_MODE_ONCE, "the layer is wiped")
	bus.floor_marks_changed.emit(false)
	check(feel.marks() == null and not feel.floor_marks, "off: no layer")
	check(feel.find_children("*", "SubViewport", true, false).is_empty(), "and no nodes")
	feel.play_cue(&"slam", 0, Vector2(300.0, 150.0), Vector2.RIGHT, 30.0)
	feel.step(0.016)
	bus.floor_marks_changed.emit(true)
	check(feel.marks() != null and feel.marks().layer_size() == Vector2i(704, 448), "on again: a layer fitted to the room")
	check_equal(feel.marks().pending(), 0, "with nothing from while it was off")


func test_the_layer_lies_on_the_floor_under_every_body() -> void:
	var pair: Array = _feel()
	var feel: FeelScript = pair[1]
	var z: int = feel.marks().sprite().z_index
	check_equal(z, FeelScript.MARK_Z, "at MARK_Z")
	check(z > RoomBase.FLOOR_Z, "over the room's floor")
	check(z < 0, "under the bodies (wizards and enemies at 0)")
	check(z < FeelScript.MOTE_Z and z < FeelScript.FLOOR_Z, "under the motes and Feel's floor flashes")
	for room_id: StringName in registry.get_ids(&"rooms"):
		var room: RoomBase = registry.get_resource(&"rooms", room_id) as RoomBase
		var layout: Node = room.scene.instantiate()
		var floor_sprite: Sprite2D = layout.get_node_or_null("Floor") as Sprite2D
		check(floor_sprite != null and floor_sprite.z_index == RoomBase.FLOOR_Z, "%s's floor is at RoomBase.FLOOR_Z, under the marks" % room_id)
		layout.free()
		check_equal(room.floor_colors().size(), 3, "%s's floor colours are sampled from its art" % room_id)


func test_a_rooms_floor_colours_can_be_set() -> void:
	var room := RoomBase.new()
	check_equal(room.floor_colors(), PackedColorArray(), "no art, no colours")
	room.floor_mark_colors = PackedColorArray([Color("2b2840"), Color("7a7694")])
	check_equal(room.floor_colors(), PackedColorArray([Color("7a7694"), Color("7a7694"), Color("2b2840")]), "set: lightest first, three shades")


func test_off_from_the_start_makes_nothing() -> void:
	var probe: FeelScript = own(FeelScript.new()) as FeelScript
	check_equal(probe.floor_marks, FloorMarks.default_on(), "the platform's default")
	var pair: Array = _feel()
	var feel: FeelScript = pair[1]
	feel.set_floor_marks(false)
	feel.play_cue(&"blast", 0, Vector2(200.0, 150.0), Vector2.RIGHT, 40.0)
	feel.step(0.016)
	check(feel.marks() == null, "no layer, and a cue's mark part does nothing")
