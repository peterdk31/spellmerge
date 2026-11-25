extends "res://tests/support/suite.gd"
## A biome's key doors and secret rocks as the view draws them (connected biomes CB12, decision 30;
## gameplay/feel/lock_looks.gd), driven by their events alone, as CB11 will send them: a key door's
## padlock turns, falls and its bars sink, a frame at a time; a secret rock's crack tint brightens as
## its own element touches the floor near it (not another, not far) and dims again; broken, it breaks
## in stages; -1 forgets them, and after a restore what is told is drawn as it stands.

const LooksScript := preload("res://gameplay/feel/lock_looks.gd")
const EventsScript := preload("res://core/events/events.gd")

const MOUTH: Rect2 = Rect2(Vector2(96.0, 40.0), Vector2(8.0, 64.0))
const ROCK: Rect2 = Rect2(Vector2(320.0, 96.0), Vector2(32.0, 32.0))

var _bus: EventsScript = null
var _looks: LooksScript = null


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_looks = LooksScript.new()
	_looks.registry = root.get_node("Registry")
	root.add_child(own(_looks))
	_looks.set_process(false)
	_looks.bind(_bus)


func _frames_of_door(door: int) -> Array[int]:
	var frames: Array[int] = []
	while _looks.is_moving() and frames.size() < 60:
		_looks.advance()
		frames.append(_looks.door_frame_of(door))
	return frames


func test_a_key_doors_padlock_turns_falls_and_its_bars_sink_a_frame_at_a_time() -> void:
	_bus.key_door_shown.emit(0, MOUTH, false)
	check_equal(_looks.doors(), 1, "the door is drawn")
	check_equal(_looks.door_frame_of(0), 0, "shut, its padlock hung on its bars")
	check(not _looks.is_moving(), "nothing moves while it is shut")
	_bus.key_door_shown.emit(0, MOUTH, true)
	var frames: Array[int] = _frames_of_door(0)
	var expected: Array[int] = []
	for frame in LooksScript.DOOR_FRAMES:
		expected.append(frame + 1)
	check_equal(frames, expected, "turning, falling and sinking: one frame at a time")
	check(LooksScript.TURN_FRAMES >= 3 and LooksScript.FALL_FRAMES >= 3 and LooksScript.BAR_FRAMES >= 3, "each stage has at least 3 frames")


func test_a_key_door_first_told_open_is_drawn_open() -> void:
	_bus.key_door_shown.emit(0, MOUTH, true)
	check_equal(_looks.door_frame_of(0), LooksScript.DOOR_FRAMES, "told open before it was drawn shut (a restore): open")


func test_a_rocks_crack_brightens_near_its_element_and_dims_again() -> void:
	_bus.secret_rock_shown.emit(0, ROCK, &"fire", false)
	check_equal(_looks.rocks(), 1, "the rock is drawn")
	check_equal(_looks.rock_glow_of(0), LooksScript.GLOW_REST, "its crack dim at rest")
	var fire: PackedColorArray = _looks.rock_tint_of(0)
	var card: ElementBase = root.get_node("Registry").call(&"get_resource", &"spells", &"fire") as ElementBase
	check(card != null and fire == Palette.shades_of(LooksScript.nearest_material(card.tint)), "in the palette material nearest its element's tint")
	_bus.floor_touched.emit(0, &"frost", ROCK.get_center(), 16.0, 0)
	check(not _looks.is_moving(), "another element on it: nothing")
	_bus.floor_touched.emit(0, &"fire", ROCK.get_center() + Vector2(400.0, 0.0), 16.0, 0)
	check(not _looks.is_moving(), "its element far away: nothing")
	_bus.floor_touched.emit(0, &"fire", ROCK.position - Vector2(60.0, 0.0), 16.0, 0)
	var glows: Array[int] = []
	while _looks.is_moving():
		_looks.advance()
		glows.append(_looks.rock_glow_of(0))
	check_equal(glows, [2, 3] as Array[int], "its element near: it brightens a shade a frame")
	_looks.pass_time(LooksScript.NEAR_SECONDS + 0.1)
	glows.clear()
	while _looks.is_moving():
		_looks.advance()
		glows.append(_looks.rock_glow_of(0))
	check_equal(glows, [2, 1] as Array[int], "and dims again a shade a frame once it is gone")


func test_a_broken_rock_breaks_in_stages() -> void:
	_bus.secret_rock_shown.emit(0, ROCK, &"water", false)
	_bus.secret_rock_shown.emit(0, ROCK, &"water", true)
	var frames: Array[int] = []
	while _looks.is_moving():
		_looks.advance()
		frames.append(_looks.rock_frame_of(0))
	var expected: Array[int] = []
	for frame in LooksScript.BREAK_FRAMES:
		expected.append(frame + 1)
	check_equal(frames, expected, "its cracks spread, then it is thrown apart, a frame at a time")
	check(LooksScript.SPREAD_FRAMES >= 3 and LooksScript.BREAK_FRAMES - LooksScript.SPREAD_FRAMES >= 3, "each stage at least 3 frames")


func test_a_rocks_tint_is_the_palette_material_nearest_its_element() -> void:
	check_equal(LooksScript.nearest_material(Palette.shades_of(&"ice")[1]), &"ice", "a palette colour is its own material")
	check(not Palette.OWNED.has(LooksScript.nearest_material(Palette.shades_of(&"player_1")[1])), "never a player's colour")


func test_minus_one_forgets_and_after_a_restore_what_is_told_stands() -> void:
	_bus.key_door_shown.emit(0, MOUTH, false)
	_bus.secret_rock_shown.emit(0, ROCK, &"fire", false)
	_bus.key_door_shown.emit(-1, Rect2(), true)
	_bus.secret_rock_shown.emit(-1, Rect2(), &"", true)
	check_equal(_looks.doors(), 0, "every key door forgotten")
	check_equal(_looks.rocks(), 0, "every rock forgotten")
	_bus.key_door_shown.emit(0, MOUTH, false)
	_bus.key_door_shown.emit(1, MOUTH, true)
	_bus.secret_rock_shown.emit(0, ROCK, &"fire", true)
	check(not _looks.is_moving(), "after a restore, what is told is drawn as it stands")
	check_equal(_looks.door_frame_of(1), LooksScript.DOOR_FRAMES, "an open door open")
	check_equal(_looks.rock_frame_of(0), LooksScript.BREAK_FRAMES, "a broken rock gone")


func test_feel_draws_the_key_doors_and_rocks() -> void:
	var feel: Node = root.get_node("Feel")
	check(feel.call("lock_looks") is LooksScript, "Feel draws them")


func test_after_a_restore_a_later_opening_is_played_in() -> void:
	_bus.key_door_shown.emit(-1, Rect2(), true)
	_bus.key_door_shown.emit(0, MOUTH, false)
	_looks._process(0.0)
	_bus.key_door_shown.emit(0, MOUTH, true)
	check_equal(_looks.door_frame_of(0), 0, "a key opening it after the restore's frame: still shut at once")
	check(_looks.is_moving(), "and its padlock turns over its frames")
