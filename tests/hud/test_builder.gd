extends "res://tests/support/suite.gd"
## Tests for the staff builder in hud/builder (staffs A6a, B8): opened with B (`back`) at any
## time, driven only by its owner's device through core/ui_focus, showing the four staffs, their
## slots, the bag, the links and the cast plan with its numbers from events, and asking for
## changes with `staff_change_requested` and `card_move_requested` (pick and place, X to the
## bag, LB and RB for the staffs, the d-pad in two dimensions, player 1's mouse). The wizards are real (on the real registry and spell runtime, with
## the 20-slot dev staff), so a request is answered as in the game. Four builders open at once is
## the point of several tests.
##
## godot --headless --path . --script res://tests/hud/test_builder.gd

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const WizardFixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const BuilderScript := preload("res://hud/builder/builder.gd")
const HintLineScript := preload("res://hud/widgets/hint_line.gd")
## Loaded when needed, not preloaded: this scene is also the "Hud" autoload.
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
## A save no test writes, so a Hud never reads the real `user://save.cfg`.
const NO_SAVE: String = "user://test_no_save.cfg"

const STEP: float = 0.0625
const START: Array = [[&"dash"], [&"fire", &"bolt"], [], []]
## The staffs by index, as the builder names its tabs.
const A: int = 0
const X: int = 1
const Y: int = 2
const B: int = 3

var _registry: RegistryScript
var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _mgr: ManagerScript
var _spells: SpellsScript
var _hud: HudScript
## The world the wizards live in (its services are the ones below).
var _world: WizardFixture
var _players: Array[Actor] = []
## Every staff_change_requested as [player, staff, slot, id].
var _requests: Array = []
## Every build_refused as [player, reason].
var _refused: Array = []
## Every card_move_requested as [player, from staff, from slot, to staff, to slot].
var _moves: Array = []


func before_each() -> void:
	# The wizard fixture's world: the real registry and spell runtime, its own bus and input.
	_world = WizardFixture.new(root)
	_registry = own(_world.registry) as RegistryScript
	_bus = own(_world.bus) as EventsScript
	_input = own(_world.input) as InputManagerScript
	_focus = own(UIFocusScript.new()) as UIFocusScript
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	_mgr = own(_world.projectiles) as ManagerScript
	_spells = own(_world.spells) as SpellsScript
	own(_world.combat)
	own(_world.table)
	_players.clear()
	_requests.clear()
	_refused.clear()
	_moves.clear()
	_bus.card_move_requested.connect(func(player: int, fs: int, fl: int, ts: int, tl: int) -> void: _moves.append([player, fs, fl, ts, tl]))
	_bus.staff_change_requested.connect(func(player: int, staff: int, slot: int, id: StringName) -> void: _requests.append([player, staff, slot, id]))
	_bus.build_refused.connect(func(player: int, reason: String) -> void: _refused.append([player, reason]))
	# The HUD first, as in the game (the autoload exists before any wizard appears).
	_hud = own((load(HUD_SCENE_PATH) as PackedScene).instantiate()) as HudScript
	_hud.events = _bus
	_hud.save = SaveFile.new(NO_SAVE)
	_hud.ui_focus = _focus
	_hud.input = _input
	_hud.spells = _spells
	root.add_child(_hud)
	# These tests are the list builder's: the pause menu's Sandbox page picked it.
	_hud.call("_on_builder_options_changed", false, 0, true)


## `count` players with a device and a wizard (the start cards on the dev staff), joined, in a room.
## With `gamepads` the devices are real gamepads (ids 0 to 3, joining in order), whose buttons
## are sent as joypad button events; else virtual devices.
func _start(count: int, gamepads: bool = false) -> void:
	for index in count:
		if gamepads:
			_input.join(index)
		else:
			_input.add_virtual_device(index)
		# A real wizard actor (actors G7), seated as flow seats it and in the tree.
		var player := own(_world.wizard(index, Vector2.ZERO, START, _registry.get_resource(&"wizard", &"dev") as StaffBase)) as Actor
		_players.append(player)
		_bus.player_joined.emit(index)
	_bus.room_entered.emit(&"test_room")


func _tap(player: int, action: StringName) -> void:
	_input.send_virtual(player, action, 1.0)
	_input.send_virtual(player, action, 0.0)


func _frame() -> void:
	_hud.poll()
	_focus.poll()
	for player in _players:
		player.step(STEP)


func _builder(player: int) -> BuilderScript:
	return _hud.get_builder(player)


## Open player's builder the way a person does: B (`back`) in play.
func _open(player: int) -> void:
	_tap(player, &"back")
	_frame()


## Put `player`'s focus on `control` (a jump; `test_every_control_is_reached_with_the_dpad`
## checks that a person gets there with the d-pad). False if it is not one of the panel's.
func _focus_on(player: int, control: Control) -> bool:
	_focus.focus(player, control)
	_frame()
	return _focus.focused(player) == control


## Focus `control` and press `accept` (activate) on it.
func _press(player: int, control: Control) -> void:
	check(_focus_on(player, control), "player %d can reach %s" % [player + 1, control.name])
	_tap(player, &"accept")
	_frame()


func _row_named(builder: BuilderScript, display_name: String) -> Button:
	for row in builder.shown_rows():
		if row.text.trim_prefix(BuilderScript.FOCUS_MARK).begins_with(display_name):
			return row
	return null


func test_b_opens_the_builder_on_the_first_slot_of_staff_2() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	check(builder.is_open(), "B opens the builder")
	check_equal(builder.viewed_staff(), X, "it shows staff 2 (the fire bolt)")
	check_equal(_focus.focused(0), builder.slot_button(0), "focus starts on the first slot")
	check_equal(builder.slot_count(), 20, "the dev staff's 20 slots")
	check_equal(builder.cards_of(X).slice(0, 2), [&"fire", &"bolt"] as Array[StringName], "the cards the player announced")


func test_a_slot_then_a_card_asks_for_it_and_moves_on_to_the_next_slot() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.slot_button(2))
	check(builder.shown_rows().size() > 1, "the bag is listed")
	_press(0, _row_named(builder, "Nova"))
	check_equal(_requests, [[0, X, 2, &"nova"]], "the request names the player, staff, slot and card")
	check_equal(builder.cards_of(X)[2], &"nova", "the player answered and the builder shows it")
	check_equal(builder.selected_slot(), 3, "the next pick goes to the next slot")
	_press(0, _row_named(builder, "Frost"))
	check_equal(builder.cards_of(X)[3], &"frost", "picking on builds left to right")


func test_empty_clears_a_slot() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.slot_button(3))
	_press(0, _row_named(builder, "Nova"))
	_press(0, builder.slot_button(5))
	_press(0, _row_named(builder, BuilderScript.EMPTY_TEXT))
	check_equal(builder.cards_of(X)[5], &"", "an empty slot stays empty")
	check_equal(builder.selected_slot(), 5, "emptying does not move on")


func test_a_tab_shows_another_staff() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.tab_button(A))
	check_equal(builder.viewed_staff(), A, "tab A shows staff A")
	check_equal(builder.cards_of(A)[0], &"dash", "with its dash")
	check_equal(_focus.focused(0), builder.slot_button(0), "focus goes to its first slot")
	_press(0, builder.slot_button(1))
	_press(0, _row_named(builder, "Bolt"))
	check_equal(_requests.back(), [0, A, 1, &"bolt"], "a pick goes to the staff shown")


func test_the_tabs_show_the_staff_buttons_and_follow_the_device() -> void:
	_start(4)
	root.size = Vector2i(640, 360)
	for player in 4:
		_open(player)
	await process_frame
	await process_frame
	var builder: BuilderScript = _builder(0)
	check(builder.is_open(), "the builder is open")
	for staff in 4:
		check_equal(builder.tab_glyph(staff).action(), StringName("staff_%d" % (staff + 1)), "tab %d shows staff_%d" % [staff + 1, staff + 1])
		check_equal(builder.tab_button(staff).tooltip_text, "Staff %s" % BuilderScript.STAFF_NAMES[staff], "tab %d is named by its tooltip" % (staff + 1))
		_check_glyph_inside_tab(builder, staff)
	check_equal(builder.tab_marks(X), "[]", "the shown staff keeps its [ ] mark")
	check_equal(builder.tab_marks(A), "", "and the others do not")
	_input.leave(0)
	_input.join(InputManagerScript.KEYBOARD)
	if not builder.is_open():
		builder.open_builder()
	await process_frame
	await process_frame
	check_equal(builder.tab_glyph(A).current_glyph()["label"], "Space", "on the keyboard the tabs show keys, live")
	for staff in 4:
		_check_glyph_inside_tab(builder, staff)
	for player in 4:
		check(Rect2(0, 0, 640, 360).encloses(_builder(player).get_global_rect()), "builder %d still fits 640x360 with a key on every tab, got %s" % [player + 1, _builder(player).get_global_rect()])


## The glyph sits inside its tab, centred when no mark is beside it, as the layout placed it.
func _check_glyph_inside_tab(builder: BuilderScript, staff: int) -> void:
	var tab_rect: Rect2 = builder.tab_button(staff).get_global_rect()
	var glyph_rect: Rect2 = builder.tab_glyph(staff).get_global_rect()
	check(glyph_rect.size.x > 0.0, "tab %d: the glyph has a size" % (staff + 1))
	check(tab_rect.encloses(glyph_rect), "tab %d holds its glyph, got %s in %s" % [staff + 1, glyph_rect, tab_rect])
	if builder.tab_marks(staff).is_empty():
		check(absf(glyph_rect.get_center().x - tab_rect.get_center().x) <= 1.0, "tab %d: the glyph is centred, got %s in %s" % [staff + 1, glyph_rect, tab_rect])
	check_equal(roundf(glyph_rect.get_center().y), roundf(tab_rect.get_center().y), "tab %d: the glyph is vertically centred" % (staff + 1))


func test_back_on_a_card_returns_to_the_slot_and_elsewhere_closes() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.slot_button(4))
	check(builder.shown_rows().has(_focus.focused(0) as Button), "focus is in the bag")
	_tap(0, &"back")
	_frame()
	check_equal(_focus.focused(0), builder.slot_button(4), "back returns to the slot")
	_tap(0, &"back")
	_frame()
	check(not builder.is_open(), "back on a slot closes the builder")


func test_the_plan_and_the_notes_follow_the_staff() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	check(builder.plan_text().begins_with("1: "), "the plan has a line per cast: %s" % builder.plan_text())
	check(builder.plan_text().contains("Bolt"), "naming the bolt")
	var lines: PackedStringArray = builder.plan_text().split("\n")
	check(lines.size() == 1 and lines[0].begins_with("1: Fire Bolt."), "one line per cast, its description with no generated name: %s" % builder.plan_text())
	# Homing alone in staff Y lands on the caster, where it does nothing.
	_bus.staff_change_requested.emit(0, Y, 0, &"homing")
	_press(0, builder.tab_button(Y))
	_frame()
	check(builder.slot_button(0).text.contains(BuilderScript.WASTED_MARK.strip_edges()), "homing with no carrier is marked: %s" % builder.slot_button(0).text)
	check_equal(_focus.focused(0), builder.slot_button(0), "focus is on that slot")
	check(not builder.note_text().contains("does nothing"), "the mark is enough: the note gives no reason: %s" % builder.note_text())


func test_a_refusal_shows_its_reason() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	_bus.staff_change_requested.emit(0, X, 0, &"no_such_card")
	_frame()
	check(builder.note_text().begins_with(BuilderScript.REFUSED_PREFIX), "the refusal is shown: %s" % builder.note_text())


func test_alternate_and_accept_have_no_code_row_to_reach() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	var before: Array[StringName] = builder.cards_of(X)
	_tap(0, &"move_up")
	_frame()
	check_equal(_focus.focused(0), builder.tab_button(X), "up from the first slot is the shown staff's tab, no code row between")
	check(not builder.has_method("copy_button") and not builder.has_method("paste_button"), "the staff code buttons are gone")
	check_equal(builder.cards_of(X), before, "nothing changed the staff")


func test_only_the_owner_drives_a_builder() -> void:
	_start(2)
	_open(0)
	var builder: BuilderScript = _builder(0)
	var focused: Control = _focus.focused(0)
	_tap(1, &"move_down")
	_frame()
	check_equal(_focus.focused(0), focused, "player 2's presses do not move player 1's focus")
	check(not _builder(1).is_open(), "and do not open player 2's builder")


func test_four_open_builders_fit_the_screen_without_overlapping() -> void:
	_start(4)
	root.size = Vector2i(640, 360)
	for player in 4:
		_open(player)
	await process_frame
	await process_frame
	var screen := Rect2(0, 0, 640, 360)
	var rects: Array[Rect2] = []
	var names: Array[String] = []
	for player in 4:
		check(_builder(player).is_open(), "builder %d is open" % (player + 1))
		rects.append(_hud.get_panel(player).get_global_rect())
		names.append("panel %d" % (player + 1))
		rects.append(_builder(player).get_global_rect())
		names.append("builder %d" % (player + 1))
	for i in rects.size():
		check(screen.encloses(rects[i]), "%s is inside the 640x360 view, got %s" % [names[i], rects[i]])
		for j in range(i + 1, rects.size()):
			check(not rects[i].intersects(rects[j]), "%s and %s do not overlap, got %s and %s" % [names[i], names[j], rects[i], rects[j]])


func test_the_builder_opens_during_a_wave() -> void:
	_start(1)
	_bus.wave_started.emit(1)
	_open(0)
	check(_builder(0).is_open(), "the full builder opens in a wave")
	check_equal(_builder(0).tab_button(A).visible, true, "with its tabs")


func test_pick_and_place_swaps_two_slots() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.slot_button(0))
	check_equal(builder.held(), [X, 0] as Array[int], "A on the fire card picks it up")
	check(builder.slot_button(0).text.contains(BuilderScript.HELD_MARK), "it is marked as held: %s" % builder.slot_button(0).text)
	check(builder.hint_text().contains(BuilderScript.HINT_PLACE), "the hint offers to place it: %s" % builder.hint_text())
	_press(0, builder.slot_button(1))
	check_equal(_moves, [[0, X, 0, X, 1]], "A on another slot moves it there")
	check_equal(builder.cards_of(X).slice(0, 2), [&"bolt", &"fire"] as Array[StringName], "swapping with the bolt")
	check_equal(builder.held(), [BuilderScript.NOTHING, -1] as Array[int], "and nothing is held any more")


func test_a_held_card_moves_to_another_staff() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.slot_button(1))
	_tap(0, &"page_prev")
	_frame()
	check_equal(builder.viewed_staff(), A, "LB shows the previous staff, still holding")
	_press(0, builder.slot_button(2))
	check_equal(builder.cards_of(A)[2], &"bolt", "the bolt went into staff A")
	check_equal(builder.cards_of(X)[1], &"", "and left staff X")


func test_back_drops_a_held_card_and_x_sends_one_to_the_bag() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.slot_button(0))
	_tap(0, &"back")
	_frame()
	check(builder.is_open(), "B while holding does not close")
	check_equal(builder.held(), [BuilderScript.NOTHING, -1] as Array[int], "it drops the card where it was")
	check(_moves.is_empty(), "without moving anything")
	check(_focus_on(0, builder.slot_button(1)), "focus on the bolt")
	_tap(0, &"alternate")
	_frame()
	check_equal(_moves, [[0, X, 1, BuilderScript.BAG, 0]], "X sends the card back to the bag")
	check_equal(builder.cards_of(X)[1], &"", "the slot is empty")
	_press(0, builder.slot_button(0))
	_press(0, _row_named(builder, "Nova"))
	check_equal(_moves.back(), [0, X, 0, BuilderScript.BAG, 0], "A on the bag while holding sends the held card back")


func test_lb_and_rb_page_through_the_staffs() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	_tap(0, &"page_next")
	_frame()
	check_equal(builder.viewed_staff(), Y, "RB: X to Y")
	_tap(0, &"page_next")
	_tap(0, &"page_next")
	_frame()
	check_equal(builder.viewed_staff(), A, "and on round to A")
	_tap(0, &"page_prev")
	_frame()
	check_equal(builder.viewed_staff(), B, "LB goes back")


func test_the_dpad_moves_in_two_dimensions() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	check_equal(_focus.focused(0), builder.slot_button(0), "start on the first slot")
	_tap(0, &"move_up")
	_frame()
	check_equal(_focus.focused(0), builder.tab_button(X), "up from the first slot is the shown staff's tab")
	_tap(0, &"move_right")
	_frame()
	check_equal(_focus.focused(0), builder.tab_button(Y), "right along the tabs")
	_tap(0, &"move_down")
	_frame()
	check_equal(_focus.focused(0), builder.slot_button(0), "down from a tab to the slots")
	_tap(0, &"move_down")
	_frame()
	check_equal(_focus.focused(0), builder.slot_button(1), "down the slots")
	_tap(0, &"move_right")
	_frame()
	check_equal(_focus.focused(0), _row_named(builder, "Bolt"), "right to the bag, on the card in the slot")
	_tap(0, &"move_left")
	_frame()
	check(builder.slot_button(0) == _focus.focused(0) or builder.slot_button(1) == _focus.focused(0), "left back to the slots")


func test_every_control_is_reached_with_the_dpad() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	var directions: Array[StringName] = [&"move_up", &"move_down", &"move_left", &"move_right"]
	var seen: Array[Control] = [_focus.focused(0)]
	var todo: Array[Control] = [_focus.focused(0)]
	while not todo.is_empty():
		var from: Control = todo.pop_back()
		for direction in directions:
			_focus.focus(0, from)
			_tap(0, direction)
			_frame()
			var to: Control = _focus.focused(0)
			if to != null and not seen.has(to):
				seen.append(to)
				todo.append(to)
	for control in builder.controls():
		check(seen.has(control), "%s is reached with the d-pad" % control.name)


func test_links_and_numbers_show() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	check(builder.slot_button(0).text.contains(">2"), "fire goes into the bolt in slot 2: %s" % builder.slot_button(0).text)
	check(builder.slot_button(1).text.contains("#1"), "the bolt is cast 1: %s" % builder.slot_button(1).text)
	check(builder.slot_button(1).text.contains(BuilderScript.LINK_MARK.strip_edges()), "focused on fire, the bolt it goes into is marked")
	check(builder.note_text().begins_with("Goes into Bolt (slot 2)."), "the note says where fire goes: %s" % builder.note_text())
	check(builder.plan_text().contains("dmg") and builder.plan_text().contains("mana"), "the plan has live numbers: %s" % builder.plan_text())


func test_player_one_drags_with_the_mouse() -> void:
	_start(1)
	root.size = Vector2i(640, 360)
	_open(0)
	await process_frame
	var builder: BuilderScript = _builder(0)
	var from: Button = builder.slot_button(0)
	var to: Button = builder.slot_button(3)
	check_equal(from.mouse_filter, Control.MOUSE_FILTER_STOP, "player 1's slots take the mouse")
	check_equal(_builder(1).slot_button(0).mouse_filter if _builder(1).slot_count() > 0 else Control.MOUSE_FILTER_IGNORE, Control.MOUSE_FILTER_IGNORE, "other players' do not")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = from.get_global_rect().get_center()
	builder._on_mouse(press, from)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.global_position = to.get_global_rect().get_center()
	builder._on_mouse(release, from)
	check_equal(_moves, [[0, X, 0, X, 3]], "dragging fire onto slot 4 moves it there")

