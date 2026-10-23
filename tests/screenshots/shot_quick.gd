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
	# Wave 1 is on: the overlay's Bag, in combat.
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
	await _walk_a_wave(1, "one")
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
	await _walk_a_wave(4, "four")
	# The break: the wave is cleared, the builders unfold and the hammer counts down (staged with
	# the events Flow sends, so the room's imps stay out of the picture).
	var events: Node = root.get_node("Events")
	events.emit_signal("room_cleared", &"arena_01")
	events.emit_signal("build_break_started", 12.0)
	await _shot("build_break")
	flow.call("stop_run")
	await create_timer(0.3).timeout
	quit(0)


## A wave as people play it, with every player's builder open: the break (full builders), the
## wave starts and they fold, a swap, a dropped component, the wave is cleared and they unfold.
## Staged with the events Flow sends, so the room's imps stay out of the picture. Each step is
## shot at 1x, and the first player's quarter again at 4x.
func _walk_a_wave(count: int, label: String) -> void:
	var events: Node = root.get_node("Events")
	events.emit_signal("room_cleared", &"arena_01")
	await _settle()
	for index in count:
		if not bool(_hud.call("get_builder", index).call("is_open")):
			await _open_builder(index)
		elif bool(_hud.call("get_builder", index).call("is_quick")):
			_fail("a builder stayed folded after room_cleared")
			return
	await _walk_shot("walk_%s_break_full" % label)
	events.emit_signal("wave_started", 2)
	await _settle()
	for index in count:
		var builder: Node = _hud.call("get_builder", index)
		if not bool(builder.call("is_quick")) or not bool(builder.call("is_open")):
			_fail("the open builder did not fold on wave_started")
			return
	await _walk_shot("walk_%s_folded" % label)
	# A swap press is dropped inside a menu, so a player closes the quick view, swaps and looks again.
	var before: Array[int] = []
	for index in count:
		before.append(int(_hud.call("get_builder", index).call("viewed_spell")))
		_tap(index, &"overlay")
	await _settle()
	for index in count:
		_tap(index, &"swap")
	await _settle()
	for index in count:
		await _open_builder(index)
		if int(_hud.call("get_builder", index).call("viewed_spell")) == before[index]:
			_fail("the swap did not change player %d's spell" % index)
			return
	await _walk_shot("walk_%s_swapped" % label)
	for index in count:
		await _press(index, _hud.call("get_builder", index).call("drop_button"))
		_tap(index, &"cast")
		await _settle()
	await _walk_shot("walk_%s_dropped" % label)
	events.emit_signal("room_cleared", &"arena_01")
	await _settle()
	for index in count:
		if bool(_hud.call("get_builder", index).call("is_quick")):
			_fail("the builder did not unfold on room_cleared")
			return
	await _walk_shot("walk_%s_unfolded" % label)
	for index in count:
		_tap(index, &"overlay")
	await _settle()


## The whole view at 1x, and the first player's quarter at 4x.
func _walk_shot(shot_name: String) -> void:
	await _shot(shot_name)
	await _quarter(shot_name + "_4x")


func _quarter(shot_name: String) -> void:
	var image: Image = root.get_texture().get_image()
	var crop: Image = image.get_region(Rect2i(0, 0, 240, 180))
	crop.resize(960, 720, Image.INTERPOLATE_NEAREST)
	if crop.save_png("%s/%s.png" % [SHOTS_DIR, shot_name]) == OK:
		print("SHOT: %s (960x720)" % shot_name)


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
