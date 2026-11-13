extends "res://tests/support/suite.gd"
## The room's code over the hub's altar (online lobby L5c; gameplay/feel/altar_code.gd): shown
## while the bus names an open room and an altar stands, over the altar's place, and only a text
## that is a room's code.

const AltarCodeScript := preload("res://gameplay/feel/altar_code.gd")
const EventsScript := preload("res://core/events/events.gd")

const AT: Vector2 = Vector2(320.0, 200.0)

var _bus: EventsScript = null
var _code: Label = null


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	var code := AltarCodeScript.new()
	root.add_child(own(code))
	code.bind(_bus)
	_code = code


func test_the_open_rooms_code_stands_over_the_altar() -> void:
	check(not _code.visible, "hidden with nothing said")
	_bus.altar_placed.emit(true, AT)
	check(not _code.visible, "an altar and no open room: hidden")
	_bus.online_line_changed.emit({OnlineWhy.LINE_ROOM: "KQ7RM"}, "")
	check(_code.visible and _code.text == "KQ7RM", "the room is open: its code shows")
	var box: Rect2 = Rect2(_code.position, _code.size)
	check(absf(box.get_center().x - AT.x) <= 1.0 and box.end.y <= AT.y and box.end.y >= AT.y - 8.0, "centred just over the altar's place, got %s" % box)
	_bus.online_line_changed.emit({OnlineWhy.LINE_ROOM: "KQ7RM", OnlineWhy.LINE_JOINED: 1}, "host: 2 machines")
	check(_code.visible and _code.text == "KQ7RM", "it stays while machines are in the room")
	_bus.altar_placed.emit(false, Vector2.ZERO)
	check(not _code.visible, "the hub left (no altar): hidden")
	_bus.altar_placed.emit(true, AT)
	check(_code.visible, "back in the hub with the room still open: shown again")
	_bus.online_line_changed.emit({}, "host: 2 machines")
	check(not _code.visible, "the room closed under the run (the line names none): hidden")


func test_only_a_rooms_code_is_ever_shown() -> void:
	_bus.altar_placed.emit(true, AT)
	_bus.online_line_changed.emit({OnlineWhy.LINE_ROOM: "SM1.a-long-code-by-hand-is-no-rooms-code"}, "")
	check(not _code.visible, "a machine's own long code is not a room's")
	_bus.online_line_changed.emit({OnlineWhy.LINE_ROOM: "a b<c"}, "")
	check(not _code.visible, "nor anything but letters and digits")
	_bus.online_line_changed.emit({OnlineWhy.LINE_ROOM: 5}, "")
	check(not _code.visible, "nor what is no text")
