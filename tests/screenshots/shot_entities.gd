extends SceneTree
## Screenshots of the entity kit (staffs B5), for people and for Claude to look at (not a test:
## it only checks that each staged state happened): each of four wizards with a decoy beside it
## and two familiars circling it (`entities_four_players`), and the same crop at 4x
## (`entities_4x`). The entities are asked for with the real events, as core/spells will.
## Needs a display, so it runs only through `ci/build/build.sh --quick --screenshots`; each
## shot is saved as user://screenshots/<name>.png and copied to build/screenshots/.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 20
const TAG: int = 1 << 20


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await _settle()
	var input: Node = root.get_node_or_null("PlayerInput")
	var flow: Node = root.get_node_or_null("Flow")
	var events: Node = root.get_node_or_null("Events")
	var entities: Node = root.get_node_or_null("Entities")
	if input == null or flow == null or events == null or entities == null:
		_fail("the PlayerInput, Flow, Events and Entities autoloads must exist")
		return
	for index in 4:
		input.call("add_virtual_device", index)
	flow.call("start_run", 0)
	for i in 4:
		await _settle()
	var centre: Vector2 = Vector2.ZERO
	for index in 4:
		var wizard: Node2D = flow.call("get_wizard", index) as Node2D
		wizard.global_position = Vector2(220.0 + 60.0 * float(index), 190.0)
		centre += wizard.global_position / 4.0
	await _settle()
	for index in 4:
		var wizard: Node2D = flow.call("get_wizard", index) as Node2D
		var at: Vector2 = wizard.global_position
		events.call("emit_signal", "entity_spawn_requested", index, &"decoy", at + Vector2(0.0, 40.0), 30.0, TAG + index)
		events.call("emit_signal", "entity_spawn_requested", index, &"familiar", at + Vector2(20.0, -14.0), 30.0, TAG + index)
		events.call("emit_signal", "entity_spawn_requested", index, &"familiar", at + Vector2(-20.0, -14.0), 30.0, TAG + index)
	await _settle()
	if int(entities.call("count")) != 12:
		_fail("there are %d entities, not 12, in entities_four_players" % int(entities.call("count")))
		return
	await _snap(centre + Vector2(0.0, 10.0), "entities_four_players", 1, Vector2i(160, 60))
	await _snap(centre + Vector2(-60.0, 10.0), "entities_4x", 4, Vector2i(40, 40))
	flow.call("stop_run")
	await create_timer(0.3).timeout
	quit(0)


## Save a crop of `half` × 2 pixels round the world point `at`, `zoom` times bigger.
func _snap(at: Vector2, shot_name: String, zoom: int, half: Vector2i) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var scale_to_image: Vector2 = Vector2(image.get_size()) / Vector2(root.get_visible_rect().size)
	var middle: Vector2i = Vector2i((root.get_canvas_transform() * at) * scale_to_image)
	var corner: Vector2i = (middle - half).clamp(Vector2i.ZERO, image.get_size() - half * 2)
	var crop: Image = image.get_region(Rect2i(corner, half * 2))
	if zoom != 1:
		crop.resize(crop.get_width() * zoom, crop.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s.png" % [SHOTS_DIR, shot_name])
	print("SHOT: %s" % shot_name)


func _fail(message: String) -> void:
	printerr("SHOT FAILED: " + message)
	quit(1)


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame
