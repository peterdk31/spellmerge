extends SceneTree
## Tests for the per-player overlay in hud/panels: the `overlay` action opens
## and closes it for its owner only; only the owner's device works its controls
## (through core/ui_focus); it never pauses the game; the build button opens the
## player's builder (tested in test_builder.gd); and, the point of it all, with one
## player's overlay open the other three wizards still move. Input goes through
## the real input manager's virtual devices.
##
## godot --headless --path . --script res://tests/hud/test_overlay.gd

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
## Loaded when needed, not preloaded: this scene is also the "Hud" autoload, and
## preloading it here makes the autoload's own load fail at start (cyclic resource).
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
const HudScript := preload("res://hud/panels/panels.gd")
const OverlayScript := preload("res://hud/panels/overlay/overlay.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")

const STEP: float = 0.0625

var _failures: Array[String] = []
var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _hud: HudScript
var _players: Array[PlayerScript] = []
var _requests: Array[Array] = []


func _initialize() -> void:
	await process_frame
	_test_owner_opens_and_closes()
	_test_overlay_looks_like_its_owner()
	await _test_overlays_do_not_overlap()
	_test_no_overlay_outside_a_room()
	_test_overlay_closes_when_the_room_ends()
	_test_downed_player_cannot_open()
	_test_tap_within_one_frame_counts()
	_test_other_players_cannot_open_it()
	_test_player_without_device_cannot_open()
	_test_only_the_owner_works_the_controls()
	_test_resume_and_cancel_close()
	_test_build_button_opens_the_builder()
	_test_focus_is_marked_with_text()
	_test_game_is_never_paused()
	_test_others_still_move()
	_test_all_four_open_at_once()
	_test_leaving_closes_the_overlay()
	_test_reopen_after_close()
	_test_bad_index()
	_teardown()
	if _failures.is_empty():
		print("TEST OK: hud/panels overlay")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _setup(count: int) -> void:
	_teardown()
	_bus = EventsScript.new()
	_input = InputManagerScript.new()
	_input.events = _bus
	_focus = UIFocusScript.new()
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	_bus.staff_change_requested.connect(_on_staff_change_requested)
	for index in count:
		_input.add_virtual_device(index)
		var player := PlayerScript.new()
		player.index = index
		player.input = _input
		player.events = _bus
		player._ready()
		_players.append(player)
	_hud = (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	_hud.events = _bus
	_hud.ui_focus = _focus
	_hud.input = _input
	root.add_child(_hud)
	for index in count:
		_bus.player_joined.emit(index)
	_bus.room_entered.emit(&"test_room")


func _teardown() -> void:
	paused = false
	for player in _players:
		player.free()
	_players.clear()
	_requests.clear()
	for node: Node in [_hud, _focus, _input, _bus]:
		if node != null:
			node.free()
	_hud = null
	_focus = null
	_input = null
	_bus = null


func _on_staff_change_requested(player: int, staff: int, slot: int, card_id: StringName) -> void:
	_requests.append([player, slot, card_id, staff])


func _tap(player: int, action: StringName) -> void:
	_input.send_virtual(player, action, 1.0)
	_input.send_virtual(player, action, 0.0)


## One frame: the HUD reads the overlay action, UIFocus reads the controls, and
## every wizard takes a step.
func _frame() -> void:
	_hud.poll()
	_focus.poll()
	for player in _players:
		player.step(STEP)


func _overlay(player: int) -> OverlayScript:
	return _hud.get_overlay(player)


# --- Tests ------------------------------------------------------------------

func _test_owner_opens_and_closes() -> void:
	_setup(2)
	_frame()
	_check(not _overlay(0).visible and not _overlay(0).is_open(), "an overlay starts closed and hidden")
	_tap(0, &"overlay")
	_frame()
	_check(_overlay(0).is_open() and _overlay(0).visible, "the overlay action opens the overlay")
	_check(_focus.is_open(0), "an open overlay is a UIFocus panel for its owner")
	_check(_input.is_captured(0), "the owner's gameplay input is captured while the overlay is open")
	_check(not _overlay(1).is_open() and not _input.is_captured(1), "player 2 is not affected")
	_tap(0, &"overlay")
	_frame()
	_check(not _overlay(0).is_open() and not _overlay(0).visible, "the overlay action closes it again")
	_check(not _focus.is_open(0) and not _input.is_captured(0), "closing frees the owner's input")


func _test_overlay_looks_like_its_owner() -> void:
	_setup(4)
	for player in 4:
		var overlay: OverlayScript = _overlay(player)
		_check(overlay.theme_type_variation == StringName("PlayerPanel%d" % (player + 1)), "overlay %d uses its player's panel look" % player)
		var title := overlay.get_node("Rows/Title") as Label
		_check(title.text == "P%d MENU" % (player + 1), "overlay %d is titled with its player and the word MENU" % player)


## The real rectangles after a layout pass, at 640x360 with all four overlays
## shown: each is on screen, clear of its own panel and of every other panel and
## overlay. (Only the geometry is checked; how it looks has not been seen.)
func _test_overlays_do_not_overlap() -> void:
	_setup(4)
	root.size = Vector2i(640, 360)
	for player in 4:
		_overlay(player).visible = true
	await process_frame
	await process_frame
	var screen := Rect2(0, 0, 640, 360)
	var rects: Array[Rect2] = []
	var names: Array[String] = []
	for player in 4:
		rects.append(_hud.get_panel(player).get_global_rect())
		names.append("panel %d" % (player + 1))
		rects.append(_overlay(player).get_global_rect())
		names.append("overlay %d" % (player + 1))
	for i in rects.size():
		_check(rects[i].size.x > 0.0 and rects[i].size.y > 0.0, "%s has a size after layout, got %s" % [names[i], rects[i]])
		_check(screen.encloses(rects[i]), "%s is inside the 640x360 view, got %s" % [names[i], rects[i]])
		for j in range(i + 1, rects.size()):
			_check(not rects[i].intersects(rects[j]), "%s and %s do not overlap, got %s and %s" % [names[i], names[j], rects[i], rects[j]])


func _test_no_overlay_outside_a_room() -> void:
	_setup(2)
	_bus.run_started.emit(2)
	_tap(0, &"overlay")
	_frame()
	_check(not _overlay(0).is_open() and not _overlay(0).visible, "the overlay action does nothing before a room is entered")
	_check(not _input.is_captured(0) and not _focus.is_open(0), "and the player's input is not captured")
	_tap(0, &"cast_a")
	_frame()
	_check(not _input.is_captured(0), "so the menu's buttons keep getting cast")
	_bus.room_entered.emit(&"test_room")
	_frame()
	_check(not _overlay(0).is_open(), "a press made outside a room is not remembered")
	_tap(0, &"overlay")
	_frame()
	_check(_overlay(0).is_open(), "inside a room the overlay opens")


func _test_overlay_closes_when_the_room_ends() -> void:
	for ending in ["run_ended", "run_started"]:
		_setup(2)
		_tap(0, &"overlay")
		_tap(1, &"overlay")
		_frame()
		_check(_overlay(0).is_open() and _overlay(1).is_open(), "%s: both overlays are open" % ending)
		if ending == "run_ended":
			_bus.run_ended.emit(false)
		else:
			_bus.run_started.emit(2)
		for player in 2:
			_check(not _overlay(player).is_open() and not _overlay(player).visible, "%s: overlay %d is closed and hidden" % [ending, player])
			_check(not _input.is_captured(player) and not _focus.is_open(player), "%s: player %d's input is free" % [ending, player])
		_tap(0, &"overlay")
		_frame()
		_check(not _overlay(0).is_open(), "%s: no overlay opens until the next room" % ending)


func _test_downed_player_cannot_open() -> void:
	_setup(2)
	_bus.player_stats_changed.emit(0, 0, 100, 50.0, 50.0)
	_tap(0, &"overlay")
	_frame()
	_check(not _overlay(0).is_open() and not _input.is_captured(0), "a downed player cannot open the overlay")
	_check(_hud.get_panel(0).status_text() == "DOWN", "and their panel says DOWN")
	_tap(1, &"overlay")
	_frame()
	_check(_overlay(1).is_open(), "a teammate can still open theirs")
	_bus.player_stats_changed.emit(1, 0, 100, 50.0, 50.0)
	_check(not _overlay(1).is_open() and not _input.is_captured(1), "an open overlay closes when its owner goes down")
	_check(_hud.get_panel(1).status_text() == "DOWN", "and DOWN shows, not MENU")
	_bus.player_stats_changed.emit(0, 50, 100, 50.0, 50.0)
	_tap(0, &"overlay")
	_frame()
	_check(_overlay(0).is_open(), "after a revive the overlay opens again")


func _test_tap_within_one_frame_counts() -> void:
	_setup(1)
	_tap(0, &"overlay")
	_frame()
	_check(_overlay(0).is_open(), "a tap released before the frame still opens the overlay")
	_tap(0, &"overlay")
	_tap(0, &"overlay")
	_frame()
	_check(not _overlay(0).is_open(), "two taps in one frame count as one toggle")


func _test_other_players_cannot_open_it() -> void:
	_setup(4)
	_tap(1, &"overlay")
	_frame()
	_check(_overlay(1).is_open(), "player 2 opens their own overlay")
	for player in [0, 2, 3]:
		_check(not _overlay(player).is_open(), "player 2's press does not open overlay %d" % player)
	# Player 1 pressing the overlay action does not close player 2's overlay.
	_tap(0, &"overlay")
	_frame()
	_check(_overlay(1).is_open(), "player 1's overlay action does not close player 2's overlay")


func _test_player_without_device_cannot_open() -> void:
	_setup(1)
	_overlay(2).toggle()
	_check(not _overlay(2).is_open() and not _overlay(2).visible, "a slot with no device cannot open its overlay")
	_check(not _focus.is_open(2), "and takes no UIFocus panel")


func _test_only_the_owner_works_the_controls() -> void:
	_setup(4)
	_tap(2, &"overlay")
	_frame()
	_check(_focus.focused(2) == _overlay(2).get_node("Rows/Resume"), "the first control (Resume) is focused")
	for player in [0, 1, 3]:
		_tap(player, &"move_down")
		_tap(player, &"cast_a")
		_tap(player, &"cast_b")
	_frame()
	_check(_overlay(2).is_open(), "the others' cast and dodge do not close player 3's overlay")
	_check(_focus.focused(2) == _overlay(2).get_node("Rows/Resume"), "the others' movement does not move player 3's focus")
	_check(_requests.is_empty(), "the others' buttons send no request")
	_tap(2, &"move_down")
	_frame()
	_check(_focus.focused(2) == _overlay(2).get_node("Rows/Build"), "the owner's move_down moves their focus")


func _test_resume_and_cancel_close() -> void:
	_setup(2)
	_tap(0, &"overlay")
	_frame()
	_tap(0, &"cast_a")
	_frame()
	_check(not _overlay(0).is_open(), "cast on Resume closes the overlay")
	_tap(0, &"overlay")
	_frame()
	_check(_overlay(0).is_open(), "it opens again")
	_tap(0, &"cast_b")
	_frame()
	_check(not _overlay(0).is_open(), "dodge (cancel) closes the overlay")


func _test_build_button_opens_the_builder() -> void:
	_setup(4)
	_tap(3, &"overlay")
	_frame()
	_tap(3, &"move_down")
	_frame()
	_tap(3, &"cast_a")
	_frame()
	_check(_requests.is_empty(), "the build button sends no build request itself, got %d" % _requests.size())
	_check(_hud.get_builder(3).is_open(), "the build button opens the owner's builder")
	_check(not _overlay(3).is_open() and not _overlay(3).visible, "which takes the place of the overlay")
	_check(_focus.is_open(3) and _input.is_captured(3), "and the owner's focus and input stay captured")
	for player in 3:
		_check(not _hud.get_builder(player).is_open(), "player %d's builder stays closed" % (player + 1))


func _test_focus_is_marked_with_text() -> void:
	_setup(1)
	var resume := _overlay(0).get_node("Rows/Resume") as Button
	var build := _overlay(0).get_node("Rows/Build") as Button
	_tap(0, &"overlay")
	_frame()
	_check(resume.text.begins_with(OverlayScript.FOCUS_MARK) and not build.text.begins_with(OverlayScript.FOCUS_MARK), "the focused control is marked with text, not colour alone")
	_tap(0, &"move_down")
	_frame()
	_check(build.text.begins_with(OverlayScript.FOCUS_MARK) and not resume.text.begins_with(OverlayScript.FOCUS_MARK), "the mark follows the focus")


func _test_game_is_never_paused() -> void:
	_setup(4)
	for player in 4:
		_tap(player, &"overlay")
	_frame()
	_check(not paused, "four open overlays do not pause the tree")
	_check(Engine.time_scale == 1.0, "and do not change the time scale")


func _test_others_still_move() -> void:
	_setup(4)
	for player in 4:
		_input.send_virtual(player, &"move_right", 1.0)
	_frame()
	for player in 4:
		_check(_players[player].velocity.x == PlayerScript.MOVE_SPEED, "before any overlay, player %d walks" % (player + 1))
	_tap(1, &"overlay")
	var start: Array[Vector2] = []
	for player in 4:
		start.append(_players[player].position)
	for i in 8:
		_frame()
		for player in 4:
			_players[player].position += _players[player].velocity * STEP
	_check(_overlay(1).is_open(), "player 2's overlay is open")
	for player in [0, 2, 3]:
		_check(_players[player].velocity.x == PlayerScript.MOVE_SPEED, "with player 2's overlay open, player %d still walks" % (player + 1))
		_check(_players[player].position.x > start[player].x, "and player %d has moved" % (player + 1))
	_check(_players[1].velocity == Vector2.ZERO, "player 2, in the overlay, stands still")
	_check(_players[1].position == start[1], "and has not moved")
	# Closing gives the key back (it is still held).
	_tap(1, &"overlay")
	_frame()
	_check(_players[1].velocity.x == PlayerScript.MOVE_SPEED, "after closing, player 2 walks again with the key still held")


func _test_all_four_open_at_once() -> void:
	_setup(4)
	for player in 4:
		_tap(player, &"overlay")
	_frame()
	for player in 4:
		_check(_overlay(player).is_open() and _input.is_captured(player), "overlay %d is open with all four open" % player)
	_tap(0, &"overlay")
	_tap(2, &"cast_b")
	_frame()
	_check(not _overlay(0).is_open() and not _overlay(2).is_open(), "closing two leaves two")
	_check(_overlay(1).is_open() and _overlay(3).is_open(), "the other two stay open")


func _test_leaving_closes_the_overlay() -> void:
	_setup(2)
	_tap(1, &"overlay")
	_frame()
	_check(_overlay(1).is_open(), "player 2's overlay is open")
	_input.leave(1)
	_frame()
	_check(not _overlay(1).is_open() and not _overlay(1).visible, "when the device leaves the overlay closes")
	_tap(1, &"overlay")
	_frame()
	_check(not _overlay(1).is_open(), "a player with no device cannot reopen it")


func _test_reopen_after_close() -> void:
	_setup(1)
	for round in 3:
		_tap(0, &"overlay")
		_frame()
		_check(_overlay(0).is_open(), "round %d: opens" % round)
		_tap(0, &"overlay")
		_frame()
		_check(not _overlay(0).is_open(), "round %d: closes" % round)


func _test_bad_index() -> void:
	_setup(1)
	_check(_hud.get_overlay(-1) == null and _hud.get_overlay(4) == null, "get_overlay answers null for a bad index")
