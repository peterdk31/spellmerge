extends "res://tests/support/suite.gd"
## Tests for core/projectiles, one behaviour each: movement and lifetime, hits and their event
## (caster, target, tag, place, travel order), layers, piercing, fast shots that must not tunnel,
## the global cap (who is dropped, the run's rules, a smaller cap), slot reuse, refused spawns, the
## hit-work budget and where the next step resumes, walls (ends, tunnelling, edges, clipping, wall
## bodies), expiry events, still shots (runes), target queries (`nearest_target`, `targets_in`)
## and the batched draw (one batch per kind, sized to its shots). 1,000 shots and random queries
## are checked against a brute-force search.
##
## Each test gets a fresh manager with an event bus and a table of four wizards at ids 0-3
## (`before_each`), out of the tree unless it draws; the manager is stepped by hand.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const DT: float = 1.0 / 60.0
## The room most wall tests use, and its one wall: x 96..128, y 0..200.
const ROOM: Rect2 = Rect2(0.0, 0.0, 640.0, 360.0)
const WALL: Rect2 = Rect2(96.0, 0.0, 32.0, 200.0)
## The shots of the packed piercing crowd (`_a_packed_piercing_crowd`).
const CROWD_SHOTS: int = 150
## The point the query tests ask round (`_three_round_a_point`).
const QUERY_POINT: Vector2 = Vector2(100.0, 100.0)

var bus: EventsScript
var mgr: ManagerScript
## Wizards at ids 0-3, seated 0-3 (the casters these tests use).
var table: ActorSeats.ActorsScript
## The targets made by `_target`, in order.
var targets: Array[Node2D] = []
## Every projectile_hit as [caster, target, position, tag].
var hits: Array = []
## Every projectile_expired as [caster, position, tag].
var expired: Array = []


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	table = own(ActorSeats.table()) as ActorSeats.ActorsScript
	mgr.actors = table
	mgr.events = bus
	targets.clear()
	hits.clear()
	expired.clear()
	bus.projectile_expired.connect(func(caster: int, position: Vector2, tag: int, _shot: int) -> void: expired.append([caster, position, tag]))
	# One row a hit: a merged hit (a step's hits of one spell on one body) stands for `impact_count`.
	bus.projectile_hit.connect(func(caster: int, target: Node, position: Vector2, tag: int, _shot: int) -> void:
		for n in mgr.impact_count:
			hits.append([caster, target, position, tag]))


## A target in the tree at `position`.
func _target(position: Vector2, radius: float = 10.0, layer: int = ManagerScript.LAYER_ENEMY) -> Node2D:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.global_position = position
	targets.append(node)
	mgr.add_target(node, radius, layer)
	return node


func _run(steps: int) -> void:
	for _i in steps:
		mgr.step(DT)


## The room with its one wall.
func _walled_room() -> void:
	mgr.set_bounds(ROOM)
	mgr.set_walls([WALL] as Array[Rect2])


## The manager in the tree, so it has its batches to draw into.
func _drawing() -> void:
	root.add_child(mgr)


## `count` bolts of seat 0 in a row from x 1, standing nearly still.
func _row_of_bolts(count: int) -> void:
	for i in count:
		mgr.spawn(0, Vector2(float(i) + 1.0, 0.0), Vector2(1.0, 0.0), 5.0)


# --- Movement and hits ---------------------------------------------------------------------


func test_a_shot_moves_by_its_velocity_each_step() -> void:
	var slot: int = mgr.spawn(0, Vector2.ZERO, Vector2(60.0, 0.0), 0.5)
	check(slot >= 0 and mgr.get_count() == 1, "spawn starts one projectile")
	mgr.step(0.25)
	check(mgr.get_position_of(slot).is_equal_approx(Vector2(15.0, 0.0)), "it moves velocity * delta")


func test_a_shot_ends_when_its_lifetime_is_over() -> void:
	var slot: int = mgr.spawn(0, Vector2.ZERO, Vector2(60.0, 0.0), 0.5)
	mgr.step(0.25)
	mgr.step(0.25)
	check(mgr.get_count() == 0 and not mgr.is_alive(slot), "it ends when its lifetime is over")
	check_equal(mgr.get_position_of(slot), Vector2.INF, "a dead slot has no position")


func test_a_hit_sends_an_event_naming_the_caster_and_the_target() -> void:
	var enemy: Node2D = _target(Vector2(30.0, 0.0))
	mgr.spawn(2, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0)
	mgr.step(DT)
	check_equal(hits.size(), 1, "one hit event")
	if hits.size() == 1:
		check(hits[0][0] == 2 and hits[0][1] == enemy, "the event names the player and the target")


func test_a_hit_ends_the_shot() -> void:
	_target(Vector2(30.0, 0.0))
	mgr.spawn(2, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0)
	mgr.step(DT)
	check_equal(mgr.get_count(), 0, "the projectile ends on a hit")
	mgr.step(DT)
	check_equal(hits.size(), 1, "no second event")


func test_hits_in_one_step_each_name_their_own_caster() -> void:
	var a: Node2D = _target(Vector2(30.0, 0.0))
	var b: Node2D = _target(Vector2(30.0, 400.0))
	mgr.spawn(0, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0)
	mgr.spawn(3, Vector2(0.0, 400.0), Vector2(1200.0, 0.0), 1.0)
	mgr.step(DT)
	check_equal(hits.size(), 2, "two hits at once")
	for hit: Array in hits:
		if hit[1] == a:
			check(hit[0] == 0, "player 0's shot hit the first target")
		elif hit[1] == b:
			check(hit[0] == 3, "player 3's shot hit the second target")
		else:
			check(false, "a hit named an unknown target")


func test_a_shot_at_enemies_hits_a_player_target_too() -> void:
	_target(Vector2(30.0, 0.0), 10.0, ManagerScript.LAYER_PLAYER)
	mgr.spawn(0, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0, 4.0, ManagerScript.LAYER_ENEMY)
	mgr.step(DT)
	check(hits.size() == 1 and mgr.get_count() == 0, "a shot at enemies hits a player target too (actors G3c: every shot hits both layers)")


func test_a_shot_of_no_actor_hits_a_wizard_naming_no_actor() -> void:
	_target(Vector2(30.0, 0.0), 10.0, ManagerScript.LAYER_PLAYER)
	mgr.spawn(EventsScript.NO_PLAYER, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0, 4.0, ManagerScript.LAYER_PLAYER)
	mgr.step(DT)
	check(hits.size() == 1 and hits[0][0] == EventsScript.NO_PLAYER, "a shot of no actor hits a wizard's target, naming no actor")
	check_equal(mgr.get_count_for(EventsScript.NO_PLAYER), 0, "the shot ended")


func test_a_shot_that_passes_wide_misses() -> void:
	_target(Vector2(30.0, 40.0), 10.0)
	mgr.spawn(0, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0, 4.0)
	mgr.step(DT)
	check(hits.is_empty() and mgr.get_count() == 1, "a shot that passes 40 px away misses a 10 px target")


func test_a_fast_shot_does_not_tunnel() -> void:
	# 3000 px/s is 50 px per step: it starts left of the target and ends right of it.
	_target(Vector2(25.0, 0.0), 6.0)
	mgr.spawn(0, Vector2(-5.0, 0.0), Vector2(3000.0, 0.0), 1.0, 2.0)
	mgr.step(DT)
	check_equal(hits.size(), 1, "a fast shot hits a target it passed over within one step")


func test_a_shot_touching_the_edge_of_a_big_target_hits_it() -> void:
	# A radius-80 target whose centre is 3 cells from the shot's end point.
	var boss: Node2D = _target(Vector2(200.0, 0.0), 80.0)
	mgr.spawn(0, Vector2(100.0, 0.0), Vector2(1200.0, 0.0), 1.0, 4.0)
	mgr.step(DT)
	check(hits.size() == 1 and hits[0][1] == boss, "a shot touching the edge of a radius-80 target hits it")


func test_a_5000_px_s_shot_hits_a_big_target() -> void:
	# 5000 px/s is 83 px per step.
	_target(Vector2(200.0, 0.0), 80.0)
	mgr.spawn(0, Vector2(40.0, 0.0), Vector2(5000.0, 0.0), 1.0, 4.0)
	mgr.step(DT)
	check_equal(hits.size(), 1, "a 5,000 px/s shot hits a big target")


func test_a_30000_px_s_shot_hits_a_small_target_on_its_path() -> void:
	_target(Vector2(500.0, 0.0), 6.0)
	mgr.spawn(0, Vector2(400.0, 0.0), Vector2(30000.0, 0.0), 1.0, 2.0)
	mgr.step(DT)
	check_equal(hits.size(), 1, "a 30,000 px/s shot (500 px per step) hits a small target on the way")


func test_a_30000_px_s_shot_misses_a_target_off_its_path() -> void:
	_target(Vector2(500.0, 100.0), 6.0)
	mgr.spawn(0, Vector2(400.0, 0.0), Vector2(30000.0, 0.0), 1.0, 2.0)
	mgr.step(DT)
	check(hits.is_empty(), "a 30,000 px/s shot misses a target 100 px off its path")


## Two targets on one path; the far one is registered last, so it comes first in the grid chain.
func _near_and_far_on_a_path() -> Node2D:
	var near: Node2D = _target(Vector2(20.0, 0.0), 10.0)
	_target(Vector2(60.0, 0.0), 10.0)
	mgr.spawn(0, Vector2.ZERO, Vector2(4800.0, 0.0), 1.0, 2.0)
	mgr.step(DT)
	return near


func test_the_nearest_target_along_the_path_is_hit_first() -> void:
	var near: Node2D = _near_and_far_on_a_path()
	check(hits.size() == 1 and hits[0][1] == near, "the nearest target along the path is hit first")


func test_the_hit_position_is_the_closest_point_on_the_path() -> void:
	_near_and_far_on_a_path()
	check(hits.size() == 1 and (hits[0][2] as Vector2).is_equal_approx(Vector2(20.0, 0.0)), "the hit position is the closest point on the path (%s)" % str(hits))


func test_each_hit_carries_the_tag_of_its_own_shot() -> void:
	_target(Vector2(20.0, 0.0))
	_target(Vector2(20.0, 100.0))
	mgr.spawn(0, Vector2.ZERO, Vector2(600.0, 0.0), 1.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 41)
	mgr.spawn(1, Vector2(0.0, 100.0), Vector2(600.0, 0.0), 1.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 42)
	mgr.spawn(2, Vector2(0.0, 500.0), Vector2(600.0, 0.0), 1.0)
	_run(4)
	check_equal(hits.size(), 2, "both tagged shots hit")
	var tags: Dictionary = {}
	for hit: Array in hits:
		tags[hit[0]] = hit[3]
	check(tags.get(0, -1) == 41 and tags.get(1, -1) == 42, "each hit carries the tag of its own projectile (%s)" % str(tags))


func test_an_untagged_shot_in_a_reused_slot_sends_tag_0() -> void:
	_target(Vector2(20.0, 0.0))
	mgr.spawn(0, Vector2.ZERO, Vector2(600.0, 0.0), 1.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 99)
	mgr.step(DT * 4.0)
	mgr.spawn(0, Vector2.ZERO, Vector2(600.0, 0.0), 1.0)
	hits.clear()
	mgr.step(DT * 4.0)
	check(hits.size() == 1 and hits[0][3] == 0, "an untagged shot in a reused slot sends tag 0")


# --- Piercing ------------------------------------------------------------------------------


## A pierce-1 shot through two targets on its line, stepped until it is spent; its slot.
func _pierce_1_through_two() -> int:
	_target(Vector2(20.0, 0.0))
	_target(Vector2(60.0, 0.0))
	var slot: int = mgr.spawn(1, Vector2.ZERO, Vector2(600.0, 0.0), 1.0, 4.0, ManagerScript.LAYER_ENEMY, 1)
	_run(12)
	return slot


func test_a_pierce_1_shot_hits_two_targets_in_the_order_it_reaches_them() -> void:
	_pierce_1_through_two()
	check_equal(hits.size(), 2, "a pierce-1 shot hits two targets, once each")
	if hits.size() == 2:
		check(hits[0][1] == targets[0] and hits[1][1] == targets[1], "in the order it reached them")


func test_a_pierce_1_shot_ends_on_its_second_hit() -> void:
	var slot: int = _pierce_1_through_two()
	check(not mgr.is_alive(slot), "a pierce-1 shot ends on the second")


## Two overlapping targets and a pierce-2 shot through them; its slot.
func _pierce_2_through_a_crowd() -> int:
	_target(Vector2(30.0, 0.0), 14.0)
	_target(Vector2(38.0, 4.0), 14.0)
	var slot: int = mgr.spawn(0, Vector2.ZERO, Vector2(300.0, 0.0), 1.0, 4.0, ManagerScript.LAYER_ENEMY, 2)
	_run(30)
	return slot


func test_a_piercing_shot_hits_each_of_two_overlapping_targets_once() -> void:
	_pierce_2_through_a_crowd()
	check_equal(hits.size(), 2, "two overlapping targets give two events")
	var seen: Array = []
	for hit: Array in hits:
		check(not seen.has(hit[1]), "no target is hit twice")
		seen.append(hit[1])
	check(seen.has(targets[0]) and seen.has(targets[1]), "each target was hit")


func test_a_piercing_shot_keeps_the_pierce_it_did_not_spend() -> void:
	var slot: int = _pierce_2_through_a_crowd()
	check(mgr.is_alive(slot), "the pierce-2 shot keeps one pierce after two hits")


## One step of 480 px past three targets by a pierce-3 shot; its slot.
func _fast_pierce_past_three() -> int:
	_target(Vector2(100.0, 0.0), 10.0)
	_target(Vector2(200.0, 0.0), 10.0)
	_target(Vector2(300.0, 0.0), 10.0)
	var slot: int = mgr.spawn(0, Vector2.ZERO, Vector2(28800.0, 0.0), 1.0, 2.0, ManagerScript.LAYER_ENEMY, 3)
	mgr.step(DT)
	return slot


func test_a_fast_piercing_shot_hits_every_target_on_its_path_in_one_step() -> void:
	_fast_pierce_past_three()
	check_equal(hits.size(), 3, "a fast piercing shot hits every target on its path in one step")
	if hits.size() == 3:
		check(hits[0][1] == targets[0] and hits[1][1] == targets[1] and hits[2][1] == targets[2], "in the order along the path")


func test_a_fast_piercing_shot_keeps_its_last_pierce() -> void:
	var slot: int = _fast_pierce_past_three()
	check(mgr.is_alive(slot), "pierce 3 after three hits keeps its last pierce")


func test_a_fast_shot_without_pierce_stops_at_the_first_target() -> void:
	_target(Vector2(100.0, 0.0), 10.0)
	_target(Vector2(200.0, 0.0), 10.0)
	mgr.spawn(0, Vector2.ZERO, Vector2(28800.0, 0.0), 1.0, 2.0)
	mgr.step(DT)
	check_equal(hits.size(), 1, "a shot without pierce stops at the first target")


# --- The cap -------------------------------------------------------------------------------


## A cap of 6, its first shot expired, full again: the slot of the oldest living shot.
func _a_full_cap_after_a_death() -> int:
	mgr.set_cap(6)
	var short_lived: int = mgr.spawn(0, Vector2(0.0, 0.0), Vector2.ZERO, 0.01)
	var keep_old: int = mgr.spawn(0, Vector2(1.0, 0.0), Vector2.ZERO, 5.0)
	for i in 4:
		mgr.spawn(0, Vector2(2.0 + i, 0.0), Vector2.ZERO, 5.0)
	mgr.step(DT)
	check(not mgr.is_alive(short_lived) and mgr.get_count() == 5, "the first shot expired")
	mgr.spawn(0, Vector2(10.0, 0.0), Vector2.ZERO, 5.0)
	check_equal(mgr.get_count(), 6, "full again")
	return keep_old


func test_after_a_death_the_cap_drops_the_oldest_living_shot() -> void:
	var keep_old: int = _a_full_cap_after_a_death()
	mgr.spawn(0, Vector2(11.0, 0.0), Vector2.ZERO, 5.0)
	check(keep_old >= 0 and mgr.dropped == 1, "one shot was dropped")
	var survivors: int = 0
	for s in 6:
		if mgr.is_alive(s) and mgr.get_position_of(s).x == 1.0:
			survivors += 1
	check_equal(survivors, 0, "the oldest living shot is the one dropped")


func test_the_owner_counts_stay_consistent_under_churn_at_the_cap() -> void:
	_a_full_cap_after_a_death()
	for i in 20:
		mgr.spawn(i % 2, Vector2(20.0 + i, 0.0), Vector2.ZERO, 5.0)
	check(mgr.get_count() == 6 and mgr.get_count_for(0) + mgr.get_count_for(1) == 6, "the lists stay consistent under churn")


func test_the_default_cap_follows_the_platform() -> void:
	var expected: int = ManagerScript.DEFAULT_CAP_WEB if OS.has_feature("web") else ManagerScript.DEFAULT_CAP_DESKTOP
	check_equal(mgr.get_cap(), expected, "the default cap on this platform")


func test_the_machines_rules_start_at_the_platforms_cap() -> void:
	check_equal(SessionRules.defaults().shot_cap, ShotCap.default_cap(), "the machine's rules start at the platform's cap")


## The "Max shots" setting (`projectile_cap_changed`) is this machine's, for the next run: the
## manager does not hear it.
func test_the_max_shots_setting_alone_changes_no_game() -> void:
	_drawing()
	for i in 5:
		mgr.spawn(0, Vector2(float(i), 0.0), Vector2.RIGHT, 5.0)
	bus.projectile_cap_changed.emit(250)
	check(mgr.get_cap() != 250 and mgr.get_count() == 5, "the setting alone changes no game")


## Rules with a cap of 250 and a hit work of 1234.
func _rules_250() -> SessionRules:
	var rules := SessionRules.new()
	rules.shot_cap = 250
	rules.hit_work = 1234
	return rules


## The run's rules set the cap (`take_rules`, online-ready N11): the shots in the air end.
func test_the_rules_cap_applies_and_ends_the_shots_in_the_air() -> void:
	for i in 5:
		mgr.spawn(0, Vector2(float(i), 0.0), Vector2.RIGHT, 5.0)
	mgr.take_rules(_rules_250())
	check(mgr.get_cap() == 250 and mgr.get_count() == 0, "the rules' cap applies and the shots in the air end")


func test_the_rules_set_the_hit_work() -> void:
	mgr.take_rules(_rules_250())
	check_equal(mgr.work_per_step, 1234, "the rules' hit work")


func test_the_manager_fills_and_drops_at_the_rules_cap() -> void:
	mgr.take_rules(_rules_250())
	for i in 300:
		mgr.spawn(i % 4, Vector2(float(i % 50), 0.0), Vector2.RIGHT, 5.0)
	check_equal(mgr.get_count(), 250, "it fills and drops at the new cap")


func test_the_same_rules_again_keep_the_shots() -> void:
	var rules: SessionRules = _rules_250()
	mgr.take_rules(rules)
	for i in 300:
		mgr.spawn(i % 4, Vector2(float(i % 50), 0.0), Vector2.RIGHT, 5.0)
	mgr.take_rules(rules)
	check_equal(mgr.get_count(), 250, "the same rules again keep the shots")


func test_a_saved_shot_cap_snaps_to_the_nearest_stop() -> void:
	check_equal(ShotCap.snap(1), ShotCap.STOPS[0], "below the lowest stop: the lowest")
	check_equal(ShotCap.snap(1_000_000), ShotCap.STOPS[-1], "above the highest stop: the highest")
	check_equal(ShotCap.snap(5000), 4000, "a tie snaps to the lower stop")


## Forty shots in a cap of 40, then a cap of 10 (regression, 2026-10-30: a cap going from 1,000 to
## 500 with shots alive in slots past 500; set_cap read past its shrunk arrays and broke the
## manager); the tags of the shots that ended.
func _a_smaller_cap_over_high_slots() -> Array[int]:
	mgr.set_cap(40)
	var ended: Array[int] = []
	mgr.shot_ended.connect(func(tag: int) -> void: ended.append(tag))
	for i in 40:
		mgr.spawn(0, Vector2(float(i), 0.0), Vector2.RIGHT, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 1000 + i)
	check_equal(mgr.get_count(), 40, "forty shots fill the cap")
	mgr.set_cap(10)
	return ended


func test_a_smaller_cap_starts_empty_and_ends_every_shot() -> void:
	var ended: Array[int] = _a_smaller_cap_over_high_slots()
	check(mgr.get_cap() == 10 and mgr.get_count() == 0, "the smaller cap starts empty")
	check_equal(ended.size(), 40, "every shot that was removed ended")


func test_a_smaller_cap_over_high_slots_fills_and_drops_as_usual() -> void:
	_a_smaller_cap_over_high_slots()
	for i in 12:
		mgr.spawn(0, Vector2(float(i), 0.0), Vector2.RIGHT, 5.0)
	mgr.step(DT)
	mgr.update_draw()
	check_equal(mgr.get_count(), 10, "the smaller cap fills and drops as usual")


func test_a_spawn_with_bad_arguments_is_refused() -> void:
	check_equal(mgr.spawn(ManagerScript.ACTORS, Vector2.ZERO, Vector2.RIGHT, 1.0), -1, "a caster past the last actor id is refused")
	check_equal(mgr.spawn(-2, Vector2.ZERO, Vector2.RIGHT, 1.0), -1, "caster -2 is refused")
	check_equal(mgr.spawn(0, Vector2.ZERO, Vector2.RIGHT, 0.0), -1, "zero lifetime is refused")
	check_equal(mgr.spawn(0, Vector2(NAN, 0.0), Vector2.RIGHT, 1.0), -1, "a NaN position is refused")
	check_equal(mgr.spawn(0, Vector2.ZERO, Vector2(INF, 0.0), 1.0), -1, "an infinite velocity is refused")
	check_equal(mgr.get_count(), 0, "refused spawns leave nothing behind")


func test_counting_an_invalid_caster_gives_0() -> void:
	check_equal(mgr.get_count_for(ManagerScript.ACTORS), 0, "counting an invalid caster gives 0")


## A cap of 10 filled by seat 0 (its first shot at x 1 the oldest), then a shot of seat 1: the
## oldest shot's slot and the new shot's.
func _a_full_cap_and_one_more() -> Vector2i:
	mgr.set_cap(10)
	var oldest: int = mgr.spawn(0, Vector2(1.0, 0.0), Vector2.ZERO, 5.0)
	for i in 9:
		mgr.spawn(0, Vector2(2.0 + i, 0.0), Vector2.ZERO, 5.0)
	check_equal(mgr.get_count(), 10, "the cap fills to 10")
	return Vector2i(oldest, mgr.spawn(1, Vector2(100.0, 0.0), Vector2.ZERO, 5.0))


func test_a_full_cap_still_takes_a_new_shot_by_dropping_one() -> void:
	var slots: Vector2i = _a_full_cap_and_one_more()
	check(slots.y >= 0, "a full cap still accepts the new shot")
	check_equal(mgr.get_count(), 10, "and stays at the cap")
	check_equal(mgr.dropped, 1, "one projectile was dropped")


func test_the_cap_drops_from_the_budget_that_owns_the_most() -> void:
	_a_full_cap_and_one_more()
	check(mgr.get_count_for(0) == 9 and mgr.get_count_for(1) == 1, "from the budget (seat 0) that owned the most")


func test_the_cap_drops_the_oldest_shot_and_reuses_its_slot() -> void:
	var slots: Vector2i = _a_full_cap_and_one_more()
	check_equal(slots.y, slots.x, "the oldest one's slot was reused")
	var survivors: int = 0
	for s in 10:
		if mgr.is_alive(s) and mgr.get_position_of(s).x == 1.0:
			survivors += 1
	check_equal(survivors, 0, "the oldest shot is the one that went")


## Seat 0 floods a cap of 40; the others fire a little.
func _a_flood_at_a_cap_of_40() -> void:
	mgr.set_cap(40)
	for i in 200:
		mgr.spawn(0, Vector2(i, 0.0), Vector2.ZERO, 5.0)
		if i % 20 == 0:
			mgr.spawn(1 + floori(i / 20.0) % 3, Vector2(i, 10.0), Vector2.ZERO, 5.0)


func test_the_cap_holds_under_a_flood() -> void:
	_a_flood_at_a_cap_of_40()
	check_equal(mgr.get_count(), 40, "the cap holds under a flood")
	check(mgr.dropped > 0, "the flood dropped some")
	check_equal(mgr.get_count_for(0) + mgr.get_count_for(1) + mgr.get_count_for(2) + mgr.get_count_for(3), 40, "the per-player counts add up")


func test_under_a_flood_every_player_keeps_shots() -> void:
	_a_flood_at_a_cap_of_40()
	for player in 4:
		check(mgr.get_count_for(player) > 0, "player %d still has projectiles" % player)


## 2,000 spawns into a cap of 100, a step every third; the most shots alive at once.
func _churn_at_a_cap_of_100() -> int:
	mgr.set_cap(100)
	var worst: int = 0
	for i in 2000:
		mgr.spawn(i % 4, Vector2(i % 50, 0.0), Vector2(30.0, 0.0), 100.0)
		if i % 3 == 0:
			mgr.step(DT)
		worst = maxi(worst, mgr.get_count())
	return worst


func test_the_count_reaches_the_cap_and_never_passes_it() -> void:
	check_equal(_churn_at_a_cap_of_100(), 100, "the most shots alive at once")
	check_equal(mgr.get_cap(), 100, "the cap is unchanged")


func test_the_arrays_never_grow_under_churn() -> void:
	mgr.set_cap(100)
	var size_before: int = mgr._pos.size()
	_churn_at_a_cap_of_100()
	check(mgr._pos.size() == size_before and mgr._alive.size() == 100, "the arrays never grow")


func test_slots_are_reused_without_a_drop() -> void:
	mgr.set_cap(8)
	for round_index in 50:
		for i in 8:
			mgr.spawn(round_index % 4, Vector2.ZERO, Vector2(10.0, 0.0), 0.1)
		check(mgr.get_count() == 8, "round %d fills the 8 slots" % round_index)
		_run(7)
		check(mgr.get_count() == 0, "round %d: all expired" % round_index)
	check_equal(mgr.dropped, 0, "reuse never needed a drop")
	check_equal(mgr._pos.size(), 8, "still 8 slots")
	var slot: int = mgr.spawn(0, Vector2.ZERO, Vector2.ZERO, 1.0)
	check(slot >= 0 and slot < 8, "a new shot takes a free slot")


# --- 1,000 shots against a brute-force search ------------------------------------------------


## 100 targets and 1,000 shots at random (seed 7), stepped once; the hits a brute-force search
## expects, and how many more are within float rounding of the reach, as (expected, borderline).
func _one_thousand_shots() -> Vector2i:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var centers: Array[Vector2] = []
	for i in 100:
		var at := Vector2(rng.randf_range(-900.0, 900.0), rng.randf_range(-900.0, 900.0))
		centers.append(at)
		_target(at, 12.0)
	var starts: Array[Vector2] = []
	var moves: Array[Vector2] = []
	for i in 1000:
		var start := Vector2(rng.randf_range(-900.0, 900.0), rng.randf_range(-900.0, 900.0))
		var velocity := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(100.0, 2000.0)
		starts.append(start)
		moves.append(velocity * DT)
		mgr.spawn(i % 4, start, velocity, 5.0, 4.0)
	check_equal(mgr.get_count(), 1000, "1,000 projectiles are alive")
	# The manager stores float32; the search here is float64. Cases within 0.01
	# px of the reach could go either way, so they only widen the allowed range.
	var expected_hits: int = 0
	var borderline: int = 0
	for i in 1000:
		var nearest: float = INF
		for center in centers:
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(center, starts[i], starts[i] + moves[i])
			nearest = minf(nearest, closest.distance_to(center))
		if nearest <= 15.99:
			expected_hits += 1
		elif nearest <= 16.01:
			borderline += 1
	mgr.step(DT)
	check(expected_hits > 0, "the layout has hits to find (%d)" % expected_hits)
	return Vector2i(expected_hits, borderline)


func test_one_thousand_shots_find_the_hits_a_brute_force_search_does() -> void:
	var expected: Vector2i = _one_thousand_shots()
	check(hits.size() >= expected.x and hits.size() <= expected.x + expected.y, "the grid finds the hits a brute-force search does (%d vs %d, %d borderline)" % [hits.size(), expected.x, expected.y])


func test_one_thousand_shots_end_exactly_the_ones_that_hit() -> void:
	_one_thousand_shots()
	check_equal(mgr.get_count(), 1000 - hits.size(), "the shots that hit end, and only those")


# --- The draw --------------------------------------------------------------------------------


## 1,000 shots in a grid over the play area and a target in their way, 30 steps on.
func _one_thousand_flying() -> void:
	_drawing()
	for i in 1000:
		mgr.spawn(i % 4, Vector2(-500.0 + i % 100 * 10.0, -400.0 + floorf(i / 100.0) * 80.0), Vector2(200.0, 40.0), 2.0)
	_target(Vector2(0.0, 0.0), 30.0)
	_run(30)
	check(mgr.get_count() > 900, "most of the 1,000 are still flying (%d)" % mgr.get_count())


func test_one_batch_draws_every_live_shot() -> void:
	_one_thousand_flying()
	mgr.update_draw()
	check_equal(mgr.drawn, mgr.get_count(), "one batch holds every live projectile")


func test_a_fixed_draw_fraction_draws_every_live_shot() -> void:
	_one_thousand_flying()
	mgr.update_draw(1.0)
	check_equal(mgr.drawn, mgr.get_count(), "a fixed draw fraction (the clip recorder's) draws every live projectile too")


func test_clear_empties_the_drawn_batch() -> void:
	_one_thousand_flying()
	mgr.update_draw()
	mgr.clear()
	mgr.update_draw()
	check(mgr.drawn == 0 and mgr.get_count() == 0, "clear empties the batch")
	check_equal(mgr._draw_node.multimesh.visible_instance_count, 0, "clear empties the drawn multimesh, not just the counter")


## Regression (issue #102): the autoload is drawn before the room, so shots need a raised z_index to show above its floor.
func test_the_shots_are_drawn_above_the_rooms_floor() -> void:
	_drawing()
	check(mgr._draw_node.z_index >= 1, "the shots are drawn above the room's floor")


## Regression (issue #102): without a culling box covering the area, shots away from the origin were never drawn.
func test_the_batchs_culling_box_covers_the_play_area() -> void:
	_one_thousand_flying()
	mgr.update_draw()
	var box: AABB = mgr._draw_node.multimesh.custom_aabb
	check(box.has_point(Vector3(-500.0, -400.0, 0.0)) and box.has_point(Vector3(900.0, 900.0, 0.0)), "the batch's culling box covers the whole play area")


## A bolt of seat 1 and a rune of seat 2, each with a frost core; their slots.
func _a_frost_bolt_and_rune() -> Vector2i:
	_drawing()
	var bolt: int = mgr.spawn(1, Vector2(10.0, 0.0), Vector2(100.0, 0.0), 1.0)
	var rune: int = mgr.spawn(2, Vector2(20.0, 0.0), Vector2.ZERO, 1.0, 8.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	check(mgr.set_core(bolt, _frost()) and mgr.set_core(rune, _frost()), "set_core takes a colour for a live shot")
	return Vector2i(bolt, rune)


func _frost() -> Color:
	return Color(0.5, 0.75, 0.94)


func test_set_core_takes_a_colour_for_a_live_shot() -> void:
	_a_frost_bolt_and_rune()


func test_set_core_refuses_a_slot_out_of_range() -> void:
	check(not mgr.set_core(-1, _frost()) and not mgr.set_core(999999, _frost()), "set_core refuses a slot out of range")


func test_set_core_refuses_a_colour_that_is_not_finite() -> void:
	var bolt: int = mgr.spawn(1, Vector2(10.0, 0.0), Vector2(100.0, 0.0), 1.0)
	check(not mgr.set_core(bolt, Color(NAN, 0.0, 0.0)), "set_core refuses a colour that is not finite")


func test_bolts_and_runes_are_drawn_in_batches_of_their_own() -> void:
	_a_frost_bolt_and_rune()
	mgr.update_draw()
	check_equal(mgr.drawn, 2, "the two shots are drawn")
	check_equal(mgr._draw_node.multimesh.visible_instance_count, 1, "the bolt is in the bolt batch")
	check_equal(mgr._still_node.multimesh.visible_instance_count, 1, "the rune is in the rune batch")


## A shot's body is tinted by its owner and its core takes the element's colour (`set_core`), so
## no shot is only the owner's colour (a bolt's core: test_projectile_looks.gd).
func test_a_runes_core_colour_is_in_its_custom_data() -> void:
	_a_frost_bolt_and_rune()
	mgr.update_draw()
	var buffer: PackedFloat32Array = mgr._still_node.multimesh.buffer
	var frost: Color = _frost()
	check(is_equal_approx(buffer[12], frost.r) and is_equal_approx(buffer[13], frost.g) and is_equal_approx(buffer[14], frost.b), "the core colour is in the custom data")


func test_each_seat_has_a_tint_of_its_own_apart_from_the_core() -> void:
	check(mgr.tint_of(1) != _frost(), "the owner's tint and the element's colour are separate")
	var seen: Array[Color] = []
	for player in 4:
		var tint: Color = mgr.tint_of(player)
		check(not seen.has(tint), "the wizard of seat %d has a tint of their own" % player)
		seen.append(tint)


func test_a_new_shot_in_a_reused_slot_has_a_white_core() -> void:
	_a_frost_bolt_and_rune()
	mgr.update_draw()
	mgr.clear()
	var again: int = mgr.spawn(0, Vector2(10.0, 0.0), Vector2(100.0, 0.0), 1.0)
	mgr.update_draw()
	var plain: PackedFloat32Array = mgr._draw_node.multimesh.buffer
	check(again >= 0 and is_equal_approx(plain[12], 1.0) and is_equal_approx(plain[13], 1.0) and is_equal_approx(plain[14], 1.0), "a new shot has a white core, not the last one's")


func test_bolts_and_runes_use_the_shared_art() -> void:
	_drawing()
	var art := PlaceholderTexture2D.new()
	mgr.texture = art
	check(mgr._draw_node.texture == art and mgr._still_node.texture == art, "bolts and runes use the shared art")


## Enemy shots are drawn in a batch of their own, by the shot shader in the enemy ramp, one
## layer above the players' shots (task "Enemy readability"; staffs F9b: a NO_PLAYER shot too,
## the old untinted sprite is gone).
func test_enemy_shots_are_drawn_by_the_shot_shaders() -> void:
	_drawing()
	check(mgr._enemy_node.material is ShaderMaterial, "enemy shots are drawn by the shot shaders")


func test_enemy_shots_are_drawn_above_the_players_shots() -> void:
	_drawing()
	check(mgr._enemy_node.z_index > mgr._draw_node.z_index, "enemy shots are drawn above the players' shots")


## A shot of seat 0 and two of no actor, drawn.
func _one_player_and_two_enemy_shots() -> void:
	_drawing()
	mgr.spawn(0, Vector2(10.0, 0.0), Vector2(100.0, 0.0), 1.0)
	mgr.spawn(EventsScript.NO_PLAYER, Vector2(20.0, 0.0), Vector2(0.0, 100.0), 1.0, 5.0, ManagerScript.LAYER_PLAYER)
	mgr.spawn(EventsScript.NO_PLAYER, Vector2(30.0, 0.0), Vector2(0.0, 100.0), 1.0, 5.0, ManagerScript.LAYER_PLAYER)
	mgr.update_draw()


func test_enemy_shots_are_drawn_in_a_batch_of_their_own() -> void:
	_one_player_and_two_enemy_shots()
	check(mgr.drawn == 3 and mgr.drawn_enemy == 2, "drawn counts both batches (%d, %d enemy)" % [mgr.drawn, mgr.drawn_enemy])
	check_equal(mgr._draw_node.multimesh.visible_instance_count, 1, "the player batch holds the one player shot")
	check_equal(mgr._enemy_node.multimesh.visible_instance_count, 2, "the enemy batch holds the two enemy shots")


## A batch has one shader (the owner, 2026-10-29): an enemy's rune is in a batch of its own.
func test_an_enemy_rune_is_drawn_in_the_enemy_rune_batch() -> void:
	_one_player_and_two_enemy_shots()
	mgr.spawn(EventsScript.NO_PLAYER, Vector2(40.0, 0.0), Vector2.ZERO, 1.0, 8.0, ManagerScript.LAYER_PLAYER, 0, 0, ManagerScript.MOTION_STILL)
	mgr.update_draw()
	check(mgr.drawn == 4 and mgr.drawn_enemy == 3, "the rune is drawn and counted as an enemy shot")
	check(mgr._enemy_node.multimesh.visible_instance_count == 2 and mgr._enemy_still_node.multimesh.visible_instance_count == 1, "in the enemy rune batch, not with the trails")
	check((mgr._enemy_still_node.material as ShaderMaterial).shader == ManagerScript.STILL_SHADER, "drawn by the rune shader")
	check_equal(mgr._enemy_still_node.z_index, mgr._enemy_node.z_index, "on the enemy shots' layer")


func test_clear_empties_the_enemy_batches() -> void:
	_one_player_and_two_enemy_shots()
	mgr.spawn(EventsScript.NO_PLAYER, Vector2(40.0, 0.0), Vector2.ZERO, 1.0, 8.0, ManagerScript.LAYER_PLAYER, 0, 0, ManagerScript.MOTION_STILL)
	mgr.update_draw()
	mgr.clear()
	mgr.update_draw()
	check(mgr.drawn == 0 and mgr._enemy_node.multimesh.visible_instance_count == 0 and mgr._enemy_still_node.multimesh.visible_instance_count == 0, "clear empties the enemy batches too")


func test_nothing_live_uploads_nothing() -> void:
	_drawing()
	mgr.set_cap(200)
	mgr.update_draw()
	check(mgr.drawn == 0 and mgr._draw_node.multimesh.instance_count == 0, "nothing live: nothing is uploaded")


## A batch uploads only the room its shots need (a power of two from MIN_BATCH up to the
## cap), not cap x DRAW_STRIDE floats, and draws the same shots at 1 and the cap.
func test_a_batch_uploads_only_the_room_its_shots_need() -> void:
	_drawing()
	mgr.set_cap(200)
	var stride: int = ManagerScript.DRAW_STRIDE
	for count: int in [1, 200]:
		mgr.clear()
		_row_of_bolts(count)
		mgr.update_draw()
		var multimesh: MultiMesh = mgr._draw_node.multimesh
		check(mgr.drawn == count and multimesh.visible_instance_count == count, "%d shots are drawn (%d)" % [count, mgr.drawn])
		var buffer: PackedFloat32Array = multimesh.buffer
		var room: int = multimesh.instance_count
		check(room >= count and room <= 256 and buffer.size() == room * stride, "the upload holds %d shots in room for %d" % [room, count])
		check(count > 1 or room == ManagerScript.MIN_BATCH, "one shot uploads only the smallest batch (%d)" % room)
		var seen: int = 0
		for i in count:
			# A shot's instance holds its head where it is drawn (its trail is placed by the shader).
			if is_equal_approx(buffer[i * stride + 3], float(i) + 1.0):
				seen += 1
		check(seen == count, "all %d shots are in the upload at their places (%d)" % [count, seen])
	mgr.clear()
	mgr.update_draw()
	check(mgr.drawn == 0 and mgr._draw_node.multimesh.visible_instance_count == 0, "no shots are visible after clear")


func test_a_batch_shrinks_once_the_crowd_is_gone() -> void:
	_drawing()
	mgr.set_cap(200)
	_row_of_bolts(200)
	mgr.update_draw()
	mgr.clear()
	mgr.spawn(0, Vector2(5.0, 0.0), Vector2(1.0, 0.0), 5.0)
	mgr.update_draw()
	check_equal(mgr._draw_node.multimesh.instance_count, ManagerScript.MIN_BATCH, "the batch shrinks once the crowd is gone")


## With no shots at all, a batch keeps its room, so a flicker between empty and busy never reallocates.
func test_an_empty_batch_keeps_its_room_for_the_next_volley() -> void:
	_drawing()
	mgr.set_cap(200)
	mgr.spawn(0, Vector2(5.0, 0.0), Vector2(1.0, 0.0), 5.0)
	mgr.update_draw()
	mgr.clear()
	mgr.update_draw()
	var idle: MultiMesh = mgr._draw_node.multimesh
	check_equal(idle.instance_count, ManagerScript.MIN_BATCH, "a small idle batch is kept")
	_row_of_bolts(100)
	mgr.update_draw()
	check_equal(idle.instance_count, 128, "100 shots need a batch of 128")
	mgr.clear()
	mgr.update_draw()
	check(idle.instance_count == 128 and mgr._rooms[ManagerScript.BATCH_BOLT] == 128 and idle.visible_instance_count == 0, "an empty batch keeps its room and draws nothing")
	_row_of_bolts(100)
	mgr.update_draw()
	check(idle.instance_count == 128 and idle.visible_instance_count == 100, "and the next volley fits without a resize")


## Bolts, runes and enemy shots at once: 70, 5 and 2.
func _three_kinds_at_once() -> void:
	_drawing()
	mgr.set_cap(300)
	_row_of_bolts(70)
	for i in 5:
		mgr.spawn(2, Vector2(float(i) + 1.0, 50.0), Vector2.ZERO, 5.0, 8.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	for i in 2:
		mgr.spawn(EventsScript.NO_PLAYER, Vector2(float(i) + 1.0, 90.0), Vector2(0.0, 1.0), 5.0, 5.0, ManagerScript.LAYER_PLAYER)
	mgr.update_draw()


func test_every_batch_is_sized_to_its_own_shots() -> void:
	_three_kinds_at_once()
	check_equal(mgr.drawn, 77, "every shot is drawn")
	var wanted: Array = [
		[mgr._draw_node, 70, 128],
		[mgr._still_node, 5, ManagerScript.MIN_BATCH],
		[mgr._enemy_node, 2, ManagerScript.MIN_BATCH],
	]
	for row: Array in wanted:
		var multimesh: MultiMesh = (row[0] as MultiMeshInstance2D).multimesh
		var used: int = row[1]
		check(multimesh.visible_instance_count == used, "%d shots in the batch (%d)" % [used, multimesh.visible_instance_count])
		check(multimesh.instance_count == row[2], "the batch has room for %d (%d)" % [row[2], multimesh.instance_count])
		check(multimesh.buffer.size() == multimesh.instance_count * ManagerScript.DRAW_STRIDE, "its buffer is instance_count x stride")


func test_every_batch_holds_its_shots_at_their_places() -> void:
	_three_kinds_at_once()
	var stride: int = ManagerScript.DRAW_STRIDE
	var bolt_buffer: PackedFloat32Array = mgr._draw_node.multimesh.buffer
	var rune_buffer: PackedFloat32Array = mgr._still_node.multimesh.buffer
	var hostile_buffer: PackedFloat32Array = mgr._enemy_node.multimesh.buffer
	# A shot in flight holds its head where it is drawn; the shader puts the quad round its trail.
	check(is_equal_approx(bolt_buffer[69 * stride + 3], 70.0), "the last bolt is at its place")
	check(is_equal_approx(rune_buffer[4 * stride + 3], 5.0) and is_equal_approx(rune_buffer[7], 50.0), "the last rune is at its place")
	check(is_equal_approx(hostile_buffer[stride + 3], 2.0) and is_equal_approx(hostile_buffer[stride + 7], 90.0), "the last enemy shot is at its place")


## A batch grows at once past a power of two, and shrinks only when use falls to a
## quarter of its room (the MultiMesh is rebuilt rarely).
func test_a_batchs_room_grows_at_once_and_shrinks_late() -> void:
	_drawing()
	mgr.set_cap(300)
	var min_batch: int = ManagerScript.MIN_BATCH
	# [shots drawn, expected room]: room 64 at 64, 128 at 65, 256 at 129, and never past the cap
	# (300) at 257; it shrinks once use is a quarter of the room or less.
	var steps: Array = [[1, min_batch], [64, min_batch], [65, 128], [129, 256], [257, 300], [300, 300],
		[129, 300], [76, 300], [75, 128], [33, 128], [32, 64], [1, 64]]
	for step: Array in steps:
		mgr.clear()
		_row_of_bolts(int(step[0]))
		mgr.update_draw()
		var room: int = mgr._draw_node.multimesh.instance_count
		check(room == step[1], "%d shots: room %d (%d)" % [step[0], step[1], room])
		check(mgr._draw_node.multimesh.visible_instance_count == step[0], "%d shots are drawn" % step[0])


## The tint keeps every owner's shots readable: the five colours (the four hat ramps and the
## enemy ramp) differ from each other and none is dark.
func _ramp_tints() -> Array[Color]:
	var colours: Array[Color] = []
	for ramp in ManagerScript.RAMP_COLORS.size():
		colours.append(ManagerScript.ramp_tint(ramp))
	return colours


func test_no_ramps_shot_tint_is_dark() -> void:
	var colours: Array[Color] = _ramp_tints()
	for i in colours.size():
		check(colours[i].get_luminance() >= 0.45, "ramp %d's tint is not dark (luminance %.2f)" % [i, colours[i].get_luminance()])


func test_the_ramps_shot_tints_differ_from_each_other() -> void:
	var colours: Array[Color] = _ramp_tints()
	for i in colours.size():
		for j in range(i + 1, colours.size()):
			var gap: float = absf(colours[i].r - colours[j].r) + absf(colours[i].g - colours[j].g) + absf(colours[i].b - colours[j].b)
			check(gap >= 0.15, "ramp tints %d and %d differ (gap %.2f)" % [i, j, gap])


# --- Targets and handlers ------------------------------------------------------------------


func test_registering_a_target_twice_keeps_one() -> void:
	var enemy: Node2D = _target(Vector2(30.0, 0.0))
	check_equal(mgr.get_target_count(), 1, "one target registered")
	mgr.add_target(enemy, 12.0)
	check_equal(mgr.get_target_count(), 1, "registering twice keeps one")


func test_a_freed_target_is_dropped_and_not_hit() -> void:
	var enemy: Node2D = _target(Vector2(30.0, 0.0))
	enemy.free()
	mgr.spawn(0, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0)
	mgr.step(DT)
	check_equal(mgr.get_target_count(), 0, "a freed target is dropped")
	check(hits.is_empty() and mgr.get_count() == 1, "and nothing hits it")


## Two targets, two shots at them, and a hit handler that removes the target it hit; one step.
func _hits_that_remove_their_targets() -> void:
	_target(Vector2(30.0, 0.0))
	_target(Vector2(30.0, 300.0))
	bus.projectile_hit.connect(func(_p: int, target: Node, _at: Vector2, _tag: int, _shot: int) -> void: mgr.remove_target(target as Node2D))
	mgr.spawn(0, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0)
	mgr.spawn(1, Vector2(0.0, 300.0), Vector2(1200.0, 0.0), 1.0)
	mgr.step(DT)


func test_a_removal_in_a_hit_handler_waits_for_the_next_step() -> void:
	_hits_that_remove_their_targets()
	check_equal(hits.size(), 2, "both targets were hit despite one removal mid-step")
	check_equal(mgr.get_target_count(), 2, "removal inside a step waits for the next one")


func test_targets_removed_in_a_hit_handler_are_swept_on_the_next_step() -> void:
	_hits_that_remove_their_targets()
	mgr.step(DT)
	check_equal(mgr.get_target_count(), 0, "removed targets are swept")


func test_a_spawn_in_a_hit_handler_waits_a_step() -> void:
	_target(Vector2(30.0, 0.0))
	var spawned: Array[int] = []
	bus.projectile_hit.connect(func(_p: int, _t: Node, at: Vector2, _tag: int, _shot: int) -> void: spawned.append(mgr.spawn(0, at, Vector2(600.0, 0.0), 1.0)))
	mgr.spawn(0, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0)
	mgr.step(DT)
	check(spawned.size() == 1 and mgr.get_count() == 1, "a spawn from a handler is kept")
	if spawned.size() == 1:
		var at: Vector2 = mgr.get_position_of(spawned[0])
		check(at.x > 19.0 and at.x < 21.0, "it did not move in the step that made it (%s)" % str(at))


func test_a_shot_far_outside_the_bounds_is_removed() -> void:
	mgr.set_bounds(ROOM)
	mgr.spawn(0, Vector2(600.0, 100.0), Vector2(12000.0, 0.0), 5.0)
	mgr.step(DT)
	check_equal(mgr.get_count(), 0, "a shot far outside the bounds is removed")


# --- The hit-work budget -------------------------------------------------------------------


## Three budgets' worth of shots on one target, stepped once; how many there are.
func _three_budgets_of_shots() -> int:
	mgr.set_cap(2000)
	_target(Vector2.ZERO)
	var shots: int = 3 * ManagerScript.WORK_PER_STEP / ManagerScript.HIT_WORK
	for i in shots:
		mgr.spawn(i % 4, Vector2(float(i % 5), 0.0), Vector2(1.0, 0.0), 10.0)
	mgr.step(DT)
	return shots


func test_one_step_hits_at_most_its_work_budget() -> void:
	var shots: int = _three_budgets_of_shots()
	var most: int = ManagerScript.WORK_PER_STEP / ManagerScript.HIT_WORK
	check(hits.size() > 0 and hits.size() <= most, "one step hits at most the budget (%d of %d)" % [hits.size(), most])
	check_equal(mgr.get_count(), shots - hits.size(), "the untested shots are kept, not lost")


func test_shots_the_budget_deferred_are_hit_on_later_steps() -> void:
	var shots: int = _three_budgets_of_shots()
	_run(20)
	check(mgr.get_count() == 0 and hits.size() == shots, "every shot is hit in the end (%d of %d)" % [hits.size(), shots])


## Piercing shots in a packed crowd never die, so a manager that always started at slot 0 would
## spend every budget on the same low slots. Three targets each shot hits once and stays on (owner,
## 2026-10-29: a piercing shot hits a target again only after it has left it), so its first test is
## the costly one. The tag is the shot. CROWD_SHOTS shots, stepped once; the tags tested in that step.
func _a_packed_piercing_crowd() -> Dictionary:
	mgr.set_cap(200)
	for i in 3:
		_target(Vector2(float(i), 0.0))
	for i in CROWD_SHOTS:
		mgr.spawn(i % 4, Vector2.ZERO, Vector2(0.1, 0.0), 10.0, 4.0, ManagerScript.LAYER_ENEMY, 100000, i)
	mgr.step(DT)
	var tested: Dictionary = {}
	for hit: Array in hits:
		tested[hit[3]] = true
	return tested


func test_a_spent_budget_leaves_the_last_slots_for_a_later_step() -> void:
	var tested: Dictionary = _a_packed_piercing_crowd()
	check(tested.size() > 0 and tested.size() < CROWD_SHOTS, "the first step cannot test every shot (%d of %d)" % [tested.size(), CROWD_SHOTS])
	check(not tested.has(CROWD_SHOTS - 1), "the last slot waits when the budget is spent")


func test_the_next_step_resumes_at_the_first_untested_slot() -> void:
	var tested: Dictionary = _a_packed_piercing_crowd()
	check_equal(mgr._resume, tested.size(), "the next step resumes at the first untested slot")


func test_deferred_shots_inside_a_target_hit_on_a_later_step() -> void:
	var seen: Dictionary = _a_packed_piercing_crowd()
	var steps: int = 0
	while seen.size() < CROWD_SHOTS and steps < 16:
		var before: int = hits.size()
		mgr.step(DT)
		for h in range(before, hits.size()):
			seen[hits[h][3]] = true
		steps += 1
	check(seen.size() == CROWD_SHOTS, "deferred shots inside a target hit on a later step, the high slots too (%d of %d)" % [seen.size(), CROWD_SHOTS])
	check_equal(mgr.get_count(), CROWD_SHOTS, "piercing shots stay alive")


func test_a_step_that_tests_every_shot_resets_the_resume_point() -> void:
	_a_packed_piercing_crowd()
	mgr.clear()
	mgr.spawn(0, Vector2.ZERO, Vector2(0.1, 0.0), 10.0, 4.0, ManagerScript.LAYER_ENEMY, 5, 0)
	mgr.step(DT)
	check_equal(mgr._resume, 0, "a step that tests everything resets the resume point")


# --- Walls ---------------------------------------------------------------------------------


func test_a_shot_that_reaches_a_wall_ends() -> void:
	_walled_room()
	var shot: int = mgr.spawn(0, Vector2(50.0, 100.0), Vector2(120.0, 0.0), 5.0)
	_run(60)
	check(not mgr.is_alive(shot), "a shot that reaches a wall ends")
	check_equal(mgr.wall_hits, 1, "wall_hits counts the shot that ended")


func test_a_shot_below_a_wall_keeps_flying() -> void:
	_walled_room()
	var clear_shot: int = mgr.spawn(0, Vector2(50.0, 250.0), Vector2(120.0, 0.0), 5.0)
	_run(60)
	check(mgr.is_alive(clear_shot), "a shot below the wall keeps flying")


func test_a_wall_ends_a_piercing_shot() -> void:
	_walled_room()
	_target(Vector2(200.0, 100.0))
	var piercing: int = mgr.spawn(0, Vector2(50.0, 100.0), Vector2(600.0, 0.0), 5.0, 4.0, ManagerScript.LAYER_ENEMY, 5)
	_run(30)
	check(not mgr.is_alive(piercing), "a piercing shot ends on a wall too")
	check(hits.is_empty(), "nothing behind the wall was hit (%d)" % hits.size())


func test_a_shot_faster_than_a_wall_is_thick_does_not_tunnel() -> void:
	_walled_room()
	_target(Vector2(200.0, 150.0))
	# 6,000 px/s moves 100 px in one step: a shot that would skip a thin wall.
	var fast: int = mgr.spawn(0, Vector2(60.0, 150.0), Vector2(6000.0, 0.0), 5.0)
	_run(30)
	check(not mgr.is_alive(fast), "a shot faster than the wall is thick does not tunnel")
	check(hits.is_empty(), "nothing behind the wall was hit (%d)" % hits.size())


func test_a_long_step_hits_a_target_in_front_of_a_wall() -> void:
	_walled_room()
	var in_front: Node2D = _target(Vector2(90.0, 100.0))
	# 6,000 px/s: one step from x 50 to x 150 crosses the target, then the wall.
	var shot: int = mgr.spawn(0, Vector2(50.0, 100.0), Vector2(6000.0, 0.0), 5.0)
	mgr.step(DT)
	check(hits.size() == 1 and hits[0][1] == in_front, "the target in front of the wall is hit (%d hits)" % hits.size())
	check(not mgr.is_alive(shot), "the shot ends at the wall or on the hit")


func test_a_piercing_long_step_hits_the_target_and_ends_on_the_wall_in_one_step() -> void:
	_walled_room()
	_target(Vector2(90.0, 100.0))
	var piercing: int = mgr.spawn(0, Vector2(50.0, 100.0), Vector2(6000.0, 0.0), 5.0, 4.0, ManagerScript.LAYER_ENEMY, 5)
	mgr.step(DT)
	check_equal(hits.size(), 1, "a piercing shot hits the target in front of the wall")
	check(not mgr.is_alive(piercing), "and ends on the wall in the same step")
	check(mgr.wall_hits >= 1, "wall_hits counts the end")


## A cap of 3 filled with shots in the open, then one spawned inside the wall; its slot and the first's.
func _a_spawn_in_a_wall_at_the_cap() -> Vector2i:
	_walled_room()
	mgr.set_cap(3)
	var first: int = mgr.spawn(1, Vector2(10.0, 300.0), Vector2(1.0, 0.0), 5.0)
	mgr.spawn(1, Vector2(20.0, 300.0), Vector2(1.0, 0.0), 5.0)
	mgr.spawn(1, Vector2(30.0, 300.0), Vector2(1.0, 0.0), 5.0)
	return Vector2i(first, mgr.spawn(0, Vector2(110.0, 100.0), Vector2(100.0, 0.0), 5.0))


func test_a_shot_spawned_in_a_wall_is_refused_and_evicts_nobody() -> void:
	var slots: Vector2i = _a_spawn_in_a_wall_at_the_cap()
	check_equal(slots.y, -1, "a shot spawned inside a wall is refused")
	check(mgr.get_count() == 3 and mgr.is_alive(slots.x), "at the cap it evicted nobody")


func test_a_shot_spawned_in_a_wall_counts_as_ended_on_it() -> void:
	_a_spawn_in_a_wall_at_the_cap()
	check_equal(mgr.wall_hits, 1, "it counts as ended on a wall")


## No cap on the walk (owner, 2026-11-09: "Caps are not logical"): however fast a shot is, it hits
## the wall it reaches and flies on through open air. One step of 1,800 px is 225 cells.
func test_a_1800_px_step_ends_on_the_wall_it_reaches() -> void:
	mgr.set_bounds(Rect2(0.0, 0.0, 4000.0, 360.0))
	mgr.set_walls([Rect2(1200.0, 0.0, 32.0, 360.0)] as Array[Rect2])
	var shot: int = mgr.spawn(0, Vector2(50.0, 100.0), Vector2(108000.0, 0.0), 5.0)
	mgr.step(DT)
	check(not mgr.is_alive(shot) and mgr.wall_hits == 1, "a 1,800 px step ends on the wall it reaches")


func test_a_1800_px_step_through_open_air_flies_on() -> void:
	mgr.set_bounds(Rect2(0.0, 0.0, 4000.0, 360.0))
	mgr.set_walls([Rect2(3900.0, 0.0, 32.0, 360.0)] as Array[Rect2])
	var clear: int = mgr.spawn(0, Vector2(50.0, 100.0), Vector2(108000.0, 0.0), 5.0)
	mgr.step(DT)
	check(mgr.is_alive(clear), "a 1,800 px step through open air flies on: open air is never taken for a wall")


func test_shots_from_every_direction_end_on_a_block() -> void:
	mgr.set_bounds(ROOM)
	mgr.set_walls([Rect2(304.0, 152.0, 32.0, 32.0)] as Array[Rect2])
	var centre := Vector2(320.0, 168.0)
	var slots: Array[int] = []
	for i in 16:
		var direction: Vector2 = Vector2.from_angle(float(i) * TAU / 16.0 + 0.1)
		slots.append(mgr.spawn(0, centre + direction * 90.0, -direction * 200.0, 5.0))
	_run(40)
	var alive: int = 0
	for slot in slots:
		if mgr.is_alive(slot):
			alive += 1
	check(alive == 0, "shots from all sides end on the block (%d still fly)" % alive)
	check_equal(mgr.wall_hits, 16, "each one counted")


func test_a_shot_beside_a_wall_does_not_touch_it() -> void:
	_walled_room()
	var beside: int = mgr.spawn(0, Vector2(90.0, 260.0), Vector2(0.0, -100.0), 1.0)
	mgr.step(DT)
	check(mgr.is_alive(beside), "a shot beside the wall does not touch it")


func test_a_shot_leaving_a_walls_edge_flies_on() -> void:
	_walled_room()
	var below: int = mgr.spawn(0, Vector2(120.0, 205.0), Vector2(0.0, 100.0), 1.0)
	mgr.step(DT)
	check(mgr.is_alive(below), "a shot leaving the wall's bottom edge flies on")


func test_a_shot_passes_once_the_walls_are_cleared() -> void:
	_walled_room()
	mgr.clear_walls()
	var through: int = mgr.spawn(0, Vector2(90.0, 100.0), Vector2(300.0, 0.0), 2.0)
	_run(20)
	check(mgr.is_alive(through) and mgr.get_position_of(through).x > 128.0, "with the walls cleared the shot passes")


func test_set_bounds_removes_the_walls() -> void:
	_walled_room()
	mgr.set_bounds(ROOM)
	var again: int = mgr.spawn(0, Vector2(90.0, 100.0), Vector2(300.0, 0.0), 2.0)
	_run(20)
	check(mgr.is_alive(again), "set_bounds removes the walls")


func test_clip_to_walls_leaves_a_segment_without_walls_unchanged() -> void:
	mgr.set_bounds(ROOM)
	check_equal(mgr.clip_to_walls(Vector2(10.0, 10.0), Vector2(90.0, 10.0)), Vector2(90.0, 10.0), "without walls the segment is unchanged")


func test_clip_to_walls_leaves_a_clear_segment_unchanged() -> void:
	_walled_room()
	check_equal(mgr.clip_to_walls(Vector2(60.0, 250.0), Vector2(160.0, 250.0)), Vector2(160.0, 250.0), "a clear segment is unchanged")


func test_clip_to_walls_stops_a_segment_at_the_walls_near_edge() -> void:
	_walled_room()
	var clipped: Vector2 = mgr.clip_to_walls(Vector2(60.0, 100.0), Vector2(160.0, 100.0))
	check(absf(clipped.x - 96.0) < 0.01 and clipped.y == 100.0, "the segment stops at the wall's near edge (%s)" % str(clipped))
	var diagonal: Vector2 = mgr.clip_to_walls(Vector2(80.0, 80.0), Vector2(180.0, 180.0))
	check(absf(diagonal.x - 96.0) < 0.01 and absf(diagonal.y - 96.0) < 0.01, "a diagonal segment stops at the edge (%s)" % str(diagonal))


func test_clip_to_walls_from_inside_a_wall_is_empty() -> void:
	_walled_room()
	check_equal(mgr.clip_to_walls(Vector2(110.0, 100.0), Vector2(60.0, 100.0)), Vector2(110.0, 100.0), "from inside a wall the segment is empty")


func test_a_circle_in_the_open_is_not_blocked() -> void:
	_walled_room()
	check(not mgr.circle_blocked(Vector2(60.0, 250.0), 6.0), "a circle in the open is not blocked")


func test_a_circle_whose_rim_meets_a_wall_is_blocked() -> void:
	_walled_room()
	check(mgr.circle_blocked(Vector2(90.0, 100.0), 6.0), "a circle whose rim meets a wall is blocked")


func test_a_circle_past_the_bounds_is_blocked() -> void:
	_walled_room()
	check(mgr.circle_blocked(Vector2(3.0, 250.0), 6.0), "a circle past the bounds is blocked")


## A wall body: a 32 x 64 rectangle at (96, 0) and a circle shape at (496, 200), added as walls.
func _add_a_wall_body() -> void:
	mgr.set_bounds(ROOM)
	var body := own(StaticBody2D.new()) as StaticBody2D
	body.position = Vector2(96.0, 0.0)
	var shape_node := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(32.0, 64.0)
	shape_node.shape = rectangle
	shape_node.position = Vector2(16.0, 32.0)
	body.add_child(shape_node)
	var circle_node := CollisionShape2D.new()
	circle_node.shape = CircleShape2D.new()
	circle_node.position = Vector2(400.0, 200.0)
	body.add_child(circle_node)
	root.add_child(body)
	mgr.add_wall_body(body)


func test_a_wall_bodys_rectangle_becomes_a_wall() -> void:
	_add_a_wall_body()
	var clipped: Vector2 = mgr.clip_to_walls(Vector2(60.0, 30.0), Vector2(200.0, 30.0))
	check(absf(clipped.x - 96.0) < 0.01, "the body's rectangle (96..128, 0..64) is a wall (%s)" % str(clipped))
	check_equal(mgr.clip_to_walls(Vector2(60.0, 100.0), Vector2(200.0, 100.0)).x, 200.0, "below the rectangle is open")


func test_a_wall_bodys_circle_shape_is_ignored() -> void:
	_add_a_wall_body()
	check_equal(mgr.clip_to_walls(Vector2(300.0, 200.0), Vector2(500.0, 200.0)).x, 500.0, "a circle shape is ignored")


## Regression (#5): the hit circle sat at the node's origin (the feet), so a shot flying through
## the drawn body above it passed without hitting. A target at (50, 0) whose circle (radius 8) is
## 14 px up.
func _a_target_with_its_circle_up() -> void:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.global_position = Vector2(50.0, 0.0)
	mgr.add_target(node, 8.0, ManagerScript.LAYER_ENEMY, EventsScript.NO_PLAYER, Vector2(0.0, -14.0))


func test_a_shot_through_the_body_hits_a_target_whose_circle_is_offset() -> void:
	_a_target_with_its_circle_up()
	mgr.spawn(0, Vector2(0.0, -14.0), Vector2(600.0, 0.0), 1.0, 4.0)
	mgr.step(0.2)
	check_equal(hits.size(), 1, "a shot through the body hits a target whose circle is offset up")


func test_a_shot_along_the_feet_misses_a_target_whose_circle_is_offset() -> void:
	_a_target_with_its_circle_up()
	# Along the feet (y = 0) is 14 px from the circle's centre, beyond 8 + 4.
	mgr.spawn(0, Vector2(0.0, 0.0), Vector2(600.0, 0.0), 1.0, 4.0)
	mgr.step(0.2)
	check(hits.is_empty(), "a shot along the feet misses the offset circle")


# --- Expiry --------------------------------------------------------------------------------


func test_no_expiry_while_a_shot_lives() -> void:
	mgr.spawn(1, Vector2.ZERO, Vector2(60.0, 0.0), 0.5, 4.0, ManagerScript.LAYER_ENEMY, 0, 77)
	mgr.step(0.25)
	check(expired.is_empty(), "no expiry while the shot lives")


func test_an_expiry_names_the_caster_tag_and_place() -> void:
	mgr.spawn(1, Vector2.ZERO, Vector2(60.0, 0.0), 0.5, 4.0, ManagerScript.LAYER_ENEMY, 0, 77)
	mgr.step(0.25)
	mgr.step(0.25)
	check_equal(expired.size(), 1, "one expiry when the life runs out")
	if expired.size() == 1:
		check(expired[0][0] == 1 and expired[0][2] == 77, "it names the player and gives the tag back")
		check((expired[0][1] as Vector2).is_equal_approx(Vector2(15.0, 0.0)), "it gives the place the shot reached")


func test_an_ended_shot_expires_only_once() -> void:
	mgr.spawn(1, Vector2.ZERO, Vector2(60.0, 0.0), 0.5, 4.0, ManagerScript.LAYER_ENEMY, 0, 77)
	mgr.step(0.25)
	mgr.step(0.25)
	mgr.step(0.25)
	check_equal(expired.size(), 1, "an ended shot expires only once")


func test_a_wall_end_sends_one_expiry_at_the_wall_with_the_tag() -> void:
	_walled_room()
	mgr.spawn(0, Vector2(50.0, 100.0), Vector2(120.0, 0.0), 5.0, 4.0, ManagerScript.LAYER_ENEMY, 3, 5)
	_run(60)
	check_equal(expired.size(), 1, "a wall end sends one expiry, even for a piercing shot")
	if expired.size() == 1:
		check(absf((expired[0][1] as Vector2).x - 96.0) < 0.5 and expired[0][2] == 5, "at the wall, with the tag")


func test_a_shot_that_ends_on_a_hit_does_not_expire() -> void:
	_target(Vector2(30.0, 0.0))
	mgr.spawn(0, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0)
	mgr.step(DT)
	check(hits.size() == 1 and expired.is_empty(), "a shot that ends on a hit is not expired")


func test_a_shot_dropped_by_the_cap_does_not_expire() -> void:
	mgr.set_cap(2)
	for _i in 3:
		mgr.spawn(0, Vector2(0.0, 100.0), Vector2(1.0, 0.0), 5.0)
	check(mgr.dropped == 1 and expired.is_empty(), "a shot dropped by the cap is not expired")


func test_a_shot_that_leaves_the_bounds_does_not_expire() -> void:
	mgr.spawn(0, Vector2(1000.0, 0.0), Vector2(5000.0, 0.0), 5.0)
	mgr.step(0.1)
	check(mgr.get_count() == 0 and expired.is_empty(), "a shot that leaves the bounds is not expired")


func test_a_shot_spawned_by_an_expiry_handler_lives() -> void:
	bus.projectile_expired.connect(func(player: int, position: Vector2, _tag: int, _shot: int) -> void:
		if mgr.get_count() == 0:
			mgr.spawn(player, position, Vector2(10.0, 0.0), 1.0))
	mgr.spawn(0, Vector2.ZERO, Vector2(10.0, 0.0), 0.1)
	mgr.step(0.2)
	check_equal(mgr.get_count(), 1, "a shot spawned by an expiry handler lives")
	mgr.step(DT)
	check_equal(mgr.get_count(), 1, "and does not expire in the step after")


# --- Still shots (runes) -------------------------------------------------------------------


## A rune at (100, 50) given a velocity it must ignore, tag 9, 30 steps on; its slot.
func _a_waiting_rune() -> int:
	var slot: int = mgr.spawn(0, Vector2(100.0, 50.0), Vector2(300.0, 300.0), 2.0, 12.0, ManagerScript.LAYER_ENEMY, 0, 9, ManagerScript.MOTION_STILL)
	check(slot >= 0, "a still shot spawns")
	_run(30)
	return slot


func test_a_still_shot_stays_where_it_was_put() -> void:
	var slot: int = _a_waiting_rune()
	check_equal(mgr.get_position_of(slot), Vector2(100.0, 50.0), "a still shot stays where it was put, whatever velocity it was given")
	check(hits.is_empty(), "nothing to hit yet")


## A target that walks into the waiting rune; it and the rune's slot.
func _a_target_walks_into_a_rune() -> Array:
	var slot: int = _a_waiting_rune()
	var enemy: Node2D = _target(Vector2(300.0, 50.0))
	enemy.global_position = Vector2(110.0, 50.0)
	mgr.step(DT)
	return [enemy, slot]


func test_a_target_walking_into_a_still_shot_is_hit_with_the_tag() -> void:
	var enemy: Node2D = _a_target_walks_into_a_rune()[0]
	check(hits.size() == 1 and hits[0][1] == enemy and hits[0][3] == 9, "a target walking into it is hit, with the tag")


func test_a_still_shot_ends_on_its_hit() -> void:
	var slot: int = _a_target_walks_into_a_rune()[1]
	check(not mgr.is_alive(slot), "the rune ends on the hit")


func test_a_piercing_rune_hits_overlapping_targets_once_each() -> void:
	_target(Vector2(100.0, 50.0))
	_target(Vector2(104.0, 50.0))
	mgr.spawn(0, Vector2(100.0, 50.0), Vector2.ZERO, 0.5, 12.0, ManagerScript.LAYER_ENEMY, 3, 0, ManagerScript.MOTION_STILL)
	mgr.step(DT)
	check(hits.size() == 2 and hits[0][1] != hits[1][1], "a piercing rune hits two overlapping targets, each once")
	mgr.step(DT)
	check_equal(hits.size(), 2, "it does not hit the same ones again while they stay")


func test_an_unspent_rune_expires_at_the_end_of_its_life() -> void:
	mgr.spawn(0, Vector2(100.0, 50.0), Vector2.ZERO, 0.5, 12.0, ManagerScript.LAYER_ENEMY, 3, 0, ManagerScript.MOTION_STILL)
	_run(42)
	check(expired.size() == 1 and mgr.get_count() == 0, "an unspent rune expires at the end of its life")


func test_an_unknown_motion_is_refused() -> void:
	check_equal(mgr.spawn(0, Vector2.ZERO, Vector2.ZERO, 1.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 0, 7), -1, "an unknown motion is refused")


func test_a_rune_cannot_be_placed_in_a_wall() -> void:
	_walled_room()
	check_equal(mgr.spawn(0, Vector2(100.0, 100.0), Vector2.ZERO, 1.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL), -1, "a rune cannot be placed in a wall")


func test_a_rune_beside_a_wall_stays() -> void:
	_walled_room()
	var slot: int = mgr.spawn(0, Vector2(60.0, 100.0), Vector2.ZERO, 1.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	_run(10)
	check(mgr.is_alive(slot) and expired.is_empty(), "a rune beside a wall stays")


func test_a_rune_hit_sends_a_unit_impact_direction() -> void:
	var directions: Array[Vector2] = []
	bus.projectile_impact.connect(func(_player: int, _target: Node, _position: Vector2, direction: Vector2) -> void: directions.append(direction))
	mgr.spawn(0, Vector2(100.0, 50.0), Vector2.ZERO, 2.0, 12.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	_target(Vector2(110.0, 50.0))
	mgr.step(DT)
	check(directions.size() == 1 and absf(directions[0].length() - 1.0) < 0.001, "a rune hit sends a unit direction, not zero")


# --- Queries -------------------------------------------------------------------------------


## Round QUERY_POINT: enemies 20 px (`targets[1]`, near) and 50 px (`targets[0]`, far) to the
## right, and a player target 1 px away (`targets[2]`).
func _three_round_a_point() -> void:
	_target(Vector2(150.0, 100.0), 10.0)
	_target(Vector2(120.0, 100.0), 10.0)
	_target(Vector2(101.0, 100.0), 10.0, ManagerScript.LAYER_PLAYER)


func test_nearest_target_finds_the_nearest_on_the_layer_before_any_step() -> void:
	_three_round_a_point()
	check(mgr.nearest_target(QUERY_POINT, 100.0, ManagerScript.LAYER_ENEMY) == targets[1], "the nearest target on the layer (before any step)")


func test_nearest_target_skips_the_target_excluded() -> void:
	_three_round_a_point()
	check(mgr.nearest_target(QUERY_POINT, 100.0, ManagerScript.LAYER_ENEMY, targets[1]) == targets[0], "exclude skips the target just hit")
	check_equal(mgr.nearest_point, Vector2(150.0, 100.0), "the hit circle's centre is left in nearest_point")


func test_nearest_target_skips_a_second_target_excluded() -> void:
	_three_round_a_point()
	check(mgr.nearest_target(QUERY_POINT, 100.0, ManagerScript.LAYER_ENEMY, targets[1], targets[0]) == null, "exclude_also skips a second target")
	check(not mgr.nearest_point.is_finite(), "and nearest_point is INF when nothing was found")


func test_nearest_target_respects_the_layer_mask() -> void:
	_three_round_a_point()
	check(mgr.nearest_target(QUERY_POINT, 100.0, ManagerScript.LAYER_PLAYER) == targets[2], "layers are respected")
	check(mgr.nearest_target(QUERY_POINT, 100.0, ManagerScript.LAYER_ENEMY | ManagerScript.LAYER_PLAYER) == targets[2], "a mask of both layers finds the closest of either")
	check(mgr.nearest_target(QUERY_POINT, 100.0, 0) == null, "an empty mask finds nothing")


func test_nearest_target_reaches_to_the_targets_edge() -> void:
	_three_round_a_point()
	check(mgr.nearest_target(QUERY_POINT, 5.0, ManagerScript.LAYER_ENEMY) == null, "nothing within a small radius")
	check(mgr.nearest_target(QUERY_POINT, 9.0, ManagerScript.LAYER_ENEMY) == null, "the radius counts to the target's edge: 20 away, 9 + 10 = 19")
	check(mgr.nearest_target(QUERY_POINT, 10.0, ManagerScript.LAYER_ENEMY) == targets[1], "and 10 + 10 = 20 reaches it")


func test_nearest_target_follows_moved_targets_after_a_step() -> void:
	_three_round_a_point()
	targets[1].global_position = Vector2(400.0, 100.0)
	mgr.step(DT)
	check(mgr.nearest_target(QUERY_POINT, 100.0, ManagerScript.LAYER_ENEMY) == targets[0], "after a step it follows moved targets")


func test_nearest_target_does_not_return_a_freed_target() -> void:
	_three_round_a_point()
	targets[1].global_position = Vector2(400.0, 100.0)
	mgr.step(DT)
	targets[0].free()
	mgr.step(DT)
	check(mgr.nearest_target(QUERY_POINT, 400.0, ManagerScript.LAYER_ENEMY) == targets[1], "a freed target is not returned")


func test_nearest_target_with_no_targets_finds_nothing() -> void:
	check(mgr.nearest_target(Vector2.ZERO, 500.0, ManagerScript.LAYER_ENEMY) == null, "no targets, no result")


func test_a_removed_target_is_not_found() -> void:
	var enemy: Node2D = _target(Vector2(10.0, 10.0))
	check(mgr.nearest_target(Vector2.ZERO, 50.0, ManagerScript.LAYER_ENEMY) == enemy, "found")
	mgr.remove_target(enemy)
	mgr.step(DT)
	check(mgr.nearest_target(Vector2.ZERO, 50.0, ManagerScript.LAYER_ENEMY) == null, "a removed target is not found")


func test_a_target_freed_since_the_last_step_is_not_found_or_listed() -> void:
	var doomed: Node2D = _target(Vector2(20.0, 0.0))
	mgr.step(DT)
	doomed.free()
	var out: Array[Node2D] = []
	check(mgr.nearest_target(Vector2.ZERO, 50.0, ManagerScript.LAYER_ENEMY) == null, "a target freed since the last step is not returned")
	check_equal(mgr.targets_in(Vector2.ZERO, 50.0, ManagerScript.LAYER_ENEMY, out), 0, "nor listed")


func test_targets_are_found_after_set_bounds_before_the_next_step() -> void:
	var enemy: Node2D = _target(Vector2(50.0, 50.0))
	mgr.step(DT)
	mgr.set_bounds(Rect2(0.0, 0.0, 800.0, 600.0))
	check(mgr.nearest_target(Vector2(50.0, 50.0), 20.0, ManagerScript.LAYER_ENEMY) == enemy, "targets are found after set_bounds, before the next step")
	var out: Array[Node2D] = []
	mgr.set_bounds(Rect2(0.0, 0.0, 800.0, 600.0))
	check_equal(mgr.targets_in(Vector2(50.0, 50.0), 20.0, ManagerScript.LAYER_ENEMY, out), 1, "and listed")


func test_queries_ignore_non_finite_input() -> void:
	_target(Vector2(50.0, 50.0))
	var out: Array[Node2D] = []
	check(mgr.nearest_target(Vector2(NAN, 0.0), 20.0, ManagerScript.LAYER_ENEMY) == null, "NaN point finds nothing")
	check(mgr.nearest_target(Vector2(50.0, 50.0), INF, ManagerScript.LAYER_ENEMY) == null, "infinite radius finds nothing")
	check_equal(mgr.targets_in(Vector2(INF, 0.0), 20.0, ManagerScript.LAYER_ENEMY, out), 0, "infinite point lists nothing")
	check_equal(mgr.targets_in(Vector2(50.0, 50.0), NAN, ManagerScript.LAYER_ENEMY, out), 0, "NaN radius lists nothing")


func test_a_query_inside_a_hit_handler_finds_the_other_target() -> void:
	_target(Vector2(30.0, 0.0))
	var second: Node2D = _target(Vector2(60.0, 0.0))
	var found: Array[Node2D] = []
	bus.projectile_hit.connect(func(_player: int, target: Node, position: Vector2, _tag: int, _shot: int) -> void:
		found.append(mgr.nearest_target(position, 80.0, ManagerScript.LAYER_ENEMY, target as Node2D)))
	mgr.spawn(0, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0)
	mgr.step(DT)
	check(found.size() == 1 and found[0] == second, "a chain query from a hit handler finds the other target")


## Enemies at (100, 100), (130, 100) and (300, 100) (`targets[0..2]`), a player target at (105, 100)
## (`targets[3]`).
func _four_on_a_line() -> void:
	_target(Vector2(100.0, 100.0))
	_target(Vector2(130.0, 100.0))
	_target(Vector2(300.0, 100.0))
	_target(Vector2(105.0, 100.0), 10.0, ManagerScript.LAYER_PLAYER)


func test_targets_in_lists_the_targets_near_the_point_on_the_layer() -> void:
	_four_on_a_line()
	var out: Array[Node2D] = []
	var n: int = mgr.targets_in(Vector2(110.0, 100.0), 30.0, ManagerScript.LAYER_ENEMY, out)
	check(n == 2 and out.size() == 2 and out.has(targets[0]) and out.has(targets[1]) and not out.has(targets[2]) and not out.has(targets[3]), "the enemies near the point, not far ones or other layers (%d)" % n)


func test_targets_in_clears_the_array_first() -> void:
	_four_on_a_line()
	var out: Array[Node2D] = []
	mgr.targets_in(Vector2(110.0, 100.0), 30.0, ManagerScript.LAYER_ENEMY, out)
	var n: int = mgr.targets_in(Vector2(110.0, 100.0), 30.0, ManagerScript.LAYER_ENEMY | ManagerScript.LAYER_PLAYER, out)
	check(n == 3 and out.size() == 3 and out.has(targets[3]), "a mask of both layers adds the player target; the array was cleared first")
	n = mgr.targets_in(Vector2(900.0, 900.0), 30.0, ManagerScript.LAYER_ENEMY, out)
	check(n == 0 and out.is_empty(), "no result empties the array")


func test_targets_in_far_outside_the_bounds_is_safe() -> void:
	_four_on_a_line()
	var out: Array[Node2D] = []
	check_equal(mgr.targets_in(Vector2(-5000.0, -5000.0), 20.0, ManagerScript.LAYER_ENEMY, out), 0, "a point far outside the bounds is safe")


func test_random_queries_agree_with_a_brute_force_search() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var radii: Array[float] = []
	for i in 300:
		var radius: float = rng.randf_range(4.0, 20.0)
		radii.append(radius)
		_target(Vector2(rng.randf_range(-900.0, 900.0), rng.randf_range(-900.0, 900.0)), radius)
	mgr.step(DT)
	var out: Array[Node2D] = []
	var wrong: int = 0
	for _q in 200:
		var point := Vector2(rng.randf_range(-1000.0, 1000.0), rng.randf_range(-1000.0, 1000.0))
		var reach: float = rng.randf_range(1.0, 150.0)
		var expected: Array[Node2D] = []
		var best: Node2D = null
		var best_d: float = INF
		for i in targets.size():
			var d: float = targets[i].global_position.distance_to(point)
			if d <= reach + radii[i]:
				expected.append(targets[i])
				if d < best_d:
					best_d = d
					best = targets[i]
		mgr.targets_in(point, reach, ManagerScript.LAYER_ENEMY, out)
		if out.size() != expected.size():
			wrong += 1
		else:
			for node in expected:
				if not out.has(node):
					wrong += 1
					break
		if mgr.nearest_target(point, reach, ManagerScript.LAYER_ENEMY) != best:
			wrong += 1
	check(wrong == 0, "200 random queries agree with a brute-force search (%d differ)" % wrong)
