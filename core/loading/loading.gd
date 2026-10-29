extends Node
## The loading screen's service, one autoload, `Loading` (core/README.md, "loading/"; owner,
## 2026-10-29: the work before playing happens behind a loading screen, not on the menu or in the
## room). `run(tasks, done)` does a list of `LoadTask`s (`load_task.gd`) one unit a frame, after
## WAIT_FRAMES so the screen is drawn first, and sends `loading_started`, `loading_progressed(done,
## total)` after each unit and `loading_finished`; then it calls `done`. The HUD shows the screen
## from those events alone (`hud/panels/loading/`). `cancel()` drops a load in progress (its tasks
## end, `loading_finished` is sent, `done` is not called). One load at a time.
##
## Starting to play: Flow lists what must be ready before a room (`Flow.play_tasks`) and runs it
## here. To load something more before playing, write a LoadTask and add it to that list.

const EventsScript := preload("res://core/events/events.gd")
const LoadTask := preload("res://core/loading/load_task.gd")
## Frames to wait before the first unit, so the screen is up first.
const WAIT_FRAMES: int = 2

var events: EventsScript = null
var _tasks: Array[LoadTask] = []
var _current: int = 0
var _wait: int = 0
var _total: int = 0
var _before: int = 0
var _done: Callable = Callable()
var _loading: bool = false


func _ready() -> void:
	# Loads go on under a paused tree too.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript


func _process(_delta: float) -> void:
	step()


## Do `tasks` behind the loading screen, then call `done`. False (and nothing done) while
## another load is running or there is nothing to do.
func run(tasks: Array[LoadTask], done: Callable) -> bool:
	if _loading or tasks.is_empty():
		return false
	_tasks = tasks.duplicate()
	_current = 0
	_before = 0
	_total = 0
	_wait = WAIT_FRAMES
	_done = done
	_loading = true
	for task in _tasks:
		_total += maxi(task.units(), 1)
	if events != null:
		events.loading_started.emit()
	_tasks[0].begin(self)
	return true


func is_loading() -> bool:
	return _loading


## Units done and in all of the load running (0 and 0 when none).
func progress() -> Vector2i:
	if not _loading:
		return Vector2i.ZERO
	return Vector2i(_before + _tasks[_current].units_done(), _total)


## Drop the load in progress: its tasks end, the screen goes, `done` is not called.
func cancel() -> void:
	if not _loading:
		return
	_tasks[_current].end()
	_finish()


## One frame of the load (the autoload calls it every frame; tests call it by hand).
func step() -> void:
	if not _loading:
		return
	if _wait > 0:
		_wait -= 1
		return
	var task: LoadTask = _tasks[_current]
	if not task.is_done():
		task.step()
	if events != null:
		var now: Vector2i = progress()
		events.loading_progressed.emit(now.x, now.y)
	if not task.is_done():
		return
	task.end()
	_before += maxi(task.units(), 1)
	_current += 1
	if _current < _tasks.size():
		_tasks[_current].begin(self)
		return
	var done: Callable = _done
	_finish()
	if done.is_valid():
		done.call()


func _finish() -> void:
	_loading = false
	_tasks.clear()
	_done = Callable()
	if events != null:
		events.loading_finished.emit()
