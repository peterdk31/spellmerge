extends "res://tests/support/suite.gd"
## The hub's lectern on screen (run generation RG7, hud/menus/lectern, hud/panels): a seat's A
## (`accept`) at the lectern (`lectern_changed`) with no menu open opens that seat's menu of the
## stone's run's depths ("Room 1" up to "The boss", as many as `start_depth_changed` offers), the
## party's pick marked; A on a depth sends the command `start_depth_picked` and closes it, B closes it
## with nothing sent, and it closes by itself when its seat leaves the lectern or the hub is left. The
## lit stone, an item in reach and the altar come first. The stone line names where the run starts
## once it is past the first room.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const StoneLineScript := preload("res://hud/widgets/stone_line.gd")
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"

var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _hud: HudScript
## Every `start_depth_picked` sent, as [seat, depth].
var _picked: Array = []


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_input = own(InputManagerScript.new()) as InputManagerScript
	_input.events = _bus
	_focus = own(UIFocusScript.new()) as UIFocusScript
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	_picked = []
	_bus.start_depth_picked.connect(func(seat: int, depth: int) -> void: _picked.append([seat, depth]))
	for seat in 2:
		_input.add_virtual_device(seat)
	_hud = (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	_hud.events = _bus
	_hud.ui_focus = _focus
	_hud.input = _input
	_hud.save = SaveFile.new("user://test_lectern_menu_save.cfg")
	root.add_child(_hud)
	own(_hud)
	for seat in 2:
		_bus.player_joined.emit(seat)
	_bus.room_entered.emit(&"hub")
	_bus.start_stone_changed.emit(0, 2, false)
	_bus.start_depth_changed.emit(0, 6)


func _tap(seat: int, action: StringName) -> void:
	_input.send_virtual(seat, action, 1.0)
	_input.send_virtual(seat, action, 0.0)


func _frame() -> void:
	_hud.poll()
	_focus.poll()


func _words(seat: int) -> Array[String]:
	var found: Array[String] = []
	for button: Button in _hud.get_lectern(seat).buttons():
		found.append(button.text.trim_prefix("> "))
	return found


func test_a_at_the_lectern_opens_the_seats_menu_of_depths() -> void:
	_tap(1, &"accept")
	_frame()
	check(not _hud.get_lectern(1).is_open(), "A away from the lectern opens nothing")
	_bus.lectern_changed.emit(0b0010)
	_tap(0, &"accept")
	_frame()
	check(not _hud.get_lectern(0).is_open(), "nor for a seat that is not at it")
	_tap(1, &"accept")
	_frame()
	var menu: Control = _hud.get_lectern(1)
	check(menu.call("is_open") and menu.visible, "A at the lectern opens that seat's menu")
	check_equal(_words(1), ["Room 1 *", "Room 2", "Room 3", "Room 4", "Room 5", "The boss"] as Array[String], "a depth a row, the party's start marked")
	check(not _hud.get_lectern(0).is_open(), "the other seat's stays shut")
	check(_hud.get_lectern(1).get_global_rect().get_center().x > _hud.get_lectern(0).get_global_rect().size.x, "in its seat's quarter of the view")
	check(_picked.is_empty(), "opening it picks nothing")


func test_a_on_a_depth_picks_it_and_b_closes_with_nothing() -> void:
	_bus.lectern_changed.emit(0b0001)
	_tap(0, &"accept")
	_frame()
	_tap(0, &"back")
	_frame()
	check(not _hud.get_lectern(0).is_open(), "B closes it")
	check(_picked.is_empty(), "with nothing picked")
	check(not _hud.get_radial(0).is_open(), "and opens no builder")
	_frame()
	_tap(0, &"accept")
	_frame()
	_focus.focus(0, _hud.get_lectern(0).buttons()[5])
	_tap(0, &"accept")
	_frame()
	check_equal(_picked, [[0, 5]], "A on the boss sends the pick, for its seat")
	check(not _hud.get_lectern(0).is_open(), "and closes it")
	_bus.start_depth_changed.emit(5, 6)
	_frame()
	_tap(0, &"accept")
	_frame()
	check_equal(_words(0).back(), "The boss *", "opened again, the party's pick is marked")
	check_equal(_hud.get_lectern(0).buttons()[5].text, "> The boss *", "and focused")
	_tap(0, &"pause")
	_frame()
	check(not _hud.get_lectern(0).is_open() and not _hud.get_pause_menu().is_open(), "Start closes it, opening no pause menu")


func test_it_closes_when_its_seat_leaves_the_lectern_or_the_hub() -> void:
	_bus.lectern_changed.emit(0b0011)
	for seat in 2:
		_tap(seat, &"accept")
	_frame()
	_bus.lectern_changed.emit(0b0010)
	check(not _hud.get_lectern(0).is_open(), "seat 0 walked off: its menu shuts")
	check(_hud.get_lectern(1).is_open(), "seat 1's stays")
	_bus.start_depth_changed.emit(0, 0)
	check(not _hud.get_lectern(1).is_open(), "the hub left: shut")
	_bus.lectern_changed.emit(0b0010)
	_tap(1, &"accept")
	_frame()
	check(not _hud.get_lectern(1).is_open(), "with no depth offered it never opens")


func test_a_downed_seat_opens_nothing() -> void:
	_bus.lectern_changed.emit(0b0001)
	_bus.player_stats_changed.emit(0, 0.0, 100.0, 0.0, 100.0)
	_tap(0, &"accept")
	_frame()
	check(not _hud.get_lectern(0).is_open(), "a downed wizard lying at the lectern opens nothing")
	_bus.player_stats_changed.emit(0, 50.0, 100.0, 0.0, 100.0)
	_frame()
	_tap(0, &"accept")
	_frame()
	check(_hud.get_lectern(0).is_open(), "up again, it opens")


func test_the_lit_stone_and_the_altar_come_first() -> void:
	var runs: Array[int] = []
	var rooms: Array[int] = []
	_bus.run_requested.connect(func(seat: int) -> void: runs.append(seat))
	_bus.online_open_requested.connect(func(seat: int) -> void: rooms.append(seat))
	_bus.lectern_changed.emit(0b0001)
	_bus.altar_changed.emit(0b0001)
	_tap(0, &"accept")
	_frame()
	check(rooms == [0] and not _hud.get_lectern(0).is_open(), "the altar's A first")
	_bus.altar_changed.emit(0)
	_bus.start_stone_changed.emit(2, 2, true)
	_tap(0, &"accept")
	_frame()
	check(runs == [0] and not _hud.get_lectern(0).is_open(), "the lit stone's A first")


func test_the_stone_line_names_where_the_run_starts() -> void:
	var line := own(StoneLineScript.new()) as StoneLineScript
	line.show_stone(1, 2, false)
	check_equal(line.text, "Everyone onto the stone to start: 1 of 2", "the first room: one line")
	line.show_start(2, 6)
	check_equal(line.text, "Everyone onto the stone to start: 1 of 2\nStarts in: Room 3", "past it: where")
	line.show_start(5, 6)
	line.show_stone(2, 2, true)
	check_equal(line.text, "Everyone is on the stone: A (Enter) starts the run\nStarts in: The boss", "the boss's row, lit")
	line.show_stone(0, 0, false)
	check(not line.visible, "out of the hub it hides")


func test_the_depths_in_words() -> void:
	check_equal(DepthWords.of(0, 6), "Room 1", "the first room")
	check_equal(DepthWords.of(4, 6), "Room 5", "a room of its row")
	check_equal(DepthWords.of(5, 6), "The boss", "the last of them")
	check_equal(DepthWords.of(0, 1), "Room 1", "a map of one row starts in its room")


func test_a_depth_picked_is_a_choice() -> void:
	var sounds: Array[StringName] = []
	_bus.ui_sound_requested.connect(func(id: StringName) -> void: sounds.append(id))
	_bus.lectern_changed.emit(0b0001)
	_tap(0, &"accept")
	_frame()
	check(_hud.get_lectern(0).is_open(), "A at the lectern opened it")
	sounds.clear()
	_tap(0, &"accept")
	_frame()
	check_equal(_picked.size(), 1, "a depth picked")
	check_equal(sounds, [UiSounds.CHOOSE], "with a choice's sound")
