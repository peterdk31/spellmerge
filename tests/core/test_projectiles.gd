extends SceneTree
## Tests for core/projectiles: movement, hits and the event, layers, piercing,
## the global cap, slot reuse, 1,000 projectiles checked against a brute-force
## search, and the batched draw. The manager is stepped by hand.
##
## godot --headless --path . --script res://tests/core/test_projectiles.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const DT: float = 1.0 / 60.0

var _failures: Array[String] = []
var _bus: Node
var _mgr: Node2D
var _targets: Array[Node2D] = []
## Every projectile_hit as [player, target, position, tag].
var _hits: Array = []
## Every projectile_expired as [player, position, tag].
var _expired: Array = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	_test_moves_and_expires()
	_test_hit_sends_the_event_and_ends_the_projectile()
	_test_hits_report_their_own_player()
	_test_layers()
	_test_miss()
	_test_fast_shot_does_not_tunnel()
	_test_pierce()
	_test_large_target_and_very_fast_shot()
	_test_hits_come_in_travel_order()
	_test_pierce_in_a_crowd_hits_each_once()
	_test_fast_pierce_hits_everything_on_the_path()
	_test_tag_comes_back_with_the_hit()
	_test_cap_drop_order_after_other_deaths()
	_test_default_cap_follows_the_platform()
	_test_bad_arguments()
	_test_cap_drops_the_oldest_of_the_richest()
	_test_cap_keeps_every_player_alive()
	_test_cap_never_exceeded_and_nothing_grows()
	_test_slots_are_reused()
	_test_one_thousand_match_brute_force()
	_test_one_thousand_run_and_draw()
	_test_enemy_shots_have_their_own_batch()
	_test_shot_core_colour_and_batches()
	_test_batches_upload_only_the_used_slice()
	_test_every_batch_is_sized_to_its_own_shots()
	_test_batch_room_grows_and_shrinks_with_hysteresis()
	_test_shot_colours_differ_and_stay_bright()
	_test_freed_target_is_dropped()
	_test_target_removed_by_a_hit_handler()
	_test_spawn_in_a_hit_handler_waits_a_step()
	_test_out_of_bounds_removed()
	_test_hit_work_per_step_is_bounded()
	_test_spent_budget_resumes_at_the_first_untested_shot()
	_test_shot_ends_on_a_wall()
	_test_wall_stops_a_piercing_shot_and_a_fast_shot()
	_test_target_in_front_of_a_wall_is_hit_by_a_long_step()
	_test_shot_born_in_a_wall_takes_no_slot()
	_test_wall_walk_is_capped()
	_test_wall_hits_from_every_direction()
	_test_wall_edges_and_clearing()
	_test_clip_to_walls()
	_test_wall_body_rectangles_become_walls()
	_test_target_offset_moves_the_hit_circle()
	_test_expiry_event_on_end_of_life()
	_test_expiry_event_on_a_wall()
	_test_no_expiry_on_a_hit_a_cap_drop_or_leaving()
	_test_expiry_handler_may_spawn()
	_test_still_shot_waits_for_a_target()
	_test_still_shot_pierces_and_expires()
	_test_still_shot_beside_and_in_a_wall()
	_test_nearest_target()
	_test_nearest_target_with_no_targets_and_after_removal()
	_test_set_bounds_with_targets_present()
	_test_queries_ignore_non_finite_input()
	_test_still_shot_impact_has_a_direction()
	_test_queries_inside_a_hit_handler()
	_test_targets_in()
	_test_queries_match_brute_force()
	_teardown()
	if _failures.is_empty():
		print("TEST OK: core/projectiles")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _setup() -> void:
	_teardown()
	_bus = EventsScript.new()
	_mgr = ManagerScript.new()
	_mgr.events = _bus
	_hits.clear()
	_expired.clear()
	_bus.projectile_expired.connect(func(player: int, position: Vector2, tag: int) -> void: _expired.append([player, position, tag]))
	_bus.projectile_hit.connect(func(player: int, target: Node, position: Vector2, tag: int) -> void: _hits.append([player, target, position, tag]))


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


## A target in the tree at `position`.
func _target(position: Vector2, radius: float = 10.0, layer: int = ManagerScript.LAYER_ENEMY) -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	node.global_position = position
	_targets.append(node)
	_mgr.add_target(node, radius, layer)
	return node


func _test_moves_and_expires() -> void:
	_setup()
	var slot: int = _mgr.spawn(0, Vector2.ZERO, Vector2(60.0, 0.0), 0.5)
	_check(slot >= 0 and _mgr.get_count() == 1, "spawn starts one projectile")
	_mgr.step(0.25)
	_check(_mgr.get_position_of(slot).is_equal_approx(Vector2(15.0, 0.0)), "it moves velocity * delta")
	_mgr.step(0.25)
	_check(_mgr.get_count() == 0 and not _mgr.is_alive(slot), "it ends when its lifetime is over")
	_check(_mgr.get_position_of(slot) == Vector2.INF, "a dead slot has no position")


func _test_hit_sends_the_event_and_ends_the_projectile() -> void:
	_setup()
	var enemy: Node2D = _target(Vector2(30.0, 0.0))
	_mgr.spawn(2, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0)
	_mgr.step(DT)
	_check(_hits.size() == 1, "one hit event")
	if _hits.size() == 1:
		_check(_hits[0][0] == 2 and _hits[0][1] == enemy, "the event names the player and the target")
	_check(_mgr.get_count() == 0, "the projectile ends on a hit")
	_mgr.step(DT)
	_check(_hits.size() == 1, "no second event")


func _test_hits_report_their_own_player() -> void:
	_setup()
	var a: Node2D = _target(Vector2(30.0, 0.0))
	var b: Node2D = _target(Vector2(30.0, 400.0))
	_mgr.spawn(0, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0)
	_mgr.spawn(3, Vector2(0.0, 400.0), Vector2(1200.0, 0.0), 1.0)
	_mgr.step(DT)
	_check(_hits.size() == 2, "two hits at once")
	for hit in _hits:
		if hit[1] == a:
			_check(hit[0] == 0, "player 0's shot hit the first target")
		elif hit[1] == b:
			_check(hit[0] == 3, "player 3's shot hit the second target")
		else:
			_check(false, "a hit named an unknown target")


func _test_layers() -> void:
	_setup()
	_target(Vector2(30.0, 0.0), 10.0, ManagerScript.LAYER_PLAYER)
	_mgr.spawn(0, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0, 4.0, ManagerScript.LAYER_ENEMY)
	_mgr.step(DT)
	_check(_hits.is_empty() and _mgr.get_count() == 1, "a shot at enemies passes a player target")
	_setup()
	_target(Vector2(30.0, 0.0), 10.0, ManagerScript.LAYER_PLAYER)
	_mgr.spawn(EventsScript.NO_PLAYER, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0, 4.0, ManagerScript.LAYER_PLAYER)
	_mgr.step(DT)
	_check(_hits.size() == 1 and _hits[0][0] == EventsScript.NO_PLAYER, "an enemy shot hits a player target, with NO_PLAYER")
	_check(_mgr.get_count_for(EventsScript.NO_PLAYER) == 0, "the enemy shot ended")


func _test_miss() -> void:
	_setup()
	_target(Vector2(30.0, 40.0), 10.0)
	_mgr.spawn(0, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0, 4.0)
	_mgr.step(DT)
	_check(_hits.is_empty() and _mgr.get_count() == 1, "a shot that passes 40 px away misses a 10 px target")


func _test_fast_shot_does_not_tunnel() -> void:
	_setup()
	# 3000 px/s is 50 px per step: it starts left of the target and ends right of it.
	_target(Vector2(25.0, 0.0), 6.0)
	_mgr.spawn(0, Vector2(-5.0, 0.0), Vector2(3000.0, 0.0), 1.0, 2.0)
	_mgr.step(DT)
	_check(_hits.size() == 1, "a fast shot hits a target it passed over within one step")


func _test_pierce() -> void:
	_setup()
	var first: Node2D = _target(Vector2(20.0, 0.0))
	var second: Node2D = _target(Vector2(60.0, 0.0))
	var slot: int = _mgr.spawn(1, Vector2.ZERO, Vector2(600.0, 0.0), 1.0, 4.0, ManagerScript.LAYER_ENEMY, 1)
	for i in 12:
		_mgr.step(DT)
	_check(_hits.size() == 2, "a pierce-1 shot hits two targets, once each (%d)" % _hits.size())
	if _hits.size() == 2:
		_check(_hits[0][1] == first and _hits[1][1] == second, "in the order it reached them")
	_check(not _mgr.is_alive(slot), "and ends on the second")


func _test_large_target_and_very_fast_shot() -> void:
	# A radius-80 target whose centre is 3 cells from the shot's end point.
	_setup()
	var boss: Node2D = _target(Vector2(200.0, 0.0), 80.0)
	_mgr.spawn(0, Vector2(100.0, 0.0), Vector2(1200.0, 0.0), 1.0, 4.0)
	_mgr.step(DT)
	_check(_hits.size() == 1 and _hits[0][1] == boss, "a shot touching the edge of a radius-80 target hits it")
	# 5000 px/s is 83 px per step.
	_setup()
	_target(Vector2(200.0, 0.0), 80.0)
	_mgr.spawn(0, Vector2(40.0, 0.0), Vector2(5000.0, 0.0), 1.0, 4.0)
	_mgr.step(DT)
	_check(_hits.size() == 1, "a 5,000 px/s shot hits a big target")
	_setup()
	_target(Vector2(500.0, 0.0), 6.0)
	_mgr.spawn(0, Vector2(400.0, 0.0), Vector2(30000.0, 0.0), 1.0, 2.0)
	_mgr.step(DT)
	_check(_hits.size() == 1, "a 30,000 px/s shot (500 px per step) hits a small target on the way")
	_setup()
	_target(Vector2(500.0, 100.0), 6.0)
	_mgr.spawn(0, Vector2(400.0, 0.0), Vector2(30000.0, 0.0), 1.0, 2.0)
	_mgr.step(DT)
	_check(_hits.is_empty(), "and still misses one 100 px off the path")


func _test_hits_come_in_travel_order() -> void:
	_setup()
	# The far target is registered last, so it comes first in the grid chain.
	var near: Node2D = _target(Vector2(20.0, 0.0), 10.0)
	_target(Vector2(60.0, 0.0), 10.0)
	_mgr.spawn(0, Vector2.ZERO, Vector2(4800.0, 0.0), 1.0, 2.0)
	_mgr.step(DT)
	_check(_hits.size() == 1 and _hits[0][1] == near, "the nearest target along the path is hit first")
	if not _hits.is_empty():
		_check(_hits[0][2].is_equal_approx(Vector2(20.0, 0.0)), "the hit position is the closest point on the path (%s)" % str(_hits[0][2]))


func _test_pierce_in_a_crowd_hits_each_once() -> void:
	# Two overlapping targets and pierce 2: exactly one event per target.
	_setup()
	var a: Node2D = _target(Vector2(30.0, 0.0), 14.0)
	var b: Node2D = _target(Vector2(38.0, 4.0), 14.0)
	var slot: int = _mgr.spawn(0, Vector2.ZERO, Vector2(300.0, 0.0), 1.0, 4.0, ManagerScript.LAYER_ENEMY, 2)
	for i in 30:
		_mgr.step(DT)
	_check(_hits.size() == 2, "two overlapping targets give two events (%d)" % _hits.size())
	var seen: Array = []
	for hit in _hits:
		_check(not seen.has(hit[1]), "no target is hit twice")
		seen.append(hit[1])
	_check(seen.has(a) and seen.has(b), "each target was hit")
	_check(_mgr.is_alive(slot), "the shot keeps one pierce")


func _test_fast_pierce_hits_everything_on_the_path() -> void:
	# One step of 480 px passes three targets: all three are hit, in order.
	_setup()
	var a: Node2D = _target(Vector2(100.0, 0.0), 10.0)
	var b: Node2D = _target(Vector2(200.0, 0.0), 10.0)
	var c: Node2D = _target(Vector2(300.0, 0.0), 10.0)
	var slot: int = _mgr.spawn(0, Vector2.ZERO, Vector2(28800.0, 0.0), 1.0, 2.0, ManagerScript.LAYER_ENEMY, 3)
	_mgr.step(DT)
	_check(_hits.size() == 3, "a fast piercing shot hits every target on its path in one step (%d)" % _hits.size())
	if _hits.size() == 3:
		_check(_hits[0][1] == a and _hits[1][1] == b and _hits[2][1] == c, "in the order along the path")
	_check(_mgr.is_alive(slot), "and keeps its last pierce")
	# Without pierce the first hit ends it: one event.
	_setup()
	_target(Vector2(100.0, 0.0), 10.0)
	_target(Vector2(200.0, 0.0), 10.0)
	_mgr.spawn(0, Vector2.ZERO, Vector2(28800.0, 0.0), 1.0, 2.0)
	_mgr.step(DT)
	_check(_hits.size() == 1, "a shot without pierce stops at the first target (%d)" % _hits.size())


func _test_tag_comes_back_with_the_hit() -> void:
	_setup()
	_target(Vector2(20.0, 0.0))
	_target(Vector2(20.0, 100.0))
	_mgr.spawn(0, Vector2.ZERO, Vector2(600.0, 0.0), 1.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 41)
	_mgr.spawn(1, Vector2(0.0, 100.0), Vector2(600.0, 0.0), 1.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 42)
	_mgr.spawn(2, Vector2(0.0, 500.0), Vector2(600.0, 0.0), 1.0)
	for i in 4:
		_mgr.step(DT)
	_check(_hits.size() == 2, "both tagged shots hit (%d)" % _hits.size())
	var tags: Dictionary = {}
	for hit in _hits:
		tags[hit[0]] = hit[3]
	_check(tags.get(0, -1) == 41 and tags.get(1, -1) == 42, "each hit carries the tag of its own projectile (%s)" % str(tags))
	# The default tag is 0, and a reused slot does not keep an old tag.
	_setup()
	_target(Vector2(20.0, 0.0))
	_mgr.spawn(0, Vector2.ZERO, Vector2(600.0, 0.0), 1.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 99)
	_mgr.step(DT * 4.0)
	_mgr.spawn(0, Vector2.ZERO, Vector2(600.0, 0.0), 1.0)
	_hits.clear()
	_mgr.step(DT * 4.0)
	_check(_hits.size() == 1 and _hits[0][3] == 0, "an untagged shot in a reused slot sends tag 0")


func _test_cap_drop_order_after_other_deaths() -> void:
	_setup()
	_mgr.set_cap(6)
	var short_lived: int = _mgr.spawn(0, Vector2(0.0, 0.0), Vector2.ZERO, 0.01)
	var keep_old: int = _mgr.spawn(0, Vector2(1.0, 0.0), Vector2.ZERO, 5.0)
	for i in 4:
		_mgr.spawn(0, Vector2(2.0 + i, 0.0), Vector2.ZERO, 5.0)
	_mgr.step(DT)
	_check(not _mgr.is_alive(short_lived) and _mgr.get_count() == 5, "the first shot expired")
	_mgr.spawn(0, Vector2(10.0, 0.0), Vector2.ZERO, 5.0)
	_check(_mgr.get_count() == 6, "full again")
	_mgr.spawn(0, Vector2(11.0, 0.0), Vector2.ZERO, 5.0)
	_check(keep_old >= 0 and _mgr.dropped == 1, "one shot was dropped")
	var survivors: int = 0
	for s in 6:
		if _mgr.is_alive(s) and _mgr.get_position_of(s).x == 1.0:
			survivors += 1
	_check(survivors == 0, "the oldest living shot is the one dropped")
	for i in 20:
		_mgr.spawn(i % 2, Vector2(20.0 + i, 0.0), Vector2.ZERO, 5.0)
	_check(_mgr.get_count() == 6 and _mgr.get_count_for(0) + _mgr.get_count_for(1) == 6, "the lists stay consistent under churn")


func _test_default_cap_follows_the_platform() -> void:
	_setup()
	var expected: int = ManagerScript.DEFAULT_CAP_WEB if OS.has_feature("web") else ManagerScript.DEFAULT_CAP_DESKTOP
	_check(_mgr.get_cap() == expected, "the default cap is %d on this platform" % expected)


func _test_bad_arguments() -> void:
	_setup()
	_check(_mgr.spawn(ManagerScript.CASTERS, Vector2.ZERO, Vector2.RIGHT, 1.0) == -1, "a caster past the last enemy row is refused")
	_check(_mgr.spawn(-2, Vector2.ZERO, Vector2.RIGHT, 1.0) == -1, "player -2 is refused")
	_check(_mgr.spawn(0, Vector2.ZERO, Vector2.RIGHT, 0.0) == -1, "zero lifetime is refused")
	_check(_mgr.spawn(0, Vector2(NAN, 0.0), Vector2.RIGHT, 1.0) == -1, "a NaN position is refused")
	_check(_mgr.spawn(0, Vector2.ZERO, Vector2(INF, 0.0), 1.0) == -1, "an infinite velocity is refused")
	_check(_mgr.get_count() == 0, "refused spawns leave nothing behind")
	_check(_mgr.get_count_for(ManagerScript.CASTERS) == 0, "counting an invalid caster gives 0")


func _test_cap_drops_the_oldest_of_the_richest() -> void:
	_setup()
	_mgr.set_cap(10)
	var oldest: int = _mgr.spawn(0, Vector2(1.0, 0.0), Vector2.ZERO, 5.0)
	for i in 9:
		_mgr.spawn(0, Vector2(2.0 + i, 0.0), Vector2.ZERO, 5.0)
	_check(_mgr.get_count() == 10, "the cap fills to 10")
	var slot: int = _mgr.spawn(1, Vector2(100.0, 0.0), Vector2.ZERO, 5.0)
	_check(slot >= 0, "a full cap still accepts the new shot")
	_check(_mgr.get_count() == 10, "and stays at the cap")
	_check(_mgr.dropped == 1, "one projectile was dropped")
	_check(_mgr.get_count_for(0) == 9 and _mgr.get_count_for(1) == 1, "from the player who owned the most")
	_check(slot == oldest, "the oldest one's slot was reused")
	var survivors: int = 0
	for s in 10:
		if _mgr.is_alive(s) and _mgr.get_position_of(s).x == 1.0:
			survivors += 1
	_check(survivors == 0, "the oldest shot is the one that went")


func _test_cap_keeps_every_player_alive() -> void:
	_setup()
	_mgr.set_cap(40)
	# Player 0 floods; the others fire a little. Everyone's newest shot lives.
	for i in 200:
		_mgr.spawn(0, Vector2(i, 0.0), Vector2.ZERO, 5.0)
		if i % 20 == 0:
			_mgr.spawn(1 + floori(i / 20.0) % 3, Vector2(i, 10.0), Vector2.ZERO, 5.0)
	_check(_mgr.get_count() == 40, "the cap holds under a flood")
	for player in 4:
		_check(_mgr.get_count_for(player) > 0, "player %d still has projectiles" % player)
	_check(_mgr.dropped > 0, "the flood dropped some")
	_check(_mgr.get_count_for(0) + _mgr.get_count_for(1) + _mgr.get_count_for(2) + _mgr.get_count_for(3) == 40, "the per-player counts add up")


func _test_cap_never_exceeded_and_nothing_grows() -> void:
	_setup()
	_mgr.set_cap(100)
	var size_before: int = _mgr._pos.size()
	var worst: int = 0
	for i in 2000:
		_mgr.spawn(i % 4, Vector2(i % 50, 0.0), Vector2(30.0, 0.0), 100.0)
		if i % 3 == 0:
			_mgr.step(DT)
		worst = maxi(worst, _mgr.get_count())
	_check(worst == 100, "the count reaches the cap and never passes it (%d)" % worst)
	_check(_mgr._pos.size() == size_before and _mgr._alive.size() == 100, "the arrays never grow")
	_check(_mgr.get_cap() == 100, "the cap is unchanged")


func _test_slots_are_reused() -> void:
	_setup()
	_mgr.set_cap(8)
	for round_index in 50:
		for i in 8:
			_mgr.spawn(round_index % 4, Vector2.ZERO, Vector2(10.0, 0.0), 0.1)
		_check(_mgr.get_count() == 8, "round %d fills the 8 slots" % round_index)
		for step in 7:
			_mgr.step(DT)
		_check(_mgr.get_count() == 0, "round %d: all expired" % round_index)
	_check(_mgr.dropped == 0, "reuse never needed a drop")
	_check(_mgr._pos.size() == 8, "still 8 slots")
	var slot: int = _mgr.spawn(0, Vector2.ZERO, Vector2.ZERO, 1.0)
	_check(slot >= 0 and slot < 8, "a new shot takes a free slot")


func _test_one_thousand_match_brute_force() -> void:
	_setup()
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
		_mgr.spawn(i % 4, start, velocity, 5.0, 4.0)
	_check(_mgr.get_count() == 1000, "1,000 projectiles are alive")
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
	_mgr.step(DT)
	_check(expected_hits > 0, "the layout has hits to find (%d)" % expected_hits)
	_check(_hits.size() >= expected_hits and _hits.size() <= expected_hits + borderline, "the grid finds the hits a brute-force search does (%d vs %d, %d borderline)" % [_hits.size(), expected_hits, borderline])
	_check(_mgr.get_count() == 1000 - _hits.size(), "and ends exactly those projectiles")


func _test_one_thousand_run_and_draw() -> void:
	_setup()
	root.add_child(_mgr)
	for i in 1000:
		_mgr.spawn(i % 4, Vector2(-500.0 + i % 100 * 10.0, -400.0 + floorf(i / 100.0) * 80.0), Vector2(200.0, 40.0), 2.0)
	_target(Vector2(0.0, 0.0), 30.0)
	for i in 30:
		_mgr.step(DT)
	var alive: int = _mgr.get_count()
	_check(alive > 900, "most of the 1,000 are still flying (%d)" % alive)
	_mgr.update_draw()
	_check(_mgr.drawn == alive, "one batch holds every live projectile (%d of %d)" % [_mgr.drawn, alive])
	_mgr.update_draw(1.0)
	_check(_mgr.drawn == alive, "a fixed draw fraction (the clip recorder's) draws every live projectile too")
	_mgr.clear()
	_mgr.update_draw()
	_check(_mgr.drawn == 0 and _mgr.get_count() == 0, "clear empties the batch")
	_check(_mgr._draw_node.multimesh.visible_instance_count == 0, "clear empties the drawn multimesh, not just the counter")
	# Regression (issue #102): the autoload is drawn before the room, so shots need a raised z_index to show above its floor.
	_check(_mgr._draw_node.z_index >= 1, "the shots are drawn above the room's floor")
	# Regression (issue #102): without a culling box covering the area, shots away from the origin were never drawn.
	var box: AABB = _mgr._draw_node.multimesh.custom_aabb
	_check(box.has_point(Vector3(-500.0, -400.0, 0.0)) and box.has_point(Vector3(900.0, 900.0, 0.0)), "the batch's culling box covers the whole play area")
	root.remove_child(_mgr)


## A shot's body is tinted by its owner and its core takes the element's colour
## (`set_core`), so no shot is only the owner's colour; runes and orbit shots have batches
## (and art) of their own.
func _test_shot_core_colour_and_batches() -> void:
	_setup()
	root.add_child(_mgr)
	var frost := Color(0.5, 0.75, 0.94)
	var bolt: int = _mgr.spawn(1, Vector2(10.0, 0.0), Vector2(100.0, 0.0), 1.0)
	var rune: int = _mgr.spawn(2, Vector2(20.0, 0.0), Vector2.ZERO, 1.0, 8.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	_mgr.set_anchor(3, Vector2(100.0, 100.0))
	var orb: int = _mgr.spawn_orbit(3, 20.0, 0.0, 1.0, 1.0)
	_check(_mgr.set_core(bolt, frost) and _mgr.set_core(rune, frost) and _mgr.set_core(orb, frost), "set_core takes a colour for a live shot")
	_check(not _mgr.set_core(-1, frost) and not _mgr.set_core(999999, frost), "set_core refuses a slot out of range")
	_check(not _mgr.set_core(bolt, Color(NAN, 0.0, 0.0)), "set_core refuses a colour that is not finite")
	_mgr.update_draw()
	_check(_mgr.drawn == 3, "the three shots are drawn (%d)" % _mgr.drawn)
	_check(_mgr._draw_node.multimesh.visible_instance_count == 1, "the bolt is in the bolt batch")
	_check(_mgr._rune_node.multimesh.visible_instance_count == 1, "the rune is in the rune batch")
	_check(_mgr._orbit_node.multimesh.visible_instance_count == 1, "the orbit shot is in the orbit batch")
	for node: MultiMeshInstance2D in [_mgr._draw_node, _mgr._rune_node, _mgr._orbit_node]:
		var buffer: PackedFloat32Array = node.multimesh.buffer
		_check(is_equal_approx(buffer[12], frost.r) and is_equal_approx(buffer[13], frost.g) and is_equal_approx(buffer[14], frost.b), "the core colour is in the custom data")
	var body: PackedFloat32Array = _mgr._draw_node.multimesh.buffer
	# The instance colour carries the owner as data (staffs B6a); the shader colours the outline
	# and the trail by it (test_projectile_looks.gd).
	_check(roundi(body[8] * 255.0) % 4 == 1, "the body names its owner, player 2 (red is player + zoom x 4)")
	var owner_tint: Color = _mgr.tint_of(1)
	_check(owner_tint != frost, "the owner's tint and the element's colour are separate")
	var seen: Array[Color] = []
	for player in 4:
		var tint: Color = _mgr.tint_of(player)
		_check(not seen.has(tint), "player %d has a tint of their own" % player)
		seen.append(tint)
	# A reused slot starts plain again.
	_mgr.clear()
	var again: int = _mgr.spawn(0, Vector2(10.0, 0.0), Vector2(100.0, 0.0), 1.0)
	_mgr.update_draw()
	var plain: PackedFloat32Array = _mgr._draw_node.multimesh.buffer
	_check(again >= 0 and is_equal_approx(plain[12], 1.0) and is_equal_approx(plain[13], 1.0) and is_equal_approx(plain[14], 1.0), "a new shot has a white core, not the last one's")
	var art := PlaceholderTexture2D.new()
	_mgr.texture = art
	_check(_mgr._rune_node.texture == art and _mgr._orbit_node.texture == art, "rune and orbit shots use the shared art")
	root.remove_child(_mgr)


## Enemy shots are drawn in a batch of their own: other texture, untinted, one layer
## above the players' shots (task "Enemy readability": shots must not read as a spell).
func _test_enemy_shots_have_their_own_batch() -> void:
	_setup()
	root.add_child(_mgr)
	var player_art := PlaceholderTexture2D.new()
	var enemy_art := PlaceholderTexture2D.new()
	_mgr.texture = player_art
	_check(_mgr._hostile_node.texture == player_art, "without hostile art, enemy shots use the shared texture")
	_mgr.hostile_texture = enemy_art
	_check(_mgr._hostile_node.texture == enemy_art and _mgr._draw_node.texture == player_art, "enemy shots get their own texture")
	_check(_mgr._hostile_node.z_index > _mgr._draw_node.z_index, "enemy shots are drawn above the players' shots")
	_mgr.spawn(0, Vector2(10.0, 0.0), Vector2(100.0, 0.0), 1.0)
	_mgr.spawn(EventsScript.NO_PLAYER, Vector2(20.0, 0.0), Vector2(0.0, 100.0), 1.0, 5.0, ManagerScript.LAYER_PLAYER)
	_mgr.spawn(EventsScript.NO_PLAYER, Vector2(30.0, 0.0), Vector2(0.0, 100.0), 1.0, 5.0, ManagerScript.LAYER_PLAYER)
	_mgr.update_draw()
	_check(_mgr.drawn == 3 and _mgr.drawn_hostile == 2, "drawn counts both batches (%d, %d hostile)" % [_mgr.drawn, _mgr.drawn_hostile])
	_check(_mgr._draw_node.multimesh.visible_instance_count == 1, "the player batch holds the one player shot")
	_check(_mgr._hostile_node.multimesh.visible_instance_count == 2, "the enemy batch holds the two enemy shots")
	var buffer: PackedFloat32Array = _mgr._hostile_node.multimesh.buffer
	_check(buffer.size() > ManagerScript.DRAW_STRIDE and is_equal_approx(buffer[3], 20.0) and is_equal_approx(buffer[ManagerScript.DRAW_STRIDE + 3], 30.0), "the enemy batch has the enemy shots' positions")
	_check(is_equal_approx(buffer[8], 1.0) and is_equal_approx(buffer[9], 1.0) and is_equal_approx(buffer[10], 1.0), "enemy shots are not tinted")
	_mgr.clear()
	_mgr.update_draw()
	_check(_mgr.drawn == 0 and _mgr._hostile_node.multimesh.visible_instance_count == 0, "clear empties the enemy batch too")
	root.remove_child(_mgr)


## A batch uploads only the room its shots need (a power of two from MIN_BATCH up to the
## cap), not cap x DRAW_STRIDE floats, and draws the same shots at 0, 1 and the cap.
func _test_batches_upload_only_the_used_slice() -> void:
	_setup()
	root.add_child(_mgr)
	_mgr.set_cap(200)
	var stride: int = ManagerScript.DRAW_STRIDE
	_mgr.update_draw()
	_check(_mgr.drawn == 0 and _mgr._draw_node.multimesh.instance_count == 0, "nothing live: nothing is uploaded")
	for count: int in [1, 200]:
		_mgr.clear()
		for i in count:
			_mgr.spawn(0, Vector2(float(i) + 1.0, 0.0), Vector2(1.0, 0.0), 5.0)
		_mgr.update_draw()
		var multimesh: MultiMesh = _mgr._draw_node.multimesh
		_check(_mgr.drawn == count and multimesh.visible_instance_count == count, "%d shots are drawn (%d)" % [count, _mgr.drawn])
		var buffer: PackedFloat32Array = multimesh.buffer
		var room: int = multimesh.instance_count
		_check(room >= count and room <= 200 and buffer.size() == room * stride, "the upload holds %d shots in room for %d" % [room, count])
		_check(count > 1 or room == ManagerScript.MIN_BATCH, "one shot uploads only the smallest batch (%d)" % room)
		var seen: int = 0
		var back: float = ManagerScript.look_back(5.0)
		for i in count:
			if is_equal_approx(buffer[i * stride + 3], float(i) + 1.0 - back):
				seen += 1
		_check(seen == count, "all %d shots are in the upload at their places (%d)" % [count, seen])
	_mgr.clear()
	_mgr.update_draw()
	_check(_mgr.drawn == 0 and _mgr._draw_node.multimesh.visible_instance_count == 0, "no shots are visible after clear")
	# A few shots after a crowd shrink the batch back down.
	_mgr.spawn(0, Vector2(5.0, 0.0), Vector2(1.0, 0.0), 5.0)
	_mgr.update_draw()
	_check(_mgr._draw_node.multimesh.instance_count == ManagerScript.MIN_BATCH, "the batch shrinks once the crowd is gone")
	# With no shots at all, a batch keeps its room, so a flicker between empty and busy never reallocates.
	_mgr.clear()
	_mgr.update_draw()
	var idle: MultiMesh = _mgr._draw_node.multimesh
	_check(idle.instance_count == ManagerScript.MIN_BATCH, "a small idle batch is kept (%d)" % idle.instance_count)
	for i in 100:
		_mgr.spawn(0, Vector2(float(i) + 1.0, 0.0), Vector2(1.0, 0.0), 5.0)
	_mgr.update_draw()
	_check(idle.instance_count == 128, "100 shots need a batch of 128 (%d)" % idle.instance_count)
	_mgr.clear()
	_mgr.update_draw()
	_check(idle.instance_count == 128 and _mgr._draw_room == 128 and idle.visible_instance_count == 0, "an empty batch keeps its room and draws nothing")
	for i in 100:
		_mgr.spawn(0, Vector2(float(i) + 1.0, 0.0), Vector2(1.0, 0.0), 5.0)
	_mgr.update_draw()
	_check(idle.instance_count == 128 and idle.visible_instance_count == 100, "and the next volley fits without a resize")
	root.remove_child(_mgr)


## Bolts, runes, orbit shots and enemy shots at once: each batch has the room, the
## buffer size and the positions of its own shots, and none is dropped.
func _test_every_batch_is_sized_to_its_own_shots() -> void:
	_setup()
	root.add_child(_mgr)
	_mgr.set_cap(300)
	var stride: int = ManagerScript.DRAW_STRIDE
	_mgr.set_anchor(3, Vector2(100.0, 100.0))
	var bolts: int = 70
	var runes: int = 5
	var orbits: int = 3
	var hostile: int = 2
	for i in bolts:
		_mgr.spawn(0, Vector2(float(i) + 1.0, 0.0), Vector2(1.0, 0.0), 5.0)
	for i in runes:
		_mgr.spawn(2, Vector2(float(i) + 1.0, 50.0), Vector2.ZERO, 5.0, 8.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	var orbit_slots: Array[int] = []
	for i in orbits:
		orbit_slots.append(_mgr.spawn_orbit(3, 20.0 + float(i) * 10.0, float(i), 1.0, 1.0))
	for i in hostile:
		_mgr.spawn(EventsScript.NO_PLAYER, Vector2(float(i) + 1.0, 90.0), Vector2(0.0, 1.0), 5.0, 5.0, ManagerScript.LAYER_PLAYER)
	_mgr.update_draw()
	_check(_mgr.drawn == bolts + runes + orbits + hostile, "every shot is drawn (%d)" % _mgr.drawn)
	var wanted: Array = [
		[_mgr._draw_node, bolts, 128],
		[_mgr._rune_node, runes, ManagerScript.MIN_BATCH],
		[_mgr._orbit_node, orbits, ManagerScript.MIN_BATCH],
		[_mgr._hostile_node, hostile, ManagerScript.MIN_BATCH],
	]
	for row: Array in wanted:
		var multimesh: MultiMesh = (row[0] as MultiMeshInstance2D).multimesh
		var used: int = row[1]
		_check(multimesh.visible_instance_count == used, "%d shots in the batch (%d)" % [used, multimesh.visible_instance_count])
		_check(multimesh.instance_count == row[2], "the batch has room for %d (%d)" % [row[2], multimesh.instance_count])
		_check(multimesh.buffer.size() == multimesh.instance_count * stride, "its buffer is instance_count x stride")
	var bolt_buffer: PackedFloat32Array = _mgr._draw_node.multimesh.buffer
	var rune_buffer: PackedFloat32Array = _mgr._rune_node.multimesh.buffer
	var hostile_buffer: PackedFloat32Array = _mgr._hostile_node.multimesh.buffer
	var orbit_buffer: PackedFloat32Array = _mgr._orbit_node.multimesh.buffer
	# A bolt's or orbit shot's quad reaches ahead of it and holds its tail behind (look_back).
	_check(is_equal_approx(bolt_buffer[(bolts - 1) * stride + 3], float(bolts) - ManagerScript.look_back(5.0)), "the last bolt is at its place")
	_check(is_equal_approx(rune_buffer[(runes - 1) * stride + 3], float(runes)) and is_equal_approx(rune_buffer[7], 50.0), "the last rune is at its place")
	_check(is_equal_approx(hostile_buffer[stride + 3], 2.0) and is_equal_approx(hostile_buffer[stride + 7], 90.0), "the last enemy shot is at its place")
	var orbit_ok: bool = true
	for i in orbits:
		var slot: int = orbit_slots[i]
		var centre: Vector2 = _mgr._pos[slot] - _mgr._vel[slot].normalized() * ManagerScript.look_back(_mgr._radius[slot])
		orbit_ok = orbit_ok and is_equal_approx(orbit_buffer[i * stride + 3], centre.x)
		orbit_ok = orbit_ok and is_equal_approx(orbit_buffer[i * stride + 7], centre.y)
	_check(orbit_ok, "the orbit shots are at their places")
	root.remove_child(_mgr)


## A batch grows at once past a power of two, and shrinks only when use falls to a
## quarter of its room (the MultiMesh is rebuilt rarely).
func _test_batch_room_grows_and_shrinks_with_hysteresis() -> void:
	_setup()
	root.add_child(_mgr)
	_mgr.set_cap(300)
	var min_batch: int = ManagerScript.MIN_BATCH
	# [shots drawn, expected room]: room 64 at 64, 128 at 65, 256 at 129, the cap at 257.
	var steps: Array = [[1, min_batch], [64, min_batch], [65, 128], [129, 256], [257, 300], [300, 300],
		[76, 300], [75, 128], [33, 128], [32, 64], [1, 64]]
	for step: Array in steps:
		_mgr.clear()
		for i in int(step[0]):
			_mgr.spawn(0, Vector2(float(i) + 1.0, 0.0), Vector2(1.0, 0.0), 5.0)
		_mgr.update_draw()
		var room: int = _mgr._draw_node.multimesh.instance_count
		_check(room == step[1], "%d shots: room %d (%d)" % [step[0], step[1], room])
		_check(_mgr._draw_node.multimesh.visible_instance_count == step[0], "%d shots are drawn" % step[0])
	root.remove_child(_mgr)


## The tint keeps every owner's shots readable: the five colours (players 0-3 and
## the enemy) differ from each other and none is dark.
func _test_shot_colours_differ_and_stay_bright() -> void:
	_setup()
	var colours: Array[Color] = []
	for owner_index in [-1, 0, 1, 2, 3]:
		colours.append(_mgr._color_of(owner_index))
	for i in colours.size():
		_check(colours[i].get_luminance() >= 0.45, "shot colour %d is not dark (luminance %.2f)" % [i, colours[i].get_luminance()])
		for j in range(i + 1, colours.size()):
			var gap: float = absf(colours[i].r - colours[j].r) + absf(colours[i].g - colours[j].g) + absf(colours[i].b - colours[j].b)
			_check(gap >= 0.15, "shot colours %d and %d differ (gap %.2f)" % [i, j, gap])


func _test_freed_target_is_dropped() -> void:
	_setup()
	var enemy: Node2D = _target(Vector2(30.0, 0.0))
	_check(_mgr.get_target_count() == 1, "one target registered")
	_mgr.add_target(enemy, 12.0)
	_check(_mgr.get_target_count() == 1, "registering twice keeps one")
	enemy.free()
	_mgr.spawn(0, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0)
	_mgr.step(DT)
	_check(_mgr.get_target_count() == 0, "a freed target is dropped")
	_check(_hits.is_empty() and _mgr.get_count() == 1, "and nothing hits it")


func _test_target_removed_by_a_hit_handler() -> void:
	_setup()
	_target(Vector2(30.0, 0.0))
	_target(Vector2(30.0, 300.0))
	_bus.projectile_hit.connect(func(_p: int, target: Node, _at: Vector2, _tag: int) -> void: _mgr.remove_target(target as Node2D))
	_mgr.spawn(0, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0)
	_mgr.spawn(1, Vector2(0.0, 300.0), Vector2(1200.0, 0.0), 1.0)
	_mgr.step(DT)
	_check(_hits.size() == 2, "both targets were hit despite one removal mid-step")
	_check(_mgr.get_target_count() == 2, "removal inside a step waits for the next one")
	_mgr.step(DT)
	_check(_mgr.get_target_count() == 0, "removed targets are swept")


func _test_spawn_in_a_hit_handler_waits_a_step() -> void:
	_setup()
	_target(Vector2(30.0, 0.0))
	var spawned: Array[int] = []
	_bus.projectile_hit.connect(func(_p: int, _t: Node, at: Vector2, _tag: int) -> void: spawned.append(_mgr.spawn(0, at, Vector2(600.0, 0.0), 1.0)))
	_mgr.spawn(0, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0)
	_mgr.step(DT)
	_check(spawned.size() == 1 and _mgr.get_count() == 1, "a spawn from a handler is kept")
	var at: Vector2 = _mgr.get_position_of(spawned[0])
	_check(at.x > 19.0 and at.x < 21.0, "it did not move in the step that made it (%s)" % str(at))


func _test_out_of_bounds_removed() -> void:
	_setup()
	_mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_mgr.spawn(0, Vector2(600.0, 100.0), Vector2(12000.0, 0.0), 5.0)
	_mgr.step(DT)
	_check(_mgr.get_count() == 0, "a shot far outside the bounds is removed")


func _test_hit_work_per_step_is_bounded() -> void:
	_setup()
	_mgr.set_cap(2000)
	_target(Vector2.ZERO)
	var shots: int = 3 * ManagerScript.WORK_PER_STEP / ManagerScript.HIT_WORK
	for i in shots:
		_mgr.spawn(i % 4, Vector2(float(i % 5), 0.0), Vector2(1.0, 0.0), 10.0)
	_mgr.step(DT)
	var most: int = ManagerScript.WORK_PER_STEP / ManagerScript.HIT_WORK
	_check(_hits.size() > 0 and _hits.size() <= most, "one step hits at most the budget (%d of %d)" % [_hits.size(), most])
	_check(_mgr.get_count() == shots - _hits.size(), "the untested shots are kept, not lost")
	# Deferred shots are tested first on the next steps: all are hit in the end.
	for i in 20:
		_mgr.step(DT)
	_check(_mgr.get_count() == 0 and _hits.size() == shots, "every shot is hit in the end (%d of %d)" % [_hits.size(), shots])


## Piercing shots in a packed crowd never die, so a manager that always started
## at slot 0 would spend every budget on the same low slots. The tag is the shot.
func _test_spent_budget_resumes_at_the_first_untested_shot() -> void:
	_setup()
	_mgr.set_cap(200)
	for i in 100:
		_target(Vector2(float(i % 3), 0.0))
	var count: int = 150
	for i in count:
		_mgr.spawn(i % 4, Vector2.ZERO, Vector2(0.1, 0.0), 10.0, 4.0, ManagerScript.LAYER_ENEMY, 100000, i)
	_mgr.step(DT)
	var tested: Dictionary = {}
	for hit in _hits:
		tested[hit[3]] = true
	_check(tested.size() > 0 and tested.size() < count, "the first step cannot test every shot (%d of %d)" % [tested.size(), count])
	_check(not tested.has(count - 1), "the last slot waits when the budget is spent")
	_check(_mgr._resume == tested.size(), "the next step resumes at the first untested slot (%d, tested %d)" % [_mgr._resume, tested.size()])
	var seen: Dictionary = tested.duplicate()
	var steps: int = 0
	while seen.size() < count and steps < 16:
		var before: int = _hits.size()
		_mgr.step(DT)
		for h in range(before, _hits.size()):
			seen[_hits[h][3]] = true
		steps += 1
	_check(seen.size() == count, "deferred shots inside a target hit on a later step, the high slots too (%d of %d)" % [seen.size(), count])
	_check(_mgr.get_count() == count, "piercing shots stay alive")
	# A step that finishes the loop resets the resume point.
	_mgr.clear()
	_mgr.spawn(0, Vector2.ZERO, Vector2(0.1, 0.0), 10.0, 4.0, ManagerScript.LAYER_ENEMY, 5, 0)
	_mgr.step(DT)
	_check(_mgr._resume == 0, "a step that tests everything resets the resume point")


func _wall_rects() -> Array[Rect2]:
	return [Rect2(96.0, 0.0, 32.0, 200.0)]


func _test_shot_ends_on_a_wall() -> void:
	_setup()
	_mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_mgr.set_walls(_wall_rects())
	var shot: int = _mgr.spawn(0, Vector2(50.0, 100.0), Vector2(120.0, 0.0), 5.0)
	var clear_shot: int = _mgr.spawn(0, Vector2(50.0, 250.0), Vector2(120.0, 0.0), 5.0)
	for _i in 60:
		_mgr.step(DT)
	_check(not _mgr.is_alive(shot), "a shot that reaches a wall ends")
	_check(_mgr.is_alive(clear_shot), "a shot below the wall keeps flying")
	_check(_mgr.wall_hits == 1, "wall_hits counts the shot that ended (%d)" % _mgr.wall_hits)


func _test_wall_stops_a_piercing_shot_and_a_fast_shot() -> void:
	_setup()
	_mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_mgr.set_walls(_wall_rects())
	_target(Vector2(200.0, 100.0))
	var piercing: int = _mgr.spawn(0, Vector2(50.0, 100.0), Vector2(600.0, 0.0), 5.0, 4.0, ManagerScript.LAYER_ENEMY, 5)
	# 6,000 px/s moves 100 px in one step: a shot that would skip a thin wall.
	var fast: int = _mgr.spawn(0, Vector2(60.0, 150.0), Vector2(6000.0, 0.0), 5.0)
	for _i in 30:
		_mgr.step(DT)
	_check(not _mgr.is_alive(piercing), "a piercing shot ends on a wall too")
	_check(not _mgr.is_alive(fast), "a shot faster than the wall is thick does not tunnel")
	_check(_hits.is_empty(), "nothing behind the wall was hit (%d)" % _hits.size())


func _test_target_in_front_of_a_wall_is_hit_by_a_long_step() -> void:
	_setup()
	_mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_mgr.set_walls(_wall_rects())
	var in_front: Node2D = _target(Vector2(90.0, 100.0))
	# 6,000 px/s: one step from x 50 to x 150 crosses the target, then the wall.
	var shot: int = _mgr.spawn(0, Vector2(50.0, 100.0), Vector2(6000.0, 0.0), 5.0)
	_mgr.step(DT)
	_check(_hits.size() == 1 and _hits[0][1] == in_front, "the target in front of the wall is hit (%d hits)" % _hits.size())
	_check(not _mgr.is_alive(shot), "the shot ends at the wall or on the hit")
	# A piercing shot passes the target and still ends on the wall in the same step.
	_hits.clear()
	var piercing: int = _mgr.spawn(0, Vector2(50.0, 100.0), Vector2(6000.0, 0.0), 5.0, 4.0, ManagerScript.LAYER_ENEMY, 5)
	_mgr.step(DT)
	_check(_hits.size() == 1, "a piercing shot hits the target in front of the wall (%d)" % _hits.size())
	_check(not _mgr.is_alive(piercing), "and ends on the wall in the same step")
	_check(_mgr.wall_hits >= 1, "wall_hits counts the end")


func _test_shot_born_in_a_wall_takes_no_slot() -> void:
	_setup()
	_mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_mgr.set_cap(3)
	_mgr.set_walls(_wall_rects())
	var first: int = _mgr.spawn(1, Vector2(10.0, 300.0), Vector2(1.0, 0.0), 5.0)
	_mgr.spawn(1, Vector2(20.0, 300.0), Vector2(1.0, 0.0), 5.0)
	_mgr.spawn(1, Vector2(30.0, 300.0), Vector2(1.0, 0.0), 5.0)
	var dead: int = _mgr.spawn(0, Vector2(110.0, 100.0), Vector2(100.0, 0.0), 5.0)
	_check(dead == -1, "a shot spawned inside a wall is refused")
	_check(_mgr.get_count() == 3 and _mgr.is_alive(first), "at the cap it evicted nobody")
	_check(_mgr.wall_hits == 1, "it counts as ended on a wall (%d)" % _mgr.wall_hits)


func _test_wall_walk_is_capped() -> void:
	_setup()
	_mgr.set_bounds(Rect2(0.0, 0.0, 2000.0, 360.0))
	var far_wall: Array[Rect2] = [Rect2(1200.0, 0.0, 32.0, 360.0)]
	_mgr.set_walls(far_wall)
	# One step of 1,800 px is 225 cells, more than MAX_WALL_VISITS: the shot is
	# ended even though the wall lies in the part that is not walked.
	var shot: int = _mgr.spawn(0, Vector2(50.0, 100.0), Vector2(108000.0, 0.0), 5.0)
	_mgr.step(DT)
	_check(not _mgr.is_alive(shot), "a step too long to walk ends the shot instead of crossing the wall")
	# A long step with nothing in the way, within the cap, flies on.
	var near: int = _mgr.spawn(0, Vector2(50.0, 100.0), Vector2(18000.0, 0.0), 5.0)
	_mgr.step(DT)
	_check(_mgr.is_alive(near), "a 300 px step toward a far wall is walked and clear")


func _test_wall_hits_from_every_direction() -> void:
	_setup()
	_mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	var block: Array[Rect2] = [Rect2(304.0, 152.0, 32.0, 32.0)]
	_mgr.set_walls(block)
	var centre := Vector2(320.0, 168.0)
	var slots: Array[int] = []
	for i in 16:
		var direction: Vector2 = Vector2.from_angle(float(i) * TAU / 16.0 + 0.1)
		slots.append(_mgr.spawn(0, centre + direction * 90.0, -direction * 200.0, 5.0))
	for _i in 40:
		_mgr.step(DT)
	var alive: int = 0
	for slot in slots:
		if _mgr.is_alive(slot):
			alive += 1
	_check(alive == 0, "shots from all sides end on the block (%d still fly)" % alive)
	_check(_mgr.wall_hits == 16, "each one counted (%d)" % _mgr.wall_hits)


func _test_wall_edges_and_clearing() -> void:
	_setup()
	_mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_mgr.set_walls(_wall_rects())
	# The wall covers x 96..128, y 0..200.
	var beside: int = _mgr.spawn(0, Vector2(90.0, 260.0), Vector2(0.0, -100.0), 1.0)
	var below: int = _mgr.spawn(0, Vector2(120.0, 205.0), Vector2(0.0, 100.0), 1.0)
	_mgr.step(DT)
	_check(_mgr.is_alive(beside), "a shot beside the wall does not touch it")
	_check(_mgr.is_alive(below), "a shot leaving the wall's bottom edge flies on")
	_mgr.clear_walls()
	var through: int = _mgr.spawn(0, Vector2(90.0, 100.0), Vector2(300.0, 0.0), 2.0)
	for _i in 20:
		_mgr.step(DT)
	_check(_mgr.is_alive(through) and _mgr.get_position_of(through).x > 128.0, "with the walls cleared the shot passes")
	_mgr.set_walls(_wall_rects())
	_mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	var again: int = _mgr.spawn(0, Vector2(90.0, 100.0), Vector2(300.0, 0.0), 2.0)
	for _i in 20:
		_mgr.step(DT)
	_check(_mgr.is_alive(again), "set_bounds removes the walls")


func _test_clip_to_walls() -> void:
	_setup()
	_mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	var open_end: Vector2 = _mgr.clip_to_walls(Vector2(10.0, 10.0), Vector2(90.0, 10.0))
	_check(open_end == Vector2(90.0, 10.0), "without walls the segment is unchanged")
	_mgr.set_walls(_wall_rects())
	var clipped: Vector2 = _mgr.clip_to_walls(Vector2(60.0, 100.0), Vector2(160.0, 100.0))
	_check(absf(clipped.x - 96.0) < 0.01 and clipped.y == 100.0, "the segment stops at the wall's near edge (%s)" % str(clipped))
	var diagonal: Vector2 = _mgr.clip_to_walls(Vector2(80.0, 80.0), Vector2(180.0, 180.0))
	_check(absf(diagonal.x - 96.0) < 0.01 and absf(diagonal.y - 96.0) < 0.01, "a diagonal segment stops at the edge (%s)" % str(diagonal))
	var inside: Vector2 = _mgr.clip_to_walls(Vector2(110.0, 100.0), Vector2(60.0, 100.0))
	_check(inside == Vector2(110.0, 100.0), "from inside a wall the segment is empty")
	var clear: Vector2 = _mgr.clip_to_walls(Vector2(60.0, 250.0), Vector2(160.0, 250.0))
	_check(clear == Vector2(160.0, 250.0), "a clear segment is unchanged")
	_check(not _mgr.circle_blocked(Vector2(60.0, 250.0), 6.0), "a circle in the open is not blocked")
	_check(_mgr.circle_blocked(Vector2(90.0, 100.0), 6.0), "a circle whose rim meets a wall is blocked")
	_check(_mgr.circle_blocked(Vector2(3.0, 250.0), 6.0), "a circle past the bounds is blocked")


func _test_wall_body_rectangles_become_walls() -> void:
	_setup()
	_mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	var body := StaticBody2D.new()
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
	_mgr.add_wall_body(body)
	var clipped: Vector2 = _mgr.clip_to_walls(Vector2(60.0, 30.0), Vector2(200.0, 30.0))
	_check(absf(clipped.x - 96.0) < 0.01, "the body's rectangle (96..128, 0..64) is a wall (%s)" % str(clipped))
	var below: Vector2 = _mgr.clip_to_walls(Vector2(60.0, 100.0), Vector2(200.0, 100.0))
	_check(below.x == 200.0, "below the rectangle is open")
	var round_shape: Vector2 = _mgr.clip_to_walls(Vector2(300.0, 200.0), Vector2(500.0, 200.0))
	_check(round_shape.x == 500.0, "a circle shape is ignored")
	body.free()


## Regression (#5): the hit circle sat at the node's origin (the feet), so a shot
## flying through the drawn body above it passed without hitting.
func _test_target_offset_moves_the_hit_circle() -> void:
	_setup()
	var node := Node2D.new()
	root.add_child(node)
	_targets.append(node)
	node.global_position = Vector2(50.0, 0.0)
	_mgr.add_target(node, 8.0, ManagerScript.LAYER_ENEMY, EventsScript.NO_PLAYER, Vector2(0.0, -14.0))
	# Through the body (y = -14) hits; along the feet (y = 0) is 14 px from the circle's centre, beyond 8 + 4.
	_mgr.spawn(0, Vector2(0.0, -14.0), Vector2(600.0, 0.0), 1.0, 4.0)
	_mgr.step(0.2)
	_check(_hits.size() == 1, "a shot through the body hits a target whose circle is offset up")
	_mgr.spawn(0, Vector2(0.0, 0.0), Vector2(600.0, 0.0), 1.0, 4.0)
	_mgr.step(0.2)
	_check(_hits.size() == 1, "a shot along the feet misses the offset circle")


func _test_expiry_event_on_end_of_life() -> void:
	_setup()
	_mgr.spawn(1, Vector2.ZERO, Vector2(60.0, 0.0), 0.5, 4.0, ManagerScript.LAYER_ENEMY, 0, 77)
	_mgr.step(0.25)
	_check(_expired.is_empty(), "no expiry while the shot lives")
	_mgr.step(0.25)
	_check(_expired.size() == 1, "one expiry when the life runs out (%d)" % _expired.size())
	if _expired.size() == 1:
		_check(_expired[0][0] == 1 and _expired[0][2] == 77, "it names the player and gives the tag back")
		_check((_expired[0][1] as Vector2).is_equal_approx(Vector2(15.0, 0.0)), "it gives the place the shot reached")
	_mgr.step(0.25)
	_check(_expired.size() == 1, "an ended shot expires only once")


func _test_expiry_event_on_a_wall() -> void:
	_setup()
	_mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_mgr.set_walls(_wall_rects())
	_mgr.spawn(0, Vector2(50.0, 100.0), Vector2(120.0, 0.0), 5.0, 4.0, ManagerScript.LAYER_ENEMY, 3, 5)
	for _i in 60:
		_mgr.step(DT)
	_check(_expired.size() == 1, "a wall end sends one expiry, even for a piercing shot")
	if _expired.size() == 1:
		_check(absf((_expired[0][1] as Vector2).x - 96.0) < 0.5 and _expired[0][2] == 5, "at the wall, with the tag")


func _test_no_expiry_on_a_hit_a_cap_drop_or_leaving() -> void:
	_setup()
	_target(Vector2(30.0, 0.0))
	_mgr.spawn(0, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0)
	_mgr.step(DT)
	_check(_hits.size() == 1 and _expired.is_empty(), "a shot that ends on a hit is not expired")
	_mgr.set_cap(2)
	for _i in 3:
		_mgr.spawn(0, Vector2(0.0, 100.0), Vector2(1.0, 0.0), 5.0)
	_check(_mgr.dropped == 1 and _expired.is_empty(), "a shot dropped by the cap is not expired")
	_mgr.clear()
	_mgr.spawn(0, Vector2(1000.0, 0.0), Vector2(5000.0, 0.0), 5.0)
	_mgr.step(0.1)
	_check(_mgr.get_count() == 0 and _expired.is_empty(), "a shot that leaves the bounds is not expired")


func _test_expiry_handler_may_spawn() -> void:
	_setup()
	_bus.projectile_expired.connect(func(player: int, position: Vector2, _tag: int) -> void:
		if _mgr.get_count() == 0:
			_mgr.spawn(player, position, Vector2(10.0, 0.0), 1.0))
	_mgr.spawn(0, Vector2.ZERO, Vector2(10.0, 0.0), 0.1)
	_mgr.step(0.2)
	_check(_mgr.get_count() == 1, "a shot spawned by an expiry handler lives")
	_mgr.step(DT)
	_check(_mgr.get_count() == 1, "and does not expire in the step after")


func _test_still_shot_waits_for_a_target() -> void:
	_setup()
	var slot: int = _mgr.spawn(0, Vector2(100.0, 50.0), Vector2(300.0, 300.0), 2.0, 12.0, ManagerScript.LAYER_ENEMY, 0, 9, ManagerScript.MOTION_STILL)
	_check(slot >= 0, "a still shot spawns")
	for _i in 30:
		_mgr.step(DT)
	_check(_mgr.get_position_of(slot) == Vector2(100.0, 50.0), "a still shot stays where it was put, whatever velocity it was given")
	_check(_hits.is_empty(), "nothing to hit yet")
	var enemy: Node2D = _target(Vector2(300.0, 50.0))
	enemy.global_position = Vector2(110.0, 50.0)
	_mgr.step(DT)
	_check(_hits.size() == 1 and _hits[0][1] == enemy and _hits[0][3] == 9, "a target walking into it is hit, with the tag")
	_check(not _mgr.is_alive(slot), "the rune ends on the hit")


func _test_still_shot_pierces_and_expires() -> void:
	_setup()
	var a: Node2D = _target(Vector2(100.0, 50.0))
	var b: Node2D = _target(Vector2(104.0, 50.0))
	_mgr.spawn(0, Vector2(100.0, 50.0), Vector2.ZERO, 0.5, 12.0, ManagerScript.LAYER_ENEMY, 3, 0, ManagerScript.MOTION_STILL)
	_mgr.step(DT)
	_check(_hits.size() == 2 and _hits[0][1] != _hits[1][1], "a piercing rune hits two overlapping targets, each once")
	_mgr.step(DT)
	_check(_hits.size() == 2, "it does not hit the same ones again while they stay")
	a.global_position = Vector2(500.0, 500.0)
	b.global_position = Vector2(500.0, 500.0)
	for _i in 40:
		_mgr.step(DT)
	_check(_expired.size() == 1 and _mgr.get_count() == 0, "an unspent rune expires at the end of its life")
	_check(_mgr.spawn(0, Vector2.ZERO, Vector2.ZERO, 1.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 0, 7) == -1, "an unknown motion is refused")


func _test_still_shot_beside_and_in_a_wall() -> void:
	_setup()
	_mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_mgr.set_walls(_wall_rects())
	_check(_mgr.spawn(0, Vector2(100.0, 100.0), Vector2.ZERO, 1.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL) == -1, "a rune cannot be placed in a wall")
	var slot: int = _mgr.spawn(0, Vector2(60.0, 100.0), Vector2.ZERO, 1.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	for _i in 10:
		_mgr.step(DT)
	_check(_mgr.is_alive(slot) and _expired.is_empty(), "a rune beside a wall stays")


func _test_nearest_target() -> void:
	_setup()
	var far: Node2D = _target(Vector2(150.0, 100.0), 10.0)
	var near: Node2D = _target(Vector2(120.0, 100.0), 10.0)
	var other_layer: Node2D = _target(Vector2(101.0, 100.0), 10.0, ManagerScript.LAYER_PLAYER)
	var point := Vector2(100.0, 100.0)
	_check(_mgr.nearest_target(point, 100.0, ManagerScript.LAYER_ENEMY) == near, "the nearest target on the layer (before any step)")
	_check(_mgr.nearest_target(point, 100.0, ManagerScript.LAYER_ENEMY, near) == far, "exclude skips the target just hit")
	_check(_mgr.nearest_point == Vector2(150.0, 100.0), "the hit circle's centre is left in nearest_point")
	_check(_mgr.nearest_target(point, 100.0, ManagerScript.LAYER_ENEMY, near, far) == null, "exclude_also skips a second target")
	_check(not _mgr.nearest_point.is_finite(), "and nearest_point is INF when nothing was found")
	_check(_mgr.nearest_target(point, 100.0, ManagerScript.LAYER_PLAYER) == other_layer, "layers are respected")
	_check(_mgr.nearest_target(point, 100.0, ManagerScript.LAYER_ENEMY | ManagerScript.LAYER_PLAYER) == other_layer, "a mask of both layers finds the closest of either")
	_check(_mgr.nearest_target(point, 5.0, ManagerScript.LAYER_ENEMY) == null, "nothing within a small radius")
	_check(_mgr.nearest_target(point, 9.0, ManagerScript.LAYER_ENEMY) == null, "the radius counts to the target's edge: 20 away, 9 + 10 = 19")
	_check(_mgr.nearest_target(point, 10.0, ManagerScript.LAYER_ENEMY) == near, "and 10 + 10 = 20 reaches it")
	_check(_mgr.nearest_target(point, 100.0, 0) == null, "an empty mask finds nothing")
	near.global_position = Vector2(400.0, 100.0)
	_mgr.step(DT)
	_check(_mgr.nearest_target(point, 100.0, ManagerScript.LAYER_ENEMY) == far, "after a step it follows moved targets")
	far.free()
	_mgr.step(DT)
	_check(_mgr.nearest_target(point, 400.0, ManagerScript.LAYER_ENEMY) == near, "a freed target is not returned")


func _test_nearest_target_with_no_targets_and_after_removal() -> void:
	_setup()
	_check(_mgr.nearest_target(Vector2.ZERO, 500.0, ManagerScript.LAYER_ENEMY) == null, "no targets, no result")
	var enemy: Node2D = _target(Vector2(10.0, 10.0))
	_check(_mgr.nearest_target(Vector2.ZERO, 50.0, ManagerScript.LAYER_ENEMY) == enemy, "found")
	_mgr.remove_target(enemy)
	_mgr.step(DT)
	_check(_mgr.nearest_target(Vector2.ZERO, 50.0, ManagerScript.LAYER_ENEMY) == null, "a removed target is not found")
	var doomed: Node2D = _target(Vector2(20.0, 0.0))
	_mgr.step(DT)
	doomed.free()
	var out: Array[Node2D] = []
	_check(_mgr.nearest_target(Vector2.ZERO, 50.0, ManagerScript.LAYER_ENEMY) == null, "a target freed since the last step is not returned")
	_check(_mgr.targets_in(Vector2.ZERO, 50.0, ManagerScript.LAYER_ENEMY, out) == 0, "nor listed")


func _test_set_bounds_with_targets_present() -> void:
	_setup()
	var enemy: Node2D = _target(Vector2(50.0, 50.0))
	_mgr.step(DT)
	_mgr.set_bounds(Rect2(0.0, 0.0, 800.0, 600.0))
	_check(_mgr.nearest_target(Vector2(50.0, 50.0), 20.0, ManagerScript.LAYER_ENEMY) == enemy, "targets are found after set_bounds, before the next step")
	var out: Array[Node2D] = []
	_mgr.set_bounds(Rect2(0.0, 0.0, 800.0, 600.0))
	_check(_mgr.targets_in(Vector2(50.0, 50.0), 20.0, ManagerScript.LAYER_ENEMY, out) == 1, "and listed")


func _test_queries_ignore_non_finite_input() -> void:
	_setup()
	_target(Vector2(50.0, 50.0))
	var out: Array[Node2D] = []
	_check(_mgr.nearest_target(Vector2(NAN, 0.0), 20.0, ManagerScript.LAYER_ENEMY) == null, "NaN point finds nothing")
	_check(_mgr.nearest_target(Vector2(50.0, 50.0), INF, ManagerScript.LAYER_ENEMY) == null, "infinite radius finds nothing")
	_check(_mgr.targets_in(Vector2(INF, 0.0), 20.0, ManagerScript.LAYER_ENEMY, out) == 0, "infinite point lists nothing")
	_check(_mgr.targets_in(Vector2(50.0, 50.0), NAN, ManagerScript.LAYER_ENEMY, out) == 0, "NaN radius lists nothing")


func _test_still_shot_impact_has_a_direction() -> void:
	_setup()
	var directions: Array[Vector2] = []
	_bus.projectile_impact.connect(func(_player: int, _target: Node, _position: Vector2, direction: Vector2) -> void: directions.append(direction))
	_mgr.spawn(0, Vector2(100.0, 50.0), Vector2.ZERO, 2.0, 12.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	_target(Vector2(110.0, 50.0))
	_mgr.step(DT)
	_check(directions.size() == 1 and absf(directions[0].length() - 1.0) < 0.001, "a rune hit sends a unit direction, not zero")


func _test_queries_inside_a_hit_handler() -> void:
	_setup()
	_target(Vector2(30.0, 0.0))
	var second: Node2D = _target(Vector2(60.0, 0.0))
	var found: Array[Node2D] = []
	_bus.projectile_hit.connect(func(_player: int, target: Node, position: Vector2, _tag: int) -> void:
		found.append(_mgr.nearest_target(position, 80.0, ManagerScript.LAYER_ENEMY, target as Node2D)))
	_mgr.spawn(0, Vector2.ZERO, Vector2(1200.0, 0.0), 1.0)
	_mgr.step(DT)
	_check(found.size() == 1 and found[0] == second, "a chain query from a hit handler finds the other target")


func _test_targets_in() -> void:
	_setup()
	var a: Node2D = _target(Vector2(100.0, 100.0))
	var b: Node2D = _target(Vector2(130.0, 100.0))
	var c: Node2D = _target(Vector2(300.0, 100.0))
	var p: Node2D = _target(Vector2(105.0, 100.0), 10.0, ManagerScript.LAYER_PLAYER)
	var out: Array[Node2D] = []
	var n: int = _mgr.targets_in(Vector2(110.0, 100.0), 30.0, ManagerScript.LAYER_ENEMY, out)
	_check(n == 2 and out.size() == 2 and out.has(a) and out.has(b) and not out.has(c) and not out.has(p), "the enemies near the point, not far ones or other layers (%d)" % n)
	n = _mgr.targets_in(Vector2(110.0, 100.0), 30.0, ManagerScript.LAYER_ENEMY | ManagerScript.LAYER_PLAYER, out)
	_check(n == 3 and out.has(p), "a mask of both layers adds the player target; the array was cleared first")
	n = _mgr.targets_in(Vector2(900.0, 900.0), 30.0, ManagerScript.LAYER_ENEMY, out)
	_check(n == 0 and out.is_empty(), "no result empties the array")
	n = _mgr.targets_in(Vector2(-5000.0, -5000.0), 20.0, ManagerScript.LAYER_ENEMY, out)
	_check(n == 0, "a point far outside the bounds is safe")


func _test_queries_match_brute_force() -> void:
	_setup()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var radii: Array[float] = []
	for i in 300:
		var radius: float = rng.randf_range(4.0, 20.0)
		radii.append(radius)
		_target(Vector2(rng.randf_range(-900.0, 900.0), rng.randf_range(-900.0, 900.0)), radius)
	_mgr.step(DT)
	var out: Array[Node2D] = []
	var wrong: int = 0
	for _q in 200:
		var point := Vector2(rng.randf_range(-1000.0, 1000.0), rng.randf_range(-1000.0, 1000.0))
		var reach: float = rng.randf_range(1.0, 150.0)
		var expected: Array[Node2D] = []
		var best: Node2D = null
		var best_d: float = INF
		for i in _targets.size():
			var d: float = _targets[i].global_position.distance_to(point)
			if d <= reach + radii[i]:
				expected.append(_targets[i])
				if d < best_d:
					best_d = d
					best = _targets[i]
		_mgr.targets_in(point, reach, ManagerScript.LAYER_ENEMY, out)
		if out.size() != expected.size():
			wrong += 1
		else:
			for node in expected:
				if not out.has(node):
					wrong += 1
					break
		if _mgr.nearest_target(point, reach, ManagerScript.LAYER_ENEMY) != best:
			wrong += 1
	_check(wrong == 0, "200 random queries agree with a brute-force search (%d differ)" % wrong)
