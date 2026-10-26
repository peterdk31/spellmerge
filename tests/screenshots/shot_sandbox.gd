extends SceneTree
## Screenshots of the sandbox (staffs B7), for people and for Claude to look at (not a test: it
## only checks that each staged state happened). Needs a display, so it runs only through
## `ci/build/build.sh --quick --screenshots`; each shot is saved as user://screenshots/<name>.png
## and copied to build/screenshots/.
##
## Shots: one player firing fire bolts up the left lane at the training dummy (damage numbers,
## DPS, burn); the pause menu's sandbox page open; four players, two per lane, with an imp
## wave in and the shooting dummy's telegraph up.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 20

var _input: Node = null
var _focus: Node = null
var _hud: Node = null
var _flow: Node = null


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	_input = root.get_node_or_null("PlayerInput")
	_focus = root.get_node_or_null("UIFocus")
	_hud = root.get_node_or_null("Hud")
	_flow = root.get_node_or_null("Flow")
	var events: Node = root.get_node_or_null("Events")
	if _input == null or _focus == null or _hud == null or _flow == null or events == null:
		_fail("the PlayerInput, UIFocus, Hud, Flow and Events autoloads must exist")
		return
	_input.call("add_virtual_device", 0)
	events.emit_signal("sandbox_requested", 0)
	await _settle()
	if not _flow.get("sandbox"):
		_fail("the sandbox did not start")
		return
	# P1 walks up the left lane and fires its X staff (fire bolt) at the training dummy.
	_input.call("send_virtual", 0, &"move_up", 1.0)
	await create_timer(1.2).timeout
	_input.call("send_virtual", 0, &"move_up", 0.0)
	var dummy: Node2D = (_flow.call("dummies") as Array)[0]
	var wizard: Node2D = _flow.call("get_wizard", 0)
	_input.call("send_virtual_aim", 0, (dummy.position + Vector2(0.0, -14.0) - wizard.position).normalized())
	_input.call("send_virtual", 0, &"staff_2", 1.0)
	await create_timer(2.0).timeout
	_input.call("send_virtual", 0, &"staff_2", 0.0)
	if int(dummy.get("total_damage")) <= 0:
		_fail("the training dummy took no damage")
		return
	await _shot("sandbox_training_lane")
	await _open_page(0)
	var pause_menu: Node = _hud.call("get_pause_menu")
	if not pause_menu.call("is_open") or int(pause_menu.get("page")) != 1:
		_fail("the pause menu's sandbox page is not open for player 1")
		return
	await _shot("sandbox_page")
	_tap(0, &"pause")
	await _settle()
	_flow.call("stop_run")
	await _settle()
	for index in range(1, 4):
		_input.call("add_virtual_device", index)
	events.emit_signal("sandbox_requested", 0)
	for i in 4:
		await _settle()
	for index in 4:
		_flow.call("get_wizard", index).call("protect", 60.0)
	events.emit_signal("sandbox_action_requested", 1, &"imp_wave")
	await create_timer(1.0).timeout
	var shooter: Node = (_flow.call("dummies") as Array)[1]
	for wait in 40:
		if shooter.call("is_telegraphing"):
			break
		await process_frame
	await _shot("sandbox_four_players")
	_flow.call("stop_run")
	await create_timer(0.3).timeout
	quit(0)


func _tap(player: int, action: StringName) -> void:
	_input.call("send_virtual", player, action, 1.0)
	_input.call("send_virtual", player, action, 0.0)


## Start, then "Sandbox" (the second button in the sandbox), as a person does.
func _open_page(player: int) -> void:
	_tap(player, &"pause")
	await _settle()
	_tap(player, &"move_down")
	await process_frame
	await process_frame
	_tap(player, &"accept")
	await _settle()


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
