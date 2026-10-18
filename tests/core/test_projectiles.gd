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
	_check(_mgr.spawn(4, Vector2.ZERO, Vector2.RIGHT, 1.0) == -1, "player 4 is refused")
	_check(_mgr.spawn(-2, Vector2.ZERO, Vector2.RIGHT, 1.0) == -1, "player -2 is refused")
	_check(_mgr.spawn(0, Vector2.ZERO, Vector2.RIGHT, 0.0) == -1, "zero lifetime is refused")
	_check(_mgr.spawn(0, Vector2(NAN, 0.0), Vector2.RIGHT, 1.0) == -1, "a NaN position is refused")
	_check(_mgr.spawn(0, Vector2.ZERO, Vector2(INF, 0.0), 1.0) == -1, "an infinite velocity is refused")
	_check(_mgr.get_count() == 0, "refused spawns leave nothing behind")
	_check(_mgr.get_count_for(7) == 0, "counting an invalid player gives 0")


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
	_check(buffer.size() > 12 and is_equal_approx(buffer[3], 20.0) and is_equal_approx(buffer[15], 30.0), "the enemy batch has the enemy shots' positions")
	_check(is_equal_approx(buffer[8], 1.0) and is_equal_approx(buffer[9], 1.0) and is_equal_approx(buffer[10], 1.0), "enemy shots are not tinted")
	_mgr.clear()
	_mgr.update_draw()
	_check(_mgr.drawn == 0 and _mgr._hostile_node.multimesh.visible_instance_count == 0, "clear empties the enemy batch too")
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
	while seen.size() < count and steps < 8:
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
