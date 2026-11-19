class_name UiSounds
extends Node
## The menus' sounds (sound plan AU8, docs/milestones/sound.md): their ids, and the one listener
## that hears every panel's focus. The HUD never plays a sound: it sends
## `ui_sound_requested(id)` (core/events), and core/audio plays it on its UI voices (the over lane,
## heard while the game is paused; at most one play of an id a frame). The sounds are baked from
## their recipes in `audio/sfx/<id>/` (family `ui`, docs/STYLE.md "Sound").
##
## Moving is felt, not heard (owner, 2026-11-19): a focus move, a card or bag pointed at, a page
## or a slider's step rumbles the player's pad (`UiHaptics.POINT`) and makes no sound, and the
## radial builder makes none at all (its own rumbles say what it did).
##
## Who sends what:
## - **This node** (made by `panels.gd`, `bind`) hears `core/ui_focus` for every player: a focus
##   moved by the player's own move rumbles POINT, and `back` (`cancelled`) is BACK (every menu
##   goes back or closes on it), but in a silent menu (its focused control in SILENT_GROUP: the
##   builder). A focus moved by the menu itself in answer to a press (the first row of a menu
##   opened, a page shown after a choice or a back) is no move: that press says it, so one press
##   is one sound or one rumble. (Presses of one poll share the mark, so a move pressed in the
##   frame of a choice is not felt; and a focus a menu moves on its own in a later frame, as when
##   a row is hidden from outside, is felt as a move.)
##   It knows nothing of any menu.
## - **Each menu** sends what only it knows, with `send`: CHOOSE when a press did something (a row
##   of the pause menu, a bag entered in the inventory, a main menu
##   button) and DENY when it was refused (the inventory's refusal), and rumbles (`UiHaptics`)
##   when its paging showed another tab or staff or a ring pointed at another entry.
##
## It allocates nothing per press: the ids are constants.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")

const CHOOSE: StringName = &"ui_choose"
const BACK: StringName = &"ui_back"
const DENY: StringName = &"ui_deny"
## Every id the HUD sends (each has its recipe in `audio/sfx/<id>/`).
const IDS: Array[StringName] = [CHOOSE, BACK, DENY]
## A menu whose focused control is in this group makes no sound here (the radial builder).
const SILENT_GROUP: StringName = &"ui_silent"

var _events: EventsScript = null
## The pads to rumble a move on (none in a test that gives none).
var _input: InputManagerScript = null
## The players (a bit each) whose menu acted on a press this frame (opened, chose, went back,
## paged): a focus change that follows it in the same frame is the menu's answer, not a move.
var _acted: int = 0
## The players (a bit each) whose focused control is in a silent menu (SILENT_GROUP), kept as the
## focus moves, so a back is judged by the menu it was pressed in whatever closes it first.
var _silent: int = 0


## Send the sound `id` (one of IDS) on `events` (none with no bus).
static func send(events: EventsScript, id: StringName) -> void:
	if events != null:
		events.ui_sound_requested.emit(id)


func _ready() -> void:
	# Menus are worked while the game is paused, so the frame's marks are cleared then too.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Hear `ui_focus`, send on `events` and rumble a move on `input`'s pads (called once by
## `panels.gd`).
func bind(events: EventsScript, ui_focus: UIFocusScript, input: InputManagerScript = null) -> void:
	_events = events
	_input = input
	if ui_focus == null:
		return
	ui_focus.opened.connect(_mark)
	ui_focus.activated.connect(func(player: int, _control: Control) -> void: _mark(player))
	ui_focus.alternate.connect(func(player: int, _control: Control) -> void: _mark(player))
	ui_focus.cancelled.connect(_on_cancelled)
	ui_focus.paged.connect(_on_paged)
	ui_focus.focus_changed.connect(_on_focus_changed)


func _process(_delta: float) -> void:
	end_frame()


## A new frame: what a menu did in the last one no longer hides a move (called by `_process`;
## tests call it between presses).
func end_frame() -> void:
	_acted = 0


func _mark(player: int) -> void:
	_acted |= 1 << player


func _on_cancelled(player: int) -> void:
	_mark(player)
	if _silent & (1 << player) == 0:
		send(_events, BACK)


func _on_paged(player: int, _step: int) -> void:
	_mark(player)


func _on_focus_changed(player: int, control: Control) -> void:
	# UIFocus focuses a menu's first control as it opens, so every menu passes here first.
	if control != null and control.is_in_group(SILENT_GROUP):
		_silent |= 1 << player
		return
	_silent &= ~(1 << player)
	if _acted & (1 << player) == 0:
		UiHaptics.pulse(_input, player, UiHaptics.POINT)
