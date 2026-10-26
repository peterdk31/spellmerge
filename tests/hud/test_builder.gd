extends "res://tests/support/suite.gd"
## Tests for the staff builder in hud/builder (staffs A6a): opened from the overlay at any
## time, driven only by its owner's device through core/ui_focus, showing the four staffs, their
## slots, the bag and the cast plan from events, and asking for changes with
## `staff_change_requested`. The wizards are real (on the real registry and spell runtime, with
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
const PlayerScript := preload("res://gameplay/player/player.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const BuilderScript := preload("res://hud/builder/builder.gd")
const HintLineScript := preload("res://hud/widgets/hint_line.gd")
## Loaded when needed, not preloaded: this scene is also the "Hud" autoload.
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"

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
var _players: Array[PlayerScript] = []
## Every staff_change_requested as [player, staff, slot, id].
var _requests: Array = []
## Every build_refused as [player, reason].
var _refused: Array = []


func before_each() -> void:
	_registry = own(RegistryScript.new()) as RegistryScript
	_registry.scan()
	_bus = own(EventsScript.new()) as EventsScript
	_input = own(InputManagerScript.new()) as InputManagerScript
	_input.events = _bus
	_focus = own(UIFocusScript.new()) as UIFocusScript
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _registry
	_spells.bind(_mgr, _bus)
	_players.clear()
	_requests.clear()
	_refused.clear()
	_bus.staff_change_requested.connect(func(player: int, staff: int, slot: int, id: StringName) -> void: _requests.append([player, staff, slot, id]))
	_bus.build_refused.connect(func(player: int, reason: String) -> void: _refused.append([player, reason]))
	# The HUD first, as in the game (the autoload exists before any wizard appears).
	_hud = own((load(HUD_SCENE_PATH) as PackedScene).instantiate()) as HudScript
	_hud.events = _bus
	_hud.ui_focus = _focus
	_hud.input = _input
	_hud.spells = _spells
	root.add_child(_hud)


## `count` players with a device and a wizard (the start cards on the dev staff), joined, in a room.
## With `gamepads` the devices are real gamepads (ids 0 to 3, joining in order), whose buttons
## are sent as joypad button events; else virtual devices.
func _start(count: int, gamepads: bool = false) -> void:
	for index in count:
		if gamepads:
			_input.join(index)
		else:
			_input.add_virtual_device(index)
		var player := own(PlayerScript.new()) as PlayerScript
		player.index = index
		player.input = _input
		player.events = _bus
		player.registry = _registry
		player.projectiles = _mgr
		player.spells = _spells
		player.staff = _registry.get_resource(&"wizard", &"dev") as StaffBase
		player.start_cards = START
		player._ready()
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


## Open player's builder the way a person does: the overlay, then "Build".
func _open(player: int) -> void:
	_tap(player, &"overlay")
	_frame()
	_tap(player, &"move_down")
	_frame()
	_tap(player, &"cast_a")
	_frame()


## Press move_down for `player` until `control` is focused. False if it never was.
func _focus_on(player: int, control: Control) -> bool:
	for _attempt in 120:
		if _focus.focused(player) == control:
			return true
		_tap(player, &"move_down")
		_frame()
	return _focus.focused(player) == control


## Focus `control` and press `cast_a` (activate) on it.
func _press(player: int, control: Control) -> void:
	check(_focus_on(player, control), "player %d can reach %s" % [player + 1, control.name])
	_tap(player, &"cast_a")
	_frame()


func _row_named(builder: BuilderScript, display_name: String) -> Button:
	for row in builder.shown_rows():
		if row.text.trim_prefix(BuilderScript.FOCUS_MARK).begins_with(display_name):
			return row
	return null


func test_the_overlay_opens_the_builder_on_the_first_slot_of_staff_x() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	check(builder.is_open(), "Build opens the builder")
	check_equal(builder.viewed_staff(), X, "it shows staff X (the fire bolt)")
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
	_press(0, builder.slot_button(0))
	_press(0, _row_named(builder, BuilderScript.EMPTY_TEXT))
	check_equal(builder.cards_of(X)[0], &"", "the fire card is gone")
	check_equal(builder.selected_slot(), 0, "emptying does not move on")


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


func test_back_on_a_card_returns_to_the_slot_and_elsewhere_closes() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	_press(0, builder.slot_button(4))
	check(builder.shown_rows().has(_focus.focused(0) as Button), "focus is in the bag")
	_tap(0, &"cast_b")
	_frame()
	check_equal(_focus.focused(0), builder.slot_button(4), "back returns to the slot")
	_tap(0, &"cast_b")
	_frame()
	check(not builder.is_open(), "back on a slot closes the builder")


func test_the_plan_and_the_notes_follow_the_staff() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	check(builder.plan_text().begins_with("1: "), "the plan has a line per cast: %s" % builder.plan_text())
	check(builder.plan_text().contains("Bolt"), "naming the bolt")
	# Homing alone in staff Y lands on the caster, where it does nothing.
	_bus.staff_change_requested.emit(0, Y, 0, &"homing")
	_press(0, builder.tab_button(Y))
	_frame()
	check(builder.slot_button(0).text.contains(BuilderScript.WASTED_MARK.strip_edges()), "homing with no carrier is marked: %s" % builder.slot_button(0).text)
	check_equal(_focus.focused(0), builder.slot_button(0), "focus is on that slot")
	check(builder.note_text().begins_with(BuilderScript.WASTED_PREFIX), "the note says why it does nothing: %s" % builder.note_text())


func test_a_refusal_shows_its_reason() -> void:
	_start(1)
	_open(0)
	var builder: BuilderScript = _builder(0)
	_bus.staff_change_requested.emit(0, X, 0, &"no_such_card")
	_frame()
	check(builder.note_text().begins_with(BuilderScript.REFUSED_PREFIX), "the refusal is shown: %s" % builder.note_text())


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
