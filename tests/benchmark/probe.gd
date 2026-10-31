extends Node
## The performance probe. It rides along in the 4-bot test (four_bot_runner.gd adds it
## and calls `report()` when the run ends) and logs, as `BENCH:` lines, the real frame
## time (average, 95th percentile, max) and the peaks of node count, live projectiles,
## live hit particles and memory, next to the budgets of docs/PLAN.md. It gates
## nothing yet: `report()` only prints.
##
## Frame time is measured between frames with `Time.get_ticks_usec()`, so it is real
## time, not game time (the run uses Engine.time_scale). Headless runs do no
## rendering, so this is game-logic time, as the PLAN says.
##
## Nothing is allocated per frame: the samples go into an array sized once.
##
## The physics step's real cost: the engine's TIME_PHYSICS_PROCESS and TIME_PROCESS monitors are
## each the LONGEST step (and process pass) of the last second, refreshed once a second, so their
## average is an average of maxima, far above a typical step (horde swarm S4: 30 ms "a step" when
## the steps took about 12). So the probe also times every physics step's scripts itself: a marker
## child runs first in each physics step (lowest priority) and the probe last (highest), and the
## clock between them is the step's scripts (`physics_scripts_average_ms`). Process the same way
## (`process_scripts_average_ms`). What a frame spends besides (the physics server, the message
## queue with its deferred calls and frees, the renderer) is the frame less the two.

const FeelScript := preload("res://gameplay/feel/feel.gd")

## Frames kept. Further frames still count towards the average and the peaks, but not
## the percentile.
const MAX_SAMPLES: int = 20000
## The 60 FPS frame, in milliseconds (PLAN budgets: frame rate).
const FRAME_BUDGET_MS: float = 1000.0 / 60.0
## Processing priorities of the first marker and of the probe: everything else runs between.
const PRIORITY_FIRST: int = -1000000000
const PRIORITY_LAST: int = 1000000000
## PLAN budgets: memory, in MiB, for the web demo and the full desktop build.
const MEMORY_BUDGET_WEB_MIB: int = 512
const MEMORY_BUDGET_DESKTOP_MIB: int = 1536

## Frames kept; a test sets it (before the probe enters the tree) to reach the overflow.
var max_samples: int = MAX_SAMPLES

var _samples: PackedFloat32Array = PackedFloat32Array()
var _count: int = 0
var _frames: int = 0
var _last_usec: int = -1
var _sum_ms: float = 0.0
var _max_ms: float = 0.0
var _peak_nodes: int = 0
var _peak_projectiles: int = 0
var _peak_memory: float = 0.0
var _peak_particles: int = 0
var _projectiles: Node = null
var _feel: Node = null
## The frame's parts, from the engine's own monitors (the web stress frame, docs/DECISIONS.md
## 2026-10-23): physics steps run per drawn frame, milliseconds in physics and in process,
## the renderer's CPU time and draw calls. Sums run over the frames after the first.
var _last_physics_frame: int = -1
var _steps_sum: int = 0
var _steps_max: int = 0
var _physics_sum_ms: float = 0.0
var _physics_max_ms: float = 0.0
var _process_sum_ms: float = 0.0
var _process_max_ms: float = 0.0
var _render_sum_ms: float = 0.0
var _render_max_ms: float = 0.0
var _peak_draw_calls: int = 0
var _parts_frames: int = 0
## The scripts' own clock (see the class doc): physics steps timed, their sum and longest, and the
## process passes' sum.
var _step_begin: int = -1
var _steps_timed: int = 0
var _step_sum_usec: int = 0
var _step_max_usec: int = 0
var _process_begin: int = -1
var _process_passes: int = 0
var _process_sum_usec: int = 0
## The marker that runs first in each physics step and process pass.
var _first: Node = null


## Runs first in each physics step and each process pass and tells the probe the time.
class FirstMarker:
	extends Node
	var probe: Node

	func _physics_process(_delta: float) -> void:
		probe.call(&"_physics_started")

	func _process(_delta: float) -> void:
		probe.call(&"_process_started")


func _ready() -> void:
	_samples.resize(max_samples)
	process_priority = PRIORITY_LAST
	process_physics_priority = PRIORITY_LAST
	var first := FirstMarker.new()
	first.probe = self
	first.process_priority = PRIORITY_FIRST
	first.process_physics_priority = PRIORITY_FIRST
	_first = first
	add_child(first)
	_projectiles = get_node_or_null("/root/Projectiles")
	_feel = get_node_or_null("/root/Feel")
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _exit_tree() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), false)


func _physics_started() -> void:
	_step_begin = Time.get_ticks_usec()


func _process_started() -> void:
	_process_begin = Time.get_ticks_usec()


func _physics_process(_delta: float) -> void:
	if _step_begin < 0:
		return
	var spent: int = Time.get_ticks_usec() - _step_begin
	_step_begin = -1
	_steps_timed += 1
	_step_sum_usec += spent
	_step_max_usec = maxi(_step_max_usec, spent)


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	if _process_begin >= 0:
		_process_passes += 1
		_process_sum_usec += now - _process_begin
		_process_begin = -1
	if _last_usec >= 0:
		record(float(now - _last_usec) / 1000.0)
	_last_usec = now
	_sample_parts()
	_peak_nodes = maxi(_peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	_peak_memory = maxf(_peak_memory, Performance.get_monitor(Performance.MEMORY_STATIC))
	if _projectiles != null:
		_peak_projectiles = maxi(_peak_projectiles, int(_projectiles.call("get_count")))
	if _feel != null:
		_peak_particles = maxi(_peak_particles, int(_feel.call("live_effects")))


## Read the engine's monitors for the frame that just ended (nothing before the second frame).
func _sample_parts() -> void:
	var physics_frame: int = Engine.get_physics_frames()
	if _last_physics_frame >= 0:
		var steps: int = physics_frame - _last_physics_frame
		_steps_sum += steps
		_steps_max = maxi(_steps_max, steps)
		var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var process_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var render_ms: float = RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())
		_physics_sum_ms += physics_ms
		_physics_max_ms = maxf(_physics_max_ms, physics_ms)
		_process_sum_ms += process_ms
		_process_max_ms = maxf(_process_max_ms, process_ms)
		_render_sum_ms += render_ms
		_render_max_ms = maxf(_render_max_ms, render_ms)
		_parts_frames += 1
	_last_physics_frame = physics_frame
	_peak_draw_calls = maxi(_peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))


## Physics steps run per drawn frame, on average (0 with no frames). The engine runs several
## in one frame when it is late, so a slow step makes the next frame slower still.
func steps_per_frame_average() -> float:
	return float(_steps_sum) / float(_parts_frames) if _parts_frames > 0 else 0.0


## The physics steps' scripts (every node's `_physics_process`, the signals they send), average
## and longest, in milliseconds, by the probe's own clock (0 before a step was timed).
func physics_scripts_average_ms() -> float:
	return float(_step_sum_usec) / float(_steps_timed) / 1000.0 if _steps_timed > 0 else 0.0


func physics_scripts_max_ms() -> float:
	return float(_step_max_usec) / 1000.0


## The process passes' scripts (every node's `_process`), average in milliseconds.
func process_scripts_average_ms() -> float:
	return float(_process_sum_usec) / float(_process_passes) / 1000.0 if _process_passes > 0 else 0.0


## The most physics steps run in one drawn frame.
func steps_per_frame_max() -> int:
	return _steps_max


## Count one frame of `ms` milliseconds. Past `max_samples` frames it still counts
## towards the average and the maximum, but not the percentile.
func record(ms: float) -> void:
	if _count < max_samples:
		_samples[_count] = ms
		_count += 1
	_sum_ms += ms
	_max_ms = maxf(_max_ms, ms)
	_frames += 1


## Average frame time so far, in milliseconds (0 with no frames).
func average_ms() -> float:
	return _sum_ms / float(_frames) if _frames > 0 else 0.0


## Longest frame so far, in milliseconds.
func max_ms() -> float:
	return _max_ms


## The 95th percentile of the kept samples, in milliseconds (0 with no samples).
func percentile_95() -> float:
	if _count == 0:
		return 0.0
	var kept: PackedFloat32Array = _samples.slice(0, _count)
	kept.sort()
	return kept[mini(int(float(_count) * 0.95), _count - 1)]


## Frames measured so far.
func frame_count() -> int:
	return _frames


## Print the numbers. Nothing here can fail a run.
func report() -> void:
	if _frames == 0:
		print("BENCH: no frames measured")
		return
	var average: float = average_ms()
	print("BENCH: frames %d, frame time avg %.2f ms, p95 %.2f ms, max %.2f ms (60 FPS budget %.1f ms; game logic only if headless)" % [_frames, average, percentile_95(), _max_ms, FRAME_BUDGET_MS])
	var cap: int = 0
	var dropped: int = 0
	if _projectiles != null:
		cap = int(_projectiles.call("get_cap"))
		dropped = int(_projectiles.get("dropped"))
	print("BENCH: peak nodes %d, peak projectiles %d (cap %d, dropped %d), peak static memory %.1f MiB (budgets %d web, %d desktop)" % [_peak_nodes, _peak_projectiles, cap, dropped, _peak_memory / 1048576.0, MEMORY_BUDGET_WEB_MIB, MEMORY_BUDGET_DESKTOP_MIB])
	if _parts_frames > 0:
		var n: float = float(_parts_frames)
		var steps: float = steps_per_frame_average()
		var physics: float = physics_scripts_average_ms()
		var process: float = process_scripts_average_ms()
		print("BENCH: frame parts: physics steps per frame avg %.2f max %d; a physics step's scripts avg %.2f ms max %.2f ms; process scripts avg %.2f ms a frame; the rest of the frame (physics server, message queue and frees, renderer) avg %.2f ms; renderer CPU avg %.2f ms max %.2f ms; peak draw calls %d" % [steps, _steps_max, physics, physics_scripts_max_ms(), process, maxf(average_ms() - steps * physics - process, 0.0), _render_sum_ms / n, _render_max_ms, _peak_draw_calls])
		print("BENCH: engine monitors (each the longest of its second, not an average step): physics step avg of maxima %.2f ms max %.2f ms; process avg of maxima %.2f ms max %.2f ms" % [_physics_sum_ms / n, _physics_max_ms, _process_sum_ms / n, _process_max_ms])
	print("BENCH: peak live effects %d (slots %d, Feel.effect_slots)" % [_peak_particles, EffectSlots.DEFAULT if _feel == null else int(_feel.get("effect_slots"))])
