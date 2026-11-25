extends "res://tests/support/suite.gd"
## `core/display` (the `Display` autoload): the `fullscreen` action (F11, Alt+Enter) and
## `toggle_fullscreen` switch the window between fullscreen and windowed, read from the window
## itself (owner, 2026-10-27: the web version must run in fullscreen). The window is faked:
## headless has none.
const DisplayScript := preload("res://core/display/display.gd")

var _mode: int = DisplayServer.WINDOW_MODE_WINDOWED
var _sets: Array[int] = []


func _display() -> DisplayScript:
	_mode = DisplayServer.WINDOW_MODE_WINDOWED
	_sets.clear()
	var display: DisplayScript = own(DisplayScript.new()) as DisplayScript
	display.get_mode = func() -> int: return _mode
	display.set_mode = func(mode: int) -> void:
		_mode = mode
		_sets.append(mode)
	return display


func test_toggle_goes_fullscreen_and_back() -> void:
	var display: DisplayScript = _display()
	var heard: Array[bool] = []
	display.fullscreen_changed.connect(func(on: bool) -> void: heard.append(on))
	check(not display.is_fullscreen(), "a window to start with")
	display.toggle_fullscreen()
	check(display.is_fullscreen(), "fullscreen")
	check_equal(_sets, [DisplayServer.WINDOW_MODE_FULLSCREEN] as Array[int], "it asked for fullscreen")
	display.toggle_fullscreen()
	check(not display.is_fullscreen(), "and back to a window")
	check_equal(heard, [true, false] as Array[bool], "told both times")


func test_it_reads_the_window_itself() -> void:
	var display: DisplayScript = _display()
	display.toggle_fullscreen()
	_mode = DisplayServer.WINDOW_MODE_WINDOWED
	check(not display.is_fullscreen(), "a browser leaving fullscreen on its own is seen")
	display.toggle_fullscreen()
	check(display.is_fullscreen(), "so the next toggle goes back in, not out")


func test_setting_what_it_is_changes_nothing() -> void:
	var display: DisplayScript = _display()
	display.set_fullscreen(false)
	check(_sets.is_empty(), "already windowed: no call")


func test_the_action_is_bound_to_f11_and_alt_enter() -> void:
	check(InputMap.has_action(&"fullscreen"), "the fullscreen action exists")
	var keys: Array[String] = []
	for event: InputEvent in InputMap.action_get_events(&"fullscreen"):
		var key := event as InputEventKey
		if key != null:
			keys.append(("Alt+" if key.alt_pressed else "") + OS.get_keycode_string(key.physical_keycode))
	check(keys.has("F11") and keys.has("Alt+Enter"), "F11 and Alt+Enter (got %s)" % [keys])


func test_the_action_toggles() -> void:
	var display: DisplayScript = _display()
	root.add_child(display)
	var press := InputEventKey.new()
	press.physical_keycode = KEY_F11
	press.pressed = true
	display._unhandled_input(press)
	check(display.is_fullscreen(), "F11 fills the screen")


## The owner's decision of 2026-11-25: whole numbers where they fill the screen, a fraction (aspect
## kept, hard pixels) where they would leave it mostly empty: 1080p shows the 1280 x 720 picture 1.5
## times; 720p, 1440p and 4K stay whole; a 1366 x 768 laptop keeps its thin borders; a window smaller
## than the picture shrinks it.
func test_the_picture_is_stretched_by_whole_numbers_unless_they_leave_the_screen_empty() -> void:
	var picture := Vector2(1280.0, 720.0)
	var whole: int = Window.CONTENT_SCALE_STRETCH_INTEGER
	var fraction: int = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	check_equal(int(DisplayScript.stretch_for(Vector2(1280.0, 720.0), picture)), whole, "720p: once")
	check_equal(int(DisplayScript.stretch_for(Vector2(1920.0, 1080.0), picture)), fraction, "1080p: 1.5 times, not once in a frame")
	check_equal(int(DisplayScript.stretch_for(Vector2(2560.0, 1440.0), picture)), whole, "1440p: twice")
	check_equal(int(DisplayScript.stretch_for(Vector2(3840.0, 2160.0), picture)), whole, "4K: three times")
	check_equal(int(DisplayScript.stretch_for(Vector2(1366.0, 768.0), picture)), whole, "1366 x 768: once, nearly full")
	check_equal(int(DisplayScript.stretch_for(Vector2(1920.0, 1200.0), picture)), fraction, "1920 x 1200: a fraction")
	check_equal(int(DisplayScript.stretch_for(Vector2(1000.0, 600.0), picture)), fraction, "a small window: shrunk")
	var root_window: Window = root
	check_equal(int(root_window.content_scale_stretch), int(DisplayScript.stretch_for(Vector2(root_window.size), Vector2(root_window.content_scale_size))), "the game's window follows the rule")
