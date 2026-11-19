class_name CheatCode
extends Node
## The cheat code (owner, 2026-11-19): a way for the owner to try every card. Typing CODE on the
## keyboard, its letters one after another in any case, sends the command `all_cards_requested`
## (core/events) for the keyboard's seat, or this machine's first seat when the keyboard has not
## joined. Flow hears it at the next tick's start and, only while the party is in the hub, fills
## every wizard's card bag with every card (gameplay/flow, `_on_all_cards_requested`). Anywhere
## else the command does nothing, so this node does not need to know where the party is.
##
## Only letter keys count (any other key is skipped, so a held Shift or a walk on the arrows does
## not break the word), and only the last CODE's length of them are kept. Being a command, the
## request reaches every machine of an online party and a replay, on the same tick.
##
## Made by `hud/panels/panels.gd` (node CheatCode), `bind`. It allocates only on a letter key.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")

## The word to type.
const CODE: String = "allcards"

var _events: EventsScript = null
var _player_input: InputManagerScript = null
## The letters typed last, lower case, at most CODE's length.
var _typed: String = ""


## Hear the keyboard and send the command on `events` for the seat `input` says.
func bind(events: EventsScript, input: InputManagerScript) -> void:
	_events = events
	_player_input = input


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	type_letter(key.unicode)


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
	var seat: int = _seat()
	if seat == EventsScript.NO_PLAYER or _events == null:
		return false
	_events.all_cards_requested.emit(seat)
	return true


## The seat the command speaks for: the keyboard's, else this machine's first while it is joined;
## NO_PLAYER when neither is.
func _seat() -> int:
	if _player_input == null:
		return EventsScript.NO_PLAYER
	var seat: int = _player_input.player_of(InputManagerScript.KEYBOARD)
	if seat != InputManagerScript.NO_PLAYER:
		return seat
	seat = _player_input.own_first_seat()
	return seat if _player_input.is_joined(seat) else EventsScript.NO_PLAYER
