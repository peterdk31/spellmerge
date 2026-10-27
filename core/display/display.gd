extends Node
## The game window (owner, 2026-10-27: the web version must run in fullscreen). One autoload,
## `Display`. The `fullscreen` action (F11, or Alt+Enter, which a browser leaves to the page)
## toggles fullscreen anywhere, menus and play alike; the pause menu's Settings page has the same
## switch. `is_fullscreen()` reads the window itself, so a browser leaving fullscreen on its own
## (Escape) is seen at once.
##
## On the web the page asks the browser (`requestFullscreen`), which only allows it right after a
## key press or a click on the page: a gamepad button does not count, so on the web the switch is
## worked with the keyboard or the mouse. The web export already fills the browser window
## (`html/canvas_resize_policy` 2, adaptive); this makes it fill the screen.

## Fullscreen went on or off through `set_fullscreen` (the window may also leave on its own).
signal fullscreen_changed(on: bool)

## How the window mode is read and set; tests swap them for fakes (headless has no window).
var get_mode: Callable = DisplayServer.window_get_mode
var set_mode: Callable = DisplayServer.window_set_mode


func _ready() -> void:
	# Works while the game is paused (the pause menu has the switch).
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"fullscreen") and not event.is_echo():
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


## True when the window fills the screen.
func is_fullscreen() -> bool:
	var mode: int = int(get_mode.call())
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## Fills the screen (`on`) or goes back to a window.
func set_fullscreen(on: bool) -> void:
	if on == is_fullscreen():
		return
	set_mode.call(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	fullscreen_changed.emit(on)


func toggle_fullscreen() -> void:
	set_fullscreen(not is_fullscreen())
