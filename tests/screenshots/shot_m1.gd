extends SceneTree
## Screenshots of the M1 game, for people and for Claude to look at (not a test:
## it checks nothing). Needs a display, so it runs only through
## `ci/build/build.sh --quick --screenshots` (on a virtual display); each shot is
## saved as user://screenshots/<name>.png and the script copies them to build/screenshots/.
##
## Shots: the main menu, the arena with four wizards just after Play, the same
## with all four overlays open, with player 4 down, and with the Coop camera at
## zoom 0.5 (wizards in the four corners). Look at them for legible 12/14 px text
## over the translucent panels.

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
	for index in 4:
		_tap(input, index, &"overlay")
	await _shot("hud_four_overlays")
	for index in 4:
		_tap(input, index, &"overlay")
	await process_frame
	var wizard4: Node = flow.call("get_wizard", 3)
	if wizard4 != null:
		wizard4.call("take_damage", 9999)
		await _shot("hud_player_four_down")
		wizard4.call("revive", 0)
	_spread_wizards(flow)
	await _shot("coop_camera_zoom_half")
	flow.call("stop_run")
	await create_timer(0.3).timeout
	quit(0)


## One press and release of `action` on the virtual device of `player`.
func _tap(input: Node, player: int, action: StringName) -> void:
	input.call("send_virtual", player, action, 1.0)
	input.call("send_virtual", player, action, 0.0)


## Put the wizards near the four corners of the room and snap the Coop camera to
## fit them, which zooms it out to its limit.
func _spread_wizards(flow: Node) -> void:
	var coop: Node = root.get_node_or_null("Coop")
	var corners: Array[Vector2] = [Vector2(24, 24), Vector2(616, 24), Vector2(24, 360), Vector2(616, 360)]
	for index in 4:
		var wizard: Node2D = flow.call("get_wizard", index) as Node2D
		if wizard != null:
			wizard.global_position = corners[index]
	if coop != null:
		coop.call("fit_camera")
		coop.call("snap")


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
