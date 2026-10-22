extends SceneTree
## Screenshots of element reactions, for people and for Claude to look at: one reaction
## (`reaction_one`) and four at once, one per player (`reaction_four_players`). Needs a
## display, so it runs only through `ci/build/build.sh --quick --screenshots`; each shot is
## saved as user://screenshots/<name>.png and copied to build/screenshots/.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 20
const NAMES: Array[StringName] = [&"shatter", &"thaw", &"flare", &"rift"]


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await _settle()
	var input: Node = root.get_node_or_null("PlayerInput")
	var flow: Node = root.get_node_or_null("Flow")
	var events: Node = root.get_node_or_null("Events")
	if input == null or flow == null or events == null:
		printerr("SHOT FAILED: the PlayerInput, Flow and Events autoloads must exist")
		quit(1)
		return
	for index in 4:
		input.call("add_virtual_device", index)
	flow.call("start_run", 0)
	await _settle()
	var centre: Vector2 = (flow.call("get_wizard", 0) as Node2D).global_position + Vector2(0.0, -60.0)
	events.call("emit_signal", "reaction_triggered", 0, NAMES[0], centre)
	await _snap(centre, "reaction_one")
	await _settle()
	for player in 4:
		var at: Vector2 = centre + Vector2(float(player - 2) * 40.0 + 20.0, float(player % 2) * 14.0)
		events.call("emit_signal", "reaction_triggered", player, NAMES[player], at)
	await _snap(centre, "reaction_four_players")
	quit(0)


## Let the flashes grow for a few frames, then save a 4x crop around the world point `at`.
func _snap(at: Vector2, name: String) -> void:
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var scale_to_image: Vector2 = Vector2(image.get_size()) / Vector2(root.get_visible_rect().size)
	var centre: Vector2i = Vector2i((root.get_canvas_transform() * at) * scale_to_image)
	var half: Vector2i = Vector2i(96, 64)
	var corner: Vector2i = (centre - half).clamp(Vector2i.ZERO, image.get_size() - half * 2)
	var crop: Image = image.get_region(Rect2i(corner, half * 2))
	crop.resize(half.x * 8, half.y * 8, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s.png" % [SHOTS_DIR, name])
	print("SHOT: %s" % name)


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame
