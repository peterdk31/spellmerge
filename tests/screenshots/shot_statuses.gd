extends SceneTree
## Screenshots of enemy statuses (#244, part 3), for people and for Claude to look at: one ember
## imp each with burning, chill, freeze, shock, hex and static, in a row in the live game
## (`statuses_1x`, as a player sees them, and `statuses_4x`), then a reaction bursting over
## the row (`status_reaction_1x`). Needs a display, so it runs only through
## `ci/build/build.sh --quick --screenshots`; each shot is saved as
## user://screenshots/<name>.png and copied to build/screenshots/.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 20
const IMP_SCENE := preload("res://content/enemies/ember_imp/ember_imp.tscn")
const IDS: Array[StringName] = [&"burn", &"chill", &"freeze", &"shock", &"hex", &"static"]
## Pixels between neighbours in the row.
const GAP: float = 40.0
## Status seconds, long enough to outlast the shots.
const SECONDS: float = 20.0


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await _settle()
	var input: Node = root.get_node_or_null("PlayerInput")
	var flow: Node = root.get_node_or_null("Flow")
	var events: Node = root.get_node_or_null("Events")
	var combat: Node = root.get_node_or_null("Combat")
	if input == null or flow == null or events == null or combat == null:
		printerr("SHOT FAILED: the PlayerInput, Flow, Events and Combat autoloads must exist")
		quit(1)
		return
	input.call("add_virtual_device", 0)
	flow.call("start_run", 0)
	await _settle()
	var centre: Vector2 = (flow.call("get_wizard", 0) as Node2D).global_position + Vector2(0.0, -60.0)
	var imps: Array[Node2D] = []
	for i in IDS.size():
		var imp := Node2D.new()
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = load("res://content/enemies/ember_imp/idle.svg") as Texture2D
		sprite.hframes = 2
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		imp.add_child(sprite)
		root.add_child(imp)
		imp.global_position = centre + Vector2((float(i) - 2.5) * GAP, 0.0)
		combat.call("register_enemy", imp, 400, 10.0)
		imps.append(imp)
	for i in IDS.size():
		var id: StringName = IDS[i]
		if id == &"freeze":
			# Three chills in a row freeze.
			for k in 3:
				combat.call("apply_status", 0, imps[i], &"chill", SECONDS, 30.0)
		else:
			combat.call("apply_status", 0, imps[i], id, SECONDS, 5.0)
	await _snap(centre, "statuses_4x", 4)
	await _snap(centre, "statuses_1x", 1)
	events.call("emit_signal", "reaction_triggered", 0, &"shatter", centre + Vector2(GAP * 0.5, 0.0))
	await _snap(centre, "status_reaction_1x", 1)
	quit(0)


## Let the flashes grow for a few frames, then save a crop around the world point `at`,
## `zoom` times bigger than the game draws it (1 is the real size).
func _snap(at: Vector2, name: String, zoom: int) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var scale_to_image: Vector2 = Vector2(image.get_size()) / Vector2(root.get_visible_rect().size)
	var centre: Vector2i = Vector2i((root.get_canvas_transform() * at) * scale_to_image)
	var half: Vector2i = Vector2i(128, 40) if zoom == 4 else Vector2i(120, 40)
	var corner: Vector2i = (centre - half).clamp(Vector2i.ZERO, image.get_size() - half * 2)
	var crop: Image = image.get_region(Rect2i(corner, half * 2))
	if zoom != 1:
		crop.resize(crop.get_width() * zoom, crop.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s.png" % [SHOTS_DIR, name])
	print("SHOT: %s" % name)


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame
