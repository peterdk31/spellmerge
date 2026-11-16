extends "res://tests/support/suite.gd"
## Tests for core/ui_focus, one rule per test: a panel takes input only from its owner, with four
## owners at once, and with one player's panel open while another's is not; an open panel
## captures its owner's gameplay input; disabled, hidden and freed controls are skipped; and the
## extras (alternate, paging, a navigator, a jump). Each test gets a UIFocus, an input manager and
## a bus of its own (never the autoloads), four players on the manager's virtual devices and four
## panels of three buttons (`buttons[player][i]`); input goes through the real virtual devices.

const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

var bus: EventsScript
var input: InputManagerScript
var focus: UIFocusScript
## Every signal as [name, player, control index or -1], in order.
var events_seen: Array = []
## Four panels of three buttons each; buttons[player][i].
var buttons: Array[Array] = []
## Every `alternate` as [player, control index] and `paged` as [player, step] (`_listen_to_extras`).
var alternates: Array = []
var pages: Array = []
## The navigator's questions as [control index, direction] (`_row_navigator`).
var asked: Array = []


func before_each() -> void:
	bus = EventsScript.new()
	input = InputManagerScript.new()
	input.events = bus
	focus = UIFocusScript.new()
	# Freed after the test in this order: the panel service, the input, the bus.
	own(focus)
	own(input)
	own(bus)
	focus.input = input
	focus.events = bus
	focus._ready()
	events_seen = []
	buttons = []
	alternates = []
	pages = []
	asked = []
	for player in 4:
		var row: Array = []
		for i in 3:
			row.append(own(Button.new()))
		buttons.append(row)
	focus.opened.connect(func(p: int) -> void: events_seen.append(["opened", p, -1]))
	focus.closed.connect(func(p: int) -> void: events_seen.append(["closed", p, -1]))
	focus.focus_changed.connect(func(p: int, c: Control) -> void: events_seen.append(["focus", p, buttons[p].find(c)]))
	focus.activated.connect(func(p: int, c: Control) -> void: events_seen.append(["activated", p, buttons[p].find(c)]))
	focus.cancelled.connect(func(p: int) -> void: events_seen.append(["cancelled", p, -1]))
	for player in 4:
		input.add_virtual_device(player)


func _panel(player: int) -> Array[Control]:
	var controls: Array[Control] = []
	for button: Button in buttons[player]:
		controls.append(button)
	return controls


func _button(player: int, i: int) -> Button:
	return buttons[player][i] as Button


## Press and release `action` on the virtual device of `player` within one frame, then poll once:
## the tap must not be lost.
func _tap(player: int, action: StringName) -> void:
	input.send_virtual(player, action, 1.0)
	input.send_virtual(player, action, 0.0)
	focus.poll()


func _count(kind: String, player: int) -> int:
	var count: int = 0
	for entry: Array in events_seen:
		if entry[0] == kind and entry[1] == player:
			count += 1
	return count


func test_the_ui_focus_autoload_is_registered() -> void:
	var path: String = str(ProjectSettings.get_setting("autoload/UIFocus", ""))
	check_equal(path, "*res://core/ui_focus/ui_focus.gd", "autoload UIFocus is registered")


# --- Opening ----------------------------------------------------------------

func test_open_opens_the_panel() -> void:
	check(focus.open(2, _panel(2)), "open succeeds")
	check(focus.is_open(2), "the panel is open")


func test_open_focuses_the_first_control() -> void:
	focus.open(2, _panel(2))
	check(focus.focused(2) == _button(2, 0), "the first control is focused")


func test_open_sends_opened_then_focus_changed() -> void:
	focus.open(2, _panel(2))
	check_equal(events_seen, [["opened", 2, -1], ["focus", 2, 0]], "opened then focus_changed")


func test_open_leaves_the_other_panels_closed() -> void:
	focus.open(2, _panel(2))
	check(not focus.is_open(0), "other players' panels stay closed")
	check(focus.focused(0) == null, "a closed panel has no focus")


func test_an_empty_panel_does_not_open() -> void:
	check(not focus.open(0, [] as Array[Control]), "an empty panel does not open")
	check(not focus.is_open(0), "nothing opened")


func test_a_panel_outside_the_four_seats_does_not_open() -> void:
	check(not focus.open(4, _panel(0)), "player 4 does not exist")
	check(not focus.open(-1, _panel(0)), "player -1 does not exist")
	check(events_seen.is_empty(), "nothing opened: %s" % [events_seen])


func test_a_player_with_no_device_cannot_open_a_panel() -> void:
	input.leave(3)
	check(not focus.open(3, _panel(3)), "a player with no device cannot open a panel")
	check(not focus.is_open(3) and not input.is_captured(3), "nothing opened or captured")
	check(events_seen.is_empty(), "no signals for the refused panel: %s" % [events_seen])


func test_reopening_a_panel_closes_the_old_one_first() -> void:
	focus.open(0, _panel(0))
	events_seen.clear()
	check(focus.open(0, _panel(0)), "opening an open panel works")
	check_equal(events_seen, [["closed", 0, -1], ["opened", 0, -1], ["focus", 0, 0]], "closed for the old panel, then opened for the new")


func test_a_reopened_panels_owner_stays_captured() -> void:
	focus.open(0, _panel(0))
	focus.open(0, _panel(0))
	check(input.is_captured(0), "the player stays captured")


func test_close_says_whether_a_panel_was_open() -> void:
	focus.open(0, _panel(0))
	check(focus.close(0), "close returns true for an open panel")
	check(not focus.close(0), "close returns false for a closed panel")


func test_a_closed_panel_has_no_focus() -> void:
	focus.open(0, _panel(0))
	_tap(0, &"move_down")
	focus.close(0)
	check(focus.focused(0) == null, "no focus after close")


func test_a_closed_panel_does_not_activate() -> void:
	focus.open(0, _panel(0))
	focus.close(0)
	_tap(0, &"accept")
	check_equal(_count("activated", 0), 0, "a closed panel does not activate")


func test_reopening_starts_at_the_first_control() -> void:
	focus.open(0, _panel(0))
	_tap(0, &"move_down")
	focus.close(0)
	focus.open(0, _panel(0))
	check_equal(focus.focus_index(0), 0, "reopening starts at the first control")


func test_the_global_godot_focus_is_never_taken() -> void:
	var holder: Control = own(Control.new()) as Control
	root.add_child(holder)
	var button := Button.new()
	holder.add_child(button)
	var controls: Array[Control] = [button]
	focus.open(0, controls)
	check(root.gui_get_focus_owner() == null, "the global Godot focus is not used")


# --- Navigating -------------------------------------------------------------

func test_down_and_right_go_to_the_next_control() -> void:
	focus.open(0, _panel(0))
	_tap(0, &"move_down")
	check_equal(focus.focus_index(0), 1, "down goes to the next control")
	_tap(0, &"move_right")
	check_equal(focus.focus_index(0), 2, "right goes to the next control")


func test_next_wraps_round_to_the_first() -> void:
	focus.open(0, _panel(0))
	for i in 3:
		_tap(0, &"move_down")
	check_equal(focus.focus_index(0), 0, "next wraps round to the first")


func test_up_from_the_first_wraps_to_the_last() -> void:
	focus.open(0, _panel(0))
	_tap(0, &"move_up")
	check_equal(focus.focus_index(0), 2, "up from the first wraps to the last")


func test_left_goes_to_the_previous_control() -> void:
	focus.open(0, _panel(0))
	_tap(0, &"move_up")
	_tap(0, &"move_left")
	check_equal(focus.focus_index(0), 1, "left goes to the previous control")


func test_navigation_skips_a_disabled_control() -> void:
	_button(0, 1).disabled = true
	focus.open(0, _panel(0))
	_tap(0, &"move_down")
	check_equal(focus.focus_index(0), 2, "a disabled button is skipped")


func test_with_one_usable_control_focus_stays() -> void:
	_button(0, 1).disabled = true
	focus.open(0, _panel(0))
	_tap(0, &"move_down")
	_button(0, 0).visible = false
	_tap(0, &"move_down")
	check_equal(focus.focus_index(0), 2, "with one usable control (one disabled, one hidden), focus stays")


func test_open_focuses_the_first_usable_control() -> void:
	_button(1, 0).disabled = true
	focus.open(1, _panel(1))
	check_equal(focus.focus_index(1), 1, "the first usable control is focused on open")


func test_a_panel_with_nothing_usable_focuses_nothing() -> void:
	for button: Button in buttons[3]:
		button.disabled = true
	focus.open(3, _panel(3))
	check(focus.focused(3) == null, "nothing usable, nothing focused")
	_tap(3, &"move_down")
	_tap(3, &"move_up")
	check(focus.focused(3) == null, "moving with nothing usable does nothing")


func test_a_control_enabled_later_can_be_reached() -> void:
	for button: Button in buttons[3]:
		button.disabled = true
	focus.open(3, _panel(3))
	_button(3, 2).disabled = false
	_tap(3, &"move_up")
	check_equal(focus.focus_index(3), 2, "a control enabled later can be reached")


func test_a_held_direction_moves_one_step() -> void:
	focus.open(0, _panel(0))
	input.send_virtual(0, &"move_down")
	for _i in 5:
		focus.poll()
	check_equal(focus.focus_index(0), 1, "a held direction moves one step")


func test_a_second_press_moves_again() -> void:
	focus.open(0, _panel(0))
	input.send_virtual(0, &"move_down")
	focus.poll()
	input.send_virtual(0, &"move_down", 0.0)
	focus.poll()
	_tap(0, &"move_down")
	check_equal(focus.focus_index(0), 2, "a second press moves again")


func test_a_tap_released_before_the_poll_still_moves() -> void:
	focus.open(0, _panel(0))
	input.send_virtual(0, &"move_down")
	input.send_virtual(0, &"move_down", 0.0)
	focus.poll()
	check_equal(focus.focus_index(0), 1, "a tap released before the poll still moves focus")


func test_two_taps_in_two_frames_move_twice() -> void:
	focus.open(0, _panel(0))
	_tap(0, &"move_down")
	_tap(0, &"move_down")
	check_equal(focus.focus_index(0), 2, "two taps in two frames move twice")


func test_two_taps_in_one_frame_activate_twice() -> void:
	focus.open(0, _panel(0))
	input.send_virtual(0, &"accept")
	input.send_virtual(0, &"accept", 0.0)
	input.send_virtual(0, &"accept")
	input.send_virtual(0, &"accept", 0.0)
	focus.poll()
	check_equal(_count("activated", 0), 2, "two taps within one frame activate twice")


func test_a_button_held_when_opening_does_nothing() -> void:
	# The button that opened the panel is still held, and a direction too.
	input.send_virtual(0, &"accept")
	input.send_virtual(0, &"move_down")
	focus.open(0, _panel(0))
	focus.poll()
	check_equal(_count("activated", 0), 0, "a held cast does not activate on open")
	check_equal(focus.focus_index(0), 0, "a held direction does not move on open")


func test_after_releasing_a_button_held_when_opening_a_new_press_works() -> void:
	input.send_virtual(0, &"accept")
	focus.open(0, _panel(0))
	focus.poll()
	input.send_virtual(0, &"accept", 0.0)
	focus.poll()
	_tap(0, &"accept")
	check_equal(_count("activated", 0), 1, "after release a new press works")


# --- Activating and cancelling ----------------------------------------------

func test_accept_activates_the_focused_control_once() -> void:
	focus.open(1, _panel(1))
	_tap(1, &"move_down")
	_tap(1, &"accept")
	check_equal(_count("activated", 1), 1, "accept activates once")
	check(events_seen.has(["activated", 1, 1]), "it activates the focused control")


func test_back_cancels_once() -> void:
	focus.open(1, _panel(1))
	_tap(1, &"back")
	check_equal(_count("cancelled", 1), 1, "back cancels once")


func test_cancel_does_not_close_the_panel() -> void:
	focus.open(1, _panel(1))
	_tap(1, &"back")
	check(focus.is_open(1), "cancel does not close the panel by itself")


func test_a_control_disabled_after_getting_focus_is_not_activated() -> void:
	focus.open(0, _panel(0))
	_button(0, 0).disabled = true
	_tap(0, &"accept")
	check_equal(_count("activated", 0), 0, "a control disabled after getting focus is not activated")


func test_accept_on_a_disabled_focus_moves_focus_to_the_next_usable_control() -> void:
	focus.open(0, _panel(0))
	_button(0, 0).disabled = true
	_tap(0, &"accept")
	check_equal(focus.focus_index(0), 1, "focus moved to the next usable control")
	check(events_seen.has(["focus", 0, 1]), "focus_changed was sent for the move")


func test_the_focus_moved_off_a_disabled_control_can_be_activated() -> void:
	focus.open(0, _panel(0))
	_button(0, 0).disabled = true
	_tap(0, &"accept")
	_tap(0, &"accept")
	check(events_seen.has(["activated", 0, 1]), "the new focus can be activated")


func test_with_every_control_disabled_nothing_is_activated() -> void:
	focus.open(0, _panel(0))
	for button: Button in buttons[0]:
		button.disabled = true
	_tap(0, &"accept")
	check(focus.focused(0) == null and _count("activated", 0) == 0, "nothing usable, nothing activated")


func test_a_control_hidden_after_getting_focus_is_not_activated() -> void:
	focus.open(0, _panel(0))
	_tap(0, &"move_down")
	_button(0, 1).visible = false
	focus.activate(0)
	check_equal(_count("activated", 0), 0, "a control hidden after getting focus is not activated")


## Frees button `i` of `player`'s panel (the suite skips it after the test).
func _free_button(player: int, i: int) -> void:
	var gone: Button = buttons[player][i]
	buttons[player][i] = null
	gone.free()


func test_a_freed_control_is_not_returned() -> void:
	focus.open(0, _panel(0))
	_free_button(0, 0)
	check(focus.focused(0) == null, "a freed control is not returned")


func test_a_freed_control_is_not_activated() -> void:
	focus.open(0, _panel(0))
	_free_button(0, 0)
	focus.activate(0)
	check_equal(_count("activated", 0), 0, "a freed control is not activated")
	check_equal(focus.focus_index(0), 1, "focus moved off the freed control")


func test_navigation_skips_a_freed_control() -> void:
	focus.open(0, _panel(0))
	_free_button(0, 0)
	focus.activate(0)
	focus.poll()
	_tap(0, &"move_down")
	_tap(0, &"move_down")
	check_equal(focus.focus_index(0), 1, "navigation skips the freed control")


func test_a_panel_of_freed_controls_does_nothing() -> void:
	focus.open(1, _panel(1))
	for i in 3:
		_free_button(1, i)
	_tap(1, &"accept")
	check(focus.focused(1) == null and _count("activated", 1) == 0, "a panel of freed controls does nothing")


## Two buttons under `parent`, in a holder in the tree; the panel is opened on them with the parent
## hidden.
func _panel_under_a_hidden_parent() -> Control:
	var holder: Control = own(Control.new()) as Control
	root.add_child(holder)
	var parent := Control.new()
	holder.add_child(parent)
	var first := Button.new()
	var second := Button.new()
	parent.add_child(first)
	parent.add_child(second)
	var controls: Array[Control] = [first, second]
	parent.visible = false
	focus.open(0, controls)
	return parent


func test_controls_under_a_hidden_parent_cannot_take_focus() -> void:
	_panel_under_a_hidden_parent()
	check(focus.focused(0) == null, "controls under a hidden parent cannot take focus")


func test_controls_take_focus_once_their_parent_is_shown() -> void:
	var parent: Control = _panel_under_a_hidden_parent()
	parent.visible = true
	_tap(0, &"move_down")
	check_equal(focus.focus_index(0), 0, "they can once the parent is shown")


func test_hiding_the_whole_panel_stops_activation() -> void:
	var parent: Control = _panel_under_a_hidden_parent()
	parent.visible = true
	_tap(0, &"move_down")
	parent.visible = false
	_tap(0, &"accept")
	check_equal(_count("activated", 0), 0, "hiding the whole panel stops activation")


# --- Owners -----------------------------------------------------------------

func test_a_closed_panel_ignores_its_owner() -> void:
	for action: StringName in [&"move_down", &"accept", &"back"]:
		_tap(0, action)
	check(events_seen.is_empty(), "no panel open, nothing happens, got %s" % [events_seen])


func test_only_the_owner_moves_a_panel() -> void:
	focus.open(1, _panel(1))
	events_seen.clear()
	for player: int in [0, 2, 3]:
		for action: StringName in [&"move_down", &"move_up", &"move_left", &"move_right", &"accept", &"back"]:
			_tap(player, action)
	check(events_seen.is_empty(), "players 1, 3 and 4 cannot touch player 2's panel, got %s" % [events_seen])
	check_equal(focus.focus_index(1), 0, "player 2's focus did not move")
	_tap(1, &"move_down")
	check_equal(focus.focus_index(1), 1, "the owner moves it")


## All four panels open; in one frame P1 holds down, P2 up, P3 accept and P4 back.
func _four_owners_press_at_once() -> void:
	for player in 4:
		focus.open(player, _panel(player))
	events_seen.clear()
	input.send_virtual(0, &"move_down")
	input.send_virtual(1, &"move_up")
	input.send_virtual(2, &"accept")
	input.send_virtual(3, &"back")
	focus.poll()


func test_four_owners_move_their_own_panels_in_one_frame() -> void:
	_four_owners_press_at_once()
	check_equal(focus.focus_index(0), 1, "player 1 went to the next control")
	check_equal(focus.focus_index(1), 2, "player 2 wrapped to the last control")
	check_equal(focus.focus_index(2), 0, "player 3 did not move")
	check_equal(focus.focus_index(3), 0, "player 4 did not move")


func test_of_four_owners_only_the_one_who_accepts_activates() -> void:
	_four_owners_press_at_once()
	check(_count("activated", 2) == 1 and _count("activated", 0) + _count("activated", 1) + _count("activated", 3) == 0,
		"only player 3 activated, got %s" % [events_seen])


func test_of_four_owners_only_the_one_who_backs_cancels() -> void:
	_four_owners_press_at_once()
	check(_count("cancelled", 3) == 1 and _count("cancelled", 0) + _count("cancelled", 1) + _count("cancelled", 2) == 0,
		"only player 4 cancelled, got %s" % [events_seen])


func test_closing_one_of_four_panels_leaves_the_other_three_working() -> void:
	for player in 4:
		focus.open(player, _panel(player))
	focus.close(2)
	for player: int in [0, 1, 3, 2]:
		_tap(player, &"move_down")
	check(focus.focus_index(0) == 1 and focus.focus_index(1) == 1 and focus.focus_index(3) == 1, "the three open panels still move")
	check(not focus.is_open(2) and focus.focus_index(2) == -1, "the closed panel stays closed")


func test_a_player_without_a_panel_plays_on() -> void:
	focus.open(0, _panel(0))
	# Player 2 plays on: moving and casting must not reach player 1's panel.
	input.send_virtual(1, &"move_down")
	input.send_virtual(1, &"staff_2")
	focus.poll()
	check_equal(events_seen.size(), 2, "only player 1's own opening was logged, got %s" % [events_seen])
	check_equal(input.get_move(1), Vector2(0.0, 1.0), "player 2's gameplay input is untouched by the panel")
	check(input.is_action_pressed(1, &"staff_2"), "player 2 is still casting")


func test_an_open_panel_invents_no_input_for_its_owner() -> void:
	focus.open(0, _panel(0))
	input.send_virtual(1, &"move_down")
	focus.poll()
	check_equal(input.get_move(0), Vector2.ZERO, "the open panel does not eat or invent input for player 1")


func test_opening_a_second_panel_leaves_the_first_alone() -> void:
	focus.open(0, _panel(0))
	_tap(0, &"move_down")
	focus.open(1, _panel(1))
	check_equal(focus.focus_index(0), 1, "opening player 2's panel leaves player 1's focus alone")
	check(focus.is_open(0) and focus.is_open(1) and not focus.is_open(2), "exactly players 1 and 2 are open")


func test_a_player_who_leaves_closes_only_their_panel() -> void:
	focus.open(0, _panel(0))
	focus.open(1, _panel(1))
	input.leave(1)
	check(focus.is_open(0), "player 1's panel stays open")
	check(not focus.is_open(1), "the panel of a player who left closes")


func test_a_leave_sends_closed_once() -> void:
	focus.open(1, _panel(1))
	input.leave(1)
	check_equal(_count("closed", 1), 1, "closed is sent once")
	input.leave(1)
	check_equal(_count("closed", 1), 1, "leaving again sends nothing")


func test_out_of_range_players_have_no_panel_or_focus() -> void:
	check(not focus.is_open(-1) and not focus.is_open(4), "out of range players have no panel")
	check(focus.focused(7) == null and focus.focus_index(-3) == -1, "out of range players have no focus")


func test_out_of_range_calls_do_nothing() -> void:
	focus.move_focus(9, 1)
	focus.activate(9)
	focus.cancel(9)
	check(not focus.close(9), "closing an out of range player is false")
	check(events_seen.is_empty(), "out of range calls do nothing: %s" % [events_seen])


# --- Capture ----------------------------------------------------------------

## P1's panel open, and P1 holding right, accept, back, staff 1, staff 2 and pause.
func _captured_owner_presses() -> void:
	focus.open(0, _panel(0))
	for action: StringName in [&"move_right", &"accept", &"back", &"staff_1", &"staff_2", &"pause"]:
		input.send_virtual(0, action)


func test_an_open_panel_captures_its_owner() -> void:
	focus.open(0, _panel(0))
	check(input.is_captured(0), "an open panel captures its owner")


func test_a_captured_owners_gameplay_reads_nothing() -> void:
	_captured_owner_presses()
	check_equal(input.get_move(0), Vector2.ZERO, "the owner's wizard does not walk")
	check(not input.is_action_pressed(0, &"staff_1") and not input.is_action_pressed(0, &"staff_2"), "the owner's wizard does not cast or dash")
	check(not input.is_action_just_pressed(0, &"staff_2"), "no just-pressed for gameplay")
	check_equal(input.get_strength(0, &"move_right"), 0.0, "no strength for gameplay")


func test_a_captured_owners_menu_buttons_stay_readable() -> void:
	_captured_owner_presses()
	check(input.is_action_pressed(0, &"pause") and input.is_action_pressed(0, &"accept"), "the menu buttons stay readable")


func test_the_panel_still_sees_a_captured_owners_presses() -> void:
	_captured_owner_presses()
	focus.poll()
	check(_count("activated", 0) == 1 and _count("cancelled", 0) == 1, "the panel still sees the presses")


func test_other_players_play_on_beside_an_open_panel() -> void:
	focus.open(0, _panel(0))
	input.send_virtual(1, &"move_down")
	input.send_virtual(1, &"staff_2")
	check(not input.is_captured(1), "other players are not captured")
	check(input.get_move(1) == Vector2(0.0, 1.0) and input.is_action_pressed(1, &"staff_2"), "other players move and cast while player 1's panel is open")


func test_a_second_open_panel_leaves_the_other_players_alone() -> void:
	focus.open(0, _panel(0))
	input.send_virtual(1, &"move_down")
	focus.open(2, _panel(2))
	check_equal(input.get_move(1), Vector2(0.0, 1.0), "a second open panel leaves player 2 alone")


func test_capture_is_per_player() -> void:
	focus.open(0, _panel(0))
	focus.open(2, _panel(2))
	check(input.is_captured(2) and not input.is_captured(3), "capture is per player")


func test_closing_a_panel_frees_the_capture() -> void:
	focus.open(0, _panel(0))
	focus.close(0)
	check(not input.is_captured(0), "closing frees the capture")


func test_a_direction_held_carries_on_after_close() -> void:
	focus.open(0, _panel(0))
	input.send_virtual(0, &"move_right")
	focus.close(0)
	check_equal(input.get_move(0), Vector2(1.0, 0.0), "a direction still held carries on after close")


func test_leaving_frees_the_capture() -> void:
	focus.open(1, _panel(1))
	input.leave(1)
	check(not input.is_captured(1) and not focus.is_open(1), "leaving frees the capture")


func test_an_out_of_range_player_is_never_captured() -> void:
	input.set_captured(7, true)
	check(not input.is_captured(7), "an out of range player is never captured")


# --- Alternate, paging, a navigator, a jump ---------------------------------

func _listen_to_extras() -> void:
	focus.alternate.connect(func(p: int, c: Control) -> void: alternates.append([p, buttons[p].find(c)]))
	focus.paged.connect(func(p: int, step: int) -> void: pages.append([p, step]))


func test_alternate_is_sent_for_the_focused_control() -> void:
	_listen_to_extras()
	focus.open(1, _panel(1))
	_tap(1, &"move_down")
	_tap(1, &"alternate")
	check_equal(alternates, [[1, 1]], "alternate sends alternate for the focused control")


func test_the_page_keys_send_paged_steps() -> void:
	_listen_to_extras()
	focus.open(1, _panel(1))
	_tap(1, &"page_next")
	_tap(1, &"page_prev")
	check_equal(pages, [[1, 1], [1, -1]], "page_next and page_prev send paged +1 and -1")


func test_alternate_and_paging_do_not_move_the_focus() -> void:
	_listen_to_extras()
	focus.open(1, _panel(1))
	_tap(1, &"move_down")
	for action: StringName in [&"alternate", &"page_next", &"page_prev"]:
		_tap(1, action)
	check_equal(focus.focus_index(1), 1, "neither moves the focus")


func test_a_closed_panel_sends_no_alternate_or_page() -> void:
	_listen_to_extras()
	_tap(2, &"alternate")
	_tap(2, &"page_next")
	check(alternates.is_empty() and pages.is_empty(), "a closed panel sends neither")


## A navigator for P1's panel of three in a row: right goes to the third, nothing else has an
## answer (so up and down fall back to next and previous). Each question goes in `asked`.
func _row_navigator() -> void:
	focus.set_navigator(0, func(c: Control, d: Vector2i) -> Control:
		asked.append([buttons[0].find(c), d])
		if d == Vector2i.RIGHT:
			return buttons[0][2]
		return null)


func test_the_navigator_steers_a_move() -> void:
	focus.open(0, _panel(0))
	_row_navigator()
	_tap(0, &"move_right")
	check_equal(focus.focus_index(0), 2, "the navigator sends right to the third control")
	check_equal(asked.back(), [0, Vector2i.RIGHT], "asked with the focused control and the direction")


func test_with_no_answer_down_goes_to_the_next_control() -> void:
	focus.open(0, _panel(0))
	_row_navigator()
	_tap(0, &"move_down")
	check_equal(focus.focus_index(0), 1, "with no answer, down goes to the next control")


func test_with_no_answer_left_goes_to_the_previous_control() -> void:
	focus.open(0, _panel(0))
	_row_navigator()
	_tap(0, &"move_left")
	check_equal(focus.focus_index(0), 2, "with no answer, left goes to the previous control (wrapping)")


func test_a_navigators_answer_outside_the_panel_counts_as_none() -> void:
	focus.open(0, _panel(0))
	var stranger: Button = own(Button.new()) as Button
	focus.set_navigator(0, func(_c: Control, _d: Vector2i) -> Control: return stranger)
	_tap(0, &"move_down")
	check_equal(focus.focus_index(0), 1, "a control outside the panel counts as no answer")


func _to_the_third(_c: Control, _d: Vector2i) -> Control:
	return buttons[0][2]


func test_reopening_a_panel_keeps_its_navigator() -> void:
	focus.open(0, _panel(0))
	focus.set_navigator(0, _to_the_third)
	focus.open(0, _panel(0))
	_tap(0, &"move_down")
	check_equal(focus.focus_index(0), 2, "opening again with new controls keeps the navigator")


func test_closing_a_panel_clears_its_navigator() -> void:
	focus.open(0, _panel(0))
	focus.set_navigator(0, _to_the_third)
	focus.close(0)
	focus.open(0, _panel(0))
	_tap(0, &"move_down")
	check_equal(focus.focus_index(0), 1, "a closed panel's navigator is gone")


func test_a_navigator_set_while_closed_is_ignored() -> void:
	focus.set_navigator(0, _to_the_third)
	focus.open(0, _panel(0))
	_tap(0, &"move_down")
	check_equal(focus.focus_index(0), 1, "a navigator set while closed is ignored")


func test_a_closed_panel_takes_no_jump() -> void:
	check(not focus.focus(0, _button(0, 2)), "a closed panel takes no jump")


func test_a_jump_focuses_the_control() -> void:
	focus.open(0, _panel(0))
	check(focus.focus(0, _button(0, 2)) and focus.focus_index(0) == 2, "a jump focuses the control")


func test_a_jump_to_another_panels_control_is_refused() -> void:
	focus.open(0, _panel(0))
	check(not focus.focus(0, _button(1, 0)), "another panel's control is refused")


func test_a_jump_to_a_disabled_control_is_refused() -> void:
	focus.open(0, _panel(0))
	focus.focus(0, _button(0, 2))
	_button(0, 1).disabled = true
	check(not focus.focus(0, _button(0, 1)) and focus.focus_index(0) == 2, "a disabled control is refused")
