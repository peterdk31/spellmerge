extends ColorRect
## The loading screen (owner, 2026-10-29): over everything, in the boot screen's colour, with
## "Loading". It is up for two kinds of wait, told by events alone:
## - core/loading's work (`loading_started` to `loading_finished`: the shaders before the first
##   room), with a bar that fills from `loading_progressed`;
## - the party's departure from the hub's stone (`run_departure_changed`, flow: the run's biome is
##   built in one tick, a second or more), with no bar, since that work has no steps to show.
## Smooth (docs/STYLE.md): it comes down from above over COVER_FRAMES frames and goes back up the
## same way, by whole pixels, and turns round where it is if it is wanted again on the way. It takes
## no input and holds nobody up: the run starts the moment its work is done.

const EventsScript := preload("res://core/events/events.gd")
## The boot screen's colour (`application/boot_splash/bg_color`), so the screen does not flash.
const BACKING: Color = Color(0.105882, 0.0941176, 0.188235, 1.0)
const BAR_SIZE: Vector2 = Vector2(160.0, 4.0)
const BAR_BACK: Color = Color(1.0, 1.0, 1.0, 0.15)
const BAR_FILL: Color = Color(1.0, 0.953, 0.651, 1.0)
## Frames the screen takes to come down (and to go up). Fewer than the frames a load waits before
## its first unit (`Loading.WAIT_FRAMES`) and the ticks a departure waits (`HubRules.DEPART_TICKS`),
## so it is down before the work freezes the game.
const COVER_FRAMES: int = 6

var events: EventsScript = null
var _label: Label = null
var _bar: ProgressBar = null
## Why it is wanted: a load, a departure.
var _loading: bool = false
var _departing: bool = false
## How far down it is, in frames (0: up and hidden, COVER_FRAMES: covering everything).
var _frame: int = 0


func _init() -> void:
	name = "Loading"
	color = BACKING
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# It comes and goes under a paused tree too, as the loads it covers.
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	set_process(false)


func _ready() -> void:
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if events != null:
		events.loading_started.connect(_on_started)
		events.loading_progressed.connect(_on_progressed)
		events.loading_finished.connect(_on_finished)
		events.run_departure_changed.connect(_on_departure_changed)


func _process(_delta: float) -> void:
	advance()


func _on_started() -> void:
	_bar.value = 0.0
	_loading = true
	_want_changed()


func _on_progressed(done: int, total: int) -> void:
	_bar.max_value = maxi(total, 1)
	_bar.value = done


func _on_finished() -> void:
	_loading = false
	_want_changed()


func _on_departure_changed(departing: bool) -> void:
	_departing = departing
	_want_changed()


## True while a load or a departure wants the screen (it may still be on its way down or up).
func is_up() -> bool:
	return _loading or _departing


## One frame of the screen's way down or up (the screen calls it every frame while moving; tests
## call it by hand).
func advance() -> void:
	_frame = clampi(_frame + (1 if is_up() else -1), 0, COVER_FRAMES)
	_place()
	if _frame == 0 and not is_up():
		visible = false
		set_process(false)


## True once it covers everything.
func is_down() -> bool:
	return _frame == COVER_FRAMES


## How far the bar is (0 to 1), for tests.
func progress() -> float:
	return _bar.value / _bar.max_value


func _want_changed() -> void:
	# The bar only for a load: a departure has nothing to count.
	_bar.visible = _loading
	if is_up():
		visible = true
	_place()
	set_process(visible)


## Where it stands for `_frame`: eased, by whole pixels, from just above the screen to over it.
func _place() -> void:
	var height: float = get_viewport_rect().size.y if is_inside_tree() else size.y
	var down: float = smoothstep(0.0, 1.0, float(_frame) / float(COVER_FRAMES))
	position.y = roundf(-height * (1.0 - down))
