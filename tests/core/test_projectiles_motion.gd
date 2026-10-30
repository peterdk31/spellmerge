extends SceneTree
## Tests for core/projectiles, part 2: orbit shots with per-actor anchors, homing
## (turn rate, every 4th step, work budget), `homing_aim` for a beam, a card's moves on a shot
## (`move_shot`: they add up), and `ray()`.
## The manager is stepped by hand.
##
## godot --headless --path . --script res://tests/core/test_projectiles_motion.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const DT: float = 1.0 / 60.0
## How far round a shot homing looks here (the Homing card's reach).
const HOMING_REACH: float = 160.0

var _failures: Array[String] = []
var _bus: Node
var _mgr: Node2D
## Wizards at ids 0-3, seated 0-3 (the casters these tests use).
var _table: ActorSeats.ActorsScript
var _targets: Array[Node2D] = []
## Every projectile_hit as [caster, target, position, tag].
var _hits: Array = []
## Every projectile_expired as [caster, position, tag].
var _expired: Array = []
## Every projectile_impact as [target, position].
var _impacts: Array = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	_test_orbit_circles_the_anchor()
	_test_orbit_follows_each_actors_anchor()
	_test_orbit_hits_what_crosses_it_and_ignores_walls()
	_test_orbit_pierce_and_expiry()
	_test_orbit_ring_over_a_crowd()
	_test_orbit_hits_again_each_time_it_comes_round()
	_test_orbit_and_still_shots_take_the_travel_cards_they_can()
	_test_a_piercing_shot_hits_everything_it_passes_in_one_step()
	_test_homing_skips_wizards_and_freed_targets()
	_test_homing_turns_toward_a_target()
	_test_a_homing_shot_homes_after_it_bounces()
	_test_homing_rules()
	_test_a_fast_homing_shot_turns_faster()
	_test_a_guard_meets_a_small_fast_shot_between_steps()
	_test_a_homing_still_shot_creeps_toward_its_target()
	_test_homing_skips_its_own_wizard_and_the_target_just_hit()
	_test_homing_checks_every_fourth_step()
	_test_homing_search_is_charged_to_the_budget()
	_test_homing_aim_for_a_beam()
	_test_home_velocity_turns_anything_that_moves()
	_test_homing_picks_at_random_and_keeps_its_pick()
	_test_moves_on_a_shot_add_up()
	_test_ray_hits_in_order_and_reports_its_reach()
	_test_ray_width_layers_and_owner()
	_test_ray_stops_at_walls()
	_test_ray_bad_arguments()
	_test_ray_handlers_may_remove_targets_and_fire_rays()
	_test_ray_matches_brute_force()
	_teardown()
	if _failures.is_empty():
		print("TEST OK: core/projectiles motion")
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
	_table = ActorSeats.table()
	_mgr.actors = _table
	_mgr.events = _bus
	_hits.clear()
	_expired.clear()
	_impacts.clear()
	_bus.projectile_expired.connect(func(caster: int, position: Vector2, tag: int, _shot: int) -> void: _expired.append([caster, position, tag]))
	_bus.projectile_hit.connect(func(caster: int, target: Node, position: Vector2, tag: int, _shot: int) -> void: _hits.append([caster, target, position, tag]))
	_bus.projectile_impact.connect(func(_caster: int, target: Node, position: Vector2, _direction: Vector2) -> void: _impacts.append([target, position]))


func _teardown() -> void:
	for target in _targets:
		if is_instance_valid(target):
			target.free()
	_targets.clear()
	for node: Node in [_mgr, _bus, _table]:
		if node != null and is_instance_valid(node):
			node.free()
	_mgr = null
	_bus = null
	_table = null


func _target(position: Vector2, radius: float = 10.0, layer: int = ManagerScript.LAYER_ENEMY, owner: int = EventsScript.NO_PLAYER) -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	node.global_position = position
	_targets.append(node)
	_mgr.add_target(node, radius, layer, owner)
	return node


func _wall_rects() -> Array[Rect2]:
	return [Rect2(96.0, 0.0, 32.0, 200.0)]


func _test_orbit_circles_the_anchor() -> void:
	_setup()
	_check(_mgr.spawn_orbit(0, 40.0, 0.0, 3.0, 5.0) == -1, "an orbit needs an anchor first")
	_mgr.set_anchor(0, Vector2(100.0, 100.0))
	var slot: int = _mgr.spawn_orbit(0, 40.0, 0.0, 3.0, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 5)
	_check(slot >= 0 and _mgr.get_position_of(slot).is_equal_approx(Vector2(140.0, 100.0)), "it starts at the angle given, one radius from the anchor")
	var worst: float = 0.0
	for _i in 120:
		_mgr.step(DT)
		worst = maxf(worst, absf(_mgr.get_position_of(slot).distance_to(Vector2(100.0, 100.0)) - 40.0))
	_check(worst < 0.01, "it keeps its radius all the way round (%f off)" % worst)
	var expected: Vector2 = Vector2(100.0, 100.0) + Vector2.from_angle(6.0) * 40.0
	_check(_mgr.get_position_of(slot).distance_to(expected) < 0.5, "after 2 s at 3 rad/s it is 6 rad round")
	var back: int = _mgr.spawn_orbit(0, 40.0, 0.0, -3.0, 5.0)
	_mgr.step(DT)
	_check(_mgr.get_position_of(back).y < 100.0, "a negative speed turns the other way")
	_check(_mgr.spawn_orbit(ManagerScript.ACTORS, 40.0, 0.0, 3.0, 5.0) == -1 and _mgr.spawn_orbit(-1, 40.0, 0.0, 3.0, 5.0) == -1, "only an actor orbits")
	_check(_mgr.spawn_orbit(0, 40.0, 0.0, 3.0, 0.0) == -1 and _mgr.spawn_orbit(0, INF, 0.0, 3.0, 1.0) == -1, "bad numbers are refused")
	_check(_mgr.get_count() == 2, "refused orbits took no slot")


## Rules R4h: growth grows any shot (a rune's trigger circle too); on an orbit, linger stops the
## circling, spiral weaves the radius and sticky takes the shot off its circle onto what it hits; a
## still shot does not move, so linger, spiral and sticky are refused for it.
func _test_orbit_and_still_shots_take_the_travel_cards_they_can() -> void:
	_setup()
	_mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	var centre: Vector2 = Vector2(200.0, 200.0)
	_mgr.set_anchor(0, centre)
	var rune: int = _mgr.spawn(0, Vector2(400.0, 100.0), Vector2.ZERO, 5.0, 6.0, ManagerScript.LAYER_ENEMY, 0, 1, ManagerScript.MOTION_STILL)
	_check(_mgr.set_growth(rune, 2.0), "a rune takes growth")
	_check(not (_mgr.set_linger(rune, 1.0) or _mgr.set_spiral(rune, 10.0) or _mgr.set_sticky(rune, 1.0)), "a rune does not move: no linger, spiral or sticky")
	var grown: int = _mgr.spawn_orbit(0, 40.0, 0.0, 1.0, 5.0)
	_check(_mgr.set_growth(grown, 2.0), "an orbit takes growth")
	for _i in 60:
		_mgr.step(DT)
	_check(absf(_mgr.get_growth_of(rune) - 2.0) < 0.05 and absf(_mgr.get_growth_of(grown) - 2.0) < 0.05, "a rune and an orbit shot grow by the factor a second (%f, %f)" % [_mgr.get_growth_of(rune), _mgr.get_growth_of(grown)])
	_check(_mgr.get_position_of(rune).is_equal_approx(Vector2(400.0, 100.0)), "the rune stays where it is")
	# Linger: half way through its 2 s life the orbit stops turning for 1 s, still round its caster.
	var held: int = _mgr.spawn_orbit(0, 40.0, 0.0, 1.0, 2.0)
	_check(_mgr.set_linger(held, 1.0), "an orbit takes linger")
	for _i in 66:
		_mgr.step(DT)
	var angle: float = (_mgr.get_position_of(held) - centre).angle()
	_mgr.set_anchor(0, centre + Vector2(30.0, 0.0))
	for _i in 30:
		_mgr.step(DT)
	var now: Vector2 = _mgr.get_position_of(held) - centre - Vector2(30.0, 0.0)
	_check(absf(angle_difference(now.angle(), angle)) < 0.01 and absf(now.length() - 40.0) < 0.01, "a lingering orbit stops circling and keeps to its caster (%f -> %f)" % [angle, now.angle()])
	for _i in 60:
		_mgr.step(DT)
	_check(_mgr.is_alive(held) and absf(angle_difference((_mgr.get_position_of(held) - centre - Vector2(30.0, 0.0)).angle(), angle)) > 0.3, "then it circles on, its life made longer by the linger")
	_mgr.set_anchor(0, centre)
	# Spiral: the radius weaves `width` pixels (half each way) round the circle.
	var weave: int = _mgr.spawn_orbit(0, 40.0, 0.0, 1.0, 5.0)
	_check(_mgr.set_spiral(weave, 10.0), "an orbit takes spiral")
	var nearest: float = INF
	var farthest: float = 0.0
	for _i in 60:
		_mgr.step(DT)
		var reach: float = _mgr.get_position_of(weave).distance_to(centre)
		nearest = minf(nearest, reach)
		farthest = maxf(farthest, reach)
	_check(absf(nearest - 35.0) < 0.2 and absf(farthest - 45.0) < 0.2, "a spiral orbit weaves its radius 10 px (%f to %f)" % [nearest, farthest])
	# Sticky: the orbit shot that hits leaves its circle and rides its target.
	_mgr.clear()
	var foe: Node2D = _target(centre + Vector2(0.0, 40.0), 6.0)
	var sticker: int = _mgr.spawn_orbit(0, 40.0, 0.0, 2.0, 5.0)
	_check(_mgr.set_sticky(sticker, 1.0), "an orbit takes sticky")
	for _i in 60:
		_mgr.step(DT)
	_check(_hits.size() == 1 and _mgr.is_alive(sticker), "it hits once and stays (%d hits)" % _hits.size())
	var off: Vector2 = _mgr.get_position_of(sticker) - foe.global_position
	foe.global_position += Vector2(100.0, 0.0)
	for _i in 10:
		_mgr.step(DT)
	_check(off.length() < 50.0 and (_mgr.get_position_of(sticker) - foe.global_position).is_equal_approx(off) and _mgr.get_position_of(sticker).distance_to(centre) > 60.0, "a sticky orbit shot leaves its circle and rides its target")


func _test_orbit_follows_each_actors_anchor() -> void:
	_setup()
	var slots: Array[int] = []
	for p in 4:
		_mgr.set_anchor(p, Vector2(100.0 * float(p + 1), 50.0))
		slots.append(_mgr.spawn_orbit(p, 20.0, 0.0, 2.0, 5.0))
	for i in 30:
		for p in 4:
			_mgr.set_anchor(p, Vector2(100.0 * float(p + 1) + float(i), 50.0 + float(p)))
		_mgr.step(DT)
	var ok: bool = true
	for p in 4:
		var anchor := Vector2(100.0 * float(p + 1) + 29.0, 50.0 + float(p))
		ok = ok and absf(_mgr.get_position_of(slots[p]).distance_to(anchor) - 20.0) < 0.01
	_check(ok, "each actor's orbit shot circles its own, moving anchor")
	_mgr.clear_anchor(2)
	_mgr.step(DT)
	_check(not _mgr.is_alive(slots[2]) and _mgr.is_alive(slots[1]) and _mgr.is_alive(slots[3]), "clearing an anchor ends that actor's orbit shots only")
	_check(_expired.is_empty(), "and sends no expiry")
	_check(_mgr.get_count_for(2) == 0, "the owner's count follows")


func _test_orbit_hits_what_crosses_it_and_ignores_walls() -> void:
	_setup()
	_mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_mgr.set_anchor(0, Vector2(100.0, 100.0))
	var enemy: Node2D = _target(Vector2(100.0, 140.0), 8.0)
	var slot: int = _mgr.spawn_orbit(0, 40.0, 0.0, PI, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 3)
	for _i in 30:
		_mgr.step(DT)
	_check(_hits.size() == 1 and _hits[0][1] == enemy and _hits[0][3] == 3, "an orbit shot hits an enemy that stands on its circle, with its tag")
	_check(not _mgr.is_alive(slot), "and ends without pierce")
	var walls: Array[Rect2] = [Rect2(130.0, 80.0, 32.0, 40.0)]
	_mgr.set_walls(walls)
	var through: int = _mgr.spawn_orbit(0, 40.0, 0.0, 2.0, 5.0)
	_check(through >= 0, "an orbit shot can start inside a wall")
	for _i in 30:
		_mgr.step(DT)
	_check(_mgr.is_alive(through) and _mgr.wall_hits == 0, "and passes through walls")


func _test_orbit_pierce_and_expiry() -> void:
	_setup()
	_mgr.set_anchor(1, Vector2(200.0, 200.0))
	_target(Vector2(240.0, 200.0), 10.0)
	_target(Vector2(160.0, 200.0), 10.0)
	var slot: int = _mgr.spawn_orbit(1, 40.0, 0.0, 1.0, 0.5, 4.0, ManagerScript.LAYER_ENEMY, 5, 8)
	for _i in 20:
		_mgr.step(DT)
	_check(_mgr.is_alive(slot), "a piercing orbit shot survives its hits (%d)" % _hits.size())
	_check(_hits.size() == 1, "it hit the enemy it began on once, not again while it stays there (%d)" % _hits.size())
	for _i in 20:
		_mgr.step(DT)
	_check(not _mgr.is_alive(slot) and _expired.size() == 1 and _expired[0][2] == 8, "it expires at the end of its life with its tag")


func _test_orbit_ring_over_a_crowd() -> void:
	_setup()
	_mgr.set_anchor(0, Vector2(200.0, 200.0))
	# Five enemies stacked under a ring that stands still (speed 0). The rule (owner, 2026-10-29):
	# a piercing shot hits a target once while it touches it, however many it touches.
	for i in 5:
		_target(Vector2(240.0 + float(i), 200.0), 10.0)
	var slot: int = _mgr.spawn_orbit(0, 40.0, 0.0, 0.0, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 100, 1)
	for _i in 10:
		_mgr.step(DT)
	_check(_mgr.is_alive(slot), "a ring with pierce left survives a crowd")
	_check(_hits.size() == 5, "a ring standing on five enemies hits each once, not again while it stays (%d hits)" % _hits.size())
	_check(_mgr._pierce[slot] == 100 - _hits.size(), "pierce left is 100 minus the hits")
	# With no pierce it ends on its first touch, like any shot.
	_mgr.clear()
	_hits.clear()
	var thin: int = _mgr.spawn_orbit(0, 40.0, 0.0, 0.0, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 1)
	_mgr.step(DT)
	_check(not _mgr.is_alive(thin) and _hits.size() == 1, "a ring with pierce 0 ends on its first touch")


func _test_orbit_hits_again_each_time_it_comes_round() -> void:
	_setup()
	_mgr.set_anchor(0, Vector2(200.0, 200.0))
	_target(Vector2(240.0, 200.0), 6.0)
	# One turn a second; it starts on the target, so it touches it at 0, 1, 2 and 3 seconds.
	var slot: int = _mgr.spawn_orbit(0, 40.0, 0.0, TAU, 3.4, 4.0, ManagerScript.LAYER_ENEMY, 100, 1)
	for _i in 200:
		_mgr.step(DT)
	_check(_hits.size() == 4, "a ring hits a target again each time it comes round to it (%d hits)" % _hits.size())
	_check(not _mgr.is_alive(slot) or _mgr._pierce[slot] == 96, "each a hit of its own")


func _test_a_piercing_shot_hits_everything_it_passes_in_one_step() -> void:
	_setup()
	for i in 10:
		_target(Vector2(120.0 + 8.0 * i, 100.0), 3.0)
	# 120 px a step: the whole row in one step, more than the old three a step.
	var slot: int = _mgr.spawn(0, Vector2(100.0, 100.0), Vector2(7200.0, 0.0), 0.1, 2.0, ManagerScript.LAYER_ENEMY, 20, 1)
	_mgr.step(DT)
	_check(_hits.size() == 10, "all ten in the one step (%d)" % _hits.size())
	_check(_mgr.is_alive(slot), "with pierce to spare")


## The general rule (owner, 2026-10-29): a bounce turns a shot, it takes none of its cards away.
## Fired right and a little down at a wall, the shot comes no nearer than 43 px to the target on
## its way there (its homing reaches 20 px past the target's edge, 26 from its centre), and on its
## way back, further down, it passes 13 px from it: too far to hit flying straight, close enough
## to home onto it, if it still homes after the bounce.
func _test_a_homing_shot_homes_after_it_bounces() -> void:
	_setup()
	_mgr.set_walls([Rect2(100.0, 0.0, 16.0, 360.0)] as Array[Rect2])
	var enemy: Node2D = _target(Vector2(40.0, 150.0), 6.0)
	var slot: int = _mgr.spawn(0, Vector2(20.0, 100.0), Vector2(150.0, 40.0), 3.0, 3.0)
	_mgr.set_bounce(slot, 1)
	_mgr.set_homing(slot, 6.0, 20.0)
	for _i in 120:
		_mgr.step(DT)
		if not _mgr.is_alive(slot):
			break
	_check(_hits.size() == 1 and _hits[0][1] == enemy, "it bounced, then homed onto the target (%d hits)" % _hits.size())
	_hits.clear()
	var plain: int = _mgr.spawn(0, Vector2(20.0, 100.0), Vector2(150.0, 40.0), 3.0, 3.0)
	_mgr.set_bounce(plain, 1)
	for _i in 120:
		_mgr.step(DT)
	_check(_hits.is_empty(), "without homing the bounced shot flies past it")


func _test_homing_turns_toward_a_target() -> void:
	_setup()
	var enemy: Node2D = _target(Vector2(300.0, 150.0), 8.0)
	var slot: int = _mgr.spawn(0, Vector2(100.0, 100.0), Vector2(200.0, 0.0), 3.0, 4.0)
	_check(_mgr.set_homing(slot, 6.0, HOMING_REACH), "a straight shot can home")
	for _i in 120:
		_mgr.step(DT)
		if not _mgr.is_alive(slot):
			break
	_check(_hits.size() == 1 and _hits[0][1] == enemy, "a homing shot fired past a target bends and hits it")
	_hits.clear()
	_mgr.spawn(0, Vector2(100.0, 100.0), Vector2(200.0, 0.0), 3.0, 4.0)
	for _i in 120:
		_mgr.step(DT)
	_check(_hits.is_empty(), "the same shot without homing misses")


## A homing shot faster than a bolt (SpellLimits.HOMING_PACE) turns faster in step with its speed,
## so its curve is no wider than a bolt's (the owner, 2026-10-30, for the atom): five times as fast,
## five times the turn; a shot at a bolt's pace or slower turns at its rate.
func _test_a_fast_homing_shot_turns_faster() -> void:
	_check(is_equal_approx(ManagerScript.turn_at(3.0, SpellLimits.HOMING_PACE * 5.0), 15.0), "five times a bolt's pace: five times the turn")
	_check(is_equal_approx(ManagerScript.turn_at(3.0, 100.0), 3.0), "slower than a bolt: its own rate")
	_setup()
	_target(Vector2(100.0, 400.0), 8.0)
	var pace: float = SpellLimits.HOMING_PACE * 5.0
	var slot: int = _mgr.spawn(0, Vector2(0.0, 100.0), Vector2(pace, 0.0), 5.0, 2.0)
	_mgr.set_homing(slot, 0.5, 400.0)
	for _i in 4:
		_mgr.step(DT)
	var turned: float = (_mgr._vel[slot] as Vector2).angle()
	_check(turned > 0.5 * 2.0 * DT and turned <= 0.5 * 5.0 * 4.0 * DT * 1.01, "it turned faster than its rate, at most five times (%f rad)" % turned)


## A swing's or beam's guard tests a shot along its last step, not only where it is now: an atom
## (1.5 px, 1100 px/s, 18 px a step) crossing a beam's line or a swing's slice between two steps is
## met (it slipped past both before).
func _test_a_guard_meets_a_small_fast_shot_between_steps() -> void:
	_setup()
	var guard: int = _table.open(ActorSeats.ActorsScript.TEAM_ENEMIES, ActorSeats.ActorsScript.RAMP_ENEMY)
	var slot: int = _mgr.spawn(0, Vector2.ZERO, Vector2(1100.0, 0.0), 1.0, 1.5)
	_mgr.step(DT)
	_check((_mgr.get_position_of(slot) as Vector2).x > 15.0, "the atom went past the line in one step")
	_check(_mgr.shots_on_segment(guard, Vector2(9.0, -50.0), Vector2(9.0, 50.0), 1.0) == 1, "a beam's line it crossed meets it")
	_check(_mgr.shots_in_wedge(guard, Vector2(9.0, -20.0), Vector2.DOWN, 1, -0.3, 0.3, 24.0) == 1, "and so does a swing's slice it crossed")
	_check(_mgr.shots_on_segment(guard, Vector2(-9.0, -50.0), Vector2(-9.0, 50.0), 1.0) == 0, "a line behind where it came from does not")


func _test_homing_rules() -> void:
	_setup()
	_target(Vector2(100.0, 220.0), 8.0)
	var slot: int = _mgr.spawn(0, Vector2(0.0, 100.0), Vector2(100.0, 0.0), 5.0, 4.0)
	_mgr.set_homing(slot, 0.5, HOMING_REACH)
	for _i in 20:
		_mgr.step(DT)
	var velocity: Vector2 = _mgr._vel[slot]
	_check(absf(velocity.length() - 100.0) < 0.01, "homing keeps the speed")
	_check(velocity.angle() > 0.0 and velocity.angle() <= 0.5 * 20.0 * DT * 1.01, "and never turns faster than the rate (%f rad)" % velocity.angle())
	var rune: int = _mgr.spawn(0, Vector2(50.0, 50.0), Vector2.ZERO, 1.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	_mgr.set_anchor(0, Vector2(200.0, 200.0))
	var orbit: int = _mgr.spawn_orbit(0, 10.0, 0.0, 1.0, 1.0)
	_check(_mgr.set_homing(rune, 3.0, HOMING_REACH) and not _mgr.set_homing(orbit, 3.0, HOMING_REACH), "a still shot can home (it creeps), an orbit shot cannot (rules R4i)")
	_check(not _mgr.set_homing(-1, 3.0, HOMING_REACH) and not _mgr.set_homing(slot, -1.0, HOMING_REACH) and not _mgr.set_homing(slot, NAN, HOMING_REACH), "bad slots and rates are refused")
	_check(not _mgr.set_homing(slot, 3.0, 0.0) and not _mgr.set_homing(slot, 3.0, INF), "a range not above 0 and finite is refused")
	_check(_mgr.set_homing(slot, 0.0, HOMING_REACH) and _mgr._turn[slot] == 0.0, "a rate of 0 turns homing off and is accepted")
	# A reused slot does not inherit homing.
	_mgr.clear()
	var gone: int = _mgr.spawn(0, Vector2.ZERO, Vector2(1.0, 0.0), 1.0)
	_mgr.set_homing(gone, 4.0, HOMING_REACH)
	_mgr.clear()
	var again: int = _mgr.spawn(0, Vector2.ZERO, Vector2(1.0, 0.0), 1.0)
	_check(again == gone and _mgr._turn[again] == 0.0, "a reused slot starts without homing")


## A homing rune (rules R4i, owner 2026-10-30): a shot with no speed creeps toward the target its
## homing picks at SpellLimits.HOMING_DRIFT, the same pick and reach as a bolt's; with nothing
## in reach it stays put.
func _test_a_homing_still_shot_creeps_toward_its_target() -> void:
	_setup()
	var enemy: Node2D = _target(Vector2(250.0, 100.0), 8.0)
	var lone: int = _mgr.spawn(0, Vector2(100.0, 400.0), Vector2.ZERO, 30.0, 14.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	_mgr.set_homing(lone, 3.0, HOMING_REACH)
	var rune: int = _mgr.spawn(0, Vector2(100.0, 100.0), Vector2.ZERO, 30.0, 14.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	_check(_mgr.set_homing(rune, 3.0, HOMING_REACH), "a rune takes homing")
	for _i in 60:
		_mgr.step(DT)
	var moved: float = _mgr.get_position_of(rune).x - 100.0
	_check(absf(moved - SpellLimits.HOMING_DRIFT) < SpellLimits.HOMING_DRIFT * DT * ManagerScript.HOMING_PERIOD + 0.01, "it creeps toward its target at HOMING_DRIFT: %s px in a second" % moved)
	_check(is_equal_approx(_mgr.get_position_of(rune).y, 100.0), "straight at it")
	_check(_mgr.get_position_of(lone) == Vector2(100.0, 400.0), "a rune with nothing in reach stays put")
	for _i in 600:
		_mgr.step(DT)
		if not _hits.is_empty():
			break
	_check(_hits.size() == 1 and _hits[0][1] == enemy, "and reaches it")


func _test_homing_skips_its_own_wizard_and_the_target_just_hit() -> void:
	_setup()
	_target(Vector2(100.0, 130.0), 8.0, ManagerScript.LAYER_PLAYER, 0)
	var slot: int = _mgr.spawn(0, Vector2(100.0, 100.0), Vector2(100.0, 0.0), 5.0, 4.0)
	_mgr.set_homing(slot, 8.0, HOMING_REACH)
	for _i in 30:
		_mgr.step(DT)
	_check(_mgr._vel[slot].normalized().is_equal_approx(Vector2.RIGHT), "a homing shot does not turn toward its own wizard")
	_mgr.clear()
	_hits.clear()
	# The pick is random among the targets in reach, so the second starts just out of reach.
	var near: Node2D = _target(Vector2(180.0, 100.0), 8.0)
	var far: Node2D = _target(Vector2(320.0, 130.0), 8.0)
	var pierce: int = _mgr.spawn(1, Vector2(150.0, 100.0), Vector2(100.0, 0.0), 5.0, 4.0, ManagerScript.LAYER_ENEMY, 3)
	_mgr.set_homing(pierce, 8.0, HOMING_REACH)
	for _i in 150:
		_mgr.step(DT)
	var hit_near: bool = false
	var hit_far: bool = false
	for h in _hits:
		hit_near = hit_near or h[1] == near
		hit_far = hit_far or h[1] == far
	_check(hit_near and hit_far, "a piercing homing shot goes on to a second target after the first")
	_check(_hits.size() == 2, "and does not turn back to hit the first again (%d hits)" % _hits.size())


func _test_homing_checks_every_fourth_step() -> void:
	_setup()
	var slots: Array[int] = []
	for i in 8:
		slots.append(_mgr.spawn(0, Vector2(100.0, 100.0), Vector2(0.0, 0.0001), 5.0, 4.0))
		_mgr.set_homing(slots[i], 1.0, HOMING_REACH)
	_target(Vector2(150.0, 100.0), 8.0)
	var searched: Array[int] = []
	for _n in 4:
		var found: int = 0
		for s in slots:
			_mgr._home_at[s] = Vector2.INF
		_mgr.step(DT)
		for s in slots:
			if _mgr._home_at[s].is_finite():
				found += 1
		searched.append(found)
	_check(searched == [2, 2, 2, 2], "each shot searches once in four steps, and the slots take turns (%s)" % str(searched))


func _test_homing_search_is_charged_to_the_budget() -> void:
	_setup()
	for i in 20:
		_target(Vector2(300.0 + float(i), 100.0), 6.0)
	var slot: int = _mgr.spawn(0, Vector2(200.0, 100.0), Vector2(10.0, 0.0), 5.0, 4.0)
	_mgr.set_homing(slot, 1.0, HOMING_REACH)
	_mgr._refresh_targets()
	_mgr._step_index = (4 - slot % 4) % 4
	# The homing pass for this one shot, at its turn in the hit pass (`_catch_up`).
	var one := PackedInt32Array([slot])
	_mgr._catching_up = true
	_mgr._work_left = 0
	_mgr._state[slot] = ManagerScript.S_MOVING
	_mgr._pass_homing(one, 0, 1, DT)
	_check(not _mgr._home_at[slot].is_finite(), "with the budget spent a search waits")
	_mgr._work_left = 1000
	_mgr._state[slot] = ManagerScript.S_MOVING
	_mgr._pass_homing(one, 0, 1, DT)
	_mgr._catching_up = false
	_check(_mgr._home_at[slot].is_finite() and _mgr._work_left < 1000, "with budget it searches and pays for the targets it examined")


func _test_homing_aim_for_a_beam() -> void:
	_setup()
	var inside: Node2D = _target(Vector2(200.0, 130.0), 8.0)
	_target(Vector2(120.0, 0.0), 8.0)
	var aim: Vector2 = _mgr.homing_aim(0, Vector2(100.0, 100.0), Vector2.RIGHT, deg_to_rad(30.0), ManagerScript.LAYER_ENEMY, HOMING_REACH, 0, 0)
	_check(aim.is_equal_approx(Vector2(100.0, 100.0).direction_to(inside.global_position)), "a beam bends toward the nearest target inside the cone")
	aim = _mgr.homing_aim(0, Vector2(100.0, 100.0), Vector2.RIGHT, deg_to_rad(10.0), ManagerScript.LAYER_ENEMY, HOMING_REACH, 0, 0)
	_check(aim == Vector2.RIGHT, "and keeps its aim when none is that close to it")
	aim = _mgr.homing_aim(0, Vector2(100.0, 100.0), Vector2.LEFT, deg_to_rad(30.0), ManagerScript.LAYER_ENEMY, HOMING_REACH, 0, 0)
	_check(aim == Vector2.LEFT, "a target behind the aim is not chosen")
	aim = _mgr.homing_aim(0, Vector2(100.0, 100.0), Vector2.ZERO, deg_to_rad(30.0), ManagerScript.LAYER_ENEMY, HOMING_REACH, 0, 0)
	_check(aim == Vector2.ZERO, "a zero aim comes back unchanged")
	_target(Vector2(500.0, 300.0), 8.0)
	aim = _mgr.homing_aim(0, Vector2(500.0, 300.0), Vector2.RIGHT, deg_to_rad(30.0), ManagerScript.LAYER_ENEMY, HOMING_REACH, 0, 0)
	_check(aim == Vector2.RIGHT, "a target exactly on the origin is skipped, never a zero aim")
	_target(Vector2(140.0, 100.0), 8.0, ManagerScript.LAYER_PLAYER, 1)
	aim = _mgr.homing_aim(0, Vector2(100.0, 100.0), Vector2.RIGHT, deg_to_rad(30.0), ManagerScript.LAYER_ENEMY | ManagerScript.LAYER_PLAYER, HOMING_REACH, 0, 0)
	_check(aim.is_equal_approx(Vector2(100.0, 100.0).direction_to(inside.global_position)), "a beam never bends toward a wizard")
	var far: Node2D = _target(Vector2(100.0, 900.0), 8.0)
	aim = _mgr.homing_aim(0, Vector2(100.0, 650.0), Vector2.DOWN, deg_to_rad(30.0), ManagerScript.LAYER_ENEMY, HOMING_REACH, 0, 0)
	_check(aim == Vector2.DOWN, "past a homing shot's range a target is not found")
	aim = _mgr.homing_aim(0, Vector2(100.0, 650.0), Vector2.DOWN, deg_to_rad(30.0), ManagerScript.LAYER_ENEMY, 260.0, 0, 0)
	_check(aim.is_equal_approx(Vector2(100.0, 650.0).direction_to(far.global_position)), "with a longer range (a beam's length) it is")
	aim = _mgr.homing_aim(0, Vector2(100.0, 650.0), Vector2.DOWN, deg_to_rad(30.0), ManagerScript.LAYER_ENEMY, 0.0, 0, 0)
	_check(aim == Vector2.DOWN, "a zero reach finds nothing")
	var ray_len: float = _mgr.ray(0, Vector2(10.0, 600.0), Vector2.RIGHT, 1000.0)
	_check(is_equal_approx(ray_len, 1000.0), "a beam is as long as it says, however long (%f)" % ray_len)


func _test_home_velocity_turns_anything_that_moves() -> void:
	_setup()
	var target: Node2D = _target(Vector2(100.0, 200.0), 8.0)
	var from: Vector2 = Vector2(100.0, 100.0)
	var velocity: Vector2 = Vector2(200.0, 0.0)
	var turned: Vector2 = _mgr.home_velocity(0, from, velocity, 3.0, HOMING_REACH, 0.1, 0, 0)
	_check(is_equal_approx(turned.length(), 200.0), "it keeps its speed")
	_check(is_equal_approx(velocity.angle_to(turned), 0.3), "turning at most the rate for the time, toward the target (%f)" % velocity.angle_to(turned))
	_check(_mgr.home_velocity(0, from, velocity, 3.0, 50.0, 0.1, 0, 0) == velocity, "a target past its reach is not homed on")
	_check(_mgr.home_velocity(0, from, velocity, 0.0, HOMING_REACH, 0.1, 0, 0) == velocity, "a rate of 0 does not turn")
	target.global_position = Vector2(500.0, 500.0)
	_mgr.step(0.0)
	_target(Vector2(100.0, 150.0), 8.0, ManagerScript.LAYER_PLAYER, 1)
	_check(_mgr.home_velocity(0, from, velocity, 3.0, HOMING_REACH, 0.1, 0, 0) == velocity, "a wizard is never homed on")
	var slot: int = _mgr.spawn(0, Vector2(300.0, 300.0), Vector2.ZERO, 2.0, 2.0)
	_target(Vector2(420.0, 360.0), 8.0)
	_check(_mgr.move_shot(slot, Vector2(60.0, 0.0), 0.5, 3.0, HOMING_REACH), "a homing move is taken")
	for i in 30:
		_mgr.step(DT)
	_check(_mgr.get_position_of(slot).y > 300.5, "a shot's homing move turns toward the target: %s" % _mgr.get_position_of(slot))


## Rules R1e: the moves a shot is given add up while they run, each on its own time, as the
## wizard's pushes do (a later move replaced the one under way before).
func _test_moves_on_a_shot_add_up() -> void:
	_setup()
	var slot: int = _mgr.spawn(0, Vector2(300.0, 300.0), Vector2.ZERO, 2.0, 2.0)
	_mgr.move_shot(slot, Vector2(-20.0, 0.0), 0.1)
	_mgr.move_shot(slot, Vector2(20.0, 0.0), 0.1)
	for i in 12:
		_mgr.step(DT)
	_check(_mgr.get_position_of(slot).is_equal_approx(Vector2(300.0, 300.0)), "two opposite pushes cancel: %s" % _mgr.get_position_of(slot))
	_mgr.move_shot(slot, Vector2(-20.0, 0.0), 0.1)
	_mgr.step(DT)
	_mgr.move_shot(slot, Vector2(0.0, 60.0), 0.15)
	for i in 12:
		_mgr.step(DT)
	_check(_mgr.get_position_of(slot).is_equal_approx(Vector2(280.0, 360.0)), "a pull after a push gets both: %s" % _mgr.get_position_of(slot))
	_mgr.move_shot(slot, Vector2(30.0, 0.0), 0.1)
	_mgr.step(DT)
	_mgr.move_shot(slot, Vector2(0.0, -40.0), 0.0)
	for i in 12:
		_mgr.step(DT)
	_check(_mgr.get_position_of(slot).is_equal_approx(Vector2(310.0, 320.0)), "a blink keeps the move under way: %s" % _mgr.get_position_of(slot))


func _test_homing_picks_at_random_and_keeps_its_pick() -> void:
	_setup()
	var centre: Vector2 = Vector2(300.0, 300.0)
	var ids: Array[int] = []
	for offset: Vector2 in [Vector2(60.0, 0.0), Vector2(-60.0, 0.0), Vector2(0.0, 60.0), Vector2(0.0, -60.0)]:
		ids.append(_target(centre + offset, 8.0).get_instance_id())
	var far: Node2D = _target(centre + Vector2(400.0, 0.0), 8.0)
	var picked: Dictionary = {}
	for pick_seed in 32:
		_mgr.homing_point(0, centre, Vector2.RIGHT, PI, ManagerScript.LAYER_ENEMY, HOMING_REACH, 0, pick_seed)
		_check(ids.has(_mgr.homing_target), "a pick is one of the targets in reach, never the far one")
		picked[_mgr.homing_target] = true
	_check(picked.size() >= 3, "different seeds pick different targets (%d of 4)" % picked.size())
	var first: Vector2 = _mgr.homing_point(0, centre, Vector2.RIGHT, PI, ManagerScript.LAYER_ENEMY, HOMING_REACH, 0, 7)
	var kept: int = _mgr.homing_target
	_check(_mgr.homing_point(0, centre, Vector2.RIGHT, PI, ManagerScript.LAYER_ENEMY, HOMING_REACH, 0, 7) == first, "the same seed picks the same target")
	for pick_seed in 16:
		_mgr.homing_point(0, centre, Vector2.RIGHT, PI, ManagerScript.LAYER_ENEMY, HOMING_REACH, kept, pick_seed)
		_check(_mgr.homing_target == kept, "a kept target stays the pick while it is in reach")
	_mgr.homing_point(0, centre, Vector2.RIGHT, PI, ManagerScript.LAYER_ENEMY, HOMING_REACH, far.get_instance_id(), 3)
	_check(ids.has(_mgr.homing_target), "a kept target out of reach gives way to a new pick")
	for pick_seed in 32:
		_mgr.homing_point(0, centre, Vector2.RIGHT, PI, ManagerScript.LAYER_ENEMY, HOMING_REACH, 0, pick_seed, ids[0])
		_check(_mgr.homing_target != ids[0] and ids.has(_mgr.homing_target), "an avoided target is not picked while others are in reach")
	# A fan of homing shots from one point spreads over the group instead of all taking one.
	var slots: Array[int] = []
	for i in 8:
		var slot: int = _mgr.spawn(0, centre + Vector2(0.0, 120.0), Vector2(0.0, -60.0), 3.0, 2.0)
		_mgr.set_homing(slot, 0.5, HOMING_REACH)
		slots.append(slot)
	for i in ManagerScript.HOMING_PERIOD:
		_mgr.step(DT)
	var chosen: Dictionary = {}
	for slot in slots:
		if _mgr._home_target[slot] != 0:
			chosen[_mgr._home_target[slot]] = true
	_check(chosen.size() >= 2, "eight shots home on more than one target (%d)" % chosen.size())


func _test_homing_skips_wizards_and_freed_targets() -> void:
	_setup()
	_target(Vector2(300.0, 160.0), 8.0, ManagerScript.LAYER_PLAYER, 1)
	var gone: Node2D = _target(Vector2(300.0, 40.0), 8.0)
	var slot: int = _mgr.spawn(0, Vector2(100.0, 100.0), Vector2(100.0, 0.0), 5.0, 4.0)
	_mgr.set_homing(slot, 3.0, HOMING_REACH)
	_mgr._refresh_targets()
	gone.free()
	_check(not _mgr._homing_point(slot, _mgr.get_position_of(slot)).is_finite(), "homing neither picks another wizard (though it would hit one) nor a freed target")


func _test_ray_hits_in_order_and_reports_its_reach() -> void:
	_setup()
	var c: Node2D = _target(Vector2(300.0, 100.0))
	var a: Node2D = _target(Vector2(120.0, 104.0))
	var b: Node2D = _target(Vector2(200.0, 96.0))
	_target(Vector2(250.0, 160.0))
	var reach: float = _mgr.ray(0, Vector2(50.0, 100.0), Vector2.RIGHT, 400.0, 0, ManagerScript.LAYER_ENEMY, 6)
	_check(_hits.size() == 1 and _hits[0][1] == a and _hits[0][3] == 6, "a ray without pierce hits only the nearest target, with the tag")
	_check(absf(reach - 70.0) < 0.01, "and stops there (%f)" % reach)
	_hits.clear()
	reach = _mgr.ray(0, Vector2(50.0, 100.0), Vector2.RIGHT, 400.0, 2)
	_check(_hits.size() == 3 and _hits[0][1] == a and _hits[1][1] == b and _hits[2][1] == c, "pierce 2 hits three in the order along the beam")
	_check(absf(reach - 250.0) < 0.01, "and reaches the third (%f)" % reach)
	_check(_hits.size() == 3 and _hits[0][2].is_equal_approx(Vector2(120.0, 100.0)), "the hit point is where the beam passes closest")
	_hits.clear()
	reach = _mgr.ray(0, Vector2(50.0, 100.0), Vector2.RIGHT, 300.0, 10)
	_check(_hits.size() == 3 and absf(reach - 300.0) < 0.001, "a ray with pierce to spare, and nothing more to hit, reaches its full length")
	_hits.clear()
	reach = _mgr.ray(0, Vector2(50.0, 100.0), Vector2.RIGHT * 7.0, 150.0, 5)
	_check(_hits.size() == 2 and absf(reach - 150.0) < 0.001, "a non-unit direction is normalised; targets past the length are not hit")
	_check(_mgr.get_count() == 0, "a ray holds no row in the pool")


func _test_ray_width_layers_and_owner() -> void:
	_setup()
	var off: Node2D = _target(Vector2(200.0, 125.0), 10.0)
	_mgr.ray(0, Vector2(50.0, 100.0), Vector2.RIGHT, 400.0, 3)
	_check(_hits.is_empty(), "a target 25 px off a thin beam is missed")
	_mgr.ray(0, Vector2(50.0, 100.0), Vector2.RIGHT, 400.0, 3, ManagerScript.LAYER_ENEMY, 0, 20.0)
	_check(_hits.size() == 1 and _hits[0][1] == off, "a wide beam reaches it")
	_hits.clear()
	var wizard: Node2D = _target(Vector2(100.0, 100.0), 8.0, ManagerScript.LAYER_PLAYER, 0)
	_mgr.ray(0, Vector2(50.0, 100.0), Vector2.RIGHT, 400.0, 3, ManagerScript.LAYER_PLAYER)
	_check(_hits.is_empty(), "a beam never hits its own wizard")
	_mgr.ray(1, Vector2(50.0, 100.0), Vector2.RIGHT, 400.0, 3)
	_check(_hits.size() == 1 and _hits[0][1] == wizard, "a teammate's beam hits the wizard, though it asked for enemies (G3c)")
	_hits.clear()
	_target(Vector2(300.0, 100.0))
	_mgr.ray(EventsScript.NO_PLAYER, Vector2(50.0, 100.0), Vector2.RIGHT, 400.0, 3, ManagerScript.LAYER_PLAYER)
	_check(_hits.size() == 2, "a beam of no actor hits the wizard and the enemy (%d)" % _hits.size())


func _test_ray_stops_at_walls() -> void:
	_setup()
	_mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_mgr.set_walls(_wall_rects())
	var before: Node2D = _target(Vector2(80.0, 100.0))
	_target(Vector2(200.0, 100.0))
	var reach: float = _mgr.ray(0, Vector2(40.0, 100.0), Vector2.RIGHT, 400.0, 5)
	_check(absf(reach - 56.0) < 0.01, "the beam ends at the wall (%f)" % reach)
	_check(_hits.size() == 1 and _hits[0][1] == before, "it hits what is in front of the wall, not behind it")
	_check(_impacts.size() == 2 and _impacts[1][0] == null and _impacts[1][1].is_equal_approx(Vector2(96.0, 100.0)), "and sends a wall impact where it ends")
	_check(_mgr.wall_hits == 0, "wall_hits counts shots, not beams")
	_check(_mgr.ray(0, Vector2(100.0, 100.0), Vector2.RIGHT, 400.0, 5) == 0.0, "a beam that starts in a wall gets nowhere")


func _test_ray_bad_arguments() -> void:
	_setup()
	_target(Vector2(100.0, 100.0))
	_check(_mgr.ray(0, Vector2(0.0, 100.0), Vector2.ZERO, 100.0) == 0.0, "no direction")
	_check(_mgr.ray(0, Vector2(0.0, 100.0), Vector2.RIGHT, 0.0) == 0.0, "no length")
	_check(_mgr.ray(0, Vector2(0.0, 100.0), Vector2.RIGHT, NAN) == 0.0, "NaN length")
	_check(_mgr.ray(0, Vector2.INF, Vector2.RIGHT, 100.0) == 0.0, "infinite origin")
	_check(_mgr.ray(ManagerScript.ACTORS, Vector2(0.0, 100.0), Vector2.RIGHT, 100.0) == 0.0, "bad caster")
	_check(_hits.is_empty(), "none of them hit anything")
	_check(absf(_mgr.ray(0, Vector2(0.0, 100.0), Vector2.RIGHT, 50.0, -3) - 50.0) < 0.001, "a negative pierce counts as 0")


func _test_ray_handlers_may_remove_targets_and_fire_rays() -> void:
	_setup()
	var a: Node2D = _target(Vector2(100.0, 100.0))
	var b: Node2D = _target(Vector2(150.0, 100.0))
	var seen: Array[Node] = []
	var nested: Array[float] = []
	var doomed: Array[Node2D] = [b]
	_bus.projectile_hit.connect(func(_p: int, target: Node, _at: Vector2, tag: int, _shot: int) -> void:
		seen.append(target)
		if target == a and is_instance_valid(doomed[0]):
			_mgr.remove_target(doomed[0])
			doomed[0].free()
		if tag == 1:
			nested.append(_mgr.ray(0, Vector2(0.0, 300.0), Vector2.RIGHT, 100.0, 1, ManagerScript.LAYER_ENEMY, 2)))
	_target(Vector2(50.0, 300.0))
	_mgr.ray(0, Vector2(0.0, 100.0), Vector2.RIGHT, 300.0, 3, ManagerScript.LAYER_ENEMY, 0)
	_check(seen.size() == 1 and seen[0] == a, "a target freed by an earlier hit's handler is skipped, not sent")
	seen.clear()
	_mgr.ray(0, Vector2(0.0, 300.0), Vector2.RIGHT, 100.0, 1, ManagerScript.LAYER_ENEMY, 1)
	_check(nested.size() == 1 and nested[0] > 0.0 and seen.size() == 2, "a handler may fire another ray (%s)" % str(nested))
	_check(_mgr._ray_depth == 0, "the nesting count is back to 0")


func _test_ray_matches_brute_force() -> void:
	_setup()
	_mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var radii: Array[float] = []
	for i in 120:
		var radius: float = rng.randf_range(4.0, 16.0)
		radii.append(radius)
		_target(Vector2(rng.randf_range(0.0, 640.0), rng.randf_range(0.0, 360.0)), radius)
	_mgr.step(DT)
	var wrong: int = 0
	var skipped: int = 0
	for _q in 100:
		var origin := Vector2(rng.randf_range(0.0, 640.0), rng.randf_range(0.0, 360.0))
		var dir: Vector2 = Vector2.from_angle(rng.randf_range(0.0, TAU))
		var length: float = rng.randf_range(20.0, 500.0)
		var width: float = rng.randf_range(0.0, 12.0)
		var pierce: int = rng.randi_range(0, 4)
		var expected: Array = []
		for i in _targets.size():
			var along: float = clampf((_targets[i].global_position - origin).dot(dir), 0.0, length)
			if (origin + dir * along).distance_to(_targets[i].global_position) <= width + radii[i]:
				expected.append([along, _targets[i]])
		expected.sort_custom(func(l: Array, r: Array) -> bool: return l[0] < r[0])
		# Targets level with the beam's start or each other tie: either order is right.
		var tied: bool = false
		for i in mini(expected.size() - 1, pierce + 1):
			tied = tied or absf(expected[i + 1][0] - expected[i][0]) < 0.001
		if tied:
			skipped += 1
			continue
		expected = expected.slice(0, pierce + 1)
		_hits.clear()
		var reach: float = _mgr.ray(0, origin, dir, length, pierce, ManagerScript.LAYER_ENEMY, 0, width)
		if _hits.size() != expected.size():
			wrong += 1
			continue
		for i in expected.size():
			if _hits[i][1] != expected[i][1]:
				wrong += 1
				break
		if expected.size() == pierce + 1 and absf(reach - expected[-1][0]) > 0.01:
			wrong += 1
	_check(skipped < 30, "few random beams are skipped for ties (%d)" % skipped)
	_check(wrong == 0, "random beams agree with a brute-force search (%d differ)" % wrong)
