extends SceneTree
## Screenshots of the staff builder (staffs A6a), for people and for Claude to look at (not a
## test: it only checks that each staged state happened). Needs a display, so it runs only through
## `ci/build/build.sh --quick --screenshots`; each shot is saved as user://screenshots/<name>.png
## and copied to build/screenshots/.
##
## Shots: one player with the builder open, then picking cards into staff X, a wasted card, then
## all four players with their builders open on different staffs, in a wave.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 20

var _input: Node = null
var _focus: Node = null
var _hud: Node = null


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	_input = root.get_node_or_null("PlayerInput")
	_focus = root.get_node_or_null("UIFocus")
	_hud = root.get_node_or_null("Hud")
	var flow: Node = root.get_node_or_null("Flow")
	if _input == null or _focus == null or _hud == null or flow == null:
		_fail("the PlayerInput, UIFocus, Hud and Flow autoloads must exist")
		return
	_input.call("add_virtual_device", 0)
	flow.call("start_run", 0)
	await _settle()
	await _open_builder(0)
	var builder: Node = _hud.call("get_builder", 0)
	await _shot("builder_opened")
	# Two cards after the fire bolt: a split and a nova; the plan shows both casts.
	await _press(0, builder.call("slot_button", 2))
	await _press(0, _row(builder, "Split"))
	await _press(0, _row(builder, "Nova"))
	if not builder.call("is_open"):
		_fail("the builder of player 1 is not open")
		return
	await _shot("builder_one_player")
	# Homing alone in staff Y: it lands on the caster and does nothing, so the note says why.
	await _press(0, builder.call("tab_button", 2))
	await _press(0, builder.call("slot_button", 0))
	await _press(0, _row(builder, "Homing"))
	await _press(0, builder.call("slot_button", 0))
	await _shot("builder_wasted")
	# A stopped run leaves the HUD as it is, so close the builder as its owner would.
	_tap(0, &"overlay")
	await _settle()
	flow.call("stop_run")
	await _settle()
	for index in range(1, 4):
		_input.call("add_virtual_device", index)
	flow.call("start_run", 0)
	# The room is entered a little after the run starts; the overlay opens only inside it.
	for i in 4:
		await _settle()
	# The wave is live while the builders are staged; a downed wizard's builder closes, so keep
	# all four from being hurt meanwhile.
	for index in 4:
		flow.call("get_wizard", index).call("protect", 60.0)
	for index in 4:
		await _open_builder(index)
	# P1: staff X. P2: staff A. P3: staff Y with a pick. P4: staff B.
	await _press(1, _hud.call("get_builder", 1).call("tab_button", 0))
	await _press(2, _hud.call("get_builder", 2).call("tab_button", 2))
	await _press(2, _hud.call("get_builder", 2).call("slot_button", 0))
	await _press(2, _row(_hud.call("get_builder", 2), "Orbit"))
	await _press(3, _hud.call("get_builder", 3).call("tab_button", 3))
	for index in 4:
		if not _hud.call("get_builder", index).call("is_open"):
			_fail("the builder of player %d is not open in builder_four_players (focus panel open: %s)" % [index + 1, _focus.call("is_open", index)])
			return
	await _shot("builder_four_players")
	for index in 4:
		_tap(index, &"overlay")
	await _settle()
	flow.call("stop_run")
	await create_timer(0.3).timeout
	quit(0)


## The bag row of the card named `display_name` in `builder`, or null.
func _row(builder: Node, display_name: String) -> Control:
	for row: Button in builder.call("shown_rows"):
		if row.text.trim_prefix("> ").begins_with(display_name):
			return row
	return null


func _tap(player: int, action: StringName) -> void:
	_input.call("send_virtual", player, action, 1.0)
	_input.call("send_virtual", player, action, 0.0)


## The overlay, then "Build" (the second control), as a person does.
func _open_builder(player: int) -> void:
	_tap(player, &"overlay")
	await _settle()
	_tap(player, &"move_down")
	await process_frame
	await process_frame
	_tap(player, &"cast_a")
	await _settle()


## Move the player's focus down to `control` and press `cast_a` (activate) on it.
func _press(player: int, control: Control) -> void:
	for attempt in 120:
		if _focus.call("focused", player) == control:
			break
		_tap(player, &"move_down")
		await process_frame
		await process_frame
	_tap(player, &"cast_a")
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
