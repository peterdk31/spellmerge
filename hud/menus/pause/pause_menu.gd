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
##   enemy arena (enemy AI AI8): "Enemy: <name>" (every enemy in the registry, by its
##   `shown_name()`; left and right or `accept` step through them), "Count: 1" (1-8, the same
##   way), "Spawn" (`sandbox_spawn_requested(player, enemy id, count)`), "Clear enemies"
##   (`sandbox_action_requested(player, clear_enemies)`) and "AI view: Off" (`ai_view_changed`: each
##   enemy shows its AI's behaviour and step); the
##   builder switches (owner, 2026-10-26), each flipping on `accept` and staying on the page:
##   "Builder: Radial" (the default) or "List", "Ring:" ("Every card", "One kind", or the ring
##   styles to try, owner 2026-10-30: "Zoom", "Kinds: hold", "Kinds: depth"; `accept` steps to the
##   next, `Ring`) and "Full slot: Push right" or "Replace" (the radial builder's options); each flip sends `builder_options_changed`,
##   which `hud/panels` applies to every player's builder. "Reload: Button" (the default) or
##   "Next cast" (owner, 2026-10-27): where the corner panels' staff rows show a staff's delay;
##   each flip sends `reload_style_changed`, which `hud/panels` applies to every panel. Back.
## - **Settings:** "Fullscreen: Off" (or On), "Effect slots: 256", Back. The switch asks
##   `Display` (core) to fill the screen or not and stays on the page; its word follows the window
##   itself, read each time the page is shown, so leaving fullscreen with the browser's Escape shows
##   Off again. "Effect slots" is a slider (the owner, 2026-10-27): left and right move it a step
##   (`EffectSlots` in core/settings: its STEP, from MIN to MAX), `accept` a step up (from the
##   top back to the bottom), up and down leave it; each move sends `effect_slots_changed`, which
##   feel applies. It is kept in memory only: it is not saved yet (`core/save` has settings now). "Screen shake: On" (or Off), the
##   last switch above Back (melee I6): `accept` flips it, it sends `screen_shake_changed`, which
##   feel applies, and the choice is saved (`SaveFile` setting `screen_shake`) and read again
##   when the menu is bound, so it holds between plays. (The Gameplay page, with
##   "Friendly fire" and "Enemy fire", went in actors G3c: every spell hits everything, always.)
##
## Only the player who opened it works it, through `core/ui_focus`: up/left and down/right move,
## `accept` (A) activates, `back` (B) goes up a page and closes it from the main page; `pause`
## again closes it (panels.gd). Every button of every page is in one UIFocus list and the
## buttons of the other pages are hidden, so UIFocus skips them. The focused button is marked
## with "> ", never by colour alone. Closing it (or its player's device leaving) un-pauses,
## except in the horde's build break (`horde_break_changed(true)` until `(false)`; owner,
## 2026-10-31), which keeps the game paused until every player is ready: closing the menu then
## leaves the tree paused, and a break that ends while the menu is open (the director
## un-pauses) is paused again here, until the menu closes.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")

const PLAYER_COUNT: int = 4
enum Page { MAIN, SANDBOX, SETTINGS }
## The radial builder's ring (see the top): the plain one with every card or one kind at a time,
## or a ring style from `hud/builder/rings/`.
enum Ring { EVERY_CARD, ONE_KIND, ZOOM, KINDS_HOLD, KINDS_DEPTH }
## The title of each page.
const TITLES: Dictionary = {
	Page.MAIN: "PAUSED", Page.SANDBOX: "SANDBOX", Page.SETTINGS: "SETTINGS",
}
## The sandbox actions, as flow knows them.
const ACTION_IMP_WAVE: StringName = &"imp_wave"
const ACTION_RESET_DUMMIES: StringName = &"reset_dummies"
const FOCUS_MARK: String = "> "
## The meta key that keeps a button's text without the focus mark.
const BASE_TEXT_META: StringName = &"base_text"

## The menu closed (resumed). Carries the player who had it.
signal closed_menu(player: int)
## A builder switch on the Sandbox page flipped: the radial builder or the list one, the ring by
## kind or every card, a full slot pushed right or replaced.
signal builder_options_changed(radial: bool, ring: Ring, push: bool)
## The reload switch on the Sandbox page flipped: the staff rows show the delay on the button
## glyph, or on the next cast.
signal reload_style_changed(on_button: bool)

const BUILDER_TEXT: String = "Builder: %s"
const RING_TEXT: String = "Ring: %s"
const RING_WORDS: Array[String] = ["Every card", "One kind", "Zoom", "Kinds: hold", "Kinds: depth"]
const PUT_TEXT: String = "Full slot: %s"
const RELOAD_TEXT: String = "Reload: %s"
## The enemy arena's rows (enemy AI AI8).
const ENEMY_TEXT: String = "Enemy: %s"
const COUNT_TEXT: String = "Count: %d"
const AI_VIEW_TEXT: String = "AI view: %s"
const COUNT_MAX: int = 8
const ACTION_CLEAR_ENEMIES: StringName = &"clear_enemies"
const FULLSCREEN_TEXT: String = "Fullscreen: %s"
const EFFECT_SLOTS_TEXT: String = "Effect slots: %d"
const SHAKE_TEXT: String = "Screen shake: %s"
## The saved setting that holds the choice.
const SHAKE_SETTING: StringName = &"screen_shake"
## The slider bar beside the words: this wide, at the right of the row.
const SLIDER_WIDTH: float = 64.0

## The player working the menu (0-3), or -1 while it is closed.
var owner_player: int = -1
## The page shown.
var page: Page = Page.MAIN

var _events: EventsScript = null
var _ui_focus: UIFocusScript = null
var _sandbox_on: bool = false
## True during the horde's build break (it holds the game paused).
var _horde_break: bool = false
var _focused: Control = null
var _controls: Array[Control] = []
## Page -> its buttons, in order.
var _pages: Dictionary = {}
## The builder switches (see the top); the radial builder by default (owner, 2026-10-26).
var builder_radial: bool = true
var ring: Ring = Ring.EVERY_CARD
var put_push: bool = true
## The reload switch (see the top); the button glyph by default (owner, 2026-10-27).
var reload_on_button: bool = true
## The "Effect slots" setting (see the top).
var effect_slots: int = EffectSlots.DEFAULT
## The "Screen shake" setting (see the top): on by default.
var screen_shake: bool = true
## The save that keeps settings; made when the menu is bound, unless a test set its own first.
var save: SaveFile = null
## The window service (`core/display`, the `Display` autoload); tests may set their own first.
var display: Node = null
## The content registry the enemy arena lists enemies from; tests may set their own first, else
## the `Registry` autoload.
var registry: Node = null
## The enemy arena's choice: the enemies' ids (read when the sandbox page opens), the one picked,
## how many, and whether the AI view is on.
var arena_ids: Array[StringName] = []
var arena_names: PackedStringArray = PackedStringArray()
var arena_pick: int = 0
var arena_count: int = 1
var ai_view: bool = false

@onready var _title: Label = %Title
@onready var _rows: VBoxContainer = %Rows
@onready var _resume: Button = _add(Page.MAIN, "Resume", "Resume")
@onready var _sandbox: Button = _add(Page.MAIN, "Sandbox", "Sandbox")
@onready var _settings: Button = _add(Page.MAIN, "Settings", "Settings")
@onready var _imp_wave: Button = _add(Page.SANDBOX, "ImpWave", "Imp wave")
@onready var _reset: Button = _add(Page.SANDBOX, "ResetDummies", "Reset dummies")
@onready var _arena_enemy: Button = _add(Page.SANDBOX, "ArenaEnemy", ENEMY_TEXT % "-")
@onready var _arena_count: Button = _add(Page.SANDBOX, "ArenaCount", COUNT_TEXT % 1)
@onready var _arena_spawn: Button = _add(Page.SANDBOX, "ArenaSpawn", "Spawn")
@onready var _arena_clear: Button = _add(Page.SANDBOX, "ArenaClear", "Clear enemies")
@onready var _ai_view: Button = _add(Page.SANDBOX, "AIView", AI_VIEW_TEXT % "Off")
@onready var _builder_style: Button = _add(Page.SANDBOX, "BuilderStyle", BUILDER_TEXT % "Radial")
@onready var _ring_style: Button = _add(Page.SANDBOX, "RingStyle", RING_TEXT % "Every card")
@onready var _put_style: Button = _add(Page.SANDBOX, "PutStyle", PUT_TEXT % "Push right")
@onready var _reload_style: Button = _add(Page.SANDBOX, "ReloadStyle", RELOAD_TEXT % "Button")
@onready var _sandbox_back: Button = _add(Page.SANDBOX, "SandboxBack", "Back")
@onready var _fullscreen: Button = _add(Page.SETTINGS, "Fullscreen", FULLSCREEN_TEXT % "Off")
@onready var _effects: Button = _add(Page.SETTINGS, "EffectSlots", EFFECT_SLOTS_TEXT % EffectSlots.DEFAULT)
@onready var _effects_bar: HSlider = _add_slider(_effects)
@onready var _shake: Button = _add(Page.SETTINGS, "ScreenShake", SHAKE_TEXT % "On")
@onready var _settings_back: Button = _add(Page.SETTINGS, "SettingsBack", "Back")


func _ready() -> void:
	# Worked while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if display == null:
		display = get_node_or_null(^"/root/Display")
	visible = false
	_show_page(Page.MAIN)


## Connect to the event bus and the focus service (called once by `panels.gd`).
func bind(events: EventsScript, ui_focus: UIFocusScript) -> void:
	_events = events
	_ui_focus = ui_focus
	if save == null:
		save = SaveFile.new()
	_load_shake()
	if _events != null:
		_events.sandbox_changed.connect(_on_sandbox_changed)
		_events.horde_break_changed.connect(_on_horde_break_changed)
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
	# Left and right work the slider; everywhere else they move as usual.
	_ui_focus.set_navigator(player, _navigate)
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


## A slider bar drawn in `row` (at its right), for show only: the row works it (see the top).
func _add_slider(row: Button) -> HSlider:
	var bar := HSlider.new()
	bar.name = "Bar"
	bar.min_value = EffectSlots.MIN
	bar.max_value = EffectSlots.MAX
	bar.step = EffectSlots.STEP
	bar.value = effect_slots
	bar.editable = false
	bar.focus_mode = Control.FOCUS_NONE
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	bar.offset_left = -SLIDER_WIDTH - 4.0
	bar.offset_right = -4.0
	row.add_child(bar)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Wide enough for the longest words (focused, at the top) and the bar beside them.
	var font: Font = row.get_theme_font(&"font")
	var longest: float = font.get_string_size(FOCUS_MARK + EFFECT_SLOTS_TEXT % EffectSlots.MAX, HORIZONTAL_ALIGNMENT_LEFT, -1, row.get_theme_font_size(&"font_size")).x
	row.custom_minimum_size.x = longest + SLIDER_WIDTH + 24.0
	return bar


## The menu's navigator for UIFocus: left and right on the slider move it and keep the focus
## there; any other move goes on as usual (null).
func _navigate(control: Control, direction: Vector2i) -> Control:
	if control == _effects and direction.x != 0:
		_set_effect_slots(effect_slots + direction.x * EffectSlots.STEP)
		return _effects
	if control == _arena_enemy and direction.x != 0:
		_pick_enemy(arena_pick + direction.x)
		return _arena_enemy
	if control == _arena_count and direction.x != 0:
		_set_count(clampi(arena_count + direction.x, 1, COUNT_MAX))
		return _arena_count
	return null


## The enemy arena: read every enemy from the registry (each time the sandbox page opens, so a
## new folder shows up), keeping the one picked if it is still there.
func _read_arena() -> void:
	var source: Node = registry if registry != null else get_node_or_null(^"/root/Registry")
	var before: StringName = arena_ids[arena_pick] if arena_pick < arena_ids.size() else &""
	arena_ids.clear()
	arena_names.clear()
	if source != null:
		for item: Variant in source.call("get_all", &"enemies"):
			var data := item as EnemyBase
			if data != null and data.scene != null:
				arena_ids.append(data.id)
				arena_names.append(data.shown_name())
	arena_pick = maxi(arena_ids.find(before), 0)
	_pick_enemy(arena_pick)


## Pick enemy `at` (wrapping round the list) and show it.
func _pick_enemy(at: int) -> void:
	if arena_ids.is_empty():
		arena_pick = 0
		_arena_enemy.set_meta(BASE_TEXT_META, ENEMY_TEXT % "-")
	else:
		arena_pick = posmod(at, arena_ids.size())
		_arena_enemy.set_meta(BASE_TEXT_META, ENEMY_TEXT % arena_names[arena_pick])
	_mark_focus()


func _set_count(count: int) -> void:
	arena_count = count
	_arena_count.set_meta(BASE_TEXT_META, COUNT_TEXT % arena_count)
	_mark_focus()


## Move the slider to `slots` (inside its range), show it and tell feel.
func _set_effect_slots(slots: int) -> void:
	var next: int = clampi(slots, EffectSlots.MIN, EffectSlots.MAX)
	if next == effect_slots:
		return
	effect_slots = next
	_effects.set_meta(BASE_TEXT_META, EFFECT_SLOTS_TEXT % effect_slots)
	_effects_bar.value = effect_slots
	_mark_focus()
	if _events != null:
		_events.effect_slots_changed.emit(effect_slots)


func _show_page(next: Page) -> void:
	page = next
	_title.text = TITLES[next] if owner_player < 0 else "P%d %s" % [owner_player + 1, TITLES[next]]
	for on_page: int in _pages:
		for control: Button in _pages[on_page]:
			control.visible = on_page == next
	_sandbox.visible = next == Page.MAIN and _sandbox_on
	if next == Page.SETTINGS:
		_show_fullscreen()
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


## The horde's build break began or ended. The director un-pauses before it says the break ended,
## so an open menu pauses again.
func _on_horde_break_changed(on: bool) -> void:
	_horde_break = on
	if not on and is_open():
		_set_paused(true)


func _on_sandbox_changed(on: bool) -> void:
	_sandbox_on = on
	if not on and page == Page.SANDBOX:
		_go(Page.MAIN)
	else:
		_show_page(page)


func _on_closed(player: int) -> void:
	if player != owner_player:
		return
	owner_player = -1
	_focused = null
	visible = false
	_show_page(Page.MAIN)
	# The horde's build break keeps the game paused after the menu.
	_set_paused(_horde_break)
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
		_read_arena()
		_go(Page.SANDBOX)
	elif control == _settings:
		_go(Page.SETTINGS)
	elif control == _imp_wave:
		_send(ACTION_IMP_WAVE)
	elif control == _reset:
		_send(ACTION_RESET_DUMMIES)
	elif control == _arena_enemy:
		_pick_enemy(arena_pick + 1)
	elif control == _arena_count:
		_set_count(arena_count % COUNT_MAX + 1)
	elif control == _arena_spawn:
		if _events != null and arena_pick < arena_ids.size():
			_events.sandbox_spawn_requested.emit(owner_player, arena_ids[arena_pick], arena_count)
	elif control == _arena_clear:
		_send(ACTION_CLEAR_ENEMIES)
	elif control == _ai_view:
		ai_view = not ai_view
		_ai_view.set_meta(BASE_TEXT_META, AI_VIEW_TEXT % ("On" if ai_view else "Off"))
		_mark_focus()
		if _events != null:
			_events.ai_view_changed.emit(ai_view)
	elif control == _builder_style:
		builder_radial = not builder_radial
		_show_builder_options()
	elif control == _ring_style:
		ring = ((ring + 1) % Ring.size()) as Ring
		_show_builder_options()
	elif control == _put_style:
		put_push = not put_push
		_show_builder_options()
	elif control == _reload_style:
		reload_on_button = not reload_on_button
		_reload_style.set_meta(BASE_TEXT_META, RELOAD_TEXT % ("Button" if reload_on_button else "Next cast"))
		_mark_focus()
		reload_style_changed.emit(reload_on_button)
	elif control == _fullscreen:
		if display != null:
			display.call("toggle_fullscreen")
		_show_fullscreen()
	elif control == _effects:
		_set_effect_slots(EffectSlots.MIN if effect_slots >= EffectSlots.MAX else effect_slots + EffectSlots.STEP)
	elif control == _shake:
		_set_shake(not screen_shake)
	elif control == _sandbox_back or control == _settings_back:
		_go(Page.MAIN)


## `back` goes up a page; on the main page it resumes.
func _on_cancelled(player: int) -> void:
	if player != owner_player:
		return
	match page:
		Page.MAIN:
			close_menu()
		_:
			_go(Page.MAIN)


## Read the saved choice and show it; feel is told only when it is off (on is feel's own default).
func _load_shake() -> void:
	screen_shake = bool(save.get_setting(SHAKE_SETTING, true))
	_shake.set_meta(BASE_TEXT_META, SHAKE_TEXT % ("On" if screen_shake else "Off"))
	_mark_focus()
	if not screen_shake and _events != null:
		_events.screen_shake_changed.emit(false)


## Flip the switch: show it, save it and tell feel.
func _set_shake(on: bool) -> void:
	screen_shake = on
	_shake.set_meta(BASE_TEXT_META, SHAKE_TEXT % ("On" if on else "Off"))
	_mark_focus()
	save.set_setting(SHAKE_SETTING, on)
	if _events != null:
		_events.screen_shake_changed.emit(on)


## Write the fullscreen switch's word from the window itself.
func _show_fullscreen() -> void:
	var on: bool = display != null and bool(display.call("is_fullscreen"))
	_fullscreen.set_meta(BASE_TEXT_META, FULLSCREEN_TEXT % ("On" if on else "Off"))
	_mark_focus()


## Write the switches' words and tell `hud/panels`.
func _show_builder_options() -> void:
	_builder_style.set_meta(BASE_TEXT_META, BUILDER_TEXT % ("Radial" if builder_radial else "List"))
	_ring_style.set_meta(BASE_TEXT_META, RING_TEXT % RING_WORDS[ring])
	_put_style.set_meta(BASE_TEXT_META, PUT_TEXT % ("Push right" if put_push else "Replace"))
	_mark_focus()
	builder_options_changed.emit(builder_radial, ring, put_push)


func _send(action: StringName) -> void:
	if _events != null:
		_events.sandbox_action_requested.emit(owner_player, action)
