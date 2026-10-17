extends SceneTree
## Tests for the per-player overlay in hud/panels: the `overlay` action opens
## and closes it for its owner only; only the owner's device works its controls
## (through core/ui_focus); it never pauses the game; the build button is a stub
## that sends `build_change_requested`; and, the point of it all, with one
## player's overlay open the other three wizards still move. Input goes through
## the real input manager's virtual devices.
##
## godot --headless --path . --script res://tests/hud/test_overlay.gd

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const HudScene := preload("res://hud/panels/panels.tscn")
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
	_test_owner_opens_and_closes()
	_test_overlay_looks_like_its_owner()
	_test_tap_within_one_frame_counts()
	_test_other_players_cannot_open_it()
	_test_player_without_device_cannot_open()
	_test_only_the_owner_works_the_controls()
	_test_resume_and_cancel_close()
	_test_build_button_is_a_stub()
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
	_bus.build_change_requested.connect(_on_build_change_requested)
	for index in count:
		_input.add_virtual_device(index)
		var player := PlayerScript.new()
		player.index = index
		player.input = _input
		player.events = _bus
		player._ready()
		_players.append(player)
	_hud = HudScene.instantiate() as HudScript
	_hud.events = _bus
	_hud.ui_focus = _focus
	_hud.input = _input
	root.add_child(_hud)


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


func _on_build_change_requested(player: int, slot: int, component_id: StringName) -> void:
	_requests.append([player, slot, component_id])


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
	# Layout is not computed before a frame, so check sizes, not rectangles: an
	# overlay sits beside its corner panel inside its own quarter of the 640x360
	# view, so four of them never overlap or leave the screen.
	for player in 4:
		var size: Vector2 = _overlay(player).get_combined_minimum_size()
		var panel_height: float = _hud.get_panel(player).get_combined_minimum_size().y
		_check(size.x <= 312.0, "overlay %d fits its quarter's width, got %s" % [player, size])
		_check(size.y + panel_height + 12.0 <= 180.0, "overlay %d and its panel fit its quarter's height, got %s" % [player, size])


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
		_tap(player, &"cast")
		_tap(player, &"dodge")
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
	_tap(0, &"cast")
	_frame()
	_check(not _overlay(0).is_open(), "cast on Resume closes the overlay")
	_tap(0, &"overlay")
	_frame()
	_check(_overlay(0).is_open(), "it opens again")
	_tap(0, &"dodge")
	_frame()
	_check(not _overlay(0).is_open(), "dodge (cancel) closes the overlay")


func _test_build_button_is_a_stub() -> void:
	_setup(4)
	_tap(3, &"overlay")
	_frame()
	_tap(3, &"move_down")
	_frame()
	_tap(3, &"cast")
	_frame()
	_check(_requests.size() == 1, "the build button sends exactly one request, got %d" % _requests.size())
	if _requests.size() == 1:
		var request: Array = _requests[0]
		_check(request[0] == 3, "the request names its owner (player index 3)")
		_check(request[1] == OverlayScript.STUB_SLOT and request[2] == OverlayScript.STUB_COMPONENT, "the stub asks for slot %d and component %s" % [OverlayScript.STUB_SLOT, OverlayScript.STUB_COMPONENT])
	_check(_overlay(3).is_open(), "the overlay stays open after the stub request")


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
	_tap(2, &"dodge")
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
