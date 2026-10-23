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

const FeelScript := preload("res://gameplay/feel/feel.gd")

## Frames kept. Further frames still count towards the average and the peaks, but not
## the percentile.
const MAX_SAMPLES: int = 20000
## The 60 FPS frame, in milliseconds (PLAN budgets: frame rate).
const FRAME_BUDGET_MS: float = 1000.0 / 60.0
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


func _ready() -> void:
	_samples.resize(max_samples)
	_projectiles = get_node_or_null("/root/Projectiles")
	_feel = get_node_or_null("/root/Feel")
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _exit_tree() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), false)


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	if _last_usec >= 0:
		record(float(now - _last_usec) / 1000.0)
	_last_usec = now
	_sample_parts()
	_peak_nodes = maxi(_peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	_peak_memory = maxf(_peak_memory, Performance.get_monitor(Performance.MEMORY_STATIC))
	if _projectiles != null:
		_peak_projectiles = maxi(_peak_projectiles, int(_projectiles.call("get_count")))
	if _feel != null:
		_peak_particles = maxi(_peak_particles, int(_feel.call("live_particles")))


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
		print("BENCH: frame parts: physics steps per frame avg %.1f max %d; physics process avg %.2f ms max %.2f ms; process avg %.2f ms max %.2f ms; renderer CPU avg %.2f ms max %.2f ms; peak draw calls %d" % [steps_per_frame_average(), _steps_max, _physics_sum_ms / n, _physics_max_ms, _process_sum_ms / n, _process_max_ms, _render_sum_ms / n, _render_max_ms, _peak_draw_calls])
	print("BENCH: peak live hit particles %d (limit %d, Feel.PARTICLE_LIMIT)" % [_peak_particles, FeelScript.PARTICLE_LIMIT])
