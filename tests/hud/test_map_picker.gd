extends "res://tests/support/suite.gd"
## The pick on the open Y map (the owner, 2026-11-19; hud/panels/map_picker.gd): while the map is
## held and Flow says there are rooms to go to (`teleport_rooms_shown`), a room is picked (the last
## one if it still may be, else the first), a flick of the stick moves it to the nearest room that
## way, A sends `map_teleport_requested` once a press, and the pick is told to the view
## (`map_pick_changed`), none as the map is let go.

const EventsScript := preload("res://core/events/events.gd")
const MapPickerScript := preload("res://hud/panels/map_picker.gd")

var _bus: EventsScript
var _picker: MapPickerScript
var _asked: Array = []
var _picks: Array = []


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_picker = MapPickerScript.new()
	_picker.bind(_bus)
	_asked = []
	_picks = []
	_bus.map_teleport_requested.connect(func(seat: int, room: int) -> void: _asked.append([seat, room]))
	_bus.map_pick_changed.connect(func(seat: int, room: int) -> void: _picks.append([seat, room]))
	# Three rooms: the start room in the middle, one west of it, one north-east of it.
	_bus.teleport_rooms_shown.emit(0, PackedInt32Array([0, 3, 5]), PackedVector2Array([Vector2(500, 500), Vector2(100, 500), Vector2(900, 100)]))


func test_nothing_is_picked_while_the_map_is_shut() -> void:
	check(not _picker.poll(0, false, Vector2.ZERO, true), "A with the map shut is not the map's")
	check_equal(_picker.pick_of(0), MapPickerScript.NONE, "nothing picked")
	check(_asked.is_empty(), "no teleport asked")


func test_held_a_room_is_picked_and_a_flick_moves_it_that_way() -> void:
	_picker.poll(0, true, Vector2.ZERO, false)
	check_equal(_picker.pick_of(0), 0, "the first room picked")
	check_equal(_picks.back(), [0, 0], "told to the view")
	_picker.poll(0, true, Vector2(-1, 0), false)
	check_equal(_picker.pick_of(0), 3, "a flick west: the room west")
	_picker.poll(0, true, Vector2(-1, 0), false)
	check_equal(_picker.pick_of(0), 3, "held over, it moves no further (one room a flick)")
	_picker.poll(0, true, Vector2.ZERO, false)
	_picker.poll(0, true, Vector2(-1, 0), false)
	check_equal(_picker.pick_of(0), 3, "nothing further west: it stays")
	_picker.poll(0, true, Vector2.ZERO, false)
	_picker.poll(0, true, Vector2(1, 0), false)
	check_equal(_picker.pick_of(0), 0, "a flick east: back to the middle room")
	_picker.poll(0, true, Vector2.ZERO, false)
	_picker.poll(0, true, Vector2(0.7, -0.7), false)
	check_equal(_picker.pick_of(0), 5, "a flick north-east: the room that way")


func test_a_sends_the_teleport_once_and_letting_go_clears_the_pick() -> void:
	_picker.poll(0, true, Vector2.ZERO, false)
	check(_picker.poll(0, true, Vector2.ZERO, true), "A on the open map is the map's")
	check_equal(_asked, [[0, 0]], "the teleport asked, once")
	_picker.poll(0, true, Vector2.ZERO, false)
	check_equal(_asked.size(), 1, "no second ask without a press")
	_picker.poll(0, false, Vector2.ZERO, false)
	check_equal(_picker.pick_of(0), MapPickerScript.NONE, "let go: no pick")
	check_equal(_picks.back(), [0, MapPickerScript.NONE], "told to the view")


func test_nowhere_to_go_picks_nothing_and_a_is_not_the_maps() -> void:
	_bus.teleport_rooms_shown.emit(0, PackedInt32Array(), PackedVector2Array())
	check(not _picker.poll(0, true, Vector2.ZERO, true), "in a fight A is not the map's")
	check(_asked.is_empty(), "no teleport asked")
	check_equal(_picker.pick_of(1), MapPickerScript.NONE, "another seat has nothing")


func test_the_last_pick_is_kept_while_it_may_still_be_gone_to() -> void:
	_picker.poll(0, true, Vector2.ZERO, false)
	_picker.poll(0, true, Vector2(-1, 0), false)
	_picker.poll(0, false, Vector2.ZERO, false)
	_picker.poll(0, true, Vector2.ZERO, false)
	check_equal(_picker.pick_of(0), 3, "opened again: the room picked last")
