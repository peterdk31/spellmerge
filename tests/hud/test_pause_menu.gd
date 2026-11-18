extends "res://tests/support/suite.gd"
## Tests for the pause menu (hud/menus/pause) and the buttons that open menus (owner,
## 2026-10-26), one behaviour per test: `pause` (Start) opens it for the player who pressed it and
## stops the game for everyone; only that player works it; Resume, `back` on the main page and
## `pause` again close it and the game goes on; the Map page shows the run's map; Settings is one
## page of tabs (owner, 2026-11-18): Graphics (Fullscreen, Dynamic lighting, Shadows, Fog, Ambient
## particles, Environment interaction, Floor marks), Performance (Effect slots, Particles, Particle
## amount, Tailless motes, Max shots), Audio (Ambience volume) and Interface (Screen shake, Damage
## numbers, Show FPS, and the switches of the builder and of where the staff rows show the reload),
## LB and RB (Z and C) paging them round from either end with their glyphs at the row's ends, a switch
## focusing the tab's first row, the box sliding and the rows stepping in by whole pixels, the panel
## one size on every tab and inside the view, no Back row and `back` going up to the main page on
## Settings; the rows that need Dynamic lighting greyed and skipped while it is off;
## `back` (B) opens the builder in play, but not from inside a menu nor while paused; `pause` closes
## an open builder; A on the hub's lit stone, by an item and on the altar, in that order; Main menu
## and Leave game let the game go first; a seat waiting for its unplugged gamepad is named and can
## be let go. The menu's stop is a reason of its own (online-ready N4).
##
## The settings' switches (Screen shake, Damage numbers, Floor marks, Dynamic lighting, Shadows, Fog,
## Ambient particles, Environment interaction) and sliders (Effect slots, Particles, Particle amount,
## Max shots, Tailless motes, Ambience volume) behave alike, so each of
## those behaviours is one test over every switch or every slider (`_switches()`, `_sliders()`).
##
## Each test builds what it needs with `_setup`: the HUD (hud/panels/panels.tscn) on a bus, input
## manager (virtual devices), UI focus and save of its own, and a stand-in for the main menu scene.
## After each test it is all freed, the save file is removed, the tree is unpaused and the current
## scene is the one before.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
## Loaded when needed, not preloaded: this scene is also the "Hud" autoload (see test_radial_builder.gd).
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
const HudScript := preload("res://hud/panels/panels.gd")
const PauseMenuScript := preload("res://hud/menus/pause/pause_menu.gd")
const RadialScript := preload("res://hud/builder/radial_builder.gd")
const MenuTabsScript := preload("res://hud/widgets/menu_tabs.gd")
const RingZoomScript := preload("res://hud/builder/rings/ring_zoom.gd")
const RingKindsScript := preload("res://hud/builder/rings/ring_kinds.gd")
const StaffRowScript := preload("res://hud/panels/player_panel/staff_row.gd")

const SAVE_PATH: String = "user://test_pause_menu_save.cfg"
## The main page out of a run of rooms.
const MAIN_PAGE: Array[String] = ["Resume", "Settings", "LeaveGame", "MainMenu"]
## The name of the stand-in the HUD shows for the main menu.
const MENU_STAND_IN: String = "MenuStandIn"
## The settings' signals, by row: what each row's moves send (feel, the projectile manager).
const SIGNAL_OF: Dictionary = {
	"EffectSlots": &"effect_slots_changed",
	"MoteCap": &"mote_cap_changed",
	"MoteDensity": &"mote_density_changed",
	"ShotCap": &"projectile_cap_changed",
	"TaillessMotes": &"tailless_motes_changed",
	"ScreenShake": &"screen_shake_changed",
	"DamageNumbers": &"damage_numbers_changed",
	"FloorMarks": &"floor_marks_changed",
	"SpellLight": &"spell_light_changed",
	"Shadows": &"shadows_changed",
	"Fog": &"fog_changed",
	"AmbientParticles": &"ambient_particles_changed",
	"EnvironmentInteraction": &"environment_interaction_changed",
	"AmbienceVolume": &"ambience_volume_changed",
}
## The Settings tabs, left to right.
const TAB_ORDER: Array[String] = ["Graphics", "Performance", "Audio", "Interface"]
## Each Settings tab's rows, in order.
const TAB_ROWS: Dictionary = {
	"Graphics": ["Fullscreen", "SpellLight", "Shadows", "Fog", "AmbientParticles", "EnvironmentInteraction", "FloorMarks"],
	"Performance": ["EffectSlots", "MoteCap", "MoteDensity", "TaillessMotes", "ShotCap"],
	"Audio": ["AmbienceVolume"],
	"Interface": ["ScreenShake", "DamageNumbers", "ShowFps", "RingStyle", "PutStyle", "ReloadStyle"],
}
## The game's view (project.godot), which every page fits in.
const VIEW: Vector2 = Vector2(640.0, 360.0)

## Whether the menu's last `pause_requested` asked the game to stop.
var _stops: bool = false
var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _hud: HudScript
## Every `shot_cap_requested` the bus sent, as [player, cap] (online-ready N11: the run's cap).
var _cap_requests: Array[Array] = []
## What each settings row's signal sent, by row name (SIGNAL_OF), from before the Hud binds.
var _heard: Dictionary = {}
## The current scene before the test (the main menu's stand-in may take its place).
var _scene_before: Node


func before_each() -> void:
	_scene_before = current_scene
	DirAccess.remove_absolute(SAVE_PATH)


func after_each() -> void:
	_teardown()
	paused = false
	var shown: Node = current_scene
	if shown != _scene_before and shown != null and is_instance_valid(shown):
		shown.free()
	current_scene = _scene_before
	DirAccess.remove_absolute(SAVE_PATH)


## The HUD for `count` seats on virtual devices, in a room; it reads and writes the test's own save
## (empty unless a test wrote it).
func _setup(count: int) -> void:
	_teardown()
	_bus = EventsScript.new()
	_input = InputManagerScript.new()
	_input.events = _bus
	_focus = UIFocusScript.new()
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	_bus.shot_cap_requested.connect(func(player: int, cap: int) -> void: _cap_requests.append([player, cap]))
	for row: String in SIGNAL_OF:
		_heard[row] = []
		_bus.connect(SIGNAL_OF[row], func(value: Variant) -> void: (_heard[row] as Array).append(value))
	# The menu's pause is a command (online-ready N4): the stop it asks for, last heard.
	_stops = false
	_bus.pause_requested.connect(func(_player: int, on: int) -> void: _stops = on != 0)
	for index in count:
		_input.add_virtual_device(index)
	_hud = (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	_hud.events = _bus
	_hud.ui_focus = _focus
	_hud.input = _input
	# Tests never touch the real save: an empty one of their own.
	_hud.save = SaveFile.new(SAVE_PATH)
	_hud.main_menu = _stand_in()
	root.add_child(_hud)
	for index in count:
		_bus.player_joined.emit(index)
	_bus.room_entered.emit(&"test_room")


## A scene of one plain node named MENU_STAND_IN, for the main menu.
func _stand_in() -> PackedScene:
	var scene := PackedScene.new()
	var made := Node.new()
	made.name = MENU_STAND_IN
	scene.pack(made)
	made.free()
	return scene


func _teardown() -> void:
	_stops = false
	_cap_requests.clear()
	_heard.clear()
	for node: Node in [_hud, _focus, _input, _bus]:
		if node != null and is_instance_valid(node):
			if node.is_inside_tree():
				node.get_parent().remove_child(node)
			node.free()
	_hud = null
	_focus = null
	_input = null
	_bus = null


func _tap(player: int, action: StringName) -> void:
	_input.send_virtual(player, action, 1.0)
	_input.send_virtual(player, action, 0.0)


## A pad's A (or Enter): it presses `accept` and `take` both.
func _tap_a(player: int) -> void:
	_tap(player, &"accept")
	_tap(player, &"take")


func _frame() -> void:
	_hud.poll()
	_focus.poll()


## `action` tapped by `player`, then a frame.
func _do(player: int, action: StringName) -> void:
	_tap(player, action)
	_frame()


func _menu() -> PauseMenuScript:
	return _hud.get_pause_menu()


func _names() -> Array[String]:
	var names: Array[String] = []
	for shown: Button in _menu().shown_buttons():
		names.append(String(shown.name))
	return names


## Press `button_name` on the menu as `player` (a row of Settings reached first as a player would:
## `_reach`).
func _press(player: int, button_name: String) -> void:
	_reach(player, button_name)
	_focus.focus(player, _menu().button(button_name))
	_tap(player, &"accept")
	_frame()


func _focused(button_name: String) -> bool:
	return _menu().button(button_name).text.begins_with("> ")


func _text_of(button_name: String) -> String:
	return _menu().button(button_name).text


## The Settings tab holding `button_name` shown, if it is not: Settings opened from the main page
## (up to it first from another page), then RB until the tab shows, all as `player`.
func _reach(player: int, button_name: String) -> void:
	var on: int = _menu().tab_of(_menu().button(button_name))
	if on < 0:
		return
	if _menu().page != PauseMenuScript.Page.SETTINGS:
		if _menu().page != PauseMenuScript.Page.MAIN:
			_do(player, &"back")
		_focus.focus(player, _menu().button("Settings"))
		_tap(player, &"accept")
		_frame()
	for _tab in PauseMenuScript.Tab.size():
		if _menu().tab == on:
			return
		_do(player, &"page_next")


## `player` opens the menu.
func _open(player: int = 0) -> void:
	_do(player, &"pause")


## One seat with the Settings page open.
func _settings() -> void:
	_setup(1)
	_open()
	_press(0, "Settings")


## Two values that may be an int and a float (a stop, as sent, saved or held).
func _same(a: Variant, b: Variant) -> bool:
	return a != null and b != null and is_equal_approx(float(a), float(b))


# --- Opening and closing -----------------------------------------------------------------------


func test_closed_and_running_at_the_start() -> void:
	_setup(2)
	check(not _menu().visible and not _stops, "closed and running at the start")


func test_start_opens_the_pause_menu() -> void:
	_setup(2)
	_open(1)
	check(_menu().is_open() and _menu().visible, "Start opens the pause menu")


func test_the_menu_is_for_the_player_who_pressed_start() -> void:
	_setup(2)
	_open(1)
	check_equal(_menu().owner_player, 1, "for the player who pressed it")


func test_start_stops_the_game_for_everyone() -> void:
	_setup(2)
	_open(1)
	check(_stops, "the game stops for everyone (the command pause_requested)")


func test_the_main_page_out_of_a_run_of_rooms() -> void:
	_setup(2)
	_open(1)
	check_equal(_names(), MAIN_PAGE, "the main page out of a run of rooms")


func test_the_focus_is_marked_with_text() -> void:
	_setup(2)
	_open(1)
	check(_focused("Resume"), "the focus is marked with text")


func test_another_players_buttons_do_nothing_to_it() -> void:
	_setup(2)
	_open(0)
	_tap(1, &"accept")
	_do(1, &"pause")
	check(_menu().is_open() and _menu().owner_player == 0, "another player's buttons do nothing to it")


func test_nobody_opens_a_builder_while_the_game_is_paused() -> void:
	_setup(2)
	_open(0)
	_do(1, &"back")
	check(not _hud.get_radial(1).is_open(), "nobody opens a builder while the game is paused")


## The menu opened by the one seat, then `way` tapped (accept lands on Resume, the first button).
func _closed_with(way: StringName) -> void:
	_setup(1)
	_open()
	check(_menu().is_open() and _stops, "%s: open" % way)
	_do(0, way)


func test_resume_closes_it() -> void:
	_closed_with(&"accept")
	check(not _menu().is_open() and not _menu().visible, "Resume closes the menu")


func test_b_on_the_main_page_closes_it() -> void:
	_closed_with(&"back")
	check(not _menu().is_open() and not _menu().visible, "B closes the menu")


func test_start_again_closes_it() -> void:
	_closed_with(&"pause")
	check(not _menu().is_open() and not _menu().visible, "Start closes the menu")


func test_closing_it_lets_the_game_go() -> void:
	for way: StringName in [&"accept", &"back", &"pause"]:
		_closed_with(way)
		check(not _stops, "%s: the game goes on" % way)


func test_closing_it_with_b_opens_no_builder() -> void:
	_closed_with(&"back")
	check(not _hud.get_radial(0).is_open(), "closing with B does not open the builder")


func test_a_run_ending_closes_it() -> void:
	_setup(1)
	_open()
	_bus.run_ended.emit(false)
	check(not _menu().is_open(), "a run ending closes the menu")


func test_a_run_ending_lets_the_game_go() -> void:
	_setup(1)
	_open()
	_bus.run_ended.emit(false)
	check(not _stops, "a run ending lets the game go")


# --- The builder's and the reload's switches (Settings) ---------------------------------------


## Two seats, seat `player` on its Settings page, where the builder's and the reload's switches are.
func _switches_page(player: int = 1) -> void:
	_setup(2)
	_open(player)
	_press(player, "Settings")


func test_the_settings_page_stays_after_each_builder_switch() -> void:
	for row: String in ["RingStyle", "PutStyle", "ReloadStyle"]:
		_switches_page()
		_press(1, row)
		check(_menu().is_open() and _menu().page == PauseMenuScript.Page.SETTINGS and _menu().tab == PauseMenuScript.Tab.INTERFACE, "the tab stays after %s, for another press" % row)


# --- The reload's place (Settings) -------------------------------------------------------------


func test_the_reload_is_on_the_button_by_default() -> void:
	_switches_page(0)
	check(_text_of("ReloadStyle").ends_with("Reload: Button"), "the reload is on the button by default")


func test_the_staff_rows_draw_the_reload_on_the_button_by_default() -> void:
	_switches_page(0)
	check_equal(_hud.get_panel(1).staff_row(0).style, StaffRowScript.Style.BUTTON, "the rows draw it there")


func test_the_reload_flips_to_the_next_cast() -> void:
	_switches_page(0)
	_press(0, "ReloadStyle")
	check(_text_of("ReloadStyle").ends_with("Reload: Next cast"), "it flips to the next cast")


func test_every_staff_row_of_every_panel_follows_the_reload() -> void:
	_switches_page(0)
	_press(0, "ReloadStyle")
	for player in 4:
		for staff in 4:
			check(_hud.get_panel(player).staff_row(staff).style == StaffRowScript.Style.NEXT_CAST, "every row of every panel follows (P%d staff %d)" % [player + 1, staff + 1])


func test_each_reload_flip_goes_out() -> void:
	_switches_page(0)
	var sent: Array[bool] = []
	_menu().reload_style_changed.connect(func(on_button: bool) -> void: sent.append(on_button))
	_press(0, "ReloadStyle")
	_press(0, "ReloadStyle")
	check_equal(sent, [false, true] as Array[bool], "each flip goes out")


func test_the_reload_flips_back_on_the_button() -> void:
	_switches_page(0)
	_press(0, "ReloadStyle")
	_press(0, "ReloadStyle")
	check_equal(_hud.get_panel(0).staff_row(2).style, StaffRowScript.Style.BUTTON, "back on the button")


# --- The builder's options (Settings) ----------------------------------------------------------


func test_there_is_no_switch_to_another_builder() -> void:
	_switches_page(0)
	check(_menu().button("BuilderStyle") == null, "no switch to another builder: the list builder is gone")


func test_a_full_slot_pushes_right_by_default() -> void:
	_switches_page(0)
	check(_text_of("PutStyle").ends_with("Full slot: Push right"), "a full slot pushes right by default")


func test_each_builder_option_flip_goes_out() -> void:
	_switches_page(0)
	var options: Array = []
	_menu().builder_options_changed.connect(func(ring: int, push: bool) -> void: options.append([ring, push]))
	_press(0, "RingStyle")
	_press(0, "PutStyle")
	check(options == [[1, true], [1, false]], "each flip goes out, got %s" % [options])


func test_the_second_ring_style_shows_one_kind_at_a_time() -> void:
	_switches_page(0)
	_press(0, "RingStyle")
	check_equal(_hud.get_radial(0).layout, RadialScript.Layout.KIND, "the ring shows one kind at a time")


func test_the_full_slot_flip_replaces_a_full_slot() -> void:
	_switches_page(0)
	_press(0, "PutStyle")
	check_equal(_hud.get_radial(0).put, RadialScript.Put.REPLACE, "a full slot is replaced")


## The ring styles to try (owner, 2026-10-30), then round to the first again: the words shown
## and the radial's ring picker after each of the four presses after the first.
func _ring_styles() -> Array:
	_switches_page(0)
	_press(0, "RingStyle")
	var words: Array[String] = []
	var styles: Array = []
	for _step in 4:
		_press(0, "RingStyle")
		words.append(_text_of("RingStyle").get_slice("Ring: ", 1))
		styles.append(_hud.get_radial(0).ring_picker.get_script() if _hud.get_radial(0).ring_picker != null else null)
	return [words, styles]


func test_the_ring_steps_through_its_styles() -> void:
	var words: Array = _ring_styles()[0]
	check(words == ["Zoom", "Kinds: hold", "Kinds: depth", "Every card"], "the ring steps through the styles, got %s" % [words])


func test_the_radial_gets_each_ring_style() -> void:
	var styles: Array = _ring_styles()[1]
	check(styles == [RingZoomScript, RingKindsScript, RingKindsScript, null], "the radial gets each style")


func test_the_ring_styles_come_round_to_every_card() -> void:
	_ring_styles()
	check_equal(_hud.get_radial(0).layout, RadialScript.Layout.ALL, "every card again")


# --- The Map page (run generation RG8) ---------------------------------------------------------
# In a run of rooms (a map told, `run_map_changed`) the main page has Map, whose page shows the
# run's map, its kinds named by the registry, and Back; the map gone, the row goes and a Map page
# shown goes back to the main page.


const MAP_PAGE: Array[String] = ["Resume", "Map", "Settings", "LeaveGame", "MainMenu"]


## Tell the HUD a map of two rooms (a fight, then the boss), the party at `at`.
func _tell_map(at: int = 0) -> void:
	var links: Array[PackedInt32Array] = [PackedInt32Array([1]), PackedInt32Array()]
	_bus.run_map_changed.emit(PackedInt32Array([0, 1]), [&"fight", &"boss"] as Array[StringName], links, at)


func _tell_no_map() -> void:
	_bus.run_map_changed.emit(PackedInt32Array(), [] as Array[StringName], [] as Array[PackedInt32Array], -1)


## One seat in a run of rooms with the menu open; on the Map page when `on_map`.
func _map_menu(on_map: bool = true) -> void:
	_setup(1)
	_tell_map()
	_open()
	if on_map:
		_press(0, "Map")


func test_in_a_run_of_rooms_the_main_page_has_map() -> void:
	_map_menu(false)
	check_equal(_names(), MAP_PAGE, "in a run of rooms the main page has Map")


func test_the_map_shows_on_its_page_only() -> void:
	_map_menu(false)
	check(not _menu().map_view().visible, "the map shows on its page only")


func test_the_map_page_holds_the_map_and_back() -> void:
	_map_menu()
	check(_menu().page == PauseMenuScript.Page.MAP and _names() == ["MapBack"], "the Map page: the map and Back, got %s" % [_names()])
	check(_menu().map_view().visible and _menu().map_view().call("has_map"), "the map shows")


func test_the_map_names_its_kinds_by_the_registry() -> void:
	_map_menu()
	check_equal(String(_menu().map_view().call("kinds_line")), "F Fight  B Boss", "the kinds by the registry's names")


func test_back_is_focused_on_the_map_page() -> void:
	_map_menu()
	check(_focused("MapBack"), "Back is focused")


func test_back_goes_from_the_map_to_the_main_page() -> void:
	_map_menu()
	_press(0, "MapBack")
	check(_menu().page == PauseMenuScript.Page.MAIN and _menu().is_open(), "Back goes to the main page")


func test_b_goes_from_the_map_to_the_main_page() -> void:
	_map_menu()
	_do(0, &"back")
	check(_menu().page == PauseMenuScript.Page.MAIN and _menu().is_open(), "B goes back to the main page")


func test_a_new_map_keeps_the_map_page_with_back_focused() -> void:
	# A room entered while the page shows (the pause not yet in effect online): it stays, on Back.
	_map_menu()
	_tell_map(1)
	check(_menu().page == PauseMenuScript.Page.MAP and _focused("MapBack"), "a new map keeps the page, Back focused")


func test_a_new_map_shows_where_the_party_is_now() -> void:
	_map_menu()
	_tell_map(1)
	check_equal(int(_menu().map_view().get("at")), 1, "the map shows where the party is now")


func test_the_map_gone_its_page_goes_back_to_the_main_page_without_map() -> void:
	_map_menu()
	_tell_no_map()
	check(_menu().page == PauseMenuScript.Page.MAIN and _names() == MAIN_PAGE, "the map gone: back to the main page, with no Map, got %s" % [_names()])


func test_the_map_gone_from_its_page_the_first_row_is_focused() -> void:
	_map_menu()
	_tell_no_map()
	check(_focused("Resume"), "the main page's first row is focused")


func test_a_map_arriving_on_the_main_page_adds_its_row() -> void:
	_setup(1)
	_open()
	_tell_map()
	check_equal(_names(), MAP_PAGE, "the Map row comes")


func test_a_map_arriving_keeps_the_focus_where_it_was() -> void:
	_setup(1)
	_open()
	_focus.focus(0, _menu().button("Settings"))
	_frame()
	_tell_map()
	check(_focused("Settings"), "the focus stays on Settings")


func test_the_map_row_focused_when_the_map_goes_focuses_resume() -> void:
	_map_menu(false)
	_focus.focus(0, _menu().button("Map"))
	_frame()
	_tell_no_map()
	check(_menu().is_open() and _focused("Resume"), "the Map row gone: Resume is focused")


# --- The Settings page: its tabs -----------------------------------------------------------------
# One page with a row of tabs (owner, 2026-11-18): Graphics, Performance, Audio, Interface; LB and RB
# (Z and C) page them, round from the ends; the glyphs at the row's ends; a switch focuses the tab's
# first row; B goes up to the main page on Settings; no Back row; the panel the same size on every
# tab, inside the view.


## The tab shown, by name.
func _tab_name() -> String:
	return PauseMenuScript.TAB_NAMES[_menu().tab]


## `player` on the main page, then on Settings.
func _open_settings(player: int = 0) -> void:
	_focus.focus(player, _menu().button("Settings"))
	_tap(player, &"accept")
	_frame()


func test_settings_opens_on_graphics_with_its_first_row_focused() -> void:
	_settings()
	check(_menu().page == PauseMenuScript.Page.SETTINGS and _tab_name() == "Graphics", "Settings opens on Graphics, got %s" % _tab_name())
	check(_focused("Fullscreen"), "its first row focused")
	check_equal(_menu().get_node("Rows/Title").text, "P1 SETTINGS", "the title")


func test_the_tabs_in_order() -> void:
	_settings()
	check_equal(_menu().tabs().names(), Array(TAB_ORDER, TYPE_STRING, &"", null), "the tabs, left to right")


func test_each_tab_has_its_rows() -> void:
	_settings()
	for at in TAB_ORDER.size():
		check_equal(_names(), Array(TAB_ROWS[TAB_ORDER[at]], TYPE_STRING, &"", null), "%s's rows" % TAB_ORDER[at])
		_do(0, &"page_next")


func test_rb_goes_to_the_next_tab_from_each_and_round() -> void:
	_settings()
	for at in TAB_ORDER.size():
		var next: String = TAB_ORDER[(at + 1) % TAB_ORDER.size()]
		_do(0, &"page_next")
		check_equal(_tab_name(), next, "RB from %s" % TAB_ORDER[at])
		check(_menu().tabs().selected() == _menu().tab, "the tab row selects %s too" % next)


func test_lb_goes_to_the_previous_tab_from_each_and_round() -> void:
	_settings()
	for at in range(TAB_ORDER.size(), 0, -1):
		var from: String = TAB_ORDER[at % TAB_ORDER.size()]
		_do(0, &"page_prev")
		check_equal(_tab_name(), TAB_ORDER[at - 1], "LB from %s" % from)


func test_lb_from_graphics_wraps_round_to_interface() -> void:
	_settings()
	_do(0, &"page_prev")
	check_equal(_tab_name(), "Interface", "LB on the first tab goes round to the last")


func test_rb_from_interface_wraps_round_to_graphics() -> void:
	_settings()
	_do(0, &"page_prev")
	_do(0, &"page_next")
	check_equal(_tab_name(), "Graphics", "RB on the last tab goes round to the first")


func test_a_switch_focuses_the_tabs_first_row() -> void:
	_settings()
	_do(0, &"move_down")
	_do(0, &"move_down")
	for at in range(1, TAB_ORDER.size() + 1):
		_do(0, &"page_next")
		var first: String = TAB_ROWS[TAB_ORDER[at % TAB_ORDER.size()]][0]
		check(_focused(first), "%s opens on %s" % [_tab_name(), first])


func test_down_goes_through_every_row_of_a_tab_and_round() -> void:
	_settings()
	for tab_name: String in TAB_ORDER:
		var rows: Array = TAB_ROWS[tab_name]
		for at in rows.size():
			check(_focused(rows[at]), "%s: down reaches %s" % [tab_name, rows[at]])
			_do(0, &"move_down")
		check(_focused(rows[0]), "%s: down from its last row comes round to %s" % [tab_name, rows[0]])
		_do(0, &"page_next")


func test_paging_does_nothing_off_the_settings_page() -> void:
	_setup(1)
	_open()
	_do(0, &"page_next")
	check(_menu().page == PauseMenuScript.Page.MAIN and _focused("Resume"), "RB on the main page changes nothing")


func test_another_players_rb_does_not_page_the_tabs() -> void:
	_setup(2)
	_open(1)
	_open_settings(1)
	_do(0, &"page_next")
	check_equal(_tab_name(), "Graphics", "P1's RB leaves P2's Settings on Graphics")


func test_b_from_each_tab_goes_up_to_the_main_page_on_settings() -> void:
	for at in TAB_ORDER.size():
		_settings()
		for _step in at:
			_do(0, &"page_next")
		_do(0, &"back")
		check(_menu().is_open() and _menu().page == PauseMenuScript.Page.MAIN and _focused("Settings"), "B on %s: the main page, on Settings" % TAB_ORDER[at])


func test_settings_opens_on_graphics_again_after_b() -> void:
	_settings()
	_do(0, &"page_next")
	_do(0, &"back")
	_open_settings()
	check(_tab_name() == "Graphics" and _focused("Fullscreen"), "Settings opens on Graphics again")


func test_there_is_no_back_row_in_settings() -> void:
	for row: String in ["SettingsBack", "GraphicsBack", "PerformanceBack", "AudioBack", "InterfaceBack", "Graphics", "Performance", "Audio", "Interface"]:
		_settings()
		check(_menu().button(row) == null, "no %s row" % row)


func test_the_hint_shows_the_back_button() -> void:
	_settings()
	check_equal(_menu().hint_glyph().current_glyph()["label"], "B", "the B glyph beside Back")
	check(_menu().hint_glyph().is_visible_in_tree(), "shown on Settings")
	_do(0, &"back")
	check(not _menu().hint_glyph().is_visible_in_tree(), "not on the main page")


func test_the_tab_row_shows_lb_and_rb_on_a_pad() -> void:
	_settings()
	check_equal(_menu().tabs().prev_glyph().current_glyph()["label"], "LB", "LB at the left end")
	check_equal(_menu().tabs().next_glyph().current_glyph()["label"], "RB", "RB at the right end")


func test_the_glyphs_sit_at_the_tab_rows_ends() -> void:
	_settings()
	var tabs: MenuTabsScript = _menu().tabs()
	var first: Rect2 = tabs.tab_rect(0)
	var last: Rect2 = tabs.tab_rect(TAB_ORDER.size() - 1)
	check(tabs.prev_glyph().position.x + tabs.prev_glyph().size.x <= first.position.x, "LB left of the first tab")
	check(tabs.next_glyph().position.x >= last.end.x, "RB right of the last tab")
	check(tabs.next_glyph().position.x + tabs.next_glyph().size.x <= tabs.size.x, "RB inside the row")


func test_the_tab_row_follows_the_device_of_the_player_working_it() -> void:
	_setup(2)
	_open(1)
	_open_settings(1)
	check_equal(_menu().tabs().next_glyph().current_glyph()["label"], "RB", "P2's pad")


## One seat on this machine's keyboard, the pause menu open by Escape, on Settings.
func _keyboard_settings() -> void:
	_setup(0)
	_input.join(InputManagerScript.KEYBOARD)
	_bus.player_joined.emit(0)
	_bus.room_entered.emit(&"test_room")
	_key(KEY_ESCAPE)
	_focus.focus(0, _menu().button("Settings"))
	_focus.activate(0)
	_frame()


## A key pressed and let go on the keyboard, then a frame.
func _key(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = down
		_input.handle_event(event)
	_frame()


func test_on_the_keyboard_z_and_c_page_the_tabs() -> void:
	_keyboard_settings()
	check(_menu().is_open() and _menu().page == PauseMenuScript.Page.SETTINGS, "Escape opened the menu, on Settings")
	_key(KEY_C)
	check_equal(_tab_name(), "Performance", "C: the next tab")
	_key(KEY_Z)
	_key(KEY_Z)
	check_equal(_tab_name(), "Interface", "Z twice: back round to the last")


func test_on_the_keyboard_the_tab_row_shows_z_and_c() -> void:
	_keyboard_settings()
	check_equal(_menu().tabs().prev_glyph().current_glyph()["label"], "Z", "Z at the left end")
	check_equal(_menu().tabs().next_glyph().current_glyph()["label"], "C", "C at the right end")
	check_equal(_menu().hint_glyph().current_glyph()["label"], "E", "E beside Back")


func test_on_the_keyboard_e_goes_back_to_the_main_page() -> void:
	_keyboard_settings()
	_key(KEY_E)
	check(_menu().page == PauseMenuScript.Page.MAIN and _focused("Settings"), "E: the main page, on Settings")


func test_the_panel_is_the_same_size_on_every_tab_and_fits_the_view() -> void:
	_settings()
	var first: Vector2 = _menu().get_combined_minimum_size()
	for tab_name: String in TAB_ORDER:
		var shown: Vector2 = _menu().get_combined_minimum_size()
		check_equal(shown, first, "the panel on %s" % tab_name)
		check(shown.y <= VIEW.y and shown.x <= VIEW.x, "%s: %s fits the %s view" % [tab_name, shown, VIEW])
		_do(0, &"page_next")


func test_the_panels_size_holds_as_the_focus_moves_and_switches_flip() -> void:
	_settings()
	var least: Vector2 = _menu().get_combined_minimum_size()
	for tab_name: String in TAB_ORDER:
		for at in (TAB_ROWS[tab_name] as Array).size():
			_do(0, &"move_down")
			check_equal(_menu().get_combined_minimum_size(), least, "%s: the same with the focus on its row %d" % [tab_name, at + 1])
		_do(0, &"page_next")
	for switch: String in ["SpellLight", "Shadows", "Fog", "AmbientParticles", "EnvironmentInteraction", "FloorMarks", "ScreenShake", "ShowFps", "RingStyle", "PutStyle", "ReloadStyle"]:
		_settings()
		_press(0, switch)
		check_equal(_menu().get_combined_minimum_size(), least, "the same with %s flipped" % switch)


func test_every_row_of_every_tab_is_as_wide() -> void:
	_settings()
	var wide: float = _menu().button("Fullscreen").custom_minimum_size.x
	for tab_name: String in TAB_ORDER:
		for row: String in TAB_ROWS[tab_name]:
			check_equal(_menu().button(row).custom_minimum_size.x, wide, "%s as wide as the rest" % row)


func test_every_setting_row_is_reached_by_paging_and_moving() -> void:
	_settings()
	for tab_name: String in TAB_ORDER:
		for row: String in TAB_ROWS[tab_name]:
			check(_focused(row) and _menu().button(row).is_visible_in_tree(), "%s reached on %s" % [row, tab_name])
			_do(0, &"move_down")
		_do(0, &"page_next")


func test_a_switch_slides_the_box_and_steps_the_rows_in_by_whole_pixels() -> void:
	_settings()
	var tabs: MenuTabsScript = _menu().tabs()
	var from: float = tabs.box().position.x
	_do(0, &"page_next")
	var rows: Control = _menu().tab_body().get_node("TabRows") as Control
	check_equal(rows.position.x, PauseMenuScript.ROW_SHIFT, "the rows start to the right, toward the tab paged to")
	var boxes: Array[float] = [from]
	var shifts: Array[float] = [rows.position.x]
	for _frame_at in 12:
		tabs.step(1.0 / 60.0)
		if tabs.box().position.x != boxes.back():
			boxes.append(tabs.box().position.x)
		if rows.position.x != shifts.back():
			shifts.append(rows.position.x)
	check(boxes.size() >= 5, "the box passes at least 3 places between the tabs: %s" % [boxes])
	check(shifts.size() >= 4, "the rows at least 3 steps in: %s" % [shifts])
	for x: float in boxes + shifts:
		check_equal(x, roundf(x), "whole pixels")
	check(boxes.back() == tabs.tab_rect(1).position.x and rows.position.x == 0.0, "both end in place")


func test_lb_steps_the_rows_in_from_the_left() -> void:
	_settings()
	_do(0, &"page_prev")
	check_equal((_menu().tab_body().get_node("TabRows") as Control).position.x, -PauseMenuScript.ROW_SHIFT, "from the left")


func test_settings_opens_still() -> void:
	_settings()
	check(not _menu().tabs().is_sliding() and (_menu().tab_body().get_node("TabRows") as Control).position.x == 0.0, "nothing slides as Settings opens")



# --- The rows that need Dynamic lighting ---------------------------------------------------------
# Shadows, Fog and Ambient particles need the light: with Dynamic lighting off they show their
# choice greyed, the focus skips them and they change nothing; on again, they work.

const NEED_LIGHT: Array[String] = ["Shadows", "Fog", "AmbientParticles"]


func test_the_rows_that_need_the_light_work_while_it_is_on() -> void:
	_settings()
	for row in NEED_LIGHT:
		check(not _menu().button(row).disabled, "%s works with the light on" % row)


func test_dynamic_lighting_off_greys_the_rows_that_need_it() -> void:
	_settings()
	_press(0, "SpellLight")
	for row in NEED_LIGHT:
		check(_menu().button(row).disabled and _text_of(row).ends_with(": On"), "%s greyed, its choice kept: %s" % [row, _text_of(row)])
	check(not _menu().button("EnvironmentInteraction").disabled and not _menu().button("FloorMarks").disabled, "the others work")


func test_the_focus_skips_the_greyed_rows() -> void:
	_settings()
	_press(0, "SpellLight")
	_do(0, &"move_down")
	check(_focused("EnvironmentInteraction"), "down from Dynamic lighting skips to Environment interaction")


func test_the_greyed_rows_stay_greyed_and_skipped_after_a_tab_switch() -> void:
	_settings()
	_press(0, "SpellLight")
	_do(0, &"page_next")
	_do(0, &"page_prev")
	for row in NEED_LIGHT:
		check(_menu().button(row).disabled, "%s still greyed back on Graphics" % row)
	_do(0, &"move_down")
	_do(0, &"move_down")
	check(_focused("EnvironmentInteraction"), "down from Dynamic lighting still skips them")


func test_dynamic_lighting_on_again_lets_them_work() -> void:
	_settings()
	_press(0, "SpellLight")
	_press(0, "SpellLight")
	for row in NEED_LIGHT:
		check(not _menu().button(row).disabled, "%s works again" % row)


func test_a_saved_dynamic_lighting_off_greys_them_from_the_start() -> void:
	_settings()
	_press(0, "SpellLight")
	_setup(1)
	for row in NEED_LIGHT:
		check(_menu().button(row).disabled, "%s greyed in a later menu" % row)


func test_a_spell_light_saved_before_the_rename_carries_over() -> void:
	# The row was "Spell light"; its save key is kept.
	var old := SaveFile.new(SAVE_PATH)
	old.set_setting(&"spell_light", not SpellLightSetting.default_on())
	_settings()
	check(_text_of("SpellLight").ends_with("Dynamic lighting: %s" % ("On" if not SpellLightSetting.default_on() else "Off")), "the saved choice shows: %s" % _text_of("SpellLight"))


func test_settings_has_no_fire_settings() -> void:
	# The Gameplay page and its Friendly fire and Enemy fire rows are gone (actors G3c: every spell
	# hits everything, always).
	_settings()
	check(_menu().button("FriendlyFire") == null and _menu().button("EnemyFire") == null, "no fire settings")



# --- Fullscreen --------------------------------------------------------------------------------


## A stand-in for `core/display` (headless has no window to fill).
class FakeDisplay:
	extends Node
	var on: bool = false
	var toggles: int = 0

	func is_fullscreen() -> bool:
		return on

	func toggle_fullscreen() -> void:
		on = not on
		toggles += 1


## The Settings page on a stand-in display, freed after the test.
func _fullscreen_settings() -> FakeDisplay:
	_setup(1)
	var display := own(FakeDisplay.new()) as FakeDisplay
	_menu().display = display
	_open()
	_press(0, "Settings")
	return display


func test_fullscreen_says_off_in_a_window() -> void:
	_fullscreen_settings()
	check(_text_of("Fullscreen").ends_with("Fullscreen: Off"), "off in a window")


func test_fullscreen_asks_display_to_fill_the_screen() -> void:
	var display: FakeDisplay = _fullscreen_settings()
	_press(0, "Fullscreen")
	check(display.toggles == 1 and display.on, "it asks Display to fill the screen")


func test_fullscreen_then_shows_on() -> void:
	_fullscreen_settings()
	_press(0, "Fullscreen")
	check(_text_of("Fullscreen").ends_with("Fullscreen: On"), "and shows On")


func test_fullscreen_stays_on_the_settings_page() -> void:
	_fullscreen_settings()
	_press(0, "Fullscreen")
	check(_menu().page == PauseMenuScript.Page.SETTINGS and _menu().tab == PauseMenuScript.Tab.GRAPHICS, "it stays on the tab")


func test_fullscreen_shows_the_windows_own_state_when_shown_again() -> void:
	# The browser leaves fullscreen on its own (Escape): the word follows the window when shown again.
	var display: FakeDisplay = _fullscreen_settings()
	_press(0, "Fullscreen")
	display.on = false
	_do(0, &"back")
	_reach(0, "Fullscreen")
	check(_text_of("Fullscreen").ends_with("Fullscreen: Off"), "the window's own state shows when Settings opens again")


func test_fullscreen_shows_the_windows_own_state_when_its_tab_is_paged_to() -> void:
	var display: FakeDisplay = _fullscreen_settings()
	_press(0, "Fullscreen")
	_do(0, &"page_next")
	display.on = false
	_do(0, &"page_prev")
	check(_text_of("Fullscreen").ends_with("Fullscreen: Off"), "the window's own state shows back on Graphics")


# --- The switches ------------------------------------------------------------------------------
# Screen shake and Damage numbers (props W5) are on by default; Floor marks (spell spectacle P2a),
# Dynamic lighting (P3a's "Spell light") and the atmosphere's switches start at the platform's
# default. None sends anything at its default; accept
# flips it and tells feel, and the choice is saved: a menu bound to the same save later starts with
# it and tells feel.


## Each switch: its row, the words before ": On", its setting, its menu field and its default.
func _switches() -> Array[Dictionary]:
	return [
		{"row": "ScreenShake", "words": "Screen shake", "key": &"screen_shake", "field": "screen_shake", "start": true},
		{"row": "DamageNumbers", "words": "Damage numbers", "key": &"damage_numbers", "field": "damage_numbers", "start": true},
		{"row": "FloorMarks", "words": "Floor marks", "key": &"floor_marks", "field": "floor_marks", "start": FloorMarks.default_on()},
		{"row": "SpellLight", "words": "Dynamic lighting", "key": &"spell_light", "field": "spell_light", "start": SpellLightSetting.default_on()},
		{"row": "Shadows", "words": "Shadows", "key": &"shadows", "field": "shadows", "start": ShadowsSetting.default_on()},
		{"row": "Fog", "words": "Fog", "key": &"fog", "field": "fog", "start": FogSetting.default_on()},
		{"row": "AmbientParticles", "words": "Ambient particles", "key": &"ambient_particles", "field": "ambient_particles", "start": AmbientParticles.default_on()},
		{"row": "EnvironmentInteraction", "words": "Environment interaction", "key": &"environment_interaction", "field": "environment_interaction", "start": EnvironmentInteraction.default_on()},
	]


func _switch_text(switch: Dictionary, on: bool) -> String:
	return "%s: %s" % [switch["words"], "On" if on else "Off"]


## A fresh menu (on a fresh save) with `switch` pressed `presses` times on the Settings page.
func _flipped(switch: Dictionary, presses: int = 1) -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	_settings()
	for i in presses:
		_press(0, switch["row"])


## `switch` flipped once, then a later menu bound to the same save.
func _later_menu_after_flipping(switch: Dictionary) -> void:
	_flipped(switch)
	_setup(1)


func test_no_switch_sends_anything_at_its_default() -> void:
	for switch in _switches():
		_setup(1)
		check((_heard[switch["row"]] as Array).is_empty(), "%s: nothing is sent at its default" % switch["row"])


func test_every_switch_shows_its_default() -> void:
	for switch in _switches():
		_settings()
		check(_text_of(switch["row"]).ends_with(_switch_text(switch, switch["start"])), "%s: the default at the start: %s" % [switch["row"], _text_of(switch["row"])])


func test_accept_flips_a_switch() -> void:
	for switch in _switches():
		_flipped(switch)
		check(_text_of(switch["row"]).ends_with(_switch_text(switch, not switch["start"])), "%s: it flips: %s" % [switch["row"], _text_of(switch["row"])])
		check_equal(bool(_menu().get(switch["field"])), not switch["start"], "%s: the menu holds it" % switch["row"])


func test_a_flipped_switch_tells_feel() -> void:
	for switch in _switches():
		_flipped(switch)
		check(_heard[switch["row"]] == [not switch["start"]], "%s: feel is told, got %s" % [switch["row"], _heard[switch["row"]]])


func test_the_save_remembers_a_flipped_switch() -> void:
	for switch in _switches():
		_flipped(switch)
		check_equal(bool(SaveFile.new(SAVE_PATH).get_setting(switch["key"], switch["start"])), not switch["start"], "%s: the save remembers it" % switch["row"])


func test_a_switch_flipped_back_tells_feel() -> void:
	for switch in _switches():
		_flipped(switch, 2)
		check(_heard[switch["row"]] == [not switch["start"], switch["start"]], "%s: it flips back, feel told, got %s" % [switch["row"], _heard[switch["row"]]])


func test_a_switch_flipped_back_is_saved() -> void:
	for switch in _switches():
		_flipped(switch, 2)
		check_equal(bool(SaveFile.new(SAVE_PATH).get_setting(switch["key"], not switch["start"])), switch["start"], "%s: flipped back, saved" % switch["row"])


func test_a_later_menu_starts_with_a_saved_switch() -> void:
	for switch in _switches():
		_later_menu_after_flipping(switch)
		check_equal(bool(_menu().get(switch["field"])), not switch["start"], "%s: a later menu starts with the saved choice" % switch["row"])


func test_a_later_menu_tells_feel_a_saved_switch_when_the_hud_binds() -> void:
	for switch in _switches():
		_later_menu_after_flipping(switch)
		check(_heard[switch["row"]] == [not switch["start"]], "%s: feel is told when the Hud binds, got %s" % [switch["row"], _heard[switch["row"]]])


# --- Show FPS ----------------------------------------------------------------------------------
# Off by default (the readout hidden), flips on accept, shows the readout, and is kept in the save:
# a Hud bound to the same save later shows it from the start.


func test_the_fps_readout_is_hidden_by_default() -> void:
	_setup(1)
	var fps: Label = _hud.get_fps_counter()
	check(fps != null and not fps.visible, "the readout is hidden by default")


func test_the_show_fps_switch_says_off_by_default() -> void:
	_settings()
	check(_text_of("ShowFps").ends_with("Show FPS: Off"), "the switch says Off")


func test_show_fps_shows_the_readout() -> void:
	_settings()
	_press(0, "ShowFps")
	check(_text_of("ShowFps").ends_with("Show FPS: On"), "it flips on")
	check(_hud.get_fps_counter().visible, "and shows the readout")


func test_the_fps_readout_reads_n_fps() -> void:
	_settings()
	_press(0, "ShowFps")
	check(_hud.get_fps_counter().text.ends_with(" FPS"), "the readout reads 'N FPS', got '%s'" % _hud.get_fps_counter().text)


func test_the_save_remembers_show_fps() -> void:
	_settings()
	_press(0, "ShowFps")
	check(bool(SaveFile.new(SAVE_PATH).get_setting(&"show_fps", false)), "the save remembers it")


func test_a_later_hud_shows_the_fps_readout_from_the_start() -> void:
	_settings()
	_press(0, "ShowFps")
	_setup(1)
	check(_menu().show_fps and _hud.get_fps_counter().visible, "a later Hud shows it from the start")


func test_show_fps_flips_back_off_saved() -> void:
	_settings()
	_press(0, "ShowFps")
	_settings()
	_press(0, "ShowFps")
	check(not _hud.get_fps_counter().visible, "the readout hides again")
	check(not bool(SaveFile.new(SAVE_PATH).get_setting(&"show_fps", true)), "off, saved")


# --- The sliders -------------------------------------------------------------------------------
# Effect slots, Particles (spell spectacle P1a: Minimal to High, no Off since S3), Particle amount
# (P1b: None to Double), Max shots, Tailless motes (S5 step 4: a dev slider) and Ambience volume
# (atmosphere, "Settings": 0% to 100%) start at their
# default (the platform's cap for Particles and Max shots) and send nothing; left and right step
# through the stops, keep the focus and tell feel or the projectile manager, the ends do not move;
# accept steps up and wraps; and every one but Effect slots is saved: a menu bound to the same
# save later starts with it and tells them.


## Each slider: its row, its stops, its default, its menu field, its setting (none for Effect
## slots, which is not saved), its words for a stop and its bar's value for a stop.
func _sliders() -> Array[Dictionary]:
	var slots: Array = []
	for value in range(EffectSlots.MIN, EffectSlots.MAX + 1, EffectSlots.STEP):
		slots.append(value)
	var volumes: Array = []
	for value in range(AmbienceVolume.MIN, AmbienceVolume.MAX + 1, AmbienceVolume.STEP):
		volumes.append(value)
	return [
		{"row": "EffectSlots", "stops": slots, "start": EffectSlots.DEFAULT, "field": "effect_slots", "key": &"",
			"text": func(v: Variant) -> String: return "Effect slots: %d" % int(v), "bar": func(v: Variant) -> float: return float(v)},
		{"row": "MoteCap", "stops": Array(MoteCap.STOPS), "start": MoteCap.default_cap(), "field": "mote_cap", "key": &"mote_cap",
			"text": func(v: Variant) -> String: return "Particles: %s" % MoteCap.word_of(int(v)), "bar": func(v: Variant) -> float: return float(MoteCap.index_of(int(v)))},
		{"row": "MoteDensity", "stops": Array(MoteDensity.STOPS), "start": MoteDensity.DEFAULT, "field": "mote_density", "key": &"mote_density",
			"text": func(v: Variant) -> String: return "Particle amount: %s" % MoteDensity.word_of(float(v)), "bar": func(v: Variant) -> float: return float(MoteDensity.index_of(float(v)))},
		{"row": "ShotCap", "stops": Array(ShotCap.STOPS), "start": ShotCap.default_cap(), "field": "shot_cap", "key": &"projectile_cap",
			"text": func(v: Variant) -> String: return "Max shots: %d" % int(v), "bar": func(v: Variant) -> float: return float(ShotCap.index_of(int(v)))},
		{"row": "TaillessMotes", "stops": Array(TaillessMotes.STOPS), "start": TaillessMotes.DEFAULT, "field": "tailless_motes", "key": &"tailless_motes",
			"text": func(v: Variant) -> String: return "Tailless motes: %d" % int(v), "bar": func(v: Variant) -> float: return float(TaillessMotes.index_of(int(v)))},
		{"row": "AmbienceVolume", "stops": volumes, "start": AmbienceVolume.DEFAULT, "field": "ambience_volume", "key": &"ambience_volume",
			"text": func(v: Variant) -> String: return "Ambience volume: %d%%" % int(v), "bar": func(v: Variant) -> float: return float(v)},
	]


func _saved_sliders() -> Array[Dictionary]:
	return _sliders().filter(func(slider: Dictionary) -> bool: return slider["key"] != &"")


func _index_of(slider: Dictionary, value: Variant) -> int:
	var stops: Array = slider["stops"]
	for at in stops.size():
		if _same(stops[at], value):
			return at
	return -1


## The move that steps `slider` from its default to a stop next to it: right, or left at the top.
func _away(slider: Dictionary) -> StringName:
	return &"move_right" if _index_of(slider, slider["start"]) < (slider["stops"] as Array).size() - 1 else &"move_left"


## The stop `_away` steps `slider` to.
func _next_to_start(slider: Dictionary) -> Variant:
	var at: int = _index_of(slider, slider["start"])
	return slider["stops"][at + 1 if _away(slider) == &"move_right" else at - 1]


## A fresh menu (on a fresh save) on the Settings page with the focus on `slider`'s row.
func _on_slider(slider: Dictionary) -> Button:
	DirAccess.remove_absolute(SAVE_PATH)
	_settings()
	_reach(0, slider["row"])
	var row: Button = _menu().button(slider["row"])
	_focus.focus(0, row)
	return row


## `slider` moved `times` times by `move`.
func _move(slider: Dictionary, move: StringName, times: int = 1) -> void:
	for i in times:
		_do(0, move)


func _heard_of(slider: Dictionary) -> Array:
	return _heard[slider["row"]]


func _value_of(slider: Dictionary) -> Variant:
	return _menu().get(slider["field"])


func test_no_slider_sends_anything_at_its_default() -> void:
	for slider in _sliders():
		_setup(1)
		check(_heard_of(slider).is_empty(), "%s: nothing is sent at the default" % slider["row"])


func test_every_slider_shows_its_default_in_words_and_on_the_bar() -> void:
	for slider in _sliders():
		var row: Button = _on_slider(slider)
		var bar: HSlider = row.get_node("Bar") as HSlider
		check(row.text.ends_with((slider["text"] as Callable).call(slider["start"])), "%s: the default in words: %s" % [slider["row"], row.text])
		check(is_equal_approx(bar.value, (slider["bar"] as Callable).call(slider["start"])), "%s: the default on the bar: %s" % [slider["row"], bar.value])


func test_a_slider_step_asks_for_the_next_stop() -> void:
	for slider in _sliders():
		_on_slider(slider)
		_move(slider, _away(slider))
		check(_heard_of(slider).size() == 1 and _same(_heard_of(slider)[0], _next_to_start(slider)), "%s: a step asks for %s, got %s" % [slider["row"], _next_to_start(slider), _heard_of(slider)])


func test_a_slider_step_shows_the_new_stop() -> void:
	for slider in _sliders():
		var row: Button = _on_slider(slider)
		_move(slider, _away(slider))
		var bar: HSlider = row.get_node("Bar") as HSlider
		check(row.text.ends_with((slider["text"] as Callable).call(_next_to_start(slider))), "%s: the new stop in words: %s" % [slider["row"], row.text])
		check(is_equal_approx(bar.value, (slider["bar"] as Callable).call(_next_to_start(slider))), "%s: the new stop on the bar: %s" % [slider["row"], bar.value])


func test_the_focus_stays_on_a_slider_after_a_step() -> void:
	for slider in _sliders():
		var row: Button = _on_slider(slider)
		_move(slider, _away(slider))
		check(_focus.focused(0) == row, "%s: the focus stays on the slider" % slider["row"])
		check_equal(_menu().page, _menu().page_of(row), "%s: on its page" % slider["row"])


func test_left_steps_a_slider_down_to_its_bottom() -> void:
	for slider in _sliders():
		_on_slider(slider)
		_move(slider, &"move_left", (slider["stops"] as Array).size() + 1)
		var bottom: Variant = slider["stops"][0]
		check(_same(_value_of(slider), bottom), "%s: it stops at the bottom, at %s" % [slider["row"], _value_of(slider)])
		check(_heard_of(slider).is_empty() or _same(_heard_of(slider).back(), bottom), "%s: the bottom is the last sent, got %s" % [slider["row"], _heard_of(slider)])


func test_right_steps_a_slider_up_to_its_top() -> void:
	for slider in _sliders():
		_on_slider(slider)
		_move(slider, &"move_right", (slider["stops"] as Array).size() + 1)
		var top: Variant = (slider["stops"] as Array).back()
		check(_same(_value_of(slider), top), "%s: it stops at the top, at %s" % [slider["row"], _value_of(slider)])
		check(_heard_of(slider).is_empty() or _same(_heard_of(slider).back(), top), "%s: the top is the last sent, got %s" % [slider["row"], _heard_of(slider)])


func test_past_a_sliders_end_nothing_is_sent() -> void:
	for slider in _sliders():
		for move: StringName in [&"move_left", &"move_right"]:
			_on_slider(slider)
			_move(slider, move, (slider["stops"] as Array).size())
			var sent: int = _heard_of(slider).size()
			_move(slider, move)
			check_equal(_heard_of(slider).size(), sent, "%s: past the end of %s nothing is sent" % [slider["row"], move])


func test_accept_steps_a_slider_up() -> void:
	for slider in _sliders():
		_on_slider(slider)
		_move(slider, &"move_left", (slider["stops"] as Array).size())
		_press(0, slider["row"])
		check(_same(_value_of(slider), slider["stops"][1]), "%s: accept steps up, to %s" % [slider["row"], _value_of(slider)])
		check(_same(_heard_of(slider).back(), slider["stops"][1]), "%s: and sends it, got %s" % [slider["row"], _heard_of(slider)])


func test_accept_at_a_sliders_top_wraps_to_the_bottom() -> void:
	for slider in _sliders():
		_on_slider(slider)
		_menu().set(slider["field"], (slider["stops"] as Array).back())
		_press(0, slider["row"])
		check(_same(_value_of(slider), slider["stops"][0]), "%s: accept at the top wraps to the bottom, at %s" % [slider["row"], _value_of(slider)])


func test_down_leaves_a_slider() -> void:
	var slider: Dictionary = _sliders()[0]
	_on_slider(slider)
	_do(0, &"move_down")
	check(_focus.focused(0) == _menu().button("MoteCap"), "down leaves the Effect slots slider for the row below")


func test_the_save_remembers_a_slider_step() -> void:
	for slider in _saved_sliders():
		_on_slider(slider)
		_move(slider, _away(slider))
		var saved: Variant = SaveFile.new(SAVE_PATH).get_setting(slider["key"], null)
		check(_same(saved, _next_to_start(slider)), "%s: the save remembers it, got %s" % [slider["row"], saved])


func test_a_later_menu_starts_with_a_saved_slider_stop() -> void:
	for slider in _saved_sliders():
		_on_slider(slider)
		_move(slider, _away(slider))
		_setup(1)
		check(_same(_value_of(slider), _next_to_start(slider)), "%s: a later menu starts with the saved stop, at %s" % [slider["row"], _value_of(slider)])


func test_a_later_menu_tells_them_a_saved_slider_stop_when_the_hud_binds() -> void:
	for slider in _saved_sliders():
		_on_slider(slider)
		_move(slider, _away(slider))
		_setup(1)
		check(_heard_of(slider).size() == 1 and _same(_heard_of(slider)[0], _next_to_start(slider)), "%s: told once when the Hud binds, got %s" % [slider["row"], _heard_of(slider)])


func test_the_platforms_particle_cap_is_a_stop_above_minimal() -> void:
	var at: int = MoteCap.index_of(MoteCap.default_cap())
	check(MoteCap.STOPS[at] == MoteCap.default_cap() and at > 0, "the platform's cap is a stop above Minimal")


func test_the_platforms_shot_cap_is_a_stop() -> void:
	check_equal(ShotCap.STOPS[ShotCap.index_of(ShotCap.default_cap())], ShotCap.default_cap(), "the platform's cap is a stop")


func test_a_max_shots_step_is_asked_for_in_the_run_by_the_seat_that_opened_the_menu() -> void:
	var slider: Dictionary = _sliders()[3]
	_on_slider(slider)
	_move(slider, &"move_left")
	var below: int = ShotCap.STOPS[ShotCap.index_of(ShotCap.default_cap()) - 1]
	check(_cap_requests == [[0, below]], "asked for in the run, as the seat that opened the menu, got %s" % [_cap_requests])


func test_a_particle_cap_saved_as_off_loads_as_minimal() -> void:
	# A cap saved as Off before S3 (0).
	SaveFile.new(SAVE_PATH).set_setting(&"mote_cap", 0)
	_setup(1)
	check(_menu().mote_cap == MoteCap.STOPS[0], "a saved Off loads as Minimal, at %d" % _menu().mote_cap)
	check(not (_heard["MoteCap"] as Array).is_empty() and (_heard["MoteCap"] as Array).back() == MoteCap.STOPS[0], "and feel is told Minimal, got %s" % [_heard["MoteCap"]])


# --- The builder from play ---------------------------------------------------------------------


func test_b_opens_the_builder_in_play() -> void:
	_setup(2)
	_do(1, &"back")
	check(_hud.get_radial(1).is_open(), "B opens the builder in play")


func test_b_opens_only_the_pressers_builder() -> void:
	_setup(2)
	_do(1, &"back")
	check(not _hud.get_radial(0).is_open(), "only the presser's")


func test_the_builder_never_pauses() -> void:
	_setup(2)
	_do(1, &"back")
	check(not paused and not _stops, "the builder never pauses")


func test_b_closes_the_builder_again() -> void:
	_setup(2)
	_do(1, &"back")
	_do(1, &"back")
	check(not _hud.get_radial(1).is_open(), "B closes it again")


func test_a_builder_closed_with_b_stays_closed() -> void:
	_setup(2)
	_do(1, &"back")
	_do(1, &"back")
	_frame()
	check(not _hud.get_radial(1).is_open(), "and it stays closed")


func test_no_builder_outside_a_room() -> void:
	_setup(2)
	_bus.room_cleared.emit(&"test_room")
	_bus.run_ended.emit(false)
	_do(0, &"back")
	check(not _hud.get_radial(0).is_open(), "no builder outside a room")


func test_start_closes_an_open_builder() -> void:
	_setup(1)
	_do(0, &"back")
	_do(0, &"pause")
	check(not _hud.get_radial(0).is_open(), "Start closes an open builder")


func test_start_on_an_open_builder_does_not_pause() -> void:
	_setup(1)
	_do(0, &"back")
	_do(0, &"pause")
	check(not _menu().is_open(), "rather than pausing on top of it")


# --- A on the hub's stone, by an item and on the altar -----------------------------------------
# The hub's stone (online-lobby L1): A (`accept`) sends `run_requested` for its player only while
# the stone is lit and that player has no menu open; never while the pause menu is open.


## Two seats; every `run_requested` heard.
func _stone_hud() -> Array[int]:
	_setup(2)
	var asked: Array[int] = []
	_bus.run_requested.connect(func(player: int) -> void: asked.append(player))
	return asked


func _light_stone() -> void:
	_bus.start_stone_changed.emit(2, 2, true)


func _put_out_stone() -> void:
	_bus.start_stone_changed.emit(0, 2, false)


func test_a_with_no_stone_lit_asks_nothing() -> void:
	var asked: Array[int] = _stone_hud()
	_do(1, &"accept")
	check(asked.is_empty(), "A with no stone lit asks nothing")


func test_a_on_the_lit_stone_asks_for_the_run_for_its_player() -> void:
	var asked: Array[int] = _stone_hud()
	_light_stone()
	_do(1, &"accept")
	check_equal(asked, [1] as Array[int], "A on the lit stone asks for the run, for its player")


func test_a_inside_a_builder_by_the_lit_stone_is_the_builders() -> void:
	var asked: Array[int] = _stone_hud()
	_light_stone()
	_do(0, &"back")
	_do(0, &"accept")
	check(asked.is_empty(), "A inside a builder is the builder's: %s" % [asked])


func test_a_while_paused_does_not_ask_for_the_run() -> void:
	var asked: Array[int] = _stone_hud()
	_light_stone()
	_open(1)
	_do(1, &"accept")
	check(asked.is_empty(), "A while paused asks nothing: %s" % [asked])


func test_a_once_the_stone_is_out_asks_nothing() -> void:
	var asked: Array[int] = _stone_hud()
	_light_stone()
	_bus.start_stone_changed.emit(1, 2, false)
	_do(1, &"accept")
	check(asked.is_empty(), "A once the stone is out asks nothing: %s" % [asked])


## The hub's altar (online-lobby L2): A (`accept`) sends `online_open_requested` for a player
## whose wizard stands on it (`altar_changed`), with no menu open; the lit stone's A comes first.
## Two seats, seat 1 on the altar when `on_altar`; every `online_open_requested` and
## `run_requested` heard, as [asked, runs].
func _altar_hud(on_altar: bool = true) -> Array:
	_setup(2)
	var asked: Array[int] = []
	var runs: Array[int] = []
	_bus.online_open_requested.connect(func(player: int) -> void: asked.append(player))
	_bus.run_requested.connect(func(player: int) -> void: runs.append(player))
	if on_altar:
		_bus.altar_changed.emit(0b0010)
	return [asked, runs]


func test_a_away_from_the_altar_asks_nothing() -> void:
	var heard: Array = _altar_hud(false)
	_do(1, &"accept")
	check((heard[0] as Array).is_empty(), "A away from the altar asks nothing")


func test_a_by_a_player_not_on_the_altar_asks_nothing() -> void:
	var heard: Array = _altar_hud()
	_do(0, &"accept")
	check((heard[0] as Array).is_empty(), "A by a player who is not on the altar asks nothing")


func test_a_on_the_altar_asks_to_open_the_room_for_its_player() -> void:
	var heard: Array = _altar_hud()
	_do(1, &"accept")
	check(heard[0] == [1], "A on the altar asks to open the room, for its player: %s" % [heard[0]])


func test_a_inside_a_builder_on_the_altar_is_the_builders() -> void:
	var heard: Array = _altar_hud()
	_do(1, &"back")
	_do(1, &"accept")
	check((heard[0] as Array).is_empty(), "A inside a builder is the builder's: %s" % [heard[0]])


func test_on_the_lit_stone_a_starts_the_run_not_the_room() -> void:
	var heard: Array = _altar_hud()
	_light_stone()
	_do(1, &"accept")
	check((heard[0] as Array).is_empty() and heard[1] == [1], "on the lit stone A starts the run, not the room: %s %s" % [heard[0], heard[1]])


func test_a_once_off_the_altar_asks_nothing() -> void:
	var heard: Array = _altar_hud()
	_bus.altar_changed.emit(0)
	_do(1, &"accept")
	check((heard[0] as Array).is_empty(), "A once off the altar asks nothing: %s" % [heard[0]])


## Items I6: A (`take`; never `accept` alone, Space on the keyboard, which casts) with an item in
## reach (`item_near_changed`) sends `item_take_requested` for its player and that item, with no
## menu open; the lit stone's A comes first, the altar's after. The hint shows over the item while
## it is in reach, hides while its player has a menu open, and shakes red on `item_refused`.
## Two seats, seat 1 on the altar with item 7 (a staff) in reach; every `item_take_requested`,
## `run_requested` and `online_open_requested` heard, as [takes, runs, rooms].
func _item_hud() -> Array:
	_setup(2)
	var takes: Array = []
	var runs: Array[int] = []
	var rooms: Array[int] = []
	_bus.item_take_requested.connect(func(player: int, item: int) -> void: takes.append([player, item]))
	_bus.run_requested.connect(func(player: int) -> void: runs.append(player))
	_bus.online_open_requested.connect(func(player: int) -> void: rooms.append(player))
	_bus.altar_changed.emit(0b0010)
	_bus.item_near_changed.emit(1, 7, Vector2(40, 40), {"kind": &"staff", "id": &"star", "name": "Wild star", "slots": 4, "cooldown": 0.15, "max_mana": 100.0, "cards": [&"bolt"]})
	_hud.step_hints(0.016)
	return [takes, runs, rooms]


func _hint() -> Control:
	return _hud.get_item_hints().call("hint_of", 1) as Control


func test_the_item_hint_shows_over_the_item() -> void:
	_item_hud()
	check(_hint().visible, "the hint shows over the item")


func test_the_item_hint_names_the_item() -> void:
	_item_hud()
	check_equal(String(_hint().call("title")), "Take Wild star", "it names the item")


func test_the_item_hint_shows_a_staffs_numbers() -> void:
	_item_hud()
	check(String(_hint().call("line")).begins_with("4 slots"), "a staff's numbers: %s" % _hint().call("line"))


func test_accept_alone_takes_no_item() -> void:
	var heard: Array = _item_hud()
	_bus.altar_changed.emit(0)
	_do(1, &"accept")
	check((heard[0] as Array).is_empty(), "accept alone (Space on the keyboard, which casts) takes nothing: %s" % [heard[0]])


func test_a_takes_the_item_not_the_altars_room() -> void:
	var heard: Array = _item_hud()
	_tap_a(1)
	_frame()
	check(heard[0] == [[1, 7]] and (heard[2] as Array).is_empty(), "A (take) takes the item, not the altar's room: %s %s" % [heard[0], heard[2]])


func test_a_refused_take_shakes_the_hint_red() -> void:
	_item_hud()
	_bus.item_refused.emit(1, 7)
	check(bool(_hint().call("is_refused")), "a refused take shakes it red")


func test_the_refused_shake_lasts_a_moment() -> void:
	_item_hud()
	_bus.item_refused.emit(1, 7)
	_hud.step_hints(1.0)
	check(not bool(_hint().call("is_refused")), "for a moment")


func test_on_the_lit_stone_a_starts_the_run_not_the_take() -> void:
	var heard: Array = _item_hud()
	_light_stone()
	_tap_a(1)
	_frame()
	check((heard[0] as Array).is_empty() and heard[1] == [1], "on the lit stone A starts the run: %s %s" % [heard[0], heard[1]])


func test_the_item_hint_hides_while_its_players_builder_is_open() -> void:
	_item_hud()
	_do(1, &"back")
	_hud.step_hints(0.016)
	check(not _hint().visible, "hidden while its player's builder is open")


func test_a_inside_the_builder_takes_no_item() -> void:
	var heard: Array = _item_hud()
	_do(1, &"back")
	_tap_a(1)
	_frame()
	check((heard[0] as Array).is_empty(), "A inside the builder is the builder's: %s" % [heard[0]])


func test_the_item_hint_hides_with_nothing_in_reach() -> void:
	_item_hud()
	_bus.item_near_changed.emit(1, -1, Vector2.ZERO, {})
	_hud.step_hints(0.016)
	check(not _hint().visible, "hidden with nothing in reach")


func test_with_nothing_in_reach_a_on_the_altar_opens_the_room() -> void:
	var heard: Array = _item_hud()
	_bus.item_near_changed.emit(1, -1, Vector2.ZERO, {})
	_hud.step_hints(0.016)
	_tap_a(1)
	_frame()
	check((heard[0] as Array).is_empty() and heard[2] == [1], "then A on the altar opens the room: %s %s" % [heard[0], heard[2]])


# --- Main menu and Leave game ------------------------------------------------------------------


## "Main menu" (online lobby: a machine whose host left joins another room from the menu): the
## menu closes and lets the game go first, then `main_menu_requested` asks this machine to leave,
## and the HUD itself shows the main menu again with no panel or menu over it. Two seats, seat 1
## pressed it; what the bus said in order.
func _main_menu_pressed() -> Array[String]:
	_setup(2)
	var heard: Array[String] = []
	_bus.pause_requested.connect(func(player: int, on: int) -> void: heard.append("pause %d %d" % [player, on]))
	# Heard before the HUD's own handler (which closes every menu too), so the order is the menu's.
	var hud_heard := Callable(_hud, &"_on_main_menu_requested")
	_bus.main_menu_requested.disconnect(hud_heard)
	_bus.main_menu_requested.connect(func(player: int) -> void: heard.append("menu %d" % player))
	_bus.main_menu_requested.connect(hud_heard)
	_open(1)
	heard.clear()
	_press(1, "MainMenu")
	return heard


func test_main_menu_closes_the_pause_menu() -> void:
	_main_menu_pressed()
	check(not _menu().is_open() and not _stops, "Main menu closes the menu and lets the game go")


func test_main_menu_lets_the_game_go_before_this_machine_leaves() -> void:
	# First: while a replay file plays the menu's closing unpauses the tree itself, which it no
	# longer does once the replay has ended on the way out.
	check_equal(_main_menu_pressed(), ["pause 1 0", "menu 1"] as Array[String], "first the game is let go, then this machine leaves")


func test_main_menu_shows_the_main_menu_as_the_current_scene() -> void:
	_main_menu_pressed()
	var shown: Node = current_scene
	check(shown != null and shown.name == MENU_STAND_IN and shown.get_parent() == root, "the main menu is the current scene")


func test_main_menu_leaves_no_panel_over_it() -> void:
	_main_menu_pressed()
	check(not _hud.get_panel(0).visible and not _hud.get_panel(1).visible, "no panel is left over it")


## "Leave game" (items I2, in place of the `leave` action): the menu closes and lets the game go
## first, then `seat_leave_requested` for the seat that opened it, whose device the input layer lets
## go (`device_left`: the seat's LEAVE in its next frame); the other seat plays on. Two seats, seat
## 1 pressed it; what the bus said in order.
func _left_game() -> Array[String]:
	_setup(2)
	var heard: Array[String] = []
	_bus.pause_requested.connect(func(player: int, on: int) -> void: heard.append("pause %d %d" % [player, on]))
	# Heard before the input layer, so the order is the menu's.
	_bus.seat_leave_requested.connect(func(player: int) -> void: heard.append("leave %d" % player))
	# The input layer hears the request once it is in the tree, as the autoload is.
	root.add_child(_input)
	await process_frame
	_bus.device_left.connect(func(player: int, _device: int) -> void: heard.append("gone %d" % player))
	_open(1)
	heard.clear()
	_press(1, "LeaveGame")
	return heard


func test_leave_game_closes_the_pause_menu() -> void:
	await _left_game()
	check(not _menu().is_open() and not _stops, "Leave game closes the menu and lets the game go")


func test_leave_game_lets_the_game_go_before_the_seat_leaves() -> void:
	check_equal(await _left_game(), ["pause 1 0", "leave 1", "gone 1"] as Array[String], "first the game is let go, then the seat leaves")


func test_leave_game_lets_the_seat_that_opened_the_menu_go() -> void:
	await _left_game()
	check(not _input.is_joined(1), "the seat that opened the menu is gone")


func test_leave_game_leaves_the_other_seat_playing() -> void:
	await _left_game()
	check(_input.is_joined(0), "the other seat plays on")


# --- A seat waiting for its gamepad ------------------------------------------------------------
# The owner, 2026-11-13: while the game waits for a seat's unplugged gamepad, the HUD says whose
# controller is gone (the pad line, from co-op's `pad_wait_changed`), the waiting seat's own pause
# menu closes, and the menu another player opens lets the waiting seat leave.


## Seat 0 on a virtual device, seat 1 on a real gamepad (device 3), the input layer in the tree.
func _pad_seats() -> void:
	_setup(1)
	root.add_child(_input)
	await process_frame
	var join := InputEventJoypadButton.new()
	join.device = 3
	join.button_index = JOY_BUTTON_A
	join.pressed = true
	_input.handle_event(join)
	_bus.player_joined.emit(1)
	check_equal(_input.player_of(3), 1, "the gamepad sits on seat 1")


## `_pad_seats` with seat 1's pause menu open, then its gamepad gone and co-op saying seat 1 waits.
func _seat_one_waits() -> void:
	await _pad_seats()
	var start := InputEventJoypadButton.new()
	start.device = 3
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	_input.handle_event(start)
	_frame()
	check_equal(_menu().owner_player, 1, "seat 1 opened the pause menu")
	_input._on_joy_connection_changed(3, false)
	# Co-op's part, done here: the waiting seats said.
	_bus.pad_wait_changed.emit(1 << 1)


## `_seat_one_waits` with seat 0's menu open.
func _other_menu_while_seat_one_waits() -> void:
	await _seat_one_waits()
	_open(0)


func test_no_pad_line_while_every_seat_has_its_device() -> void:
	await _pad_seats()
	check(not _hud.get_pad_line().visible, "no line while every seat has its device")


func test_a_waiting_seats_own_menu_closes() -> void:
	await _seat_one_waits()
	check(not _menu().is_open(), "the waiting seat's menu closes: it cannot work it")


func test_the_pad_line_names_the_waiting_seat() -> void:
	await _seat_one_waits()
	var line: Label = _hud.get_pad_line()
	check(line.visible and line.text.contains("P2:") and not line.text.contains("P1:"), "the line names the seat: %s" % line.text)


func test_another_players_menu_offers_the_waiting_seats_leave() -> void:
	await _other_menu_while_seat_one_waits()
	check(_menu().owner_player == 0 and _names().has("LeaveWaiting"), "the menu offers the waiting seat's leave: %s" % [_names()])
	check(_text_of("LeaveWaiting").contains("P2"), "naming the seat: %s" % _text_of("LeaveWaiting"))


func test_leave_waiting_lets_only_the_waiting_seat_go() -> void:
	await _other_menu_while_seat_one_waits()
	_press(0, "LeaveWaiting")
	check(not _input.is_joined(1) and _input.is_joined(0), "only the waiting seat left")


func test_the_menu_stays_open_after_leave_waiting() -> void:
	await _other_menu_while_seat_one_waits()
	_press(0, "LeaveWaiting")
	check(_menu().is_open(), "the menu stays open")


func test_the_leave_waiting_row_goes_at_once() -> void:
	await _other_menu_while_seat_one_waits()
	_press(0, "LeaveWaiting")
	check(not _names().has("LeaveWaiting"), "the row goes at once, so a second press asks nothing")


func test_with_nobody_waiting_no_line_and_no_row_show() -> void:
	await _other_menu_while_seat_one_waits()
	_bus.pad_wait_changed.emit(0)
	check(not _hud.get_pad_line().visible and not _names().has("LeaveWaiting"), "nobody waits: no line, no row: %s" % [_names()])


func test_another_machines_waiting_seat_is_named_not_offered() -> void:
	# A seat that waits on another machine is not this menu's to let go.
	await _other_menu_while_seat_one_waits()
	_bus.pad_wait_changed.emit(1 << 2)
	var line: Label = _hud.get_pad_line()
	check(line.visible and line.text.contains("P3"), "another machine's waiting seat is named: %s" % line.text)
	check(not _names().has("LeaveWaiting"), "not offered: %s" % [_names()])


func test_back_at_the_main_menu_no_pad_line_stays() -> void:
	await _seat_one_waits()
	_bus.main_menu_requested.emit(0)
	check(not _hud.get_pad_line().visible, "back at the main menu no line stays")


func test_a_waiting_seats_builder_closes() -> void:
	# As when a device left: the builder closes and frees the seat.
	_setup(2)
	_hud.get_radial(1).open_builder()
	check(_hud.get_radial(1).is_open(), "seat 1's builder is open")
	_bus.pad_wait_changed.emit(1 << 1)
	check(not _hud.get_radial(1).is_open() and not _input.is_captured(1), "a waiting seat's builder closes and frees it")
