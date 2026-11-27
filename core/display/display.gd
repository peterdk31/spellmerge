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
##
## **How the picture is stretched to the window** (the owner's decision of 2026-11-25; docs/STYLE.md,
## "The picture and the art's detail"): the 1280 x 720 picture is drawn to the window by whole
## numbers (project.godot), unless that leaves the window mostly empty: where the largest whole
## number fills less than FILL_LEAST of the window's width or height the picture is stretched by the
## largest factor that fits, its aspect kept and its pixels hard (nearest), so a 1920 x 1080 screen
## shows it 1.5 times, each picture pixel 1 or 2 screen pixels. A 2560 x 1440 or 3840 x 2160 screen
## stays at 2 and 3. `stretch_for(window, picture)` decides, every time the window's size changes.
## View only: nothing in the game reads it.
##
## It also makes the game's pixel font every theme's default as the game starts (`PixelFont.install`).

## Fullscreen went on or off through `set_fullscreen` (the window may also leave on its own).
signal fullscreen_changed(on: bool)

## The least share of the window's width or height that whole-number scaling must fill; below it the
## picture is stretched by a fraction (1280 x 720 at 1 on 1920 x 1080 fills two thirds; on a
## 1366 x 768 laptop 94%, which stays whole).
const FILL_LEAST: float = 0.85

## How the window mode is read and set; tests swap them for fakes (headless has no window).
var get_mode: Callable = DisplayServer.window_get_mode
var set_mode: Callable = DisplayServer.window_set_mode


func _enter_tree() -> void:
	# The game's pixel font, the default of every theme before anything draws text (core/display/pixel_font.gd).
	PixelFont.install()


func _ready() -> void:
	# Works while the game is paused (the pause menu has the switch).
	process_mode = Node.PROCESS_MODE_ALWAYS
	var window: Window = get_tree().root
	window.size_changed.connect(_fit_stretch)
	_fit_stretch()


## Whole-number or fractional stretching for a window of `window` px showing a picture of `picture`
## px (`Window.CONTENT_SCALE_STRETCH_*`): whole numbers while the largest that fits fills at least
## FILL_LEAST of the window's width or height, and the picture fits at least once; a fraction
## otherwise.
static func stretch_for(window: Vector2, picture: Vector2) -> Window.ContentScaleStretch:
	if picture.x <= 0.0 or picture.y <= 0.0 or window.x <= 0.0 or window.y <= 0.0:
		return Window.CONTENT_SCALE_STRETCH_INTEGER
	var fit: float = minf(window.x / picture.x, window.y / picture.y)
	var whole: float = floorf(fit + 0.0001)
	if whole < 1.0:
		return Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	var filled: float = maxf(picture.x * whole / window.x, picture.y * whole / window.y)
	return Window.CONTENT_SCALE_STRETCH_INTEGER if filled >= FILL_LEAST else Window.CONTENT_SCALE_STRETCH_FRACTIONAL


func _fit_stretch() -> void:
	var window: Window = get_tree().root
	var stretch: Window.ContentScaleStretch = stretch_for(Vector2(window.size), Vector2(window.content_scale_size))
	if window.content_scale_stretch != stretch:
		window.content_scale_stretch = stretch


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
