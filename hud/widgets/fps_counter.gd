extends Label
## The frame rate readout (owner, 2026-11-02): "60 FPS" in small type with an outline, shown while
## the pause menu's "Show FPS" switch is on (`hud/panels` sets `visible`). It reads the engine's
## frames per second (`Engine.get_frames_per_second()`, an average over the last second) and
## writes it when the number changes, at most every UPDATE_SECONDS, so it makes no string a frame.
## It keeps counting while the game is paused.

const FONT_SIZE: int = 10
const OUTLINE: int = 3
const TEXT: String = "%d FPS"
## How often the number is read, in real seconds.
const UPDATE_SECONDS: float = 0.25

## The number shown, or -1 before the first read.
var shown_fps: int = -1
var _since: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override(&"font_size", FONT_SIZE)
	add_theme_constant_override(&"outline_size", OUTLINE)
	add_theme_color_override(&"font_outline_color", Color.BLACK)
	refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_since += delta
	if _since >= UPDATE_SECONDS:
		_since = 0.0
		refresh()


## Read the frame rate now and write it if it changed.
func refresh() -> void:
	var fps: int = roundi(Engine.get_frames_per_second())
	if fps != shown_fps:
		shown_fps = fps
		text = TEXT % fps
