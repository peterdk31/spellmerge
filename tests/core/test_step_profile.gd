extends "res://tests/support/suite.gd"
## The projectile manager's step profile and hit-work budget (shot scale H0, core/projectiles,
## tests/benchmark/shot_scale.gd): in the game `step()` reads no clock; a benchmark that sizes
## `step_profile` gets every part of the step timed by the clock it hands, the hand-backs to
## GDScript and the shots the budget left for later, and the profiled step plays exactly as the
## plain one. `work_per_step` is the budget.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const DT: float = 1.0 / 60.0
## Shots fired through the crowd each scene.
const SHOTS: int = 400


class Scene:
	extends RefCounted
	var bus: EventsScript
	var table: Node
	var mgr: ManagerScript
	var bodies: Array[Node2D] = []
	## Every hit, in order: caster, which body, the point.
	var hits: Array = []


func test_the_game_step_reads_no_clock() -> void:
	var scene := _scene(true)
	var calls: Array[int] = [0]
	scene.mgr.profile_clock = func() -> int:
		calls[0] += 1
		return 0
	for i in 30:
		scene.mgr.step(DT)
	check_equal(calls[0], 0, "with no profile the step never asks the clock")
	check(not scene.hits.is_empty(), "the scene hits something")
	_free(scene)


func test_a_profiled_step_times_every_part() -> void:
	for native: bool in [false, true]:
		var scene := _scene(native)
		# A clock that ticks one microsecond a call: every part that asks it is at least one.
		var now: Array[int] = [0]
		scene.mgr.profile_clock = func() -> int:
			now[0] += 1
			return now[0]
		scene.mgr.step_profile.resize(ManagerScript.PROF_PARTS)
		scene.mgr.step(DT)
		var profile: PackedInt64Array = scene.mgr.step_profile
		var label: String = "native" if scene.mgr.is_native() else "GDScript"
		for part: int in [ManagerScript.PROF_REFRESH, ManagerScript.PROF_COMMON, ManagerScript.PROF_BEFORE, ManagerScript.PROF_HITS, ManagerScript.PROF_AFTER, ManagerScript.PROF_DASHES]:
			check(profile[part] >= 1, "%s: part %d is timed (%d)" % [label, part, profile[part]])
		if scene.mgr.is_native():
			check(profile[ManagerScript.PROF_HANDBACKS] >= 1, "native: the kernel's calls are counted")
			check(profile[ManagerScript.PROF_KERNEL] >= profile[ManagerScript.PROF_HANDBACKS], "native: the kernel's time is timed per call")
			check(profile[ManagerScript.PROF_KERNEL] < profile[ManagerScript.PROF_HITS], "native: the kernel's time is part of the hit pass's")
		else:
			check_equal(profile[ManagerScript.PROF_HANDBACKS], 0, "GDScript: no kernel, no hand-backs")
		_free(scene)


func test_the_parts_cover_the_whole_step() -> void:
	for native: bool in [false, true]:
		var scene := _scene(native)
		var reads: Array[int] = []
		scene.mgr.profile_clock = func() -> int:
			reads.append(reads.size())
			return reads.size()
		scene.mgr.step_profile.resize(ManagerScript.PROF_PARTS)
		for i in 12:
			reads.clear()
			scene.mgr.step(DT)
		var profile: PackedInt64Array = scene.mgr.step_profile
		var parts: int = 0
		for part: int in [ManagerScript.PROF_REFRESH, ManagerScript.PROF_COMMON, ManagerScript.PROF_BEFORE, ManagerScript.PROF_HITS, ManagerScript.PROF_AFTER, ManagerScript.PROF_DASHES]:
			parts += profile[part]
		# The clock reads 1, 2, 3, ...: the step's whole span is the last read less the first.
		check_equal(parts, reads.size() - 1, "%s: the parts follow each other with no gap from the step's first clock read to its last" % ("native" if scene.mgr.is_native() else "GDScript"))
		_free(scene)


func test_profiling_changes_nothing_in_the_game() -> void:
	for native: bool in [false, true]:
		var plain := _scene(native)
		var timed := _scene(native)
		timed.mgr.profile_clock = Time.get_ticks_usec
		timed.mgr.step_profile.resize(ManagerScript.PROF_PARTS)
		for i in 60:
			plain.mgr.step(DT)
			timed.mgr.step(DT)
		check(not plain.hits.is_empty(), "the scene hits something")
		check_equal(timed.hits, plain.hits, "the same hits, in the same order, at the same points")
		check_equal(timed.mgr.get_count(), plain.mgr.get_count(), "the same shots alive")
		_free(plain)
		_free(timed)


func test_the_work_budget_leaves_shots_for_a_later_step_and_counts_them() -> void:
	for native: bool in [false, true]:
		var results: Array[Array] = []
		for work: int in [1 << 40, 1]:
			var scene := _scene(native)
			scene.mgr.work_per_step = work
			scene.mgr.profile_clock = Time.get_ticks_usec
			scene.mgr.step_profile.resize(ManagerScript.PROF_PARTS)
			var most_past: int = 0
			for i in 20:
				scene.mgr.step(DT)
				most_past = maxi(most_past, scene.mgr.step_profile[ManagerScript.PROF_PAST_BUDGET])
			results.append([most_past, scene.hits.size()])
			_free(scene)
		var label: String = "native" if native else "GDScript"
		check_equal(results[0][0], 0, "%s: a lifted budget tests every shot every step" % label)
		check(results[1][0] > 0, "%s: a budget of one leaves shots for a later step, counted (%d)" % [label, results[1][0]])
		check(results[0][1] > 0 and results[1][1] < results[0][1], "%s: and hits less (%d against %d)" % [label, results[1][1], results[0][1]])


## A crowd of bodies on a line and SHOTS shots fired through it from the left.
func _scene(native: bool) -> Scene:
	var scene := Scene.new()
	scene.bus = EventsScript.new()
	scene.table = ActorSeats.table()
	scene.mgr = ManagerScript.new()
	scene.mgr.actors = scene.table
	scene.mgr.events = scene.bus
	scene.mgr.set_native(native)
	scene.mgr.set_cap(1024)
	scene.mgr.set_bounds(Rect2(-400.0, -400.0, 800.0, 800.0))
	for i in 12:
		var body := Node2D.new()
		root.add_child(body)
		body.global_position = Vector2(20.0 + 12.0 * float(i), float(i % 3) * 6.0 - 6.0)
		scene.mgr.add_target(body, 8.0)
		scene.bodies.append(body)
	scene.bus.projectile_hit.connect(func(caster: int, target: Node, point: Vector2, _tag: int, _shot: int) -> void:
		scene.hits.append([caster, scene.bodies.find(target as Node2D), point]))
	var velocities := PackedVector2Array()
	for i in SHOTS:
		velocities.append(Vector2(300.0, float(i % 21) - 10.0))
	var slots := PackedInt32Array()
	slots.resize(SHOTS)
	scene.mgr.spawn_batch((scene.table as ActorSeats.ActorsScript).actor_of_seat(0), Vector2(-20.0, 0.0), velocities, 2.0, 3.0, ManagerScript.LAYER_ENEMY, 1, 0, slots)
	return scene


func _free(scene: Scene) -> void:
	for body in scene.bodies:
		body.free()
	scene.mgr.free()
	scene.table.free()
	scene.bus.free()
