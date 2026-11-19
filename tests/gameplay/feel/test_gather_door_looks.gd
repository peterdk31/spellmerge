extends "res://tests/support/suite.gd"
## A biome's gather doors as the view draws them (connected biomes CB7; gameplay/feel/gather_door_looks.gd):
## from the bus alone; Smooth (docs/STYLE.md): a door's bars sink over its frames, never in one jump,
## each lamp steps through its shades, the portal opens out over frames; door -1 forgets them all.

const LooksScript := preload("res://gameplay/feel/gather_door_looks.gd")
const EventsScript := preload("res://core/events/events.gd")

const MOUTH: Rect2 = Rect2(Vector2(96.0, 40.0), Vector2(8.0, 64.0))

var _bus: EventsScript = null
var _looks: LooksScript = null


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_looks = LooksScript.new()
	root.add_child(own(_looks))
	_looks.set_process(false)
	_looks.bind(_bus)


func _advance_until_still(most: int = 40) -> int:
	var frames: int = 0
	while _looks.is_moving() and frames < most:
		_looks.advance()
		frames += 1
	return frames


func test_a_shut_door_shows_a_lamp_for_each_standing_wizard_lit_in_stages() -> void:
	_bus.gather_door_shown.emit(0, RoomKind.DOOR_GATE, MOUTH, 0, 2, false, false)
	check_equal(_looks.doors(), 1, "the door is drawn")
	check_equal(_looks.frame_of(0), 0, "shut: its bars up")
	_advance_until_still()
	check_equal(_looks.lamps_of(0), PackedInt32Array([1, 1]), "two lamps, unlit")
	_bus.gather_door_shown.emit(0, RoomKind.DOOR_GATE, MOUTH, 1, 2, false, false)
	var shades: Array[int] = []
	while _looks.is_moving():
		_looks.advance()
		shades.append(_looks.lamps_of(0)[0])
	check_equal(shades, [2, 3] as Array[int], "the first lights in stages, one shade a frame")
	check_equal(_looks.lamps_of(0)[1], 1, "the second stays unlit")


func test_an_opening_door_sinks_over_its_frames() -> void:
	_bus.gather_door_shown.emit(0, RoomKind.DOOR_GATHER, MOUTH, 1, 1, false, false)
	_advance_until_still()
	_bus.gather_door_shown.emit(0, RoomKind.DOOR_GATHER, MOUTH, 1, 1, false, true)
	var frames: Array[int] = []
	while _looks.is_moving():
		_looks.advance()
		frames.append(_looks.frame_of(0))
	check(frames.size() >= 3, "at least 3 frames between shut and open: %s" % [frames])
	check_equal(frames.slice(0, LooksScript.OPEN_FRAMES), [1, 2, 3, 4, 5, 6] as Array[int], "a frame at a time")
	check_equal(_looks.lamps_of(0), PackedInt32Array(), "its lamps go out with it, in stages")


func test_a_door_first_told_open_is_drawn_open() -> void:
	_bus.gather_door_shown.emit(0, RoomKind.DOOR_GATE, MOUTH, 2, 2, false, true)
	check_equal(_looks.frame_of(0), LooksScript.OPEN_FRAMES, "a door told open before it was drawn shut (a restore) is open")


func test_the_portal_opens_out_over_frames() -> void:
	_bus.gather_door_shown.emit(1, RoomKind.DOOR_PORTAL_HOME, Rect2(200.0, 200.0, 48.0, 48.0), 0, 2, false, true)
	check_equal(_looks.frame_of(1), 0, "the portal starts closed")
	check_equal(_advance_until_still(), LooksScript.OPEN_FRAMES, "it opens over its frames")
	check_equal(_looks.frame_of(1), LooksScript.OPEN_FRAMES, "open")
	check_equal(_looks.lamps_of(1), PackedInt32Array([1, 1]), "with a lamp for each standing wizard")


func test_door_minus_one_forgets_every_door() -> void:
	_bus.gather_door_shown.emit(0, RoomKind.DOOR_GATE, MOUTH, 0, 1, false, false)
	_bus.gather_door_shown.emit(-1, &"", Rect2(), 0, 0, false, false)
	check_equal(_looks.doors(), 0, "every door forgotten")


func test_feel_has_the_gather_doors() -> void:
	var feel: Node = root.get_node("Feel")
	check(feel.call("gather_doors") is LooksScript, "Feel draws the gather doors")
