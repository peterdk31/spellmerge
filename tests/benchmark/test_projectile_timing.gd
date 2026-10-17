extends SceneTree
## Times the projectile manager at its caps (1,000 web, 3,000 desktop) with four
## players, and prints `BENCH:` lines. It gates nothing on time (runners differ);
## it checks only that the work was really done: the cap is full, nothing is lost,
## the batch holds every projectile.
##
## What is timed, per cap:
##  - spawn: one spawn per slot with the cap already full, so every call also drops
##    the oldest projectile of the richest owner (the worst case),
##  - update_draw with a full cap (the per-frame copy into the batch),
##  - step with a full cap and no targets (movement alone),
##  - step with a full cap, 100 enemies and four wizards as targets, friendly fire
##    on so the owner check runs for every shot (movement plus the hit test),
##  - the hit test alone, `_hit_test` for every live slot, on the same scene.
## The hit-test scene is a worst case: the whole cap is inside one 640x360 room and
## the shots pierce, so they stay alive and keep testing the crowd. Targets are
## spread with a fixed pattern; nothing is random.
##
## godot --headless --path . --script res://tests/benchmark/test_projectile_timing.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const DT: float = 1.0 / 60.0
const ROOM: Vector2 = Vector2(640.0, 360.0)
const ENEMIES: int = 100
const PLAYERS: int = 4
## Steps / draws averaged for each timing.
const REPEATS: int = 20
## PLAN budget for one frame at 60 FPS, in milliseconds.
const FRAME_MS: float = 1000.0 / 60.0

var _failures: Array[String] = []
var _bus: Node
var _mgr: Node2D
var _targets: Array[Node2D] = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	for cap in [ManagerScript.DEFAULT_CAP_WEB, ManagerScript.DEFAULT_CAP_DESKTOP]:
		_run_cap(cap)
	_teardown()
	if _failures.is_empty():
		print("test_projectile_timing: OK")
		quit(0)
	else:
		for failure in _failures:
			printerr("test_projectile_timing FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _teardown() -> void:
	for target in _targets:
		if is_instance_valid(target):
			target.free()
	_targets.clear()
	for node: Node in [_mgr, _bus]:
		if node != null and is_instance_valid(node):
			node.free()
	_mgr = null
	_bus = null


func _run_cap(cap: int) -> void:
	_teardown()
	_bus = EventsScript.new()
	_mgr = ManagerScript.new()
	_mgr.events = _bus
	root.add_child(_mgr)
	_mgr.set_cap(cap)
	_mgr.set_bounds(Rect2(Vector2.ZERO, ROOM))

	# Spawn at the cap: fill it, then one more spawn per slot.
	_fill(cap, 1.0e6, false)
	_check(_mgr.get_count() == cap, "cap %d: full after filling" % cap)
	var dropped_before: int = _mgr.dropped
	var start: int = Time.get_ticks_usec()
	for i in cap:
		_spawn(i, 1.0e6, false)
	var spawn_us: float = float(Time.get_ticks_usec() - start)
	_check(_mgr.get_count() == cap, "cap %d: still full after spawning at the cap" % cap)
	_check(_mgr.dropped - dropped_before == cap, "cap %d: each spawn at the cap dropped one" % cap)
	_log("spawn at the cap (%d calls)" % cap, spawn_us, cap, "per call")

	# update_draw with a full cap.
	var draw_us: float = 0.0
	for i in REPEATS:
		start = Time.get_ticks_usec()
		_mgr.update_draw()
		draw_us += float(Time.get_ticks_usec() - start)
	_check(_mgr.drawn == cap, "cap %d: the batch holds every projectile (%d)" % [cap, _mgr.drawn])
	_log("update_draw, full cap", draw_us / float(REPEATS), 1, "per frame")

	# Movement alone.
	var step_us: float = _time_steps()
	_log("step, full cap, no targets", step_us, 1, "per step")

	# The crowd: 100 enemies and four wizards, shots that pierce.
	_mgr.clear()
	_add_crowd()
	_fill(cap, 1.0e6, true)
	_check(_mgr.get_count() == cap, "cap %d: full for the hit test" % cap)
	var hit_step_us: float = _time_steps()
	_check(_mgr.get_count() == cap, "cap %d: piercing shots survive the steps" % cap)
	_log("step, full cap, %d enemies + %d wizards, friendly fire" % [ENEMIES, PLAYERS], hit_step_us, 1, "per step")
	_log("  of which the hit test, if movement is %.0f us" % step_us, maxf(hit_step_us - step_us, 0.0), 1, "per step")

	# The hit test alone for every live slot.
	_mgr.step(DT)
	var hit_us: float = 0.0
	for i in REPEATS:
		start = Time.get_ticks_usec()
		for slot in cap:
			_mgr._hit_test(slot)
		hit_us += float(Time.get_ticks_usec() - start)
	_log("_hit_test for every slot (%d calls)" % cap, hit_us / float(REPEATS), cap, "per call")
	root.remove_child(_mgr)


## Mean microseconds of one `step` over REPEATS steps.
func _time_steps() -> float:
	var total: float = 0.0
	for i in REPEATS:
		var start: int = Time.get_ticks_usec()
		_mgr.step(DT)
		total += float(Time.get_ticks_usec() - start)
	return total / float(REPEATS)


## Fill the manager to `count` shots, owners rotating over the four players.
func _fill(count: int, lifetime: float, pierce: bool) -> void:
	_mgr.clear()
	for i in count:
		_spawn(i, lifetime, pierce)


func _spawn(i: int, lifetime: float, pierce: bool) -> void:
	var at := Vector2(float(i * 37 % int(ROOM.x)), float(i * 53 % int(ROOM.y)))
	var velocity := Vector2(float(i % 7) - 3.0, float(i % 5) - 2.0) * 2.0
	var hit_layers: int = ManagerScript.LAYER_ENEMY
	_mgr.friendly_fire = pierce
	_mgr.spawn(i % PLAYERS, at, velocity, lifetime, 4.0, hit_layers, 1000000 if pierce else 0)


## 100 enemies on a grid over the room and four wizards (owners 0-3).
func _add_crowd() -> void:
	for i in ENEMIES:
		var enemy := Node2D.new()
		root.add_child(enemy)
		enemy.global_position = Vector2(32.0 + float(i % 20) * 30.0, 40.0 + floorf(float(i) / 20.0) * 60.0)
		_targets.append(enemy)
		_mgr.add_target(enemy, 10.0, ManagerScript.LAYER_ENEMY)
	for player in PLAYERS:
		var wizard := Node2D.new()
		root.add_child(wizard)
		wizard.global_position = Vector2(120.0 + float(player) * 130.0, 300.0)
		_targets.append(wizard)
		_mgr.add_target(wizard, 8.0, ManagerScript.LAYER_PLAYER, player)


## `total_us` is for `calls` calls.
func _log(what: String, total_us: float, calls: int, unit: String) -> void:
	var each_us: float = total_us / float(calls)
	var share: String = ""
	if calls == 1:
		share = ", %.1f%% of a 60 FPS frame" % (total_us / 1000.0 / FRAME_MS * 100.0)
	print("BENCH: cap %d: %s: %.0f us total, %.3f us %s%s" % [_mgr.get_cap(), what, total_us, each_us, unit, share])
