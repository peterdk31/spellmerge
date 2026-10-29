extends "res://tests/support/suite.gd"
## The loading service (core/loading): `run` does its tasks one unit a frame after the screen is
## up, says how far it is, then calls `done`; one load at a time; `cancel` ends it without `done`.
## A fresh service with fake tasks, stepped by hand.
##
## godot --headless --path . --script res://tests/core/test_loading.gd

const LoadingScript := preload("res://core/loading/loading.gd")
const EventsScript := preload("res://core/events/events.gd")
const LoadTask := preload("res://core/loading/load_task.gd")


## A task of `count` units that records what was asked of it.
class FakeTask extends LoadTask:
	var count: int = 1
	var steps: int = 0
	var begun: int = 0
	var ended: int = 0
	var log: Array[String] = []

	func _init(units_in_all: int, shared_log: Array[String]) -> void:
		count = units_in_all
		log = shared_log

	func units() -> int:
		return count

	func units_done() -> int:
		return steps

	func begin(_host: Node) -> void:
		begun += 1
		log.append("begin %d" % count)

	func step() -> void:
		steps += 1

	func is_done() -> bool:
		return steps >= count

	func end() -> void:
		ended += 1
		log.append("end %d" % count)


var loading: LoadingScript
var bus: EventsScript
var log: Array[String] = []
var progress: Array[Vector2i] = []
var started: int = 0
var finished: int = 0
var done_calls: int = 0


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	loading = own(LoadingScript.new()) as LoadingScript
	loading.events = bus
	root.add_child(loading)
	loading.set_process(false)
	log = []
	progress = []
	started = 0
	finished = 0
	done_calls = 0
	bus.loading_started.connect(func() -> void: started += 1)
	bus.loading_finished.connect(func() -> void: finished += 1)
	bus.loading_progressed.connect(func(d: int, t: int) -> void: progress.append(Vector2i(d, t)))


func _done() -> void:
	done_calls += 1


func _steps(n: int) -> void:
	for i in n:
		loading.step()


func test_tasks_run_in_order_one_unit_a_frame_then_done_is_called() -> void:
	var first := FakeTask.new(2, log)
	var second := FakeTask.new(3, log)
	var tasks: Array[LoadTask] = [first, second]
	check(loading.run(tasks, _done), "a load starts")
	check_equal(started, 1, "the screen is asked for at once")
	check(loading.is_loading(), "and it is loading")
	_steps(LoadingScript.WAIT_FRAMES)
	check_equal(first.steps, 0, "nothing is done while the screen comes up")
	_steps(1)
	check_equal(first.steps, 1, "then one unit a frame")
	_steps(10)
	check_equal(first.steps, 2, "every unit of the first task")
	check_equal(second.steps, 3, "then of the second")
	check_equal(log, ["begin 2", "end 2", "begin 3", "end 3"] as Array[String], "each begun and ended once, in order")
	check_equal(progress[progress.size() - 1], Vector2i(5, 5), "the bar reaches the end")
	check(progress[0].x <= progress[1].x, "and only moves on")
	check_equal(done_calls, 1, "done is called once")
	check_equal(finished, 1, "and the screen goes")
	check(not loading.is_loading(), "nothing loading")


func test_one_load_at_a_time_and_nothing_to_do_is_no_load() -> void:
	var tasks: Array[LoadTask] = [FakeTask.new(1, log)]
	check(loading.run(tasks, _done), "a load starts")
	var more: Array[LoadTask] = [FakeTask.new(1, log)]
	check(not loading.run(more, _done), "a second waits for no one: it is refused")
	_steps(10)
	var none: Array[LoadTask] = []
	check(not loading.run(none, _done), "nothing to load: no load, no screen")
	check_equal(started, 1, "one screen in all")


func test_cancel_ends_the_task_and_never_calls_done() -> void:
	var task := FakeTask.new(5, log)
	var tasks: Array[LoadTask] = [task]
	loading.run(tasks, _done)
	_steps(LoadingScript.WAIT_FRAMES + 2)
	loading.cancel()
	check_equal(task.ended, 1, "the task is ended")
	check_equal(finished, 1, "the screen goes")
	check_equal(done_calls, 0, "and what was waiting does not start")
	_steps(5)
	check_equal(task.steps, 2, "nothing more is done")
