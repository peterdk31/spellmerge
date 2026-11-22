extends RefCounted
## Feel's per-frame work on independent pieces, on the engine's worker threads on the desktop (the
## owner's decision of 2026-11-22, "the per-frame effects on worker threads"): a room's mist parted,
## a view's part of the light grid lit. One place knows threads; an
## effect hands it a job, a Callable taking a piece's number, and how many pieces there are.
##
## - **The rules a job keeps:** a piece writes only what is its own (its room's arrays, its view's
##   cells) and reads what no piece writes; it touches no node, no scene tree, no RenderingServer and
##   no resource another piece holds; it allocates nothing. Whatever is handed to the GPU is handed
##   after the join, on the main thread, in the pieces' order. So what is drawn is the same on one
##   thread or many, and does not hang on the threads' timing (`test_feel_jobs.gd` compares the
##   threaded effects' arrays byte for byte; the play frames' `--shots` with and without
##   `--one-thread` compare whole frames pixel for pixel).
## - **How:** `run(job, count)` hands pieces 1 to count - 1 to `WorkerThreadPool` as one group task,
##   runs piece 0 on the calling thread meanwhile, and returns once every piece is done: nothing
##   waits longer than it did on one thread. One group at a time (a job may not run another).
## - **One thread:** with `threaded` off every piece runs in order on the calling thread, as on the
##   web build, which has no threads (`OS.has_feature("threads")` false), and on a machine of fewer
##   than CORES_FOR_THREADS cores; `Feel.set_effect_threads`
##   switches it, and benchmarks and tests run both ways. It is this machine's, never a run's: it
##   changes no result.
##
## View only: nothing here touches the simulation.

## The fewest cores on which Feel's pieces run on the worker threads by default (`threads_by_default`).
const CORES_FOR_THREADS: int = 4

## Whether pieces run on the worker threads (false: all on the calling thread). The default is the
## build's: threads where the engine has them, none on the web.
var threaded: bool = default_threaded()
## Groups run on the threads and pieces run in all since made (for tests and benchmarks).
var groups: int = 0
var pieces: int = 0

## The job of the group running now, and the Callable the pool runs (made once: no allocation a frame).
var _job: Callable = Callable()
var _offset_job: Callable = Callable()


func _init() -> void:
	_offset_job = _run_offset


## Whether this build runs Feel's pieces on threads by default (`threads_by_default` on this machine).
static func default_threaded() -> bool:
	return threads_by_default(OS.has_feature("threads") and not OS.has_feature("web"), OS.get_processor_count())


## Whether a build with threads (`has_threads`: the engine has them and it is not the web) on a machine
## of `cores` cores runs Feel's pieces on them by default: with CORES_FOR_THREADS or more (the owner's
## answer on #917, 2026-11-22: on fewer, the workers take the cores the rest of the frame needs).
static func threads_by_default(has_threads: bool, cores: int) -> bool:
	return has_threads and cores >= CORES_FOR_THREADS


## Run `job` (taking a piece's number, 0 to `count` - 1) on every piece, on the threads while
## `threaded` (piece 0 on the calling thread), and return when all are done.
func run(job: Callable, count: int) -> void:
	if count <= 0:
		return
	if _job.is_valid():
		# Called from a piece (not done today): in turn on its thread, writing nothing here.
		for piece in count:
			job.call(piece)
		return
	pieces += count
	if not threaded or count == 1:
		for piece in count:
			job.call(piece)
		return
	_job = job
	groups += 1
	var group: int = WorkerThreadPool.add_group_task(_offset_job, count - 1, -1, true)
	job.call(0)
	WorkerThreadPool.wait_for_group_task_completion(group)
	_job = Callable()


## The pool's piece `index` is the job's piece `index` + 1 (piece 0 runs on the caller).
func _run_offset(index: int) -> void:
	_job.call(index + 1)
