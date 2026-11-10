extends "res://tests/support/suite.gd"
## The online line (netcode spike S4; hud/widgets/online_line.gd): hidden until a run is played
## with another machine, then the text of `online_line_changed` as it is, and what
## `online_changed` says when the other machine leaves.

const OnlineLineScript := preload("res://hud/widgets/online_line.gd")
const EventsScript := preload("res://core/events/events.gd")


func test_it_shows_what_the_bus_says_and_hides_with_nothing_to_say() -> void:
	var bus := own(EventsScript.new()) as EventsScript
	var line := OnlineLineScript.new()
	root.add_child(own(line))
	line.bind(bus)
	check(not line.visible, "hidden offline")
	bus.online_changed.emit(&"code", "SM1.code", "")
	check(not line.visible, "and while the codes are swapped (the menu's business)")
	bus.online_changed.emit(&"playing", "", "")
	check(line.visible and line.text != "", "shown once the run plays")
	bus.online_line_changed.emit("client: ping 40 ms")
	check_equal(line.text, "client: ping 40 ms", "the line as it was sent")
	bus.online_changed.emit(&"ended", "", "The host left; the run plays on here, alone.")
	check_equal(line.text, "The host left; the run plays on here, alone.", "the other machine gone: said")
	bus.online_line_changed.emit("")
	check(not line.visible, "an empty line hides it")
	check_equal(line.mouse_filter, Control.MOUSE_FILTER_IGNORE, "it takes no input")
