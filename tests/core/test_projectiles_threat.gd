extends "res://tests/support/suite.gd"
## What an AI dodges (enemy AI AI3, docs/milestones/M2-enemy-ai.md): `Projectiles.threat` finds
## the shot of another team that will come within a radius of a point soonest, and the way off
## its line. Enemies at ids 0-6, wizards at 7-10, as in test_projectiles_actors.gd.
##
## godot --headless --path . --script res://tests/core/test_projectiles_threat.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

const IMP: int = 2
const OTHER_IMP: int = 3
const WIZ: int = 7

var mgr: ManagerScript


func before_each() -> void:
	var bus := own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.actors = own(ActorSeats.table(4, 7)) as ActorsScript
	mgr.events = bus
	mgr.set_bounds(Rect2(-1000.0, -1000.0, 2000.0, 2000.0))
	root.add_child(mgr)


func test_nothing_coming() -> void:
	check_equal(mgr.threat(Vector2.ZERO, 10.0, ActorsScript.TEAM_ENEMIES, IMP), -1.0, "no shot, no threat")
	check_equal(mgr.threat_slot, -1, "and no slot")


func test_a_shot_coming_straight() -> void:
	var slot: int = mgr.spawn(WIZ, Vector2(-200.0, 0.0), Vector2(200.0, 0.0), 3.0, 4.0, ManagerScript.ACTOR_LAYERS)
	var when: float = mgr.threat(Vector2.ZERO, 10.0, ActorsScript.TEAM_ENEMIES, IMP)
	check(absf(when - 1.0) < 0.1, "a wizard's shot 200 px away at 200 px/s arrives in about 1 s: %s" % when)
	check_equal(mgr.threat_slot, slot, "that shot")
	check(absf(mgr.threat_away.dot(Vector2.RIGHT)) < 0.01 and is_equal_approx(mgr.threat_away.length(), 1.0), "the way off is across its line: %s" % mgr.threat_away)


func test_the_side_it_is_already_on() -> void:
	mgr.spawn(WIZ, Vector2(-200.0, 0.0), Vector2(200.0, 0.0), 3.0, 4.0, ManagerScript.ACTOR_LAYERS)
	mgr.threat(Vector2(0.0, 6.0), 10.0, ActorsScript.TEAM_ENEMIES, IMP)
	check(mgr.threat_away.y > 0.9, "a body a little below the line steps further down: %s" % mgr.threat_away)
	mgr.threat(Vector2(0.0, -6.0), 10.0, ActorsScript.TEAM_ENEMIES, IMP)
	check(mgr.threat_away.y < -0.9, "and one above steps up: %s" % mgr.threat_away)


func test_shots_that_miss_or_fly_away_are_no_threat() -> void:
	mgr.spawn(WIZ, Vector2(-200.0, 100.0), Vector2(200.0, 0.0), 3.0, 4.0, ManagerScript.ACTOR_LAYERS)
	mgr.spawn(WIZ, Vector2(50.0, 0.0), Vector2(200.0, 0.0), 3.0, 4.0, ManagerScript.ACTOR_LAYERS)
	check_equal(mgr.threat(Vector2.ZERO, 10.0, ActorsScript.TEAM_ENEMIES, IMP), -1.0, "one passes far off, one flies away")


func test_too_far_or_dying_first() -> void:
	mgr.spawn(WIZ, Vector2(-900.0, 0.0), Vector2(200.0, 0.0), 10.0, 4.0, ManagerScript.ACTOR_LAYERS)
	check_equal(mgr.threat(Vector2.ZERO, 10.0, ActorsScript.TEAM_ENEMIES, IMP, 1.0), -1.0, "4.5 s away is past the horizon")
	mgr.spawn(WIZ, Vector2(-200.0, 0.0), Vector2(200.0, 0.0), 0.5, 4.0, ManagerScript.ACTOR_LAYERS)
	check_equal(mgr.threat(Vector2.ZERO, 10.0, ActorsScript.TEAM_ENEMIES, IMP, 2.0), -1.0, "a shot that ends before it arrives is none")


func test_own_team_and_own_shots_are_skipped() -> void:
	mgr.spawn(OTHER_IMP, Vector2(-200.0, 0.0), Vector2(200.0, 0.0), 3.0, 4.0, ManagerScript.ACTOR_LAYERS)
	check_equal(mgr.threat(Vector2.ZERO, 10.0, ActorsScript.TEAM_ENEMIES, IMP), -1.0, "a teammate's shot is not dodged")
	check(mgr.threat(Vector2.ZERO, 10.0, ActorsScript.NONE, IMP) > 0.0, "with no team every other actor's shot counts")
	check_equal(mgr.threat(Vector2.ZERO, 10.0, ActorsScript.NONE, OTHER_IMP), -1.0, "but never one's own")


func test_the_soonest_wins() -> void:
	mgr.spawn(WIZ, Vector2(-300.0, 0.0), Vector2(200.0, 0.0), 3.0, 4.0, ManagerScript.ACTOR_LAYERS)
	var near: int = mgr.spawn(WIZ, Vector2(0.0, 100.0), Vector2(0.0, -200.0), 3.0, 4.0, ManagerScript.ACTOR_LAYERS)
	var when: float = mgr.threat(Vector2.ZERO, 10.0, ActorsScript.TEAM_ENEMIES, IMP)
	check_equal(mgr.threat_slot, near, "the one from below arrives first")
	check(when < 0.6, "in about half a second: %s" % when)


func test_a_still_shot_on_the_point() -> void:
	mgr.spawn(WIZ, Vector2(5.0, 0.0), Vector2.ZERO, 3.0, 6.0, ManagerScript.ACTOR_LAYERS, 0, 0, ManagerScript.MOTION_STILL)
	check_equal(mgr.threat(Vector2.ZERO, 10.0, ActorsScript.TEAM_ENEMIES, IMP), 0.0, "standing on a rune is a threat now")
	check(mgr.threat_away.x < -0.9, "step away from it: %s" % mgr.threat_away)


## With THREAT_GRID_FROM shots or more an ask goes through the threat grid (performance,
## 2026-11-02). It must find what one pass over every shot finds (the same exact test, in slot
## order), for every kind of shot: fast ones whose paths span many cells, still ones, ones whose
## life ends first, near the bounds and outside them.
func test_the_grid_finds_what_one_pass_finds() -> void:
	_compare_with_one_pass(900, true)


## Below THREAT_GRID_FROM shots every ask is one pass (written out in `threat`): the same answers.
func test_one_pass_matches_the_exact_test() -> void:
	_compare_with_one_pass(ManagerScript.THREAT_GRID_FROM - 20, false)


func _compare_with_one_pass(shots: int, grid: bool) -> void:
	mgr.set_cap(1200)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026_11_02
	var casters: Array[int] = [WIZ, WIZ + 1, IMP, OTHER_IMP]
	for i in shots:
		var at := Vector2(rng.randf_range(-950.0, 950.0), rng.randf_range(-950.0, 950.0))
		var speed: float = [0.0, 60.0, 250.0, 900.0, 3000.0][i % 5]
		var motion: int = ManagerScript.MOTION_STILL if speed == 0.0 else ManagerScript.MOTION_STRAIGHT
		mgr.spawn(casters[i % 4], at, Vector2.from_angle(rng.randf() * TAU) * speed, rng.randf_range(0.2, 4.0), rng.randf_range(1.0, 12.0), ManagerScript.ACTOR_LAYERS, 0, 0, motion)
	check_equal(mgr.get_count() >= ManagerScript.THREAT_GRID_FROM, grid, "shots for the grid or not: %d" % mgr.get_count())
	mgr.step(1.0 / 60.0)
	var asked: int = 0
	var found: int = 0
	var gridded: int = 0
	for q in 400:
		var point := Vector2(rng.randf_range(-1100.0, 1100.0), rng.randf_range(-1100.0, 1100.0))
		var radius: float = rng.randf_range(4.0, 40.0)
		var team: int = [ActorsScript.TEAM_ENEMIES, ActorsScript.TEAM_WIZARDS, ActorsScript.NONE][q % 3]
		var own: int = [IMP, WIZ, -1][q % 3]
		var horizon: float = [0.9, 0.9, 0.3, 2.0][q % 4]
		var when: float = mgr.threat(point, radius, team, own, horizon)
		var slot: int = mgr.threat_slot
		var away: Vector2 = mgr.threat_away
		gridded += 1 if mgr._threat_step == mgr._step_index else 0
		# The same exact test over every slot, in order.
		mgr.threat_slot = -1
		var best: float = INF
		for s in mgr._high:
			best = mgr._threat_try(s, point, radius, team, own, horizon, best)
		var want: float = best if mgr.threat_slot >= 0 else -1.0
		asked += 1
		found += 1 if slot >= 0 else 0
		if not (when == want and slot == mgr.threat_slot and away.is_equal_approx(mgr.threat_away)):
			check(false, "ask %d at %s r %.1f: grid %s slot %d, one pass %s slot %d" % [q, point, radius, when, slot, want, mgr.threat_slot])
			return
	check(found > 20, "the asks found shots, not only none: %d of %d" % [found, asked])
	if grid:
		check(gridded > 300, "most asks went through the grid: %d of %d" % [gridded, asked])
	else:
		check_equal(gridded, 0, "no ask went through the grid")


## A shot spawned, deflected or moved by a card after the grid was built in a step is still seen
## by the next ask in that step.
func test_the_grid_sees_changes_within_a_step() -> void:
	mgr.set_cap(600)
	for i in 400:
		mgr.spawn(WIZ, Vector2(-900.0 + float(i), 900.0), Vector2(0.0, 50.0), 3.0, 2.0, ManagerScript.ACTOR_LAYERS)
	mgr.step(1.0 / 60.0)
	for n in ManagerScript.THREAT_GRID_ASKS:
		check_equal(mgr.threat(Vector2.ZERO, 10.0, ActorsScript.TEAM_ENEMIES, IMP), -1.0, "nothing heads for the point yet")
	check_equal(mgr._threat_step, mgr._step_index, "the asks built the grid")
	var slot: int = mgr.spawn(WIZ, Vector2(-200.0, 0.0), Vector2(200.0, 0.0), 3.0, 4.0, ManagerScript.ACTOR_LAYERS)
	mgr.threat(Vector2.ZERO, 10.0, ActorsScript.TEAM_ENEMIES, IMP)
	check_equal(mgr.threat_slot, slot, "a shot spawned after the grid was built")
	var away: int = mgr.spawn(WIZ, Vector2(0.0, -200.0), Vector2(0.0, -200.0), 3.0, 4.0, ManagerScript.ACTOR_LAYERS)
	mgr.step(1.0 / 60.0)
	check(mgr.is_alive(away), "the shot flying away is alive")
	check_equal(mgr.threat(Vector2(0.0, 50.0), 10.0, ActorsScript.TEAM_ENEMIES, IMP), -1.0, "it flies away from the point")
	check_equal(mgr._threat_step, mgr._step_index, "a step after a busy one builds the grid at its first ask")
	mgr.deflect_shot(away, OTHER_IMP, Vector2(0.0, 1.0), 0)
	mgr.threat(Vector2(0.0, 50.0), 10.0, ActorsScript.TEAM_WIZARDS, WIZ)
	check_equal(mgr.threat_slot, away, "deflected back toward the point, it is seen in the same step")
