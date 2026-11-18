class_name UiSounds
extends Node
## The menus' sounds (sound plan AU8, docs/milestones/sound.md): their ids, and the one listener
## that hears every panel's focus move. The HUD never plays a sound: it sends
## `ui_sound_requested(id)` (core/events), and core/audio plays it on its UI voices (the over lane,
## heard while the game is paused; at most one play of an id a frame). The sounds are baked from
## their recipes in `audio/sfx/<id>/` (family `ui`, docs/STYLE.md "Sound").
##
## Who sends what:
## - **This node** (made by `panels.gd`, `bind`) hears `core/ui_focus` for every player: a focus
##   moved by the player's own move is MOVE, and `back` (`cancelled`) is BACK (every menu goes back
##   or closes on it). A focus moved by the menu itself in answer to a press (the first row of
##   a menu opened, a page shown after a choice or a back) is no move: that press's own sound says
##   it, so one press is one sound. It knows nothing of any menu.
## - **Each menu** sends what only it knows, with `send`: CHOOSE when a press did something (a row
##   of the pause menu, a bag entered in the inventory, a depth at the lectern, a main menu
##   button), MOVE when its paging showed another tab or staff (LB and RB do nothing in some
##   menus, so `paged` alone says nothing), DENY when it was refused (the builder's or the
##   inventory's refusal, an item not taken), and the builder CARD_PLACE and CARD_REMOVE as a
##   card goes in or comes out (a clear too).
##   Pointing at another card or bag on a ring is MOVE, as a focus move is.
##
## It allocates nothing per press: the ids are constants.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")

const MOVE: StringName = &"ui_move"
const CHOOSE: StringName = &"ui_choose"
const BACK: StringName = &"ui_back"
const DENY: StringName = &"ui_deny"
const CARD_PLACE: StringName = &"ui_card_place"
const CARD_REMOVE: StringName = &"ui_card_remove"
## Every id the HUD sends (each has its recipe in `audio/sfx/<id>/`).
const IDS: Array[StringName] = [MOVE, CHOOSE, BACK, DENY, CARD_PLACE, CARD_REMOVE]

var _events: EventsScript = null
## The players (a bit each) whose menu acted on a press this frame (opened, chose, went back,
## paged): a focus change that follows it in the same frame is the menu's answer, not a move.
var _acted: int = 0


## Send the sound `id` (one of IDS) on `events` (none with no bus).
static func send(events: EventsScript, id: StringName) -> void:
	if events != null:
		events.ui_sound_requested.emit(id)


func _ready() -> void:
	# Menus are worked while the game is paused, so the frame's marks are cleared then too.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Hear `ui_focus` and send on `events` (called once by `panels.gd`).
func bind(events: EventsScript, ui_focus: UIFocusScript) -> void:
	_events = events
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
	send(_events, BACK)


func _on_paged(player: int, _step: int) -> void:
	_mark(player)


func _on_focus_changed(player: int, _control: Control) -> void:
	if _acted & (1 << player) == 0:
		send(_events, MOVE)
