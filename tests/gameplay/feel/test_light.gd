extends "res://tests/support/suite.gd"
## Spell light (gameplay/feel/spell_light.gd; docs/milestones/spell-spectacle.md, P3a): a light
## buffer the projectile batches draw into again and a rect that applies it to the world. Its
## batches mirror the manager's (each is handed the rows the batch uploads; nothing is written
## twice), the rect sits above every body and under every spell, flash and telegraph, the buffer
## follows the view at a quarter of its size, both shaders are warmed, and with the "Spell light"
## setting off no node of it exists. How it looks is checked by eye
## (tests/screenshots/shot_spell_light.gd): headless runs draw nothing.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const EntitiesScript := preload("res://gameplay/ai/entities.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

## The scenes with bodies and room art: everything in them is drawn under the light.
const BODY_SCENES: Array[PackedScene] = [
	preload("res://content/wizard/base/wizard.tscn"),
	preload("res://content/enemies/training_dummy/training_dummy.tscn"),
	preload("res://content/enemies/bone_husk/bone_husk.tscn"),
	preload("res://content/rooms/crypt/arena_01.tscn"),
	preload("res://content/rooms/crypt/sandbox.tscn"),
	preload("res://content/rooms/horde/horde.tscn"),
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
	check(light != null and light.get_parent() == feel, "Feel makes the light")
	check(light.viewport != null and light.apply != null, "a light buffer and the rect that applies it")
	check_equal(light.batches.size(), ProjectilesScript.BATCHES, "one light batch per projectile batch")


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
	for batch in ProjectilesScript.BATCHES:
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
	for batch in ProjectilesScript.BATCHES:
		var source: MultiMesh = manager._nodes[batch].multimesh
		var mirror: MultiMesh = manager.batch_mirror(batch)
		check(mirror == light.batches[batch].multimesh, "batch %d is mirrored by its light batch" % batch)
		check(mirror != source and mirror.mesh is QuadMesh, "batch %d: the light draws a quad of its own, not the trails' mesh" % batch)
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
		if item != feel and item != light.apply:
			check(_drawn_z(item) > at, "Feel's %s (z %d) is over the light" % [feel.get_path_to(item), _drawn_z(item)])
	var shot_items: Array[CanvasItem] = []
	_items(manager, shot_items)
	for item in shot_items:
		if item != manager:
			check(_drawn_z(item) > at, "the shots' %s (z %d) are over the light" % [manager.get_path_to(item), _drawn_z(item)])
	check(EntitiesScript.DRAW_Z > at, "the entities are over the light")
	check(FeelScript.MOTE_Z > at and FeelScript.FLOOR_Z > at and FeelScript.FORM_Z > at and FeelScript.EFFECT_Z > at, "motes, floor flashes, beams and effects are over the light")


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
	check(ambient == null or is_equal_approx(float(ambient), 1.0), "the ambient is 1.0: the room as it is")
	for batch in ProjectilesScript.BATCHES:
		var material: ShaderMaterial = light.batches[batch].material as ShaderMaterial
		check(material.shader == SpellLightScript.LIGHT_SHADER, "batch %d draws its light" % batch)
		check(bool(material.get_shader_parameter(&"rune_rows")) == (ProjectilesScript.BATCH_MESH[batch] < 0), "batch %d reads its rows as %s" % [batch, "runes" if ProjectilesScript.BATCH_MESH[batch] < 0 else "trails"])
