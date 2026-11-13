extends "res://tests/support/suite.gd"
## The online line (netcode spike S4; hud/widgets/online_line.gd): hidden until there is
## something to say of playing with other machines, then what `online_changed` gives a reason
## for, in the HUD's words, and the line of `online_line_changed` (its facts worded, the counters
## as they come).

const OnlineLineScript := preload("res://hud/widgets/online_line.gd")
const EventsScript := preload("res://core/events/events.gd")

var _bus: EventsScript = null
var _line: Label = null


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	var line := OnlineLineScript.new()
	root.add_child(own(line))
	line.bind(_bus)
	_line = line


func test_it_shows_what_the_bus_says_and_hides_with_nothing_to_say() -> void:
	check(not _line.visible, "hidden offline")
	_bus.online_changed.emit(&"code", "SM1.code", &"", {})
	check(not _line.visible, "and while the codes are swapped (the menu's business)")
	_bus.online_changed.emit(&"playing", "", &"", {})
	check(_line.visible and _line.text != "", "shown once the run plays")
	_bus.online_line_changed.emit({}, "client: ping 40 ms")
	check_equal(_line.text, "client: ping 40 ms", "the counters as they were sent")
	_bus.online_line_changed.emit({OnlineWhy.LINE_CATCHING_UP: true}, "client: ping 40 ms")
	check_equal(_line.text, "Catching up with the host. client: ping 40 ms", "a fact of the run is worded before them")
	_bus.online_changed.emit(&"ended", "", OnlineWhy.HOST_LEFT, {OnlineWhy.AFTER: OnlineWhy.SILENT, OnlineWhy.SECONDS: 10})
	check_equal(_line.text, "The host left; the run plays on here, alone. (Nothing was heard from the other machine for 10 seconds.) Catching up with the host. client: ping 40 ms", "the other machine gone: said, with why its link closed, before the counters still there")
	_bus.online_line_changed.emit({}, "")
	check_equal(_line.text, "The host left; the run plays on here, alone. (Nothing was heard from the other machine for 10 seconds.)", "the line cleared: only what was said")
	_bus.run_started.emit(1)
	check(not _line.visible, "a new run: what was said of the last is gone")
	_bus.online_changed.emit(&"ended", "", OnlineWhy.HOST_LEFT, {})
	_bus.online_changed.emit(&"off", "", &"", {})
	check(not _line.visible, "nothing online and nothing to say hides it")
	check_equal(_line.mouse_filter, Control.MOUSE_FILTER_IGNORE, "it takes no input")


func test_hushed_it_leaves_the_reason_to_whoever_says_it() -> void:
	call_group(OnlineLineScript.GROUP, &"hush", true)
	_bus.online_changed.emit(&"failed", "", OnlineWhy.NO_ROOM, {OnlineWhy.ROOM: "ABCDE"})
	check(not _line.visible, "hushed (the main menu's online box is open and says it): the reason is not said twice")
	call_group(OnlineLineScript.GROUP, &"hush", false)
	check_equal(_line.text, "No room has the code ABCDE.", "let speak again, it says what stands")


func test_a_room_in_the_hub_says_its_code_and_what_went_wrong() -> void:
	_bus.online_changed.emit(&"failed", "", OnlineWhy.NO_SERVER, {})
	check_equal(_line.text, "The room server could not be reached.", "a room that could not be opened says why: no menu is open in the hub to say it")
	_bus.online_changed.emit(&"making", "", &"", {})
	check(not _line.visible, "asked again: what was said is gone")
	_bus.online_changed.emit(&"code", "ABCDE", &"", {})
	_bus.online_line_changed.emit({OnlineWhy.LINE_ROOM: "ABCDE"}, "")
	check_equal(_line.text, "Online room ABCDE: the code other machines join by.", "the room's code")
	_bus.online_changed.emit(&"code", "ABCDE", OnlineWhy.OUT_OF_HUB, {})
	check(_line.text.begins_with("A machine came while the party was out of the hub") and _line.text.ends_with("the code other machines join by."), "a machine turned away is said, and the code stays (%s)" % _line.text)
	_bus.online_changed.emit(&"playing", "ABCDE", &"", {})
	_bus.online_line_changed.emit({OnlineWhy.LINE_ROOM: "ABCDE", OnlineWhy.LINE_JOINED: 2}, "host: 3 kB/s")
	check_equal(_line.text, "Room ABCDE, 2 machine(s) joined. host: 3 kB/s", "the run: who is in, then the counters")
	_bus.online_line_changed.emit({OnlineWhy.LINE_PARTED_TICK: 96, OnlineWhy.LINE_PARTED_AREAS: PackedStringArray(["actors", "shots"])}, "host: 3 kB/s")
	check_equal(_line.text, "PARTED at tick 96 (actors, shots). host: 3 kB/s", "the machines parted: where")
	_bus.online_changed.emit(&"failed", "", OnlineWhy.ROOM_CLOSED, {})
	check_equal(_line.text, "The room is closed.", "failed: the line of before is gone with the room")
