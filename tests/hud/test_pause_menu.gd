extends SceneTree
## Tests for the pause menu (hud/menus/pause) and the buttons that open menus (owner,
## 2026-10-26): `pause` (Start) opens it for the player who pressed it and stops the game for
## everyone; only that player works it; Resume, `back` on the main page and `pause` again close
## it and the game goes on; Sandbox shows only in the sandbox and its page sends the sandbox
## actions and switches the builder and where the staff rows show the reload; Settings has Fullscreen, Effect slots, Particles, Floor marks, Max shots, Screen shake, Damage numbers and Show FPS; `back` (B)
## opens the builder in play, but not from inside a menu nor while paused; `pause` closes an
## open builder; the menu's stop is a reason of its own (online-ready N4). Input goes through the real input manager's virtual devices.
##
## godot --headless --path . --script res://tests/hud/test_pause_menu.gd

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
## Loaded when needed, not preloaded: this scene is also the "Hud" autoload (see test_radial_builder.gd).
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
const HudScript := preload("res://hud/panels/panels.gd")
const PauseMenuScript := preload("res://hud/menus/pause/pause_menu.gd")
const RadialScript := preload("res://hud/builder/radial_builder.gd")
const RingZoomScript := preload("res://hud/builder/rings/ring_zoom.gd")
const RingKindsScript := preload("res://hud/builder/rings/ring_kinds.gd")
const StaffRowScript := preload("res://hud/panels/player_panel/staff_row.gd")

var _failures: Array[String] = []
## Whether the menu's last `pause_requested` asked the game to stop.
var _stops: bool = false
var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _hud: HudScript
var _actions: Array[Array] = []
var _slots: Array[int] = []
## Every `screen_shake_changed` the bus sent, from before the Hud binds.
var _shakes: Array[bool] = []
## Every `damage_numbers_changed` the bus sent, from before the Hud binds.
var _numbers: Array[bool] = []
## Every `projectile_cap_changed` the bus sent, from before the Hud binds.
var _caps: Array[int] = []
## Every `shot_cap_requested` the bus sent, as [player, cap] (online-ready N11: the run's cap).
var _cap_requests: Array[Array] = []
## Every `mote_cap_changed` the bus sent, from before the Hud binds.
var _mote_caps: Array[int] = []
var _densities: Array[float] = []
## Every `floor_marks_changed` the bus sent, from before the Hud binds.
var _floor_marks: Array[bool] = []
var _lights: Array[bool] = []
var _tailless: Array[int] = []

const SAVE_PATH: String = "user://test_pause_menu_save.cfg"


func _initialize() -> void:
	await process_frame
	_test_start_opens_it_and_pauses_everyone()
	_test_only_the_opener_works_it()
	_test_resume_back_and_start_close_it()
	_test_sandbox_entry_and_actions()
	_test_the_settings_page()
	_test_the_fullscreen_switch()
	_test_the_effect_slots_slider()
	_test_the_screen_shake_switch()
	_test_the_damage_numbers_switch()
	_test_the_max_shots_slider()
	_test_the_particles_slider()
	_test_the_particle_amount_slider()
	_test_the_floor_marks_switch()
	_test_the_spell_light_switch()
	_test_the_tailless_motes_slider()
	_test_the_show_fps_switch()
	_test_the_sandbox_switches_the_builder()
	_test_the_sandbox_switches_the_reload()
	_test_the_enemy_arena()
	_test_b_opens_the_builder_in_play_only()
	_test_start_closes_the_builder()
	_test_a_on_the_lit_stone_starts_the_run()
	_test_a_on_the_altar_asks_to_open_the_room()
	_test_a_by_an_item_takes_it_after_the_stone_and_before_the_altar()
	_test_the_run_ending_closes_it()
	_test_main_menu_leaves_for_the_main_menu()
	await _test_leave_game_lets_the_seat_go()
	await _test_a_waiting_seat_is_named_and_can_be_let_go()
	_teardown()
	if _failures.is_empty():
		print("TEST OK: hud/menus pause menu")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _setup(count: int, sandbox: bool = false, save: SaveFile = null) -> void:
	_teardown()
	_bus = EventsScript.new()
	_input = InputManagerScript.new()
	_input.events = _bus
	_focus = UIFocusScript.new()
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	_bus.sandbox_action_requested.connect(func(player: int, action: StringName) -> void: _actions.append([player, action]))
	_bus.effect_slots_changed.connect(func(slots: int) -> void: _slots.append(slots))
	_bus.screen_shake_changed.connect(func(enabled: bool) -> void: _shakes.append(enabled))
	_bus.damage_numbers_changed.connect(func(on: bool) -> void: _numbers.append(on))
	_bus.projectile_cap_changed.connect(func(cap: int) -> void: _caps.append(cap))
	_bus.shot_cap_requested.connect(func(player: int, cap: int) -> void: _cap_requests.append([player, cap]))
	_bus.mote_cap_changed.connect(func(cap: int) -> void: _mote_caps.append(cap))
	_bus.mote_density_changed.connect(func(density: float) -> void: _densities.append(density))
	_bus.floor_marks_changed.connect(func(on: bool) -> void: _floor_marks.append(on))
	_bus.spell_light_changed.connect(func(on: bool) -> void: _lights.append(on))
	_bus.tailless_motes_changed.connect(func(pool: int) -> void: _tailless.append(pool))
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
	_hud.save = save if save != null else SaveFile.new(SAVE_PATH)
	root.add_child(_hud)
	for index in count:
		_bus.player_joined.emit(index)
	_bus.room_entered.emit(&"test_room")
	_bus.sandbox_changed.emit(sandbox)


func _teardown() -> void:
	paused = false
	_stops = false
	_actions.clear()
	_slots.clear()
	_shakes.clear()
	_numbers.clear()
	_caps.clear()
	_cap_requests.clear()
	_mote_caps.clear()
	_densities.clear()
	_floor_marks.clear()
	_lights.clear()
	_tailless.clear()
	for node: Node in [_hud, _focus, _input, _bus]:
		if node != null:
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


func _menu() -> PauseMenuScript:
	return _hud.get_pause_menu()


func _names() -> Array[String]:
	var names: Array[String] = []
	for shown: Button in _menu().shown_buttons():
		names.append(String(shown.name))
	return names


## Press `button_name` on the menu as `player`.
func _press(player: int, button_name: String) -> void:
	_focus.focus(player, _menu().button(button_name))
	_tap(player, &"accept")
	_frame()


# --- Tests ------------------------------------------------------------------

func _test_start_opens_it_and_pauses_everyone() -> void:
	_setup(2)
	_check(not _menu().visible and not _stops, "closed and running at the start")
	_tap(1, &"pause")
	_frame()
	_check(_menu().is_open() and _menu().visible, "Start opens the pause menu")
	_check(_menu().owner_player == 1, "for the player who pressed it")
	_check(_stops, "the game stops for everyone (the command pause_requested)")
	_check(_names() == ["Resume", "Settings", "LeaveGame", "MainMenu"], "the main page out of the sandbox, got %s" % [_names()])
	_check(_menu().button("Resume").text.begins_with("> "), "the focus is marked with text")


func _test_only_the_opener_works_it() -> void:
	_setup(2)
	_tap(0, &"pause")
	_frame()
	_tap(1, &"accept")
	_tap(1, &"pause")
	_frame()
	_check(_menu().is_open() and _menu().owner_player == 0, "another player's buttons do nothing to it")
	_tap(1, &"back")
	_frame()
	_check(not _hud.get_radial(1).is_open(), "nobody opens a builder while the game is paused")


func _test_resume_back_and_start_close_it() -> void:
	_setup(1)
	for way: StringName in [&"accept", &"back", &"pause"]:
		_tap(0, &"pause")
		_frame()
		_check(_menu().is_open() and _stops, "%s: open" % way)
		_tap(0, way)  # accept lands on Resume, the first button.
		_frame()
		_check(not _menu().is_open() and not _menu().visible, "%s closes the menu" % way)
		_check(not _stops, "%s: the game goes on" % way)
		_check(not _hud.get_radial(0).is_open(), "%s: closing with B does not open the builder" % way)


func _test_sandbox_entry_and_actions() -> void:
	_setup(2, true)
	_tap(1, &"pause")
	_frame()
	_check(_names() == ["Resume", "Sandbox", "Settings", "LeaveGame", "MainMenu"], "in the sandbox the main page has Sandbox, got %s" % [_names()])
	_press(1, "Sandbox")
	_check(_names() == ["ResetDummies", "ArenaEnemy", "ArenaCount", "ArenaSpawn", "ArenaClear", "AIView", "RingStyle", "PutStyle", "ReloadStyle", "SandboxBack"], "the sandbox page, got %s" % [_names()])
	_press(1, "ResetDummies")
	_press(1, "ArenaClear")
	_check(_actions == [[1, &"reset_dummies"], [1, &"clear_enemies"]], "the actions go out with the opener's index, got %s" % [_actions])
	_check(_menu().is_open() and _menu().page == PauseMenuScript.Page.SANDBOX, "the page stays for another press")
	_tap(1, &"back")
	_frame()
	_check(_menu().page == PauseMenuScript.Page.MAIN and _menu().is_open(), "B goes back to the main page")
	_bus.sandbox_changed.emit(false)
	_check(_names() == ["Resume", "Settings", "LeaveGame", "MainMenu"], "out of the sandbox the entry goes")


func _test_the_enemy_arena() -> void:
	_setup(1, true)
	var spawns: Array = []
	var views: Array[bool] = []
	_bus.sandbox_spawn_requested.connect(func(player: int, id: StringName, count: int) -> void: spawns.append([player, id, count]))
	_bus.ai_view_changed.connect(func(on: bool) -> void: views.append(on))
	_tap(0, &"pause")
	_frame()
	_press(0, "Sandbox")
	var menu: PauseMenuScript = _menu()
	_check(menu.arena_ids.size() >= 7, "every enemy of the registry is listed, got %s" % [menu.arena_ids])
	_check(menu.arena_names.has("Cinder Rod"), "by its name")
	var first: StringName = menu.arena_ids[0]
	_check(menu.button("ArenaEnemy").text.ends_with("Enemy: " + menu.arena_names[0]), "the first is picked")
	_press(0, "ArenaEnemy")
	_check(menu.arena_pick == 1, "accept picks the next")
	_press(0, "ArenaCount")
	_press(0, "ArenaCount")
	_check(menu.button("ArenaCount").text.ends_with("Count: 3"), "the count steps up")
	_press(0, "ArenaSpawn")
	_check(spawns == [[0, menu.arena_ids[1], 3]], "spawn asks for three of the picked enemy, got %s" % [spawns])
	_press(0, "ArenaClear")
	_check(_actions.has([0, &"clear_enemies"]), "clear asks flow to clear the enemies, got %s" % [_actions])
	_press(0, "AIView")
	_press(0, "AIView")
	_check(views == [true, false], "the AI view flips on and off, got %s" % [views])
	_check(first != &"", "an id")
	_check(menu.page == PauseMenuScript.Page.SANDBOX, "the page stays")


func _test_the_sandbox_switches_the_reload() -> void:
	_setup(2, true)
	var sent: Array[bool] = []
	_menu().reload_style_changed.connect(func(on_button: bool) -> void: sent.append(on_button))
	_tap(0, &"pause")
	_frame()
	_press(0, "Sandbox")
	_check(_menu().button("ReloadStyle").text.ends_with("Reload: Button"), "the reload is on the button by default")
	_check(_hud.get_panel(1).staff_row(0).style == StaffRowScript.Style.BUTTON, "and the rows draw it there")
	_press(0, "ReloadStyle")
	_check(_menu().button("ReloadStyle").text.ends_with("Reload: Next cast"), "it flips to the next cast")
	for player in 4:
		for staff in 4:
			_check(_hud.get_panel(player).staff_row(staff).style == StaffRowScript.Style.NEXT_CAST, "every row of every panel follows (P%d staff %d)" % [player + 1, staff + 1])
	_press(0, "ReloadStyle")
	_check(sent == [false, true], "each flip goes out, got %s" % [sent])
	_check(_hud.get_panel(0).staff_row(2).style == StaffRowScript.Style.BUTTON, "and back on the button")
	_check(_menu().page == PauseMenuScript.Page.SANDBOX, "the page stays")


func _test_the_sandbox_switches_the_builder() -> void:
	_setup(1, true)
	var options: Array = []
	_menu().builder_options_changed.connect(func(ring: int, push: bool) -> void: options.append([ring, push]))
	_tap(0, &"pause")
	_frame()
	_press(0, "Sandbox")
	_check(_menu().button("BuilderStyle") == null, "no switch to another builder: the list builder is gone")
	_check(_menu().button("PutStyle").text.ends_with("Full slot: Push right"), "a full slot pushes right by default")
	_press(0, "RingStyle")
	_press(0, "PutStyle")
	_check(options == [[1, true], [1, false]], "each flip goes out, got %s" % [options])
	_check(_hud.get_radial(0).layout == RadialScript.Layout.KIND, "the ring shows one kind at a time")
	_check(_hud.get_radial(0).put == RadialScript.Put.REPLACE, "a full slot is replaced")
	# The ring styles to try (owner, 2026-10-30), then round to the first again.
	var words: Array[String] = []
	var styles: Array = []
	for _step in 4:
		_press(0, "RingStyle")
		words.append(_menu().button("RingStyle").text.get_slice("Ring: ", 1))
		styles.append(_hud.get_radial(0).ring_picker.get_script() if _hud.get_radial(0).ring_picker != null else null)
	_check(words == ["Zoom", "Kinds: hold", "Kinds: depth", "Every card"], "the ring steps through the styles, got %s" % [words])
	_check(styles == [RingZoomScript, RingKindsScript, RingKindsScript, null], "and the radial gets each style")
	_check(_hud.get_radial(0).layout == RadialScript.Layout.ALL, "every card again")
	_check(_menu().page == PauseMenuScript.Page.SANDBOX, "the page stays")
	_tap(0, &"pause")
	_frame()
	_tap(0, &"back")
	_frame()
	_check(_hud.get_radial(0).is_open(), "B opens the radial builder")
	_tap(0, &"back")
	_frame()
	_check(not _hud.get_radial(0).is_open(), "B closes it again")
	_frame()
	_check(not _hud.get_radial(0).is_open(), "and it stays closed")
	_tap(0, &"back")
	_frame()
	_tap(0, &"pause")
	_frame()
	_check(not _hud.get_radial(0).is_open() and not _menu().is_open(), "Start closes it rather than pausing")


## Settings holds Fullscreen and Effect slots; the Gameplay page and its Friendly fire and Enemy
## fire rows are gone (actors G3c: every spell hits everything, always).
func _test_the_settings_page() -> void:
	_setup(1)
	_tap(0, &"pause")
	_frame()
	_press(0, "Settings")
	_check(_names() == ["Fullscreen", "EffectSlots", "MoteCap", "MoteDensity", "FloorMarks", "SpellLight", "TaillessMotes", "ShotCap", "ScreenShake", "DamageNumbers", "ShowFps", "SettingsBack"], "Settings, got %s" % [_names()])
	_check(_menu().button("FriendlyFire") == null and _menu().button("EnemyFire") == null, "no fire settings")
	_tap(0, &"back")
	_frame()
	_check(_menu().page == PauseMenuScript.Page.MAIN, "B goes up to the main page")


## Screen shake is on by default, flips on accept, tells feel, and is kept in the save: a menu
## bound to the same save later starts with it off and tells feel.
func _test_the_screen_shake_switch() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	_setup(1, false, SaveFile.new(SAVE_PATH))
	var sent: Array[bool] = _shakes
	_check(sent.is_empty(), "nothing is sent while shake is on")
	_tap(0, &"pause")
	_frame()
	_press(0, "Settings")
	_check(_menu().button("ScreenShake").text.ends_with("Screen shake: On"), "shake is on by default")
	_press(0, "ScreenShake")
	_check(_menu().button("ScreenShake").text.ends_with("Screen shake: Off"), "it flips off")
	_check(sent == [false], "and feel is told, got %s" % [sent])
	_check(SaveFile.new(SAVE_PATH).get_setting(&"screen_shake", true) == false, "the save remembers it")
	_press(0, "ScreenShake")
	_check(sent == [false, true] and SaveFile.new(SAVE_PATH).get_setting(&"screen_shake", false) == true, "and flips back on, saved")
	_press(0, "ScreenShake")
	_setup(1, false, SaveFile.new(SAVE_PATH))
	_check(not _menu().screen_shake, "a later menu starts with it off")
	_check(_shakes == [false], "and tells feel when the Hud binds, got %s" % [_shakes])
	_teardown()
	DirAccess.remove_absolute(SAVE_PATH)


## Damage numbers (props W5) are on by default and send nothing; accept flips them and tells feel,
## and the choice is saved: a menu bound to the same save later starts with them off and tells feel.
func _test_the_damage_numbers_switch() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	_setup(1, false, SaveFile.new(SAVE_PATH))
	_check(_numbers.is_empty(), "nothing is sent while the numbers are on")
	_tap(0, &"pause")
	_frame()
	_press(0, "Settings")
	_check(_menu().button("DamageNumbers").text.ends_with("Damage numbers: On"), "on by default")
	_press(0, "DamageNumbers")
	_check(_menu().button("DamageNumbers").text.ends_with("Damage numbers: Off"), "it flips off")
	_check(_numbers == [false], "and feel is told, got %s" % [_numbers])
	_check(SaveFile.new(SAVE_PATH).get_setting(&"damage_numbers", true) == false, "the save remembers it")
	_press(0, "DamageNumbers")
	_check(_numbers == [false, true] and SaveFile.new(SAVE_PATH).get_setting(&"damage_numbers", false) == true, "and flips back on, saved")
	_press(0, "DamageNumbers")
	_setup(1, false, SaveFile.new(SAVE_PATH))
	_check(not _menu().damage_numbers, "a later menu starts with them off")
	_check(_numbers == [false], "and tells feel when the Hud binds, got %s" % [_numbers])
	_teardown()
	DirAccess.remove_absolute(SAVE_PATH)


## Floor marks (spell spectacle P2a) starts at the platform's default and sends nothing; accept
## flips it and tells feel, and the choice is saved: a menu bound to the same save later starts
## with it and tells feel.
func _test_the_floor_marks_switch() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	_setup(1, false, SaveFile.new(SAVE_PATH))
	var start: bool = FloorMarks.default_on()
	var word: Callable = func(on: bool) -> String: return "Floor marks: %s" % ("On" if on else "Off")
	_check(_floor_marks.is_empty(), "nothing is sent at the platform's default")
	_tap(0, &"pause")
	_frame()
	_press(0, "Settings")
	_check(_menu().button("FloorMarks").text.ends_with(word.call(start)), "the platform's default at the start")
	_press(0, "FloorMarks")
	_check(_menu().button("FloorMarks").text.ends_with(word.call(not start)), "it flips")
	_check(_floor_marks == [not start], "and feel is told, got %s" % [_floor_marks])
	_check(SaveFile.new(SAVE_PATH).get_setting(&"floor_marks", start) == (not start), "the save remembers it")
	_setup(1, false, SaveFile.new(SAVE_PATH))
	_check(_menu().floor_marks == (not start), "a later menu starts with it")
	_check(_floor_marks == [not start], "and tells feel when the Hud binds, got %s" % [_floor_marks])


## Spell light (spell spectacle P3a) starts at the platform's default and sends nothing; accept
## flips it and tells feel, and the choice is saved: a menu bound to the same save later starts
## with it and tells feel.
func _test_the_spell_light_switch() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	_setup(1, false, SaveFile.new(SAVE_PATH))
	_check(_lights.is_empty(), "nothing is sent at the platform's default")
	_tap(0, &"pause")
	_frame()
	_press(0, "Settings")
	var start: bool = SpellLightSetting.default_on()
	var word: String = "On" if start else "Off"
	_check(_menu().button("SpellLight").text.ends_with("Spell light: %s" % word), "the default at the start")
	_press(0, "SpellLight")
	_check(_menu().spell_light == not start and _lights == [not start], "accept flips it and tells feel, got %s" % [_lights])
	_check(bool(SaveFile.new(SAVE_PATH).get_setting(&"spell_light", start)) == not start, "the save remembers it")
	_setup(1, false, SaveFile.new(SAVE_PATH))
	_check(_menu().spell_light == not start, "a later menu starts with the saved choice")
	_check(_lights == [not start], "and tells feel when the Hud binds, got %s" % [_lights])
	_teardown()
	DirAccess.remove_absolute(SAVE_PATH)


## Tailless motes (S5 step 4: a dev slider) starts at the default pool and sends nothing; left
## and right step through the stops and tell the manager and feel, accept steps up and wraps, and
## the choice is saved: a menu bound to the same save later starts with it and tells them.
func _test_the_tailless_motes_slider() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	_setup(1, false, SaveFile.new(SAVE_PATH))
	_check(_tailless.is_empty(), "nothing is sent at the default")
	_tap(0, &"pause")
	_frame()
	_press(0, "Settings")
	var row: Button = _menu().button("TaillessMotes")
	var bar: HSlider = row.get_node("Bar") as HSlider
	_check(row.text.ends_with("Tailless motes: 2048") and is_equal_approx(bar.value, 0.0), "2048 at the start, in words and on the bar")
	_focus.focus(0, row)
	_tap(0, &"move_right")
	_frame()
	_check(_menu().tailless_motes == 4096 and _tailless == [4096], "right asks for 4096, got %s" % [_tailless])
	_check(row.text.ends_with("Tailless motes: 4096") and is_equal_approx(bar.value, 1.0), "and shows it")
	_check(_focus.focused(0) == row, "the focus stays on the slider")
	_tap(0, &"move_right")
	_frame()
	_tap(0, &"move_right")
	_frame()
	_check(_menu().tailless_motes == 8192 and _tailless == [4096, 8192], "right stops at the top, got %s" % [_tailless])
	_check(int(SaveFile.new(SAVE_PATH).get_setting(&"tailless_motes", -1)) == 8192, "the save remembers it")
	_press(0, "TaillessMotes")
	_check(_menu().tailless_motes == 2048, "accept at the top wraps to the default")
	_press(0, "TaillessMotes")
	_check(_menu().tailless_motes == 4096, "accept steps up")
	_setup(1, false, SaveFile.new(SAVE_PATH))
	_check(_menu().tailless_motes == 4096 and _tailless == [4096], "a later menu starts with the saved pool and tells them, got %s" % [_tailless])
	_teardown()
	DirAccess.remove_absolute(SAVE_PATH)


## Particles (spell spectacle P1a) starts at the platform's cap and sends nothing; left and right
## step through Minimal, Low, Medium and High (no Off since S3) and tell feel, accept steps up and wraps, and the choice
## is saved: a menu bound to the same save later starts with it and tells feel.
func _test_the_particles_slider() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	_setup(1, false, SaveFile.new(SAVE_PATH))
	_check(_mote_caps.is_empty(), "nothing is sent at the platform's cap")
	_tap(0, &"pause")
	_frame()
	_press(0, "Settings")
	var row: Button = _menu().button("MoteCap")
	var bar: HSlider = row.get_node("Bar") as HSlider
	var at: int = MoteCap.index_of(MoteCap.default_cap())
	_check(MoteCap.STOPS[at] == MoteCap.default_cap() and at > 0, "the platform's cap is a stop above Minimal")
	_check(row.text.ends_with("Particles: %s" % MoteCap.WORDS[at]) and is_equal_approx(bar.value, float(at)), "the platform's cap at the start, in words and on the bar")
	_focus.focus(0, row)
	for i in MoteCap.STOPS.size():
		_tap(0, &"move_left")
		_frame()
	_check(_menu().mote_cap == MoteCap.STOPS[0] and _mote_caps.back() == MoteCap.STOPS[0], "left goes down to Minimal, got %s" % [_mote_caps])
	_check(row.text.ends_with("Particles: Minimal") and is_equal_approx(bar.value, 0.0), "and shows it")
	_check(_focus.focused(0) == row, "the focus stays on the slider")
	_check(int(SaveFile.new(SAVE_PATH).get_setting(&"mote_cap", -1)) == MoteCap.STOPS[0], "the save remembers it")
	var sent: int = _mote_caps.size()
	_tap(0, &"move_left")
	_frame()
	_check(_mote_caps.size() == sent, "past the end nothing is sent")
	_press(0, "MoteCap")
	_check(_menu().mote_cap == MoteCap.STOPS[1] and _mote_caps.back() == MoteCap.STOPS[1], "accept steps up")
	_menu().mote_cap = MoteCap.STOPS[-1]
	_press(0, "MoteCap")
	_check(_menu().mote_cap == MoteCap.STOPS[0], "accept at the top wraps to Minimal")
	_setup(1, false, SaveFile.new(SAVE_PATH))
	_check(_menu().mote_cap == MoteCap.STOPS[0], "a later menu starts with the saved cap")
	_check(_mote_caps == [MoteCap.STOPS[0]], "and tells feel when the Hud binds, got %s" % [_mote_caps])
	_teardown()
	# A cap saved as Off before S3 (0) loads as Minimal.
	var old: SaveFile = SaveFile.new(SAVE_PATH)
	old.set_setting(&"mote_cap", 0)
	_setup(1, false, SaveFile.new(SAVE_PATH))
	_check(_menu().mote_cap == MoteCap.STOPS[0] and _mote_caps.back() == MoteCap.STOPS[0], "a saved Off loads as Minimal, got %s" % [_mote_caps])
	_teardown()
	DirAccess.remove_absolute(SAVE_PATH)


## Particle amount (spell spectacle P1b) starts at Full and sends nothing; left and right step
## through None, Half, Full and Double and tell feel, accept steps up and wraps, and the choice is
## saved: a menu bound to the same save later starts with it and tells feel.
func _test_the_particle_amount_slider() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	_setup(1, false, SaveFile.new(SAVE_PATH))
	_check(_densities.is_empty(), "nothing is sent at the default")
	_tap(0, &"pause")
	_frame()
	_press(0, "Settings")
	var row: Button = _menu().button("MoteDensity")
	var bar: HSlider = row.get_node("Bar") as HSlider
	var at: int = MoteDensity.index_of(MoteDensity.DEFAULT)
	_check(row.text.ends_with("Particle amount: Full") and is_equal_approx(bar.value, float(at)), "Full at the start, in words and on the bar")
	_focus.focus(0, row)
	_tap(0, &"move_right")
	_frame()
	_check(is_equal_approx(_menu().mote_density, 2.0) and _densities == [2.0], "right asks for Double, got %s" % [_densities])
	_check(row.text.ends_with("Particle amount: Double") and is_equal_approx(bar.value, float(at + 1)), "and shows it")
	_check(_focus.focused(0) == row, "the focus stays on the slider")
	for i in MoteDensity.STOPS.size():
		_tap(0, &"move_left")
		_frame()
	_check(_menu().mote_density == 0.0 and _densities.back() == 0.0, "left goes down to None")
	_check(is_equal_approx(float(SaveFile.new(SAVE_PATH).get_setting(&"mote_density", -1.0)), 0.0), "the save remembers it")
	_press(0, "MoteDensity")
	_check(is_equal_approx(_menu().mote_density, 0.5), "accept steps up")
	_menu().mote_density = MoteDensity.STOPS[-1]
	_press(0, "MoteDensity")
	_check(_menu().mote_density == 0.0, "accept at the top wraps to None")
	_setup(1, false, SaveFile.new(SAVE_PATH))
	_check(_menu().mote_density == 0.0 and _densities == [0.0], "a later menu starts with the saved amount and tells feel, got %s" % [_densities])
	_teardown()
	DirAccess.remove_absolute(SAVE_PATH)


## Max shots starts at the platform's cap and sends nothing; left and right step through the
## stops and tell the projectile manager, accept steps up and wraps, and the choice is saved: a
## menu bound to the same save later starts with it and tells the manager.
func _test_the_max_shots_slider() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	_setup(1, false, SaveFile.new(SAVE_PATH))
	_check(_caps.is_empty(), "nothing is sent at the platform's cap")
	_tap(0, &"pause")
	_frame()
	_press(0, "Settings")
	var row: Button = _menu().button("ShotCap")
	var bar: HSlider = row.get_node("Bar") as HSlider
	var start: int = ShotCap.default_cap()
	var at: int = ShotCap.index_of(start)
	_check(ShotCap.STOPS[at] == start, "the platform's cap is a stop")
	_check(row.text.ends_with("Max shots: %d" % start) and is_equal_approx(bar.value, float(at)), "the platform's cap at the start, in words and on the bar")
	_focus.focus(0, row)
	_tap(0, &"move_left")
	_frame()
	_check(_caps == [ShotCap.STOPS[at - 1]], "left asks for the stop below, got %s" % [_caps])
	_check(_cap_requests == [[0, ShotCap.STOPS[at - 1]]], "and asks for it in the run, as the seat that opened the menu, got %s" % [_cap_requests])
	_check(row.text.ends_with("Max shots: %d" % ShotCap.STOPS[at - 1]) and is_equal_approx(bar.value, float(at - 1)), "and shows it")
	_check(_focus.focused(0) == row, "the focus stays on the slider")
	_check(int(SaveFile.new(SAVE_PATH).get_setting(&"projectile_cap", 0)) == ShotCap.STOPS[at - 1], "the save remembers it")
	for i in ShotCap.STOPS.size():
		_tap(0, &"move_right")
		_frame()
	_check(_menu().shot_cap == ShotCap.STOPS[-1] and _caps.back() == ShotCap.STOPS[-1], "it stops at the top")
	var sent: int = _caps.size()
	_tap(0, &"move_right")
	_frame()
	_check(_caps.size() == sent, "past the end nothing is sent")
	_press(0, "ShotCap")
	_check(_menu().shot_cap == ShotCap.STOPS[0], "accept at the top wraps to the bottom")
	_press(0, "ShotCap")
	_check(_menu().shot_cap == ShotCap.STOPS[1], "accept steps up")
	_setup(1, false, SaveFile.new(SAVE_PATH))
	_check(_menu().shot_cap == ShotCap.STOPS[1], "a later menu starts with the saved cap")
	_check(_caps == [ShotCap.STOPS[1]], "and tells the manager when the Hud binds, got %s" % [_caps])
	_teardown()
	DirAccess.remove_absolute(SAVE_PATH)


## Show FPS is off by default (the readout hidden), flips on accept, shows the readout, and is
## kept in the save: a Hud bound to the same save later shows it from the start.
func _test_the_show_fps_switch() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	_setup(1, false, SaveFile.new(SAVE_PATH))
	var fps: Label = _hud.get_fps_counter()
	_check(fps != null and not fps.visible, "the readout is hidden by default")
	_tap(0, &"pause")
	_frame()
	_press(0, "Settings")
	_check(_menu().button("ShowFps").text.ends_with("Show FPS: Off"), "the switch says Off")
	_press(0, "ShowFps")
	_check(_menu().button("ShowFps").text.ends_with("Show FPS: On") and fps.visible, "it flips on and shows the readout")
	_check(fps.text.ends_with(" FPS"), "the readout reads 'N FPS', got '%s'" % fps.text)
	_check(bool(SaveFile.new(SAVE_PATH).get_setting(&"show_fps", false)), "the save remembers it")
	_setup(1, false, SaveFile.new(SAVE_PATH))
	_check(_menu().show_fps and _hud.get_fps_counter().visible, "a later Hud shows it from the start")
	_tap(0, &"pause")
	_frame()
	_press(0, "Settings")
	_press(0, "ShowFps")
	_check(not _hud.get_fps_counter().visible and not bool(SaveFile.new(SAVE_PATH).get_setting(&"show_fps", true)), "and flips back off, saved")
	_teardown()
	DirAccess.remove_absolute(SAVE_PATH)


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


func _test_the_fullscreen_switch() -> void:
	_setup(1)
	var display := FakeDisplay.new()
	_menu().display = display
	_tap(0, &"pause")
	_frame()
	_press(0, "Settings")
	_check(_menu().button("Fullscreen").text.ends_with("Fullscreen: Off"), "off in a window")
	_press(0, "Fullscreen")
	_check(display.toggles == 1 and display.on, "it asks Display to fill the screen")
	_check(_menu().button("Fullscreen").text.ends_with("Fullscreen: On"), "and shows On")
	_check(_menu().page == PauseMenuScript.Page.SETTINGS, "it stays on the page")
	# The browser leaves fullscreen on its own (Escape): the word follows the window when shown again.
	display.on = false
	_tap(0, &"back")
	_frame()
	_press(0, "Settings")
	_check(_menu().button("Fullscreen").text.ends_with("Fullscreen: Off"), "the window's own state shows")
	display.free()


## Settings > Effect slots is a slider: left and right move it a step and keep the focus on it,
## accept steps up and wraps, up and down leave it; each move tells feel, the ends do not move.
func _test_the_effect_slots_slider() -> void:
	_setup(1)
	_tap(0, &"pause")
	_frame()
	_press(0, "Settings")
	var row: Button = _menu().button("EffectSlots")
	var bar: HSlider = row.get_node("Bar") as HSlider
	_check(row.text.ends_with("Effect slots: 256") and is_equal_approx(bar.value, 256.0), "256 at the start, shown in words and on the bar")
	_focus.focus(0, row)
	_tap(0, &"move_right")
	_frame()
	_check(_slots == [320], "right asks for a step more, got %s" % [_slots])
	_check(row.text.ends_with("Effect slots: 320") and is_equal_approx(bar.value, 320.0), "and shows it")
	_check(_focus.focused(0) == row, "the focus stays on the slider")
	_tap(0, &"move_left")
	_frame()
	_tap(0, &"move_left")
	_frame()
	_check(_slots == [320, 256, 192], "left steps down, got %s" % [_slots])
	for i in 10:
		_tap(0, &"move_left")
		_frame()
	_check(_menu().effect_slots == EffectSlots.MIN and _slots.back() == EffectSlots.MIN, "it stops at the bottom")
	var sent: int = _slots.size()
	_tap(0, &"move_left")
	_frame()
	_check(_slots.size() == sent, "past the end nothing is sent")
	_menu().effect_slots = EffectSlots.MAX
	_press(0, "EffectSlots")
	_check(_menu().effect_slots == EffectSlots.MIN, "accept at the top wraps to the bottom")
	_press(0, "EffectSlots")
	_check(_menu().effect_slots == EffectSlots.MIN + EffectSlots.STEP, "accept steps up")
	_focus.focus(0, row)
	_tap(0, &"move_down")
	_frame()
	_check(_focus.focused(0) == _menu().button("MoteCap"), "down leaves the slider")
	_check(_menu().page == PauseMenuScript.Page.SETTINGS, "all on the Settings page")


func _test_b_opens_the_builder_in_play_only() -> void:
	_setup(2)
	_tap(1, &"back")
	_frame()
	_check(_hud.get_radial(1).is_open(), "B opens the builder in play")
	_check(not _hud.get_radial(0).is_open(), "only the presser's")
	_check(not paused, "the builder never pauses")
	_tap(1, &"back")
	_frame()
	_check(not _hud.get_radial(1).is_open(), "B closes it again")
	_frame()
	_check(not _hud.get_radial(1).is_open(), "and it stays closed")
	_bus.room_cleared.emit(&"test_room")
	_bus.run_ended.emit(false)
	_tap(0, &"back")
	_frame()
	_check(not _hud.get_radial(0).is_open(), "no builder outside a room")


## The hub's altar (online-lobby L2): A (`accept`) sends `online_open_requested` for a player
## whose wizard stands on it (`altar_changed`), with no menu open; the lit stone's A comes first.
func _test_a_on_the_altar_asks_to_open_the_room() -> void:
	_setup(2)
	var asked: Array[int] = []
	var runs: Array[int] = []
	_bus.online_open_requested.connect(func(player: int) -> void: asked.append(player))
	_bus.run_requested.connect(func(player: int) -> void: runs.append(player))
	_tap(1, &"accept")
	_frame()
	_check(asked.is_empty(), "A away from the altar asks nothing")
	_bus.altar_changed.emit(0b0010)
	_tap(0, &"accept")
	_frame()
	_check(asked.is_empty(), "A by a player who is not on the altar asks nothing")
	_tap(1, &"accept")
	_frame()
	_check((asked.size() == 1 and asked[0] == 1), "A on the altar asks to open the room, for its player: %s" % [asked])
	_tap(1, &"back")
	_frame()
	_tap(1, &"accept")
	_frame()
	_check((asked.size() == 1 and asked[0] == 1), "A inside a builder is the builder's: %s" % [asked])
	_tap(1, &"back")
	_frame()
	if _hud.get_radial(1).is_open():
		_hud.get_radial(1).close()
	_frame()
	_frame()
	_check(not _hud.get_radial(1).is_open(), "its builder is closed again")
	_bus.start_stone_changed.emit(2, 2, true)
	_tap(1, &"accept")
	_frame()
	_check((asked.size() == 1 and asked[0] == 1) and (runs.size() == 1 and runs[0] == 1), "on the lit stone A starts the run, not the room: %s %s" % [asked, runs])
	_bus.start_stone_changed.emit(0, 2, false)
	_bus.altar_changed.emit(0)
	_tap(1, &"accept")
	_frame()
	_check((asked.size() == 1 and asked[0] == 1), "A once off the altar asks nothing: %s" % [asked])


## Items I6: A (`take`; never `accept` alone, Space on the keyboard, which casts) with an item in
## reach (`item_near_changed`) sends `item_take_requested` for its player and that item, with no
## menu open; the lit stone's A comes first, the altar's after.
## The hint shows over the item while it is in reach, hides while its player has a menu open, and
## shakes red on `item_refused`.
func _test_a_by_an_item_takes_it_after_the_stone_and_before_the_altar() -> void:
	_setup(2)
	var takes: Array = []
	var runs: Array[int] = []
	var rooms: Array[int] = []
	_bus.item_take_requested.connect(func(player: int, item: int) -> void: takes.append([player, item]))
	_bus.run_requested.connect(func(player: int) -> void: runs.append(player))
	_bus.online_open_requested.connect(func(player: int) -> void: rooms.append(player))
	var hints: Control = _hud.get_item_hints()
	_bus.altar_changed.emit(0b0010)
	_bus.item_near_changed.emit(1, 7, Vector2(40, 40), {"kind": &"staff", "id": &"star", "name": "Wild star", "slots": 4, "cooldown": 0.15, "max_mana": 100.0, "cards": [&"bolt"]})
	_hud.step_hints(0.016)
	var hint: Control = hints.call("hint_of", 1)
	_check(hint.visible, "the hint shows over the item")
	_check(String(hint.call("title")) == "Take Wild star", "it names the item: %s" % hint.call("title"))
	_check(String(hint.call("line")).begins_with("4 slots"), "a staff's numbers: %s" % hint.call("line"))
	_bus.altar_changed.emit(0)
	_tap(1, &"accept")
	_frame()
	_check(takes.is_empty(), "accept alone (Space on the keyboard, which casts) takes nothing: %s" % [takes])
	_bus.altar_changed.emit(0b0010)
	_tap_a(1)
	_frame()
	_check(takes == [[1, 7]] and rooms.is_empty(), "A (take) takes the item, not the altar's room: %s %s" % [takes, rooms])
	_bus.item_refused.emit(1, 7)
	_check(bool(hint.call("is_refused")), "a refused take shakes it red")
	_hud.step_hints(1.0)
	_check(not bool(hint.call("is_refused")), "for a moment")
	_bus.start_stone_changed.emit(2, 2, true)
	_tap_a(1)
	_frame()
	_check(takes.size() == 1 and runs == [1], "on the lit stone A starts the run: %s %s" % [takes, runs])
	_bus.start_stone_changed.emit(0, 2, false)
	_tap(1, &"back")
	_frame()
	_hud.step_hints(0.016)
	_check(not hint.visible, "hidden while its player's builder is open")
	_tap_a(1)
	_frame()
	_check(takes.size() == 1, "and A inside the builder is the builder's: %s" % [takes])
	if _hud.get_radial(1).is_open():
		_hud.get_radial(1).close_builder()
	_frame()
	_frame()
	_bus.item_near_changed.emit(1, -1, Vector2.ZERO, {})
	_hud.step_hints(0.016)
	_check(not hint.visible, "hidden with nothing in reach")
	_tap_a(1)
	_frame()
	_check(takes.size() == 1 and rooms == [1], "then A on the altar opens the room: %s %s" % [takes, rooms])
	_bus.altar_changed.emit(0)


## The hub's stone (online-lobby L1): A (`accept`) sends `run_requested` for its player only while
## the stone is lit and that player has no menu open; never while the pause menu is open.
func _test_a_on_the_lit_stone_starts_the_run() -> void:
	_setup(2)
	var asked: Array[int] = []
	_bus.run_requested.connect(func(player: int) -> void: asked.append(player))
	_tap(1, &"accept")
	_frame()
	_check(asked.is_empty(), "A with no stone lit asks nothing")
	_bus.start_stone_changed.emit(2, 2, true)
	_tap(1, &"accept")
	_frame()
	_check(asked.size() == 1 and asked[0] == 1, "A on the lit stone asks for the run, for its player: %s" % [asked])
	_tap(0, &"back")
	_frame()
	_tap(0, &"accept")
	_frame()
	_check(asked.size() == 1 and asked[0] == 1, "A inside a builder is the builder's: %s" % [asked])
	_tap(0, &"pause")
	_frame()
	_tap(1, &"pause")
	_frame()
	_tap(1, &"accept")
	_frame()
	_check(asked.size() == 1 and asked[0] == 1, "A while paused asks nothing: %s" % [asked])
	# That A worked the menu (its focused Resume may have closed it): close it if it is still open.
	if _menu().is_open():
		_tap(1, &"pause")
		_frame()
	_check(not _menu().is_open() and not _hud.get_radial(0).is_open(), "no menu open now")
	_bus.start_stone_changed.emit(1, 2, false)
	_tap(1, &"accept")
	_frame()
	_check(asked.size() == 1 and asked[0] == 1, "A once the stone is out asks nothing: %s" % [asked])


func _test_start_closes_the_builder() -> void:
	_setup(1)
	_tap(0, &"back")
	_frame()
	_tap(0, &"pause")
	_frame()
	_check(not _hud.get_radial(0).is_open(), "Start closes an open builder")
	_check(not _menu().is_open(), "rather than pausing on top of it")


func _test_the_run_ending_closes_it() -> void:
	_setup(1)
	_tap(0, &"pause")
	_frame()
	_bus.run_ended.emit(false)
	_check(not _menu().is_open() and not _stops, "a run ending closes the menu and lets the game go")


## "Main menu" (online lobby: a machine whose host left joins another room from the menu): the
## menu closes and lets the game go first, then `main_menu_requested` asks this machine to leave,
## and the HUD itself shows the main menu again with no panel or menu over it.
func _test_main_menu_leaves_for_the_main_menu() -> void:
	_setup(2)
	var stand_in := PackedScene.new()
	var made := Node.new()
	made.name = "MenuStandIn"
	stand_in.pack(made)
	made.free()
	_hud.main_menu = stand_in
	var heard: Array[String] = []
	_bus.pause_requested.connect(func(player: int, on: int) -> void: heard.append("pause %d %d" % [player, on]))
	# Heard before the HUD's own handler (which closes every menu too), so the order is the menu's.
	var hud_heard := Callable(_hud, &"_on_main_menu_requested")
	_bus.main_menu_requested.disconnect(hud_heard)
	_bus.main_menu_requested.connect(func(player: int) -> void: heard.append("menu %d" % player))
	_bus.main_menu_requested.connect(hud_heard)
	_tap(1, &"pause")
	_frame()
	heard.clear()
	_press(1, "MainMenu")
	_check(not _menu().is_open() and not _stops, "Main menu closes the menu and lets the game go")
	# First: while a replay file plays the menu's closing unpauses the tree itself, which it no
	# longer does once the replay has ended on the way out.
	_check(heard == ["pause 1 0", "menu 1"], "first the game is let go, then this machine leaves, got %s" % [heard])
	var shown: Node = current_scene
	_check(shown != null and shown.name == "MenuStandIn" and shown.get_parent() == root, "the main menu is the current scene")
	_check(not _hud.get_panel(0).visible and not _hud.get_panel(1).visible, "and no panel is left over it")
	if shown != null and shown.name == "MenuStandIn":
		shown.free()


## "Leave game" (items I2, in place of the `leave` action): the menu closes and lets the game go
## first, then `seat_leave_requested` for the seat that opened it, whose device the input layer lets
## go (`device_left`: the seat's LEAVE in its next frame); the other seat plays on.
func _test_leave_game_lets_the_seat_go() -> void:
	_setup(2)
	var heard: Array[String] = []
	_bus.pause_requested.connect(func(player: int, on: int) -> void: heard.append("pause %d %d" % [player, on]))
	# Heard before the input layer, so the order is the menu's.
	_bus.seat_leave_requested.connect(func(player: int) -> void: heard.append("leave %d" % player))
	# The input layer hears the request once it is in the tree, as the autoload is.
	root.add_child(_input)
	await process_frame
	_bus.device_left.connect(func(player: int, _device: int) -> void: heard.append("gone %d" % player))
	_tap(1, &"pause")
	_frame()
	heard.clear()
	_press(1, "LeaveGame")
	_check(not _menu().is_open() and not _stops, "Leave game closes the menu and lets the game go")
	_check(heard == ["pause 1 0", "leave 1", "gone 1"], "first the game is let go, then the seat leaves, got %s" % [heard])
	_check(not _input.is_joined(1), "the seat that opened the menu is gone")
	_check(_input.is_joined(0), "the other seat plays on")


## The owner, 2026-11-13: while the game waits for a seat's unplugged gamepad, the HUD says whose
## controller is gone (the pad line, from co-op's `pad_wait_changed`), the waiting seat's own pause
## menu closes, and the menu another player opens lets the waiting seat leave.
func _test_a_waiting_seat_is_named_and_can_be_let_go() -> void:
	_setup(1)
	root.add_child(_input)
	await process_frame
	# Seat 1 is a real gamepad (device 3).
	var join := InputEventJoypadButton.new()
	join.device = 3
	join.button_index = JOY_BUTTON_A
	join.pressed = true
	_input.handle_event(join)
	_bus.player_joined.emit(1)
	_check(_input.player_of(3) == 1, "the gamepad sits on seat 1")
	var line: Label = _hud.get_pad_line()
	_check(not line.visible, "no line while every seat has its device")
	# Its own pause menu is open when the gamepad goes.
	var start := InputEventJoypadButton.new()
	start.device = 3
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	_input.handle_event(start)
	_frame()
	_check(_menu().owner_player == 1, "seat 1 opened the pause menu")
	_input._on_joy_connection_changed(3, false)
	# Co-op's part, done here: the waiting seats said.
	_bus.pad_wait_changed.emit(1 << 1)
	_check(not _menu().is_open(), "the waiting seat's menu closes: it cannot work it")
	_check(line.visible and line.text.contains("P2:") and not line.text.contains("P1:"), "the line names the seat: %s" % line.text)
	# Another player's menu offers to let it go.
	_tap(0, &"pause")
	_frame()
	_check(_menu().owner_player == 0 and _names().has("LeaveWaiting"), "the menu offers the waiting seat's leave: %s" % [_names()])
	_check(_menu().button("LeaveWaiting").text.contains("P2"), "naming the seat: %s" % _menu().button("LeaveWaiting").text)
	_press(0, "LeaveWaiting")
	_check(not _input.is_joined(1) and _input.is_joined(0), "only the waiting seat left")
	_check(_menu().is_open(), "the menu stays open")
	_check(not _names().has("LeaveWaiting"), "the row goes at once, so a second press asks nothing")
	_bus.pad_wait_changed.emit(0)
	_check(not line.visible and not _names().has("LeaveWaiting"), "nobody waits: no line, no row: %s" % [_names()])
	# A seat that waits on another machine is not this menu's to let go.
	_bus.pad_wait_changed.emit(1 << 2)
	_check(line.visible and line.text.contains("P3") and not _names().has("LeaveWaiting"), "another machine's waiting seat is named, not offered")
	_bus.main_menu_requested.emit(0)
	_check(not line.visible, "back at the main menu no line stays")
	# A waiting seat's builder closes too, as when a device left.
	_setup(2)
	_bus.room_entered.emit(&"test_room")
	_hud.get_radial(1).open_builder()
	_check(_hud.get_radial(1).is_open(), "seat 1's builder is open")
	_bus.pad_wait_changed.emit(1 << 1)
	_check(not _hud.get_radial(1).is_open() and not _input.is_captured(1), "a waiting seat's builder closes and frees it")
