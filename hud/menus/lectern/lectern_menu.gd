extends PanelContainer
## A seat's lectern menu (run generation RG7, docs/milestones/run-generation.md, "The lectern"): the
## depths of the stone's run's map, one button each ("Room 1" up to "The boss", `DepthWords`), the
## party's pick now marked. `hud/panels/panels.gd` opens it for its seat (nodes Root/Lectern1 to
## Root/Lectern4) when that seat presses A at the lectern with no menu open; it is that seat's alone
## and pauses nothing. `accept` on a depth sends the command `start_depth_picked(seat, depth)` and
## closes it; `back` closes it with nothing sent. It closes by itself when its seat leaves the
## lectern or the party leaves the hub (`lectern_changed`, `start_depth_changed`). Display and
## intent only: what the party starts at is Flow's, told back by `start_depth_changed`.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")

const TITLE_TEXT: String = "Start the run at"
## Marks the focused depth, and the one the party starts at now.
const FOCUS_MARK: String = "> "
const PICKED_MARK: String = " *"
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
## What the party starts at now and how many depths are offered (`start_depth_changed`).
var _depth: int = 0
var _depths: int = 0


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
	_title.text = TITLE_TEXT
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.theme_type_variation = StringName("PlayerLabel%d" % (index + 1))
	_rows.add_child(_title)


## Connect to the event bus and the focus service (called once by `panels.gd`).
func bind(events: EventsScript, ui_focus: UIFocusScript) -> void:
	_events = events
	_ui_focus = ui_focus
	if _events != null:
		_events.lectern_changed.connect(_on_lectern_changed)
		_events.start_depth_changed.connect(_on_start_depth_changed)
	if _ui_focus != null:
		_ui_focus.closed.connect(_on_closed)
		_ui_focus.activated.connect(_on_activated)
		_ui_focus.cancelled.connect(_on_cancelled)
		_ui_focus.focus_changed.connect(_on_focus_changed)


func is_open() -> bool:
	return _open


## Open it for its seat on the depth the party starts at now (closing any other panel of theirs).
## False with no depth offered, already open, or the seat has no device.
func open_menu() -> bool:
	if _open or _ui_focus == null or _depths <= 0:
		return false
	_ui_focus.close(index)
	_fill()
	visible = true
	var controls: Array[Control] = []
	for button: Button in _buttons:
		controls.append(button)
	if not _ui_focus.open(index, controls):
		visible = false
		return false
	_open = true
	_ui_focus.focus(index, _buttons[clampi(_depth, 0, _buttons.size() - 1)])
	return true


## Close it if it is open.
func close_menu() -> bool:
	if not _open or _ui_focus == null:
		return false
	return _ui_focus.close(index)


## Its depth buttons, in order (for tests and screenshots).
func buttons() -> Array[Button]:
	return _buttons.duplicate()


## One button a depth offered, the party's pick marked.
func _fill() -> void:
	for button: Button in _buttons:
		_rows.remove_child(button)
		button.queue_free()
	_buttons.clear()
	for depth in _depths:
		var made := Button.new()
		made.name = "Depth%d" % depth
		made.focus_mode = Control.FOCUS_NONE
		made.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rows.add_child(made)
		_buttons.append(made)
	_focused = null
	_mark()


func _mark() -> void:
	for depth in _buttons.size():
		var words: String = DepthWords.of(depth, _depths) + (PICKED_MARK if depth == _depth else "")
		_buttons[depth].text = (FOCUS_MARK if _buttons[depth] == _focused else "") + words


func _on_lectern_changed(seats: int) -> void:
	if seats & (1 << index) == 0:
		close_menu()


func _on_start_depth_changed(depth: int, depths: int) -> void:
	var offered_before: int = _depths
	_depth = depth
	_depths = depths
	if not _open:
		return
	if depths != offered_before:
		# The hub was left (none offered) or the run changed: the list it showed is gone.
		close_menu()
	else:
		_mark()


func _on_closed(player: int) -> void:
	if player != index:
		return
	_open = false
	_focused = null
	visible = false


func _on_focus_changed(player: int, control: Control) -> void:
	if player == index and _open:
		_focused = control
		_mark()


func _on_activated(player: int, control: Control) -> void:
	if player != index or not _open:
		return
	var depth: int = _buttons.find(control as Button)
	if depth < 0:
		return
	if _events != null:
		_events.start_depth_picked.emit(index, depth)
	close_menu()


func _on_cancelled(player: int) -> void:
	if player == index and _open:
		close_menu()
