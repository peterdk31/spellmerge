extends "res://tests/support/suite.gd"
## Tests for core/input, one rule per test, each on a manager and a bus of its own (`before_each`;
## the PlayerInput autoload is never touched): join by button press, one device per player, the
## keyboard only on the machine's first seat (P1 on a machine of its own) and a provisional one
## taken over by a pad, gamepads for P1-P4, seats given by another machine (`join_asker`,
## `join_as`) or told (`set_own_seats`), leave, an unplugged pad that keeps its seat and waits, a
## virtual device for every player index, moves, aims, the menu's sticks, rumble, mouse aim, the
## bindings, and per-player state that never leaks between players.

const InputManagerScript := preload("res://core/input/input_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const NO_DEVICE: int = InputManagerScript.NO_DEVICE
const NO_PLAYER: int = InputManagerScript.NO_PLAYER
const KEYBOARD: int = InputManagerScript.KEYBOARD

var bus: EventsScript
var manager: InputManagerScript
## Every device event as [name, player, device], in order.
var joins: Array = []
## Every `pad_wait_requested` as [player, on], in order.
var waits: Array = []
## The devices `join_asker` was called with (`_ask_for_seats`).
var asked: Array[int] = []
## Every rumble as [device, weak, strong, seconds] (`_rumble_rig`).
var shaken: Array = []


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	manager = own(InputManagerScript.new()) as InputManagerScript
	manager.events = bus
	joins = []
	waits = []
	asked = []
	shaken = []
	bus.device_joined.connect(func(player: int, device: int) -> void: joins.append(["joined", player, device]))
	bus.device_left.connect(func(player: int, device: int) -> void: joins.append(["left", player, device]))
	bus.pad_wait_requested.connect(func(player: int, on: int) -> void: waits.append([player, on]))


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


func _click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	return click


func _mouse_move(relative: Vector2) -> InputEventMouseMotion:
	var move := InputEventMouseMotion.new()
	move.relative = relative
	return move


## A gamepad presses A: the join button.
func _press_join(device: int) -> void:
	manager.handle_event(_button(device, JOY_BUTTON_A))


func _join_pads(count: int) -> void:
	for pad in count:
		_press_join(pad)


## The keyboard joins with its own key press.
func _join_keyboard() -> void:
	manager.handle_event(_key(KEY_ENTER))


# --- The project's actions --------------------------------------------------

func test_the_project_defines_the_game_actions() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down", &"staff_1", &"staff_2", &"staff_3", &"staff_4", &"accept", &"back", &"alternate", &"pause", &"join"]:
		check(InputMap.has_action(action), "project.godot defines the action %s" % action)


func test_there_is_no_leave_action() -> void:
	# Items I2: the pause menu's "Leave game" took its place (Select is the inventory's).
	check(not InputMap.has_action(&"leave"), "no leave action")


func test_every_action_of_the_manager_is_defined() -> void:
	for action in InputManagerScript.ACTIONS:
		check(InputMap.has_action(action), "the manager's action %s is defined in project.godot" % action)


func test_the_player_input_autoload_is_registered() -> void:
	var path: String = str(ProjectSettings.get_setting("autoload/PlayerInput", ""))
	check_equal(path, "*res://core/input/input_manager.gd", "autoload PlayerInput is registered")


func test_each_action_is_bound_to_its_documented_keys() -> void:
	var keys: Dictionary = {
		&"move_left": [KEY_A, KEY_LEFT], &"move_right": [KEY_D, KEY_RIGHT],
		&"move_up": [KEY_W, KEY_UP], &"move_down": [KEY_S, KEY_DOWN],
		&"staff_1": [KEY_SPACE, KEY_SHIFT], &"staff_2": [KEY_J], &"staff_3": [KEY_K], &"staff_4": [KEY_Q, KEY_L],
		&"accept": [KEY_ENTER, KEY_SPACE], &"back": [KEY_E], &"inventory": [KEY_TAB], &"alternate": [KEY_X, KEY_DELETE],
		&"pause": [KEY_ESCAPE],
		&"join": [KEY_ENTER, KEY_SPACE],
	}
	for action: StringName in keys:
		for key: Key in keys[action]:
			check(InputMap.action_has_event(action, _key(key)), "%s is bound to key %d" % [action, key])


func test_each_action_is_bound_to_its_documented_gamepad_buttons() -> void:
	var pad: Dictionary = {
		&"move_left": JOY_BUTTON_DPAD_LEFT, &"move_right": JOY_BUTTON_DPAD_RIGHT,
		&"move_up": JOY_BUTTON_DPAD_UP, &"move_down": JOY_BUTTON_DPAD_DOWN,
		&"staff_1": JOY_BUTTON_RIGHT_SHOULDER, &"staff_3": JOY_BUTTON_LEFT_SHOULDER,
		&"accept": JOY_BUTTON_A, &"back": JOY_BUTTON_B, &"alternate": JOY_BUTTON_X, &"pause": JOY_BUTTON_START,
		&"join": JOY_BUTTON_A, &"inventory": JOY_BUTTON_BACK,
	}
	for action: StringName in pad:
		check(InputMap.action_has_event(action, _button(0, pad[action])), "%s is bound to gamepad button %d" % [action, pad[action]])
	check(InputMap.action_has_event(&"join", _button(0, JOY_BUTTON_START)), "join is bound to Start")


func test_tab_is_not_back() -> void:
	check(not InputMap.action_has_event(&"back", _key(KEY_TAB)), "Tab is the inventory's, no longer the builder's (items I7)")


func test_a_casts_no_staff() -> void:
	# The triggers are axes; the manager routes them itself (RT staff 2, LT staff 4).
	check(not InputMap.action_has_event(&"staff_1", _button(0, JOY_BUTTON_A)), "A no longer casts a staff")


# --- Joining ----------------------------------------------------------------

func test_gamepads_join_in_press_order_whatever_their_ids() -> void:
	# Gamepad ids need not be 0..3 or in order.
	var pads: Array[int] = [2, 0, 5, 1]
	for i in 4:
		_press_join(pads[i])
		check(manager.device_of(i) == pads[i], "gamepad %d joined as player %d, got device %d" % [pads[i], i, manager.device_of(i)])
		check(manager.player_of(pads[i]) == i, "player_of(gamepad %d) is %d" % [pads[i], i])


func test_four_gamepads_make_four_players() -> void:
	_join_pads(4)
	check_equal(manager.joined_count(), 4, "four gamepads make four players")


func test_device_joined_carries_player_then_device() -> void:
	for pad: int in [2, 0, 5, 1]:
		_press_join(pad)
	check_equal(joins, [["joined", 0, 2], ["joined", 1, 0], ["joined", 2, 5], ["joined", 3, 1]], "device_joined carries player then device for every index")


func test_the_keyboard_joins_as_p1() -> void:
	_join_keyboard()
	check_equal(manager.device_of(0), KEYBOARD, "the keyboard joins as player 0")


func test_gamepads_join_beside_the_keyboard() -> void:
	_join_keyboard()
	for pad in 3:
		_press_join(pad)
		check(manager.device_of(pad + 1) == pad, "gamepad %d joins as player %d next to the keyboard" % [pad, pad + 1])
	check_equal(manager.joined_count(), 4, "keyboard plus three gamepads make four players")


func test_the_keyboard_cannot_join_twice() -> void:
	_join_keyboard()
	manager.handle_event(_key(KEY_SPACE))
	check_equal(manager.joined_count(), 1, "another keyboard press does not join a second time")


func test_the_keyboard_takes_no_seat_but_p1() -> void:
	_press_join(3)
	_join_keyboard()
	check_equal(manager.device_of(0), 3, "a gamepad that joined first keeps player 0")
	check_equal(manager.player_of(KEYBOARD), NO_PLAYER, "the keyboard does not take P2-P4")
	check_equal(manager.joined_count(), 1, "the keyboard press did not add a player")


func test_the_keyboard_takes_p1_once_it_is_free() -> void:
	_press_join(3)
	manager.leave(0)
	_join_keyboard()
	check_equal(manager.device_of(0), KEYBOARD, "the keyboard can take player 0 once it is free")


func test_join_twice_on_one_gamepad_adds_one_player() -> void:
	_press_join(4)
	_press_join(4)
	check_equal(manager.joined_count(), 1, "pressing join twice on one gamepad adds one player")


func test_join_of_a_joined_device_is_refused() -> void:
	_press_join(4)
	check_equal(manager.join(4), NO_PLAYER, "join() of a device that already joined returns NO_PLAYER")


func test_join_of_no_device_is_refused() -> void:
	check_equal(manager.join(NO_DEVICE), NO_PLAYER, "join() of NO_DEVICE returns NO_PLAYER")


func test_a_fifth_gamepad_does_not_join() -> void:
	_join_pads(4)
	_press_join(9)
	check_equal(manager.joined_count(), 4, "a fifth gamepad does not join")
	check_equal(manager.player_of(9), NO_PLAYER, "the fifth gamepad has no player")


func test_the_keyboard_does_not_join_a_full_game() -> void:
	_join_pads(4)
	_join_keyboard()
	check_equal(manager.player_of(KEYBOARD), NO_PLAYER, "the keyboard does not join a full game")


func test_the_press_that_joins_does_not_cast() -> void:
	manager.handle_event(_key(KEY_SPACE))
	check(manager.is_joined(0), "Space joins the keyboard")
	check(not manager.is_action_pressed(0, &"staff_1"), "the press that joined does not also cast staff 1")


func test_space_casts_staff_1_once_joined() -> void:
	manager.handle_event(_key(KEY_SPACE))
	manager.handle_event(_key(KEY_SPACE, false))
	manager.handle_event(_key(KEY_SPACE))
	check(manager.is_action_pressed(0, &"staff_1"), "Space casts staff 1 once joined")


func test_start_joins_a_gamepad() -> void:
	manager.handle_event(_button(0, JOY_BUTTON_START))
	check(manager.is_joined(0), "Start joins a gamepad")


# --- A provisional keyboard -------------------------------------------------
# One player with a controller on the web clicks Play with the mouse: the keyboard joins P1
# provisionally, and the pad's first A takes P1 over (owner, 2026-10-27).

## The click on Play seats the keyboard provisionally; pad 0 (its stick at rest first) takes over.
func _take_over_the_keyboard() -> void:
	manager.join(KEYBOARD, true)
	manager.handle_event(_axis(0, JOY_AXIS_LEFT_X, 0.0))
	_press_join(0)


func test_a_click_on_play_joins_the_keyboard_provisionally() -> void:
	check_equal(manager.join(KEYBOARD, true), 0, "the click on Play joins the keyboard as P1")
	check(manager.is_keyboard_provisional(), "provisionally")


func test_a_gamepad_takes_p1_from_a_provisional_keyboard() -> void:
	_take_over_the_keyboard()
	check_equal(manager.device_of(0), 0, "the gamepad is P1 now")
	check_equal(manager.player_of(KEYBOARD), NO_PLAYER, "the keyboard is out")
	check_equal(manager.joined_count(), 1, "still one player")


func test_a_takeover_changes_p1s_glyphs() -> void:
	var glyphs: Array[int] = []
	manager.glyph_kind_changed.connect(func(player: int) -> void: glyphs.append(player))
	_take_over_the_keyboard()
	check(not glyphs.is_empty() and glyphs.back() == 0, "P1's glyphs change to the pad's: %s" % [glyphs])


func test_a_takeover_neither_leaves_nor_joins() -> void:
	_take_over_the_keyboard()
	check_equal(joins, [["joined", 0, KEYBOARD]], "no leave or join: the wizard stays")


func test_the_gamepad_that_took_over_moves_p1() -> void:
	_take_over_the_keyboard()
	manager.handle_event(_axis(0, JOY_AXIS_LEFT_X, 1.0))
	check(manager.get_move(0).x > 0.5, "the pad moves P1")


func test_a_second_pad_after_a_takeover_is_p2() -> void:
	_take_over_the_keyboard()
	_press_join(1)
	check_equal(manager.device_of(1), 1, "a second pad is P2 as usual")


func test_the_keyboard_cannot_join_after_a_takeover() -> void:
	# The keyboard can still join later, as anyone else would: P1 is taken, so it cannot.
	_take_over_the_keyboard()
	_press_join(1)
	_join_keyboard()
	check_equal(manager.player_of(KEYBOARD), NO_PLAYER, "the keyboard only ever takes P1")


func test_a_key_press_makes_a_provisional_keyboard_for_real() -> void:
	manager.join(KEYBOARD, true)
	manager.handle_event(_key(KEY_W))
	manager.handle_event(_key(KEY_W, false))
	check(not manager.is_keyboard_provisional(), "a key press makes the keyboard P1 for real")


func test_a_pad_joins_as_p2_beside_a_used_keyboard() -> void:
	manager.join(KEYBOARD, true)
	manager.handle_event(_key(KEY_W))
	manager.handle_event(_key(KEY_W, false))
	_press_join(0)
	check(manager.device_of(0) == KEYBOARD and manager.device_of(1) == 0, "the pad joins as P2")


func test_a_keyboard_joined_by_its_own_key_is_never_provisional() -> void:
	_join_keyboard()
	check(not manager.is_keyboard_provisional(), "a key join is for real")


func test_a_pad_joins_as_p2_beside_a_keyboard_joined_by_key() -> void:
	_join_keyboard()
	_press_join(0)
	check_equal(manager.device_of(1), 0, "the pad is P2")


# --- Seats another machine gives out (online lobby L2) ----------------------
# With `join_asker` set, a device that would join is not seated here; whoever set it is called with
# the device and seats it where it says with `join_as`. Leaving is the device's own, as ever.

func _ask_for_seats() -> void:
	manager.join_asker = func(device: int) -> void: asked.append(device)


func test_each_device_that_presses_join_is_asked_for() -> void:
	_ask_for_seats()
	_press_join(4)
	_join_keyboard()
	check_equal(asked, [4, KEYBOARD] as Array[int], "each device that presses join is asked for")


func test_a_machine_whose_seats_are_given_seats_nobody_itself() -> void:
	_ask_for_seats()
	_press_join(4)
	_join_keyboard()
	check(manager.joined_count() == 0 and joins.is_empty(), "nobody is seated here")


func test_a_join_by_call_is_asked_for_too() -> void:
	_ask_for_seats()
	check_equal(manager.join(7), NO_PLAYER, "a join by call seats nobody")
	check_equal(asked, [7] as Array[int], "and is asked for")


func test_join_as_seats_a_pad_where_it_is_told() -> void:
	_ask_for_seats()
	check(manager.join_as(4, 2) == 2 and manager.device_of(2) == 4, "seated where it is told: the pad is P3")


func test_join_as_seats_the_keyboard_for_real() -> void:
	_ask_for_seats()
	check(manager.join_as(KEYBOARD, 3) == 3 and not manager.is_keyboard_provisional(), "the keyboard P4, for real")


func test_join_as_announces_each_join() -> void:
	_ask_for_seats()
	manager.join_as(4, 2)
	manager.join_as(KEYBOARD, 3)
	check_equal(joins, [["joined", 2, 4], ["joined", 3, KEYBOARD]], "joined as told")


func test_join_as_refuses_a_device_that_has_a_seat() -> void:
	_ask_for_seats()
	manager.join_as(4, 2)
	check_equal(manager.join_as(4, 0), NO_PLAYER, "a device that has a seat is not seated twice")


func test_join_as_refuses_a_taken_seat() -> void:
	_ask_for_seats()
	manager.join_as(4, 2)
	check(manager.join_as(9, 2) == NO_PLAYER and manager.device_of(2) == 4, "nor on a seat that is taken")


func test_join_as_refuses_outside_the_four_a_virtual_device_or_none() -> void:
	_ask_for_seats()
	check_equal(manager.join_as(9, 4), NO_PLAYER, "not outside the four")
	check_equal(manager.join_as(InputManagerScript.virtual_device_id(0), 0), NO_PLAYER, "not a virtual device")
	check_equal(manager.join_as(NO_DEVICE, 0), NO_PLAYER, "not no device")


func test_the_keyboard_moves_the_seat_it_was_given() -> void:
	_ask_for_seats()
	manager.join_as(KEYBOARD, 3)
	manager.handle_event(_key(KEY_W))
	check(manager.get_move(3).y < -0.5, "the keyboard moves the seat it was given")


func test_a_device_that_plays_asks_no_more() -> void:
	_ask_for_seats()
	manager.join_as(4, 2)
	_press_join(4)
	check(asked.is_empty(), "a device that plays asks no more: %s" % [asked])


func test_a_virtual_device_takes_its_slot_while_seats_are_given() -> void:
	_ask_for_seats()
	check(manager.add_virtual_device(0) != NO_DEVICE, "a virtual device takes its slot as ever (the other machine's seat)")


func test_with_nobody_giving_seats_a_device_seats_itself_again() -> void:
	_ask_for_seats()
	manager.join_as(4, 2)
	manager.add_virtual_device(0)
	manager.join_asker = Callable()
	_press_join(6)
	check_equal(manager.device_of(1), 6, "with nobody giving seats, a device seats itself again: the lowest free")


# --- A machine told its seats (netcode spike S4) ----------------------------

func test_set_own_seats_says_which_seats_are_this_machines() -> void:
	check(manager.set_own_seats(1, 1), "P2 alone is this machine's")
	check(manager.own_first_seat() == 1 and manager.own_seat_count() == 1, "and it says so")


func test_own_seats_outside_the_four_are_refused() -> void:
	manager.set_own_seats(2, 2)
	check(not manager.set_own_seats(3, 2), "seats past P4 are refused")
	check(not manager.set_own_seats(-1, 1), "seats before P1 are refused")
	check_equal(manager.own_first_seat(), 2, "a refused call keeps the seats")


func test_the_keyboard_joins_on_the_machines_first_seat() -> void:
	manager.set_own_seats(1, 1)
	_join_keyboard()
	check(manager.device_of(1) == KEYBOARD and not manager.is_joined(0), "the keyboard joins as P2, not P1")


func test_a_gamepad_finds_no_seat_when_the_machines_seats_are_full() -> void:
	manager.set_own_seats(1, 1)
	_join_keyboard()
	_press_join(0)
	check(manager.player_of(0) == NO_PLAYER and manager.joined_count() == 1, "a gamepad finds no seat left")


func test_the_keyboard_moves_the_machines_seat() -> void:
	manager.set_own_seats(1, 1)
	_join_keyboard()
	manager.handle_event(_key(KEY_W))
	check(manager.get_move(1).y < -0.5 and manager.get_move(0) == Vector2.ZERO, "the keyboard moves P2")


func test_a_virtual_device_takes_another_machines_seat() -> void:
	manager.set_own_seats(1, 1)
	_join_keyboard()
	check(manager.add_virtual_device(0) != NO_DEVICE, "a virtual device still takes any free slot (the other machine's seat)")
	check_equal(joins, [["joined", 1, KEYBOARD], ["joined", 0, InputManagerScript.virtual_device_id(0)]], "joined as told")


func test_a_gamepad_joins_on_the_machines_first_seat() -> void:
	manager.set_own_seats(1, 1)
	_press_join(3)
	check_equal(manager.device_of(1), 3, "a gamepad joins as P2")


func test_the_keyboard_finds_the_machines_seat_taken_by_a_gamepad() -> void:
	manager.set_own_seats(1, 1)
	_press_join(3)
	_join_keyboard()
	check_equal(manager.player_of(KEYBOARD), NO_PLAYER, "the keyboard finds its seat taken")


func test_the_keyboard_takes_only_the_machines_first_seat() -> void:
	# Two seats from P3: the keyboard the first, a gamepad the next.
	manager.set_own_seats(2, 2)
	_press_join(0)
	_join_keyboard()
	_press_join(1)
	check(manager.device_of(2) == 0 and manager.device_of(3) == 1 and manager.joined_count() == 2, "gamepads take P3 and P4; the keyboard, which takes only the first, stays out")


# The mouse click that asked for the run seats the keyboard provisionally on this machine's first
# seat, wherever that is, and the first gamepad takes that seat over.

func test_a_provisional_keyboard_holds_the_machines_first_seat() -> void:
	manager.set_own_seats(1, 1)
	check(manager.join(KEYBOARD, true) == 1 and manager.is_keyboard_provisional(), "the keyboard holds P2 provisionally")


func test_a_gamepad_takes_over_a_provisional_keyboard_on_the_machines_seat() -> void:
	manager.set_own_seats(1, 1)
	manager.join(KEYBOARD, true)
	_press_join(0)
	check(manager.device_of(1) == 0 and manager.player_of(KEYBOARD) == NO_PLAYER, "the gamepad is P2 now, the keyboard out")
	check(not manager.is_joined(0) and manager.joined_count() == 1, "P1 was never touched")
	check_equal(joins, [["joined", 1, KEYBOARD]], "no leave or join: the wizard stays")


func test_the_gamepad_that_took_over_moves_the_machines_seat() -> void:
	manager.set_own_seats(1, 1)
	manager.join(KEYBOARD, true)
	_press_join(0)
	manager.handle_event(_axis(0, JOY_AXIS_LEFT_X, 1.0))
	check(manager.get_move(1).x > 0.5, "the pad moves P2")


# A machine told its seats while devices are joined: a device whose seat is still the machine's
# keeps it (its wizard is not touched), one outside leaves and takes the place it would joining
# now, or none. With `reseat` everyone is seated anew (a menu's reset), a provisional keyboard
# still provisional.

## The keyboard joined on P1 holding W, then the machine told P2 alone is its own.
func _keyboard_moved_to_p2() -> bool:
	_join_keyboard()
	manager.handle_event(_key(KEY_W))
	joins.clear()
	return manager.set_own_seats(1, 1)


func test_a_device_outside_the_new_seats_moves_into_them() -> void:
	check(_keyboard_moved_to_p2(), "P2 alone")
	check(manager.device_of(1) == KEYBOARD and manager.joined_count() == 1, "the keyboard, outside its machine's seats, moved to P2")


func test_a_moved_device_holds_nothing_it_held_before() -> void:
	_keyboard_moved_to_p2()
	check_equal(manager.get_move(1), Vector2.ZERO, "it holds nothing it held before")


func test_a_moved_device_leaves_and_joins_again() -> void:
	_keyboard_moved_to_p2()
	check_equal(joins, [["left", 0, KEYBOARD], ["joined", 1, KEYBOARD]], "it left and joined again")


func test_a_device_whose_seat_stays_the_machines_keeps_it() -> void:
	_keyboard_moved_to_p2()
	joins.clear()
	check(manager.set_own_seats(), "all four again")
	check(manager.device_of(1) == KEYBOARD and joins.is_empty(), "a device whose seat is still the machine's keeps it: nothing leaves or joins")


func test_a_gamepad_takes_the_lowest_free_seat_after_the_seats_change() -> void:
	_keyboard_moved_to_p2()
	manager.set_own_seats()
	_press_join(4)
	check_equal(manager.device_of(0), 4, "a gamepad takes the lowest free seat as ever")


func test_a_device_outside_the_seats_with_no_place_left_leaves() -> void:
	_keyboard_moved_to_p2()
	manager.set_own_seats()
	_press_join(4)
	joins.clear()
	manager.set_own_seats(1, 1)
	check(manager.device_of(1) == KEYBOARD and manager.joined_count() == 1, "told P2 alone again, only the device outside it leaves")
	check_equal(joins, [["left", 0, 4]], "and finds no place")


func test_a_reseat_seats_everyone_as_if_they_joined_now() -> void:
	_keyboard_moved_to_p2()
	_press_join(4)
	check(manager.set_own_seats(0, 4, true), "all four, everyone seated anew")
	check(manager.device_of(0) == KEYBOARD and manager.joined_count() == 1, "the keyboard is P1 again, as if it joined now")
	_press_join(4)
	check_equal(manager.device_of(1), 4, "and a gamepad joins as P2")


func test_seats_told_again_move_nothing() -> void:
	_join_keyboard()
	_press_join(4)
	joins.clear()
	check(manager.set_own_seats(0, 4) and joins.is_empty(), "told what it is already, nothing moves")


func test_a_provisional_keyboard_stays_provisional_when_reseated() -> void:
	manager.join(KEYBOARD, true)
	manager.set_own_seats(1, 1, true)
	check(manager.device_of(1) == KEYBOARD and manager.is_keyboard_provisional(), "a provisional keyboard stays provisional on its new seat")


func test_a_reseat_never_moves_a_virtual_device() -> void:
	manager.join(KEYBOARD, true)
	manager.set_own_seats(1, 1, true)
	manager.add_virtual_device(0)
	manager.set_own_seats(0, 4, true)
	check_equal(manager.device_of(0), InputManagerScript.virtual_device_id(0), "a virtual device is never moved")
	check_equal(manager.player_of(KEYBOARD), NO_PLAYER, "the keyboard finds P1 taken")


# --- Leaving ----------------------------------------------------------------

func test_leave_frees_only_that_slot() -> void:
	_join_pads(4)
	check(manager.leave(1), "leave(1) reports a player left")
	check(not manager.is_joined(1), "slot 1 is free after leaving")
	check(manager.is_joined(0) and manager.is_joined(2) and manager.is_joined(3), "the other players stay")


func test_leaving_an_empty_slot_is_refused() -> void:
	_join_pads(4)
	manager.leave(1)
	check(not manager.leave(1), "leaving an empty slot returns false")


func test_device_left_carries_player_then_device() -> void:
	_join_pads(4)
	joins.clear()
	manager.leave(1)
	check_equal(joins, [["left", 1, 1]], "device_left carries player then device")


func test_the_next_gamepad_takes_a_freed_slot() -> void:
	_join_pads(4)
	manager.leave(1)
	_press_join(7)
	check_equal(manager.device_of(1), 7, "the next gamepad takes the freed slot 1")


## No button leaves (items I2): Back (the inventory's since items I7) and Backspace keep the seat
## (the pause menu's "Leave game" does: `test_leave_game_frees_only_that_seat`).
func test_back_does_not_leave() -> void:
	_join_pads(4)
	manager.handle_event(_button(1, JOY_BUTTON_BACK))
	check(manager.is_joined(1), "Back no longer leaves")


func test_backspace_does_not_leave() -> void:
	_join_keyboard()
	manager.handle_event(_key(KEY_BACKSPACE))
	check(manager.is_joined(0), "Backspace no longer leaves")


## The pause menu's "Leave game" (`seat_leave_requested`, heard once the manager is in the tree)
## frees that seat alone, with `device_left`, as a pad pulled out would.
func test_leave_game_frees_only_that_seat() -> void:
	root.add_child(manager)
	await process_frame
	_join_pads(4)
	joins.clear()
	bus.seat_leave_requested.emit(1)
	check(not manager.is_joined(1), "Leave game frees player 1")
	check_equal(manager.joined_count(), 3, "and only that seat")
	check(joins.size() == 1 and joins[0][0] == "left" and joins[0][1] == 1, "with device_left, got %s" % [joins])


func test_a_player_who_leaves_holding_buttons_holds_nothing() -> void:
	manager.add_virtual_device(1)
	manager.send_virtual(1, &"move_down")
	manager.send_virtual(1, &"staff_2")
	manager.leave(1)
	check(manager.get_move(1) == Vector2.ZERO and not manager.is_action_pressed(1, &"staff_2"),
		"a player who leaves holding a button does not keep moving or casting")


# --- An unplugged gamepad (the owner, 2026-11-13) ---------------------------
# An unplugged pad keeps its seat and the game is asked to wait for it.

## Four pads; pad 2 holds RB and its stick right, then is unplugged.
func _unplug_pad_2() -> void:
	_join_pads(4)
	manager.handle_event(_button(2, JOY_BUTTON_RIGHT_SHOULDER))
	manager.handle_event(_axis(2, JOY_AXIS_LEFT_X, 1.0))
	joins.clear()
	manager._on_joy_connection_changed(2, false)


func test_an_unplugged_gamepad_keeps_its_seat() -> void:
	_unplug_pad_2()
	check(manager.is_joined(2) and manager.joined_count() == 4 and manager.device_of(2) == 2, "an unplugged gamepad keeps its seat")


func test_only_the_unplugged_seat_waits() -> void:
	_unplug_pad_2()
	check(manager.is_waiting(2) and not manager.is_waiting(1), "only its seat waits")


func test_an_unplug_neither_leaves_nor_joins() -> void:
	_unplug_pad_2()
	check(joins.is_empty(), "no device left or joined: %s" % [joins])


func test_an_unplug_asks_the_game_to_wait_for_that_seat() -> void:
	_unplug_pad_2()
	check_equal(waits, [[2, 1]], "the game is asked to wait for seat 2's gamepad")


func test_a_waiting_seat_holds_nothing() -> void:
	_unplug_pad_2()
	check(manager.get_move(2) == Vector2.ZERO and not manager.is_action_pressed(2, &"staff_1"), "a waiting seat holds nothing")


func test_an_unplugged_gamepad_is_not_shaken() -> void:
	_unplug_pad_2()
	check(not manager.rumble(2, 1.0, 1.0, 0.1), "an unplugged gamepad is not shaken")


func test_an_unplug_told_twice_asks_once() -> void:
	_unplug_pad_2()
	manager._on_joy_connection_changed(2, false)
	check_equal(waits.size(), 1, "unplugged twice is once")


func test_unplugging_a_gamepad_that_never_joined_changes_nothing() -> void:
	_join_pads(4)
	manager._on_joy_connection_changed(8, false)
	check(manager.joined_count() == 4 and waits.is_empty(), "unplugging a gamepad that never joined changes nothing")


func test_plugging_in_a_gamepad_does_not_join_it() -> void:
	_join_pads(4)
	manager.leave(3)
	manager._on_joy_connection_changed(8, true)
	check(waits.is_empty() and manager.player_of(8) == NO_PLAYER, "plugging in a gamepad does not join it without a button press")


func test_a_waiting_seat_asks_again_in_a_new_room() -> void:
	# A room entered while it waits (a run's start let the stop go): asked again.
	_unplug_pad_2()
	manager._on_room_entered(&"room")
	check_equal(waits, [[2, 1], [2, 1]], "a waiting seat asks again in a new room")


func test_a_gamepad_plugged_back_in_plays_its_seat_again() -> void:
	_unplug_pad_2()
	manager._on_joy_connection_changed(2, true)
	check(not manager.is_waiting(2) and manager.device_of(2) == 2, "plugged back in, the seat has its gamepad again")
	check(joins.is_empty(), "still no device left or joined: %s" % [joins])


func test_a_gamepad_plugged_back_in_asks_the_game_to_go_on() -> void:
	_unplug_pad_2()
	manager._on_joy_connection_changed(2, true)
	check_equal(waits.back(), [2, 0], "the game is asked to go on")


func test_a_gamepad_plugged_back_in_has_its_buttons() -> void:
	_unplug_pad_2()
	manager._on_joy_connection_changed(2, true)
	manager.handle_event(_button(2, JOY_BUTTON_RIGHT_SHOULDER))
	check(manager.is_action_pressed(2, &"staff_1"), "its buttons work again")


func test_a_new_room_asks_nothing_when_nobody_waits() -> void:
	_unplug_pad_2()
	manager._on_joy_connection_changed(2, true)
	var count: int = waits.size()
	manager._on_room_entered(&"room")
	check_equal(waits.size(), count, "nobody waits, so a new room asks nothing")


## Pads 0-2 joined; pad 2 unplugged, then pad 1: each seat waits by itself.
func _unplug_pads_2_and_1() -> void:
	_join_pads(3)
	manager._on_joy_connection_changed(2, false)
	manager._on_joy_connection_changed(1, false)
	joins.clear()


func test_two_unplugged_seats_each_wait() -> void:
	_unplug_pads_2_and_1()
	check(manager.is_waiting(1) and manager.is_waiting(2), "two seats wait")
	check_equal(waits, [[2, 1], [1, 1]], "each asked for in turn")


func test_the_keyboard_takes_no_gamepads_waiting_seat() -> void:
	_unplug_pads_2_and_1()
	_join_keyboard()
	check(manager.is_waiting(1) and manager.player_of(KEYBOARD) == NO_PLAYER, "the keyboard takes no waiting seat")


func test_a_new_gamepad_takes_the_lowest_waiting_seat() -> void:
	# A new gamepad's join goes to the lowest waiting seat, before the free slot 3.
	_unplug_pads_2_and_1()
	_press_join(7)
	check(manager.player_of(7) == 1 and not manager.is_waiting(1) and manager.is_waiting(2), "another gamepad takes the lowest waiting seat")


func test_a_gamepad_taking_a_waiting_seat_lets_the_game_go_on_without_a_join() -> void:
	_unplug_pads_2_and_1()
	_press_join(7)
	check_equal(waits.back(), [1, 0], "the game goes on for that seat")
	check(joins.is_empty(), "no seat was left or joined: %s" % [joins])


func test_the_press_that_takes_a_waiting_seat_is_not_its_accept() -> void:
	_unplug_pads_2_and_1()
	_press_join(7)
	check(not manager.is_action_pressed(1, &"accept"), "the join press is not the seat's A")


func test_a_replaced_gamepad_plugged_back_in_takes_nothing() -> void:
	# The old gamepad of that seat, back: a gamepad like any other, for the next waiting seat.
	_unplug_pads_2_and_1()
	_press_join(7)
	manager._on_joy_connection_changed(1, true)
	check(manager.player_of(1) == NO_PLAYER and manager.is_waiting(2), "the replaced gamepad takes nothing by being plugged in")


func test_a_waiting_gamepads_press_brings_it_back() -> void:
	# A waiting gamepad that speaks is back, whether or not its connection was told.
	_unplug_pads_2_and_1()
	manager.handle_event(_button(2, JOY_BUTTON_RIGHT_SHOULDER))
	check(not manager.is_waiting(2), "a waiting gamepad's press brings it back")
	check_equal(waits.back(), [2, 0], "the game goes on for it")
	check(manager.is_action_pressed(2, &"staff_1"), "its press counts")


func test_with_nobody_waiting_a_join_takes_a_free_slot() -> void:
	_unplug_pads_2_and_1()
	_press_join(7)
	manager.handle_event(_button(2, JOY_BUTTON_RIGHT_SHOULDER))
	_press_join(1)
	check_equal(manager.player_of(1), 3, "then a join takes the free slot")


func test_a_waiting_seat_can_leave() -> void:
	_join_pads(2)
	manager._on_joy_connection_changed(1, false)
	joins.clear()
	check(manager.leave(1), "a waiting seat leaves")
	check(not manager.is_joined(1) and not manager.is_waiting(1), "its slot is free")
	check_equal(joins, [["left", 1, 1]], "and the leave is said")


func test_a_left_waiting_seats_gamepad_back_joins_nothing() -> void:
	_join_pads(2)
	manager._on_joy_connection_changed(1, false)
	manager.leave(1)
	manager._on_joy_connection_changed(1, true)
	check(not manager.is_joined(1), "its gamepad back joins nothing by itself")


func test_a_waiting_seat_that_must_move_leaves() -> void:
	# A waiting seat that must move (this machine's seats changed) leaves: no gamepad to seat.
	_join_pads(2)
	manager._on_joy_connection_changed(1, false)
	check(manager.set_own_seats(2, 2), "seats given")
	check(manager.player_of(0) == 2 and manager.player_of(1) == NO_PLAYER, "the other moved, the waiting seat left")
	check(not manager.is_waiting(1) and not manager.is_waiting(3), "nobody waits")


## A pad pulled out may still flush a release or a stick back at rest: no sign it is in hand.
func _flush_a_dead_pad() -> void:
	_press_join(0)
	manager.handle_event(_axis(0, JOY_AXIS_LEFT_X, 1.0))
	manager._on_joy_connection_changed(0, false)
	manager.handle_event(_axis(0, JOY_AXIS_LEFT_X, 0.0))
	manager.handle_event(_button(0, JOY_BUTTON_RIGHT_SHOULDER, false))
	manager.handle_event(_axis(0, JOY_AXIS_RIGHT_X, 0.1))


func test_a_dead_pads_releases_keep_its_seat_waiting() -> void:
	_flush_a_dead_pad()
	check(manager.is_waiting(0), "releases and a stick at rest keep the seat waiting")
	check_equal(manager.get_move(0), Vector2.ZERO, "and the seat still holds nothing")


func test_a_waiting_pads_stick_pushed_ends_the_wait() -> void:
	_flush_a_dead_pad()
	manager.handle_event(_axis(0, JOY_AXIS_LEFT_X, 0.8))
	check(not manager.is_waiting(0), "a stick pushed is a pad in hand")


# A player alone whose only pad died goes on with the keyboard (on P1, the seat it may hold).

func _keyboard_after_a_dead_pad() -> void:
	_press_join(0)
	manager._on_joy_connection_changed(0, false)
	joins.clear()
	_join_keyboard()


func test_the_keyboard_takes_p1_back_from_a_dead_pad() -> void:
	_keyboard_after_a_dead_pad()
	check(manager.device_of(0) == KEYBOARD and not manager.is_waiting(0), "the keyboard's join takes P1 back")


func test_the_keyboard_taking_p1_back_lets_the_game_go_on_without_a_join() -> void:
	_keyboard_after_a_dead_pad()
	check_equal(waits, [[0, 1], [0, 0]], "the game goes on")
	check(joins.is_empty(), "no seat left or joined: %s" % [joins])


func test_the_keyboard_holds_a_dead_pads_seat_for_good() -> void:
	_keyboard_after_a_dead_pad()
	check(not manager.is_keyboard_provisional(), "the keyboard holds it for good")


func test_the_keyboard_takes_no_other_waiting_seat() -> void:
	# Only its own seat: a waiting P2 is a gamepad's to take.
	_join_pads(2)
	manager._on_joy_connection_changed(1, false)
	_join_keyboard()
	check(manager.is_waiting(1) and manager.player_of(KEYBOARD) == NO_PLAYER, "the keyboard takes no other waiting seat")


# --- Virtual devices --------------------------------------------------------

func _add_four_virtual_devices() -> void:
	for player in 4:
		manager.add_virtual_device(player)


func test_a_virtual_device_has_its_id_on_every_seat() -> void:
	for player in 4:
		var device: int = manager.add_virtual_device(player)
		check(device == InputManagerScript.virtual_device_id(player), "virtual device of player %d has its id" % player)
		check(InputManagerScript.is_virtual(device), "device %d is virtual" % device)
		check(manager.device_of(player) == device, "player %d owns its virtual device" % player)
		check(manager.player_of(device) == player, "player_of(virtual %d) is %d" % [device, player])


func test_a_virtual_device_announces_its_join() -> void:
	_add_four_virtual_devices()
	check_equal(joins, [["joined", 0, 1000], ["joined", 1, 1001], ["joined", 2, 1002], ["joined", 3, 1003]], "a virtual device announces device_joined for every index")


func test_a_virtual_device_moves_only_its_own_seat() -> void:
	# Each virtual device drives only its own player, through the real path.
	_add_four_virtual_devices()
	for player in 4:
		manager.send_virtual(player, &"move_right")
		for other in 4:
			var expected: Vector2 = Vector2.RIGHT if other == player else Vector2.ZERO
			check(manager.get_move(other) == expected, "after virtual move from %d, player %d moves %s, got %s" % [player, other, expected, manager.get_move(other)])
		manager.send_virtual(player, &"move_right", 0.0)


func test_a_virtual_release_stops_its_seat() -> void:
	_add_four_virtual_devices()
	for player in 4:
		manager.send_virtual(player, &"move_right")
		manager.send_virtual(player, &"move_right", 0.0)
		check(manager.get_move(player) == Vector2.ZERO, "virtual release stops player %d" % player)


func test_a_virtual_cast_reaches_its_seat() -> void:
	_add_four_virtual_devices()
	for player in 4:
		manager.send_virtual(player, &"staff_2")
		check(manager.is_action_pressed(player, &"staff_2"), "virtual cast reaches player %d" % player)


func test_a_virtual_device_can_leave() -> void:
	_add_four_virtual_devices()
	check(manager.leave(2), "a virtual device can leave")
	check(not manager.is_joined(2), "its slot is free")


func test_a_virtual_device_cannot_take_a_used_slot() -> void:
	_press_join(0)
	check_equal(manager.add_virtual_device(0), NO_DEVICE, "a virtual device cannot take a used slot")
	check_equal(manager.device_of(0), 0, "the real device keeps its slot")


func test_a_virtual_device_outside_the_four_is_refused() -> void:
	check_equal(manager.add_virtual_device(4), NO_DEVICE, "a virtual device for index 4 is refused")
	check_equal(manager.add_virtual_device(-1), NO_DEVICE, "a virtual device for index -1 is refused")


func test_a_bot_can_take_a_free_slot_beside_a_real_player() -> void:
	_press_join(0)
	check_equal(manager.add_virtual_device(3), 1003, "a bot can take a free slot beside a real player")


func test_a_virtual_devices_join_action_joins_nothing() -> void:
	var event := InputEventAction.new()
	event.device = InputManagerScript.virtual_device_id(0)
	event.action = &"join"
	event.pressed = true
	manager.handle_event(event)
	check_equal(manager.joined_count(), 0, "a virtual device joins only through add_virtual_device")


func test_join_refuses_a_virtual_id() -> void:
	check_equal(manager.join(InputManagerScript.virtual_device_id(1)), NO_PLAYER, "join() refuses virtual ids")


func test_a_virtual_send_without_a_virtual_device_does_nothing() -> void:
	manager.send_virtual(0, &"staff_2")
	check(not manager.is_action_pressed(0, &"staff_2"), "a virtual send without a virtual device does nothing")


func test_a_virtual_send_cannot_drive_a_real_players_seat() -> void:
	_press_join(0)
	manager.send_virtual(0, &"staff_2")
	check(not manager.is_action_pressed(0, &"staff_2"), "a virtual send cannot drive a real player's slot")


func test_a_press_is_stamped_with_its_frames() -> void:
	manager.add_virtual_device(0)
	manager.send_virtual(0, &"staff_1")
	check_equal(manager._pressed_physics[0][&"staff_1"], Engine.get_physics_frames(), "a press is stamped with the physics frame")
	check_equal(manager._pressed_process[0][&"staff_1"], Engine.get_process_frames(), "a press is stamped with the process frame")


func test_a_press_counts_as_just_pressed_outside_a_physics_step() -> void:
	manager.add_virtual_device(0)
	manager.send_virtual(0, &"staff_1")
	check(manager.is_action_just_pressed(0, &"staff_1"), "the press counts as just pressed outside a physics step")


# --- Moving and casting -----------------------------------------------------

func test_d_moves_right() -> void:
	_join_keyboard()
	manager.handle_event(_key(KEY_D))
	check_equal(manager.get_move(0), Vector2.RIGHT, "D moves right")


func test_a_keyboard_diagonal_has_length_one() -> void:
	_join_keyboard()
	manager.handle_event(_key(KEY_D))
	manager.handle_event(_key(KEY_S))
	var diagonal: Vector2 = manager.get_move(0)
	check(is_equal_approx(diagonal.length(), 1.0), "a diagonal has length 1, got %s" % diagonal.length())


func test_releasing_the_keys_stops() -> void:
	_join_keyboard()
	manager.handle_event(_key(KEY_D))
	manager.handle_event(_key(KEY_S))
	manager.handle_event(_key(KEY_D, false))
	manager.handle_event(_key(KEY_S, false))
	check_equal(manager.get_move(0), Vector2.ZERO, "releasing the keys stops")


func test_w_and_a_move_up_and_left() -> void:
	_join_keyboard()
	manager.handle_event(_key(KEY_W))
	manager.handle_event(_key(KEY_A))
	check(manager.get_move(0).x < 0.0 and manager.get_move(0).y < 0.0, "W and A move up and left")


func test_the_left_mouse_button_casts() -> void:
	_join_keyboard()
	manager.handle_event(_click())
	check(manager.is_action_pressed(0, &"staff_2"), "the left mouse button casts")


func test_a_players_stick_moves_that_player_only() -> void:
	_join_pads(2)
	manager.handle_event(_axis(1, JOY_AXIS_LEFT_X, -1.0))
	manager.handle_event(_axis(1, JOY_AXIS_LEFT_Y, 1.0))
	var move: Vector2 = manager.get_move(1)
	check(move.x < 0.0 and move.y > 0.0, "the stick moves down-left, got %s" % move)
	check_equal(manager.get_move(0), Vector2.ZERO, "player 0 does not move from player 1's stick")


func test_the_left_stick_has_a_dead_zone() -> void:
	_join_pads(2)
	manager.handle_event(_axis(1, JOY_AXIS_LEFT_X, 0.1))
	manager.handle_event(_axis(1, JOY_AXIS_LEFT_Y, -0.1))
	check_equal(manager.get_move(1), Vector2.ZERO, "values inside the deadzone are zero")


func test_the_right_trigger_casts_until_released() -> void:
	_press_join(0)
	manager.handle_event(_axis(0, JOY_AXIS_TRIGGER_RIGHT, 1.0))
	check(manager.is_action_pressed(0, &"staff_2"), "the right trigger casts")
	manager.handle_event(_axis(0, JOY_AXIS_TRIGGER_RIGHT, 0.0))
	check(not manager.is_action_pressed(0, &"staff_2"), "releasing the trigger stops the cast")


func test_a_key_still_moves_after_another_key_for_its_action_is_released() -> void:
	_join_keyboard()
	manager.handle_event(_key(KEY_A))
	manager.handle_event(_key(KEY_LEFT))
	manager.handle_event(_key(KEY_LEFT, false))
	check_equal(manager.get_move(0), Vector2.LEFT, "A still moves left after Left is released")
	manager.handle_event(_key(KEY_A, false))
	check_equal(manager.get_move(0), Vector2.ZERO, "releasing the last key stops")
	manager.handle_event(_key(KEY_W))
	manager.handle_event(_key(KEY_UP))
	manager.handle_event(_key(KEY_W, false))
	check_equal(manager.get_move(0), Vector2.UP, "Up still moves up after W is released")


## The keyboard on P1, pads 1 and 2 on P2 and P3 (pad 2 is player 2).
func _keyboard_and_two_pads() -> void:
	_join_keyboard()
	_press_join(1)
	_press_join(2)


func test_a_stick_at_rest_does_not_cancel_a_held_dpad() -> void:
	_keyboard_and_two_pads()
	manager.handle_event(_button(2, JOY_BUTTON_DPAD_LEFT))
	manager.handle_event(_axis(2, JOY_AXIS_LEFT_X, 0.0))
	check_equal(manager.get_move(2), Vector2.LEFT, "a stick at rest does not cancel the held d-pad")


func test_the_stick_still_moves_after_the_dpad_is_released() -> void:
	_keyboard_and_two_pads()
	manager.handle_event(_button(2, JOY_BUTTON_DPAD_LEFT))
	manager.handle_event(_axis(2, JOY_AXIS_LEFT_X, -1.0))
	manager.handle_event(_button(2, JOY_BUTTON_DPAD_LEFT, false))
	check_equal(manager.get_move(2), Vector2.LEFT, "the stick still moves left after the d-pad is released")
	manager.handle_event(_axis(2, JOY_AXIS_LEFT_X, 0.0))
	check_equal(manager.get_move(2), Vector2.ZERO, "everything released stops")


func test_the_left_trigger_casts_staff_4() -> void:
	_keyboard_and_two_pads()
	manager.handle_event(_axis(2, JOY_AXIS_TRIGGER_LEFT, 1.0))
	manager.handle_event(_key(KEY_Q))
	check(manager.is_action_pressed(2, &"staff_4"), "the left trigger casts staff 4")


func test_the_right_trigger_still_casts_after_rb_is_released() -> void:
	_keyboard_and_two_pads()
	manager.handle_event(_axis(2, JOY_AXIS_TRIGGER_RIGHT, 1.0))
	manager.handle_event(_button(2, JOY_BUTTON_RIGHT_SHOULDER))
	manager.handle_event(_button(2, JOY_BUTTON_RIGHT_SHOULDER, false))
	check(manager.is_action_pressed(2, &"staff_2"), "the right trigger still casts after RB is released")
	manager.handle_event(_axis(2, JOY_AXIS_TRIGGER_RIGHT, 0.0))
	check(not manager.is_action_pressed(2, &"staff_2"), "the cast stops when the last input is released")


func test_the_dpad_moves() -> void:
	_press_join(0)
	var dpad: Dictionary = {
		JOY_BUTTON_DPAD_LEFT: Vector2.LEFT, JOY_BUTTON_DPAD_RIGHT: Vector2.RIGHT,
		JOY_BUTTON_DPAD_UP: Vector2.UP, JOY_BUTTON_DPAD_DOWN: Vector2.DOWN,
	}
	for button: JoyButton in dpad:
		manager.handle_event(_button(0, button))
		check(manager.get_move(0) == dpad[button], "d-pad button %d moves %s" % [button, dpad[button]])
		manager.handle_event(_button(0, button, false))


func test_each_gamepad_button_routes_to_its_action() -> void:
	_press_join(0)
	var buttons: Dictionary = {
		JOY_BUTTON_RIGHT_SHOULDER: &"staff_1", JOY_BUTTON_LEFT_SHOULDER: &"staff_3", JOY_BUTTON_A: &"accept",
		JOY_BUTTON_B: &"back", JOY_BUTTON_X: &"alternate", JOY_BUTTON_Y: &"extra", JOY_BUTTON_START: &"pause",
		JOY_BUTTON_DPAD_LEFT: &"kind_prev", JOY_BUTTON_DPAD_RIGHT: &"kind_next", JOY_BUTTON_BACK: &"inventory",
	}
	for button: JoyButton in buttons:
		manager.handle_event(_button(0, button))
		check(manager.is_action_pressed(0, buttons[button]), "gamepad button %d is %s" % [button, buttons[button]])
		manager.handle_event(_button(0, button, false))
		check(not manager.is_action_pressed(0, buttons[button]), "releasing gamepad button %d stops %s" % [button, buttons[button]])


func test_each_key_routes_to_its_action() -> void:
	_join_keyboard()
	var keys: Dictionary = {
		KEY_LEFT: &"move_left", KEY_RIGHT: &"move_right", KEY_UP: &"move_up", KEY_DOWN: &"move_down",
		KEY_SHIFT: &"staff_1", KEY_SPACE: &"staff_1", KEY_TAB: &"inventory", KEY_E: &"back", KEY_J: &"staff_2",
		KEY_K: &"staff_3", KEY_Q: &"staff_4", KEY_L: &"staff_4", KEY_ENTER: &"accept", KEY_X: &"alternate",
		KEY_ESCAPE: &"pause", KEY_R: &"extra", KEY_PAGEUP: &"kind_prev", KEY_PAGEDOWN: &"kind_next",
	}
	for key: Key in keys:
		manager.handle_event(_key(key))
		check(manager.is_action_pressed(0, keys[key]), "key %d is %s" % [key, keys[key]])
		manager.handle_event(_key(key, false))
		check(not manager.is_action_pressed(0, keys[key]), "releasing key %d stops %s" % [key, keys[key]])


# --- Aiming -----------------------------------------------------------------

func test_no_aim_before_the_right_stick_moves() -> void:
	_join_pads(2)
	check_equal(manager.get_aim(1), Vector2.ZERO, "no aim before the stick moves")


func test_the_right_stick_aims() -> void:
	_join_pads(2)
	manager.handle_event(_axis(1, JOY_AXIS_RIGHT_X, 1.0))
	check(manager.get_aim(1).is_equal_approx(Vector2.RIGHT), "right stick right aims right")


func test_a_diagonal_aim_is_a_unit_vector() -> void:
	_join_pads(2)
	manager.handle_event(_axis(1, JOY_AXIS_RIGHT_X, 1.0))
	manager.handle_event(_axis(1, JOY_AXIS_RIGHT_Y, 1.0))
	check(manager.get_aim(1).is_equal_approx(Vector2(1, 1).normalized()), "a diagonal aim is a unit vector")


func test_a_players_right_stick_aims_that_player_only() -> void:
	_join_pads(2)
	manager.handle_event(_axis(1, JOY_AXIS_RIGHT_X, 1.0))
	check_equal(manager.get_aim(0), Vector2.ZERO, "player 0 does not aim from player 1's stick")


func test_the_right_stick_has_a_dead_zone() -> void:
	_join_pads(2)
	manager.handle_event(_axis(1, JOY_AXIS_RIGHT_X, 0.1))
	manager.handle_event(_axis(1, JOY_AXIS_RIGHT_Y, 0.1))
	check_equal(manager.get_aim(1), Vector2.ZERO, "the right stick has a dead zone")


func test_a_captured_player_does_not_aim() -> void:
	_join_pads(2)
	manager.handle_event(_axis(1, JOY_AXIS_RIGHT_X, -1.0))
	manager.set_captured(1, true)
	check_equal(manager.get_aim(1), Vector2.ZERO, "a captured player does not aim")


func test_leaving_clears_the_aim() -> void:
	_join_pads(2)
	manager.handle_event(_axis(1, JOY_AXIS_RIGHT_X, -1.0))
	manager.leave(1)
	_press_join(1)
	check_equal(manager.get_aim(1), Vector2.ZERO, "leaving clears the aim")


func test_a_bot_aims_through_its_virtual_device() -> void:
	manager.add_virtual_device(2)
	manager.send_virtual_aim(2, Vector2.UP)
	check(manager.get_aim(2).is_equal_approx(Vector2.UP), "a bot aims through its virtual device")


func test_a_seat_without_a_virtual_device_is_not_aimed_by_one() -> void:
	manager.add_virtual_device(2)
	manager.send_virtual_aim(3, Vector2.UP)
	check_equal(manager.get_aim(3), Vector2.ZERO, "a player without a virtual device is not aimed")


# --- A captured player's menu -----------------------------------------------

func _captured_pad() -> void:
	_press_join(0)
	manager.set_captured(0, true)


func test_a_captured_player_does_not_walk() -> void:
	_captured_pad()
	manager.handle_event(_axis(0, JOY_AXIS_LEFT_X, 1.0))
	check_equal(manager.get_move(0), Vector2.ZERO, "a captured player does not walk")


func test_a_captured_players_menu_reads_the_left_stick() -> void:
	_captured_pad()
	manager.handle_event(_axis(0, JOY_AXIS_LEFT_X, 1.0))
	check(manager.menu_move(0).is_equal_approx(Vector2.RIGHT), "their menu reads the left stick, got %s" % manager.menu_move(0))


func test_on_a_pad_the_dpad_is_not_the_menus_stick() -> void:
	_captured_pad()
	manager.handle_event(_button(0, JOY_BUTTON_DPAD_LEFT))
	check_equal(manager.menu_move(0), Vector2.ZERO, "on a pad the d-pad is not the menu's stick")
	check(manager.is_action_pressed(0, &"kind_prev"), "a captured player's d-pad left is still kind_prev")


func test_a_captured_players_trigger_casts_nothing() -> void:
	_captured_pad()
	manager.handle_event(_axis(0, JOY_AXIS_TRIGGER_LEFT, 1.0))
	check(not manager.is_action_pressed(0, &"staff_4"), "a captured player's LT casts nothing")


func test_a_captured_players_menu_sees_a_trigger_held() -> void:
	_captured_pad()
	manager.handle_event(_axis(0, JOY_AXIS_TRIGGER_LEFT, 1.0))
	check(manager.is_held(0, &"staff_4"), "their menu sees it held")
	manager.handle_event(_axis(0, JOY_AXIS_TRIGGER_LEFT, 0.0))
	check(not manager.is_held(0, &"staff_4"), "and let go")


func test_a_captured_players_menu_reads_the_right_stick() -> void:
	_captured_pad()
	manager.handle_event(_axis(0, JOY_AXIS_RIGHT_Y, -1.0))
	check(manager.menu_aim(0).is_equal_approx(Vector2.UP), "their menu reads the right stick")


func test_the_menus_full_tilt_reads_one() -> void:
	_captured_pad()
	manager.handle_event(_axis(0, JOY_AXIS_RIGHT_Y, -1.0))
	check(manager.menu_tilt(0).is_equal_approx(Vector2.UP), "full tilt reads 1")


func test_the_menus_tilt_grows_from_the_dead_zone_while_its_aim_stays_a_unit() -> void:
	_captured_pad()
	manager.handle_event(_axis(0, JOY_AXIS_RIGHT_Y, -0.625))
	check(is_equal_approx(manager.menu_tilt(0).y, -0.5), "half way past the dead zone reads half a tilt, got %s" % manager.menu_tilt(0))
	check(manager.menu_aim(0).is_equal_approx(Vector2.UP), "the aim stays a unit")


func test_the_menus_aim_and_tilt_are_zero_inside_the_dead_zone() -> void:
	_captured_pad()
	manager.handle_event(_axis(0, JOY_AXIS_RIGHT_Y, -0.1))
	check_equal(manager.menu_aim(0), Vector2.ZERO, "inside the dead zone the aim is zero")
	check_equal(manager.menu_tilt(0), Vector2.ZERO, "and so is the tilt")


func test_a_virtual_devices_menu_reads_its_move_actions() -> void:
	manager.add_virtual_device(1)
	manager.set_captured(1, true)
	manager.send_virtual(1, &"move_down", 1.0)
	check(manager.menu_move(1).is_equal_approx(Vector2.DOWN), "a virtual device's menu reads its move actions")


func test_a_free_slots_menu_reads_nothing() -> void:
	_captured_pad()
	check(manager.menu_move(2) == Vector2.ZERO and manager.menu_aim(2) == Vector2.ZERO, "a free slot reads nothing")


# --- Rumble -----------------------------------------------------------------

## The keyboard on P1, pad 3 on P2; rumbles are recorded in `shaken`.
func _rumble_rig() -> void:
	manager.set("vibrator", func(device: int, weak: float, strong: float, seconds: float) -> void: shaken.append([device, weak, strong, seconds]))
	_join_keyboard()
	_press_join(3)


func test_the_keyboard_does_not_rumble() -> void:
	_rumble_rig()
	check(not manager.rumble(0, 1.0, 1.0, 0.1), "the keyboard does not rumble")
	check(shaken.is_empty(), "nothing shook")


func test_a_players_rumble_shakes_its_own_pad_with_motors_clamped() -> void:
	_rumble_rig()
	check(manager.rumble(1, 0.25, 2.0, 0.05), "player 2's pad rumbles")
	check_equal(shaken, [[3, 0.25, 1.0, 0.05]], "on its own device, motors clamped to 1")


func test_a_free_slot_does_not_rumble() -> void:
	_rumble_rig()
	check(not manager.rumble(2, 1.0, 1.0, 0.1), "a free slot does not rumble")


# --- Mouse aim --------------------------------------------------------------

## The keyboard on P1, aiming with the mouse.
func _mouse_aiming() -> void:
	manager.handle_event(_key(KEY_SPACE))
	manager.handle_event(_mouse_move(Vector2(30, 0)))


func test_no_mouse_aim_before_anyone_joined() -> void:
	check(not manager.is_mouse_aiming(0), "no mouse aim before anyone joined")


func test_no_mouse_aim_before_the_mouse_moves() -> void:
	manager.handle_event(_key(KEY_SPACE))
	check(not manager.is_mouse_aiming(0), "no mouse aim before the mouse moves")


func test_a_tiny_mouse_brush_does_not_turn_mouse_aim_on() -> void:
	manager.handle_event(_key(KEY_SPACE))
	manager.handle_event(_mouse_move(Vector2(1, 1)))
	check(not manager.is_mouse_aiming(0), "a tiny mouse brush does not turn mouse aim on")


func test_a_mouse_move_turns_mouse_aim_on() -> void:
	_mouse_aiming()
	check(manager.is_mouse_aiming(0), "a mouse move turns mouse aim on")


func test_the_keyboard_cast_key_turns_mouse_aim_off() -> void:
	_mouse_aiming()
	manager.handle_event(_key(KEY_J))
	check(not manager.is_mouse_aiming(0), "the keyboard cast key turns mouse aim off")


func test_a_click_turns_mouse_aim_on() -> void:
	_mouse_aiming()
	manager.handle_event(_key(KEY_J))
	manager.handle_event(_click())
	check(manager.is_mouse_aiming(0), "a click turns mouse aim on")


func test_a_captured_player_does_not_mouse_aim() -> void:
	_mouse_aiming()
	manager.set_captured(0, true)
	check(not manager.is_mouse_aiming(0), "a captured player does not mouse aim")


func test_leaving_turns_mouse_aim_off() -> void:
	_mouse_aiming()
	manager.leave(0)
	check(not manager.is_mouse_aiming(0), "leaving turns mouse aim off")


func test_a_bot_never_mouse_aims() -> void:
	manager.add_virtual_device(1)
	manager.handle_event(InputEventMouseMotion.new())
	manager.handle_event(_mouse_move(Vector2(30, 0)))
	check(not manager.is_mouse_aiming(1), "a bot never mouse aims")


# --- Per-player state -------------------------------------------------------

func test_players_do_not_share_state() -> void:
	_join_pads(4)
	var actions: Array[JoyButton] = [JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_A, JOY_BUTTON_X]
	var names: Array[StringName] = [&"back", &"alternate", &"accept", &"alternate"]
	for player in 4:
		manager.handle_event(_button(player, actions[player]))
	for player in 4:
		for action in InputManagerScript.ACTIONS:
			# Pad A is `accept` and `take` both (items I6).
			var expected: bool = action == names[player] or (names[player] == &"accept" and action == &"take")
			check(manager.is_action_pressed(player, action) == expected,
				"player %d: %s pressed is %s" % [player, action, expected])


func test_nobody_has_a_press_before_pressing() -> void:
	_join_pads(4)
	for player in 4:
		check(not manager.is_action_just_pressed(player, &"back"), "player %d has no B press before pressing" % player)


func test_a_press_is_just_pressed_for_its_player_only() -> void:
	_join_pads(4)
	manager.handle_event(_button(2, JOY_BUTTON_B))
	check(manager.is_action_just_pressed(2, &"back"), "player 2 just pressed back this frame")
	check(not manager.is_action_just_pressed(1, &"back"), "player 1 did not")


func test_a_press_is_just_pressed_for_its_action_only() -> void:
	_join_pads(4)
	manager.handle_event(_button(2, JOY_BUTTON_B))
	check(not manager.is_action_just_pressed(2, &"staff_2"), "player 2 did not press cast")


func test_a_seat_outside_the_four_has_nothing() -> void:
	for player: int in [-1, 4, 99]:
		check(manager.device_of(player) == NO_DEVICE, "device_of(%d) is NO_DEVICE" % player)
		check(not manager.is_joined(player), "player %d is not joined" % player)
		check(manager.get_move(player) == Vector2.ZERO, "player %d has no move" % player)
		check(not manager.is_action_pressed(player, &"staff_2"), "player %d has no cast" % player)
		check(not manager.is_action_just_pressed(player, &"staff_2"), "player %d has no just-pressed cast" % player)
		check(not manager.leave(player), "player %d cannot leave" % player)
