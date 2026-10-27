extends SceneTree
## Tests for core/projectiles, the projectile kit (staffs B1): bounce, ghost, spiral, return,
## linger, growth, sticky, shield, shots that hit their caster, passing through teammates and
## the wall flag of an expiry. The manager is stepped by hand.
##
## godot --headless --path . --script res://tests/core/test_projectiles_kit.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const EventsScript :=preload("res://core/events/events.gd")

const DT: float = 1.0 / 60.0

var _failures: Array[String] = []
var _bus: Node
var _mgr: Node2D
var _targets: Array[Node2D] = []
## Every projectile_hit as [player, target, position, tag].
var _hits: Array = []
## Every projectile_expired as [player, position, tag, on_wall].
var _expired: Array = []
## Every ally_passed as [player, ally, tag].
var _passed: Array = []
## Every shot_blocked as [player, position, tag].
var _blocked: Array = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	_test_a_plain_shot_has_no_behaviours()
	_test_wall_ends_a_shot_and_says_so()
	_test_bounce_off_a_vertical_wall()
	_test_bounce_off_a_horizontal_wall_and_corner()
	_test_bounce_count_runs_out()
	_test_ghost_passes_walls()
	_test_spiral_weaves_round_its_line()
	_test_return_comes_back_and_hits_twice()
	_test_linger_stops_then_goes_on()
	_test_growth_is_capped()
	_test_sticky_follows_its_target()
	_test_shield_blocks_enemy_shots()
	_test_shield_only_for_players_shots()
	_test_self_hit_waits_until_the_shot_leaves_the_caster()
	_test_ally_is_passed_once_or_hit()
	_test_sticky_shot_keeps_its_direction_and_stays_stuck_at_a_wall()
	_test_shield_catches_fast_shots_in_any_slot_order()
	_test_apply_travel_maps_cards_to_the_shot()
	_test_setters_refuse_bad_slots()
	_test_many_shots_with_behaviours_stay_cheap()
	_teardown()
	if _failures.is_empty():
		print("TEST OK: core/projectiles kit")
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
	_mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_hits.clear()
	_expired.clear()
	_passed.clear()
	_blocked.clear()
	_bus.projectile_expired.connect(func(player: int, position: Vector2, tag: int) -> void: _expired.append([player, position, tag, _mgr.expired_on_wall]))
	_bus.projectile_hit.connect(func(player: int, target: Node, position: Vector2, tag: int) -> void: _hits.append([player, target, position, tag]))
	_bus.ally_passed.connect(func(player: int, ally: Node, _position: Vector2, tag: int) -> void: _passed.append([player, ally, tag]))
	_bus.shot_blocked.connect(func(player: int, position: Vector2, tag: int) -> void: _blocked.append([player, position, tag]))


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


func _target(position: Vector2, radius: float = 10.0, layer: int = ManagerScript.LAYER_ENEMY, owner: int = EventsScript.NO_PLAYER) -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	node.global_position = position
	_targets.append(node)
	_mgr.add_target(node, radius, layer, owner)
	return node


func _run(steps: int) -> void:
	for _i in steps:
		_mgr.step(DT)


func _fire(velocity: Vector2, at: Vector2 = Vector2(50.0, 100.0), life: float = 3.0, tag: int = 1, player: int = 0) -> int:
	return _mgr.spawn(player, at, velocity, life, 3.0, ManagerScript.LAYER_ENEMY, 0, tag)


func _test_a_plain_shot_has_no_behaviours() -> void:
	_setup()
	var slot: int = _fire(Vector2(120.0, 0.0), Vector2(50.0, 100.0), 1.0)
	_run(30)
	_check(_mgr.get_position_of(slot).is_equal_approx(Vector2(110.0, 100.0)), "a plain shot flies straight (%s)" % _mgr.get_position_of(slot))
	_check(is_equal_approx(_mgr.get_growth_of(slot), 1.0) and _mgr.get_shield_of(slot) == 0 and not _mgr.is_self_live(slot), "and has no growth, shield or self-hit")
	_run(40)
	_check(_expired.size() == 1 and not _expired[0][3], "it expires by its life, not on a wall")


func _test_wall_ends_a_shot_and_says_so() -> void:
	_setup()
	_mgr.set_walls([Rect2(96.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	_fire(Vector2(300.0, 0.0))
	_run(30)
	_check(_expired.size() == 1 and _expired[0][3], "a shot that ends on a wall has the wall flag in its expiry")
	_check(not _mgr.expired_on_wall, "and the flag is down again afterwards")


func _test_bounce_off_a_vertical_wall() -> void:
	_setup()
	_mgr.set_walls([Rect2(96.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	var slot: int = _fire(Vector2(300.0, 0.0))
	_check(_mgr.set_bounce(slot, 1), "bounce is accepted")
	_run(20)
	_check(_mgr.is_alive(slot) and _mgr.get_velocity_of(slot).x < 0.0 and is_zero_approx(_mgr.get_velocity_of(slot).y), "a shot bounces straight back off a vertical wall (%s)" % _mgr.get_velocity_of(slot))
	_check(_mgr.get_position_of(slot).x < 96.0, "and stays out of the wall")
	_check(_expired.is_empty() and _mgr.wall_hits == 1, "a bounce is a wall hit but not an expiry")


func _test_bounce_off_a_horizontal_wall_and_corner() -> void:
	_setup()
	_mgr.set_walls([Rect2(0.0, 150.0, 400.0, 32.0)] as Array[Rect2])
	var slot: int = _fire(Vector2(200.0, 200.0), Vector2(50.0, 100.0))
	_mgr.set_bounce(slot, 2)
	_run(20)
	var velocity: Vector2 = _mgr.get_velocity_of(slot)
	_check(_mgr.is_alive(slot) and is_equal_approx(velocity.x, 200.0) and is_equal_approx(velocity.y, -200.0), "a floor flips only the vertical speed (%s)" % velocity)
	# A shot into a corner of two walls turns right round.
	_setup()
	_mgr.set_walls([Rect2(96.0, 0.0, 32.0, 200.0), Rect2(0.0, 200.0, 400.0, 32.0)] as Array[Rect2])
	var corner: int = _fire(Vector2(200.0, 200.0), Vector2(40.0, 60.0))
	_mgr.set_bounce(corner, 4)
	_run(60)
	_check(_mgr.is_alive(corner) and _mgr.get_position_of(corner).x < 96.0 and _mgr.get_position_of(corner).y < 200.0, "a shot in a corner never ends up inside a wall (%s)" % _mgr.get_position_of(corner))


func _test_bounce_count_runs_out() -> void:
	_setup()
	_mgr.set_walls([Rect2(96.0, 0.0, 32.0, 200.0), Rect2(0.0, 0.0, 16.0, 200.0)] as Array[Rect2])
	var slot: int = _fire(Vector2(300.0, 0.0), Vector2(50.0, 100.0), 5.0)
	_mgr.set_bounce(slot, 2)
	_run(120)
	_check(not _mgr.is_alive(slot) and _expired.size() == 1 and _expired[0][3], "after its bounces a shot ends on the next wall, with the wall flag")
	_check(_mgr.wall_hits == 3, "that took three wall hits (%d)" % _mgr.wall_hits)


func _test_ghost_passes_walls() -> void:
	_setup()
	_mgr.set_walls([Rect2(96.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	var slot: int = _fire(Vector2(300.0, 0.0))
	_mgr.set_ghost(slot)
	var enemy: Node2D = _target(Vector2(250.0, 100.0), 8.0)
	_run(40)
	_check(_mgr.wall_hits == 0 and _hits.size() == 1 and _hits[0][1] == enemy, "a ghost shot flies through a wall and hits what is behind it")


func _test_spiral_weaves_round_its_line() -> void:
	_setup()
	var slot: int = _fire(Vector2(100.0, 0.0), Vector2(50.0, 100.0), 4.0)
	_mgr.set_spiral(slot, 20.0)
	var low: float = 0.0
	var high: float = 0.0
	for _i in 60:
		_mgr.step(DT)
		var y: float = _mgr.get_position_of(slot).y - 100.0
		low = minf(low, y)
		high = maxf(high, y)
	_check(absf(high - 10.0) < 0.5 and absf(low + 10.0) < 0.5, "a spiral 20 px wide swings 10 px either side (%f, %f)" % [low, high])
	_check(absf(_mgr.get_position_of(slot).x - 150.0) < 0.5 or _mgr.get_position_of(slot).x > 140.0, "and still travels at its speed")
	var straight: int = _fire(Vector2(100.0, 0.0), Vector2(50.0, 200.0), 4.0, 2)
	_check(not _mgr.set_spiral(straight, 0.0), "a spiral needs a width")


func _test_return_comes_back_and_hits_twice() -> void:
	_setup()
	_mgr.set_anchor(0, Vector2(50.0, 100.0))
	var enemy: Node2D = _target(Vector2(110.0, 100.0), 8.0)
	var slot: int = _mgr.spawn(0, Vector2(50.0, 100.0), Vector2(120.0, 0.0), 1.0, 3.0, ManagerScript.LAYER_ENEMY, 5, 7)
	_check(_mgr.set_return(slot), "return is accepted")
	var farthest: float = 0.0
	for _i in 70:
		_mgr.step(DT)
		if _mgr.is_alive(slot):
			farthest = maxf(farthest, _mgr.get_position_of(slot).x)
	_check(farthest > 105.0 and farthest < 125.0, "it flies out for half its life (%f)" % farthest)
	_check(_hits.size() == 2, "it hits the enemy on the way out and again on the way back (%d)" % _hits.size())
	_check(not _mgr.is_alive(slot) and _expired.size() == 1 and _expired[0][1].distance_to(Vector2(50.0, 100.0)) < 8.0, "and ends back at its caster")
	_check(not _expired[0][3], "not on a wall")
	# Its owner leaving ends it.
	_mgr.clear_anchor(0)
	var lost: int = _mgr.spawn(0, Vector2(50.0, 100.0), Vector2(120.0, 0.0), 1.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 8)
	_mgr.set_return(lost)
	_run(40)
	_check(not _mgr.is_alive(lost), "a returning shot with no caster to return to ends")


func _test_linger_stops_then_goes_on() -> void:
	_setup()
	var slot: int = _fire(Vector2(100.0, 0.0), Vector2(50.0, 100.0), 1.0)
	_mgr.set_linger(slot, 0.5)
	_run(31)
	var stopped_at: Vector2 = _mgr.get_position_of(slot)
	_run(15)
	_check(_mgr.get_position_of(slot).is_equal_approx(stopped_at), "a lingering shot hangs in the air half way through its flight")
	_check(absf(stopped_at.x - 100.0) < 4.0, "after half its life (%s)" % stopped_at)
	_run(30)
	_check(_mgr.is_alive(slot) and _mgr.get_position_of(slot).x > stopped_at.x + 10.0, "then flies on")
	_run(60)
	_check(not _mgr.is_alive(slot) and _expired.size() == 1, "and ends by its life, which the stop did not use up")
	_check(absf(_expired[0][1].x - 100.0 - 50.0) < 6.0, "having flown the whole flight (%s)" % _expired[0][1])


func _test_growth_is_capped() -> void:
	_setup()
	var slot: int = _fire(Vector2(10.0, 0.0), Vector2(50.0, 100.0), 10.0)
	_mgr.set_growth(slot, 2.0)
	_run(60)
	_check(absf(_mgr.get_growth_of(slot) - 2.0) < 0.05, "a shot growing x2 a second is twice as big after a second (%f)" % _mgr.get_growth_of(slot))
	_run(300)
	_check(absf(_mgr.get_growth_of(slot) - ManagerScript.GROWTH_MAX) < 0.01, "and stops at %s times" % ManagerScript.GROWTH_MAX)
	# A grown shot hits what the small one would miss.
	_setup()
	var big: int = _fire(Vector2(20.0, 0.0), Vector2(50.0, 100.0), 10.0)
	_mgr.set_growth(big, 3.0)
	var enemy: Node2D = _target(Vector2(130.0, 112.0), 6.0)
	_run(200)
	_check(_hits.size() == 1 and _hits[0][1] == enemy, "a grown shot hits an enemy off its line")
	_check(not _mgr.set_growth(big, 1.0), "growth must be more than 1")


func _test_sticky_follows_its_target() -> void:
	_setup()
	var enemy: Node2D = _target(Vector2(100.0, 100.0), 8.0)
	var other: Node2D = _target(Vector2(104.0, 100.0), 8.0)
	var slot: int = _fire(Vector2(200.0, 0.0), Vector2(50.0, 100.0), 3.0, 9)
	_mgr.set_sticky(slot, 0.5)
	_run(20)
	_check(_hits.size() == 1 and _mgr.is_alive(slot), "a sticky shot hits once and stays")
	var first: Node2D = _hits[0][1]
	enemy.global_position += Vector2(0.0, 30.0)
	other.global_position += Vector2(0.0, 30.0)
	_run(10)
	var carrier: Node2D = first
	_check(absf(_mgr.get_position_of(slot).y - (carrier.global_position.y + (_hits[0][2].y - 100.0))) < 0.01, "it rides on its target")
	_check(_hits.size() == 1, "and hits nothing more while stuck")
	_run(40)
	_check(not _mgr.is_alive(slot) and _expired.size() == 1 and _expired[0][2] == 9, "it expires where it sticks when the time is up")
	_check(_expired[0][1].distance_to(carrier.global_position) < 12.0, "on its target")
	# A target freed while carrying a shot ends it.
	_setup()
	var doomed: Node2D = _target(Vector2(100.0, 100.0), 8.0)
	var stuck: int = _fire(Vector2(200.0, 0.0), Vector2(50.0, 100.0), 3.0, 4)
	_mgr.set_sticky(stuck, 5.0)
	_run(15)
	_mgr.remove_target(doomed)
	_targets.erase(doomed)
	doomed.free()
	_run(2)
	_check(not _mgr.is_alive(stuck), "a shot stuck to a freed target ends")


func _test_shield_blocks_enemy_shots() -> void:
	_setup()
	var shield: int = _fire(Vector2(0.0, 0.0), Vector2(100.0, 100.0), 3.0, 5)
	_mgr.set_shield(shield, 2)
	var spawned: Array[int] = []
	for i in 3:
		spawned.append(_mgr.spawn(EventsScript.NO_PLAYER, Vector2(160.0 + 20.0 * i, 100.0), Vector2(-100.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_PLAYER, 0, 0))
	var ended: Array[int] = []
	_mgr.shot_ended.connect(func(tag: int) -> void: ended.append(tag))
	_run(90)
	_check(_blocked.size() == 2 and _blocked[0][0] == 0 and _blocked[0][2] == 5, "a shield with two charges blocks two enemy shots and says so (%d)" % _blocked.size())
	_check(_mgr.get_shield_of(shield) == 0 and _mgr.is_alive(shield), "and survives with no charge left")
	var alive: int = 0
	for slot in spawned:
		if _mgr.is_alive(slot):
			alive += 1
	_check(alive == 1, "the third enemy shot gets through (%d alive)" % alive)
	# A fast enemy shot cannot tunnel through the shield.
	_setup()
	var wall: int = _fire(Vector2(0.0, 0.0), Vector2(100.0, 100.0), 3.0, 6)
	_mgr.set_shield(wall, 1)
	var fast: int = _mgr.spawn(EventsScript.NO_PLAYER, Vector2(300.0, 100.0), Vector2(-3000.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_PLAYER, 0, 0)
	_run(6)
	_check(not _mgr.is_alive(fast) and _blocked.size() == 1, "a very fast enemy shot is still stopped")


func _test_shield_only_for_players_shots() -> void:
	_setup()
	var enemy_shot: int = _mgr.spawn(EventsScript.NO_PLAYER, Vector2(100.0, 100.0), Vector2.ZERO, 1.0, 3.0, ManagerScript.LAYER_PLAYER, 0, 0)
	_check(not _mgr.set_shield(enemy_shot, 1), "an enemy shot cannot have a shield")
	_mgr.clear()
	var mine: int = _fire(Vector2.ZERO, Vector2(100.0, 100.0))
	var friend: int = _fire(Vector2.ZERO, Vector2(100.0, 100.0), 1.0, 2, 1)
	_mgr.set_shield(mine, 1)
	_run(5)
	_check(_mgr.is_alive(friend) and _blocked.is_empty(), "a shield stops enemy shots only, never a teammate's")


func _test_self_hit_waits_until_the_shot_leaves_the_caster() -> void:
	_setup()
	_mgr.set_walls([Rect2(160.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	var caster: Node2D = _target(Vector2(50.0, 100.0), 8.0, ManagerScript.LAYER_PLAYER, 0)
	# Without the flag a shot never hits its caster.
	var harmless: int = _fire(Vector2(200.0, 0.0))
	_mgr.set_bounce(harmless, 1)
	_run(100)
	_check(_hits.is_empty(), "a shot without the flag passes its caster")
	_setup()
	_mgr.set_walls([Rect2(160.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	caster = _target(Vector2(50.0, 100.0), 8.0, ManagerScript.LAYER_PLAYER, 0)
	var slot: int = _fire(Vector2(200.0, 0.0))
	_mgr.set_bounce(slot, 1)
	_check(_mgr.set_self_hit(slot), "self-hit is accepted for a player's shot")
	_run(3)
	_check(_hits.is_empty() and _mgr.is_alive(slot), "it does not hit the caster it starts inside")
	_check(not _mgr.is_self_live(slot) or _mgr.get_position_of(slot).distance_to(Vector2(50.0, 100.0)) > 10.0, "and is not live while it overlaps them")
	_run(10)
	_check(_mgr.is_self_live(slot), "it goes live once it has left the caster's hitbox")
	_run(100)
	_check(_hits.size() == 1 and _hits[0][1] == caster and _hits[0][0] == 0, "and hits the caster when it comes back")
	_check(_hits[0][2].x > 50.0 and _hits[0][2].x < 70.0, "at the caster")
	_check(not _mgr.is_alive(slot), "that spends it")
	_check(not _mgr.set_self_hit(_mgr.spawn(EventsScript.NO_PLAYER, Vector2(10.0, 10.0), Vector2.ZERO, 1.0)), "an enemy shot has no caster")


func _test_ally_is_passed_once_or_hit() -> void:
	_setup()
	var friend: Node2D = _target(Vector2(100.0, 100.0), 8.0, ManagerScript.LAYER_PLAYER, 1)
	var slot: int = _fire(Vector2(200.0, 0.0), Vector2(50.0, 100.0), 2.0, 12)
	_run(30)
	_check(_passed.size() == 1 and _passed[0][0] == 0 and _passed[0][1] == friend and _passed[0][2] == 12, "a shot flying through a teammate sends ally_passed once, with its tag (%d)" % _passed.size())
	_check(_hits.is_empty() and _mgr.is_alive(slot), "and is not stopped")
	# Staying inside the friend does not repeat it.
	_setup()
	friend = _target(Vector2(100.0, 100.0), 8.0, ManagerScript.LAYER_PLAYER, 1)
	_mgr.spawn(0, Vector2(100.0, 100.0), Vector2.ZERO, 1.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 13, ManagerScript.MOTION_STILL)
	_run(20)
	_check(_passed.size() == 1, "a still shot over a teammate says it once (%d)" % _passed.size())
	# The caster's own body is not an ally.
	_setup()
	_target(Vector2(60.0, 100.0), 8.0, ManagerScript.LAYER_PLAYER, 0)
	_fire(Vector2(200.0, 0.0))
	_run(20)
	_check(_passed.is_empty(), "a shot leaving its caster passes nobody")
	# An enemy's shot hits wizards as it always did and passes nobody.
	_setup()
	_target(Vector2(100.0, 100.0), 8.0, ManagerScript.LAYER_PLAYER, 1)
	_mgr.spawn(EventsScript.NO_PLAYER, Vector2(50.0, 100.0), Vector2(200.0, 0.0), 2.0, 3.0, ManagerScript.LAYER_PLAYER, 0, 0)
	_run(30)
	_check(_passed.is_empty() and _hits.size() == 1, "enemy shots hit a wizard and pass nobody")
	# A mend shot hits the teammate.
	_setup()
	friend = _target(Vector2(100.0, 100.0), 8.0, ManagerScript.LAYER_PLAYER, 1)
	var mend: int = _fire(Vector2(200.0, 0.0), Vector2(50.0, 100.0), 2.0, 14)
	_check(_mgr.set_ally_hit(mend), "ally-hit is accepted")
	_run(30)
	_check(_hits.size() == 1 and _hits[0][1] == friend and _passed.is_empty(), "a shot that may hit teammates hits one")
	# Friendly fire hits too, and does not announce a pass.
	_setup()
	_mgr.friendly_fire = true
	friend = _target(Vector2(100.0, 100.0), 8.0, ManagerScript.LAYER_PLAYER, 1)
	_fire(Vector2(200.0, 0.0))
	_run(30)
	_check(_hits.size() == 1 and _passed.is_empty(), "with friendly fire a teammate is hit, not passed")


func _test_sticky_shot_keeps_its_direction_and_stays_stuck_at_a_wall() -> void:
	_setup()
	_target(Vector2(100.0, 100.0), 8.0)
	var slot: int = _fire(Vector2(200.0, 0.0), Vector2(50.0, 100.0), 3.0, 9)
	_mgr.set_sticky(slot, 1.0)
	_run(20)
	_check(_mgr.get_velocity_of(slot).x > 100.0, "a stuck shot still reports the way it was flying")
	# It sticks on the step it also reaches a wall: it stays, it does not bounce or end.
	_setup()
	_mgr.set_walls([Rect2(104.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	_target(Vector2(100.0, 100.0), 8.0)
	var wall_slot: int = _fire(Vector2(300.0, 0.0), Vector2(50.0, 100.0), 3.0, 8)
	_mgr.set_bounce(wall_slot, 2)
	_mgr.set_sticky(wall_slot, 1.0)
	_run(12)
	_check(_mgr.is_alive(wall_slot) and _hits.size() == 1 and _mgr.get_velocity_of(wall_slot).x > 100.0, "a shot that sticks at a wall stays stuck")


func _test_shield_catches_fast_shots_in_any_slot_order() -> void:
	# The enemy shot has a higher slot than the shield, and the shield moves toward it.
	_setup()
	var shield: int = _fire(Vector2(600.0, 0.0), Vector2(100.0, 100.0), 3.0, 5)
	_mgr.set_shield(shield, 1)
	var enemy: int = _mgr.spawn(EventsScript.NO_PLAYER, Vector2(300.0, 100.0), Vector2(-1500.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_PLAYER, 0, 0)
	_run(8)
	_check(enemy > shield and not _mgr.is_alive(enemy) and _blocked.size() == 1, "a moving shield blocks a fast shot in a higher slot")
	# And with the enemy shot in the lower slot.
	_setup()
	var first: int = _mgr.spawn(EventsScript.NO_PLAYER, Vector2(300.0, 100.0), Vector2(-1500.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_PLAYER, 0, 0)
	var second: int = _fire(Vector2(600.0, 0.0), Vector2(100.0, 100.0), 3.0, 5)
	_mgr.set_shield(second, 1)
	_run(8)
	_check(first < second and not _mgr.is_alive(first) and _blocked.size() == 1, "and a fast shot in a lower slot")


func _test_apply_travel_maps_cards_to_the_shot() -> void:
	_setup()
	var spells: SpellsScript = SpellsScript.new()
	spells.bind(_mgr, _bus)
	# A plain spell calls no setter.
	var plain_slot: int = _fire(Vector2(100.0, 0.0))
	spells._apply_travel(plain_slot, CompiledSpell.new())
	_check(_mgr.get_shield_of(plain_slot) == 0 and _mgr.get_growth_of(plain_slot) == 1.0, "a plain spell sets nothing")
	# A spell with every behaviour; the wall is passed because the shot is a ghost.
	var spell := CompiledSpell.new()
	spell.behaviours.resize(ModifierBase.Behaviour.size())
	spell.behaviours[ModifierBase.Behaviour.BOUNCE] = 1.4
	spell.behaviours[ModifierBase.Behaviour.GHOST] = 1.0
	spell.behaviours[ModifierBase.Behaviour.SPIRAL] = 20.0
	spell.behaviours[ModifierBase.Behaviour.LINGER] = 0.3
	spell.behaviours[ModifierBase.Behaviour.GROWTH] = 2.0
	spell.behaviours[ModifierBase.Behaviour.STICKY] = 0.5
	spell.behaviours[ModifierBase.Behaviour.SHIELD] = 2.6
	spell.behaviours[ModifierBase.Behaviour.RETURN] = 1.0
	_mgr.set_walls([Rect2(100.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	_mgr.set_anchor(0, Vector2(50.0, 100.0))
	var slot: int = _fire(Vector2(200.0, 0.0), Vector2(50.0, 100.0), 1.2)
	spells._apply_travel(slot, spell)
	_check(_mgr.get_shield_of(slot) == 3, "shield strength is rounded (%d)" % _mgr.get_shield_of(slot))
	_run(28)
	_check(_mgr.get_growth_of(slot) > 1.0, "the shot grows")
	_check(_mgr.is_alive(slot) and _mgr.get_position_of(slot).x > 132.0 and _mgr.get_velocity_of(slot).x > 0.0, "a ghost passes the wall without bouncing")
	_run(150)
	_check(not _mgr.is_alive(slot) and not _expired.is_empty() and _expired.back()[1].distance_to(Vector2(50.0, 100.0)) < 1.0, "a returning shot flies back to the caster")
	spells.free()
	# A bounce card: 1.4 rounds to one bounce.
	_setup()
	spells = SpellsScript.new()
	spells.bind(_mgr, _bus)
	var bouncer := CompiledSpell.new()
	bouncer.behaviours.resize(ModifierBase.Behaviour.size())
	bouncer.behaviours[ModifierBase.Behaviour.BOUNCE] = 1.4
	_mgr.set_walls([Rect2(160.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	var bounced: int = _fire(Vector2(200.0, 0.0), Vector2(50.0, 100.0), 3.0)
	spells._apply_travel(bounced, bouncer)
	_run(60)
	_check(_mgr.is_alive(bounced) and _mgr.get_velocity_of(bounced).x < 0.0, "a bounce card turns the shot at a wall")
	spells.free()


func _test_setters_refuse_bad_slots() -> void:
	_setup()
	var still: int = _mgr.spawn(0, Vector2(100.0, 100.0), Vector2.ZERO, 1.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 1, ManagerScript.MOTION_STILL)
	_mgr.set_anchor(0, Vector2(100.0, 100.0))
	var orbit: int = _mgr.spawn_orbit(0, 30.0, 0.0, 1.0, 1.0)
	var bad: bool = _mgr.set_bounce(still, 1) or _mgr.set_ghost(orbit) or _mgr.set_return(still) or _mgr.set_sticky(still, 1.0)
	_check(not bad, "travel behaviours are refused for still and orbit shots")
	_check(not (_mgr.set_bounce(-1, 1) or _mgr.set_bounce(99999, 1) or _mgr.set_linger(5, 1.0)), "and for empty or unknown slots")
	var flyer: int = _fire(Vector2(10.0, 0.0))
	_check(not (_mgr.set_bounce(flyer, -1) or _mgr.set_linger(flyer, 0.0) or _mgr.set_sticky(flyer, INF)), "bad numbers are refused")
	# A reused slot starts clean.
	_mgr.set_bounce(flyer, 3)
	_mgr.set_ghost(flyer)
	_mgr.set_growth(flyer, 2.0)
	_mgr.clear()
	var again: int = _fire(Vector2(10.0, 0.0))
	_check(is_equal_approx(_mgr.get_growth_of(again), 1.0) and _mgr.get_shield_of(again) == 0, "a fresh shot has no leftovers from the slot's last one")


func _test_many_shots_with_behaviours_stay_cheap() -> void:
	_setup()
	_mgr.set_cap(3000)
	_mgr.set_walls([Rect2(300.0, 0.0, 16.0, 360.0), Rect2(0.0, 0.0, 16.0, 360.0)] as Array[Rect2])
	for i in 40:
		_target(Vector2(100.0 + float(i % 10) * 20.0, 40.0 + float(i / 10) * 60.0), 8.0)
	_mgr.set_anchor(0, Vector2(150.0, 180.0))
	for i in 1500:
		var slot: int = _mgr.spawn(i % 4, Vector2(150.0, 20.0 + float(i % 300)), Vector2(100.0 + float(i % 7) * 40.0, float(i % 5) * 20.0 - 40.0), 4.0, 3.0, ManagerScript.LAYER_ENEMY, 2, i + 1)
		match i % 6:
			0: _mgr.set_bounce(slot, 3)
			1: _mgr.set_spiral(slot, 16.0)
			2: _mgr.set_return(slot)
			3: _mgr.set_linger(slot, 0.4)
			4: _mgr.set_growth(slot, 1.5)
			5: _mgr.set_shield(slot, 1)
	var started: int = Time.get_ticks_usec()
	for _i in 120:
		_mgr.step(DT)
	var per_step: float = float(Time.get_ticks_usec() - started) / 120.0
	# The budget (docs/PLAN.md) is a few milliseconds a frame for the whole manager; headless
	# test machines are slower, so only a gross regression fails.
	_check(per_step < 8000.0, "1,500 shots with behaviours step in %d us" % int(per_step))
