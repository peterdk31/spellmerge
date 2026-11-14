extends PanelContainer
## The pause menu (owner, 2026-10-26): `pause` (Start; Escape on the keyboard) opens it for the
## player who pressed it, and it stops the game for everyone (co-op rule 6: only the real pause
## menu stops the game, and any player can open it). `hud/panels/panels.gd` opens and closes it
## (node Root/PauseMenu); it sits in the middle of the view.
##
## Pages, one list of buttons each:
## - **Main:** Resume, Sandbox (only while the run is a sandbox, `sandbox_changed`), Settings, Leave
##   game (`seat_leave_requested`: the seat that opened the menu lets its device go and its wizard
##   leaves, at its tick on every machine; the others play on; items I2, in place of the `leave`
##   action; the menu closes first), "Leave game: P2 (no controller)" (only while a seat of this
##   machine waits for its unplugged gamepad, `set_waiting_seats`; the lowest such seat: it leaves
##   by the same `seat_leave_requested`, the game goes on once no seat waits, and the menu stays
##   open), Main menu (`main_menu_requested`: this machine leaves the run,
##   online too, and the main menu shows again; the menu closes first).
## - **Sandbox** (staffs B7): Reset dummies (`sandbox_action_requested(player, reset_dummies)`;
##   it stays on the page); the enemy arena (enemy AI AI8): "Enemy: <name>" (every enemy in the registry, by its
##   `shown_name()`; left and right or `accept` step through them), "Count: 1" (1-8, the same
##   way), "Spawn" (`sandbox_spawn_requested(player, enemy id, count)`), "Clear enemies"
##   (`sandbox_action_requested(player, clear_enemies)`) and "AI view: Off" (`ai_view_changed`: each
##   enemy shows its AI's behaviour and step); the
##   builder switches (owner, 2026-10-26), each flipping on `accept` and staying on the page:
##   "Ring:" ("Every card", "One kind", or the ring
##   styles to try, owner 2026-10-30: "Zoom", "Kinds: hold", "Kinds: depth"; `accept` steps to the
##   next, `Ring`) and "Full slot: Push right" or "Replace" (the radial builder's options); each flip sends `builder_options_changed`,
##   which `hud/panels` applies to every player's builder. "Reload: Button" (the default) or
##   "Next cast" (owner, 2026-10-27): where the corner panels' staff rows show a staff's delay;
##   each flip sends `reload_style_changed`, which `hud/panels` applies to every panel. Back.
## - **Settings:** "Fullscreen: Off" (or On), "Effect slots: 256", "Particles: High", "Floor marks: On", "Spell light: On", "Tails: On", "Max shots: 6000", "Screen shake: On", "Damage numbers: On",
##   "Show FPS: Off", Back. The switch asks
##   `Display` (core) to fill the screen or not and stays on the page; its word follows the window
##   itself, read each time the page is shown, so leaving fullscreen with the browser's Escape shows
##   Off again. "Effect slots" is a slider (the owner, 2026-10-27): left and right move it a step
##   (`EffectSlots` in core/settings: its STEP, from MIN to MAX), `accept` a step up (from the
##   top back to the bottom), up and down leave it; each move sends `effect_slots_changed`, which
##   feel applies. It is kept in memory only: it is not saved yet (`core/save` has settings now).
##   "Particles" (docs/milestones/spell-spectacle.md, P1a) is a slider like "Max shots" through
##   `MoteCap.STOPS` (core/settings: Minimal, Low, Medium, High), from the platform's cap
##   (`MoteCap.default_cap()`); each move sends `mote_cap_changed`, which feel applies (its motes
##   in the air end), and is saved (`mote_cap`); a saved cap other than the default is sent again
##   when the menu is bound. "Particle amount" (P1b) is a slider the same way through
##   `MoteDensity.STOPS` (None, Half, Full, Double: the share of its count every burst of motes
##   throws), from `MoteDensity.DEFAULT`; each move sends `mote_density_changed`, which feel
##   applies, and is saved (`mote_density`), sent again when bound if it is not the default.
##   "Floor marks: On" (or Off; spell spectacle P2a) flips on `accept`
##   from the platform's default (`FloorMarks.default_on()` in core/settings), is saved
##   (`floor_marks`) and sends `floor_marks_changed`, which feel applies (off frees the room's
##   marks); a saved choice other than the default is sent again when the menu is bound.
##   "Spell light: On" (or Off; P3a) flips on `accept`, from the
##   platform's default (`SpellLightSetting.default_on()`), sends `spell_light_changed`, which feel
##   applies, and is saved (`spell_light`); a saved choice other than the default is sent again
##   when the menu is bound. (The "Tails" and "Tail motes" dev switches went when the owner picked
##   tails as motes, every shot in one of the tail kinds, 2026-11-05.)
##   "Tailless motes" (a dev slider, S5 step 4: "no tails, more motes") steps the same
##   way as "Particle amount" through `TaillessMotes.STOPS` (2048, 4096, 8192: the births' pool
##   with the tails off), from `TaillessMotes.DEFAULT`; each move sends `tailless_motes_changed`,
##   which the projectile manager and feel apply, and is saved (`tailless_motes`), sent again when
##   bound if it is not the default.
##   "Screen shake: On" (or Off), the
##   last switch above Back (melee I6): `accept` flips it, it sends `screen_shake_changed`, which
##   feel applies, and the choice is saved (`SaveFile` setting `screen_shake`) and read again
##   when the menu is bound, so it holds between plays. "Damage numbers: On" (or Off; props W5)
##   below it flips the same way: it sends `damage_numbers_changed`, which feel applies to every
##   actor's numbers, and is saved (`damage_numbers`); only Off is sent again when bound. "Max shots" (owner, 2026-11-02) is a
##   slider like "Effect slots" through `ShotCap.STOPS` (core/settings), from the platform's cap
##   (`ShotCap.default_cap()`); each move sends `projectile_cap_changed`, which the projectile
##   manager applies at once (the shots in the air end), and is saved (`projectile_cap`); a saved
##   cap other than the default is sent again when the menu is bound. "Show FPS: Off" (or On;
##   owner, 2026-11-02) flips on `accept`, is saved (`show_fps`) and sends `show_fps_changed`,
##   which `hud/panels` applies to its frame rate readout (`hud/widgets/fps_counter.gd`); panels
##   reads `show_fps` once after binding the menu. (The Gameplay page, with
##   "Friendly fire" and "Enemy fire", went in actors G3c: every spell hits everything, always.)
##
## Only the player who opened it works it, through `core/ui_focus`: up/left and down/right move,
## `accept` (A) activates, `back` (B) goes up a page and closes it from the main page; `pause`
## again closes it (panels.gd). Every button of every page is in one UIFocus list and the
## buttons of the other pages are hidden, so UIFocus skips them. The focused button is marked
## with "> ", never by colour alone. Opening it stops the game and closing it (or its player's
## device leaving) lets it go: the command `pause_requested` (online-ready N4: a stop is the game's
## state, `Sim.stop`, one reason of its own, so another stop stands apart and the game goes on
## only when none stops it). The Tick pauses the tree for the picture. While a replay
## plays (its commands are the recording's) the menu pauses the tree itself, and the replay waits.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const FramesScript := preload("res://core/sim/frames.gd")

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
const ACTION_RESET_DUMMIES: StringName = &"reset_dummies"
const FOCUS_MARK: String = "> "
## The meta key that keeps a button's text without the focus mark.
const BASE_TEXT_META: StringName = &"base_text"

## The menu closed (resumed). Carries the player who had it.
signal closed_menu(player: int)
## A builder switch on the Sandbox page flipped: the radial builder's ring, a full slot pushed
## right or replaced.
signal builder_options_changed(ring: Ring, push: bool)
## The reload switch on the Sandbox page flipped: the staff rows show the delay on the button
## glyph, or on the next cast.
signal reload_style_changed(on_button: bool)
## The "Show FPS" switch on the Settings page flipped.
signal show_fps_changed(on: bool)

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
const LEAVE_WAITING_TEXT: String = "Leave game: P%d (no controller)"
const FULLSCREEN_TEXT: String = "Fullscreen: %s"
const EFFECT_SLOTS_TEXT: String = "Effect slots: %d"
const SHAKE_TEXT: String = "Screen shake: %s"
## The saved setting that holds the choice.
const SHAKE_SETTING: StringName = &"screen_shake"
const NUMBERS_TEXT: String = "Damage numbers: %s"
const NUMBERS_SETTING: StringName = &"damage_numbers"
const SHOT_CAP_TEXT: String = "Max shots: %d"
const SHOT_CAP_SETTING: StringName = &"projectile_cap"
const MOTE_CAP_TEXT: String = "Particles: %s"
const MOTE_CAP_SETTING: StringName = &"mote_cap"
const MOTE_DENSITY_TEXT: String = "Particle amount: %s"
const MOTE_DENSITY_SETTING: StringName = &"mote_density"
const MARKS_TEXT: String = "Floor marks: %s"
const MARKS_SETTING: StringName = &"floor_marks"
const LIGHT_TEXT: String = "Spell light: %s"
const LIGHT_SETTING: StringName = &"spell_light"
const TAILLESS_TEXT: String = "Tailless motes: %s"
const TAILLESS_SETTING: StringName = &"tailless_motes"
const FPS_TEXT: String = "Show FPS: %s"
const FPS_SETTING: StringName = &"show_fps"
## The slider bar beside the words: this wide, at the right of the row.
const SLIDER_WIDTH: float = 64.0

## The player working the menu (0-3), or -1 while it is closed.
var owner_player: int = -1
## The page shown.
var page: Page = Page.MAIN

var _events: EventsScript = null
var _ui_focus: UIFocusScript = null
var _sandbox_on: bool = false
## The seats of this machine that wait for their unplugged gamepad, a bit each (`set_waiting_seats`).
var _waiting_seats: int = 0
## The player whose menu is closing, for the command that lets the game go.
var _closing_player: int = 0
var _focused: Control = null
var _controls: Array[Control] = []
## Page -> its buttons, in order.
var _pages: Dictionary = {}
## The builder switches (see the top).
var ring: Ring = Ring.EVERY_CARD
var put_push: bool = true
## The reload switch (see the top); the button glyph by default (owner, 2026-10-27).
var reload_on_button: bool = true
## The "Effect slots" setting (see the top).
var effect_slots: int = EffectSlots.DEFAULT
## The "Screen shake" setting (see the top): on by default.
var screen_shake: bool = true
## The "Damage numbers" setting (see the top): on by default.
var damage_numbers: bool = true
## The "Max shots" setting (see the top): the platform's cap by default.
var shot_cap: int = ShotCap.default_cap()
## The "Particles" setting (see the top): the platform's cap by default.
var mote_cap: int = MoteCap.default_cap()
## The "Particle amount" setting (see the top): `MoteDensity.DEFAULT` by default.
var mote_density: float = MoteDensity.DEFAULT
## The "Floor marks" setting (see the top): the platform's default.
var floor_marks: bool = FloorMarks.default_on()
## The "Show FPS" setting (see the top): off by default.
var show_fps: bool = false
## The "Spell light" setting (see the top): the platform's default.
var spell_light: bool = SpellLightSetting.default_on()
## The "Tailless motes" dev setting (see the top): `TaillessMotes.DEFAULT` by default.
var tailless_motes: int = TaillessMotes.DEFAULT
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
@onready var _leave: Button = _add(Page.MAIN, "LeaveGame", "Leave game")
@onready var _leave_waiting: Button = _add(Page.MAIN, "LeaveWaiting", LEAVE_WAITING_TEXT % 1)
@onready var _main_menu: Button = _add(Page.MAIN, "MainMenu", "Main menu")
@onready var _reset: Button = _add(Page.SANDBOX, "ResetDummies", "Reset dummies")
@onready var _arena_enemy: Button = _add(Page.SANDBOX, "ArenaEnemy", ENEMY_TEXT % "-")
@onready var _arena_count: Button = _add(Page.SANDBOX, "ArenaCount", COUNT_TEXT % 1)
@onready var _arena_spawn: Button = _add(Page.SANDBOX, "ArenaSpawn", "Spawn")
@onready var _arena_clear: Button = _add(Page.SANDBOX, "ArenaClear", "Clear enemies")
@onready var _ai_view: Button = _add(Page.SANDBOX, "AIView", AI_VIEW_TEXT % "Off")
@onready var _ring_style: Button = _add(Page.SANDBOX, "RingStyle", RING_TEXT % "Every card")
@onready var _put_style: Button = _add(Page.SANDBOX, "PutStyle", PUT_TEXT % "Push right")
@onready var _reload_style: Button = _add(Page.SANDBOX, "ReloadStyle", RELOAD_TEXT % "Button")
@onready var _sandbox_back: Button = _add(Page.SANDBOX, "SandboxBack", "Back")
@onready var _fullscreen: Button = _add(Page.SETTINGS, "Fullscreen", FULLSCREEN_TEXT % "Off")
@onready var _effects: Button = _add(Page.SETTINGS, "EffectSlots", EFFECT_SLOTS_TEXT % EffectSlots.DEFAULT)
@onready var _effects_bar: HSlider = _add_slider(_effects, EffectSlots.MIN, EffectSlots.MAX, EffectSlots.STEP, effect_slots, EFFECT_SLOTS_TEXT % EffectSlots.MAX)
@onready var _motes: Button = _add(Page.SETTINGS, "MoteCap", MOTE_CAP_TEXT % MoteCap.word_of(mote_cap))
@onready var _motes_bar: HSlider = _add_slider(_motes, 0, MoteCap.STOPS.size() - 1, 1, MoteCap.index_of(mote_cap), MOTE_CAP_TEXT % "Medium")
@onready var _density: Button = _add(Page.SETTINGS, "MoteDensity", MOTE_DENSITY_TEXT % MoteDensity.word_of(mote_density))
@onready var _density_bar: HSlider = _add_slider(_density, 0, MoteDensity.STOPS.size() - 1, 1, MoteDensity.index_of(mote_density), MOTE_DENSITY_TEXT % "Double")
@onready var _marks: Button = _add(Page.SETTINGS, "FloorMarks", MARKS_TEXT % ("On" if floor_marks else "Off"))
@onready var _light: Button = _add(Page.SETTINGS, "SpellLight", LIGHT_TEXT % ("On" if spell_light else "Off"))
@onready var _tailless: Button = _add(Page.SETTINGS, "TaillessMotes", TAILLESS_TEXT % TaillessMotes.word_of(tailless_motes))
@onready var _tailless_bar: HSlider = _add_slider(_tailless, 0, TaillessMotes.STOPS.size() - 1, 1, TaillessMotes.index_of(tailless_motes), TAILLESS_TEXT % TaillessMotes.STOPS[-1])
@onready var _shots: Button = _add(Page.SETTINGS, "ShotCap", SHOT_CAP_TEXT % shot_cap)
@onready var _shots_bar: HSlider = _add_slider(_shots, 0, ShotCap.STOPS.size() - 1, 1, ShotCap.index_of(shot_cap), SHOT_CAP_TEXT % ShotCap.STOPS[-1])
@onready var _shake: Button = _add(Page.SETTINGS, "ScreenShake", SHAKE_TEXT % "On")
@onready var _numbers: Button = _add(Page.SETTINGS, "DamageNumbers", NUMBERS_TEXT % "On")
@onready var _fps: Button = _add(Page.SETTINGS, "ShowFps", FPS_TEXT % "Off")
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
	_load_numbers()
	_load_shot_cap()
	_load_mote_cap()
	_load_mote_density()
	_load_floor_marks()
	_load_light()
	_load_tailless_motes()
	_load_fps()
	if _events != null:
		_events.sandbox_changed.connect(_on_sandbox_changed)
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
## `longest_text` is the row's longest words, which the row is made wide enough for.
func _add_slider(row: Button, low: int, high: int, step: int, value: int, longest_text: String) -> HSlider:
	var bar := HSlider.new()
	bar.name = "Bar"
	bar.min_value = low
	bar.max_value = high
	bar.step = step
	bar.value = value
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
	var longest: float = font.get_string_size(FOCUS_MARK + longest_text, HORIZONTAL_ALIGNMENT_LEFT, -1, row.get_theme_font_size(&"font_size")).x
	row.custom_minimum_size.x = longest + SLIDER_WIDTH + 24.0
	return bar


## The menu's navigator for UIFocus: left and right on the slider move it and keep the focus
## there; any other move goes on as usual (null).
func _navigate(control: Control, direction: Vector2i) -> Control:
	if control == _effects and direction.x != 0:
		_set_effect_slots(effect_slots + direction.x * EffectSlots.STEP)
		return _effects
	if control == _motes and direction.x != 0:
		var stop: int = clampi(MoteCap.index_of(mote_cap) + direction.x, 0, MoteCap.STOPS.size() - 1)
		_set_mote_cap(MoteCap.STOPS[stop])
		return _motes
	if control == _density and direction.x != 0:
		var step: int = clampi(MoteDensity.index_of(mote_density) + direction.x, 0, MoteDensity.STOPS.size() - 1)
		_set_mote_density(MoteDensity.STOPS[step])
		return _density
	if control == _tailless and direction.x != 0:
		var pick: int = clampi(TaillessMotes.index_of(tailless_motes) + direction.x, 0, TaillessMotes.STOPS.size() - 1)
		_set_tailless_motes(TaillessMotes.STOPS[pick])
		return _tailless
	if control == _shots and direction.x != 0:
		var at: int = clampi(ShotCap.index_of(shot_cap) + direction.x, 0, ShotCap.STOPS.size() - 1)
		_set_shot_cap(ShotCap.STOPS[at])
		return _shots
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
	_leave_waiting.visible = next == Page.MAIN and _waiting_seats != 0
	_leave_waiting.set_meta(BASE_TEXT_META, LEAVE_WAITING_TEXT % (waiting_seat() + 1))
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


## Open or close the game's pause. Offline the game stops for everyone by the command
## `pause_requested` (the simulation's own stop, Coop's). While a replay file plays, a live command
## would change what it replays, so the menu only stands the picture still (the tree's pause, which
## runs no tick: core/sim/tick.gd) and the replay waits. Online (a live replay) the command goes to
## the host as the seat's, and stops both machines when it comes back.
func _set_paused(on: bool) -> void:
	if not is_inside_tree():
		return
	var frames: FramesScript = get_node_or_null(^"/root/Frames") as FramesScript
	var seat: int = owner_player if owner_player >= 0 else _closing_player
	if frames != null and not frames.hears_commands(seat):
		get_tree().paused = on
	elif _events != null:
		_events.pause_requested.emit(seat, 1 if on else 0)


## The seats of this machine whose gamepad is unplugged (a bit each; `panels.gd` tells): while any
## waits, the main page offers to let the lowest leave. If the row focused goes, the first is.
func set_waiting_seats(seats: int) -> void:
	if seats == _waiting_seats:
		return
	_waiting_seats = seats
	_show_page(page)
	if is_open() and _focused != null and not _focused.visible:
		_focus_first()


## The lowest seat waiting for its gamepad (the one "Leave game: P2" lets go), or -1.
func waiting_seat() -> int:
	for seat in PLAYER_COUNT:
		if _waiting_seats & (1 << seat) != 0:
			return seat
	return -1


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
	_closing_player = player
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
		_read_arena()
		_go(Page.SANDBOX)
	elif control == _settings:
		_go(Page.SETTINGS)
	elif control == _leave:
		# Closed first, so the game is let go before the seat leaves it.
		close_menu()
		if _events != null:
			_events.seat_leave_requested.emit(player)
	elif control == _leave_waiting:
		var seat: int = waiting_seat()
		if _events != null and seat >= 0:
			# Gone from the row at once, so a second press never asks again before co-op says so.
			set_waiting_seats(_waiting_seats & ~(1 << seat))
			_events.seat_leave_requested.emit(seat)
	elif control == _main_menu:
		# Closed first, so the game is let go before this machine leaves it.
		close_menu()
		if _events != null:
			_events.main_menu_requested.emit(player)
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
	elif control == _motes:
		_set_mote_cap(MoteCap.STOPS[(MoteCap.index_of(mote_cap) + 1) % MoteCap.STOPS.size()])
	elif control == _density:
		_set_mote_density(MoteDensity.STOPS[(MoteDensity.index_of(mote_density) + 1) % MoteDensity.STOPS.size()])
	elif control == _shots:
		_set_shot_cap(ShotCap.STOPS[(ShotCap.index_of(shot_cap) + 1) % ShotCap.STOPS.size()])
	elif control == _marks:
		_set_floor_marks(not floor_marks)
	elif control == _light:
		_set_light(not spell_light)
	elif control == _tailless:
		_set_tailless_motes(TaillessMotes.STOPS[(TaillessMotes.index_of(tailless_motes) + 1) % TaillessMotes.STOPS.size()])
	elif control == _shake:
		_set_shake(not screen_shake)
	elif control == _numbers:
		_set_numbers(not damage_numbers)
	elif control == _fps:
		_set_fps(not show_fps)
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


## Read the saved "Damage numbers" choice and show it; feel is told only when it is off (on is
## feel's own default).
func _load_numbers() -> void:
	damage_numbers = bool(save.get_setting(NUMBERS_SETTING, true))
	_numbers.set_meta(BASE_TEXT_META, NUMBERS_TEXT % ("On" if damage_numbers else "Off"))
	_mark_focus()
	if not damage_numbers and _events != null:
		_events.damage_numbers_changed.emit(false)


## Flip the "Damage numbers" switch: show it, save it and tell feel.
func _set_numbers(on: bool) -> void:
	damage_numbers = on
	_numbers.set_meta(BASE_TEXT_META, NUMBERS_TEXT % ("On" if on else "Off"))
	_mark_focus()
	save.set_setting(NUMBERS_SETTING, on)
	if _events != null:
		_events.damage_numbers_changed.emit(on)


## Read the saved "Spell light" choice and show it; feel is told only when it is not the default.
func _load_light() -> void:
	spell_light = bool(save.get_setting(LIGHT_SETTING, SpellLightSetting.default_on()))
	_light.set_meta(BASE_TEXT_META, LIGHT_TEXT % ("On" if spell_light else "Off"))
	_mark_focus()
	if spell_light != SpellLightSetting.default_on() and _events != null:
		_events.spell_light_changed.emit(spell_light)


## Flip the "Spell light" switch: show it, save it and tell feel.
func _set_light(on: bool) -> void:
	spell_light = on
	_light.set_meta(BASE_TEXT_META, LIGHT_TEXT % ("On" if on else "Off"))
	_mark_focus()
	save.set_setting(LIGHT_SETTING, on)
	if _events != null:
		_events.spell_light_changed.emit(on)


## Flip the switch: show it, save it and tell feel.
func _set_shake(on: bool) -> void:
	screen_shake = on
	_shake.set_meta(BASE_TEXT_META, SHAKE_TEXT % ("On" if on else "Off"))
	_mark_focus()
	save.set_setting(SHAKE_SETTING, on)
	if _events != null:
		_events.screen_shake_changed.emit(on)


## Read the saved cap and show it; the simulation is told only when it is not the platform's (the
## machine's default, `SessionRules.defaults()`): the next run takes it.
func _load_shot_cap() -> void:
	var saved: int = ShotCap.snap(int(save.get_setting(SHOT_CAP_SETTING, ShotCap.default_cap())))
	_show_shot_cap(saved)
	if saved != ShotCap.default_cap() and _events != null:
		_events.projectile_cap_changed.emit(saved)


## Move the "Max shots" slider to `cap` (a stop): show it, save it, make it this machine's (the
## next run's) and ask for it in the run playing now (a command, applied at the next tick: the
## shots in the air end; online-ready N11).
func _set_shot_cap(cap: int) -> void:
	if cap == shot_cap:
		return
	_show_shot_cap(cap)
	save.set_setting(SHOT_CAP_SETTING, cap)
	if _events != null:
		_events.projectile_cap_changed.emit(cap)
		if owner_player >= 0:
			_events.shot_cap_requested.emit(owner_player, cap)


func _show_shot_cap(cap: int) -> void:
	shot_cap = cap
	_shots.set_meta(BASE_TEXT_META, SHOT_CAP_TEXT % cap)
	_shots_bar.value = ShotCap.index_of(cap)
	_mark_focus()


## Read the saved particles cap and show it; feel is told only when it is not the platform's (feel's
## own default).
func _load_mote_cap() -> void:
	var saved: int = MoteCap.snap(int(save.get_setting(MOTE_CAP_SETTING, MoteCap.default_cap())))
	_show_mote_cap(saved)
	if saved != MoteCap.default_cap() and _events != null:
		_events.mote_cap_changed.emit(saved)


## Move the "Particles" slider to `cap` (a stop): show it, save it and tell feel.
func _set_mote_cap(cap: int) -> void:
	if cap == mote_cap:
		return
	_show_mote_cap(cap)
	save.set_setting(MOTE_CAP_SETTING, cap)
	if _events != null:
		_events.mote_cap_changed.emit(cap)


func _show_mote_cap(cap: int) -> void:
	mote_cap = cap
	_motes.set_meta(BASE_TEXT_META, MOTE_CAP_TEXT % MoteCap.word_of(cap))
	_motes_bar.value = MoteCap.index_of(cap)
	_mark_focus()


## Read the saved "Tailless motes" pool and show it; the manager and feel are told only when it
## is not the default.
func _load_tailless_motes() -> void:
	var saved: int = TaillessMotes.snap(int(save.get_setting(TAILLESS_SETTING, TaillessMotes.DEFAULT)))
	_show_tailless_motes(saved)
	if saved != TaillessMotes.DEFAULT and _events != null:
		_events.tailless_motes_changed.emit(saved)


## Move the "Tailless motes" slider to `pool` (a stop): show it, save it and tell the manager and
## feel.
func _set_tailless_motes(pool: int) -> void:
	if pool == tailless_motes:
		return
	_show_tailless_motes(pool)
	save.set_setting(TAILLESS_SETTING, pool)
	if _events != null:
		_events.tailless_motes_changed.emit(pool)


func _show_tailless_motes(pool: int) -> void:
	tailless_motes = pool
	_tailless.set_meta(BASE_TEXT_META, TAILLESS_TEXT % TaillessMotes.word_of(pool))
	_tailless_bar.value = TaillessMotes.index_of(pool)
	_mark_focus()


## Read the saved particle amount and show it; feel is told only when it is not the default.
func _load_mote_density() -> void:
	var saved: float = MoteDensity.snap(float(save.get_setting(MOTE_DENSITY_SETTING, MoteDensity.DEFAULT)))
	_show_mote_density(saved)
	if saved != MoteDensity.DEFAULT and _events != null:
		_events.mote_density_changed.emit(saved)


## Move the "Particle amount" slider to `density` (a stop): show it, save it and tell feel.
func _set_mote_density(density: float) -> void:
	if density == mote_density:
		return
	_show_mote_density(density)
	save.set_setting(MOTE_DENSITY_SETTING, density)
	if _events != null:
		_events.mote_density_changed.emit(density)


func _show_mote_density(density: float) -> void:
	mote_density = density
	_density.set_meta(BASE_TEXT_META, MOTE_DENSITY_TEXT % MoteDensity.word_of(density))
	_density_bar.value = MoteDensity.index_of(density)
	_mark_focus()


## Read the saved "Floor marks" choice and show it; feel is told only when it is not the platform's
## (feel's own default).
func _load_floor_marks() -> void:
	floor_marks = bool(save.get_setting(MARKS_SETTING, FloorMarks.default_on()))
	_marks.set_meta(BASE_TEXT_META, MARKS_TEXT % ("On" if floor_marks else "Off"))
	_mark_focus()
	if floor_marks != FloorMarks.default_on() and _events != null:
		_events.floor_marks_changed.emit(floor_marks)


## Flip the "Floor marks" switch: show it, save it and tell feel.
func _set_floor_marks(on: bool) -> void:
	floor_marks = on
	_marks.set_meta(BASE_TEXT_META, MARKS_TEXT % ("On" if on else "Off"))
	_mark_focus()
	save.set_setting(MARKS_SETTING, on)
	if _events != null:
		_events.floor_marks_changed.emit(on)


## Read the saved "Show FPS" choice and show it (panels reads `show_fps` after binding).
func _load_fps() -> void:
	show_fps = bool(save.get_setting(FPS_SETTING, false))
	_fps.set_meta(BASE_TEXT_META, FPS_TEXT % ("On" if show_fps else "Off"))
	_mark_focus()


## Flip the "Show FPS" switch: show it, save it and tell panels.
func _set_fps(on: bool) -> void:
	show_fps = on
	_fps.set_meta(BASE_TEXT_META, FPS_TEXT % ("On" if on else "Off"))
	_mark_focus()
	save.set_setting(FPS_SETTING, on)
	show_fps_changed.emit(on)


## Write the fullscreen switch's word from the window itself.
func _show_fullscreen() -> void:
	var on: bool = display != null and bool(display.call("is_fullscreen"))
	_fullscreen.set_meta(BASE_TEXT_META, FULLSCREEN_TEXT % ("On" if on else "Off"))
	_mark_focus()


## Write the switches' words and tell `hud/panels`.
func _show_builder_options() -> void:
	_ring_style.set_meta(BASE_TEXT_META, RING_TEXT % RING_WORDS[ring])
	_put_style.set_meta(BASE_TEXT_META, PUT_TEXT % ("Push right" if put_push else "Replace"))
	_mark_focus()
	builder_options_changed.emit(ring, put_push)


func _send(action: StringName) -> void:
	if _events != null:
		_events.sandbox_action_requested.emit(owner_player, action)
