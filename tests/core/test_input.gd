extends SceneTree
## Tests for core/input: join by button press, one device per player, the
## keyboard only as P1, gamepads for P1-P4, leave, a virtual device for every
## player index, and per-player state that never leaks between players.
##
## godot --headless --path . --script res://tests/core/test_input.gd

const InputManagerScript := preload("res://core/input/input_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const NO_DEVICE: int = InputManagerScript.NO_DEVICE
const NO_PLAYER: int = InputManagerScript.NO_PLAYER

var _failures: Array[String] = []
var _bus: Node
var _manager: Node
## Every device event as [name, player, device], in order.
var _log: Array = []


func _initialize() -> void:
	_test_actions_defined()
	_test_autoload_registered()
	_test_gamepads_join_in_order()
	_test_keyboard_is_player_one_only()
	_test_keyboard_blocked_by_gamepad_in_slot_zero()
	_test_one_device_per_player()
	_test_full_game_rejects_a_fifth()
	_test_leave_frees_the_slot()
	_test_leave_by_button()
	_test_unplugged_gamepad_leaves()
	_test_virtual_device_every_index()
	_test_virtual_device_slot_taken()
	_test_virtual_device_is_not_joinable_by_button()
	_test_virtual_send_needs_a_device()
	_test_move_from_keyboard()
	_test_move_from_gamepad_stick()
	_test_players_do_not_share_state()
	_test_just_pressed()
	_test_two_inputs_one_action()
	_test_bindings_route_as_documented()
	_test_input_map_has_documented_bindings()
	_test_press_frames_recorded()
	_test_leave_clears_held_actions()
	_test_join_press_is_not_a_dodge()
	_test_invalid_player_index()
	if _failures.is_empty():
		print("TEST OK: core/input")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _on_joined(player: int, device: int) -> void:
	_log.append(["joined", player, device])


func _on_left(player: int, device: int) -> void:
	_log.append(["left", player, device])


func _setup() -> void:
	_teardown()
	_bus = EventsScript.new()
	_manager = InputManagerScript.new()
	_manager.events = _bus
	_log.clear()
	_bus.device_joined.connect(_on_joined)
	_bus.device_left.connect(_on_left)


func _teardown() -> void:
	if _bus != null:
		_bus.free()
		_bus = null
	if _manager != null:
		_manager.free()
		_manager = null


# --- Event builders ---------------------------------------------------------

func _key(keycode: Key, pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
	return event


func _button(device: int, button: JoyButton, pressed: bool = true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = pressed
	return event


func _axis(device: int, axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	return event


## A gamepad presses A: the join button.
func _press_join(device: int) -> void:
	_manager.handle_event(_button(device, JOY_BUTTON_A))


# --- Tests ------------------------------------------------------------------

func _test_actions_defined() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down", &"dodge", &"cast", &"overlay", &"join", &"leave"]:
		_check(InputMap.has_action(action), "project.godot defines the action %s" % action)
	for action in InputManagerScript.ACTIONS:
		_check(InputMap.has_action(action), "the manager's action %s is defined in project.godot" % action)


func _test_autoload_registered() -> void:
	var path := str(ProjectSettings.get_setting("autoload/PlayerInput", ""))
	_check(path == "*res://core/input/input_manager.gd", "autoload PlayerInput is registered, got '%s'" % path)


func _test_gamepads_join_in_order() -> void:
	_setup()
	# Gamepad ids need not be 0..3 or in order.
	var pads: Array[int] = [2, 0, 5, 1]
	for i in 4:
		_press_join(pads[i])
		_check(_manager.device_of(i) == pads[i], "gamepad %d joined as player %d, got device %d" % [pads[i], i, _manager.device_of(i)])
		_check(_manager.player_of(pads[i]) == i, "player_of(gamepad %d) is %d" % [pads[i], i])
	_check(_manager.joined_count() == 4, "four gamepads make four players")
	_check(_log == [["joined", 0, 2], ["joined", 1, 0], ["joined", 2, 5], ["joined", 3, 1]],
		"device_joined carries player then device for every index, got %s" % [_log])


func _test_keyboard_is_player_one_only() -> void:
	_setup()
	_manager.handle_event(_key(KEY_ENTER))
	_check(_manager.device_of(0) == InputManagerScript.KEYBOARD, "the keyboard joins as player 0")
	for pad in 3:
		_press_join(pad)
		_check(_manager.device_of(pad + 1) == pad, "gamepad %d joins as player %d next to the keyboard" % [pad, pad + 1])
	_check(_manager.joined_count() == 4, "keyboard plus three gamepads make four players")
	# Another keyboard press does not join a second time.
	_manager.handle_event(_key(KEY_SPACE))
	_check(_manager.joined_count() == 4, "the keyboard cannot join twice")


func _test_keyboard_blocked_by_gamepad_in_slot_zero() -> void:
	_setup()
	_press_join(3)
	_manager.handle_event(_key(KEY_ENTER))
	_check(_manager.device_of(0) == 3, "a gamepad that joined first keeps player 0")
	_check(_manager.player_of(InputManagerScript.KEYBOARD) == NO_PLAYER, "the keyboard does not take P2-P4")
	_check(_manager.joined_count() == 1, "the keyboard press did not add a player")
	_manager.leave(0)
	_manager.handle_event(_key(KEY_ENTER))
	_check(_manager.device_of(0) == InputManagerScript.KEYBOARD, "the keyboard can take player 0 once it is free")


func _test_one_device_per_player() -> void:
	_setup()
	_press_join(4)
	_press_join(4)
	_check(_manager.joined_count() == 1, "pressing join twice on one gamepad adds one player")
	_check(_manager.join(4) == NO_PLAYER, "join() of a device that already joined returns NO_PLAYER")
	_check(_manager.join(NO_DEVICE) == NO_PLAYER, "join() of NO_DEVICE returns NO_PLAYER")


func _test_full_game_rejects_a_fifth() -> void:
	_setup()
	for pad in 4:
		_press_join(pad)
	_press_join(9)
	_check(_manager.joined_count() == 4, "a fifth gamepad does not join")
	_check(_manager.player_of(9) == NO_PLAYER, "the fifth gamepad has no player")
	_manager.handle_event(_key(KEY_ENTER))
	_check(_manager.player_of(InputManagerScript.KEYBOARD) == NO_PLAYER, "the keyboard does not join a full game")


func _test_leave_frees_the_slot() -> void:
	_setup()
	for pad in 4:
		_press_join(pad)
	_log.clear()
	_check(_manager.leave(1), "leave(1) reports a player left")
	_check(not _manager.is_joined(1), "slot 1 is free after leaving")
	_check(_manager.is_joined(0) and _manager.is_joined(2) and _manager.is_joined(3), "the other players stay")
	_check(not _manager.leave(1), "leaving an empty slot returns false")
	_check(_log == [["left", 1, 1]], "device_left carries player then device, got %s" % [_log])
	_press_join(7)
	_check(_manager.device_of(1) == 7, "the next gamepad takes the freed slot 1")


func _test_leave_by_button() -> void:
	_setup()
	for pad in 4:
		_press_join(pad)
	for player in 4:
		_manager.handle_event(_button(player, JOY_BUTTON_BACK))
		_check(not _manager.is_joined(player), "the leave button frees player %d" % player)
	_check(_manager.joined_count() == 0, "everybody can leave")
	_setup()
	_manager.handle_event(_key(KEY_ENTER))
	_manager.handle_event(_key(KEY_BACKSPACE))
	_check(not _manager.is_joined(0), "Backspace makes the keyboard player leave")


func _test_unplugged_gamepad_leaves() -> void:
	_setup()
	for pad in 4:
		_press_join(pad)
	_manager._on_joy_connection_changed(2, false)
	_check(not _manager.is_joined(2) and _manager.joined_count() == 3, "an unplugged gamepad frees its player")
	_manager._on_joy_connection_changed(8, false)
	_check(_manager.joined_count() == 3, "unplugging a gamepad that never joined changes nothing")
	_manager._on_joy_connection_changed(2, true)
	_check(_manager.joined_count() == 3, "plugging in a gamepad does not join it without a button press")


func _test_virtual_device_every_index() -> void:
	_setup()
	for player in 4:
		var device: int = _manager.add_virtual_device(player)
		_check(device == InputManagerScript.virtual_device_id(player), "virtual device of player %d has its id" % player)
		_check(InputManagerScript.is_virtual(device), "device %d is virtual" % device)
		_check(_manager.device_of(player) == device, "player %d owns its virtual device" % player)
		_check(_manager.player_of(device) == player, "player_of(virtual %d) is %d" % [device, player])
	_check(_log == [["joined", 0, 1000], ["joined", 1, 1001], ["joined", 2, 1002], ["joined", 3, 1003]],
		"a virtual device announces device_joined for every index, got %s" % [_log])
	# Each virtual device drives only its own player, through the real path.
	for player in 4:
		_manager.send_virtual(player, &"move_right")
		for other in 4:
			var expected: Vector2 = Vector2.RIGHT if other <= player else Vector2.ZERO
			_check(_manager.get_move(other) == expected, "after virtual move from %d, player %d moves %s, got %s" % [player, other, expected, _manager.get_move(other)])
	for player in 4:
		_manager.send_virtual(player, &"move_right", 0.0)
		_manager.send_virtual(player, &"cast")
		_check(_manager.is_action_pressed(player, &"cast"), "virtual cast reaches player %d" % player)
		_check(_manager.get_move(player) == Vector2.ZERO, "virtual release stops player %d" % player)
	_check(_manager.leave(2), "a virtual device can leave")
	_check(not _manager.is_joined(2), "its slot is free")


func _test_virtual_device_slot_taken() -> void:
	_setup()
	_press_join(0)
	_check(_manager.add_virtual_device(0) == NO_DEVICE, "a virtual device cannot take a used slot")
	_check(_manager.add_virtual_device(4) == NO_DEVICE, "a virtual device for index 4 is refused")
	_check(_manager.add_virtual_device(-1) == NO_DEVICE, "a virtual device for index -1 is refused")
	_check(_manager.device_of(0) == 0, "the real device keeps its slot")
	_check(_manager.add_virtual_device(3) == 1003, "a bot can take a free slot beside a real player")


func _test_virtual_device_is_not_joinable_by_button() -> void:
	_setup()
	var event := InputEventAction.new()
	event.device = InputManagerScript.virtual_device_id(0)
	event.action = &"join"
	event.pressed = true
	_manager.handle_event(event)
	_check(_manager.joined_count() == 0, "a virtual device joins only through add_virtual_device")
	_check(_manager.join(InputManagerScript.virtual_device_id(1)) == NO_PLAYER, "join() refuses virtual ids")


func _test_virtual_send_needs_a_device() -> void:
	_setup()
	_manager.send_virtual(0, &"cast")
	_check(not _manager.is_action_pressed(0, &"cast"), "a virtual send without a virtual device does nothing")
	_press_join(0)
	_manager.send_virtual(0, &"cast")
	_check(not _manager.is_action_pressed(0, &"cast"), "a virtual send cannot drive a real player's slot")


func _test_move_from_keyboard() -> void:
	_setup()
	_manager.handle_event(_key(KEY_ENTER))
	_manager.handle_event(_key(KEY_D))
	_check(_manager.get_move(0) == Vector2.RIGHT, "D moves right")
	_manager.handle_event(_key(KEY_S))
	var diagonal: Vector2 = _manager.get_move(0)
	_check(is_equal_approx(diagonal.length(), 1.0), "a diagonal has length 1, got %s" % diagonal.length())
	_manager.handle_event(_key(KEY_D, false))
	_manager.handle_event(_key(KEY_S, false))
	_check(_manager.get_move(0) == Vector2.ZERO, "releasing the keys stops")
	_manager.handle_event(_key(KEY_W))
	_manager.handle_event(_key(KEY_A))
	_check(_manager.get_move(0).x < 0.0 and _manager.get_move(0).y < 0.0, "W and A move up and left")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_manager.handle_event(click)
	_check(_manager.is_action_pressed(0, &"cast"), "the left mouse button casts")


func _test_move_from_gamepad_stick() -> void:
	_setup()
	for pad in 2:
		_press_join(pad)
	_manager.handle_event(_axis(1, JOY_AXIS_LEFT_X, -1.0))
	_manager.handle_event(_axis(1, JOY_AXIS_LEFT_Y, 1.0))
	var move: Vector2 = _manager.get_move(1)
	_check(move.x < 0.0 and move.y > 0.0, "the stick moves down-left, got %s" % move)
	_check(_manager.get_move(0) == Vector2.ZERO, "player 0 does not move from player 1's stick")
	_manager.handle_event(_axis(1, JOY_AXIS_LEFT_X, 0.1))
	_manager.handle_event(_axis(1, JOY_AXIS_LEFT_Y, -0.1))
	_check(_manager.get_move(1) == Vector2.ZERO, "values inside the deadzone are zero")
	_manager.handle_event(_axis(0, JOY_AXIS_TRIGGER_RIGHT, 1.0))
	_check(_manager.is_action_pressed(0, &"cast"), "the right trigger casts")
	_manager.handle_event(_axis(0, JOY_AXIS_TRIGGER_RIGHT, 0.0))
	_check(not _manager.is_action_pressed(0, &"cast"), "releasing the trigger stops the cast")


func _test_players_do_not_share_state() -> void:
	_setup()
	for pad in 4:
		_press_join(pad)
	var actions: Array[JoyButton] = [JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_X]
	var names: Array[StringName] = [&"dodge", &"cast", &"overlay", &"cast"]
	for player in 4:
		_manager.handle_event(_button(player, actions[player]))
	for player in 4:
		for action in InputManagerScript.ACTIONS:
			var expected: bool = action == names[player]
			_check(_manager.is_action_pressed(player, action) == expected,
				"player %d: %s pressed is %s" % [player, action, expected])


func _test_just_pressed() -> void:
	_setup()
	for pad in 4:
		_press_join(pad)
	for player in 4:
		_check(not _manager.is_action_just_pressed(player, &"dodge"), "player %d has no dodge before pressing" % player)
	_manager.handle_event(_button(2, JOY_BUTTON_B))
	_check(_manager.is_action_just_pressed(2, &"dodge"), "player 2 just pressed dodge this frame")
	_check(not _manager.is_action_just_pressed(1, &"dodge"), "player 1 did not")
	_check(not _manager.is_action_just_pressed(2, &"cast"), "player 2 did not press cast")


func _test_two_inputs_one_action() -> void:
	_setup()
	_manager.handle_event(_key(KEY_ENTER))
	_manager.handle_event(_key(KEY_A))
	_manager.handle_event(_key(KEY_LEFT))
	_manager.handle_event(_key(KEY_LEFT, false))
	_check(_manager.get_move(0) == Vector2.LEFT, "A still moves left after Left is released")
	_manager.handle_event(_key(KEY_A, false))
	_check(_manager.get_move(0) == Vector2.ZERO, "releasing the last key stops")
	_manager.handle_event(_key(KEY_W))
	_manager.handle_event(_key(KEY_UP))
	_manager.handle_event(_key(KEY_W, false))
	_check(_manager.get_move(0) == Vector2.UP, "Up still moves up after W is released")

	_press_join(1)
	_press_join(2)
	_manager.handle_event(_button(2, JOY_BUTTON_DPAD_LEFT))
	_manager.handle_event(_axis(2, JOY_AXIS_LEFT_X, 0.0))
	_check(_manager.get_move(2) == Vector2.LEFT, "a stick at rest does not cancel the held d-pad")
	_manager.handle_event(_axis(2, JOY_AXIS_LEFT_X, -1.0))
	_manager.handle_event(_button(2, JOY_BUTTON_DPAD_LEFT, false))
	_check(_manager.get_move(2) == Vector2.LEFT, "the stick still moves left after the d-pad is released")
	_manager.handle_event(_axis(2, JOY_AXIS_LEFT_X, 0.0))
	_check(_manager.get_move(2) == Vector2.ZERO, "everything released stops")

	_manager.handle_event(_axis(2, JOY_AXIS_TRIGGER_RIGHT, 1.0))
	_manager.handle_event(_button(2, JOY_BUTTON_X))
	_manager.handle_event(_button(2, JOY_BUTTON_X, false))
	_check(_manager.is_action_pressed(2, &"cast"), "the trigger still casts after X is released")
	_manager.handle_event(_axis(2, JOY_AXIS_TRIGGER_RIGHT, 0.0))
	_check(not _manager.is_action_pressed(2, &"cast"), "the cast stops when the last input is released")


func _test_bindings_route_as_documented() -> void:
	_setup()
	_manager.handle_event(_button(0, JOY_BUTTON_START))
	_check(_manager.is_joined(0), "Start joins a gamepad")
	var dpad: Dictionary = {
		JOY_BUTTON_DPAD_LEFT: Vector2.LEFT, JOY_BUTTON_DPAD_RIGHT: Vector2.RIGHT,
		JOY_BUTTON_DPAD_UP: Vector2.UP, JOY_BUTTON_DPAD_DOWN: Vector2.DOWN,
	}
	for button: JoyButton in dpad:
		_manager.handle_event(_button(0, button))
		_check(_manager.get_move(0) == dpad[button], "d-pad button %d moves %s" % [button, dpad[button]])
		_manager.handle_event(_button(0, button, false))
	var buttons: Dictionary = {
		JOY_BUTTON_B: &"dodge", JOY_BUTTON_X: &"cast", JOY_BUTTON_RIGHT_SHOULDER: &"cast", JOY_BUTTON_Y: &"overlay",
	}
	for button: JoyButton in buttons:
		_manager.handle_event(_button(0, button))
		_check(_manager.is_action_pressed(0, buttons[button]), "gamepad button %d is %s" % [button, buttons[button]])
		_manager.handle_event(_button(0, button, false))
		_check(not _manager.is_action_pressed(0, buttons[button]), "releasing gamepad button %d stops %s" % [button, buttons[button]])
	_manager.handle_event(_button(0, JOY_BUTTON_BACK))
	_check(not _manager.is_joined(0), "Back leaves")

	_manager.handle_event(_key(KEY_ENTER))
	var keys: Dictionary = {
		KEY_LEFT: &"move_left", KEY_RIGHT: &"move_right", KEY_UP: &"move_up", KEY_DOWN: &"move_down",
		KEY_SHIFT: &"dodge", KEY_SPACE: &"dodge", KEY_TAB: &"overlay", KEY_E: &"overlay", KEY_J: &"cast",
	}
	for key: Key in keys:
		_manager.handle_event(_key(key))
		_check(_manager.is_action_pressed(0, keys[key]), "key %d is %s" % [key, keys[key]])
		_manager.handle_event(_key(key, false))
		_check(not _manager.is_action_pressed(0, keys[key]), "releasing key %d stops %s" % [key, keys[key]])
	_manager.handle_event(_key(KEY_BACKSPACE))
	_check(not _manager.is_joined(0), "Backspace leaves")


func _test_input_map_has_documented_bindings() -> void:
	var keys: Dictionary = {
		&"move_left": [KEY_A, KEY_LEFT], &"move_right": [KEY_D, KEY_RIGHT],
		&"move_up": [KEY_W, KEY_UP], &"move_down": [KEY_S, KEY_DOWN],
		&"dodge": [KEY_SPACE, KEY_SHIFT], &"cast": [KEY_J], &"overlay": [KEY_TAB, KEY_E],
		&"join": [KEY_ENTER, KEY_SPACE], &"leave": [KEY_BACKSPACE],
	}
	for action: StringName in keys:
		for key: Key in keys[action]:
			_check(InputMap.action_has_event(action, _key(key)), "%s is bound to key %d" % [action, key])
	var pad: Dictionary = {
		&"move_left": JOY_BUTTON_DPAD_LEFT, &"move_right": JOY_BUTTON_DPAD_RIGHT,
		&"move_up": JOY_BUTTON_DPAD_UP, &"move_down": JOY_BUTTON_DPAD_DOWN,
		&"dodge": JOY_BUTTON_B, &"cast": JOY_BUTTON_X, &"overlay": JOY_BUTTON_Y,
		&"join": JOY_BUTTON_A, &"leave": JOY_BUTTON_BACK,
	}
	for action: StringName in pad:
		_check(InputMap.action_has_event(action, _button(0, pad[action])), "%s is bound to gamepad button %d" % [action, pad[action]])
	_check(InputMap.action_has_event(&"join", _button(0, JOY_BUTTON_START)), "join is bound to Start")
	_check(InputMap.action_has_event(&"cast", _button(0, JOY_BUTTON_RIGHT_SHOULDER)), "cast is bound to the right shoulder")


func _test_press_frames_recorded() -> void:
	_setup()
	_manager.add_virtual_device(0)
	_manager.send_virtual(0, &"dodge")
	_check(_manager._pressed_physics[0][&"dodge"] == Engine.get_physics_frames(), "a press is stamped with the physics frame")
	_check(_manager._pressed_process[0][&"dodge"] == Engine.get_process_frames(), "a press is stamped with the process frame")
	_check(_manager.is_action_just_pressed(0, &"dodge"), "the press counts as just pressed outside a physics step")


func _test_leave_clears_held_actions() -> void:
	_setup()
	_manager.add_virtual_device(1)
	_manager.send_virtual(1, &"move_down")
	_manager.send_virtual(1, &"cast")
	_manager.leave(1)
	_check(_manager.get_move(1) == Vector2.ZERO and not _manager.is_action_pressed(1, &"cast"),
		"a player who leaves holding a button does not keep moving or casting")


func _test_join_press_is_not_a_dodge() -> void:
	_setup()
	_manager.handle_event(_key(KEY_SPACE))
	_check(_manager.is_joined(0), "Space joins the keyboard")
	_check(not _manager.is_action_pressed(0, &"dodge"), "the press that joined is not also a dodge")
	_manager.handle_event(_key(KEY_SPACE, false))
	_manager.handle_event(_key(KEY_SPACE))
	_check(_manager.is_action_pressed(0, &"dodge"), "Space dodges once joined")


func _test_invalid_player_index() -> void:
	_setup()
	for player: int in [-1, 4, 99]:
		_check(_manager.device_of(player) == NO_DEVICE, "device_of(%d) is NO_DEVICE" % player)
		_check(not _manager.is_joined(player), "player %d is not joined" % player)
		_check(_manager.get_move(player) == Vector2.ZERO, "player %d has no move" % player)
		_check(not _manager.is_action_pressed(player, &"cast"), "player %d has no cast" % player)
		_check(not _manager.is_action_just_pressed(player, &"cast"), "player %d has no just-pressed cast" % player)
		_check(not _manager.leave(player), "player %d cannot leave" % player)
	_teardown()
