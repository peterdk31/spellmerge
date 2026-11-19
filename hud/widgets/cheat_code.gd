class_name CheatCode
extends Node
## The cheat code (owner, 2026-11-19): a way for the owner to try every card. Typing CODE on the
## keyboard, or pressing PAD_CODE on a gamepad (up, down, left, right on the d-pad, then A, B, X,
## Y), sends the command `all_cards_requested` (core/events). Flow hears it at the next tick's
## start and, only while the party is in the hub, fills the card bag of that seat's wizard (and no
## other's) with every card
## (gameplay/flow, `_on_all_cards_requested`). Anywhere else the command does nothing, so this node
## does not need to know where the party is. Being a command, the request reaches every machine of
## an online party and a replay, on the same tick.
##
## - **The keyboard:** only letter keys count (any other key is skipped, so a held Shift or a walk
##   on the arrows does not break the word), in any case, and only the last CODE's length of them
##   are kept. It speaks for the keyboard's seat, or this machine's first seat when the keyboard
##   has not joined.
## - **A gamepad:** its buttons in a row, each pad on its own (`_pad_steps`); any other button
##   starts it over (the stick is no button, so it never does). It speaks for that pad's seat; a
##   pad with no seat when the last button is pressed sends nothing (but A is also `join`, so a
##   pad pressing the code usually has joined by then).
## - **Both do what their keys do, too:** the letters and the d-pad walk and cast as they are
##   pressed, and A, B, X, Y act as ever (A on the lit stone starts the run, so the code then
##   does nothing; B opens the builder). Type it standing clear of the stone and the rack.
##
## Made by `hud/panels/panels.gd` (node CheatCode), `bind`. It allocates only on a key or a button.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")

## The word to type.
const CODE: String = "allcards"
## The buttons to press on a gamepad, in order (Godot's names: A, B, X, Y where a pad of the
## common layout has them).
const PAD_CODE: Array[JoyButton] = [
	JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT,
	JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y,
]

var _events: EventsScript = null
var _player_input: InputManagerScript = null
## The letters typed last, lower case, at most CODE's length.
var _typed: String = ""
## By gamepad (its device id): how many of PAD_CODE's buttons it pressed in a row so far.
var _pad_steps: Dictionary = {}


## Hear the keyboard and the gamepads, and send the command on `events` for the seat `input` says.
func bind(events: EventsScript, input: InputManagerScript) -> void:
	_events = events
	_player_input = input


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null:
		if key.pressed and not key.echo:
			type_letter(key.unicode)
		return
	var button := event as InputEventJoypadButton
	if button != null and button.pressed:
		press_button(button.device, button.button_index)


## One character typed (`unicode`, as `InputEventKey.unicode`): kept when it is a letter, and the
## command sent when the letters kept spell CODE. True when it was sent.
func type_letter(unicode: int) -> bool:
	if unicode <= 0:
		return false
	var letter: String = String.chr(unicode).to_lower()
	if letter < "a" or letter > "z":
		return false
	_typed = (_typed + letter).right(CODE.length())
	if _typed != CODE:
		return false
	_typed = ""
	return _send(_keyboard_seat())


## The gamepad `device` pressed `button` (as `InputEventJoypadButton.button_index`): one step on
## when it is PAD_CODE's next, else the code starts over (from its first step when it is PAD_CODE's
## first); the command is sent for the pad's seat when the last one is pressed. True when it was sent.
func press_button(device: int, button: int) -> bool:
	var step: int = int(_pad_steps.get(device, 0))
	if button == PAD_CODE[step]:
		step += 1
	else:
		step = 1 if button == PAD_CODE[0] else 0
	if step < PAD_CODE.size():
		_pad_steps[device] = step
		return false
	_pad_steps.erase(device)
	return _send(_player_input.player_of(device) if _player_input != null else EventsScript.NO_PLAYER)


## Send the command for `seat`; nothing for NO_PLAYER. True when it was sent.
func _send(seat: int) -> bool:
	if seat == EventsScript.NO_PLAYER or _events == null:
		return false
	_events.all_cards_requested.emit(seat)
	return true


## The seat the keyboard's code speaks for: the keyboard's, else this machine's first while it is
## joined; NO_PLAYER when neither is.
func _keyboard_seat() -> int:
	if _player_input == null:
		return EventsScript.NO_PLAYER
	var seat: int = _player_input.player_of(InputManagerScript.KEYBOARD)
	if seat != InputManagerScript.NO_PLAYER:
		return seat
	seat = _player_input.own_first_seat()
	return seat if _player_input.is_joined(seat) else EventsScript.NO_PLAYER
