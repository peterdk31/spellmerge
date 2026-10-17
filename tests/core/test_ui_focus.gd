extends SceneTree
## Tests for core/ui_focus: a panel takes input only from its owner, with four
## owners at once, and with one player's panel open while another's is not.
## Input goes through the real input manager's virtual devices.
##
## godot --headless --path . --script res://tests/core/test_ui_focus.gd

const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

var _failures: Array[String] = []
var _bus: Node
var _input: Node
var _focus: Node
## Every signal as [name, player, control index or -1], in order.
var _log: Array = []
## Four panels of three buttons each; _buttons[player][i].
var _buttons: Array[Array] = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	_test_autoload_registered()
	_test_open_focuses_first()
	_test_open_rejects_bad_input()
	_test_navigation_wraps()
	_test_disabled_and_hidden_are_skipped()
	_test_activate_and_cancel()
	_test_closed_panel_ignores_its_owner()
	_test_only_the_owner_moves_the_panel()
	_test_four_owners_at_once()
	_test_one_open_others_closed()
	_test_held_button_when_opening_does_nothing()
	_test_press_acts_once()
	_test_device_left_closes_the_panel()
	_test_quick_taps_are_not_lost()
	_test_open_panel_captures_its_owners_input()
	_test_capture_ends_on_close_and_leave()
	_test_focused_control_disabled_before_activate()
	_test_focused_control_freed()
	_test_hidden_parent_in_the_tree()
	_test_open_needs_a_joined_device()
	_test_reopen_replaces_the_panel()
	_test_close_then_reopen()
	_test_never_takes_global_focus()
	_test_invalid_player_index()
	_teardown()
	if _failures.is_empty():
		print("TEST OK: core/ui_focus")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _setup(devices: int = 4) -> void:
	_teardown()
	_bus = EventsScript.new()
	_input = InputManagerScript.new()
	_input.events = _bus
	_focus = UIFocusScript.new()
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	_log.clear()
	_focus.opened.connect(func(p: int) -> void: _log.append(["opened", p, -1]))
	_focus.closed.connect(func(p: int) -> void: _log.append(["closed", p, -1]))
	_focus.focus_changed.connect(func(p: int, c: Control) -> void: _log.append(["focus", p, _buttons[p].find(c)]))
	_focus.activated.connect(func(p: int, c: Control) -> void: _log.append(["activated", p, _buttons[p].find(c)]))
	_focus.cancelled.connect(func(p: int) -> void: _log.append(["cancelled", p, -1]))
	for player in devices:
		_input.add_virtual_device(player)
	_free_buttons()
	for player in 4:
		var row: Array = []
		for i in 3:
			row.append(Button.new())
		_buttons.append(row)


func _teardown() -> void:
	_free_buttons()
	for node: Node in [_focus, _input, _bus]:
		if node != null:
			node.free()
	_focus = null
	_input = null
	_bus = null


func _free_buttons() -> void:
	for row in _buttons:
		for button: Node in row:
			if is_instance_valid(button):
				button.free()
	_buttons.clear()


func _panel(player: int) -> Array[Control]:
	var controls: Array[Control] = []
	for button: Button in _buttons[player]:
		controls.append(button)
	return controls


## Press and release `action` on the virtual device of `player` within one
## frame, then poll once: the tap must not be lost.
func _tap(player: int, action: StringName) -> void:
	_input.send_virtual(player, action, 1.0)
	_input.send_virtual(player, action, 0.0)
	_focus.poll()


func _count(kind: String, player: int) -> int:
	var count: int = 0
	for entry: Array in _log:
		if entry[0] == kind and entry[1] == player:
			count += 1
	return count


func _test_autoload_registered() -> void:
	var path := str(ProjectSettings.get_setting("autoload/UIFocus", ""))
	_check(path == "*res://core/ui_focus/ui_focus.gd", "autoload UIFocus is registered, got '%s'" % path)


func _test_open_focuses_first() -> void:
	_setup()
	_check(_focus.open(2, _panel(2)), "open succeeds")
	_check(_focus.is_open(2), "the panel is open")
	_check(_focus.focused(2) == _buttons[2][0], "the first control is focused")
	_check(_log == [["opened", 2, -1], ["focus", 2, 0]], "opened then focus_changed, got %s" % str(_log))
	_check(not _focus.is_open(0), "other players' panels stay closed")
	_check(_focus.focused(0) == null, "a closed panel has no focus")


func _test_open_rejects_bad_input() -> void:
	_setup()
	_check(not _focus.open(0, [] as Array[Control]), "an empty panel does not open")
	_check(not _focus.open(4, _panel(0)), "player 4 does not exist")
	_check(not _focus.open(-1, _panel(0)), "player -1 does not exist")
	_check(not _focus.is_open(0), "nothing opened")


func _test_navigation_wraps() -> void:
	_setup()
	_focus.open(0, _panel(0))
	_tap(0, &"move_down")
	_check(_focus.focus_index(0) == 1, "down goes to the next control")
	_tap(0, &"move_right")
	_check(_focus.focus_index(0) == 2, "right goes to the next control")
	_tap(0, &"move_down")
	_check(_focus.focus_index(0) == 0, "next wraps round to the first")
	_tap(0, &"move_up")
	_check(_focus.focus_index(0) == 2, "up from the first wraps to the last")
	_tap(0, &"move_left")
	_check(_focus.focus_index(0) == 1, "left goes to the previous control")


func _test_disabled_and_hidden_are_skipped() -> void:
	_setup()
	(_buttons[0][1] as Button).disabled = true
	_focus.open(0, _panel(0))
	_tap(0, &"move_down")
	_check(_focus.focus_index(0) == 2, "a disabled button is skipped")
	(_buttons[0][0] as Button).visible = false
	_tap(0, &"move_down")
	_check(_focus.focus_index(0) == 2, "with one usable control, focus stays")
	_setup()
	(_buttons[1][0] as Button).disabled = true
	_focus.open(1, _panel(1))
	_check(_focus.focus_index(1) == 1, "the first usable control is focused on open")
	_setup()
	for button: Button in _buttons[3]:
		button.disabled = true
	_focus.open(3, _panel(3))
	_check(_focus.focused(3) == null, "nothing usable, nothing focused")
	_tap(3, &"move_down")
	_tap(3, &"move_up")
	_check(_focus.focused(3) == null, "moving with nothing usable does nothing")
	(_buttons[3][2] as Button).disabled = false
	_tap(3, &"move_up")
	_check(_focus.focus_index(3) == 2, "a control enabled later can be reached")


func _test_activate_and_cancel() -> void:
	_setup()
	_focus.open(1, _panel(1))
	_tap(1, &"move_down")
	_tap(1, &"cast")
	_tap(1, &"dodge")
	_check(_count("activated", 1) == 1, "cast activates once")
	_check(_log.has(["activated", 1, 1]), "it activates the focused control")
	_check(_count("cancelled", 1) == 1, "dodge cancels once")
	_check(_focus.is_open(1), "cancel does not close the panel by itself")


func _test_closed_panel_ignores_its_owner() -> void:
	_setup()
	for action: StringName in [&"move_down", &"cast", &"dodge"]:
		_tap(0, action)
	_check(_log.is_empty(), "no panel open, nothing happens, got %s" % str(_log))


func _test_only_the_owner_moves_the_panel() -> void:
	_setup()
	_focus.open(1, _panel(1))
	_log.clear()
	for player in [0, 2, 3]:
		for action: StringName in [&"move_down", &"move_up", &"move_left", &"move_right", &"cast", &"dodge"]:
			_tap(player, action)
	_check(_log.is_empty(), "players 1, 3 and 4 cannot touch player 2's panel, got %s" % str(_log))
	_check(_focus.focus_index(1) == 0, "player 2's focus did not move")
	_tap(1, &"move_down")
	_check(_focus.focus_index(1) == 1, "the owner moves it")


func _test_four_owners_at_once() -> void:
	_setup()
	for player in 4:
		_focus.open(player, _panel(player))
	_log.clear()
	# All four hold a different direction in the same frame.
	_input.send_virtual(0, &"move_down")
	_input.send_virtual(1, &"move_up")
	_input.send_virtual(2, &"cast")
	_input.send_virtual(3, &"dodge")
	_focus.poll()
	_check(_focus.focus_index(0) == 1, "player 1 went to the next control")
	_check(_focus.focus_index(1) == 2, "player 2 wrapped to the last control")
	_check(_focus.focus_index(2) == 0, "player 3 did not move")
	_check(_focus.focus_index(3) == 0, "player 4 did not move")
	_check(_count("activated", 2) == 1 and _count("activated", 0) + _count("activated", 1) + _count("activated", 3) == 0,
		"only player 3 activated, got %s" % str(_log))
	_check(_count("cancelled", 3) == 1 and _count("cancelled", 0) + _count("cancelled", 1) + _count("cancelled", 2) == 0,
		"only player 4 cancelled, got %s" % str(_log))
	# Holding does not repeat, releasing does nothing.
	_focus.poll()
	_input.send_virtual(0, &"move_down", 0.0)
	_input.send_virtual(1, &"move_up", 0.0)
	_input.send_virtual(2, &"cast", 0.0)
	_input.send_virtual(3, &"dodge", 0.0)
	_focus.poll()
	_check(_focus.focus_index(0) == 1 and _focus.focus_index(1) == 2, "holding moved focus only once")
	# Closing one panel leaves the other three working.
	_focus.close(2)
	_tap(0, &"move_down")
	_tap(1, &"move_down")
	_tap(3, &"move_down")
	_tap(2, &"move_down")
	_check(_focus.focus_index(0) == 2 and _focus.focus_index(1) == 0 and _focus.focus_index(3) == 1,
		"the three open panels still move")
	_check(not _focus.is_open(2) and _focus.focus_index(2) == -1, "the closed panel stays closed")


func _test_one_open_others_closed() -> void:
	_setup()
	_focus.open(0, _panel(0))
	# Player 2 plays on: moving and casting must not reach player 1's panel.
	_input.send_virtual(1, &"move_down")
	_input.send_virtual(1, &"cast")
	_focus.poll()
	_check(_log.size() == 2, "only player 1's own opening was logged, got %s" % str(_log))
	_check(_input.get_move(1) == Vector2(0.0, 1.0), "player 2's gameplay input is untouched by the panel")
	_check(_input.is_action_pressed(1, &"cast"), "player 2 is still casting")
	_check(_input.get_move(0) == Vector2.ZERO, "the open panel does not eat or invent input for player 1")
	# Player 1 opens, then player 2's own panel opens later without disturbing it.
	_tap(0, &"move_down")
	_focus.open(1, _panel(1))
	_check(_focus.focus_index(0) == 1, "opening player 2's panel leaves player 1's focus alone")
	_check(_focus.is_open(0) and _focus.is_open(1) and not _focus.is_open(2), "exactly players 1 and 2 are open")


func _test_held_button_when_opening_does_nothing() -> void:
	_setup()
	# The overlay button opens the panel; casting is held too.
	_input.send_virtual(0, &"cast")
	_input.send_virtual(0, &"move_down")
	_focus.open(0, _panel(0))
	_focus.poll()
	_check(_count("activated", 0) == 0, "a held cast does not activate on open")
	_check(_focus.focus_index(0) == 0, "a held direction does not move on open")
	_input.send_virtual(0, &"cast", 0.0)
	_input.send_virtual(0, &"move_down", 0.0)
	_focus.poll()
	_tap(0, &"cast")
	_check(_count("activated", 0) == 1, "after release a new press works")


func _test_press_acts_once() -> void:
	_setup()
	_focus.open(0, _panel(0))
	_input.send_virtual(0, &"move_down")
	for _i in 5:
		_focus.poll()
	_check(_focus.focus_index(0) == 1, "a held direction moves one step, got %d" % _focus.focus_index(0))
	_input.send_virtual(0, &"move_down", 0.0)
	_focus.poll()
	_tap(0, &"move_down")
	_check(_focus.focus_index(0) == 2, "a second press moves again")


func _test_device_left_closes_the_panel() -> void:
	_setup()
	_focus.open(0, _panel(0))
	_focus.open(1, _panel(1))
	_input.leave(1)
	_check(_focus.is_open(0), "player 1's panel stays open")
	_check(not _focus.is_open(1), "the panel of a player who left closes")
	_check(_count("closed", 1) == 1, "closed is sent once")
	_input.leave(1)
	_check(_count("closed", 1) == 1, "leaving again sends nothing")


func _test_quick_taps_are_not_lost() -> void:
	_setup()
	_focus.open(0, _panel(0))
	_input.send_virtual(0, &"move_down")
	_input.send_virtual(0, &"move_down", 0.0)
	_focus.poll()
	_check(_focus.focus_index(0) == 1, "a tap released before the poll still moves focus")
	_tap(0, &"move_down")
	_tap(0, &"move_down")
	_check(_focus.focus_index(0) == 0, "two taps in two frames move twice")
	_input.send_virtual(0, &"cast")
	_input.send_virtual(0, &"cast", 0.0)
	_input.send_virtual(0, &"cast")
	_input.send_virtual(0, &"cast", 0.0)
	_focus.poll()
	_check(_count("activated", 0) == 2, "two taps within one frame activate twice")


func _test_open_panel_captures_its_owners_input() -> void:
	_setup()
	_focus.open(0, _panel(0))
	_check(_input.is_captured(0), "an open panel captures its owner")
	_input.send_virtual(0, &"move_right")
	_input.send_virtual(0, &"cast")
	_input.send_virtual(0, &"dodge")
	_input.send_virtual(0, &"overlay")
	_check(_input.get_move(0) == Vector2.ZERO, "the owner's wizard does not walk")
	_check(not _input.is_action_pressed(0, &"cast") and not _input.is_action_pressed(0, &"dodge"),
		"the owner's wizard does not cast or dodge")
	_check(not _input.is_action_just_pressed(0, &"cast"), "no just-pressed for gameplay")
	_check(_input.get_strength(0, &"move_right") == 0.0, "no strength for gameplay")
	_check(_input.is_action_pressed(0, &"overlay"), "the overlay button stays readable")
	_focus.poll()
	_check(_count("activated", 0) == 1 and _count("cancelled", 0) == 1, "the panel still sees the presses")
	# Other players, with and without a panel, play on.
	_input.send_virtual(1, &"move_down")
	_input.send_virtual(1, &"cast")
	_check(not _input.is_captured(1), "other players are not captured")
	_check(_input.get_move(1) == Vector2(0.0, 1.0) and _input.is_action_pressed(1, &"cast"),
		"other players move and cast while player 1's panel is open")
	_focus.open(2, _panel(2))
	_check(_input.get_move(1) == Vector2(0.0, 1.0), "a second open panel leaves player 2 alone")
	_check(_input.is_captured(2) and not _input.is_captured(3), "capture is per player")


func _test_capture_ends_on_close_and_leave() -> void:
	_setup()
	_focus.open(0, _panel(0))
	_focus.open(1, _panel(1))
	_input.send_virtual(0, &"move_right")
	_focus.close(0)
	_check(not _input.is_captured(0), "closing frees the capture")
	_check(_input.get_move(0) == Vector2(1.0, 0.0), "a direction still held carries on after close")
	_input.leave(1)
	_check(not _input.is_captured(1) and not _focus.is_open(1), "leaving frees the capture")
	_input.set_captured(7, true)
	_check(not _input.is_captured(7), "an out of range player is never captured")


func _test_focused_control_disabled_before_activate() -> void:
	_setup()
	_focus.open(0, _panel(0))
	(_buttons[0][0] as Button).disabled = true
	_tap(0, &"cast")
	_check(_count("activated", 0) == 0, "a control disabled after getting focus is not activated")
	_check(_focus.focus_index(0) == 1, "focus moved to the next usable control")
	_check(_log.has(["focus", 0, 1]), "focus_changed was sent for the move")
	_tap(0, &"cast")
	_check(_log.has(["activated", 0, 1]), "the new focus can be activated")
	for button: Button in _buttons[0]:
		button.disabled = true
	_tap(0, &"cast")
	_check(_focus.focused(0) == null and _count("activated", 0) == 1, "nothing usable, nothing activated")
	(_buttons[0][2] as Button).disabled = false
	_tap(0, &"move_down")
	_check(_focus.focus_index(0) == 2, "a control enabled later can be reached")
	(_buttons[0][2] as Button).visible = false
	_focus.activate(0)
	_check(_count("activated", 0) == 1, "a control hidden after getting focus is not activated")


func _test_focused_control_freed() -> void:
	_setup()
	_focus.open(0, _panel(0))
	var gone: Button = _buttons[0][0]
	_buttons[0][0] = null
	gone.free()
	_check(_focus.focused(0) == null, "a freed control is not returned")
	_focus.activate(0)
	_check(_count("activated", 0) == 0, "a freed control is not activated")
	_check(_focus.focus_index(0) == 1, "focus moved off the freed control")
	_focus.poll()
	_tap(0, &"move_down")
	_tap(0, &"move_down")
	_check(_focus.focus_index(0) == 1, "navigation skips the freed control")
	var all_gone: Button = _buttons[1][0]
	_focus.open(1, _panel(1))
	_buttons[1][0] = null
	all_gone.free()
	(_buttons[1][1] as Button).free()
	(_buttons[1][2] as Button).free()
	_buttons[1][1] = null
	_buttons[1][2] = null
	_tap(1, &"cast")
	_check(_focus.focused(1) == null and _count("activated", 1) == 0, "a panel of freed controls does nothing")


func _test_hidden_parent_in_the_tree() -> void:
	_setup()
	var holder := Control.new()
	get_root().add_child(holder)
	var parent := Control.new()
	holder.add_child(parent)
	var first := Button.new()
	var second := Button.new()
	parent.add_child(first)
	parent.add_child(second)
	var controls: Array[Control] = [first, second]
	parent.visible = false
	_focus.open(0, controls)
	_check(_focus.focused(0) == null, "controls under a hidden parent cannot take focus")
	parent.visible = true
	_tap(0, &"move_down")
	_check(_focus.focus_index(0) == 0, "they can once the parent is shown")
	parent.visible = false
	_tap(0, &"cast")
	_check(_count("activated", 0) == 0, "hiding the whole panel stops activation")
	holder.free()


func _test_open_needs_a_joined_device() -> void:
	_setup(2)
	_check(not _focus.open(3, _panel(3)), "a player with no device cannot open a panel")
	_check(not _focus.is_open(3) and not _input.is_captured(3), "nothing opened or captured")
	_check(_log.is_empty(), "no signals for the refused panel")
	_check(_focus.open(1, _panel(1)), "a joined player can")


func _test_reopen_replaces_the_panel() -> void:
	_setup()
	_focus.open(0, _panel(0))
	_log.clear()
	_check(_focus.open(0, _panel(0)), "opening an open panel works")
	_check(_log == [["closed", 0, -1], ["opened", 0, -1], ["focus", 0, 0]],
		"closed for the old panel, then opened for the new, got %s" % str(_log))
	_check(_input.is_captured(0), "the player stays captured")


func _test_close_then_reopen() -> void:
	_setup()
	_focus.open(0, _panel(0))
	_tap(0, &"move_down")
	_check(_focus.close(0), "close returns true for an open panel")
	_check(not _focus.close(0), "close returns false for a closed panel")
	_check(_focus.focused(0) == null, "no focus after close")
	_tap(0, &"cast")
	_check(_count("activated", 0) == 0, "a closed panel does not activate")
	_focus.open(0, _panel(0))
	_check(_focus.focus_index(0) == 0, "reopening starts at the first control")


func _test_never_takes_global_focus() -> void:
	_setup()
	var root := Control.new()
	get_root().add_child(root)
	var button := Button.new()
	root.add_child(button)
	var controls: Array[Control] = [button]
	_focus.open(0, controls)
	_check(get_root().gui_get_focus_owner() == null, "the global Godot focus is not used")
	root.free()


func _test_invalid_player_index() -> void:
	_setup()
	_check(not _focus.is_open(-1) and not _focus.is_open(4), "out of range players have no panel")
	_check(_focus.focused(7) == null and _focus.focus_index(-3) == -1, "out of range players have no focus")
	_focus.move_focus(9, 1)
	_focus.activate(9)
	_focus.cancel(9)
	_check(not _focus.close(9), "closing an out of range player is false")
	_check(_log.is_empty(), "out of range calls do nothing")
