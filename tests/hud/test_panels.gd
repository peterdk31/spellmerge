extends "res://tests/support/suite.gd"
## Tests for hud/panels and hud/theme, one behaviour per test: a panel per player index 0-3 in its
## own colour (theme variation), health and mana shown from `player_stats_changed` only, "DOWN"
## and "MENU" words (state is never colour alone; a possession has no word: the panel stays the
## player's own wizard, owner 2026-10-28, tested in tests/gameplay/actor/test_possess.gd), panels
## shown only for joined players once a room was entered, four players at once without crosstalk,
## a corner each, the hurt vignette, the ONLINE word on a seat another machine plays, and the panel
## scripts sending no events but the player intents.
##
## The theme tests read the theme alone, the panel tests make one player panel, and the HUD tests
## make the panels scene (hud/panels/panels.tscn) on a bus, UI focus and save of their own; all of
## it is freed after each test.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const PlayerPanelScript := preload("res://hud/panels/player_panel/player_panel.gd")
const PanelScene := preload("res://hud/panels/player_panel/player_panel.tscn")
const MeterLineScript := preload("res://hud/widgets/meter_line.gd")
const QuickCrossScript := preload("res://hud/widgets/quick_cross.gd")
## Loaded when needed, not preloaded: this scene is also the "Hud" autoload, and
## preloading it here makes the autoload's own load fail at start (cyclic resource).
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
## A save no test writes, so a Hud never reads the real `user://save.cfg`.
const NO_SAVE: String = "user://test_no_save.cfg"
const HudScript := preload("res://hud/panels/panels.gd")
const SpellmergeTheme := preload("res://hud/theme/spellmerge_theme.tres")
## Panel background alpha must stay below 1 (a wizard or enemy under a corner panel shows
## through) and at or above this floor (docs/DECISIONS.md, 2026-10-17: below 0.4 the text would
## stand on almost nothing). All four panel_p1-p4 boxes change together.
const PANEL_ALPHA_MIN: float = 0.4
## The sizes the HUD was designed with at 640x360; lowering them is a deliberate decision.
const LABEL_SIZE_MIN: int = 12
const BUTTON_SIZE_MIN: int = 14

var _hud: HudScript
var _bus: EventsScript
var _focus: UIFocusScript


func before_each() -> void:
	_hud = null
	_bus = null
	_focus = null


## The panels scene on a bus, UI focus and save of its own, in the tree; `joined` players have
## joined, and a room was entered when `room`.
func _make_hud(joined: Array[int] = [], room: bool = false) -> HudScript:
	_bus = own(EventsScript.new()) as EventsScript
	_focus = own(UIFocusScript.new()) as UIFocusScript
	_hud = (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	_hud.events = _bus
	_hud.save = SaveFile.new(NO_SAVE)
	_hud.ui_focus = _focus
	root.add_child(own(_hud))
	for player in joined:
		_bus.player_joined.emit(player)
	if room:
		_bus.room_entered.emit(&"arena_01", 0)
	return _hud


## One player panel for `index`, in the tree.
func _panel(index: int = 0) -> PlayerPanelScript:
	var panel := PanelScene.instantiate() as PlayerPanelScript
	panel.index = index
	root.add_child(own(panel))
	return panel


func _label(panel: Control, label: String) -> String:
	return (panel.find_child(label, true, false) as Label).text


# --- The theme ---------------------------------------------------------------------------------


func test_the_theme_has_a_panel_and_a_label_variation_per_player() -> void:
	for n in range(1, 5):
		check(SpellmergeTheme.has_stylebox("panel", "PlayerPanel%d" % n), "theme has PlayerPanel%d" % n)
		check(SpellmergeTheme.has_color("font_color", "PlayerLabel%d" % n), "theme has PlayerLabel%d" % n)


func test_the_theme_has_the_health_bar_fill() -> void:
	# The boss bar's; the corner panel draws thin lines of its own (`meter_line.gd`).
	check(SpellmergeTheme.has_stylebox("fill", "HealthBar"), "theme has HealthBar")


func test_every_player_panel_has_its_own_border_colour() -> void:
	# The four panel borders differ, so no two players look alike.
	var borders: Array[Color] = []
	for n in range(1, 5):
		var box := SpellmergeTheme.get_stylebox("panel", "PlayerPanel%d" % n) as StyleBoxFlat
		check(box != null and not borders.has(box.border_color), "player panel %d has its own border colour" % n)
		if box != null:
			borders.append(box.border_color)


func test_every_player_panel_background_is_translucent_but_readable() -> void:
	for n in range(1, 5):
		var box := SpellmergeTheme.get_stylebox("panel", "PlayerPanel%d" % n) as StyleBoxFlat
		check(box != null and box.bg_color.a < 1.0 and box.bg_color.a >= PANEL_ALPHA_MIN, "player panel %d background is translucent but readable, alpha %s" % [n, box.bg_color.a if box != null else -1.0])


func test_the_theme_fonts_are_no_smaller_than_designed() -> void:
	check(SpellmergeTheme.get_font_size("font_size", "Label") >= LABEL_SIZE_MIN, "labels are at least %d px" % LABEL_SIZE_MIN)
	check(SpellmergeTheme.get_font_size("font_size", "Button") >= BUTTON_SIZE_MIN, "buttons are at least %d px" % BUTTON_SIZE_MIN)


func test_the_project_uses_the_single_hud_theme() -> void:
	var path := str(ProjectSettings.get_setting("gui/theme/custom", ""))
	check_equal(path, "res://hud/theme/spellmerge_theme.tres", "the project theme is the HUD's theme")


func test_the_hud_is_an_autoload() -> void:
	var autoload := str(ProjectSettings.get_setting("autoload/Hud", ""))
	check_equal(autoload, "*res://hud/panels/panels.tscn", "autoload Hud is registered")


## The loading screen covers every line and overlay of the HUD (the stone line was drawn over it
## while the party departed from the stone). The pause menu and the pad line are over it: either stops
## the game, and a departure with it, so the screen stays down under them until the run starts.
func test_the_loading_screen_is_under_only_the_pause_menu_the_pad_line_and_the_frame_rate() -> void:
	var hud_root: Control = _make_hud().get_node("Root") as Control
	var count: int = hud_root.get_child_count()
	var top: Array[StringName] = []
	for i in range(count - 4, count):
		top.append(hud_root.get_child(i).name)
	check_equal(top, [&"Loading", &"PauseMenu", &"PadLine", &"FpsCounter"] as Array[StringName], "the loading screen over the rest, those over it")


# --- One panel ---------------------------------------------------------------------------------


func test_each_panel_uses_its_players_theme_variation() -> void:
	for player in 4:
		var panel: PlayerPanelScript = _panel(player)
		check_equal(panel.theme_type_variation, StringName("PlayerPanel%d" % (player + 1)), "panel %d uses its theme variation" % player)


func test_the_health_line_shows_the_health() -> void:
	var panel: PlayerPanelScript = _panel(1)
	await process_frame
	panel.set_stats(64, 100)
	var line: MeterLineScript = panel.health_line()
	var width: int = floori(line.size.x)
	check(width >= 40, "the line has its width, got %d" % width)
	check_equal(line.target_pixels(), ceili(width * 0.64 - 0.001), "the red line goes to 64 of 100")
	check_equal(line.shown_pixels(), line.target_pixels(), "the first value is drawn at once")
	check(line.size.y <= 3.0, "and it is a thin line, %s px" % line.size.y)
	check_equal(line.fill_color, MeterLineScript.HEALTH_COLOR, "in the HUD's red")


func test_the_panel_is_small() -> void:
	var panel: PlayerPanelScript = _panel(1)
	panel.set_stats(64, 100)
	await process_frame
	var wanted: Vector2 = panel.get_combined_minimum_size()
	# With no staffs: one thin line and its small number, over the empty quick-use cross that always
	# shows (the owner, 2026-11-20).
	check(wanted.y <= 20.0 + QuickCrossScript.SIDE, "with no staffs the panel is one thin line and its small number over the cross, got %s" % wanted)
	check(wanted.x <= 104.0, "and narrow, got %s" % wanted)
	check(panel.find_child("ManaBar", true, false) == null and panel.find_child("ManaValue", true, false) == null, "no panel-wide mana bar: each staff row has its own line")


func test_the_health_number_is_shown_small() -> void:
	var panel: PlayerPanelScript = _panel(1)
	panel.set_stats(64, 100)
	check_equal(_label(panel, "HealthValue"), "64", "health number")
	var label := panel.find_child("HealthValue", true, false) as Label
	check(label.get_theme_font_size(&"font_size") <= 8, "in the small font")


func test_a_healthy_player_has_no_status_word() -> void:
	var panel: PlayerPanelScript = _panel(1)
	panel.set_stats(64, 100)
	check(not panel.is_downed(), "not shown down")
	check_equal(panel.status_text(), "", "no status word")


func test_a_staffs_mana_shows_on_its_own_row() -> void:
	var panel: PlayerPanelScript = _panel(1)
	var icons: Array[Texture2D] = [null]
	panel.set_staff_plan(2, {"cards": [&"bolt"], "casts": [{"slots": PackedInt32Array([0])}]}, icons)
	await process_frame
	var line: MeterLineScript = panel.staff_row(2).mana_line()
	check(line.size.x >= 40.0, "the line runs under the cards, got %s" % line.size)
	check(line.position.y >= panel.staff_row(2).BOX_HEIGHT, "under the cards' frames")
	check(not line.visible, "no line before the staff's mana is told")
	panel.set_staff_mana(2, 30.0, 120.0)
	check(line.visible, "told, the line shows")
	check_equal(line.fill_color, MeterLineScript.MANA_COLOR, "in the HUD's blue")
	check_equal(line.target_pixels(), ceili(floorf(line.size.x) * 0.25 - 0.001), "a quarter of its pool")
	check(not panel.staff_row(0).mana_line().visible, "another staff's line is its own")
	panel.set_staff_mana(2, INF, 0.0)
	check(not line.visible, "a mana forgotten (another body shown) hides it again")


func test_an_open_overlay_shows_menu() -> void:
	var panel: PlayerPanelScript = _panel()
	panel.set_stats(100, 100)
	panel.set_menu_open(true)
	check_equal(panel.status_text(), "MENU", "an open overlay shows MENU")


func test_no_health_shows_down_over_menu() -> void:
	var panel: PlayerPanelScript = _panel()
	panel.set_menu_open(true)
	panel.set_stats(0, 100)
	check(panel.is_downed(), "no health is down")
	check_equal(panel.status_text(), "DOWN", "DOWN wins over MENU")


func test_a_revive_with_the_overlay_open_shows_menu_again() -> void:
	var panel: PlayerPanelScript = _panel()
	panel.set_menu_open(true)
	panel.set_stats(0, 100)
	panel.set_stats(50, 100)
	check_equal(panel.status_text(), "MENU", "a revive shows MENU again while the overlay is open")


func test_closing_the_overlay_clears_the_word() -> void:
	var panel: PlayerPanelScript = _panel()
	panel.set_stats(100, 100)
	panel.set_menu_open(true)
	panel.set_menu_open(false)
	check_equal(panel.status_text(), "", "closing the overlay clears the word")


# --- Which panels show -------------------------------------------------------------------------


func test_every_panel_starts_hidden() -> void:
	var hud: HudScript = _make_hud()
	for player in 4:
		check(not hud.get_panel(player).visible, "panel %d starts hidden" % player)


func test_a_joined_players_panel_waits_for_a_room() -> void:
	var hud: HudScript = _make_hud([0, 2])
	check(not hud.get_panel(0).visible, "a joined player's panel waits for a room")


func test_joined_players_panels_show_once_a_room_is_entered() -> void:
	var hud: HudScript = _make_hud([0, 2], true)
	check(hud.get_panel(0).visible and hud.get_panel(2).visible, "joined players' panels show once a room is entered")


func test_players_who_did_not_join_have_no_panel() -> void:
	var hud: HudScript = _make_hud([0, 2], true)
	check(not hud.get_panel(1).visible and not hud.get_panel(3).visible, "players who did not join have no panel")


func test_a_mid_run_joiners_panel_shows_at_once() -> void:
	var hud: HudScript = _make_hud([0, 2], true)
	_bus.player_joined.emit(1)
	check(hud.get_panel(1).visible, "a mid-run joiner's panel shows at once")


func test_a_leavers_panel_hides_while_the_others_stay() -> void:
	var hud: HudScript = _make_hud([0, 2], true)
	_bus.player_left.emit(0)
	check(not hud.get_panel(0).visible, "a leaver's panel hides")
	check(hud.get_panel(2).visible, "the others stay")


func test_leaving_clears_the_down_state() -> void:
	var hud: HudScript = _make_hud([1], true)
	_bus.player_stats_changed.emit(1, 0, 5, 3.0, 10.0)
	check(hud.get_panel(1).is_downed(), "the panel shows down before the player leaves")
	_bus.player_left.emit(1)
	check(not hud.get_panel(1).is_downed() and hud.get_panel(1).status_text() == "", "leaving clears the down state")


func test_stats_alone_do_not_show_a_panel() -> void:
	var hud: HudScript = _make_hud([], true)
	_bus.player_stats_changed.emit(1, 5, 5, 10.0, 10.0)
	check(not hud.get_panel(1).visible, "stats alone do not show a panel")


func test_a_rejoined_panel_shows_the_numbers_sent_before_the_join() -> void:
	# Stats may arrive before the join: they are kept and shown when the join comes.
	var hud: HudScript = _make_hud([1], true)
	_bus.player_stats_changed.emit(1, 0, 5, 3.0, 10.0)
	_bus.player_left.emit(1)
	_bus.player_stats_changed.emit(1, 5, 5, 10.0, 10.0)
	_bus.player_joined.emit(1)
	check(hud.get_panel(1).visible, "the rejoined panel shows")
	check(not hud.get_panel(1).is_downed(), "with fresh numbers")


func test_run_ended_hides_every_panel() -> void:
	var hud: HudScript = _make_hud([0, 3], true)
	check(hud.get_panel(0).visible and hud.get_panel(3).visible, "panels show during the run")
	_bus.run_ended.emit(false)
	check(not hud.get_panel(0).visible and not hud.get_panel(3).visible, "run_ended hides all panels")


func test_run_ended_clears_the_down_state() -> void:
	var hud: HudScript = _make_hud([0, 3], true)
	_bus.player_stats_changed.emit(0, 0, 5, 0.0, 10.0)
	_bus.run_ended.emit(false)
	check(not hud.get_panel(0).is_downed(), "run_ended clears the down state")


func test_panels_wait_for_a_room_after_run_started() -> void:
	var hud: HudScript = _make_hud([0, 3], true)
	_bus.run_ended.emit(false)
	_bus.run_started.emit(2)
	check(not hud.get_panel(0).visible, "panels wait for a room after run_started")


func test_joined_players_panels_return_in_the_next_run() -> void:
	var hud: HudScript = _make_hud([0, 3], true)
	_bus.run_ended.emit(false)
	_bus.run_started.emit(2)
	_bus.room_entered.emit(&"arena_01", 0)
	check(hud.get_panel(0).visible and hud.get_panel(3).visible, "joined players' panels return in the next run")


func test_stats_reach_only_their_players_panel() -> void:
	var hud: HudScript = _make_hud()
	_bus.player_stats_changed.emit(2, 40, 100, 10.0, 100.0)
	check_equal(_label(hud.get_panel(2), "HealthValue"), "40", "player 2's panel shows its health")
	check(_label(hud.get_panel(0), "HealthValue") == "100" and _label(hud.get_panel(3), "HealthValue") == "100", "the other panels are untouched")


func test_only_the_downed_players_panel_shows_down() -> void:
	var hud: HudScript = _make_hud()
	_bus.player_stats_changed.emit(2, 40, 100, 10.0, 100.0)
	_bus.player_stats_changed.emit(3, 0, 100, 0.0, 100.0)
	check(hud.get_panel(3).is_downed(), "player 3 is shown down")
	check(not hud.get_panel(2).is_downed(), "player 2 is not")


func test_four_players_show_four_panels() -> void:
	var hud: HudScript = _make_hud([0, 1, 2, 3], true)
	for player in 4:
		check(hud.get_panel(player).visible, "panel %d is shown" % player)


func test_each_panel_is_anchored_to_its_corner() -> void:
	var hud: HudScript = _make_hud([0, 1, 2, 3], true)
	var right: Array[bool] = [false, true, false, true]
	var bottom: Array[bool] = [false, false, true, true]
	for player in 4:
		var panel: Control = hud.get_panel(player)
		check(panel.anchor_left == (1.0 if right[player] else 0.0), "panel %d is on the %s" % [player, "right" if right[player] else "left"])
		check(panel.anchor_top == (1.0 if bottom[player] else 0.0), "panel %d is at the %s" % [player, "bottom" if bottom[player] else "top"])


func test_each_panel_grows_away_from_its_corner_onto_the_screen() -> void:
	var hud: HudScript = _make_hud([0, 1, 2, 3], true)
	var right: Array[bool] = [false, true, false, true]
	var bottom: Array[bool] = [false, false, true, true]
	for player in 4:
		var panel: Control = hud.get_panel(player)
		check(panel.grow_horizontal == (Control.GROW_DIRECTION_BEGIN if right[player] else Control.GROW_DIRECTION_END), "panel %d grows away from its side" % player)
		check(panel.grow_vertical == (Control.GROW_DIRECTION_BEGIN if bottom[player] else Control.GROW_DIRECTION_END), "panel %d grows away from its edge" % player)


# --- The hurt vignette -------------------------------------------------------------------------


## A HUD with player 2 in a room, its wizard just appeared (full health, mana 10).
func _hud_with_player_two() -> HudScript:
	var hud: HudScript = _make_hud([2], true)
	_bus.player_stats_changed.emit(2, 100, 100, 10.0, 100.0)
	return hud


func test_no_vignette_when_a_wizard_appears() -> void:
	var hud: HudScript = _hud_with_player_two()
	check(not hud.get_vignette().visible, "no vignette when a wizard appears")


func test_no_vignette_when_only_mana_changes() -> void:
	var hud: HudScript = _hud_with_player_two()
	_bus.player_stats_changed.emit(2, 100, 100, 5.0, 100.0)
	check(not hud.get_vignette().visible, "no vignette when only mana changes")


func test_a_health_drop_shows_the_vignette() -> void:
	var hud: HudScript = _hud_with_player_two()
	_bus.player_stats_changed.emit(2, 80, 100, 10.0, 100.0)
	check(hud.get_vignette().visible and hud.get_vignette().strength > 0.0, "a health drop shows the vignette")


func test_more_hits_glow_more_up_to_a_limit() -> void:
	var vignette := _hud_with_player_two().get_vignette()
	_bus.player_stats_changed.emit(2, 80, 100, 10.0, 100.0)
	var first: float = vignette.strength
	_bus.player_stats_changed.emit(2, 60, 100, 10.0, 100.0)
	check(vignette.strength > first and vignette.strength <= vignette.MAX_STRENGTH, "more hits glow more, up to a limit")


func test_the_vignette_never_passes_its_limit() -> void:
	var vignette := _hud_with_player_two().get_vignette()
	for i in 12:
		_bus.player_stats_changed.emit(2, 80 - i, 100, 10.0, 100.0)
	check(vignette.strength <= vignette.MAX_STRENGTH, "the vignette never passes its limit")


func test_the_vignette_fades_out() -> void:
	var vignette := _hud_with_player_two().get_vignette()
	_bus.player_stats_changed.emit(2, 60, 100, 10.0, 100.0)
	for i in 30:
		vignette.step(0.0625)
	check(not vignette.visible and vignette.strength == 0.0, "the vignette fades out")


func test_a_heal_shows_no_vignette() -> void:
	var vignette := _hud_with_player_two().get_vignette()
	_bus.player_stats_changed.emit(2, 50, 100, 10.0, 100.0)
	for i in 30:
		vignette.step(0.0625)
	_bus.player_stats_changed.emit(2, 80, 100, 10.0, 100.0)
	check(not vignette.visible, "a revive or heal shows no vignette")


func test_a_run_ending_clears_the_vignette() -> void:
	var vignette := _hud_with_player_two().get_vignette()
	_bus.player_stats_changed.emit(2, 10, 100, 10.0, 100.0)
	_bus.run_ended.emit(false)
	check(not vignette.visible, "a run ending clears the vignette")


func test_the_vignette_takes_no_input() -> void:
	check_equal(_make_hud().get_vignette().mouse_filter, Control.MOUSE_FILTER_IGNORE, "the vignette takes no input")


func test_four_wizards_under_fire_do_not_keep_the_vignette_at_its_limit() -> void:
	var hud: HudScript = _make_hud()
	var vignette := hud.get_vignette()
	for player in 4:
		_bus.player_joined.emit(player)
		_bus.player_stats_changed.emit(player, 100, 100, 5.0, 100.0)
	_bus.room_entered.emit(&"arena_01", 0)
	# Eight seconds of a fight: each wizard loses 10 of 100 health every half second.
	var peak: float = 0.0
	for tick in 64:
		var player: int = tick % 4
		_bus.player_stats_changed.emit(player, 90, 100, 5.0, 100.0)
		_bus.player_stats_changed.emit(player, 100, 100, 5.0, 100.0)
		vignette.step(0.125)
		peak = maxf(peak, vignette.strength)
	check(peak < vignette.MAX_STRENGTH * 0.8, "four wizards under fire do not keep the vignette at its limit (peak %s)" % peak)


func test_a_small_hit_glows_less_than_a_big_one() -> void:
	var vignette := _make_hud().get_vignette()
	vignette.flash_hit(0, 0.05, 1)
	var small: float = vignette.strength
	vignette.clear()
	vignette.flash_hit(0, 0.5, 1)
	check(small < vignette.strength, "a small hit glows less than a big one")


func test_the_vignette_can_be_turned_off() -> void:
	var vignette := _make_hud().get_vignette()
	vignette.enabled = false
	vignette.flash_hit(0, 0.5, 1)
	check(not vignette.visible and vignette.strength == 0.0, "the vignette can be turned off")


# --- The ONLINE word (online lobby L5c) --------------------------------------------------------
# While this machine plays with others, a seat in the game with no real device of this machine on
# it says ONLINE; a seat played here, a bot's seat offline and every seat once nothing is online
# say nothing.


## A HUD in the hub with seat 0 on this machine's keyboard and seat 1 on a virtual device (a bot
## offline, another machine online), online when `online`.
func _seats_hud(online: bool) -> HudScript:
	var hud: HudScript = _make_hud()
	var input := own(InputManagerScript.new()) as InputManagerScript
	hud.input = input
	input.join(InputManagerScript.KEYBOARD)
	input.add_virtual_device(1)
	_bus.player_joined.emit(0)
	_bus.player_joined.emit(1)
	_bus.room_entered.emit(&"hub", 0)
	if online:
		_bus.online_changed.emit(EventsScript.ONLINE_PLAYING, "", &"", {})
	hud.poll()
	return hud


func test_offline_no_seat_is_marked_online() -> void:
	var hud: HudScript = _seats_hud(false)
	check(hud.get_panel(0).seat_text() == "" and hud.get_panel(1).seat_text() == "", "offline no seat is marked, a virtual device's (a bot's) neither")


func test_online_the_seat_this_machine_plays_says_nothing() -> void:
	check_equal(_seats_hud(true).get_panel(0).seat_text(), "", "playing online, the seat this machine's keyboard holds says nothing")


func test_online_the_seat_another_machine_plays_says_online() -> void:
	check_equal(_seats_hud(true).get_panel(1).seat_text(), PlayerPanelScript.ONLINE_TEXT, "the seat another machine plays says ONLINE")


func test_online_a_seat_nobody_plays_says_nothing() -> void:
	check_equal(_seats_hud(true).get_panel(2).seat_text(), "", "a seat nobody plays says nothing")


func test_a_pad_of_this_machine_taking_the_seat_removes_the_word() -> void:
	# No event says so: the HUD sees it when it polls.
	var hud: HudScript = _seats_hud(true)
	hud.input.leave(1)
	hud.input.join_as(7, 1)
	hud.poll()
	check_equal(hud.get_panel(1).seat_text(), "", "a pad of this machine takes the seat: the word goes")


func test_the_word_comes_back_with_the_other_machine() -> void:
	var hud: HudScript = _seats_hud(true)
	hud.input.leave(1)
	hud.input.join_as(7, 1)
	hud.poll()
	hud.input.leave(1)
	hud.input.add_virtual_device(1)
	hud.poll()
	check_equal(hud.get_panel(1).seat_text(), PlayerPanelScript.ONLINE_TEXT, "the word comes back with the other machine")


func test_once_online_play_ends_no_seat_is_marked() -> void:
	var hud: HudScript = _seats_hud(true)
	_bus.online_changed.emit(EventsScript.ONLINE_ENDED, "", &"", {})
	hud.poll()
	check_equal(hud.get_panel(1).seat_text(), "", "the other machines gone: nothing is marked")


# --- The MENU word from UI focus ---------------------------------------------------------------


func test_an_overlay_open_for_a_player_shows_menu_on_their_panel() -> void:
	var hud: HudScript = _make_hud()
	_focus.opened.emit(1)
	check_equal(hud.get_panel(1).status_text(), "MENU", "an overlay open for player 1 shows MENU on panel 1")


func test_an_overlay_open_for_one_player_leaves_the_other_panels_blank() -> void:
	var hud: HudScript = _make_hud()
	_focus.opened.emit(1)
	check(hud.get_panel(0).status_text() == "" and hud.get_panel(2).status_text() == "", "the other panels show nothing")


func test_the_overlay_closing_clears_the_menu_word() -> void:
	var hud: HudScript = _make_hud()
	_focus.opened.emit(1)
	_focus.closed.emit(1)
	check_equal(hud.get_panel(1).status_text(), "", "closing clears the word")


# --- Bad indices -------------------------------------------------------------------------------


func test_get_panel_gives_null_for_a_bad_index() -> void:
	var hud: HudScript = _make_hud()
	check(hud.get_panel(4) == null and hud.get_panel(-1) == null, "get_panel gives null for a bad index")


func test_events_for_a_bad_index_change_no_panel() -> void:
	var hud: HudScript = _make_hud()
	_bus.player_joined.emit(7)
	_bus.player_left.emit(-1)
	_bus.player_stats_changed.emit(4, 1, 100, 1.0, 100.0)
	_bus.player_stats_changed.emit(-1, 1, 100, 1.0, 100.0)
	for player in 4:
		check_equal(hud.get_panel(player).status_text(), "", "panel %d changed for a bad index" % player)
		check(not hud.get_panel(player).visible, "panel %d shows for a bad index" % player)


# --- What the panel scripts may do -------------------------------------------------------------


## The panel scripts' source, the player intents they may send taken out.
func _panel_source() -> String:
	var source := FileAccess.get_file_as_string("res://hud/panels/panels.gd")
	source = source.replace("events.spell_swap_requested.emit(player)", "")
	source = source.replace("events.run_requested.emit(player)", "")
	source = source.replace("events.online_open_requested.emit(player)", "")
	source = source.replace("events.item_take_requested.emit(player, _item_hints.item_of(player))", "")
	source = source.replace("events.shelf_buy_requested.emit(player, _item_hints.shelf_of(player))", "")
	source = source.replace("events.quick_use_requested.emit(player, slot)", "")
	source += FileAccess.get_file_as_string("res://hud/panels/quick_slots.gd")
	source += FileAccess.get_file_as_string("res://hud/panels/map_legend.gd")
	source += FileAccess.get_file_as_string("res://hud/widgets/quick_cross.gd")
	source += FileAccess.get_file_as_string("res://hud/panels/item_hints.gd")
	source += FileAccess.get_file_as_string("res://hud/widgets/item_hint.gd")
	source += FileAccess.get_file_as_string("res://hud/panels/player_panel/player_panel.gd")
	source += FileAccess.get_file_as_string("res://hud/panels/player_panel/staff_row.gd")
	return source


## The panels send no event but the player intents `spell_swap_requested` (a `swap` press) and
## `run_requested` (A on the hub's lit stone), `item_take_requested` (A by an item),
## `shelf_buy_requested` (A at a shop's item) and
## `online_open_requested` (A on the altar; all tested in test_pause_menu.gd); the corner panel
## itself sends nothing. (Tested in test_quick.gd.)
func test_the_panel_scripts_send_only_the_player_intents() -> void:
	# A staff row's own `live_changed` (its live parts over the cached picture) is no bus event.
	check(not _panel_source().replace("live_changed.emit(", "").contains(".emit("), "the panel scripts send no events but the swap request and A on the hub's lit stone, an item or its altar")


func test_the_panel_scripts_read_no_input() -> void:
	check(not _panel_source().contains("Input."), "the panel scripts read no input")


func test_the_health_line_keeps_its_length_when_a_word_shows() -> void:
	var panel: PlayerPanelScript = _panel()
	panel.set_stats(100, 100)
	await process_frame
	var width: float = panel.health_line().size.x
	panel.set_menu_open(true)
	await process_frame
	check_equal(panel.status_text(), "MENU", "the word shows")
	check_equal(panel.health_line().size.x, width, "and the line keeps its length (Smooth: no jump)")
	check(not (panel.find_child("HealthValue", true, false) as Label).visible, "the word is in the number's place")
	panel.set_stats(0, 100)
	await process_frame
	check_equal(panel.status_text(), "DOWN", "down")
	check_equal(panel.health_line().size.x, width, "the line keeps its length down too")


func test_a_new_body_hides_the_mana_lines_until_its_mana_comes() -> void:
	var hud: HudScript = _make_hud([0], true)
	var line: MeterLineScript = hud.get_panel(0).staff_row(1).mana_line()
	_bus.staff_mana_changed.emit(0, 1, 40.0, 80.0)
	check(line.visible and is_equal_approx(line.share(), 0.5), "the staff's mana shows")
	_bus.inventory_announced.emit(0, 7)
	check(not line.visible, "another body shown: the last body's mana is not shown for it")
	_bus.staff_mana_changed.emit(0, 1, 20.0, 80.0)
	check(line.visible and is_equal_approx(line.share(), 0.25), "the new body's mana shows when it comes")


## A seat that joined while the run could not be joined (the owner, 2026-11-19): its panel says WAIT
## in the health number's place and why under it, until it is let in.
func test_a_held_join_says_why_on_its_panel() -> void:
	var panel: PlayerPanelScript = _panel()
	await process_frame
	panel.set_join_held(true)
	check_equal(panel.status_text(), PlayerPanelScript.WAIT_TEXT, "WAIT in the number's place")
	var note := panel.find_child("JoinHeld", true, false) as Label
	check(note != null and note.visible and note.text.contains("start room"), "and why: the party left the start room")
	panel.set_join_held(false)
	check_equal(panel.status_text(), "", "let in: no word")
	check(not note.visible, "no note")
