extends SceneTree
## Screenshots of the M1 game, for people and for Claude to look at (not a test:
## it checks nothing). Needs a display, so it runs only through
## `ci/build/build.sh --quick --screenshots` (on a virtual display); each shot is
## saved as user://screenshots/<name>.png and the script copies them to build/screenshots/.
##
## Shots: the main menu, and the arena with four wizards just after Play.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 30


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await _shot("main_menu")
	var input: Node = root.get_node_or_null("PlayerInput")
	var flow: Node = root.get_node_or_null("Flow")
	if input == null or flow == null:
		printerr("SHOT FAILED: the PlayerInput and Flow autoloads must exist")
		quit(1)
		return
	for index in 4:
		input.call("add_virtual_device", index)
	flow.call("start_run", 0)
	await _shot("arena_four_wizards")
	flow.call("stop_run")
	await create_timer(0.3).timeout
	quit(0)


func _shot(shot_name: String) -> void:
	for i in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/%s.png" % [SHOTS_DIR, shot_name]
	if image == null or image.save_png(path) != OK:
		printerr("SHOT FAILED: could not save " + path)
		return
	print("SHOT: %s (%dx%d)" % [shot_name, image.get_width(), image.get_height()])
