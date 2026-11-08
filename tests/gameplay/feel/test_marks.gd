extends "res://tests/support/suite.gd"
## Floor marks (gameplay/feel/marks.gd; docs/milestones/spell-spectacle.md, P2a): the room's mark
## layer, a viewport that is never cleared until the room ends and renders only on a frame a
## stamp lands. A cue's mark part queues one stamp at its point, as big as its reach, in the
## mark of its cards with `cards`; a frame draws the queue in one batch and empties it, a flood
## waits for later frames. A new room wipes the layer and fits it to the room's bounds, walls and
## floor colours. Kinds are data (`MarkKind`, content/marks); every mark a cue names exists. The
## layer lies over the room's floor and under every body; with the "Floor marks" setting off
## there is no layer and no nodes.
##
## P2b: a mote of a kind that settles (`MoteKind.settles`) leaves its mark where `Motes.mote_land`
## says it comes to rest, never before then and at most a slot after, SETTLED_PER_FRAME a frame at
## most; the other marks (a nova's burn ring, a rune's scar, a death's ichor in the body's own
## colours, lightning's char) are stamped by their cues.

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
const LIGHTNING_LOOK: int = 1 << 4
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")

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
	for id: StringName in [&"scorch", &"crack", &"frost", &"speck", &"burn_ring", &"rune_scar", &"ichor", &"char"]:
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
				if not part.has("mark"):
					check(bool(part.get("cards", false)), "%s: a mark part with no mark takes its cards' marks" % cue_id)
					continue
				check(ids.has(StringName(part["mark"])), "%s names the mark '%s', which exists" % [cue_id, part["mark"]])
	check(named >= 3, "the blast, fireball, slam and quake cues leave marks (%d parts)" % named)
	for cue_id: StringName in [&"blast", &"slam", &"nova", &"rune_burst", &"enemy_death", &"boss_death"]:
		var parts: Array[Dictionary] = (registry.get_resource(&"cues", cue_id) as CueBase).parts
		check(parts.any(func(p: Dictionary) -> bool: return StringName(p.get("part", "")) == &"mark"), "%s leaves a mark" % cue_id)
	var settling: int = 0
	for mote_id: StringName in registry.get_ids(&"motes"):
		var mote: MoteKind = registry.get_resource(&"motes", mote_id) as MoteKind
		if mote.settles != &"":
			settling += 1
			check(ids.has(mote.settles), "%s settles as the mark '%s', which exists" % [mote_id, mote.settles])
	check(settling >= 2, "the falling kinds settle (the chips, frost's flecks): %d" % settling)


func test_problems_name_what_is_wrong() -> void:
	var kind := _kind(&"broken")
	kind.form = "smear"
	kind.body_shade = "light"
	kind.edge_from = "sky"
	kind.look_layers = PackedInt32Array([30])
	check_equal(kind.problems().size(), 4, "a form, a shade (light is not a mark's), a source and a layer: %s" % [kind.problems()])
	var ember := MoteKind.new()
	ember.id = &"ember"
	ember.look_layers = PackedInt32Array([1])
	ember.gravity = -10.0
	ember.settles = &"speck"
	check_equal(ember.problems().size(), 1, "a mote that rises never comes to rest, so it leaves no mark: %s" % [ember.problems()])
	var cue := CueBase.new()
	cue.id = &"broken"
	cue.parts = [{"part": &"mark"}, {"part": &"mark", "mark": &"scorch", "zoom": 2, "rot": &"spin", "radius": 0.0}]
	check_equal(cue.problems().size(), 4, "no mark; an unknown key, an unknown rot and a radius of 0: %s" % [cue.problems()])
	cue.parts = [{"part": &"mark", "mark": &"scorch", "reach": 0.9, "cards": true, "rot": &"aim"}, {"part": &"mark", "cards": true, "radius": 6.0}]
	check_equal(cue.problems(), PackedStringArray(), "fine mark parts (they take no flash; with cards the mark may be left out)")


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
	check(code.contains("const float TABLE_SOURCE = %.1f;" % float(MotesScript.TABLE_SOURCE)), "and its TABLE_SOURCE")
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


func test_a_new_floor_flash_draws_over_the_marks_left_before() -> void:
	# The owner, 2026-11-08: the debris a slam leaves drew over the next slam's strike. The floor
	# flashes and the mark layer share a z, so the later in the tree draws on top: the flashes.
	var pair: Array = _feel()
	var feel: FeelScript = pair[1]
	check_equal(feel._floor_node.z_index, feel.marks().sprite().z_index, "one z")
	check(feel._floor_node.is_greater_than(feel.marks().sprite()), "the floor flashes after the marks in the tree")
	feel.set_floor_marks(false)
	feel.set_floor_marks(true)
	check(feel._floor_node.is_greater_than(feel.marks().sprite()), "and after a mark layer made again (the setting turned back on)")


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
	feel.play_cue(&"heal", 0, Vector2(300.0, 150.0))
	check_equal(marks.pending(), 3, "a cue with no mark part stamps nothing")
	feel.play_cue(&"blast", 0, Vector2(200.0, 150.0), Vector2.RIGHT, 40.0, Color("f4e04d"), LIGHTNING_LOOK)
	check_equal(roundi(marks.pending_row(3)[8] * MarksScript.KIND_CODE), marks.kind_index(&"char"), "a lightning blast leaves char")
	# A dash's landing (S5) names no mark: only its cards' marks.
	feel.play_cue(&"dash_land", 0, Vector2(200.0, 150.0), Vector2.RIGHT, 1.0, Color("e0592f"), FIRE_LOOK)
	check_equal(marks.pending(), 4, "a fire dash lands leaving nothing (fire has no mark)")
	feel.play_cue(&"dash_land", 0, Vector2(200.0, 150.0), Vector2.RIGHT, 1.0, Color("4fd6dc"), FROST_LOOK)
	check_equal(marks.pending(), 5, "a frost dash lands on frost")
	check_equal(roundi(marks.pending_row(4)[8] * MarksScript.KIND_CODE), marks.kind_index(&"frost"), "its cards' mark")
	check_equal(marks.pending_row(4)[0], 6.0, "as big as the part's radius")


func test_the_other_marks_come_from_their_cues() -> void:
	var pair: Array = _feel()
	var feel: FeelScript = pair[1]
	var marks: MarksScript = feel.marks()
	feel.play_cue(&"nova", 0, Vector2(300.0, 150.0))
	check_equal(roundi(marks.pending_row(0)[8] * MarksScript.KIND_CODE), marks.kind_index(&"burn_ring"), "a nova burns a ring round its caster")
	var rune: FormBase = registry.get_resource(&"spells", &"rune") as FormBase
	check_equal(rune.impact_cue, &"rune_burst", "a rune's impact plays rune_burst")
	feel.play_cue(&"rune_burst", 0, Vector2(300.0, 150.0), Vector2.RIGHT, rune.radius)
	check_equal(roundi(marks.pending_row(1)[8] * MarksScript.KIND_CODE), marks.kind_index(&"rune_scar"), "which leaves a rune's scar")
	check_equal(marks.pending_row(1)[0], roundf(rune.radius), "as big as the rune")
	feel.play_cue(&"enemy_death", 0, Vector2(300.0, 150.0))
	var row: PackedFloat32Array = marks.pending_row(2)
	check_equal(roundi(row[8] * MarksScript.KIND_CODE), marks.kind_index(&"ichor"), "a death leaves ichor")
	var surface: int = roundi(row[10] * MarksScript.SOURCE_CODE)
	check(surface >= MotesScript.TABLE_SOURCE, "in the colours of a surface, a row of the ramp table: %d" % surface)
	check(marks.shader_parameter(&"ramp_table") is Texture2D and marks.shader_parameter(&"table_rows") == float(RampTableScript.ROWS), "which the marks read")
	var ichor: MarkKind = marks.kinds()[marks.kind_index(&"ichor")]
	check(ichor.body_from == "surface" and ichor.edge_from == "surface", "ichor is all the surface's colours (the body's own art, not blood)")


func _settling_pair(kinds: Array[MoteKind]) -> Array:
	var speck := _kind(&"speck")
	speck.form = "speck"
	speck.body_from = "spell"
	var marks: MarksScript = _layer([_kind(&"scorch"), speck])
	var motes: MotesScript = own(MotesScript.new(4096, 0, kinds)) as MotesScript
	root.add_child(motes)
	motes.settle_into(marks)
	motes.step(0.0)
	marks.step(0.0)
	return [motes, marks]


func test_a_settled_mote_leaves_its_mark_where_it_rests() -> void:
	var chip: MoteKind = registry.get_resource(&"motes", &"chip") as MoteKind
	var ember: MoteKind = registry.get_resource(&"motes", &"ember") as MoteKind
	check_equal(chip.settles, &"speck", "a chip settles as a speck")
	var pair: Array = _settling_pair([chip, ember] as Array[MoteKind])
	var motes: MotesScript = pair[0]
	var marks: MarksScript = pair[1]
	check_equal(motes.settle_mark(0), marks.kind_index(&"speck"), "the chips' mark is the layer's speck")
	check_equal(motes.settle_mark(1), -1, "an ember leaves none")
	var source: int = motes.table_source(PackedColorArray([Color("c8c3b4"), Color("8a8577"), Color("4e4a42")]))
	motes.throw(1, Vector2(200.0, 150.0), Vector2.RIGHT, 2, Color.WHITE, 3.0)
	check_equal(marks.settling(), 0, "embers rise: nothing settles")
	var first: int = motes.next_row()
	motes.throw(0, Vector2(200.0, 150.0), Vector2.RIGHT, source, Color.WHITE, 2.0)
	var thrown: int = motes.next_row() - first
	var lands: Array[Vector3] = []
	for row in range(first, first + thrown):
		var land: Vector3 = motes.mote_land(row)
		if land.z != INF:
			lands.append(land)
	check(thrown > 0 and lands.size() > 0, "chips are thrown (%d) and come to rest (%d)" % [thrown, lands.size()])
	check_equal(marks.settling(), lands.size(), "each one that rests in its life waits for its time")
	var found: Dictionary = {}
	var t: float = 0.0
	while t < MotesScript.LIFE_MAX + 0.5:
		t += 1.0 / 60.0
		marks.settle_due(t)
		for n in marks.pending():
			var row: PackedFloat32Array = marks.pending_row(n)
			var at := Vector2(row[3], row[7]) + marks.origin()
			found[at] = found.get(at, 0) + 1
			var match_land: bool = false
			for land in lands:
				if Vector2(land.x, land.y).floor() == at and t >= land.z and t <= land.z + MarksScript.SETTLE_SLOT + 1.0 / 60.0 + 0.0001:
					match_land = true
			check(match_land, "a speck at %s at %.3f s: where a chip rests, once it does, at most a slot later" % [at, t])
			check_equal(row[0], 1.0, "one pixel")
			check_equal(roundi(row[8] * MarksScript.KIND_CODE), marks.kind_index(&"speck"), "a speck")
			check_equal(roundi(row[9] * MarksScript.SOURCE_CODE), source, "in the chip's own colours")
		marks.step()
	var stamped: int = 0
	for at: Vector2 in found:
		stamped += found[at]
	check_equal(stamped, lands.size(), "every chip that rests leaves one speck")
	check_equal(marks.settling(), 0, "and none waits")
	check_equal(marks.settles_faded, 0, "none faded")


func test_settled_motes_are_capped_a_frame() -> void:
	var pair: Array = _settling_pair([registry.get_resource(&"motes", &"chip") as MoteKind] as Array[MoteKind])
	var marks: MarksScript = pair[1]
	for i in MarksScript.SETTLE_SLOT_ROWS + 5:
		marks.settle(1, Vector2(i % 600, 100.0), 0.5, 2, Color.WHITE)
	check_equal(marks.settling(), MarksScript.SETTLE_SLOT_ROWS, "a slot holds SETTLE_SLOT_ROWS")
	check_equal(marks.settles_faded, 5, "the rest fade")
	for slot in 3:
		for i in 200:
			marks.settle(1, Vector2(i, 200.0 + slot), (30.5 + slot) * MarksScript.SETTLE_SLOT, 2, Color.WHITE)
	marks.settle_due(0.6)
	check_equal(marks.pending(), MarksScript.SETTLE_SLOT_ROWS, "a frame stamps what is due")
	marks.step()
	marks.settle_due(2.0)
	check_equal(marks.pending(), MarksScript.SETTLED_PER_FRAME, "at most SETTLED_PER_FRAME a frame")
	check_equal(marks.settles_faded, 5 + 600 - MarksScript.SETTLED_PER_FRAME, "the rest fade with their motes")
	check_equal(marks.settling(), 0, "and none waits")
	marks.settle(1, Vector2(10.0, 10.0), 0.1, 2, Color.WHITE)
	marks.settle_due(2.1)
	check_equal(marks.pending(), MarksScript.SETTLED_PER_FRAME + 1, "one already due is stamped at the next frame")
	marks.settle(1, Vector2(10.0, 10.0), 3.0, 2, Color.WHITE)
	marks.enter(BOUNDS, null, 8.0)
	check_equal(marks.settling(), 0, "a new room: the waiting motes go")
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for frame in 30:
		for i in 100:
			marks.settle(1, Vector2(i, frame), 2.2 + frame * 0.02, 2, Color.WHITE)
		marks.step(2.2 + frame * 0.02)
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "nothing is made while settling")


func test_feel_links_settled_motes_to_the_settings() -> void:
	var pair: Array = _feel()
	var bus: EventsScript = pair[0]
	var feel: FeelScript = pair[1]
	feel.set_mote_cap(8192)
	var chip: int = feel.motes().kind_index(&"chip")
	check_equal(feel.motes().settle_mark(chip), feel.marks().kind_index(&"speck"), "Feel's chips settle into its layer")
	feel.step(0.016)
	feel.step(0.016)
	feel.play_cue(&"slam", 0, Vector2(300.0, 150.0), Vector2.RIGHT, 30.0)
	check(feel.marks().settling() > 0, "a slam's chips wait to settle: %d" % feel.marks().settling())
	for i in 300:
		feel.step(0.016)
	check_equal(feel.marks().settling(), 0, "and are stamped as Feel's clock passes")
	bus.floor_marks_changed.emit(false)
	check_equal(feel.motes().settle_mark(chip), -1, "floor marks off: nothing settles")
	feel.play_cue(&"slam", 0, Vector2(300.0, 150.0), Vector2.RIGHT, 30.0)
	bus.floor_marks_changed.emit(true)
	check_equal(feel.motes().settle_mark(chip), feel.marks().kind_index(&"speck"), "on again: linked again")
	feel.set_mote_cap(MoteCap.STOPS[0])
	check_equal(feel.motes().settle_mark(chip), feel.marks().kind_index(&"speck"), "a new ring (the Minimal one): linked to the layer")


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
	# Only the mark layer's nodes: spell light has a viewport of its own under Feel.
	check(feel.find_child("Marks", true, false) == null and feel.find_children("*", "SubViewport", true, false).all(func(n: Node) -> bool: return feel.light() != null and feel.light().is_ancestor_of(n)), "and no nodes")
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
	check(z < FeelScript.MOTE_Z, "under the motes")
	check_equal(FeelScript.FLOOR_Z, z, "with Feel's floor flashes (a slam's strike, a quake's cracks), on the floor under the bodies")
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


func test_a_rooms_first_frame_can_settle_motes() -> void:
	var marks: MarksScript = own(MarksScript.new(-1, [_kind(&"speck")] as Array[MarkKind])) as MarksScript
	root.add_child(marks)
	marks.step(1.0)
	marks.enter(BOUNDS, null, 8.0)
	marks.settle(0, Vector2(100.0, 100.0), 1.5, 2, Color.WHITE)
	check_equal(marks.settling(), 1, "the clock was learnt before the room: a mote thrown as it is entered settles")
	marks.step(1.6)
	check_equal(marks.drawn(), 1, "and is stamped once it rests")


## The specks a pool's settling motes leave, over the clock from 0 to past their lives: each
## stamped one's point and the time it was stamped.
func _stamped_over_time(marks: MarksScript) -> Array[Vector3]:
	var found: Array[Vector3] = []
	var t: float = 0.0
	while t < MotesScript.LIFE_MAX + 0.5:
		t += 1.0 / 60.0
		marks.settle_due(t)
		for n in marks.pending():
			var row: PackedFloat32Array = marks.pending_row(n)
			var at := Vector2(row[3], row[7]) + marks.origin()
			found.append(Vector3(at.x, at.y, t))
		marks.step()
	return found


## A kind that sways (wobble) or glides with no drag rests where `mote_land` says, as a chip does:
## the settled marks use the very sum the flight does.
func test_swaying_and_dragless_kinds_settle_where_they_rest() -> void:
	var sway := MoteKind.new()
	sway.id = &"sway"
	sway.surface = true
	sway.settles = &"speck"
	sway.gravity = 300.0
	sway.drag = 1.5
	sway.bounce = 0.4
	sway.wobble = 4.0
	sway.wobble_rate = 9.0
	var glide := MoteKind.new()
	glide.id = &"glide"
	glide.surface = true
	glide.settles = &"speck"
	glide.gravity = 300.0
	glide.drag = 0.0
	glide.bounce = 0.2
	var pair: Array = _settling_pair([sway, glide] as Array[MoteKind])
	var motes: MotesScript = pair[0]
	var marks: MarksScript = pair[1]
	var lands: Array[Vector3] = []
	for k in 2:
		var first: int = motes.next_row()
		motes.burst(k, Vector2(200.0 + 100.0 * k, 150.0), Vector2.RIGHT, 6, Vector2(20.0, 60.0), 120.0, Vector2(10.0, 50.0), Vector2(2.0, 3.0), 2, Color.WHITE, 4.0)
		for row in range(first, motes.next_row()):
			var land: Vector3 = motes.mote_land(row)
			check(land.z != INF, "row %d rests in its life" % row)
			lands.append(land)
	var stamped: Array[Vector3] = _stamped_over_time(marks)
	check_equal(stamped.size(), lands.size(), "one speck a mote")
	for land in lands:
		var match_land: bool = false
		for at in stamped:
			if Vector2(at.x, at.y) == Vector2(land.x, land.y).floor() and at.z >= land.z and at.z <= land.z + MarksScript.SETTLE_SLOT + 1.0 / 60.0 + 0.0001:
				match_land = true
		check(match_land, "a speck where the mote rests (%s), once it does" % land)


## A trail's motes settle as any other's (one rule: a kind that settles leaves its mark however it
## was thrown), so a frost bolt's trail leaves specks where its flecks come to rest.
func test_a_trails_settling_motes_leave_their_marks() -> void:
	var fleck: MoteKind = registry.get_resource(&"motes", &"fleck") as MoteKind
	check_equal(fleck.settles, &"speck", "frost's flecks settle")
	var pair: Array = _settling_pair([fleck] as Array[MoteKind])
	var motes: MotesScript = pair[0]
	var marks: MarksScript = pair[1]
	var given := PackedFloat32Array()
	given.resize(4 * MotesScript.BIRTH_STRIDE)
	for n in 4:
		var b: int = n * MotesScript.BIRTH_STRIDE
		given[b + ProjectilesScript.SPARK_X] = 100.0 + 40.0 * n
		given[b + ProjectilesScript.SPARK_Y] = 120.0
		given[b + ProjectilesScript.SPARK_BACK_X] = -1.0
		given[b + ProjectilesScript.SPARK_KIND] = float(fleck.look_layers[0])
		given[b + ProjectilesScript.SPARK_LOOK] = float(FROST_LOOK)
		given[b + ProjectilesScript.SPARK_CORE] = 0.6
		given[b + ProjectilesScript.SPARK_CORE + 1] = 0.8
		given[b + ProjectilesScript.SPARK_CORE + 2] = 1.0
	motes.give_off(given, 4)
	var resting: int = 0
	for row in 4:
		if motes.mote_land(row).z != INF:
			resting += 1
	check(resting > 0, "the flecks come to rest in their lives: %d" % resting)
	check_equal(marks.settling(), resting, "and each waits to leave its speck")
	check_equal(_stamped_over_time(marks).size(), resting, "then leaves it")


## A mote the ring writes over before it rests leaves no mark (on the web's small ring a storm
## wraps it in under half a second): its settle carries its serial, and the motes tell the layer
## which are gone.
func test_a_mote_written_over_before_it_rests_leaves_no_mark() -> void:
	var marks: MarksScript = _layer([_kind(&"speck")])
	marks.step(0.0)
	marks.settle(0, Vector2(10.0, 10.0), 0.2, 2, Color.WHITE, 5)
	marks.settle(0, Vector2(12.0, 10.0), 0.2, 2, Color.WHITE, 12)
	marks.settle(0, Vector2(14.0, 10.0), 0.2, 2, Color.WHITE)
	marks.forget_settles_before(10)
	marks.settle_due(0.5)
	check_equal(marks.pending(), 2, "the overwritten one fades; a later one and one with no serial are stamped")
	check_equal(marks.settles_faded, 1, "counted as faded")

	var chip: MoteKind = registry.get_resource(&"motes", &"chip") as MoteKind
	var ember: MoteKind = registry.get_resource(&"motes", &"ember") as MoteKind
	var speck := _kind(&"speck")
	speck.form = "speck"
	var layer: MarksScript = _layer([speck])
	var small: MotesScript = own(MotesScript.new(MotesScript.CHUNK, 0, [chip, ember] as Array[MoteKind])) as MotesScript
	root.add_child(small)
	small.settle_into(layer)
	small.step(0.0)
	layer.step(0.0)
	small.burst(0, Vector2(200.0, 150.0), Vector2.RIGHT, 8, chip.speed, chip.spread, chip.up, chip.life, 2, Color.WHITE, chip.height)
	check_equal(layer.settling(), 8, "eight chips wait to settle")
	# The ring (one chunk) is written over by embers before the chips rest.
	var t: float = 0.0
	for frame in 5:
		t += 1.0 / 60.0
		small.step(t)
		small.burst(1, Vector2(400.0, 150.0), Vector2.RIGHT, 250, ember.speed, ember.spread, ember.up, ember.life, 2, Color.WHITE, ember.height)
	small.step(t)
	check_equal(_stamped_over_time(layer).size(), 0, "none of the written-over chips leaves a speck")
