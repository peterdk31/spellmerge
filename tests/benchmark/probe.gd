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


func _ready() -> void:
	_samples.resize(MAX_SAMPLES)
	_projectiles = get_node_or_null("/root/Projectiles")
	_feel = get_node_or_null("/root/Feel")


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	if _last_usec >= 0:
		var ms: float = float(now - _last_usec) / 1000.0
		if _count < MAX_SAMPLES:
			_samples[_count] = ms
			_count += 1
		_sum_ms += ms
		_max_ms = maxf(_max_ms, ms)
		_frames += 1
	_last_usec = now
	_peak_nodes = maxi(_peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	_peak_memory = maxf(_peak_memory, Performance.get_monitor(Performance.MEMORY_STATIC))
	if _projectiles != null:
		_peak_projectiles = maxi(_peak_projectiles, int(_projectiles.call("get_count")))
	if _feel != null:
		_peak_particles = maxi(_peak_particles, int(_feel.call("live_particles")))


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
	var average: float = _sum_ms / float(_frames)
	print("BENCH: frames %d, frame time avg %.2f ms, p95 %.2f ms, max %.2f ms (60 FPS budget %.1f ms; game logic only if headless)" % [_frames, average, percentile_95(), _max_ms, FRAME_BUDGET_MS])
	var cap: int = 0
	var dropped: int = 0
	if _projectiles != null:
		cap = int(_projectiles.call("get_cap"))
		dropped = int(_projectiles.get("dropped"))
	print("BENCH: peak nodes %d, peak projectiles %d (cap %d, dropped %d), peak static memory %.1f MiB (budgets %d web, %d desktop)" % [_peak_nodes, _peak_projectiles, cap, dropped, _peak_memory / 1048576.0, MEMORY_BUDGET_WEB_MIB, MEMORY_BUDGET_DESKTOP_MIB])
	print("BENCH: peak live hit particles %d (limit %d, Feel.PARTICLE_LIMIT)" % [_peak_particles, FeelScript.PARTICLE_LIMIT])
