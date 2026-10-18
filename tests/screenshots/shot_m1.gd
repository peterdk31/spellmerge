extends SceneTree
## Screenshots of the M1 game, for people and for Claude to look at (not a test: it only
## checks that each staged state happened). Needs a display, so it runs only through
## `ci/build/build.sh --quick --screenshots` (on a virtual display); each shot is
## saved as user://screenshots/<name>.png and the script copies them to build/screenshots/.
##
## Shots: the main menu, the arena with four wizards just after Play, the same
## with all four overlays open, with player 4 down, and with the Coop camera at
## zoom 0.5 (wizards in the corners of an area twice the screen). Look at them for legible 12/14 px text
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
	# Each wizard aims its own way, to see the aim reticle and the turned sprites.
	var aims: Array[Vector2] = [Vector2.UP, Vector2(1, -1).normalized(), Vector2.LEFT, Vector2.RIGHT]
	for index in 4:
		input.call("send_virtual_aim", index, aims[index])
	await _shot("arena_four_wizards")
	# Shots above the floor, fired from the staff tips, and a wizard mid-dash.
	for index in 3:
		input.call("send_virtual", index, &"cast", 1.0)
	input.call("send_virtual", 3, &"move_right", 1.0)
	_tap(input, 3, &"dodge")
	for i in 12:
		await physics_frame
	await RenderingServer.frame_post_draw
	var shots_node: Node = root.get_node_or_null("Projectiles")
	if shots_node == null or int(shots_node.get("drawn")) < 3:
		_fail("the three shots are not in the draw batch in shots_and_dash")
		return
	var action_image: Image = root.get_texture().get_image()
	if action_image != null:
		action_image.save_png("%s/shots_and_dash.png" % SHOTS_DIR)
		print("SHOT: shots_and_dash (%dx%d)" % [action_image.get_width(), action_image.get_height()])
	for index in 3:
		input.call("send_virtual", index, &"cast", 0.0)
	input.call("send_virtual", 3, &"move_right", 0.0)
	for index in 4:
		_tap(input, index, &"overlay")
	await _settle()
	var focus: Node = root.get_node_or_null("UIFocus")
	for index in 4:
		if focus == null or not focus.call("is_open", index):
			_fail("the overlay of player %d is not open in hud_four_overlays" % (index + 1))
			return
	await _shot("hud_four_overlays")
	for index in 4:
		_tap(input, index, &"overlay")
	await process_frame
	var wizard4: Node = flow.call("get_wizard", 3)
	if wizard4 == null:
		_fail("player 4 has no wizard")
		return
	# One frame after a cast and after a hit: the muzzle flash in the caster's colour
	# along the aim, the caster squash, and the red vignette toward player 4's corner.
	await _settle()
	var wizard1: Node2D = flow.call("get_wizard", 0) as Node2D
	# The HUD stops fading the vignette for this shot: frames are slow on a software
	# renderer and the glow would be gone before it is drawn.
	root.get_node("Hud").set_process(false)
	input.call("send_virtual", 0, &"cast", 1.0)
	wizard4.call("take_damage", 30)
	await physics_frame
	await physics_frame
	input.call("send_virtual", 0, &"cast", 0.0)
	await RenderingServer.frame_post_draw
	var juice_image: Image = root.get_texture().get_image()
	var hud: Node = root.get_node_or_null("Hud")
	if juice_image == null or hud == null or not hud.call("get_vignette").visible:
		_fail("the vignette does not show after player 4 is hit in juice_cast_and_hit")
		return
	juice_image.save_png("%s/juice_cast_and_hit.png" % SHOTS_DIR)
	print("SHOT: juice_cast_and_hit (%dx%d)" % [juice_image.get_width(), juice_image.get_height()])
	# The caster and its muzzle flash, cropped and enlarged 4 times (the flash and the
	# squash last a few frames, so two frames are taken after the cast).
	root.get_node("Hud").set_process(true)
	_save_crop(juice_image, wizard1, "juice_muzzle_flash_a")
	await physics_frame
	await RenderingServer.frame_post_draw
	_save_crop(root.get_texture().get_image(), wizard1, "juice_muzzle_flash_b")
	await _settle()
	# An imp 6 frames (0.1 s) after the killing blow: the death animation.
	var combat: Node = root.get_node_or_null("Combat")
	var imps: Array = flow.get("_enemies")
	var imp: Node2D = null
	for candidate: Variant in imps:
		if is_instance_valid(candidate):
			imp = candidate as Node2D
			break
	if combat == null or imp == null:
		_fail("there is no imp to kill in juice_death_animation")
		return
	var imp_at: Transform2D = imp.get_global_transform_with_canvas()
	combat.call("hit", 0, imp, 9999)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	_save_crop_at(root.get_texture().get_image(), imp_at.origin, "juice_death_animation")
	await _settle()
	wizard4.call("take_damage", 9999)
	await _settle()
	if not wizard4.call("is_downed"):
		_fail("player 4 is not down in hud_player_four_down")
		return
	await _shot("hud_player_four_down")
	wizard4.call("revive", 0)
	_spread_wizards(flow)
	await _settle()
	var coop: Node = root.get_node_or_null("Coop")
	var camera: Camera2D = null if coop == null else coop.get("camera") as Camera2D
	if camera == null or camera.zoom.x > 0.51:
		_fail("the Coop camera is not at zoom 0.5 in coop_camera_zoom_half")
		return
	print("SHOT: camera zoom %.2f" % camera.zoom.x)
	await _shot("coop_camera_zoom_half")
	flow.call("stop_run")
	await create_timer(0.3).timeout
	quit(0)


## One press and release of `action` on the virtual device of `player`.
func _tap(input: Node, player: int, action: StringName) -> void:
	input.call("send_virtual", player, action, 1.0)
	input.call("send_virtual", player, action, 0.0)


## Put the wizards in the four corners of an area twice the screen and snap the
## Coop camera to fit them, which zooms it out to its limit (0.5). The room is only
## one screen, so its camera limits are widened first, or the zoom would stay at 1.
## Most of the picture is then outside the room; the panels are what is looked at.
func _spread_wizards(flow: Node) -> void:
	var coop: Node = root.get_node_or_null("Coop")
	var corners: Array[Vector2] = [Vector2(24, 24), Vector2(1208, 24), Vector2(24, 648), Vector2(1208, 648)]
	for index in 4:
		var wizard: Node2D = flow.call("get_wizard", index) as Node2D
		if wizard != null:
			wizard.global_position = corners[index]
	if coop != null:
		var camera: Camera2D = coop.get("camera") as Camera2D
		if camera != null:
			camera.limit_left = -64
			camera.limit_top = -64
			camera.limit_right = 1344
			camera.limit_bottom = 784
		coop.call("snap")


## Save a 4x enlarged crop of `image` around `node` (see `_save_crop_at`).
func _save_crop(image: Image, node: Node2D, name: String) -> void:
	_save_crop_at(image, node.get_global_transform_with_canvas().origin, name)


## Save the 96x96 pixels of `image` around the screen position `at`, enlarged 4 times.
func _save_crop_at(image: Image, at: Vector2, name: String) -> void:
	var size: Vector2 = Vector2(image.get_size())
	var scale_to_image: Vector2 = size / Vector2(root.get_visible_rect().size)
	var centre: Vector2 = at * scale_to_image
	var half: int = 48
	var corner: Vector2i = Vector2i(centre) - Vector2i(half, half)
	corner = corner.clamp(Vector2i.ZERO, Vector2i(image.get_size()) - Vector2i(half * 2, half * 2))
	var crop: Image = image.get_region(Rect2i(corner, Vector2i(half * 2, half * 2)))
	crop.resize(half * 8, half * 8, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s.png" % [SHOTS_DIR, name])
	print("SHOT: %s" % name)


func _fail(message: String) -> void:
	printerr("SHOT FAILED: " + message)
	quit(1)


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame


func _shot(shot_name: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/%s.png" % [SHOTS_DIR, shot_name]
	if image == null or image.save_png(path) != OK:
		printerr("SHOT FAILED: could not save " + path)
		return
	print("SHOT: %s (%dx%d)" % [shot_name, image.get_width(), image.get_height()])
