extends PanelContainer
## One player's sandbox page (staffs B7, docs/milestones/M2-staffs.md, "The sandbox"): the
## sandbox actions, opened from the "Sandbox" line of that player's overlay and shown in the
## overlay's place. `hud/panels/panels.gd` makes one per player (nodes Root/Sandbox1-4).
##
## Like the overlay it never pauses the game and takes only its owner's input through
## `core/ui_focus`: up/left and down/right move, `cast_a` activates, `cast_b` goes back. Every
## UIFocus signal carries a player index and this page ignores all but its own. The focused
## control is marked with "> ", never by colour alone.
##
## "Imp wave" and "Reset dummies" send `sandbox_action_requested(player, action)` and keep the
## page open, so a player can press again; flow applies them to the room, never to another
## player's staffs or menus. "Back" (or `cast_b`) sends the local signal `back_pressed(player)`,
## and panels.gd opens the overlay again.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")

const PLAYER_COUNT: int = 4
const TITLE: String = "SANDBOX"
const IMP_WAVE_TEXT: String = "Imp wave"
const RESET_TEXT: String = "Reset dummies"
const BACK_TEXT: String = "Back"
## The actions sent, as flow knows them.
const ACTION_IMP_WAVE: StringName = &"imp_wave"
const ACTION_RESET_DUMMIES: StringName = &"reset_dummies"
const FOCUS_MARK: String = "> "
## The meta key that keeps a button's text without the focus mark.
const BASE_TEXT_META: StringName = &"base_text"

## The owner left the page with "Back" or `cast_b`. Carries the index of this page.
signal back_pressed(player: int)

## The player index 0-3. Set before adding the node to the tree.
@export var index: int = 0

var _events: EventsScript = null
var _ui_focus: UIFocusScript = null
var _open: bool = false
var _focused: Control = null
var _controls: Array[Control] = []

@onready var _title: Label = %Title
@onready var _imp_wave: Button = %ImpWave
@onready var _reset: Button = %ResetDummies
@onready var _back: Button = %Back


func _ready() -> void:
	var player: int = clampi(index, 0, PLAYER_COUNT - 1)
	theme_type_variation = StringName("PlayerPanel%d" % (player + 1))
	_title.theme_type_variation = StringName("PlayerLabel%d" % (player + 1))
	_title.text = "P%d %s" % [player + 1, TITLE]
	_imp_wave.set_meta(BASE_TEXT_META, IMP_WAVE_TEXT)
	_reset.set_meta(BASE_TEXT_META, RESET_TEXT)
	_back.set_meta(BASE_TEXT_META, BACK_TEXT)
	_controls = [_imp_wave, _reset, _back]
	_mark_focus()
	visible = false


## Connect to the event bus and the focus service (called once by `panels.gd`).
func bind(events: EventsScript, ui_focus: UIFocusScript) -> void:
	_events = events
	_ui_focus = ui_focus
	if _ui_focus != null:
		_ui_focus.closed.connect(_on_closed)
		_ui_focus.activated.connect(_on_activated)
		_ui_focus.cancelled.connect(_on_cancelled)
		_ui_focus.focus_changed.connect(_on_focus_changed)


func is_open() -> bool:
	return _open


## Open the page for its owner, taking the focus over from the overlay. False without a focus
## service or when the owner has no device.
func open_page() -> bool:
	if _open or _ui_focus == null:
		return false
	_focused = null
	# Close the overlay's panel first: its `closed` would hide this node if it came during open.
	_ui_focus.close(index)
	# Visible first: UIFocus only focuses controls that are shown.
	visible = true
	if not _ui_focus.open(index, _controls):
		visible = false
		return false
	_open = true
	_focused = _ui_focus.focused(index)
	_mark_focus()
	return true


## Close the page if it is open.
func close_page() -> bool:
	if not _open or _ui_focus == null:
		return false
	return _ui_focus.close(index)


## The buttons, in order (for tests and screenshots).
func buttons() -> Array[Control]:
	return _controls.duplicate()


func _mark_focus() -> void:
	for control in _controls:
		var button := control as Button
		button.text = (FOCUS_MARK if button == _focused else "") + str(button.get_meta(BASE_TEXT_META, ""))


func _on_closed(player: int) -> void:
	if player != index:
		return
	_open = false
	_focused = null
	visible = false


func _on_focus_changed(player: int, control: Control) -> void:
	if player == index and _open:
		_focused = control
		_mark_focus()


func _on_activated(player: int, control: Control) -> void:
	if player != index or not _open:
		return
	if control == _imp_wave:
		_send(ACTION_IMP_WAVE)
	elif control == _reset:
		_send(ACTION_RESET_DUMMIES)
	elif control == _back:
		_go_back()


func _on_cancelled(player: int) -> void:
	if player == index and _open:
		_go_back()


func _send(action: StringName) -> void:
	if _events != null:
		_events.sandbox_action_requested.emit(index, action)


func _go_back() -> void:
	close_page()
	back_pressed.emit(index)
