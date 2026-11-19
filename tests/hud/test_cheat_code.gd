extends "res://tests/support/suite.gd"
## Tests for the cheat code (`hud/widgets/cheat_code.gd`; owner, 2026-11-19): typing its word on the
## keyboard, in any case and with other keys between its letters, sends `all_cards_requested` once
## for the keyboard's seat (or this machine's first seat), and nothing while no seat is joined; its
## buttons in a row on a gamepad (up, down, left, right, A, B, X, Y) send it for that pad's seat,
## each pad on its own, any other button starting it over.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")

var _bus: EventsScript
var _input: InputManagerScript
var _code: CheatCode
## Every `all_cards_requested` sent: its seat.
var _sent: Array[int] = []


func before_each() -> void:
	_sent.clear()
	_bus = own(EventsScript.new()) as EventsScript
	_input = own(InputManagerScript.new()) as InputManagerScript
	_input.events = _bus
	_code = own(CheatCode.new()) as CheatCode
	_code.bind(_bus, _input)
	_bus.all_cards_requested.connect(func(seat: int) -> void: _sent.append(seat))


func _type(text: String) -> void:
	for at in text.length():
		_code.type_letter(text.unicode_at(at))


func test_the_word_sends_the_command_for_the_keyboards_seat() -> void:
	_input.add_virtual_device(0)
	_input.join_as(InputManagerScript.KEYBOARD, 2)
	check_equal(_input.player_of(InputManagerScript.KEYBOARD), 2, "the keyboard holds seat 2")
	_type(CheatCode.CODE)
	check_equal(_sent, [2] as Array[int], "sent once, for the keyboard's seat, not the first seat")


func test_any_case_and_other_keys_between_the_letters_count() -> void:
	_input.join(InputManagerScript.KEYBOARD)
	_type("xyz ALL-1Cards!")
	check_equal(_sent, [0] as Array[int], "the letters in a row, any case, the rest skipped")


func test_half_the_word_or_another_word_sends_nothing() -> void:
	_input.join(InputManagerScript.KEYBOARD)
	_type(CheatCode.CODE.left(CheatCode.CODE.length() - 1))
	_type("x")
	_type("cards")
	check(_sent.is_empty(), "nothing but the word sends it")
	_type(CheatCode.CODE)
	check_equal(_sent.size(), 1, "and the word still does after")


func test_typed_again_it_is_sent_again() -> void:
	_input.join(InputManagerScript.KEYBOARD)
	_type(CheatCode.CODE + CheatCode.CODE)
	check_equal(_sent.size(), 2, "each time it is typed")


func test_with_no_keyboard_seat_the_machines_first_seat_speaks() -> void:
	_input.add_virtual_device(0)
	_type(CheatCode.CODE)
	check_equal(_sent, [0] as Array[int], "this machine's first seat")


func test_with_nobody_joined_nothing_is_sent() -> void:
	_type(CheatCode.CODE)
	check(_sent.is_empty(), "no seat to speak for")


func test_key_presses_reach_it() -> void:
	_input.join(InputManagerScript.KEYBOARD)
	for at in CheatCode.CODE.length():
		var key := InputEventKey.new()
		key.pressed = true
		key.unicode = CheatCode.CODE.unicode_at(at)
		_code._input(key)
		var echo := InputEventKey.new()
		echo.pressed = true
		echo.echo = true
		echo.unicode = &"x".unicode_at(0)
		_code._input(echo)
	check_equal(_sent, [0] as Array[int], "pressed keys are typed; held keys' echoes are not")


## Gamepad `device` presses `buttons` in order.
func _press(device: int, buttons: Array) -> void:
	for button: int in buttons:
		_code.press_button(device, button)


func test_the_pads_buttons_send_the_command_for_its_seat() -> void:
	_input.add_virtual_device(0)
	_input.join_as(1, 3)
	_press(1, CheatCode.PAD_CODE)
	check_equal(_sent, [3] as Array[int], "sent once, for the seat of the pad that pressed it")
	_press(1, CheatCode.PAD_CODE)
	check_equal(_sent, [3, 3] as Array[int], "and again each time")


func test_another_button_starts_the_pads_code_over() -> void:
	_input.join_as(0, 0)
	var code: Array = CheatCode.PAD_CODE.duplicate()
	_press(0, code.slice(0, 5))
	_press(0, [JOY_BUTTON_LEFT_SHOULDER])
	_press(0, code.slice(5))
	check(_sent.is_empty(), "a button out of the row breaks it")
	# Up, up, down, ...: the second up starts it anew, so the code still counts from there.
	_press(0, [JOY_BUTTON_DPAD_UP])
	_press(0, code)
	check_equal(_sent, [0] as Array[int], "a first button pressed again starts it anew")


func test_each_pad_counts_on_its_own() -> void:
	_input.join_as(0, 0)
	_input.join_as(1, 1)
	var code: Array = CheatCode.PAD_CODE.duplicate()
	for at in code.size():
		_press(0, [code[at]])
		_press(1, [JOY_BUTTON_START])
	check_equal(_sent, [0] as Array[int], "pad 1's presses never break pad 0's code")


func test_a_pad_with_no_seat_sends_nothing() -> void:
	_input.join(InputManagerScript.KEYBOARD)
	_press(4, CheatCode.PAD_CODE)
	check(_sent.is_empty(), "a pad that never joined has no seat to speak for")


func test_button_presses_reach_it() -> void:
	_input.join_as(2, 1)
	for button: JoyButton in CheatCode.PAD_CODE:
		var down := InputEventJoypadButton.new()
		down.device = 2
		down.button_index = button
		down.pressed = true
		_code._input(down)
		var up := InputEventJoypadButton.new()
		up.device = 2
		up.button_index = button
		_code._input(up)
	check_equal(_sent, [1] as Array[int], "pressed buttons count; their releases do not")
