extends SceneTree
## Tests for the pause menu (hud/menus/pause) and the buttons that open menus (owner,
## 2026-10-26): `pause` (Start) opens it for the player who pressed it and stops the game for
## everyone; only that player works it; Resume, `back` on the main page and `pause` again close
## it and the game goes on; Sandbox shows only in the sandbox and its page sends the sandbox
## actions and switches the builder and where the staff rows show the reload; Settings has Fullscreen and Effect slots; `back` (B)
## opens the builder in play, but not from inside a menu nor while paused; `pause` closes an
## open builder. Input goes through the real input manager's virtual devices.
##
## godot --headless --path . --script res://tests/hud/test_pause_menu.gd

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
## Loaded when needed, not preloaded: this scene is also the "Hud" autoload (see test_builder.gd).
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
const HudScript := preload("res://hud/panels/panels.gd")
const PauseMenuScript := preload("res://hud/menus/pause/pause_menu.gd")
const RadialScript := preload("res://hud/builder/radial_builder.gd")
const StaffRowScript := preload("res://hud/panels/player_panel/staff_row.gd")

var _failures: Array[String] = []
var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _hud: HudScript
var _actions: Array[Array] = []
var _slots: Array[int] = []


func _initialize() -> void:
	await process_frame
	_test_start_opens_it_and_pauses_everyone()
	_test_only_the_opener_works_it()
	_test_resume_back_and_start_close_it()
	_test_sandbox_entry_and_actions()
	_test_the_settings_page()
	_test_the_fullscreen_switch()
	_test_the_effect_slots_slider()
	_test_the_sandbox_switches_the_builder()
	_test_the_sandbox_switches_the_reload()
	_test_b_opens_the_builder_in_play_only()
	_test_start_closes_the_builder()
	_test_the_run_ending_closes_it()
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


func _setup(count: int, sandbox: bool = false) -> void:
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
	for index in count:
		_input.add_virtual_device(index)
	_hud = (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	_hud.events = _bus
	_hud.ui_focus = _focus
	_hud.input = _input
	root.add_child(_hud)
	for index in count:
		_bus.player_joined.emit(index)
	_bus.room_entered.emit(&"test_room")
	_bus.sandbox_changed.emit(sandbox)


func _teardown() -> void:
	paused = false
	_actions.clear()
	_slots.clear()
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
	_check(not _menu().visible and not paused, "closed and running at the start")
	_tap(1, &"pause")
	_frame()
	_check(_menu().is_open() and _menu().visible, "Start opens the pause menu")
	_check(_menu().owner_player == 1, "for the player who pressed it")
	_check(paused, "the game is paused for everyone")
	_check(_names() == ["Resume", "Settings"], "the main page out of the sandbox, got %s" % [_names()])
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
		_check(_menu().is_open() and paused, "%s: open" % way)
		_tap(0, way)  # accept lands on Resume, the first button.
		_frame()
		_check(not _menu().is_open() and not _menu().visible, "%s closes the menu" % way)
		_check(not paused, "%s: the game goes on" % way)
		_check(not _hud.get_radial(0).is_open(), "%s: closing with B does not open the builder" % way)


func _test_sandbox_entry_and_actions() -> void:
	_setup(2, true)
	_tap(1, &"pause")
	_frame()
	_check(_names() == ["Resume", "Sandbox", "Settings"], "in the sandbox the main page has Sandbox, got %s" % [_names()])
	_press(1, "Sandbox")
	_check(_names() == ["ImpWave", "ResetDummies", "BuilderStyle", "RingStyle", "PutStyle", "ReloadStyle", "SandboxBack"], "the sandbox page, got %s" % [_names()])
	_press(1, "ImpWave")
	_press(1, "ImpWave")
	_press(1, "ResetDummies")
	_check(_actions == [[1, &"imp_wave"], [1, &"imp_wave"], [1, &"reset_dummies"]], "the actions go out with the opener's index, got %s" % [_actions])
	_check(_menu().is_open() and _menu().page == PauseMenuScript.Page.SANDBOX, "the page stays for another press")
	_tap(1, &"back")
	_frame()
	_check(_menu().page == PauseMenuScript.Page.MAIN and _menu().is_open(), "B goes back to the main page")
	_bus.sandbox_changed.emit(false)
	_check(_names() == ["Resume", "Settings"], "out of the sandbox the entry goes")


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
	_menu().builder_options_changed.connect(func(radial: bool, by_kind: bool, push: bool) -> void: options.append([radial, by_kind, push]))
	_tap(0, &"pause")
	_frame()
	_press(0, "Sandbox")
	_check(_menu().button("BuilderStyle").text.ends_with("Builder: Radial"), "the radial builder by default")
	_check(_hud.uses_radial(), "and the panels use it")
	_check(_menu().button("PutStyle").text.ends_with("Full slot: Push right"), "a full slot pushes right by default")
	_press(0, "BuilderStyle")
	_check(_menu().button("BuilderStyle").text.ends_with("Builder: List"), "it flips to the list builder")
	_check(not _hud.uses_radial(), "and the panels use that")
	_press(0, "BuilderStyle")
	_press(0, "RingStyle")
	_press(0, "PutStyle")
	_check(options == [[false, false, true], [true, false, true], [true, true, true], [true, true, false]], "each flip goes out, got %s" % [options])
	_check(_hud.get_radial(0).layout == RadialScript.Layout.KIND, "the ring shows one kind at a time")
	_check(_hud.get_radial(0).put == RadialScript.Put.REPLACE, "a full slot is replaced")
	_check(_menu().page == PauseMenuScript.Page.SANDBOX, "the page stays")
	_tap(0, &"pause")
	_frame()
	_tap(0, &"back")
	_frame()
	_check(_hud.get_radial(0).is_open(), "B opens the radial builder now")
	_check(not _hud.get_builder(0).is_open(), "not the list one")
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
	_check(_names() == ["Fullscreen", "EffectSlots", "SettingsBack"], "Settings, got %s" % [_names()])
	_check(_menu().button("FriendlyFire") == null and _menu().button("EnemyFire") == null, "no fire settings")
	_tap(0, &"back")
	_frame()
	_check(_menu().page == PauseMenuScript.Page.MAIN, "B goes up to the main page")


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
	_check(_focus.focused(0) == _menu().button("SettingsBack"), "down leaves the slider")
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
	_check(not _menu().is_open() and not paused, "a run ending closes the menu and un-pauses")
