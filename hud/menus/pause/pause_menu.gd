extends PanelContainer
## The pause menu (owner, 2026-10-26): `pause` (Start; Escape on the keyboard) opens it for the
## player who pressed it, and it stops the game for everyone (co-op rule 6: only the real pause
## menu stops the game, and any player can open it). `hud/panels/panels.gd` opens and closes it
## (node Root/PauseMenu); it sits in the middle of the view.
##
## Pages, one list of buttons each:
## - **Main:** Resume, Sandbox (only while the run is a sandbox, `sandbox_changed`), Settings.
## - **Sandbox** (staffs B7): Imp wave and Reset dummies (each sends
##   `sandbox_action_requested(player, imp_wave | reset_dummies)` and stays on the page); the
##   builder switches (owner, 2026-10-26), each flipping on `accept` and staying on the page:
##   "Builder: Radial" (the default) or "List", "Ring: Every card" or "One kind" and "Full slot: Push right"
##   or "Replace" (the radial builder's options); each flip sends `builder_options_changed`,
##   which `hud/panels` applies to every player's builder. Back.
## - **Settings:** Gameplay, Back.
## - **Gameplay:** "Friendly fire: Off" (or On), which sends `friendly_fire_requested(player, on)`;
##   the word follows `friendly_fire_changed` from coop, never the press itself. Back.
##
## Only the player who opened it works it, through `core/ui_focus`: up/left and down/right move,
## `accept` (A) activates, `back` (B) goes up a page and closes it from the main page; `pause`
## again closes it (panels.gd). Every button of every page is in one UIFocus list and the
## buttons of the other pages are hidden, so UIFocus skips them. The focused button is marked
## with "> ", never by colour alone. Closing it (or its player's device leaving) un-pauses.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")

const PLAYER_COUNT: int = 4
enum Page { MAIN, SANDBOX, SETTINGS, GAMEPLAY }
## The title of each page.
const TITLES: Dictionary = {
	Page.MAIN: "PAUSED", Page.SANDBOX: "SANDBOX", Page.SETTINGS: "SETTINGS", Page.GAMEPLAY: "GAMEPLAY",
}
## The sandbox actions, as flow knows them.
const ACTION_IMP_WAVE: StringName = &"imp_wave"
const ACTION_RESET_DUMMIES: StringName = &"reset_dummies"
const FRIENDLY_FIRE_TEXT: String = "Friendly fire: %s"
const FOCUS_MARK: String = "> "
## The meta key that keeps a button's text without the focus mark.
const BASE_TEXT_META: StringName = &"base_text"

## The menu closed (resumed). Carries the player who had it.
signal closed_menu(player: int)
## A builder switch on the Sandbox page flipped: the radial builder or the list one, the ring by
## kind or every card, a full slot pushed right or replaced.
signal builder_options_changed(radial: bool, ring_by_kind: bool, push: bool)

const BUILDER_TEXT: String = "Builder: %s"
const RING_TEXT: String = "Ring: %s"
const PUT_TEXT: String = "Full slot: %s"

## The player working the menu (0-3), or -1 while it is closed.
var owner_player: int = -1
## The page shown.
var page: Page = Page.MAIN

var _events: EventsScript = null
var _ui_focus: UIFocusScript = null
var _sandbox_on: bool = false
var _friendly_fire: bool = false
var _focused: Control = null
var _controls: Array[Control] = []
## Page -> its buttons, in order.
var _pages: Dictionary = {}
## The builder switches (see the top); the radial builder by default (owner, 2026-10-26).
var builder_radial: bool = true
var ring_by_kind: bool = false
var put_push: bool = true

@onready var _title: Label = %Title
@onready var _rows: VBoxContainer = %Rows
@onready var _resume: Button = _add(Page.MAIN, "Resume", "Resume")
@onready var _sandbox: Button = _add(Page.MAIN, "Sandbox", "Sandbox")
@onready var _settings: Button = _add(Page.MAIN, "Settings", "Settings")
@onready var _imp_wave: Button = _add(Page.SANDBOX, "ImpWave", "Imp wave")
@onready var _reset: Button = _add(Page.SANDBOX, "ResetDummies", "Reset dummies")
@onready var _builder_style: Button = _add(Page.SANDBOX, "BuilderStyle", BUILDER_TEXT % "Radial")
@onready var _ring_style: Button = _add(Page.SANDBOX, "RingStyle", RING_TEXT % "Every card")
@onready var _put_style: Button = _add(Page.SANDBOX, "PutStyle", PUT_TEXT % "Push right")
@onready var _sandbox_back: Button = _add(Page.SANDBOX, "SandboxBack", "Back")
@onready var _gameplay: Button = _add(Page.SETTINGS, "Gameplay", "Gameplay")
@onready var _settings_back: Button = _add(Page.SETTINGS, "SettingsBack", "Back")
@onready var _friendly: Button = _add(Page.GAMEPLAY, "FriendlyFire", FRIENDLY_FIRE_TEXT % "Off")
@onready var _gameplay_back: Button = _add(Page.GAMEPLAY, "GameplayBack", "Back")


func _ready() -> void:
	# Worked while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_show_page(Page.MAIN)


## Connect to the event bus and the focus service (called once by `panels.gd`).
func bind(events: EventsScript, ui_focus: UIFocusScript) -> void:
	_events = events
	_ui_focus = ui_focus
	if _events != null:
		_events.sandbox_changed.connect(_on_sandbox_changed)
		_events.friendly_fire_changed.connect(_on_friendly_fire_changed)
	if _ui_focus != null:
		_ui_focus.closed.connect(_on_closed)
		_ui_focus.activated.connect(_on_activated)
		_ui_focus.cancelled.connect(_on_cancelled)
		_ui_focus.focus_changed.connect(_on_focus_changed)


func is_open() -> bool:
	return owner_player >= 0


## Open the menu for `player` on its main page and pause the game. False when it is open
## already, or the player has no device.
func open_menu(player: int) -> bool:
	if is_open() or _ui_focus == null or player < 0 or player >= PLAYER_COUNT:
		return false
	# Close the player's builder first: its `closed` would hide this node if it came during open.
	_ui_focus.close(player)
	owner_player = player
	_title.theme_type_variation = StringName("PlayerLabel%d" % (player + 1))
	theme_type_variation = StringName("PlayerPanel%d" % (player + 1))
	_show_page(Page.MAIN)
	visible = true
	if not _ui_focus.open(player, _controls):
		owner_player = -1
		visible = false
		return false
	_set_paused(true)
	_focus_first()
	return true


## Close the menu if it is open; the game goes on.
func close_menu() -> bool:
	if not is_open() or _ui_focus == null:
		return false
	return _ui_focus.close(owner_player)


## The button of a page by its node name (for tests and screenshots), or null.
func button(button_name: String) -> Button:
	return _rows.get_node_or_null(button_name) as Button


## The buttons of the page shown, in order.
func shown_buttons() -> Array[Button]:
	var shown: Array[Button] = []
	for control: Button in _pages[page]:
		if control.visible:
			shown.append(control)
	return shown


func _add(on_page: Page, node_name: String, text: String) -> Button:
	var made := Button.new()
	made.name = node_name
	made.focus_mode = Control.FOCUS_NONE
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	made.set_meta(BASE_TEXT_META, text)
	made.text = text
	_rows.add_child(made)
	_controls.append(made)
	if not _pages.has(on_page):
		_pages[on_page] = []
	(_pages[on_page] as Array).append(made)
	return made


func _show_page(next: Page) -> void:
	page = next
	_title.text = TITLES[next] if owner_player < 0 else "P%d %s" % [owner_player + 1, TITLES[next]]
	for on_page: int in _pages:
		for control: Button in _pages[on_page]:
			control.visible = on_page == next
	_sandbox.visible = next == Page.MAIN and _sandbox_on
	_mark_focus()


func _go(next: Page) -> void:
	_show_page(next)
	_focus_first()


func _focus_first() -> void:
	if _ui_focus == null or not is_open():
		return
	var shown: Array[Button] = shown_buttons()
	if not shown.is_empty():
		_ui_focus.focus(owner_player, shown[0])
	_focused = _ui_focus.focused(owner_player)
	_mark_focus()


func _mark_focus() -> void:
	for control in _controls:
		var shown := control as Button
		shown.text = (FOCUS_MARK if shown == _focused else "") + str(shown.get_meta(BASE_TEXT_META, ""))


func _set_paused(on: bool) -> void:
	if is_inside_tree():
		get_tree().paused = on


func _on_sandbox_changed(on: bool) -> void:
	_sandbox_on = on
	if not on and page == Page.SANDBOX:
		_go(Page.MAIN)
	else:
		_show_page(page)


func _on_friendly_fire_changed(on: bool) -> void:
	_friendly_fire = on
	_friendly.set_meta(BASE_TEXT_META, FRIENDLY_FIRE_TEXT % ("On" if on else "Off"))
	_mark_focus()


func _on_closed(player: int) -> void:
	if player != owner_player:
		return
	owner_player = -1
	_focused = null
	visible = false
	_show_page(Page.MAIN)
	_set_paused(false)
	closed_menu.emit(player)


func _on_focus_changed(player: int, control: Control) -> void:
	if player == owner_player:
		_focused = control
		_mark_focus()


func _on_activated(player: int, control: Control) -> void:
	if player != owner_player:
		return
	if control == _resume:
		close_menu()
	elif control == _sandbox:
		_go(Page.SANDBOX)
	elif control == _settings:
		_go(Page.SETTINGS)
	elif control == _imp_wave:
		_send(ACTION_IMP_WAVE)
	elif control == _reset:
		_send(ACTION_RESET_DUMMIES)
	elif control == _builder_style:
		builder_radial = not builder_radial
		_show_builder_options()
	elif control == _ring_style:
		ring_by_kind = not ring_by_kind
		_show_builder_options()
	elif control == _put_style:
		put_push = not put_push
		_show_builder_options()
	elif control == _gameplay:
		_go(Page.GAMEPLAY)
	elif control == _friendly:
		if _events != null:
			_events.friendly_fire_requested.emit(player, not _friendly_fire)
	elif control == _sandbox_back or control == _settings_back:
		_go(Page.MAIN)
	elif control == _gameplay_back:
		_go(Page.SETTINGS)


## `back` goes up a page; on the main page it resumes.
func _on_cancelled(player: int) -> void:
	if player != owner_player:
		return
	match page:
		Page.MAIN:
			close_menu()
		Page.GAMEPLAY:
			_go(Page.SETTINGS)
		_:
			_go(Page.MAIN)


## Write the switches' words and tell `hud/panels`.
func _show_builder_options() -> void:
	_builder_style.set_meta(BASE_TEXT_META, BUILDER_TEXT % ("Radial" if builder_radial else "List"))
	_ring_style.set_meta(BASE_TEXT_META, RING_TEXT % ("One kind" if ring_by_kind else "Every card"))
	_put_style.set_meta(BASE_TEXT_META, PUT_TEXT % ("Push right" if put_push else "Replace"))
	_mark_focus()
	builder_options_changed.emit(builder_radial, ring_by_kind, put_push)


func _send(action: StringName) -> void:
	if _events != null:
		_events.sandbox_action_requested.emit(owner_player, action)
