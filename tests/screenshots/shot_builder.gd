extends SceneTree
## Screenshots of the spell builder (M2 part 16), for people and for Claude to look at (not a
## test: it only checks that each staged state happened). Needs a display, so it runs only through
## `ci/build/build.sh --quick --screenshots`; each shot is saved as user://screenshots/<name>.png
## and copied to build/screenshots/.
##
## Shots: one player with the builder open on the bag of the element slot, then all four players
## with their builders open, each on something different (an element, a modifier, a held spell).

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
	await _press(0, builder.call("slot_button", 1))
	if not _hud.call("get_builder", 0).call("is_open"):
		_fail("the builder of player 1 is not open")
		return
	await _shot("builder_one_player")
	# A trigger, its held spell, then an element for it: refused (no form), so the reason shows.
	await _press(0, builder.call("slot_button", 5))
	await _press(0, builder.call("shown_rows")[0])
	await _press(0, builder.call("held_button"))
	await _press(0, builder.call("slot_button", 1))
	await _press(0, builder.call("shown_rows")[0])
	if str(builder.call("note_text")) == "":
		_fail("the refused pick showed no reason")
		return
	await _shot("builder_refused")
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
	for index in 4:
		await _open_builder(index)
	# P1: the element bag. P2: a modifier. P3: a trigger and its held spell. P4: spell B.
	await _press(0, _hud.call("get_builder", 0).call("slot_button", 1))
	await _press(1, _hud.call("get_builder", 1).call("slot_button", 2))
	await _press(2, _hud.call("get_builder", 2).call("slot_button", 5))
	await _press(2, _hud.call("get_builder", 2).call("shown_rows")[0])
	await _press(3, _hud.call("get_builder", 3).call("tab_button", 1))
	for index in 4:
		if not _hud.call("get_builder", index).call("is_open"):
			_fail("the builder of player %d is not open in builder_four_players (focus panel open: %s)" % [index + 1, _focus.call("is_open", index)])
			return
	await _shot("builder_four_players")
	flow.call("stop_run")
	await create_timer(0.3).timeout
	quit(0)


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
	_tap(player, &"cast")
	await _settle()


## Move the player's focus down to `control` and press cast on it.
func _press(player: int, control: Control) -> void:
	for attempt in 40:
		if _focus.call("focused", player) == control:
			break
		_tap(player, &"move_down")
		await process_frame
		await process_frame
	_tap(player, &"cast")
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
