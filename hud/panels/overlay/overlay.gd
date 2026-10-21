extends PanelContainer
## One player's overlay: a small menu beside that player's corner panel, opened
## and closed by their `overlay` action (the toggle is in `hud/panels/panels.gd`).
## It never pauses the game and never blocks another player: opening it only
## captures its owner's gameplay input through `core/ui_focus`, so the wizard
## stands still while the other three carry on.
##
## Input comes only through UIFocus: up/left and down/right move between the
## controls, `cast` activates, `dodge` goes back. Every UIFocus signal carries a
## player index and this overlay ignores all but its own, so it is the same for
## any index 0-3. The focused control is marked with "> " in front of its text,
## so the focus is never shown by colour alone.
##
## "Build slot 1" is a stub (M1 has no spell builder yet): it only sends
## `build_change_requested(player, [0], 0, STUB_COMPONENT)` and changes nothing here.
## Gameplay checks the request and refuses what it does not know.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")

const PLAYER_COUNT: int = 4
## The slot and the component the stub button asks for.
## The spell path `[0]`: spell A.
const STUB_SPELL: PackedInt32Array = [0]
const STUB_SLOT: int = 0
const STUB_COMPONENT: StringName = &"stub"
const RESUME_TEXT: String = "Resume"
const BUILD_TEXT: String = "Build slot 1"
const FOCUS_MARK: String = "> "

## The player index 0-3. Set before adding the node to the tree.
@export var index: int = 0

var _events: EventsScript = null
var _ui_focus: UIFocusScript = null
var _open: bool = false

@onready var _title: Label = %Title
@onready var _resume: Button = %Resume
@onready var _build: Button = %Build


func _ready() -> void:
	var player: int = clampi(index, 0, PLAYER_COUNT - 1)
	theme_type_variation = StringName("PlayerPanel%d" % (player + 1))
	_title.theme_type_variation = StringName("PlayerLabel%d" % (player + 1))
	_title.text = "P%d MENU" % (player + 1)
	_resume.text = RESUME_TEXT
	_build.text = BUILD_TEXT
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


## Open the overlay for its owner. False if the owner has no device or their
## panel is already taken by something else.
func open_overlay() -> bool:
	if _open or _ui_focus == null or _ui_focus.is_open(index):
		return false
	var controls: Array[Control] = [_resume, _build]
	# Visible first: UIFocus only focuses controls that are shown.
	visible = true
	if not _ui_focus.open(index, controls):
		visible = false
		return false
	_open = true
	_mark_focus(_ui_focus.focused(index))
	return true


## Close the overlay if it is open.
func close_overlay() -> bool:
	if not _open or _ui_focus == null:
		return false
	return _ui_focus.close(index)


## Open if closed, close if open: what the `overlay` action does.
func toggle() -> void:
	if _open:
		close_overlay()
	else:
		open_overlay()


func _mark_focus(control: Control) -> void:
	_resume.text = (FOCUS_MARK if control == _resume else "") + RESUME_TEXT
	_build.text = (FOCUS_MARK if control == _build else "") + BUILD_TEXT


func _on_closed(player: int) -> void:
	if player != index:
		return
	_open = false
	visible = false


func _on_focus_changed(player: int, control: Control) -> void:
	if player == index and _open:
		_mark_focus(control)


func _on_activated(player: int, control: Control) -> void:
	if player != index or not _open:
		return
	if control == _resume:
		close_overlay()
	elif control == _build and _events != null:
		_events.build_change_requested.emit(index, STUB_SPELL, STUB_SLOT, STUB_COMPONENT)


func _on_cancelled(player: int) -> void:
	if player == index and _open:
		close_overlay()
