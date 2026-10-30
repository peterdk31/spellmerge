extends "res://tests/support/suite.gd"
## Tests for the horde HUD (hud/panels/horde/, docs/milestones/horde.md H5): the status shows
## only while a horde run is on and says the time, kills, level and experience; a seat's offer
## shows near its corner with the cards as the registry names them, takes only that seat's
## buttons (d-pad left and right, accept; P1's mouse on the keyboard) and sends the right
## `horde_pick_requested`; it closes on `horde_pick_taken`; a menu of the seat's own or the
## pause hides it or stops it; in the build break (the game paused) a seat picks, then gets the
## "Build, then ready" prompt and says ready with A, its box says "Ready", and the line under
## the status names who the break still waits for; the end summary stays until the next run. The real `panels.tscn` (the "Hud" autoload) is used, so the node exists in every
## build.
##
## godot --headless --path . --script res://tests/hud/test_horde_hud.gd

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const HordePanelScript := preload("res://hud/panels/horde/horde_panel.gd")
const HordePickScript := preload("res://hud/panels/horde/horde_pick.gd")
## Loaded when needed, not preloaded: this scene is also the "Hud" autoload.
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
## A save no test writes, so a Hud never reads the real `user://save.cfg`.
const NO_SAVE: String = "user://test_no_save.cfg"
const VIEW: Rect2 = Rect2(0.0, 0.0, 640.0, 360.0)
const OFFER: Array[StringName] = [&"bolt", &"fire", &"dash"]

var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _hud: HudScript
var _horde: HordePanelScript
var _requests: Array = []
var _readies: Array[int] = []


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_input = own(InputManagerScript.new()) as InputManagerScript
	_input.events = _bus
	_focus = own(UIFocusScript.new()) as UIFocusScript
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	_requests.clear()
	_readies.clear()
	_bus.horde_pick_requested.connect(func(seat: int, choice: int) -> void: _requests.append([seat, choice]))
	_bus.horde_ready_requested.connect(func(seat: int) -> void: _readies.append(seat))


func after_each() -> void:
	paused = false


## The Hud with the spell runtime `spells` (null: none, the cards show their ids).
func _make_hud(spells: SpellsScript = null) -> void:
	_hud = own((load(HUD_SCENE_PATH) as PackedScene).instantiate()) as HudScript
	_hud.events = _bus
	_hud.save = SaveFile.new(NO_SAVE)
	_hud.ui_focus = _focus
	_hud.input = _input
	_hud.spells = spells
	root.add_child(_hud)
	_horde = _hud.get_horde()
	# The tests poll by hand, so a frame never reads a press first.
	_horde.set_process(false)


func _join(count: int) -> void:
	for seat in count:
		_input.add_virtual_device(seat)
		_bus.player_joined.emit(seat)
	_bus.room_entered.emit(&"horde")
	_bus.horde_started.emit(null)


func _tap(seat: int, action: StringName) -> void:
	_input.send_virtual(seat, action, 1.0)
	_input.send_virtual(seat, action, 0.0)


func _offer(seat: int, ids: Array[StringName] = OFFER) -> void:
	_bus.horde_picks_offered.emit(seat, ids)
	_horde.poll()


## A build break as the director starts it: the game paused, `seats` not ready.
func _break(seats: Array[int]) -> void:
	paused = true
	_bus.horde_break_changed.emit(true)
	for seat in seats:
		_bus.horde_ready_changed.emit(seat, false)
	_horde.poll()


func test_the_node_is_in_the_hud_scene() -> void:
	_make_hud()
	check(_horde != null, "panels.tscn has the horde HUD")
	check(_hud.get_node_or_null("Root/Horde") == _horde, "it is node Root/Horde")
	check(not _horde.get_status().visible and not _horde.get_summary().visible and not _horde.get_break_row().visible,
			"nothing shows outside a horde run")


func test_status_shows_only_during_a_run() -> void:
	_make_hud()
	_join(1)
	check(_horde.get_status().visible, "horde_started shows the status")
	_bus.horde_ended.emit()
	check(not _horde.get_status().visible, "horde_ended hides it")
	_bus.horde_started.emit(null)
	check(_horde.get_status().visible, "a new run shows it again")


func test_status_text_and_experience_bar() -> void:
	_make_hud()
	_join(1)
	_bus.horde_status.emit(192.7, 140, 31, 4, 12, 30)
	check_equal(_horde.status_text(), "03:12  Kills 140  Level 4", "time as mm:ss, kills and level")
	check_equal(_horde.xp_text(), "XP 12/30", "experience in words beside the bar")
	check(_horde.xp_bar().value == 12.0 and _horde.xp_bar().max_value == 30.0, "the bar is 12 of 30")
	_bus.horde_status.emit(3725.0, 900, 0, 11, 0, 80)
	check_equal(_horde.status_text(), "62:05  Kills 900  Level 11", "minutes past an hour keep counting")
	_bus.horde_started.emit(null)
	check_equal(_horde.status_text(), "00:00  Kills 0  Level 1", "a restart starts the numbers over")


func test_offer_shows_the_cards_of_the_registry_for_its_seat_only() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var spells := own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	_make_hud(spells)
	_join(4)
	_offer(2)
	for seat in 4:
		check_equal(_horde.get_pick(seat).visible, seat == 2, "only seat 2's pick shows (seat %d)" % seat)
	var pick: HordePickScript = _horde.get_pick(2)
	check_equal(pick.theme_type_variation, &"PlayerPanel3", "the box has seat 2's colour")
	for at in OFFER.size():
		var card := pick.card(at)
		check_equal(card.name_text(), spells.component_name(OFFER[at]), "card %d is named as the builder names it" % at)
		check(card.icon() != null, "card %d has its icon" % at)
		check(card.kind_text() != "", "card %d says its kind in words, not colour alone" % at)
	check_equal(pick.card(0).kind_text(), "Carrier", "a bolt is a carrier")
	check(pick.card(0).is_chosen() and not pick.card(1).is_chosen(), "the first card is chosen at first")


func test_a_seats_buttons_work_only_its_own_pick() -> void:
	_make_hud()
	_join(2)
	_offer(1)
	_tap(0, &"kind_next")
	_tap(0, &"accept")
	_horde.poll()
	check(_requests.is_empty(), "seat 0's buttons do nothing to seat 1's pick")
	check_equal(_horde.get_pick(1).choice(), 0, "seat 1's choice did not move")
	_tap(1, &"kind_next")
	_horde.poll()
	check_equal(_horde.get_pick(1).choice(), 1, "the d-pad's right moves the choice")
	_tap(1, &"kind_prev")
	_tap(1, &"kind_prev")
	_horde.poll()
	check_equal(_horde.get_pick(1).choice(), 2, "the choice wraps round to the last card")
	_tap(1, &"accept")
	_horde.poll()
	check_equal(_requests, [[1, 2]], "accept asks for the chosen card, for that seat")


func test_two_seats_pick_at_once() -> void:
	_make_hud()
	_join(4)
	_offer(0)
	_offer(3)
	_tap(3, &"kind_next")
	_tap(0, &"accept")
	_tap(3, &"accept")
	_horde.poll()
	check_equal(_requests, [[0, 0], [3, 1]], "each seat sends its own request in the same frame")


func test_presses_before_the_offer_take_nothing() -> void:
	_make_hud()
	_join(1)
	_tap(0, &"accept")
	_tap(0, &"kind_next")
	_offer(0)
	_horde.poll()
	check(_requests.is_empty(), "an accept pressed before the offer takes nothing")
	check_equal(_horde.get_pick(0).choice(), 0, "nor does a d-pad press move it")


func test_taken_closes_the_pick() -> void:
	_make_hud()
	_join(2)
	_offer(0)
	_offer(1)
	_tap(0, &"accept")
	_horde.poll()
	_bus.horde_pick_taken.emit(0, &"bolt")
	_horde.poll()
	check(not _horde.get_pick(0).visible and not _horde.get_pick(0).has_offer(), "horde_pick_taken closes the pick")
	check(_horde.get_pick(1).visible, "the other seat's pick stays open")
	_tap(0, &"accept")
	_horde.poll()
	check_equal(_requests.size(), 1, "a closed pick sends nothing more")
	_bus.horde_pick_taken.emit(1, &"")
	check(not _horde.get_pick(1).visible, "a dropped offer (no card) closes too")


func test_a_menu_of_the_seat_hides_and_stops_its_pick() -> void:
	_make_hud()
	_join(2)
	_offer(0)
	_offer(1)
	var control := own(Button.new()) as Button
	_focus.open(0, [control])
	_horde.poll()
	check(not _horde.get_pick(0).visible, "the pick hides while its seat's builder or menu is open")
	check(_horde.get_pick(1).visible, "another seat's pick stays")
	_tap(0, &"accept")
	_horde.poll()
	check(_requests.is_empty(), "the menu's accept never takes a card")
	_focus.close(0)
	_tap(0, &"accept")
	_horde.poll()
	check(_horde.get_pick(0).visible, "the pick shows again when the menu closes, the offer kept")
	check(_requests.is_empty(), "an accept in the frame the menu closed takes nothing")
	_tap(0, &"accept")
	_horde.poll()
	check_equal(_requests, [[0, 0]], "then accept takes the card")


func test_the_pause_stops_every_pick() -> void:
	_make_hud()
	_join(1)
	_offer(0)
	paused = true
	_tap(0, &"accept")
	_horde.poll()
	paused = false
	_horde.poll()
	_tap(0, &"accept")
	_horde.poll()
	check_equal(_requests, [[0, 0]], "the press while paused took nothing, the one after it did")


func test_the_keyboard_seat_clicks_a_card() -> void:
	_make_hud()
	check_equal(_input.join(InputManagerScript.KEYBOARD), 0, "the keyboard is P1")
	_bus.player_joined.emit(0)
	_bus.horde_started.emit(null)
	_offer(0)
	await process_frame
	var target := _horde.get_pick(0).card(2).get_global_rect().get_center()
	_horde.mouse_position = func() -> Vector2: return target
	_horde.poll()
	check_equal(_horde.get_pick(0).choice(), 2, "pointing at a card chooses it")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_input.handle_event(click)
	var release := click.duplicate() as InputEventMouseButton
	release.pressed = false
	_input.handle_event(release)
	_horde.poll()
	check_equal(_requests, [[0, 2]], "a click on it takes it")


func test_four_picks_and_the_status_fit_the_view_apart() -> void:
	_make_hud()
	_join(4)
	_break([0, 1, 2, 3])
	for seat in 4:
		_offer(seat)
	await process_frame
	await process_frame
	var boxes: Array[Rect2] = [_horde.get_status().get_global_rect(), _horde.get_break_row().get_global_rect()]
	for seat in 4:
		boxes.append(_horde.get_pick(seat).get_global_rect())
	for seat in 4:
		boxes.append(_hud.get_panel(seat).get_global_rect())
	for at in boxes.size():
		check(boxes[at].size.x > 20.0 and boxes[at].size.y > 10.0, "box %d %s has its size" % [at, boxes[at]])
		check(VIEW.encloses(boxes[at]), "box %d %s is inside the 640x360 view" % [at, boxes[at]])
		for other in range(at + 1, boxes.size()):
			# The status and the break line are one column; the corner panels are their own.
			if at < 2 and other < 2:
				continue
			check(not boxes[at].intersects(boxes[other]), "box %d %s does not cover box %d %s" % [at, boxes[at], other, boxes[other]])


func test_the_prompts_and_the_waiting_line_fit_the_view_apart() -> void:
	_make_hud()
	_join(4)
	_break([0, 1, 2, 3])
	_bus.horde_ready_changed.emit(3, true)
	await process_frame
	await process_frame
	var boxes: Array[Rect2] = [_horde.get_status().get_global_rect(), _horde.get_break_row().get_global_rect()]
	for seat in 4:
		check(_horde.get_pick(seat).visible, "seat %d's box shows" % seat)
		boxes.append(_horde.get_pick(seat).get_global_rect())
	for seat in 4:
		boxes.append(_hud.get_panel(seat).get_global_rect())
	check(_horde.get_pick(3).get_global_rect().size.y < _horde.get_pick(0).get_global_rect().size.y, "a Ready box is smaller than a prompt")
	for at in boxes.size():
		check(VIEW.encloses(boxes[at]), "box %d %s is inside the 640x360 view" % [at, boxes[at]])
		for other in range(at + 1, boxes.size()):
			if at < 2 and other < 2:
				continue
			check(not boxes[at].intersects(boxes[other]), "box %d %s does not cover box %d %s" % [at, boxes[at], other, boxes[other]])


func test_the_break_walks_a_seat_through_pick_build_and_ready() -> void:
	_make_hud()
	_join(2)
	_break([0, 1])
	_offer(0)
	_offer(1)
	check(_horde.in_break() and _horde.get_break_row().visible, "the break line shows")
	check_equal(_horde.break_text(), "Waiting for P1, P2", "naming who is not ready")
	var pick: HordePickScript = _horde.get_pick(0)
	check_equal(pick.mode(), HordePickScript.Mode.OFFER, "seat 0 picks first")
	_tap(0, &"accept")
	_horde.poll()
	check_equal(_requests, [[0, 0]], "a pick works while the break pauses the game")
	_bus.horde_pick_taken.emit(0, &"bolt")
	check_equal(pick.mode(), HordePickScript.Mode.PROMPT, "then the seat builds and gets ready")
	check(pick.visible and pick.get_node("Column/PromptHints").visible, "the prompt shows its buttons")
	check(not pick.get_node("Column/Hints").visible, "and not the pick's")
	_horde.poll()
	check(_readies.is_empty(), "the accept that took the card does not also say ready")
	_tap(0, &"accept")
	_horde.poll()
	check_equal(_readies, [0] as Array[int], "A on the prompt says ready")
	_bus.horde_ready_changed.emit(0, true)
	check_equal(pick.mode(), HordePickScript.Mode.READY, "the box says Ready")
	check(pick.visible, "and stays shown")
	check_equal(_horde.break_text(), "Waiting for P2", "only P2 is waited for")
	_tap(0, &"accept")
	_horde.poll()
	check_equal(_readies.size(), 1, "a ready box reads nothing more")
	paused = false
	_bus.horde_break_changed.emit(false)
	_horde.poll()
	check(not _horde.get_break_row().visible, "the break's end hides the line")
	for seat in 2:
		check(not _horde.get_pick(seat).visible, "and every box (seat %d)" % seat)


func test_a_seat_with_no_offer_gets_the_prompt_at_once() -> void:
	_make_hud()
	_join(1)
	_break([0])
	check_equal(_horde.get_pick(0).mode(), HordePickScript.Mode.PROMPT, "no offer: build and ready")
	check(_horde.get_pick(0).visible, "shown")
	_tap(0, &"accept")
	_horde.poll()
	check_equal(_readies, [0] as Array[int], "and A says ready")


func test_the_builder_hides_the_prompt_and_owns_its_buttons() -> void:
	_make_hud()
	_join(1)
	_break([0])
	_tap(0, &"back")
	_hud.poll()
	_horde.poll()
	check(_hud.get_radial(0).is_open() or _hud.get_builder(0).is_open(), "B opens the builder while the game is paused")
	check(not _horde.get_pick(0).visible, "the prompt hides while the builder is open")
	_tap(0, &"accept")
	_horde.poll()
	check(_readies.is_empty(), "the builder's A never says ready")
	_tap(0, &"pause")
	_hud.poll()
	check(not _hud.get_radial(0).is_open() and not _hud.get_builder(0).is_open(), "Start closes the builder")
	check(paused, "and the break keeps the game paused")
	_horde.poll()
	check(_horde.get_pick(0).visible, "the prompt shows again")
	_tap(0, &"accept")
	_horde.poll()
	check_equal(_readies, [0] as Array[int], "then A says ready")


func test_the_pause_menu_stops_every_box_in_a_break() -> void:
	_make_hud()
	_join(2)
	_break([0, 1])
	_tap(0, &"pause")
	_hud.poll()
	check(_hud.get_pause_menu().is_open(), "P1 opened the pause menu in the break")
	_tap(1, &"accept")
	_horde.poll()
	check(_readies.is_empty(), "another seat's A says nothing while the menu is open")
	_hud.get_pause_menu().close_menu()
	check(paused, "closing the menu leaves the break's pause")
	_horde.poll()
	_tap(1, &"accept")
	_horde.poll()
	check_equal(_readies, [1] as Array[int], "after it the boxes work again")


func test_a_seat_that_leaves_is_not_waited_for() -> void:
	_make_hud()
	_join(3)
	_break([0, 1, 2])
	_bus.player_left.emit(1)
	check_equal(_horde.break_text(), "Waiting for P1, P3", "P2 left")
	check(not _horde.get_pick(1).visible, "its box goes")


func test_a_level_up_in_the_break_brings_a_ready_seat_back_to_pick() -> void:
	_make_hud()
	_join(1)
	_break([0])
	_bus.horde_ready_changed.emit(0, true)
	check(not _horde.get_break_row().visible, "nobody is waited for")
	_bus.horde_picks_offered.emit(0, OFFER)
	_bus.horde_ready_changed.emit(0, false)
	check_equal(_horde.get_pick(0).mode(), HordePickScript.Mode.OFFER, "the new offer shows")
	check_equal(_horde.break_text(), "Waiting for P1", "and the seat is waited for again")


func test_the_end_summary_stays_until_the_next_run() -> void:
	_make_hud()
	_join(1)
	_break([0])
	_offer(0)
	_bus.horde_over.emit(75.9, 12, 3)
	check(_horde.get_summary().visible, "horde_over shows the summary")
	check_equal(_horde.summary_text(), "Time 01:15  Kills 12  Level 3", "with time, kills and level")
	check(not _horde.get_pick(0).visible and not _horde.get_break_row().visible, "the pick and the break go")
	_horde.poll()
	check(_horde.get_summary().visible, "it stays while the run waits to restart")
	_bus.horde_started.emit(null)
	check(not _horde.get_summary().visible, "the next run hides it")
	_bus.horde_over.emit(10.0, 1, 1)
	_bus.horde_ended.emit()
	check(not _horde.get_summary().visible and not _horde.get_status().visible, "leaving the horde hides everything")
