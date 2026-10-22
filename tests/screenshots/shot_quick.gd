extends SceneTree
## Screenshots of the quick view and the quick actions (M2 part 18), for people and for Claude to
## look at (not a test: it only checks that each staged state happened). Needs a display, so it
## runs only through `ci/build/build.sh --quick --screenshots`; each shot is saved as
## user://screenshots/<name>.png and copied to build/screenshots/.
##
## Shots: one player in the first wave with the quick view and its drop list (the corner panel
## says which spell is active), the overlay with its drop list, and four players with their quick
## views at once.

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
	# Wave 1 is on: the overlay's Drop component, in combat.
	_tap(0, &"swap")
	await _settle()
	_tap(0, &"overlay")
	await _settle()
	var overlay: Node = _hud.call("get_overlay", 0)
	await _press(0, overlay.call("drop_button"))
	if not bool(overlay.call("is_dropping")):
		_fail("the overlay's drop list is not shown")
		return
	await _shot("quick_overlay_drop")
	_tap(0, &"dodge")
	await _settle()
	_tap(0, &"dodge")
	await _settle()
	await _open_builder(0)
	var builder: Node = _hud.call("get_builder", 0)
	if not bool(builder.call("is_quick")):
		_fail("the builder opened in a wave is not the quick view")
		return
	await _shot("quick_view")
	await _press(0, builder.call("drop_button"))
	if not bool(builder.call("is_dropping")):
		_fail("the quick view's drop list is not shown")
		return
	await _shot("quick_view_drop_list")
	_tap(0, &"overlay")
	await _settle()
	flow.call("stop_run")
	await _settle()
	for index in range(1, 4):
		_input.call("add_virtual_device", index)
	flow.call("start_run", 0)
	for i in 4:
		await _settle()
	for index in 4:
		await _open_builder(index)
	for index in 4:
		if not bool(_hud.call("get_builder", index).call("is_quick")):
			_fail("the builder of player %d is not the quick view" % [index + 1])
			return
	# P1 and P4 drop a component, P2 and P3 stay on the button.
	for index in [0, 3]:
		await _press(index, _hud.call("get_builder", index).call("drop_button"))
	await _shot("quick_view_four_players")
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
