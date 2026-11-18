extends PanelContainer
## The pause menu (owner, 2026-10-26): `pause` (Start; Escape on the keyboard) opens it for the
## player who pressed it, and it stops the game for everyone (co-op rule 6: only the real pause
## menu stops the game, and any player can open it). `hud/panels/panels.gd` opens and closes it
## (node Root/PauseMenu); it sits in the middle of the view.
##
## Pages, one list of buttons each:
## - **Main:** Resume, Map (only while the run has a map, a run of rooms), Settings, Leave
##   game (`seat_leave_requested`: the seat that opened the menu lets its device go and its wizard
##   leaves, at its tick on every machine; the others play on; items I2, in place of the `leave`
##   action; the menu closes first), "Leave game: P2 (no controller)" (only while a seat of this
##   machine waits for its unplugged gamepad, `set_waiting_seats`; the lowest such seat: it leaves
##   by the same `seat_leave_requested`, the game goes on once no seat waits, and the menu stays
##   open), Main menu (`main_menu_requested`: this machine leaves the run,
##   online too, and the main menu shows again; the menu closes first).
## - **Map** (run generation RG8): the run's map (`hud/widgets/run_map_view.gd`, told by the run
##   area's `run_map_changed`: its rows, links and kinds, and where the party is), view only, and
##   Back. It goes back to the main page by itself if the map goes while it shows.
## - **Settings:** a row for each page of settings, named as games name them, and Back (every row on
##   one page no longer fit the 360 px view): "Graphics", "Performance", "Audio", "Interface". A
##   page's own Back (and `back`) goes up to Settings with that page's row focused, and Settings'
##   own up to the main page on its Settings row (the Map page's on its Map row). Every row of a
##   page is as wide as the page's widest words focused, either way (`_fit_widths`), so the panel
##   keeps its width as the focus moves and a switch flips. Every saved
##   setting below is read when the menu is bound and sent again only when it is not its default
##   (each default lives in core/settings, which feel reads too, so neither reads the other).
## - **Graphics:** "Fullscreen: Off" (or On), "Dynamic lighting: On", "Shadows: On", "Fog: On",
##   "Ambient particles: On", "Environment interaction: On", "Floor marks: On", Back.
##   "Fullscreen" asks `Display` (core) to fill the screen or not and stays on the page; its word
##   follows the window itself, read each time the page is shown, so leaving fullscreen with the
##   browser's Escape shows Off again. The others are switches flipping on `accept` from the
##   platform's default, each saved and sent on its core event, which feel applies
##   (docs/milestones/atmosphere.md, "Settings"). "Dynamic lighting" (`SpellLightSetting`; P3a's
##   spell light and atmosphere A: the light buffer, the room's dark and tint, the wizards' carried
##   lights) was "Spell light" and keeps its save key (`spell_light`) and event
##   (`spell_light_changed`), so a saved choice carries over. "Shadows" (`ShadowsSetting`, saved as
##   `shadows`, `shadows_changed`; atmosphere C: light blocked by walls and pillars, the bodies'
##   shadows), "Fog" (`FogSetting`, `fog`, `fog_changed`; F, the floor mist) and "Ambient particles"
##   (`AmbientParticles`, `ambient_particles`, `ambient_particles_changed`; B, the air's dust) need
##   the light: while "Dynamic lighting" is off they show their choice greyed (`disabled`, which
##   UIFocus skips) and change nothing. "Environment interaction" (`EnvironmentInteraction`,
##   `environment_interaction`, `environment_interaction_changed`; E: the lights, the cover, the dust
##   and the mist pushed by shots and blasts). "Floor marks" (`FloorMarks`, `floor_marks`,
##   `floor_marks_changed`; spell spectacle P2a: off frees the room's marks).
## - **Performance:** "Effect slots: 256", "Particles: High", "Particle amount: Full", "Tailless
##   motes: 2048", "Max shots: 6000", Back: sliders. Left and right move one a step and keep the
##   focus, `accept` steps it up (from the top back to the bottom), up and down leave it.
##   "Effect slots" (the owner, 2026-10-27; `EffectSlots` in core/settings: its STEP, from MIN to
##   MAX) sends `effect_slots_changed`, which feel applies; it is kept in memory only, not saved.
##   "Particles" (docs/milestones/spell-spectacle.md, P1a) steps through `MoteCap.STOPS` (Minimal,
##   Low, Medium, High) from the platform's cap (`MoteCap.default_cap()`), sends `mote_cap_changed`
##   (feel's motes in the air end) and is saved (`mote_cap`). "Particle amount" (P1b) steps through
##   `MoteDensity.STOPS` (None, Half, Full, Double: the share of its count every burst of motes
##   throws), sends `mote_density_changed` and is saved (`mote_density`). "Tailless motes" (a dev
##   slider, S5 step 4: "no tails, more motes") steps through `TaillessMotes.STOPS` (2048, 4096,
##   8192: the births' pool with the tails off), sends `tailless_motes_changed`, which the
##   projectile manager and feel apply, and is saved (`tailless_motes`). "Max shots" (owner,
##   2026-11-02) steps through `ShotCap.STOPS` from the platform's cap (`ShotCap.default_cap()`),
##   sends `projectile_cap_changed`, which the projectile manager applies at once (the shots in the
##   air end), asks for it in the run playing (`shot_cap_requested`) and is saved (`projectile_cap`).
## - **Audio:** "Ambience volume: 100%", Back: a slider like those, from `AmbienceVolume.MIN` to MAX
##   by its STEP (0% to 100% by 10%; `AmbienceVolume.DEFAULT`, 100%), sending
##   `ambience_volume_changed`, which feel hands to the room's sound (atmosphere D; heard on
##   `AmbienceVolume.share_of`'s curve, 0% silent),
##   and saved (`ambience_volume`).
## - **Interface:** "Screen shake: On" (or Off; melee I6: `screen_shake_changed`, saved as
##   `screen_shake`), "Damage numbers: On" (or Off; props W5: `damage_numbers_changed`, which feel
##   applies to every actor's numbers, saved as `damage_numbers`), "Show FPS: Off" (or On; owner,
##   2026-11-02: saved as `show_fps`, sending `show_fps_changed`, which `hud/panels` applies to its
##   frame rate readout, `hud/widgets/fps_counter.gd`, and reads once after binding the menu), the
##   builder switches (owner, 2026-10-26; flipping on `accept`, not saved): "Ring:" ("Every card",
##   "One kind", or the ring styles to try, owner 2026-10-30: "Zoom", "Kinds: hold", "Kinds:
##   depth"; `accept` steps to the next, `Ring`) and "Full slot: Push right" or "Replace" (the radial
##   builder's options), each sending `builder_options_changed`, which `hud/panels` applies to every
##   player's builder; "Reload: Button" (the default) or "Next cast" (owner, 2026-10-27): where the
##   corner panels' staff rows show a staff's delay, sending `reload_style_changed`; then Back. (The
##   Gameplay page, with "Friendly fire" and "Enemy fire", went in actors G3c: every spell hits
##   everything, always. The "Tails" and "Tail motes" dev switches went when the owner picked tails
##   as motes, 2026-11-05.)
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
const RunMapViewScript := preload("res://hud/widgets/run_map_view.gd")

const PLAYER_COUNT: int = 4
enum Page { MAIN, SETTINGS, MAP, GRAPHICS, PERFORMANCE, AUDIO, INTERFACE }
## The radial builder's ring (see the top): the plain one with every card or one kind at a time,
## or a ring style from `hud/builder/rings/`.
enum Ring { EVERY_CARD, ONE_KIND, ZOOM, KINDS_HOLD, KINDS_DEPTH }
## The title of each page.
const TITLES: Dictionary = {
	Page.MAIN: "PAUSED", Page.SETTINGS: "SETTINGS", Page.MAP: "MAP", Page.GRAPHICS: "GRAPHICS",
	Page.PERFORMANCE: "PERFORMANCE", Page.AUDIO: "AUDIO", Page.INTERFACE: "INTERFACE",
}
const FOCUS_MARK: String = "> "
## The meta key that keeps a button's text without the focus mark.
const BASE_TEXT_META: StringName = &"base_text"
## The words a switch shows, either way.
const ON_OFF: Array[String] = ["On", "Off"]

## The menu closed (resumed). Carries the player who had it.
signal closed_menu(player: int)
## A builder switch on the Interface page flipped: the radial builder's ring, a full slot pushed
## right or replaced.
signal builder_options_changed(ring: Ring, push: bool)
## The reload switch on the Interface page flipped: the staff rows show the delay on the button
## glyph, or on the next cast.
signal reload_style_changed(on_button: bool)
## The "Show FPS" switch on the Interface page flipped.
signal show_fps_changed(on: bool)

const RING_TEXT: String = "Ring: %s"
const RING_WORDS: Array[String] = ["Every card", "One kind", "Zoom", "Kinds: hold", "Kinds: depth"]
const PUT_TEXT: String = "Full slot: %s"
const RELOAD_TEXT: String = "Reload: %s"
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
## "Dynamic lighting" (once "Spell light": its save key kept, so a saved choice carries over).
const LIGHT_TEXT: String = "Dynamic lighting: %s"
const LIGHT_SETTING: StringName = &"spell_light"
const SHADOWS_TEXT: String = "Shadows: %s"
const SHADOWS_SETTING: StringName = &"shadows"
const FOG_TEXT: String = "Fog: %s"
const FOG_SETTING: StringName = &"fog"
const AIR_TEXT: String = "Ambient particles: %s"
const AIR_SETTING: StringName = &"ambient_particles"
const STIRS_TEXT: String = "Environment interaction: %s"
const STIRS_SETTING: StringName = &"environment_interaction"
const AMBIENCE_TEXT: String = "Ambience volume: %s"
const AMBIENCE_SETTING: StringName = &"ambience_volume"
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
## The "Dynamic lighting" setting (once "Spell light"; see the top): the platform's default.
var spell_light: bool = SpellLightSetting.default_on()
## The atmosphere's switches and the ambience's volume (see the top): their platforms' defaults.
var shadows: bool = ShadowsSetting.default_on()
var fog: bool = FogSetting.default_on()
var ambient_particles: bool = AmbientParticles.default_on()
var environment_interaction: bool = EnvironmentInteraction.default_on()
var ambience_volume: int = AmbienceVolume.DEFAULT
## The "Tailless motes" dev setting (see the top): `TaillessMotes.DEFAULT` by default.
var tailless_motes: int = TaillessMotes.DEFAULT
## The save that keeps settings; made when the menu is bound, unless a test set its own first.
var save: SaveFile = null
## The window service (`core/display`, the `Display` autoload); tests may set their own first.
var display: Node = null
## The content registry the Map page names room kinds by; tests may set their own first, else the
## `Registry` autoload.
var registry: Node = null

@onready var _title: Label = %Title
@onready var _rows: VBoxContainer = %Rows
@onready var _resume: Button = _add(Page.MAIN, "Resume", "Resume")
@onready var _map_row: Button = _add(Page.MAIN, "Map", "Map")
@onready var _settings: Button = _add(Page.MAIN, "Settings", "Settings")
@onready var _leave: Button = _add(Page.MAIN, "LeaveGame", "Leave game")
@onready var _leave_waiting: Button = _add(Page.MAIN, "LeaveWaiting", LEAVE_WAITING_TEXT % 1)
@onready var _main_menu: Button = _add(Page.MAIN, "MainMenu", "Main menu")
@onready var _graphics_row: Button = _add(Page.SETTINGS, "Graphics", "Graphics")
@onready var _performance_row: Button = _add(Page.SETTINGS, "Performance", "Performance")
@onready var _audio_row: Button = _add(Page.SETTINGS, "Audio", "Audio")
@onready var _interface_row: Button = _add(Page.SETTINGS, "Interface", "Interface")
@onready var _settings_back: Button = _add(Page.SETTINGS, "SettingsBack", "Back")
@onready var _fullscreen: Button = _add(Page.GRAPHICS, "Fullscreen", FULLSCREEN_TEXT % "Off")
@onready var _light: Button = _add(Page.GRAPHICS, "SpellLight", LIGHT_TEXT % _word(spell_light))
@onready var _shadows: Button = _add(Page.GRAPHICS, "Shadows", SHADOWS_TEXT % _word(shadows))
@onready var _fog: Button = _add(Page.GRAPHICS, "Fog", FOG_TEXT % _word(fog))
@onready var _air: Button = _add(Page.GRAPHICS, "AmbientParticles", AIR_TEXT % _word(ambient_particles))
@onready var _stirs: Button = _add(Page.GRAPHICS, "EnvironmentInteraction", STIRS_TEXT % _word(environment_interaction))
@onready var _marks: Button = _add(Page.GRAPHICS, "FloorMarks", MARKS_TEXT % _word(floor_marks))
@onready var _graphics_back: Button = _add(Page.GRAPHICS, "GraphicsBack", "Back")
@onready var _effects: Button = _add(Page.PERFORMANCE, "EffectSlots", EFFECT_SLOTS_TEXT % EffectSlots.DEFAULT)
@onready var _effects_bar: HSlider = _add_slider(_effects, EffectSlots.MIN, EffectSlots.MAX, EffectSlots.STEP, effect_slots, EFFECT_SLOTS_TEXT % EffectSlots.MAX)
@onready var _motes: Button = _add(Page.PERFORMANCE, "MoteCap", MOTE_CAP_TEXT % MoteCap.word_of(mote_cap))
@onready var _motes_bar: HSlider = _add_slider(_motes, 0, MoteCap.STOPS.size() - 1, 1, MoteCap.index_of(mote_cap), MOTE_CAP_TEXT % "Medium")
@onready var _density: Button = _add(Page.PERFORMANCE, "MoteDensity", MOTE_DENSITY_TEXT % MoteDensity.word_of(mote_density))
@onready var _density_bar: HSlider = _add_slider(_density, 0, MoteDensity.STOPS.size() - 1, 1, MoteDensity.index_of(mote_density), MOTE_DENSITY_TEXT % "Double")
@onready var _tailless: Button = _add(Page.PERFORMANCE, "TaillessMotes", TAILLESS_TEXT % TaillessMotes.word_of(tailless_motes))
@onready var _tailless_bar: HSlider = _add_slider(_tailless, 0, TaillessMotes.STOPS.size() - 1, 1, TaillessMotes.index_of(tailless_motes), TAILLESS_TEXT % TaillessMotes.STOPS[-1])
@onready var _shots: Button = _add(Page.PERFORMANCE, "ShotCap", SHOT_CAP_TEXT % shot_cap)
@onready var _shots_bar: HSlider = _add_slider(_shots, 0, ShotCap.STOPS.size() - 1, 1, ShotCap.index_of(shot_cap), SHOT_CAP_TEXT % ShotCap.STOPS[-1])
@onready var _performance_back: Button = _add(Page.PERFORMANCE, "PerformanceBack", "Back")
@onready var _ambience: Button = _add(Page.AUDIO, "AmbienceVolume", AMBIENCE_TEXT % AmbienceVolume.word_of(ambience_volume))
@onready var _ambience_bar: HSlider = _add_slider(_ambience, AmbienceVolume.MIN, AmbienceVolume.MAX, AmbienceVolume.STEP, ambience_volume, AMBIENCE_TEXT % AmbienceVolume.word_of(AmbienceVolume.MAX))
@onready var _audio_back: Button = _add(Page.AUDIO, "AudioBack", "Back")
@onready var _shake: Button = _add(Page.INTERFACE, "ScreenShake", SHAKE_TEXT % "On")
@onready var _numbers: Button = _add(Page.INTERFACE, "DamageNumbers", NUMBERS_TEXT % "On")
@onready var _fps: Button = _add(Page.INTERFACE, "ShowFps", FPS_TEXT % "Off")
@onready var _ring_style: Button = _add(Page.INTERFACE, "RingStyle", RING_TEXT % "Every card")
@onready var _put_style: Button = _add(Page.INTERFACE, "PutStyle", PUT_TEXT % "Push right")
@onready var _reload_style: Button = _add(Page.INTERFACE, "ReloadStyle", RELOAD_TEXT % "Button")
@onready var _interface_back: Button = _add(Page.INTERFACE, "InterfaceBack", "Back")
## The Map page's map (not a button: UIFocus never stops on it), over its Back.
@onready var _map: RunMapViewScript = _add_map()
@onready var _map_back: Button = _add(Page.MAP, "MapBack", "Back")


func _ready() -> void:
	# Worked while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if display == null:
		display = get_node_or_null(^"/root/Display")
	visible = false
	_fit_widths()
	_show_page(Page.MAIN)


## Every row of a page as wide as the page's widest: its focus mark and its longest words either way
## (a switch's On and Off, a builder switch's every word) or its slider, so the panel keeps its width
## as the focus moves and a switch flips.
func _fit_widths() -> void:
	var needs: Dictionary = {}
	for row: Button in _controls:
		needs[row] = maxf(row.custom_minimum_size.x, _width_of(row, [str(row.get_meta(BASE_TEXT_META, ""))]))
	var switches: Dictionary = {
		_fullscreen: FULLSCREEN_TEXT, _light: LIGHT_TEXT, _shadows: SHADOWS_TEXT, _fog: FOG_TEXT,
		_air: AIR_TEXT, _stirs: STIRS_TEXT, _marks: MARKS_TEXT, _shake: SHAKE_TEXT,
		_numbers: NUMBERS_TEXT, _fps: FPS_TEXT,
	}
	for row: Button in switches:
		needs[row] = maxf(needs[row], _width_of(row, _worded(switches[row], ON_OFF)))
	needs[_ring_style] = maxf(needs[_ring_style], _width_of(_ring_style, _worded(RING_TEXT, RING_WORDS)))
	needs[_put_style] = maxf(needs[_put_style], _width_of(_put_style, _worded(PUT_TEXT, ["Push right", "Replace"])))
	needs[_reload_style] = maxf(needs[_reload_style], _width_of(_reload_style, _worded(RELOAD_TEXT, ["Button", "Next cast"])))
	for on_page: int in _pages:
		var widest: float = 0.0
		for row: Button in _pages[on_page]:
			widest = maxf(widest, needs[row])
		for row: Button in _pages[on_page]:
			row.custom_minimum_size.x = widest


## `format` with each of `words`.
static func _worded(format: String, words: Array) -> Array[String]:
	var texts: Array[String] = []
	for word: Variant in words:
		texts.append(format % word)
	return texts


## How wide `row` must be for the longest of `texts`, focused (its style's margins included).
func _width_of(row: Button, texts: Array[String]) -> float:
	var font: Font = row.get_theme_font(&"font")
	var font_size: int = row.get_theme_font_size(&"font_size")
	var widest: float = 0.0
	for text in texts:
		widest = maxf(widest, font.get_string_size(FOCUS_MARK + text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var style: StyleBox = row.get_theme_stylebox(&"normal")
	return ceilf(widest + (style.get_minimum_size().x if style != null else 0.0))


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
	_load_atmosphere()
	_load_ambience_volume()
	_load_tailless_motes()
	_load_fps()
	_map.name_of = _kind_name
	_map.bind(_events)
	_map.map_changed.connect(_on_map_changed)
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


## The page `control` (a button) is on (MAIN for none).
func page_of(control: Control) -> Page:
	for on_page: int in _pages:
		if (_pages[on_page] as Array).has(control):
			return on_page as Page
	return Page.MAIN


## The Settings page's row that opens `of_page` (null for a page that is not a page of settings).
func page_row(of_page: Page) -> Button:
	match of_page:
		Page.GRAPHICS:
			return _graphics_row
		Page.PERFORMANCE:
			return _performance_row
		Page.AUDIO:
			return _audio_row
		Page.INTERFACE:
			return _interface_row
	return null


## "On" or "Off".
static func _word(on: bool) -> String:
	return "On" if on else "Off"


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


## The Map page's map, in the rows after the buttons made before it (shown on that page only).
func _add_map() -> RunMapViewScript:
	var made := RunMapViewScript.new()
	made.name = "RunMap"
	made.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_rows.add_child(made)
	return made


## The map the Map page shows (for tests and screenshots).
func map_view() -> RunMapViewScript:
	return _map


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
	if control == _ambience and direction.x != 0:
		_set_ambience_volume(ambience_volume + direction.x * AmbienceVolume.STEP)
		return _ambience
	if control == _shots and direction.x != 0:
		var at: int = clampi(ShotCap.index_of(shot_cap) + direction.x, 0, ShotCap.STOPS.size() - 1)
		_set_shot_cap(ShotCap.STOPS[at])
		return _shots
	return null


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
	_map_row.visible = next == Page.MAIN and _map.has_map()
	_map.visible = next == Page.MAP
	_leave_waiting.visible = next == Page.MAIN and _waiting_seats != 0
	_leave_waiting.set_meta(BASE_TEXT_META, LEAVE_WAITING_TEXT % (waiting_seat() + 1))
	if next == Page.GRAPHICS:
		_show_fullscreen()
	_mark_focus()


## Show the page `next` with its first row focused, or `focused` when given (a row of it).
func _go(next: Page, focused: Button = null) -> void:
	_show_page(next)
	_focus_first()
	if focused != null and _ui_focus != null and is_open():
		_ui_focus.focus(owner_player, focused)
		_focused = _ui_focus.focused(owner_player)
		_mark_focus()


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


## The run's map changed: the Map row follows it, and a Map page whose map went goes back.
func _on_map_changed() -> void:
	if not _map.has_map() and page == Page.MAP:
		_go(Page.MAIN)
	else:
		_show_page(page)
		if is_open() and _focused != null and not _focused.visible:
			_focus_first()


## A room kind's name for people (`RoomKind.shown_name`), from the registry; its id in words if the
## registry has no such kind.
func _kind_name(kind: StringName) -> String:
	var source: Node = registry if registry != null else get_node_or_null(^"/root/Registry")
	var data: RoomKind = source.call("get_resource", &"room_kinds", kind) as RoomKind if source != null else null
	return data.shown_name() if data != null else String(kind).capitalize()


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
	elif control == _map_row:
		_go(Page.MAP)
	elif control == _settings:
		_go(Page.SETTINGS)
	elif control == _graphics_row:
		_go(Page.GRAPHICS)
	elif control == _performance_row:
		_go(Page.PERFORMANCE)
	elif control == _audio_row:
		_go(Page.AUDIO)
	elif control == _interface_row:
		_go(Page.INTERFACE)
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
	elif control == _shadows:
		_set_shadows(not shadows)
	elif control == _fog:
		_set_fog(not fog)
	elif control == _air:
		_set_ambient_particles(not ambient_particles)
	elif control == _stirs:
		_set_environment_interaction(not environment_interaction)
	elif control == _ambience:
		_set_ambience_volume(AmbienceVolume.MIN if ambience_volume >= AmbienceVolume.MAX else ambience_volume + AmbienceVolume.STEP)
	elif control == _tailless:
		_set_tailless_motes(TaillessMotes.STOPS[(TaillessMotes.index_of(tailless_motes) + 1) % TaillessMotes.STOPS.size()])
	elif control == _shake:
		_set_shake(not screen_shake)
	elif control == _numbers:
		_set_numbers(not damage_numbers)
	elif control == _fps:
		_set_fps(not show_fps)
	elif control == _settings_back:
		_go(Page.MAIN, _settings)
	elif control == _map_back:
		_go(Page.MAIN, _map_row)
	elif control == _graphics_back or control == _performance_back or control == _audio_back or control == _interface_back:
		_go(Page.SETTINGS, page_row(page))


## `back` goes up a page; on the main page it resumes.
func _on_cancelled(player: int) -> void:
	if player != owner_player:
		return
	match page:
		Page.MAIN:
			close_menu()
		Page.SETTINGS:
			# Up to the main page on its Settings row, as a page of settings goes up on its own.
			_go(Page.MAIN, _settings)
		Page.MAP:
			_go(Page.MAIN, _map_row)
		_:
			# A page of settings goes up to Settings, its own row focused.
			_go(Page.SETTINGS, page_row(page))


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


## Read the saved "Dynamic lighting" choice and show it; feel is told only when it is not the
## default.
func _load_light() -> void:
	spell_light = bool(save.get_setting(LIGHT_SETTING, SpellLightSetting.default_on()))
	_light.set_meta(BASE_TEXT_META, LIGHT_TEXT % _word(spell_light))
	_show_needs_light()
	if spell_light != SpellLightSetting.default_on() and _events != null:
		_events.spell_light_changed.emit(spell_light)


## Flip the "Dynamic lighting" switch: show it, save it and tell feel.
func _set_light(on: bool) -> void:
	spell_light = on
	_light.set_meta(BASE_TEXT_META, LIGHT_TEXT % _word(on))
	_show_needs_light()
	save.set_setting(LIGHT_SETTING, on)
	if _events != null:
		_events.spell_light_changed.emit(on)


## The rows that need the light ("Shadows", "Fog", "Ambient particles") greyed while it is off: they
## keep their choice, and UIFocus skips them.
func _show_needs_light() -> void:
	for row: Button in [_shadows, _fog, _air]:
		row.disabled = not spell_light
	_mark_focus()


## Read the saved atmosphere switches ("Shadows", "Fog", "Ambient particles", "Environment
## interaction") and show them; feel is told of each only when it is not the platform's default.
func _load_atmosphere() -> void:
	shadows = _load_switch(_shadows, SHADOWS_TEXT, SHADOWS_SETTING, ShadowsSetting.default_on(), _events.shadows_changed if _events != null else Signal())
	fog = _load_switch(_fog, FOG_TEXT, FOG_SETTING, FogSetting.default_on(), _events.fog_changed if _events != null else Signal())
	ambient_particles = _load_switch(_air, AIR_TEXT, AIR_SETTING, AmbientParticles.default_on(), _events.ambient_particles_changed if _events != null else Signal())
	environment_interaction = _load_switch(_stirs, STIRS_TEXT, STIRS_SETTING, EnvironmentInteraction.default_on(), _events.environment_interaction_changed if _events != null else Signal())


## A saved switch read (`key`; `default` when none) and shown on `row` in `words`; `changed` (the
## bus's event; null with no bus) is sent it when it is not `default`. Returns it.
func _load_switch(row: Button, words: String, key: StringName, default: bool, changed: Signal) -> bool:
	var on: bool = bool(save.get_setting(key, default))
	row.set_meta(BASE_TEXT_META, words % _word(on))
	_mark_focus()
	if on != default and not changed.is_null():
		changed.emit(on)
	return on


## A switch flipped to `on`: shown on `row` in `words`, saved (`key`) and sent on `changed` (the
## bus's event; null with no bus).
func _flip_switch(row: Button, words: String, key: StringName, on: bool, changed: Signal) -> void:
	row.set_meta(BASE_TEXT_META, words % _word(on))
	_mark_focus()
	save.set_setting(key, on)
	if not changed.is_null():
		changed.emit(on)


func _set_shadows(on: bool) -> void:
	shadows = on
	_flip_switch(_shadows, SHADOWS_TEXT, SHADOWS_SETTING, on, _events.shadows_changed if _events != null else Signal())


func _set_fog(on: bool) -> void:
	fog = on
	_flip_switch(_fog, FOG_TEXT, FOG_SETTING, on, _events.fog_changed if _events != null else Signal())


func _set_ambient_particles(on: bool) -> void:
	ambient_particles = on
	_flip_switch(_air, AIR_TEXT, AIR_SETTING, on, _events.ambient_particles_changed if _events != null else Signal())


func _set_environment_interaction(on: bool) -> void:
	environment_interaction = on
	_flip_switch(_stirs, STIRS_TEXT, STIRS_SETTING, on, _events.environment_interaction_changed if _events != null else Signal())


## Read the saved "Ambience volume" and show it; feel is told only when it is not the default.
func _load_ambience_volume() -> void:
	var saved: int = AmbienceVolume.snap(int(save.get_setting(AMBIENCE_SETTING, AmbienceVolume.DEFAULT)))
	_show_ambience_volume(saved)
	if saved != AmbienceVolume.DEFAULT and _events != null:
		_events.ambience_volume_changed.emit(saved)


## Move the "Ambience volume" slider to `percent` (snapped inside its range): show it, save it and
## tell feel.
func _set_ambience_volume(percent: int) -> void:
	var next: int = AmbienceVolume.snap(percent)
	if next == ambience_volume:
		return
	_show_ambience_volume(next)
	save.set_setting(AMBIENCE_SETTING, next)
	if _events != null:
		_events.ambience_volume_changed.emit(next)


func _show_ambience_volume(percent: int) -> void:
	ambience_volume = percent
	_ambience.set_meta(BASE_TEXT_META, AMBIENCE_TEXT % AmbienceVolume.word_of(percent))
	_ambience_bar.value = percent
	_mark_focus()


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
