extends PanelContainer
## One player's overlay: a small menu beside that player's corner panel, opened
## and closed by their `overlay` action (the toggle is in `hud/panels/panels.gd`).
## It never pauses the game and never blocks another player: opening it only
## captures its owner's gameplay input through `core/ui_focus`, so the wizard
## stands still while the other three carry on.
##
## Input comes only through UIFocus: up/left and down/right move between the
## controls, `cast_a` activates, `cast_b` goes back. Every UIFocus signal carries a
## player index and this overlay ignores all but its own, so it is the same for
## any index 0-3. The focused control is marked with "> " in front of its text,
## so the focus is never shown by colour alone.
##
## "Build" asks for this player's builder: it only sends the local signal
## `build_pressed(player)`, and `hud/panels/panels.gd` opens the builder (which takes the
## player's focus over from this overlay). The overlay sends no event for it. There is no
## quick "Bag" drop any more: the full builder is open at any time, waves included (owner,
## staffs A6a).
##
## "Sandbox" (staffs B7) shows under "Build" only while the run is a sandbox (`sandbox_changed`)
## and sends the local signal `sandbox_pressed(player)`; `hud/panels/panels.gd` opens that
## player's sandbox page (`hud/menus/sandbox/`) in the overlay's place.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const SpellsScript := preload("res://core/spells/spells.gd")

const PLAYER_COUNT: int = 4
const RESUME_TEXT: String = "Resume"
const BUILD_TEXT: String = "Build"
const SANDBOX_TEXT: String = "Sandbox"
## The title word.
const MENU_TITLE: String = "MENU"
const FOCUS_MARK: String = "> "
## The meta key that keeps a button's text without the focus mark.
const BASE_TEXT_META: StringName = &"base_text"

## The owner activated "Build". Carries the index of this overlay.
signal build_pressed(player: int)
## The owner activated "Sandbox". Carries the index of this overlay.
signal sandbox_pressed(player: int)

## The player index 0-3. Set before adding the node to the tree.
@export var index: int = 0

var _ui_focus: UIFocusScript = null
var _open: bool = false
var _focused: Control = null
var _controls: Array[Control] = []

@onready var _title: Label = %Title
@onready var _resume: Button = %Resume
@onready var _build: Button = %Build
@onready var _sandbox: Button = %Sandbox


func _ready() -> void:
	var player: int = clampi(index, 0, PLAYER_COUNT - 1)
	theme_type_variation = StringName("PlayerPanel%d" % (player + 1))
	_title.theme_type_variation = StringName("PlayerLabel%d" % (player + 1))
	_title.text = "P%d %s" % [player + 1, MENU_TITLE]
	_set_text(_resume, RESUME_TEXT)
	_set_text(_build, BUILD_TEXT)
	_set_text(_sandbox, SANDBOX_TEXT)
	_sandbox.visible = false
	_controls = [_resume, _build, _sandbox]
	visible = false


## Connect to the event bus (for `sandbox_changed`) and the focus service (called once by
## `panels.gd`). `spells` is taken for the same call as the builder's and not used.
func bind(events: EventsScript, ui_focus: UIFocusScript, _spells: SpellsScript = null) -> void:
	if events != null:
		events.sandbox_changed.connect(_on_sandbox_changed)
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
	_focused = null
	# Visible first: UIFocus only focuses controls that are shown.
	visible = true
	if not _ui_focus.open(index, _controls):
		visible = false
		return false
	_open = true
	_focused = _ui_focus.focused(index)
	_mark_focus()
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


## The "Build" button (for tests and screenshots).
func build_button() -> Button:
	return _build


## The "Sandbox" button, shown only in the sandbox (for tests and screenshots).
func sandbox_button() -> Button:
	return _sandbox


func _on_sandbox_changed(on: bool) -> void:
	_sandbox.visible = on


func _set_text(button: Button, text: String) -> void:
	button.set_meta(BASE_TEXT_META, text)
	button.text = (FOCUS_MARK if button == _focused else "") + text


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
	if control == _resume:
		close_overlay()
	elif control == _build:
		build_pressed.emit(index)
	elif control == _sandbox:
		sandbox_pressed.emit(index)


func _on_cancelled(player: int) -> void:
	if player == index and _open:
		close_overlay()
