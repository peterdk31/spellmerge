extends "res://tests/support/suite.gd"
## Tests for the cheat code (`hud/widgets/cheat_code.gd`; owner, 2026-11-19): typing its word on the
## keyboard, in any case and with other keys between its letters, sends `all_cards_requested` once
## for the keyboard's seat (or this machine's first seat), and nothing while no seat is joined.

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
