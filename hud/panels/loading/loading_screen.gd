extends ColorRect
## The loading screen (owner, 2026-10-29): over everything, in the boot screen's colour, from
## `loading_started` to `loading_finished` (flow, while the game's shaders compile before the
## first room), with "Loading" and a bar that fills from `loading_progressed`. It takes no input
## and holds nobody up: the run starts the moment it is done.

const EventsScript := preload("res://core/events/events.gd")
## The boot screen's colour (`application/boot_splash/bg_color`), so the screen does not flash.
const BACKING: Color = Color(0.105882, 0.0941176, 0.188235, 1.0)
const BAR_SIZE: Vector2 = Vector2(160.0, 4.0)
const BAR_BACK: Color = Color(1.0, 1.0, 1.0, 0.15)
const BAR_FILL: Color = Color(1.0, 0.953, 0.651, 1.0)

var events: EventsScript = null
var _label: Label = null
var _bar: ProgressBar = null


func _init() -> void:
	name = "Loading"
	color = BACKING
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	_label = Label.new()
	_label.text = "Loading"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_label)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = BAR_SIZE
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = BAR_BACK
	var fill := StyleBoxFlat.new()
	fill.bg_color = BAR_FILL
	_bar.add_theme_stylebox_override("background", back)
	_bar.add_theme_stylebox_override("fill", fill)
	column.add_child(_bar)


func _ready() -> void:
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if events != null:
		events.loading_started.connect(_on_started)
		events.loading_progressed.connect(_on_progressed)
		events.loading_finished.connect(_on_finished)


func _on_started() -> void:
	_bar.value = 0.0
	visible = true


func _on_progressed(done: int, total: int) -> void:
	_bar.max_value = maxi(total, 1)
	_bar.value = done


func _on_finished() -> void:
	visible = false


## How far the bar is (0 to 1), for tests.
func progress() -> float:
	return _bar.value / _bar.max_value
