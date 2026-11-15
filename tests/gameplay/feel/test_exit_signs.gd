extends "res://tests/support/suite.gd"
## The names over a run's lit exits (run generation RG4; gameplay/feel/exit_signs.gd): one over each
## exit the bus names, the kind of room behind it by its name for people, centred just over the exit;
## gone when no exit is lit. And Feel's own reads the names from the registry's room kinds.

const ExitSignsScript := preload("res://gameplay/feel/exit_signs.gd")
const EventsScript := preload("res://core/events/events.gd")

const LEFT: Vector2 = Vector2(272.0, 40.0)
const RIGHT: Vector2 = Vector2(368.0, 40.0)

var _bus: EventsScript = null
var _signs: ExitSignsScript = null


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_signs = ExitSignsScript.new()
	root.add_child(own(_signs))
	_signs.bind(_bus, func(kind: StringName) -> String: return "The " + String(kind))


func test_each_lit_exit_shows_the_kind_behind_it() -> void:
	check_equal(_signs.shown(), PackedStringArray(), "nothing shown with nothing said")
	_bus.room_exits_shown.emit(PackedVector2Array([LEFT, RIGHT]), [&"fight", &"boss"] as Array[StringName])
	check_equal(_signs.shown(), PackedStringArray(["The fight", "The boss"]), "a name over each exit")
	var label := _signs.get_child(0) as Label
	var box: Rect2 = Rect2(label.position, label.size)
	check(absf(box.get_center().x - LEFT.x) <= 1.0 and box.end.y <= LEFT.y and box.end.y >= LEFT.y - 8.0, "centred just over its exit, got %s" % box)
	_bus.room_exits_shown.emit(PackedVector2Array(), [] as Array[StringName])
	check_equal(_signs.shown(), PackedStringArray(), "none lit: none shown")


func test_feel_names_a_kind_as_its_data_does() -> void:
	var feel: Node = root.get_node("Feel")
	var signs := feel.call("exit_signs") as ExitSignsScript
	check(signs != null, "Feel has the exit signs")
	if signs == null:
		return
	check_equal(String(signs.name_of.call(&"boss")), "Boss", "the boss kind's display name")
	check_equal(String(signs.name_of.call(&"no_such_kind")), "No Such Kind", "an unknown kind in words")
