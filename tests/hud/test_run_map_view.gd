extends "res://tests/support/suite.gd"
## The run's map on screen (run generation RG8; hud/widgets/run_map_view.gd): it shows what the bus
## says (`run_map_changed`) and nothing else: its rooms row by row, the party's room, the rooms it can
## still reach, the kinds' letters and names, "Room 2 of 3"; empty, it has no map and no size.

const EventsScript := preload("res://core/events/events.gd")
const ViewScript := preload("res://hud/widgets/run_map_view.gd")
const Theme_ := preload("res://hud/theme/spellmerge_theme.tres")

var bus: EventsScript
var view: ViewScript
var changes: int = 0


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	view = ViewScript.new()
	view.theme = Theme_
	own(view)
	root.add_child(view)
	view.bind(bus)
	changes = 0
	view.map_changed.connect(func() -> void: changes += 1)


func after_each() -> void:
	if view.is_inside_tree():
		root.remove_child(view)


## A map of three rows: room 0 leads to 1 and 2, 1 to 3, 2 to 3 (the boss).
func _tell(at: int) -> void:
	var links: Array[PackedInt32Array] = [PackedInt32Array([1, 2]), PackedInt32Array([3]), PackedInt32Array([3]), PackedInt32Array()]
	bus.run_map_changed.emit(PackedInt32Array([0, 1, 1, 2]), [&"fight", &"fight", &"fight", &"boss"] as Array[StringName], links, at)


func test_it_shows_the_map_the_bus_tells() -> void:
	check(not view.has_map(), "no map before one is told")
	check_equal(view.custom_minimum_size, Vector2.ZERO, "and no size")
	_tell(0)
	check(view.has_map(), "a map")
	check_equal(changes, 1, "told as it changes")
	check_equal(view.depth(), 3, "three rows deep")
	check_equal(view.here_line(), "Room 1 of 3", "where the party is")
	check_equal(view.kinds_line(), "F Fight  B Boss", "each kind's letter and name, once, as they first stand")
	check(view.custom_minimum_size.x > 0.0 and view.custom_minimum_size.y > 0.0, "it takes room for the map")


func test_the_rooms_stand_in_their_rows() -> void:
	_tell(0)
	view.size = view.custom_minimum_size
	var first: Vector2 = view.room_middle(0)
	var left: Vector2 = view.room_middle(1)
	var right: Vector2 = view.room_middle(2)
	var boss: Vector2 = view.room_middle(3)
	check(first.y < left.y and left.y == right.y and right.y < boss.y, "row by row, the first at the top")
	check(left.x < right.x, "a row's rooms left to right")
	check(absf(first.x - (left.x + right.x) * 0.5) <= 1.0 and absf(boss.x - first.x) <= 0.5, "each row centred")
	var inside := Rect2(Vector2.ZERO, view.size)
	for index in 4:
		check(inside.has_point(view.room_middle(index)), "room %d within the map's size" % index)


func test_the_rooms_out_of_reach_are_known() -> void:
	_tell(0)
	check_equal(Array(view.reachable()), [0, 1, 2, 3], "from the first room every room can be reached")
	_tell(2)
	check_equal(Array(view.reachable()), [2, 3], "from the right room: itself and the boss; the left room and the first not")
	check_equal(view.here_line(), "Room 2 of 3", "its row")
	_tell(3)
	check_equal(Array(view.reachable()), [3], "the boss's room: itself")


func test_an_empty_map_takes_it_away() -> void:
	_tell(1)
	bus.run_map_changed.emit(PackedInt32Array(), [] as Array[StringName], [] as Array[PackedInt32Array], -1)
	check(not view.has_map(), "no map")
	check_equal(view.here_line(), "", "nowhere")
	check_equal(view.custom_minimum_size, Vector2.ZERO, "no size")
	check_equal(changes, 2, "told both times")


func test_the_kinds_are_named_as_it_is_told() -> void:
	view.name_of = func(kind: StringName) -> String: return "Battle" if kind == &"fight" else "The broom"
	_tell(0)
	check_equal(view.kinds_line(), "B Battle  T The broom", "the names it is given, and their first letters")


func test_what_it_holds_is_a_copy() -> void:
	var links: Array[PackedInt32Array] = [PackedInt32Array([1]), PackedInt32Array()]
	bus.run_map_changed.emit(PackedInt32Array([0, 1]), [&"fight", &"boss"] as Array[StringName], links, 0)
	links[0].append(5)
	links.append(PackedInt32Array())
	check_equal(view.links.size(), 2, "its own list of rooms")
