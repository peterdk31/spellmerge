extends SceneTree
## Tests for hud/panels and hud/theme: a panel per player index 0-3 in its own
## colour (theme variation and "P<n>" text), health and mana shown from
## `player_stats_changed` only, "DOWN" and "MENU" words (state is never colour
## alone), panels shown only for joined players once a room was entered, four
## players at once without crosstalk, a corner each, and every panel fits the
## 640x360 view.
##
## godot --headless --path . --script res://tests/hud/test_panels.gd

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const PlayerPanelScript := preload("res://hud/panels/player_panel/player_panel.gd")
const PanelScene := preload("res://hud/panels/player_panel/player_panel.tscn")
## Loaded when needed, not preloaded: this scene is also the "Hud" autoload, and
## preloading it here makes the autoload's own load fail at start (cyclic resource).
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
const HudScript := preload("res://hud/panels/panels.gd")
const SpellmergeTheme := preload("res://hud/theme/spellmerge_theme.tres")

var _failures: Array[String] = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	_test_theme_has_the_variations()
	_test_project_uses_the_theme()
	_test_panel_per_player()
	_test_panel_shows_numbers()
	_test_down_and_menu_words()
	_test_hud_waits_for_room_and_join()
	_test_hud_routes_to_the_right_panel()
	_test_leave_and_rejoin_resets_the_panel()
	_test_run_boundaries_hide_panels()
	_test_hud_four_players_in_four_corners()
	_test_hud_menu_word_follows_ui_focus()
	_test_bad_indices_are_ignored()
	_test_hud_sends_no_events()
	if _failures.is_empty():
		print("TEST OK: hud/panels and hud/theme")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _make_hud() -> Array:
	var bus: EventsScript = EventsScript.new()
	var focus: UIFocusScript = UIFocusScript.new()
	var hud: HudScript = (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	hud.events = bus
	hud.ui_focus = focus
	root.add_child(hud)
	return [hud, bus, focus]


func _free_hud(parts: Array) -> void:
	for node: Node in parts:
		node.free()


func _test_theme_has_the_variations() -> void:
	for n in range(1, 5):
		_check(SpellmergeTheme.has_stylebox("panel", "PlayerPanel%d" % n), "theme has PlayerPanel%d" % n)
		_check(SpellmergeTheme.has_color("font_color", "PlayerLabel%d" % n), "theme has PlayerLabel%d" % n)
	for type_name in ["HealthBar", "ManaBar"]:
		_check(SpellmergeTheme.has_stylebox("fill", type_name), "theme has %s" % type_name)
	# The four panel borders differ, so no two players look alike.
	var borders: Array[Color] = []
	for n in range(1, 5):
		var box := SpellmergeTheme.get_stylebox("panel", "PlayerPanel%d" % n) as StyleBoxFlat
		_check(box != null and not borders.has(box.border_color), "player panel %d has its own border colour" % n)
		if box != null:
			borders.append(box.border_color)


func _test_project_uses_the_theme() -> void:
	var path := str(ProjectSettings.get_setting("gui/theme/custom", ""))
	_check(path == "res://hud/theme/spellmerge_theme.tres", "the project theme is the single HUD theme, got '%s'" % path)
	var autoload := str(ProjectSettings.get_setting("autoload/Hud", ""))
	_check(autoload == "*res://hud/panels/panels.tscn", "autoload Hud is registered, got '%s'" % autoload)


func _test_panel_per_player() -> void:
	for player in 4:
		var panel := PanelScene.instantiate() as PlayerPanelScript
		panel.index = player
		root.add_child(panel)
		_check(panel.theme_type_variation == StringName("PlayerPanel%d" % (player + 1)), "panel %d uses its theme variation" % player)
		_check((panel.find_child("Name", true, false) as Label).text == "P%d" % (player + 1), "panel %d is labelled P%d" % [player, player + 1])
		panel.free()


func _test_panel_shows_numbers() -> void:
	var panel := PanelScene.instantiate() as PlayerPanelScript
	panel.index = 1
	root.add_child(panel)
	panel.set_stats(64, 100, 37.8, 100.0)
	var health_bar := panel.find_child("HealthBar", true, false) as ProgressBar
	var mana_bar := panel.find_child("ManaBar", true, false) as ProgressBar
	_check(health_bar.value == 64.0 and health_bar.max_value == 100.0, "health bar shows 64 of 100")
	_check(is_equal_approx(mana_bar.value, 37.8) and mana_bar.max_value == 100.0, "mana bar shows the mana")
	_check((panel.find_child("HealthValue", true, false) as Label).text == "64", "health number is 64")
	_check((panel.find_child("ManaValue", true, false) as Label).text == "37", "mana number is whole, 37")
	_check(not panel.is_downed() and panel.status_text() == "", "a healthy player has no status word")
	panel.free()


func _test_down_and_menu_words() -> void:
	var panel := PanelScene.instantiate() as PlayerPanelScript
	root.add_child(panel)
	panel.set_stats(100, 100, 100.0, 100.0)
	panel.set_menu_open(true)
	_check(panel.status_text() == "MENU", "an open overlay shows MENU")
	panel.set_stats(0, 100, 50.0, 100.0)
	_check(panel.is_downed() and panel.status_text() == "DOWN", "no health shows DOWN, which wins over MENU")
	panel.set_stats(50, 100, 50.0, 100.0)
	_check(panel.status_text() == "MENU", "a revive shows MENU again while the overlay is open")
	panel.set_menu_open(false)
	_check(panel.status_text() == "", "closing the overlay clears the word")
	panel.free()


func _test_hud_waits_for_room_and_join() -> void:
	var parts: Array = _make_hud()
	var hud: HudScript = parts[0]
	var bus: EventsScript = parts[1]
	for player in 4:
		_check(not hud.get_panel(player).visible, "panel %d starts hidden" % player)
	bus.player_joined.emit(0)
	bus.player_joined.emit(2)
	_check(not hud.get_panel(0).visible, "a joined player's panel waits for a room")
	bus.room_entered.emit(&"arena_01")
	_check(hud.get_panel(0).visible and hud.get_panel(2).visible, "joined players' panels show once a room is entered")
	_check(not hud.get_panel(1).visible and not hud.get_panel(3).visible, "players who did not join have no panel")
	bus.player_joined.emit(1)
	_check(hud.get_panel(1).visible, "a mid-run joiner's panel shows at once")
	bus.player_left.emit(0)
	_check(not hud.get_panel(0).visible and hud.get_panel(2).visible, "a leaver's panel hides and the others stay")
	_free_hud(parts)


func _test_leave_and_rejoin_resets_the_panel() -> void:
	var parts: Array = _make_hud()
	var hud: HudScript = parts[0]
	var bus: EventsScript = parts[1]
	bus.room_entered.emit(&"arena_01")
	bus.player_joined.emit(1)
	bus.player_stats_changed.emit(1, 0, 5, 3.0, 10.0)
	_check(hud.get_panel(1).is_downed(), "the panel shows down before the player leaves")
	bus.player_left.emit(1)
	_check(not hud.get_panel(1).is_downed() and hud.get_panel(1).status_text() == "", "leaving clears the down state")
	# Stats may arrive before the join: they are kept and shown when the join comes.
	bus.player_stats_changed.emit(1, 5, 5, 10.0, 10.0)
	_check(not hud.get_panel(1).visible, "stats alone do not show a panel")
	bus.player_joined.emit(1)
	_check(hud.get_panel(1).visible and not hud.get_panel(1).is_downed(), "the rejoined panel shows with fresh numbers")
	_free_hud(parts)


func _test_run_boundaries_hide_panels() -> void:
	var parts: Array = _make_hud()
	var hud: HudScript = parts[0]
	var bus: EventsScript = parts[1]
	bus.player_joined.emit(0)
	bus.player_joined.emit(3)
	bus.room_entered.emit(&"arena_01")
	bus.player_stats_changed.emit(0, 0, 5, 0.0, 10.0)
	_check(hud.get_panel(0).visible and hud.get_panel(3).visible, "panels show during the run")
	bus.run_ended.emit(false)
	_check(not hud.get_panel(0).visible and not hud.get_panel(3).visible, "run_ended hides all panels")
	_check(not hud.get_panel(0).is_downed(), "run_ended clears the down state")
	bus.run_started.emit(2)
	_check(not hud.get_panel(0).visible, "panels wait for a room after run_started")
	bus.room_entered.emit(&"arena_01")
	_check(hud.get_panel(0).visible and hud.get_panel(3).visible, "joined players' panels return in the next run")
	_free_hud(parts)


func _test_hud_routes_to_the_right_panel() -> void:
	var parts: Array = _make_hud()
	var hud: HudScript = parts[0]
	var bus: EventsScript = parts[1]
	bus.player_stats_changed.emit(2, 40, 100, 10.0, 100.0)
	var value := func(player: int, label: String) -> String:
		return (hud.get_panel(player).find_child(label, true, false) as Label).text
	_check(value.call(2, "HealthValue") == "40" and value.call(2, "ManaValue") == "10", "player 2's panel shows its numbers")
	_check(value.call(0, "HealthValue") == "100" and value.call(3, "HealthValue") == "100", "the other panels are untouched")
	bus.player_stats_changed.emit(3, 0, 100, 0.0, 100.0)
	_check(hud.get_panel(3).is_downed() and not hud.get_panel(2).is_downed(), "only player 3 is shown down")
	_free_hud(parts)


func _test_hud_four_players_in_four_corners() -> void:
	var parts: Array = _make_hud()
	var hud: HudScript = parts[0]
	var bus: EventsScript = parts[1]
	for player in 4:
		bus.player_joined.emit(player)
	bus.room_entered.emit(&"arena_01")
	# Each panel is anchored to its corner and grows away from it, onto the screen.
	var right: Array[bool] = [false, true, false, true]
	var bottom: Array[bool] = [false, false, true, true]
	for player in 4:
		var panel: Control = hud.get_panel(player)
		_check(panel.visible, "panel %d is shown" % player)
		_check(panel.anchor_left == (1.0 if right[player] else 0.0), "panel %d is on the %s" % [player, "right" if right[player] else "left"])
		_check(panel.anchor_top == (1.0 if bottom[player] else 0.0), "panel %d is at the %s" % [player, "bottom" if bottom[player] else "top"])
		_check(panel.grow_horizontal == (Control.GROW_DIRECTION_BEGIN if right[player] else Control.GROW_DIRECTION_END), "panel %d grows away from its side" % player)
		_check(panel.grow_vertical == (Control.GROW_DIRECTION_BEGIN if bottom[player] else Control.GROW_DIRECTION_END), "panel %d grows away from its edge" % player)
		# Four panels of this size leave most of the 640x360 view free.
		var wanted: Vector2 = panel.get_combined_minimum_size()
		_check(wanted.x >= 100.0 and wanted.x <= 140.0 and wanted.y <= 80.0, "panel %d is small, got %s" % [player, wanted])
	_free_hud(parts)


func _test_hud_menu_word_follows_ui_focus() -> void:
	var parts: Array = _make_hud()
	var hud: HudScript = parts[0]
	var focus: UIFocusScript = parts[2]
	focus.opened.emit(1)
	_check(hud.get_panel(1).status_text() == "MENU", "an overlay open for player 1 shows MENU on panel 1")
	_check(hud.get_panel(0).status_text() == "" and hud.get_panel(2).status_text() == "", "the other panels show nothing")
	focus.closed.emit(1)
	_check(hud.get_panel(1).status_text() == "", "closing clears the word")
	_free_hud(parts)


func _test_bad_indices_are_ignored() -> void:
	var parts: Array = _make_hud()
	var hud: HudScript = parts[0]
	var bus: EventsScript = parts[1]
	bus.player_joined.emit(7)
	bus.player_left.emit(-1)
	bus.player_stats_changed.emit(4, 1, 100, 1.0, 100.0)
	bus.player_stats_changed.emit(-1, 1, 100, 1.0, 100.0)
	_check(hud.get_panel(4) == null and hud.get_panel(-1) == null, "get_panel gives null for a bad index")
	for player in 4:
		_check(hud.get_panel(player).status_text() == "", "no panel changed for a bad index")
	_free_hud(parts)


## The HUD must not send any event itself (it only listens in this part).
func _test_hud_sends_no_events() -> void:
	var source := FileAccess.get_file_as_string("res://hud/panels/panels.gd")
	source += FileAccess.get_file_as_string("res://hud/panels/player_panel/player_panel.gd")
	_check(not source.contains(".emit("), "the panel scripts send no events")
	_check(not source.contains("Input."), "the panel scripts read no input")
