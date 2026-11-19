extends "res://tests/support/suite.gd"
## The loading screen (hud/panels/loading/): up for a load (`loading_started` to `loading_finished`,
## with its bar) and for the party's departure from the hub's stone (`run_departure_changed`, no
## bar); it comes down from above over COVER_FRAMES frames and goes back up the same way, by whole
## pixels and never in one jump (docs/STYLE.md, "Smooth"), and turns round where it is. Its frames
## are stepped by hand (`advance`), on a bus of its own.

const ScreenScript := preload("res://hud/panels/loading/loading_screen.gd")
const EventsScript := preload("res://core/events/events.gd")
const LoadingScript := preload("res://core/loading/loading.gd")

var _bus: EventsScript = null
var _screen: ScreenScript = null


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_screen = ScreenScript.new()
	_screen.events = _bus
	root.add_child(own(_screen))
	_screen.set_process(false)


## Its top edge in each of `frames` frames, stepped by hand.
func _tops(frames: int) -> Array[float]:
	var out: Array[float] = []
	for i in frames:
		_screen.advance()
		# Shown on a paused tree too: nothing else steps it.
		_screen.set_process(false)
		out.append(_screen.position.y)
	return out


func test_a_departure_brings_it_down_and_the_runs_start_takes_it_up() -> void:
	check(not _screen.visible, "hidden at first")
	_bus.run_departure_changed.emit(true)
	check(_screen.visible and _screen.is_up(), "a departure shows it")
	check(not _screen.is_down(), "but it is not down yet")
	var height: float = _screen.get_viewport_rect().size.y
	check_equal(_screen.position.y, -height, "it starts just above the screen")
	var down: Array[float] = _tops(ScreenScript.COVER_FRAMES)
	check(_screen.is_down(), "down after COVER_FRAMES frames")
	check_equal(down.back(), 0.0, "covering everything")
	check(ScreenScript.COVER_FRAMES >= 3, "a change of look plays at least 3 frames")
	var last: float = -height
	for top in down:
		check(top > last, "it moves down every frame (%s after %s)" % [top, last])
		check_equal(top, roundf(top), "by whole pixels")
		last = top
	check(not (_screen.get_child(0).get_child(1) as Control).visible, "no bar: a departure has nothing to count")
	_bus.run_departure_changed.emit(false)
	check(not _screen.is_up(), "the run's start lets it go")
	check(_screen.visible, "but it does not vanish")
	var up: Array[float] = _tops(ScreenScript.COVER_FRAMES)
	check_equal(up.back(), -height, "it goes back up the same way")
	check(not _screen.visible, "and is hidden there")


func test_it_turns_round_where_it_is() -> void:
	_bus.run_departure_changed.emit(true)
	var down: Array[float] = _tops(2)
	_bus.run_departure_changed.emit(false)
	var up: Array[float] = _tops(1)
	check(up[0] < down[1] and up[0] > -_screen.get_viewport_rect().size.y, "wanted no more half way down: it goes up from where it was")
	_bus.run_departure_changed.emit(true)
	check_equal(_tops(1)[0], down[1], "wanted again: down from there")


func test_a_load_shows_its_bar_and_is_down_before_its_first_unit() -> void:
	_bus.loading_started.emit()
	check(_screen.is_up(), "a load shows it")
	check((_screen.get_child(0).get_child(1) as Control).visible, "with its bar")
	check(ScreenScript.COVER_FRAMES < LoadingScript.WAIT_FRAMES, "down before the load's first unit freezes the game")
	check(ScreenScript.COVER_FRAMES < HubRules.DEPART_TICKS, "and before a departure's run is built")
	_bus.loading_progressed.emit(1, 4)
	check_equal(_screen.progress(), 0.25, "the bar follows the load")
	_bus.run_departure_changed.emit(true)
	_bus.loading_finished.emit()
	check(_screen.is_up(), "still up while a departure wants it")
	_bus.run_departure_changed.emit(false)
	check(not _screen.is_up(), "and lets go when nothing does")
	check_equal(_screen.mouse_filter, Control.MOUSE_FILTER_IGNORE, "it takes no input")
