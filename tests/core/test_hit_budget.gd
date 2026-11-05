extends "res://tests/support/suite.gd"
## The hit-work budget loses no damage (shot scale H2, docs/milestones/shot-scale.md): a shot the
## budget passes over keeps the start of its untested path and its next test sweeps all of it, so a
## fast shot skips no target; a deferred shot that ends (its life out, out of the bounds) is tested
## first whatever the budget; over a flight a budget of one hits the very bodies no budget does; and
## in a full crowd at the desktop cap no shot waits more than one step. Each runs on the GDScript
## and on the native kernel (when built), which must agree.
##
## godot --headless --path . --script res://tests/core/test_hit_budget.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const DT: float = 1.0 / 60.0
const UNBUDGETED: int = 1 << 40
## The full crowd: the shot scale benchmark's (tests/benchmark/shot_scale.gd), at the desktop cap.
const ARENA: Rect2 = Rect2(0.0, 0.0, 1280.0, 720.0)
const CROWD: int = 500
const CROWD_RADIUS: float = 7.0
const SHOT_SPEED: float = 300.0
const SHOT_LIFE: float = 2.0


class Scene:
	extends RefCounted
	var bus: EventsScript
	var table: Node
	var mgr: ManagerScript
	var bodies: Array[Node2D] = []
	## The bodies each shot hit, in order, by its slot.
	var hit_by_shot: Dictionary = {}
	var hits: int = 0


## A fast piercing shot through a row of bodies, one body a step, tested only every other step
## (a blocker in the slot before it spends the budget of one in turn with it): before H2 it skipped
## the bodies it passed in its untested steps.
func test_a_deferred_fast_shot_hits_every_body_in_a_row() -> void:
	var results: Array = []
	for native: bool in _modes():
		var scene := _scene(native, Rect2(-400.0, -400.0, 800.0, 800.0))
		scene.mgr.work_per_step = 1
		_blocker(scene)
		for i in 6:
			_body(scene, Vector2(40.0 + 40.0 * float(i), 0.0), 4.0)
		var shot: int = scene.mgr.spawn(_caster(scene), Vector2.ZERO, Vector2(2400.0, 0.0), 0.2, 2.0, ManagerScript.LAYER_ENEMY, 100, 0)
		var deferred: int = 0
		for i in 10:
			scene.mgr.step(DT)
			if scene.mgr.is_alive(shot) and (scene.mgr._flags[shot] & ManagerScript.F_DEFERRED) != 0:
				deferred += 1
		var label: String = _label(scene)
		check(deferred >= 2, "%s: the budget passed over the shot in some steps (%d)" % [label, deferred])
		check_equal(scene.hit_by_shot.get(shot, []), [1, 2, 3, 4, 5, 6], "%s: it hit every body in the row, in order" % label)
		results.append(scene.hit_by_shot)
		_free(scene)
	if results.size() == 2:
		check_equal(results[1], results[0], "native and GDScript hit alike")


## A deferred shot whose life runs out is tested on the path it was not tested on before it ends.
func test_a_deferred_shot_that_expires_is_tested_first() -> void:
	for native: bool in _modes():
		var scene := _scene(native, Rect2(-400.0, -400.0, 800.0, 800.0))
		scene.mgr.work_per_step = 1
		_blocker(scene)
		_body(scene, Vector2(20.0, 0.0), 4.0)
		# One step and a half of life: it passes the body untested, then expires.
		var shot: int = scene.mgr.spawn(_caster(scene), Vector2.ZERO, Vector2(2400.0, 0.0), DT * 1.5, 2.0, ManagerScript.LAYER_ENEMY, 0, 0)
		scene.mgr.step(DT)
		var label: String = _label(scene)
		check(scene.mgr.is_alive(shot) and (scene.mgr._flags[shot] & ManagerScript.F_DEFERRED) != 0, "%s: the first step passed over the shot" % label)
		check(not scene.hit_by_shot.has(shot), "%s: and it hit nothing yet" % label)
		scene.mgr.step(DT)
		check(not scene.mgr.is_alive(shot), "%s: its life ran out" % label)
		check_equal(scene.hit_by_shot.get(shot, []), [1], "%s: it hit the body it passed untested before it ended" % label)
		_free(scene)


## A deferred shot that leaves the bounds is tested on its untested path before it is removed.
func test_a_deferred_shot_that_leaves_the_bounds_is_tested_first() -> void:
	for native: bool in _modes():
		var scene := _scene(native, Rect2(-100.0, -100.0, 200.0, 200.0))
		scene.mgr.work_per_step = 1
		_blocker(scene, Vector2(-60.0, 60.0))
		_body(scene, Vector2(60.0, 0.0), 4.0)
		# 100 px a step from x = 0: past the body in the first step, past the bounds' margin
		# (BOUNDS_MARGIN) in the third.
		var shot: int = scene.mgr.spawn(_caster(scene), Vector2.ZERO, Vector2(6000.0, 0.0), 1.0, 2.0, ManagerScript.LAYER_ENEMY, 0, 0)
		scene.mgr.step(DT)
		var label: String = _label(scene)
		check((scene.mgr._flags[shot] & ManagerScript.F_DEFERRED) != 0, "%s: the first step passed over the shot" % label)
		for i in 4:
			scene.mgr.step(DT)
		check(not scene.mgr.is_alive(shot), "%s: it left the bounds" % label)
		check_equal(scene.hit_by_shot.get(shot, []), [1], "%s: it hit the body it passed untested" % label)
		_free(scene)


## Over their whole flight, shots under a budget of one hit the very bodies they hit with none:
## the budget only delays hits, it loses none.
func test_a_budget_delays_hits_and_loses_none() -> void:
	var results: Array = []
	for native: bool in _modes():
		var by_budget: Array[Dictionary] = []
		for work: int in [UNBUDGETED, 1]:
			var scene := _scene(native, Rect2(-400.0, -400.0, 800.0, 800.0))
			scene.mgr.work_per_step = work
			for i in 12:
				_body(scene, Vector2(20.0 + 12.0 * float(i), float(i % 3) * 6.0 - 6.0), 8.0)
			var velocities := PackedVector2Array()
			for i in 400:
				velocities.append(Vector2(300.0, float(i % 21) - 10.0))
			var slots := PackedInt32Array()
			slots.resize(velocities.size())
			scene.mgr.spawn_batch(_caster(scene), Vector2(-20.0, 0.0), velocities, 2.0, 3.0, ManagerScript.LAYER_ENEMY, 1, 0, slots)
			# Until every shot has left the bounds or ended.
			for i in 130:
				scene.mgr.step(DT)
			check_equal(scene.mgr.get_count(), 0, "%s, budget %d: every shot ended" % [_label(scene), work])
			by_budget.append(scene.hit_by_shot)
			_free(scene)
		var label: String = "native" if native else "GDScript"
		check(not by_budget[0].is_empty(), "%s: the shots hit the bodies" % label)
		check_equal(by_budget[1], by_budget[0], "%s: with a budget of one every shot hit the bodies it hit with none" % label)
		results.append(by_budget[1])
	if results.size() == 2:
		check_equal(results[1], results[0], "native and GDScript hit alike")


## The game's budget (WORK_PER_STEP) is sized for a full crowd at the desktop cap: there, no shot
## waits more than one step for its test.
func test_no_shot_waits_more_than_one_step_in_a_full_crowd() -> void:
	for native: bool in _modes():
		var scene := _scene(native, ARENA)
		scene.mgr.set_cap(ManagerScript.DEFAULT_CAP_DESKTOP)
		scene.mgr.work_per_step = ManagerScript.WORK_PER_STEP
		var home := PackedVector2Array()
		for i in CROWD:
			var at := Vector2(fmod(float(i) * 97.31, ARENA.size.x - 40.0) + 20.0, fmod(float(i) * 53.77 + float(i / 13) * 7.0, ARENA.size.y - 40.0) + 20.0)
			home.append(at)
			_body(scene, at, CROWD_RADIUS)
		var casters := PackedInt32Array()
		for seat in 4:
			casters.append((scene.table as ActorSeats.ActorsScript).actor_of_seat(seat))
		var fired: Array[int] = [0]
		# Deferred after a step: slot -> its shot's seq.
		var waiting: Dictionary = {}
		var waited_twice: int = 0
		var deferred_most: int = 0
		var label: String = _label(scene)
		for step in 200:
			var t: float = float(step) * DT
			for i in CROWD:
				var a: float = float(i) * 0.37 + t * 1.3
				scene.bodies[i].position = home[i] + Vector2(cos(a), sin(a)) * 18.0
			_top_up(scene, casters, fired)
			scene.mgr.step(DT)
			# Past the first flight's warm-up: the arena full of shots.
			if step < 120:
				continue
			var now: Dictionary = {}
			for slot in scene.mgr._high:
				if scene.mgr._alive[slot] != 0 and (scene.mgr._flags[slot] & ManagerScript.F_DEFERRED) != 0:
					var seq: int = scene.mgr._seq[slot]
					if waiting.get(slot, -1) == seq:
						waited_twice += 1
					now[slot] = seq
			deferred_most = maxi(deferred_most, now.size())
			waiting = now
		print("%s: full crowd at %d shots: at most %d shots waiting after a step, %d waited two" % [label, ManagerScript.DEFAULT_CAP_DESKTOP, deferred_most, waited_twice])
		check(scene.hits > 0, "%s: the crowd is hit" % label)
		check_equal(waited_twice, 0, "%s: no shot waited more than one step for its test" % label)
		_free(scene)


## The shots at the cap from the wizards in the middle, a third piercing two (as the benchmark).
func _top_up(scene: Scene, casters: PackedInt32Array, fired: Array[int]) -> void:
	var missing: int = ManagerScript.DEFAULT_CAP_DESKTOP - scene.mgr.get_count()
	if missing <= 0:
		return
	var velocities := PackedVector2Array()
	velocities.resize(missing)
	for k in missing:
		velocities[k] = Vector2.from_angle(float(fired[0] + k) * 2.399963) * SHOT_SPEED
	var slots := PackedInt32Array()
	slots.resize(missing)
	var seat: int = fired[0] % 4
	var pierce: int = 2 if fired[0] % 3 == 0 else 0
	scene.mgr.spawn_batch(casters[seat], ARENA.get_center() + Vector2(-30.0 + 20.0 * float(seat), -8.0), velocities, SHOT_LIFE, 3.0, ManagerScript.LAYER_ENEMY, pierce, 0, slots)
	fired[0] += missing


## GDScript, and the native kernel when the module is built.
func _modes() -> Array[bool]:
	var probe := ManagerScript.new()
	probe.set_native(true)
	var native: bool = probe.is_native()
	probe.free()
	return [false, true] if native else [false]


func _scene(native: bool, bounds: Rect2) -> Scene:
	var scene := Scene.new()
	scene.bus = EventsScript.new()
	scene.table = ActorSeats.table()
	scene.mgr = ManagerScript.new()
	scene.mgr.actors = scene.table
	scene.mgr.events = scene.bus
	scene.mgr.set_native(native)
	scene.mgr.set_cap(1024)
	scene.mgr.set_bounds(bounds)
	scene.bus.projectile_hit.connect(func(_caster: int, target: Node, _point: Vector2, _tag: int, shot: int) -> void:
		scene.hits += 1
		var list: Array = scene.hit_by_shot.get(shot, [])
		list.append(scene.bodies.find(target as Node2D))
		scene.hit_by_shot[shot] = list)
	return scene


func _body(scene: Scene, at: Vector2, radius: float) -> void:
	var body := Node2D.new()
	root.add_child(body)
	body.global_position = at
	scene.mgr.add_target(body, radius)
	scene.bodies.append(body)


## A slow piercing shot sitting on a body of its own, spawned first (the lowest slot): each step
## it is tested it spends a budget of one on examining that body, so the shot after it waits, and
## the step after it is that shot's turn first.
func _blocker(scene: Scene, at: Vector2 = Vector2(0.0, 300.0)) -> void:
	_body(scene, at, 6.0)
	scene.mgr.spawn(_caster(scene), at, Vector2(0.01, 0.0), 10.0, 2.0, ManagerScript.LAYER_ENEMY, 1000, 0)


func _caster(scene: Scene) -> int:
	return (scene.table as ActorSeats.ActorsScript).actor_of_seat(0)


func _label(scene: Scene) -> String:
	return "native" if scene.mgr.is_native() else "GDScript"


func _free(scene: Scene) -> void:
	for body in scene.bodies:
		body.free()
	scene.mgr.free()
	scene.table.free()
	scene.bus.free()
