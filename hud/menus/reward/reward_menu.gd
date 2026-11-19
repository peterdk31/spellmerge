extends PanelContainer
## A seat's reward menu (connected biomes CB10, decisions 16 and 17; DESIGN rules 3 and 4): the
## oldest of the seat's offers not yet picked (`rewards_waiting_changed`), "Pick 1 of 2", one button
## a choice (its name, as the Rewards area's view says). `hud/panels/panels.gd` opens it for its seat
## (nodes Root/Reward1 to Root/Reward4): by itself as an offer is rolled for a seat whose wizard was
## in the room (`reward_rolled`'s `here`: `wants_open`), and on the seat's A with no menu open and
## nothing else for A while it has one waiting (the unspent icon on its corner panel says so). It is
## that seat's alone and pauses nothing (pillar 2). `accept` on a choice sends the command
## `reward_pick_requested(seat, offer, choice)` and closes it; `back` closes it with nothing sent, the
## offer left unspent. It closes by itself when the offer it shows is gone. Display and intent
## only: what a pick gives is the Rewards area's, told back by `rewards_waiting_changed`.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")

const TITLE_TEXT: String = "Pick 1 of %d"
## Marks the focused choice.
const FOCUS_MARK: String = "> "
const MIN_WIDTH: float = 96.0

## The seat it belongs to (0-3), set before it enters the tree.
var index: int = 0

var _events: EventsScript = null
var _ui_focus: UIFocusScript = null
var _rows: VBoxContainer = null
var _title: Label = null
var _buttons: Array[Button] = []
var _focused: Control = null
var _open: bool = false
## The seat's offers waiting, oldest first (`rewards_waiting_changed`), and the one shown (-1: none).
var _offers: Array[Dictionary] = []
var _shown: int = -1
## An offer was rolled while the seat's wizard was there: the panels open it when they may.
var _wants_open: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(MIN_WIDTH, 0.0)
	theme_type_variation = StringName("PlayerPanel%d" % (index + 1))
	visible = false
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override(&"separation", 2)
	add_child(_rows)
	_title = Label.new()
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.theme_type_variation = StringName("PlayerLabel%d" % (index + 1))
	_rows.add_child(_title)


## Connect to the event bus and the focus service (called once by `panels.gd`).
func bind(events: EventsScript, ui_focus: UIFocusScript) -> void:
	_events = events
	_ui_focus = ui_focus
	if _events != null:
		_events.rewards_waiting_changed.connect(_on_rewards_waiting_changed)
		_events.reward_rolled.connect(_on_reward_rolled)
	if _ui_focus != null:
		_ui_focus.closed.connect(_on_closed)
		_ui_focus.activated.connect(_on_activated)
		_ui_focus.cancelled.connect(_on_cancelled)
		_ui_focus.focus_changed.connect(_on_focus_changed)


func is_open() -> bool:
	return _open


## How many of the seat's offers wait (the unspent count).
func waiting() -> int:
	return _offers.size()


## True once an offer was rolled with the seat's wizard there and the menu has not opened since.
func wants_open() -> bool:
	return _wants_open and not _offers.is_empty()


## Open it for its seat on its oldest offer (closing any other panel of theirs). False with none
## waiting, already open, or the seat has no device.
func open_menu() -> bool:
	_wants_open = false
	if _open or _ui_focus == null or _offers.is_empty():
		return false
	_ui_focus.close(index)
	_fill(_offers[0])
	visible = true
	var controls: Array[Control] = []
	for button: Button in _buttons:
		controls.append(button)
	if not _ui_focus.open(index, controls):
		visible = false
		_shown = -1
		return false
	_open = true
	_ui_focus.focus(index, _buttons[0])
	return true


## Close it if it is open (the offer stays unspent).
func close_menu() -> bool:
	if not _open or _ui_focus == null:
		return false
	return _ui_focus.close(index)


## Its choice buttons, in order (for tests and screenshots).
func buttons() -> Array[Button]:
	return _buttons.duplicate()


## The number of the offer it shows (-1 for none).
func shown_offer() -> int:
	return _shown


## One button a choice of `offer`.
func _fill(offer: Dictionary) -> void:
	for button: Button in _buttons:
		_rows.remove_child(button)
		button.queue_free()
	_buttons.clear()
	_shown = int(offer.get("offer", -1))
	var choices: Array = offer.get("choices", [])
	_title.text = TITLE_TEXT % choices.size()
	for choice in choices.size():
		var made := Button.new()
		made.name = "Choice%d" % choice
		made.focus_mode = Control.FOCUS_NONE
		made.mouse_filter = Control.MOUSE_FILTER_IGNORE
		made.set_meta(&"words", String((choices[choice] as Dictionary).get("name", "")))
		made.icon = (choices[choice] as Dictionary).get("icon") as Texture2D
		made.expand_icon = false
		_rows.add_child(made)
		_buttons.append(made)
	_focused = null
	_mark()


func _mark() -> void:
	for button: Button in _buttons:
		button.text = (FOCUS_MARK if button == _focused else "") + String(button.get_meta(&"words", ""))


func _on_rewards_waiting_changed(player: int, offers: Array[Dictionary]) -> void:
	if player != index:
		return
	_offers = offers.duplicate()
	if _offers.is_empty():
		_wants_open = false
	if _open and (_offers.is_empty() or int(_offers[0].get("offer", -1)) != _shown):
		# The offer it showed was picked or went (a run's start): the menu goes with it.
		close_menu()


func _on_reward_rolled(player: int, _offer: int, _choices: Array[Dictionary], here: bool) -> void:
	if player == index and here:
		_wants_open = true


func _on_closed(player: int) -> void:
	if player != index:
		return
	_open = false
	_focused = null
	_shown = -1
	visible = false


func _on_focus_changed(player: int, control: Control) -> void:
	if player == index and _open:
		_focused = control
		_mark()


func _on_activated(player: int, control: Control) -> void:
	if player != index or not _open:
		return
	var choice: int = _buttons.find(control as Button)
	if choice < 0:
		return
	UiSounds.send(_events, UiSounds.CHOOSE)
	if _events != null:
		_events.reward_pick_requested.emit(index, _shown, choice)
	close_menu()


func _on_cancelled(player: int) -> void:
	if player == index and _open:
		close_menu()
