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
##  - step with a full cap, 100 enemies packed into a few cells and four wizards as
##    targets, friendly fire on, with fast shots (200-400 px/s) fired through them:
##    the shots are refilled before each timed step, so every step does fresh hits
##    and sends `projectile_hit` (the first-hit path),
##  - the hit test alone (`_hit_test` for every live slot) on the same fresh state,
##  - the steady state: the same shots stepped again, most targets remembered.
## The hit-test scene is hostile on purpose: the whole cap starts inside the crowd,
## the shots pierce, and every hit sends the signal (a counter listens). Positions
## and angles follow a fixed pattern; nothing is random.
##
## godot --headless --path . --script res://tests/benchmark/test_projectile_timing.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const DT: float = 1.0 / 60.0
const ROOM: Vector2 = Vector2(640.0, 360.0)
const ENEMIES: int = 100
## Where the crowd stands, and where the hostile shots start.
const CROWD_CENTER: Vector2 = Vector2(320.0, 150.0)
const PLAYERS: int = 4
## Steps / draws averaged for each timing.
const REPEATS: int = 20
## PLAN budget for one frame at 60 FPS, in milliseconds.
const FRAME_MS: float = 1000.0 / 60.0

var _failures: Array[String] = []
var _bus: Node
var _mgr: Node2D
var _targets: Array[Node2D] = []
var _hits: int = 0


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

	# The same with the arena's walls (border and six pillars) set: shots refilled
	# before each step cross the wall grid and some end on a wall.
	_mgr.set_walls(_arena_walls())
	var wall_us: float = 0.0
	for i in REPEATS:
		_fill(cap, 1.0e6, false)
		var wall_start: int = Time.get_ticks_usec()
		_mgr.step(DT)
		wall_us += float(Time.get_ticks_usec() - wall_start)
	_check(_mgr.get_count() < cap, "cap %d: some shots ended on a wall" % cap)
	_check(_mgr.wall_hits > 0, "cap %d: wall_hits counts them" % cap)
	_log("step, full cap, no targets, arena walls set", wall_us / float(REPEATS), 1, "per step")
	_mgr.clear_walls()

	# The crowd: 100 enemies packed into a few cells, four wizards beside them, and
	# fast piercing shots fired through them. Every timing starts from a fresh fill,
	# so every call does real hits and sends `projectile_hit`.
	_mgr.clear()
	_add_crowd()
	_bus.projectile_hit.connect(_on_hit)
	var first_us: float = 0.0
	var first_hits: int = 0
	for i in REPEATS:
		_fill_hostile(cap)
		_hits = 0
		start = Time.get_ticks_usec()
		_mgr.step(DT)
		first_us += float(Time.get_ticks_usec() - start)
		first_hits += _hits
	_check(_mgr.get_count() == cap, "cap %d: piercing shots survive the steps" % cap)
	_check(first_hits > 0, "cap %d: the first step really hits (%d hits)" % [cap, first_hits])
	_log("step with fresh hits, full cap, %d packed enemies + %d wizards (%d hits a step)" % [ENEMIES, PLAYERS, first_hits / REPEATS], first_us / float(REPEATS), 1, "per step")

	# The hit test alone, fresh each time: shots moved one step, nothing remembered.
	var hit_us: float = 0.0
	for i in REPEATS:
		_fill_hostile(cap)
		_advance_paths(cap)
		start = Time.get_ticks_usec()
		for slot in cap:
			_mgr._hit_test(slot)
		hit_us += float(Time.get_ticks_usec() - start)
	_log("_hit_test with fresh hits (%d calls, with the signal)" % cap, hit_us / float(REPEATS), cap, "per call")

	# The steady state: the same shots stepped again, most targets remembered.
	_fill_hostile(cap)
	_mgr.step(DT)
	var steady_us: float = _time_steps()
	_log("step, steady state (targets remembered)", steady_us, 1, "per step")
	_bus.projectile_hit.disconnect(_on_hit)
	root.remove_child(_mgr)


## The solid parts of the arena: a 32 px border and six 32 px pillars.
func _arena_walls() -> Array[Rect2]:
	var rects: Array[Rect2] = [
		Rect2(0, 0, 640, 32), Rect2(0, 328, 640, 32), Rect2(0, 0, 32, 360), Rect2(608, 0, 32, 360),
	]
	for corner: Vector2 in [Vector2(160, 128), Vector2(448, 128), Vector2(160, 224), Vector2(448, 224), Vector2(288, 160), Vector2(320, 192)]:
		rects.append(Rect2(corner, Vector2(32, 32)))
	return rects


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
	_mgr.friendly_fire = pierce
	_mgr.spawn(i % PLAYERS, at, velocity, lifetime, 4.0, ManagerScript.LAYER_ENEMY, 1000000 if pierce else 0)


## Fill the manager to `count` fast piercing shots (200-400 px/s) that start inside
## the crowd and fly in all directions, friendly fire on.
func _fill_hostile(count: int) -> void:
	_mgr.clear()
	_mgr.friendly_fire = true
	for i in count:
		var at := CROWD_CENTER + Vector2(float(i * 37 % 80) - 40.0, float(i * 53 % 80) - 40.0)
		var speed: float = 200.0 + float(i % 5) * 50.0
		_mgr.spawn(i % PLAYERS, at, Vector2.from_angle(float(i) * 0.7) * speed, 1.0e6, 4.0, ManagerScript.LAYER_ENEMY, 1000000)


## Move every shot one step without testing it, so `_hit_test` can be timed alone.
func _advance_paths(count: int) -> void:
	for slot in count:
		_mgr._prev[slot] = _mgr._pos[slot]
		_mgr._pos[slot] += _mgr._vel[slot] * DT


func _on_hit(_player: int, _node: Node, _at: Vector2, _tag: int) -> void:
	_hits += 1


## 100 enemies packed 9 px apart (radius 10, so they overlap) in about four 64 px
## cells, and four wizards (owners 0-3) at their lower edge.
func _add_crowd() -> void:
	for i in ENEMIES:
		var enemy := Node2D.new()
		root.add_child(enemy)
		enemy.global_position = CROWD_CENTER + Vector2(float(i % 10) - 4.5, floorf(float(i) / 10.0) - 4.5) * 9.0
		_targets.append(enemy)
		_mgr.add_target(enemy, 10.0, ManagerScript.LAYER_ENEMY)
	for player in PLAYERS:
		var wizard := Node2D.new()
		root.add_child(wizard)
		wizard.global_position = CROWD_CENTER + Vector2(float(player) * 16.0 - 24.0, 52.0)
		_targets.append(wizard)
		_mgr.add_target(wizard, 8.0, ManagerScript.LAYER_PLAYER, player)


## `total_us` is for `calls` calls.
func _log(what: String, total_us: float, calls: int, unit: String) -> void:
	var each_us: float = total_us / float(calls)
	var share: String = ""
	if calls == 1:
		share = ", %.1f%% of a 60 FPS frame" % (total_us / 1000.0 / FRAME_MS * 100.0)
	print("BENCH: cap %d: %s: %.0f us total, %.3f us %s%s" % [_mgr.get_cap(), what, total_us, each_us, unit, share])
