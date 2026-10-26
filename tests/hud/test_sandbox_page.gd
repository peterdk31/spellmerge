extends SceneTree
## Tests for the sandbox page (hud/menus/sandbox, staffs B7): the overlay shows "Sandbox" only
## while the run is a sandbox; it opens that player's page in the overlay's place; only the
## owner works it; "Imp wave" and "Reset dummies" send `sandbox_action_requested` and keep the
## page open; "Back" and `cast_b` go back to the overlay; the `overlay` action closes it; the page
## closes when the sandbox ends; and four pages open at once never overlap. Input goes through
## the real input manager's virtual devices.
##
## godot --headless --path . --script res://tests/hud/test_sandbox_page.gd

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
## Loaded when needed, not preloaded: this scene is also the "Hud" autoload (see test_overlay.gd).
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
const HudScript := preload("res://hud/panels/panels.gd")
const OverlayScript := preload("res://hud/panels/overlay/overlay.gd")
const PageScript := preload("res://hud/menus/sandbox/sandbox_page.gd")

var _failures: Array[String] = []
var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _hud: HudScript
var _actions: Array[Array] = []


func _initialize() -> void:
	await process_frame
	_test_the_entry_shows_only_in_the_sandbox()
	_test_the_entry_opens_the_page()
	_test_actions_are_sent_and_the_page_stays()
	_test_only_the_owner_works_it()
	_test_back_and_cancel_go_back_to_the_overlay()
	_test_the_overlay_action_closes_it()
	_test_leaving_the_sandbox_closes_it()
	await _test_four_pages_fit_apart()
	_teardown()
	if _failures.is_empty():
		print("TEST OK: hud/menus/sandbox page")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _setup(count: int, sandbox: bool = true) -> void:
	_teardown()
	_bus = EventsScript.new()
	_input = InputManagerScript.new()
	_input.events = _bus
	_focus = UIFocusScript.new()
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	_bus.sandbox_action_requested.connect(func(player: int, action: StringName) -> void: _actions.append([player, action]))
	for index in count:
		_input.add_virtual_device(index)
	_hud = (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	_hud.events = _bus
	_hud.ui_focus = _focus
	_hud.input = _input
	root.add_child(_hud)
	for index in count:
		_bus.player_joined.emit(index)
	_bus.room_entered.emit(&"sandbox")
	_bus.sandbox_changed.emit(sandbox)


func _teardown() -> void:
	_actions.clear()
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


func _overlay(player: int) -> OverlayScript:
	return _hud.get_overlay(player)


func _page(player: int) -> PageScript:
	return _hud.get_sandbox_page(player)


## Open `player`'s overlay and move to its "Sandbox" line (Resume, Build, Sandbox).
func _to_sandbox_line(player: int) -> void:
	_tap(player, &"overlay")
	_frame()
	_tap(player, &"move_down")
	_frame()
	_tap(player, &"move_down")
	_frame()


func _open_page(player: int) -> void:
	_to_sandbox_line(player)
	_tap(player, &"cast_a")
	_frame()


## Move `player`'s page focus to button `at` (0 Imp wave, 1 Reset dummies, 2 Back) and press it.
func _press(player: int, at: int) -> void:
	_focus.focus(player, _page(player).buttons()[at])
	_tap(player, &"cast_a")
	_frame()


# --- Tests ------------------------------------------------------------------

func _test_the_entry_shows_only_in_the_sandbox() -> void:
	_setup(1, false)
	_check(not _overlay(0).sandbox_button().visible, "out of the sandbox the overlay has no Sandbox line")
	_bus.sandbox_changed.emit(true)
	_check(_overlay(0).sandbox_button().visible, "in the sandbox it has one")
	_bus.sandbox_changed.emit(false)
	_check(not _overlay(0).sandbox_button().visible, "and loses it when the sandbox ends")


func _test_the_entry_opens_the_page() -> void:
	_setup(2)
	_to_sandbox_line(1)
	_check(_focus.focused(1) == _overlay(1).sandbox_button(), "the Sandbox line is reached with the d-pad")
	_tap(1, &"cast_a")
	_frame()
	_check(_page(1).is_open() and _page(1).visible, "Sandbox opens the page")
	_check(not _overlay(1).is_open() and not _overlay(1).visible, "the overlay gives way to it")
	_check(not _page(0).is_open(), "the other player's page stays shut")
	_check(_page(1).buttons()[0].text.begins_with("> "), "the focus is marked with text")
	# P2's corner is the top right: both hang from the same top edge and the same right edge.
	var page: Rect2 = _page(1).get_global_rect()
	var overlay: Rect2 = _overlay(1).get_global_rect()
	_check(is_equal_approx(page.position.y, overlay.position.y) and is_equal_approx(page.end.x, overlay.end.x), "the page sits in the overlay's place: %s vs %s" % [page, overlay])


func _test_actions_are_sent_and_the_page_stays() -> void:
	_setup(2)
	_open_page(1)
	_press(1, 0)
	_press(1, 0)
	_press(1, 1)
	_check(_actions == [[1, &"imp_wave"], [1, &"imp_wave"], [1, &"reset_dummies"]], "the actions go out with the owner's index, got %s" % [_actions])
	_check(_page(1).is_open(), "the page stays open for another press")


func _test_only_the_owner_works_it() -> void:
	_setup(2)
	_open_page(0)
	_tap(1, &"cast_a")
	_frame()
	_check(_actions.is_empty(), "player 2's button does nothing on player 1's page")
	_check(_page(0).is_open(), "and does not close it")


func _test_back_and_cancel_go_back_to_the_overlay() -> void:
	_setup(1)
	_open_page(0)
	_press(0, 2)
	_check(not _page(0).is_open() and not _page(0).visible, "Back closes the page")
	_check(_overlay(0).is_open(), "and opens the overlay again")
	_tap(0, &"cast_a")  # Resume: closes the overlay.
	_frame()
	_open_page(0)
	_tap(0, &"cast_b")
	_frame()
	_check(not _page(0).is_open() and _overlay(0).is_open(), "cast_b goes back to the overlay too")


func _test_the_overlay_action_closes_it() -> void:
	_setup(1)
	_open_page(0)
	_tap(0, &"overlay")
	_frame()
	_check(not _page(0).is_open() and not _overlay(0).is_open(), "the overlay action closes the page, not back to the overlay")


func _test_leaving_the_sandbox_closes_it() -> void:
	_setup(1)
	_open_page(0)
	_bus.sandbox_changed.emit(false)
	_check(not _page(0).is_open() and not _page(0).visible, "the page closes when the sandbox ends")


func _test_four_pages_fit_apart() -> void:
	_setup(4)
	root.size = Vector2i(640, 360)
	for player in 4:
		_open_page(player)
	await process_frame
	var screen := Rect2(Vector2.ZERO, Vector2(640, 360))
	for player in 4:
		var rect: Rect2 = _page(player).get_global_rect()
		_check(_page(player).is_open(), "page %d is open" % (player + 1))
		_check(screen.encloses(rect), "page %d fits the 640x360 view: %s" % [player + 1, rect])
		_check(not rect.intersects(_hud.get_panel(player).get_global_rect()), "page %d leaves its corner panel clear" % (player + 1))
		for other in range(player + 1, 4):
			_check(not rect.intersects(_page(other).get_global_rect()), "pages %d and %d do not overlap" % [player + 1, other + 1])
