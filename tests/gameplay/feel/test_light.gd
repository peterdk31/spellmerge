extends "res://tests/support/suite.gd"
## Spell light (gameplay/feel/spell_light.gd; docs/milestones/spell-spectacle.md, P3a, P3b): a
## light buffer the projectile batches, Feel's flashes, the live beams and the room's light spots
## draw into, and a rect that applies it to the world. Its batches mirror the manager's (each is
## handed the rows the batch uploads; nothing is written twice), every shot lights (the enemies'
## too), Feel hands its flash rows and beam paths over, a torch is a light spot coloured by its
## art, a room sets the ambient, the steps are a switch, the rect sits above every body and under
## every spell, flash and telegraph, the buffer follows the view at a quarter of its size, the
## shaders are warmed, and with the "Spell light" setting off no node of it exists. How it looks is
## checked by eye (tests/screenshots/shot_spell_light.gd): headless runs draw nothing.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const EntitiesScript := preload("res://gameplay/ai/entities.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const TORCH := preload("res://content/rooms/crypt/decals/torch.tscn")
const SANDBOX := preload("res://content/rooms/crypt/sandbox.tres")
const ARENA := preload("res://content/rooms/crypt/arena_01.tres")

## The scenes with bodies and room art: everything in them is drawn under the light.
const BODY_SCENES: Array[PackedScene] = [
	preload("res://content/wizard/base/wizard.tscn"),
	preload("res://content/enemies/training_dummy/training_dummy.tscn"),
	preload("res://content/enemies/bone_husk/bone_husk.tscn"),
	preload("res://content/rooms/crypt/arena_01.tscn"),
	preload("res://content/rooms/crypt/sandbox.tscn"),
	preload("res://content/rooms/crypt/decals/torch.tscn"),
]

var registry: RegistryScript


func before_each() -> void:
	registry = own(RegistryScript.new()) as RegistryScript
	registry.scan()


## A Feel with its own bus and a projectile manager in the tree. Returns [bus, feel, manager].
func _feel() -> Array:
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
	return [bus, feel, manager]


## The z a canvas item is drawn at: its own, plus its parents' while it is relative to them.
func _drawn_z(item: CanvasItem) -> int:
	var z: int = item.z_index
	var node: Node = item
	while (node as CanvasItem) != null and (node as CanvasItem).z_as_relative:
		node = node.get_parent()
		if node is CanvasItem:
			z += (node as CanvasItem).z_index
		else:
			break
	return z


## Every canvas item that draws under `node` (itself too; a bare Node2D or Node holder draws
## nothing), not inside a SubViewport (drawn elsewhere).
func _items(node: Node, into: Array[CanvasItem]) -> void:
	if node is CanvasItem and node.get_class() != "Node2D":
		into.append(node as CanvasItem)
	for child: Node in node.get_children():
		if not child is SubViewport:
			_items(child, into)


func test_the_setting_is_on_by_default_and_makes_the_light() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	check(SpellLightSetting.default_on(), "spell light is on by default on the desktop")
	var light: SpellLightScript = feel.light()
	check(light != null and feel.is_ancestor_of(light), "Feel makes the light (its spectacle)")
	check(light.viewport != null and light.apply != null, "a light buffer and the rect that applies it")
	check_equal(light.batches.size(), feel.projectiles.batch_count(), "one light batch per projectile batch, the card bodies' too")


func test_off_leaves_no_nodes_and_on_makes_them_again() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var manager: ProjectilesScript = made[2]
	bus.spell_light_changed.emit(false)
	check(feel.light() == null and not feel.spell_light, "off: no light")
	var found: Array[CanvasItem] = []
	_items(feel, found)
	var viewports: int = 0
	for child: Node in feel.find_children("*", "SubViewport", true, false):
		if not child.is_queued_for_deletion():
			viewports += 1
	check_equal(viewports, 0, "off: no light buffer under Feel")
	for item in found:
		check(item.material == null or (item.material as ShaderMaterial) == null or (item.material as ShaderMaterial).shader != SpellLightScript.APPLY_SHADER, "off: no apply rect")
	for batch in manager.batch_count():
		check(manager.batch_mirror(batch) == null, "off: batch %d mirrored by nothing" % batch)
	bus.spell_light_changed.emit(true)
	check(feel.light() != null and feel.spell_light, "on again: the light is back")
	check(manager.batch_mirror(0) == feel.light().batches[0].multimesh, "and mirrors the batches again")


func test_the_light_batches_get_the_rows_the_batches_upload() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	var manager: ProjectilesScript = made[2]
	var light: SpellLightScript = feel.light()
	for i in 5:
		manager.spawn(0, Vector2(100.0 + 10.0 * i, 100.0), Vector2(60.0, 0.0), 2.0)
	manager.step(1.0 / 60.0)
	manager.update_draw(1.0)
	var drawn: int = 0
	for batch in manager.batch_count():
		var source: MultiMesh = manager._nodes[batch].multimesh
		var mirror: MultiMesh = manager.batch_mirror(batch)
		check(mirror == light.batches[batch].multimesh, "batch %d is mirrored by its light batch" % batch)
		check(mirror != source and mirror.mesh is QuadMesh, "batch %d: the light draws a quad of its own, not the shots' mesh" % batch)
		check_equal(mirror.instance_count, source.instance_count, "batch %d: as many rows" % batch)
		check_equal(mirror.visible_instance_count, source.visible_instance_count, "batch %d: as many drawn" % batch)
		check(mirror.buffer == source.buffer, "batch %d: the same rows" % batch)
		drawn += mirror.visible_instance_count
	check(drawn >= 5, "the live shots are in the light batches, got %d" % drawn)


func test_the_light_is_applied_above_the_bodies_and_under_every_spell() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	var manager: ProjectilesScript = made[2]
	var light: SpellLightScript = feel.light()
	var at: int = _drawn_z(light.apply)
	check_equal(at, FeelScript.LIGHT_Z, "the rect is at LIGHT_Z")
	# Every body and the room's art under it.
	for scene in BODY_SCENES:
		var body: Node = scene.instantiate()
		var items: Array[CanvasItem] = []
		_items(body, items)
		for item in items:
			check(_drawn_z(item) < at, "%s/%s (z %d) is under the light" % [scene.resource_path, body.get_path_to(item), _drawn_z(item)])
		body.free()
	# Every other thing Feel draws, the shots and the entities over it.
	var feel_items: Array[CanvasItem] = []
	_items(feel, feel_items)
	for item in feel_items:
		# The floor flashes lie under the bodies, so under the light (checked below).
		if item != feel and item != light.apply and item != feel._floor_node:
			check(_drawn_z(item) > at, "Feel's %s (z %d) is over the light" % [feel.get_path_to(item), _drawn_z(item)])
	var shot_items: Array[CanvasItem] = []
	_items(manager, shot_items)
	for item in shot_items:
		if item != manager:
			check(_drawn_z(item) > at, "the shots' %s (z %d) are over the light" % [manager.get_path_to(item), _drawn_z(item)])
	check(EntitiesScript.DRAW_Z > at, "the entities are over the light")
	check(FeelScript.MOTE_Z > at and FeelScript.SHOWN_BEAM_Z > at and FeelScript.FLASH_Z > at, "motes, beams and flashes are over the light")
	# The floor flashes lie on the floor under the bodies (owner, 2026-11-08), so under the light
	# with the floor marks: lit by it, as the slam's cue lights its own strike (its `light` part).
	check(FeelScript.FLOOR_Z < at and FeelScript.FLOOR_Z == FeelScript.MARK_Z, "floor flashes lie with the floor marks, lit by the light")


func test_the_buffer_follows_the_view_at_a_quarter_size() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	var light: SpellLightScript = feel.light()
	var view: Viewport = light.get_viewport()
	var before: Transform2D = view.canvas_transform
	view.canvas_transform = Transform2D(0.0, Vector2(2.0, 2.0), 0.0, Vector2(-100.0, -40.0))
	light.follow()
	var size: Vector2 = view.get_visible_rect().size
	var wanted := Vector2i(ceili(size.x / SpellLightScript.DOWNSCALE), ceili(size.y / SpellLightScript.DOWNSCALE))
	check_equal(light.viewport.size, wanted, "the buffer is a quarter of the view each way")
	var world := Vector2(300.0, 200.0)
	var on_screen: Vector2 = view.global_canvas_transform * view.canvas_transform * world
	var in_buffer: Vector2 = light.viewport.canvas_transform * world
	var scale := Vector2(float(wanted.x) / size.x, float(wanted.y) / size.y)
	check(in_buffer.is_equal_approx(on_screen * scale), "a point lands where it is on screen, scaled: %s against %s" % [in_buffer, on_screen * scale])
	view.canvas_transform = before


func test_both_shaders_are_warmed_and_the_rect_reads_the_buffer() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	var light: SpellLightScript = feel.light()
	var warmed: Array[Shader] = ShaderWarmupScript.shaders()
	check(warmed.has(SpellLightScript.LIGHT_SHADER), "the light shader is warmed")
	check(warmed.has(SpellLightScript.APPLY_SHADER), "the apply shader is warmed")
	var shade: ShaderMaterial = light.apply.material as ShaderMaterial
	check(shade.get_shader_parameter(&"light_buffer") is ViewportTexture, "the rect reads the light buffer")
	var ambient: Variant = shade.get_shader_parameter(&"ambient")
	check(ambient == null or is_equal_approx(float(ambient), 1.0), "the ambient is 1.0 with no room: the room as it is")
	for batch in light.batches.size():
		var material: ShaderMaterial = light.batches[batch].material as ShaderMaterial
		check(material.shader == SpellLightScript.LIGHT_SHADER, "batch %d draws its light" % batch)
		var rows: int = SpellLightScript.ROWS_RUNE if light._projectiles.batch_mesh(batch) == ProjectilesScript.MESH_QUAD else SpellLightScript.ROWS_SHOT
		check_equal(int(material.get_shader_parameter(&"rows")), rows, "batch %d reads its rows as %s" % [batch, "runes" if rows == SpellLightScript.ROWS_RUNE else "shots"])
	check(warmed.has(SpellLightScript.BEAM_SHADER), "the beam light shader is warmed")


## The shader's ROWS_* and its row-reading constants are the script's and Feel's.
func test_the_light_shader_reads_rows_as_the_script_says() -> void:
	var code: String = SpellLightScript.LIGHT_SHADER.code
	for pair: Array in [["ROWS_SHOT", SpellLightScript.ROWS_SHOT], ["ROWS_RUNE", SpellLightScript.ROWS_RUNE], ["ROWS_FLASH", SpellLightScript.ROWS_FLASH], ["ROWS_SPOT", SpellLightScript.ROWS_SPOT], ["ROWS_CUE", SpellLightScript.ROWS_CUE]]:
		check(code.contains("const int %s = %d;" % [pair[0], pair[1]]), "the shader's %s is %d" % pair)
	check(code.contains("const float FLASH_FROM = %s;" % str(FeelScript.FLASH_FROM)), "the shader's FLASH_FROM is Feel's")
	check(code.contains("const float FLASH_SPAN = %s;" % str(FeelScript.FLASH_SPAN)), "the shader's FLASH_SPAN is Feel's")
	check(SpellLightScript.BEAM_SHADER.code.contains("const int BEAM_POINTS = %d;" % SpellLightScript.BEAM_POINTS), "the beam light's BEAM_POINTS")
	check_equal(SpellLightScript.BEAM_POINTS, FeelScript.LIVE_BEAM_POINTS, "a beam's light holds every point of a live beam")
	check_equal(SpellLightScript.STRIDE, FeelScript.FLASH_STRIDE, "a flash row is a light row")


## Which flashes light is data (`FlashKind.room_light`): the flares, rings, casts, hits, puffs, the
## poof, lightning and the explosions light; the columns and the cracks do not. Feel writes each
## flash's light into its row (the transform's second unused float), which the light reads.
func test_each_flash_kinds_light_is_its_files() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	for id: StringName in [&"burst", &"ring_out", &"ring_in", &"rune_burst", &"cast", &"spray", &"puff", &"poof", &"arc", &"shell", &"fireball"]:
		check(feel.flash_kind(id) != null and feel.flash_kind(id).room_light > 0.0, "%s lights" % id)
	for id: StringName in [&"rise", &"fall", &"quake"]:
		check(feel.flash_kind(id) != null and feel.flash_kind(id).room_light == 0.0, "%s does not" % id)
	feel.show_flash(&"burst", Vector2(100.0, 100.0), Vector2.RIGHT, Color.WHITE, 0, 0, 2, 0.5)
	feel._process(1.0 / 60.0)
	check_equal(feel.flash_info(&"burst")["light"], 1.0, "a burst lights 1.0 (its file)")
	check(is_equal_approx(feel.light().flashes[SpellLightScript.FLASHES_FLARE].multimesh.buffer[6], 1.0), "and its row says so")
	check(SpellLightScript.LIGHT_SHADER.code.contains("MODEL_MATRIX[2].y"), "where the light reads it")


## Feel's flashes light: the light's flash batches draw the rows Feel just uploaded.
func test_feels_flashes_are_handed_to_the_light() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	var light: SpellLightScript = feel.light()
	feel.show_flash(&"burst", Vector2(100.0, 100.0), Vector2.RIGHT, Color.WHITE, 0, 0, 2, 0.5)
	feel.show_flash(&"shell", Vector2(200.0, 100.0), Vector2.RIGHT, Color.WHITE, 0, 0, 6, 0.5)
	feel.show_flash(&"arc", Vector2(300.0, 100.0), Vector2.RIGHT, Color.WHITE, 0, 0, 1, 0.5, 40.0)
	feel._process(1.0 / 60.0)
	for kind: int in [SpellLightScript.FLASHES_FLARE, SpellLightScript.FLASHES_BLAST, SpellLightScript.FLASHES_ARC]:
		var multimesh: MultiMesh = light.flashes[kind].multimesh
		check_equal(multimesh.visible_instance_count, 1, "flash batch %d lights its one flash" % kind)
		check_equal(multimesh.instance_count, feel.effect_slots, "as many rows as Feel's slots")
		check_equal(int((light.flashes[kind].material as ShaderMaterial).get_shader_parameter(&"rows")), SpellLightScript.ROWS_FLASH, "read as flash rows")
	var row: PackedFloat32Array = light.flashes[SpellLightScript.FLASHES_FLARE].multimesh.buffer
	check(is_equal_approx(row[3], 100.0) and is_equal_approx(row[7], 100.0), "the burst's row is Feel's: where it is")
	feel._process(1.0)
	check_equal(light.flashes[SpellLightScript.FLASHES_FLARE].multimesh.visible_instance_count, 0, "a flash that ended no longer lights")


## A cue's `light` part (S6, item 4) lights round its point in its colour for its seconds, fading;
## and a cue with one lights by it alone: its flashes' rows light 0, while another cue's flashes
## light by their kinds as before.
func test_a_cues_light_part_lights_and_its_flashes_do_not() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	var light: SpellLightScript = feel.light()
	var heal: CueBase = feel.cue_of(&"heal")
	check(heal != null and heal.lights(), "the heal lights by its own light part")
	feel.play_cue(&"heal", 0, Vector2(100.0, 50.0))
	feel._process(1.0 / 60.0)
	check_equal(light.cue_light_count(), 1, "one cue light")
	var rows: PackedFloat32Array = light.cue_lights.multimesh.buffer
	check(is_equal_approx(rows[3], 100.0) and is_equal_approx(rows[7], 50.0), "at the cue's point")
	check(is_equal_approx(rows[0], 44.0) and is_equal_approx(rows[5], 44.0), "out to its radius")
	check(rows[15] > 0.9 and rows[15] <= 1.0, "as bright as it says, fading: %f" % rows[15])
	check(is_equal_approx(rows[12], 0.4196078), "in its exact colour")
	check(not feel.flash_info(&"ring_out").is_empty(), "its ring is a flare row")
	check_equal(light.flashes[SpellLightScript.FLASHES_FLARE].multimesh.buffer[6], 0.0, "unlit: its row lights 0")
	feel._process(1.0)
	check_equal(light.cue_light_count(), 0, "gone after its seconds")
	feel.play_cue(&"possess_start", 0, Vector2(100.0, 50.0))
	feel._process(1.0 / 60.0)
	check_equal(light.cue_light_count(), 0, "a cue with no light part makes no cue light")
	check(not feel.flash_info(&"ring_in").is_empty(), "its ring")
	check(is_equal_approx(light.flashes[SpellLightScript.FLASHES_FLARE].multimesh.buffer[6], feel.flash_kind(&"ring_in").room_light), "lights by its kind, as before")


## The cue lights' rows are the spell light's own: a new one past CUE_LIGHTS takes the oldest's
## place, and with the setting off a light part does nothing.
func test_cue_lights_are_bounded_and_off_with_the_setting() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	var light: SpellLightScript = feel.light()
	for i in SpellLightScript.CUE_LIGHTS + 5:
		light.flash(Vector2(i, 0.0), 20.0, 1.0, 5.0, Color.WHITE, 0, 0, 0.0)
	light.step_cues(0.1)
	check_equal(light.cue_light_count(), SpellLightScript.CUE_LIGHTS, "at most CUE_LIGHTS")
	light.flash(Vector2.ZERO, 0.0, 1.0, 5.0, Color.WHITE, 0, 0, 0.0)
	light.flash(Vector2.ZERO, 20.0, 0.0, 5.0, Color.WHITE, 0, 0, 0.0)
	light.step_cues(0.1)
	check_equal(light.cue_light_count(), SpellLightScript.CUE_LIGHTS, "no reach or no strength lights nothing")
	feel.set_spell_light(false)
	feel.play_cue(&"heal", 0, Vector2(100.0, 50.0))
	feel._process(1.0 / 60.0)
	check(feel.light() == null, "no light with the setting off, and the light part plays nothing")


## A live beam lights along the path Feel gives its shader; a beam that is gone does not.
func test_a_beam_lights_along_its_path() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	var light: SpellLightScript = feel.light()
	var path := PackedVector3Array()
	path.resize(SpellLightScript.BEAM_POINTS)
	path[0] = Vector3(10.0, 20.0, 0.0)
	path[1] = Vector3(110.0, 20.0, 100.0)
	path[2] = Vector3(110.0, 70.0, 150.0)
	light.light_beams_begin()
	light.light_beam(1, path, 3, 2, 0, Color(0.9, 0.5, 0.1), 0.5)
	check_equal(light.beams.size(), 2, "a light per beam slot")
	var beam: MeshInstance2D = light.beams[1]
	check(beam.visible and beam.get_parent() == light.viewport, "drawn into the light buffer")
	var shade: ShaderMaterial = beam.material as ShaderMaterial
	check(shade.shader == SpellLightScript.BEAM_SHADER, "by the beam light shader")
	check(shade.get_shader_parameter(&"beam_path") == path and int(shade.get_shader_parameter(&"beam_points")) == 3, "along the beam's own path")
	check_equal(int(shade.get_shader_parameter(&"beam_player")), 2, "in its caster's ramp")
	check(is_equal_approx(float(shade.get_shader_parameter(&"beam_fade")), 0.5), "fading as it fades")
	check((beam.mesh as ArrayMesh).custom_aabb.size.x >= 100000.0, "its mesh's box is the world: never culled")
	light.light_beams_begin()
	check(not beam.visible, "not lit until Feel lights it again")


## Every shot lights by one rule, an enemy's too: its row is in the light batch, a live head.
func test_an_enemy_shot_lights_like_any() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	var manager: ProjectilesScript = made[2]
	var enemy: int = ActorSeats.enemy(feel.actors as ActorSeats.ActorsScript)
	var slot: int = manager.spawn(enemy, Vector2(240.0, 160.0), Vector2(60.0, 0.0), 2.0, 4.0, ProjectilesScript.LAYER_PLAYER)
	check(slot >= 0, "an enemy shot")
	manager.step(1.0 / 60.0)
	manager.update_draw(1.0)
	var at: Vector2 = manager.get_position_of(slot)
	var found: bool = false
	for batch in manager.batch_count():
		var mirror: MultiMesh = manager.batch_mirror(batch)
		var buffer: PackedFloat32Array = mirror.buffer
		for n in mirror.visible_instance_count:
			var i: int = n * SpellLightScript.STRIDE
			if Vector2(buffer[i + 3], buffer[i + 7]).distance_to(at) < 2.0 and int(buffer[i + 5]) & ProjectilesScript.HEAD_LIVE != 0:
				found = true
	check(found, "the enemy shot's live head is in a light batch, so it lights")


## The regression (tails as motes, 2026-11-05): a shot drawn without a trail row (every shot, now
## its tail is motes) still lights; the light shader once lit only shots that held a row.
func test_a_shot_without_a_trail_row_lights() -> void:
	var made: Array = _feel()
	var manager: ProjectilesScript = made[2]
	var slot: int = manager.spawn(0, Vector2(200.0, 120.0), Vector2(60.0, 0.0), 2.0, 4.0)
	manager.step(1.0 / 60.0)
	manager.update_draw(1.0)
	check(slot >= 0, "a shot (with no trail row: its tail is motes)")
	var shader: String = (load("res://gameplay/feel/light.gdshader") as Shader).code
	check(not shader.contains("row >= 0.0 && flag_set(flags, HF_LIVE)"), "the light shader lights a head without a row")
	var at: Vector2 = manager.get_position_of(slot)
	var found: bool = false
	for batch in manager.batch_count():
		var mirror: MultiMesh = manager.batch_mirror(batch)
		var buffer: PackedFloat32Array = mirror.buffer
		for n in mirror.visible_instance_count:
			var i: int = n * SpellLightScript.STRIDE
			if Vector2(buffer[i + 3], buffer[i + 7]).distance_to(at) < 2.0 and int(buffer[i + 5]) & ProjectilesScript.HEAD_LIVE != 0:
				found = true
	check(found, "its head is in a light batch")


## A torch is a light spot (data on a plain node: rooms carry no scripts), lit in its flame's
## colour while it is in the tree, and gone with it.
func test_a_torch_lights_in_its_flames_colour() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	var light: SpellLightScript = feel.light()
	light.follow()
	check_equal(light.spot_count(), 0, "no spots with no room")
	var torch: Node2D = TORCH.instantiate() as Node2D
	torch.position = Vector2(64.0, 32.0)
	root.add_child(torch)
	light.follow()
	check_equal(light.spot_count(), 1, "the torch lights")
	var spot: Node = torch.get_tree().get_nodes_in_group(LightSpot.GROUP)[0]
	check_equal(LightSpot.problems(spot), PackedStringArray(), "the torch's spot is whole")
	var flame: AnimatedSprite2D = torch.get_node("Flame") as AnimatedSprite2D
	var colours: PackedColorArray = ArtPixels.colours_of(flame.sprite_frames.get_frame_texture(flame.animation, 0))
	check(not colours.is_empty() and LightSpot.colour_of(spot).is_equal_approx(colours[0]), "its colour is the flame art's lightest")
	var row: PackedFloat32Array = light.spots.multimesh.buffer
	check(Vector2(row[3], row[7]).is_equal_approx((spot as Node2D).global_position), "where its spot is")
	check(is_equal_approx(row[0], LightSpot.reach_of(spot)), "as far as its reach")
	check(Color(row[8], row[9], row[10]).is_equal_approx(colours[0]), "in the flame's colour")
	check(is_equal_approx(row[11], LightSpot.DEFAULT_STRENGTH), "at its strength")
	check_equal(int((light.spots.material as ShaderMaterial).get_shader_parameter(&"rows")), SpellLightScript.ROWS_SPOT, "read as spots")
	torch.free()
	light.follow()
	check_equal(light.spot_count(), 0, "a torch gone lights no more")


## S6 item 12: a torch's painted glow (its sprites in `LightSpot.PAINTED`) is hidden while Spell
## light draws its spot's light, whether the torch was there first or came after, and shown again
## when the setting is off; its flame stays.
func test_a_torchs_painted_glow_is_hidden_while_spell_light_is_on() -> void:
	# The game's own Feel (the autoload) lights the whole tree too: off for this test.
	var game_feel: Node = root.get_node_or_null(^"Feel")
	var game_light: bool = game_feel != null and bool(game_feel.get("spell_light"))
	if game_light:
		game_feel.call("set_spell_light", false)
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	bus.spell_light_changed.emit(false)
	var first: Node2D = TORCH.instantiate() as Node2D
	root.add_child(first)
	var painted: Array[CanvasItem] = [first.get_node("Glow") as CanvasItem, first.get_node("Core") as CanvasItem]
	for item in painted:
		check(item.is_in_group(LightSpot.PAINTED) and item.visible, "%s: painted light, shown with Spell light off" % item.name)
	bus.spell_light_changed.emit(true)
	for item in painted:
		check(not item.visible, "%s: hidden with Spell light on" % item.name)
	check((first.get_node("Flame") as CanvasItem).visible and (first.get_node("Bracket") as CanvasItem).visible, "the flame and bracket stay")
	var later: Node2D = TORCH.instantiate() as Node2D
	root.add_child(later)
	check(not (later.get_node("Glow") as CanvasItem).visible and not (later.get_node("Core") as CanvasItem).visible, "a torch that comes while it is on: hidden too")
	bus.spell_light_changed.emit(false)
	for item: CanvasItem in painted + [later.get_node("Glow") as CanvasItem, later.get_node("Core") as CanvasItem]:
		check(item.visible, "%s: shown again with Spell light off" % item.get_path())
	first.free()
	later.free()
	if game_light:
		game_feel.call("set_spell_light", true)


## A spot's numbers are its metadata; a tint stands in for its art; broken data is named.
func test_a_light_spots_data_is_read_and_checked() -> void:
	var spot := Marker2D.new()
	spot.add_to_group(LightSpot.GROUP)
	check(not LightSpot.problems(spot).is_empty(), "no art and no tint is a problem")
	spot.set_meta(LightSpot.TINT, Color(0.2, 0.4, 1.0))
	spot.set_meta(LightSpot.REACH, 80.0)
	check_equal(LightSpot.problems(spot), PackedStringArray(), "a tint is enough")
	check(LightSpot.colour_of(spot).is_equal_approx(Color(0.2, 0.4, 1.0)), "the tint's colour")
	check(is_equal_approx(LightSpot.reach_of(spot), 80.0) and is_equal_approx(LightSpot.flicker_of(spot), LightSpot.DEFAULT_FLICKER), "its reach, and the default flicker")
	spot.set_meta(LightSpot.STRENGTH, 3.0)
	check(not LightSpot.problems(spot).is_empty(), "a strength past 1 is a problem")
	spot.free()


## Every light spot in the rooms' and decals' scenes is whole.
func test_every_light_spot_in_the_content_is_whole() -> void:
	var seen: int = 0
	for path: String in ["res://content/rooms/crypt/arena_01.tscn", "res://content/rooms/crypt/sandbox.tscn", "res://content/rooms/crypt/decals/torch.tscn"]:
		var scene: Node = (load(path) as PackedScene).instantiate()
		for node: Node in scene.find_children("*", "", true, false):
			if node.is_in_group(LightSpot.GROUP):
				seen += 1
				check_equal(LightSpot.problems(node), PackedStringArray(), "%s: %s" % [path, scene.get_path_to(node)])
		scene.free()
	check(seen >= 5, "the torches are light spots, got %d" % seen)


## A room sets the light's ambient (the sandbox's 0.85, the owner's pick; others 1.0), and the
## light keeps it when the setting is turned off and on.
func test_a_room_sets_the_ambient() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	check(is_equal_approx(ARENA.ambient, 1.0), "a room is as drawn by default")
	check(is_equal_approx(SANDBOX.ambient, 0.85), "the sandbox is a little darker (the owner, 2026-11-04)")
	bus.room_entered.emit(SANDBOX.id)
	check(is_equal_approx(feel.light().ambient, 0.85), "the sandbox's ambient")
	check(is_equal_approx(float((feel.light().apply.material as ShaderMaterial).get_shader_parameter(&"ambient")), 0.85), "to the rect")
	bus.spell_light_changed.emit(false)
	bus.spell_light_changed.emit(true)
	check(is_equal_approx(feel.light().ambient, 0.85), "kept through the setting")
	bus.room_entered.emit(ARENA.id)
	check(is_equal_approx(feel.light().ambient, 1.0), "the arena's")


## The steps are a switch: 3 by default (dim, lit, bright), 0 smooth; the shader's default too.
func test_the_steps_are_a_switch() -> void:
	var made: Array = _feel()
	var light: SpellLightScript = (made[1] as FeelScript).light()
	var shade: ShaderMaterial = light.apply.material as ShaderMaterial
	check_equal(light.bands, 3, "three steps by default")
	check_equal(int(shade.get_shader_parameter(&"bands")), 3, "to the rect")
	check(SpellLightScript.APPLY_SHADER.code.contains("uniform int bands = %d;" % SpellLightScript.DEFAULT_BANDS), "the shader's default is the script's")
	light.set_bands(0)
	check_equal(int(shade.get_shader_parameter(&"bands")), 0, "smooth")
	light.set_bands(1)
	check_equal(light.bands, 2, "at least one step past dim")


## A card's light (docs/milestones/card-looks.md, phase 1b): each shot's row carries its card's
## light reach and intensity (`set_looks`, `set_light`; 1 for a plain shot) in its free floats, a
## head's and a rune's alike, and the light shader multiplies its reach and brightness by them.
func test_a_shots_row_carries_its_cards_light() -> void:
	var made: Array = _feel()
	var manager: ProjectilesScript = made[2]
	var plain: int = manager.spawn(0, Vector2(120.0, 100.0), Vector2(60.0, 0.0), 2.0, 4.0)
	var dim: int = manager.spawn(0, Vector2(120.0, 160.0), Vector2(60.0, 0.0), 2.0, 4.0)
	var rune: int = manager.spawn(0, Vector2(300.0, 160.0), Vector2.ZERO, 2.0, 6.0, ProjectilesScript.LAYER_ENEMY, 0, 0, ProjectilesScript.MOTION_STILL)
	var launch := LaunchLook.new()
	launch.carrier_card = &"atom"
	launch.light_intensity = 0.5
	launch.light_reach = 0.75
	manager.set_looks(PackedInt32Array([dim]), 1, launch)
	check(manager.set_light(rune, 1.5, 2.0), "a rune's light set")
	check(not manager.set_light(-1, 1.0, 1.0), "not an empty slot")
	manager.step(1.0 / 60.0)
	manager.update_draw(1.0)
	var rows: Dictionary = {}
	for batch in manager.batch_count():
		var mirror: MultiMesh = manager.batch_mirror(batch)
		var buffer: PackedFloat32Array = mirror.buffer
		for n in mirror.visible_instance_count:
			var i: int = n * SpellLightScript.STRIDE
			for slot: int in [plain, dim, rune]:
				var at: Vector2 = manager.get_position_of(slot)
				if Vector2(buffer[i + 3], buffer[i + 7]).distance_to(at) < 4.0:
					rows[slot] = Vector2(buffer[i + ProjectilesScript.LIGHT_REACH_FLOAT], buffer[i + ProjectilesScript.LIGHT_INTENSITY_FLOAT])
	check_equal(rows.get(plain), Vector2(1.0, 1.0), "a plain shot lights as before")
	check_equal(rows.get(dim), Vector2(0.75, 0.5), "a dimmer card's head: its reach and intensity")
	check_equal(rows.get(rune), Vector2(2.0, 1.5), "a rune's quad carries them too")
	var bounded: int = manager.spawn(0, Vector2(400.0, 100.0), Vector2(60.0, 0.0), 2.0, 4.0)
	manager.set_light(bounded, 9.0, 0.0)
	check(is_equal_approx(manager._look_light_intensity[bounded], ProjectilesScript.LIGHT_MAX) and is_equal_approx(manager._look_light_reach[bounded], ProjectilesScript.LIGHT_REACH_MIN), "kept in bounds")
	var code: String = (load("res://gameplay/feel/light.gdshader") as Shader).code
	# The shader names the row's floats once: MODEL_MATRIX[2].x is a row's float 2, .y its float 6.
	check_equal(ProjectilesScript.LIGHT_REACH_FLOAT, 2, "the reach is the row's float 2")
	check_equal(ProjectilesScript.LIGHT_INTENSITY_FLOAT, 6, "the intensity its float 6")
	check(code.contains("#define LIGHT_REACH MODEL_MATRIX[2].x") and code.contains("#define LIGHT_INTENSITY MODEL_MATRIX[2].y"), "which the light shader reads as LIGHT_REACH and LIGHT_INTENSITY")
	check(code.contains("RUNE_REACH * LIGHT_REACH") and code.contains("rune_strength * LIGHT_INTENSITY"), "a rune's light: its reach and brightness times the row's")
	check(code.contains("half_size = vec2(reach * LIGHT_REACH)") and code.contains("shot_strength * LIGHT_INTENSITY"), "a head's light too")


## A beam card's light (card-looks phase 1b, 2): a beam's light is BEAM_STRENGTH times its card's
## `look_light_intensity` bright and BEAM_REACH times its `look_light_reach` wide, 1 as any beam.
func test_a_beams_light_follows_its_cards_light() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	var light: SpellLightScript = feel.light()
	var path := PackedVector3Array()
	path.resize(SpellLightScript.BEAM_POINTS)
	path[0] = Vector3(10.0, 20.0, 0.0)
	path[1] = Vector3(110.0, 20.0, 100.0)
	light.light_beams_begin()
	light.light_beam(0, path, 2, 0, 0, Color.WHITE, 1.0)
	light.light_beam(1, path, 2, 0, 0, Color.WHITE, 1.0, 0.5, 2.0)
	var plain: ShaderMaterial = light.beams[0].material as ShaderMaterial
	var card: ShaderMaterial = light.beams[1].material as ShaderMaterial
	check(is_equal_approx(float(plain.get_shader_parameter(&"beam_strength")), SpellLightScript.BEAM_STRENGTH) and is_equal_approx(float(plain.get_shader_parameter(&"beam_reach")), SpellLightScript.BEAM_REACH), "a plain beam lights as before")
	check(is_equal_approx(float(card.get_shader_parameter(&"beam_strength")), SpellLightScript.BEAM_STRENGTH * 0.5), "half as bright")
	check(is_equal_approx(float(card.get_shader_parameter(&"beam_reach")), SpellLightScript.BEAM_REACH * 2.0), "twice as wide")
