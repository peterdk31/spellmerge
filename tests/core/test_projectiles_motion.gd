extends "res://tests/support/suite.gd"
## Tests for core/projectiles, part 2, one behaviour each: orbit shots (`set_orbit`: what it takes,
## its turn by speed and drift, a speed curve on it, per-actor anchors, its hits, walls and the
## travel cards it takes), homing (turn rate and curve, after a bounce, a homing rune, whom it
## skips, every 4th step, the work budget, the random pick it keeps), `homing_aim` for a beam,
## `home_velocity`, a card's moves on a shot (`move_shot`: they add up), a guard's test along a
## shot's last step, and `ray()` (order, reach, width, layers, its caster, walls, handlers, a
## brute-force check).
##
## Each test gets a fresh manager with an event bus and a table of four wizards at ids 0-3
## (`before_each`); the manager is stepped by hand.
##
## godot --headless --path . --script res://tests/support/run.gd -- res://tests/core/test_projectiles_motion.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const OrbitShot := preload("res://tests/support/orbit_shot.gd")

const DT: float = 1.0 / 60.0
## How far round a shot homing looks here (the Homing card's reach).
const HOMING_REACH: float = 160.0
const ROOM: Rect2 = Rect2(0.0, 0.0, 640.0, 360.0)
## The anchor or centre most orbit tests circle.
const CENTRE: Vector2 = Vector2(300.0, 300.0)
## The anchor the travel-card orbits circle.
const ORBIT_CENTRE: Vector2 = Vector2(200.0, 200.0)
## Where the `homing_aim` tests aim from.
const AIM_FROM: Vector2 = Vector2(100.0, 100.0)
## Where the `home_velocity` tests home from, and at what velocity.
const HOME_FROM: Vector2 = Vector2(100.0, 100.0)
const HOME_VELOCITY: Vector2 = Vector2(200.0, 0.0)
## Where most ray tests cast from.
const RAY_FROM: Vector2 = Vector2(50.0, 100.0)

var bus: EventsScript
var mgr: ManagerScript
## Wizards at ids 0-3, seated 0-3 (the casters these tests use).
var table: ActorSeats.ActorsScript
## Every projectile_hit as [caster, target, position, tag].
var hits: Array = []
## Every projectile_expired as [caster, position, tag].
var expired: Array = []
## Every projectile_impact as [target, position].
var impacts: Array = []
## The targets made by `_target`, in order.
var targets: Array[Node2D] = []


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	table = own(ActorSeats.table()) as ActorSeats.ActorsScript
	mgr.actors = table
	mgr.events = bus
	hits.clear()
	expired.clear()
	impacts.clear()
	targets.clear()
	bus.projectile_expired.connect(func(caster: int, position: Vector2, tag: int, _shot: int) -> void: expired.append([caster, position, tag]))
	bus.projectile_hit.connect(func(caster: int, target: Node, position: Vector2, tag: int, _shot: int) -> void: hits.append([caster, target, position, tag]))
	bus.projectile_impact.connect(func(_caster: int, target: Node, position: Vector2, _direction: Vector2) -> void: impacts.append([target, position]))


func _target(position: Vector2, radius: float = 10.0, layer: int = ManagerScript.LAYER_ENEMY, owner: int = EventsScript.NO_PLAYER) -> Node2D:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.global_position = position
	targets.append(node)
	mgr.add_target(node, radius, layer, owner)
	return node


func _run(steps: int) -> void:
	for _i in steps:
		mgr.step(DT)


func _hit(target: Node2D) -> bool:
	for hit: Array in hits:
		if hit[1] == target:
			return true
	return false


## The angle round CENTRE the shot in `slot` is at.
func _angle_of(slot: int) -> float:
	return (mgr.get_position_of(slot) - CENTRE).angle()


# --- Orbits round an anchor ----------------------------------------------------------------


func test_an_orbit_needs_an_anchor() -> void:
	check_equal(OrbitShot.start(mgr, 0, 40.0, 0.0, 3.0, 5.0), -1, "an orbit needs an anchor first")


## An orbit of seat 0 round (100, 100), 40 px out from angle 0, at 3 rad/s; its slot.
func _an_orbit_at_3_rad_s() -> int:
	mgr.set_anchor(0, Vector2(100.0, 100.0))
	return OrbitShot.start(mgr, 0, 40.0, 0.0, 3.0, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 5)


func test_an_orbit_starts_at_its_angle_one_radius_from_the_anchor() -> void:
	var slot: int = _an_orbit_at_3_rad_s()
	check(slot >= 0 and mgr.get_position_of(slot).is_equal_approx(Vector2(140.0, 100.0)), "it starts at the angle given, one radius from the anchor")


func test_an_orbit_keeps_its_radius_all_the_way_round() -> void:
	var slot: int = _an_orbit_at_3_rad_s()
	var worst: float = 0.0
	for _i in 120:
		mgr.step(DT)
		worst = maxf(worst, absf(mgr.get_position_of(slot).distance_to(Vector2(100.0, 100.0)) - 40.0))
	check(worst < 0.01, "it keeps its radius all the way round (%f off)" % worst)


func test_an_orbit_turns_at_its_speed() -> void:
	var slot: int = _an_orbit_at_3_rad_s()
	_run(120)
	var expected: Vector2 = Vector2(100.0, 100.0) + Vector2.from_angle(6.0) * 40.0
	check(mgr.get_position_of(slot).distance_to(expected) < 0.5, "after 2 s at 3 rad/s it is 6 rad round")


func test_a_negative_orbit_speed_turns_the_other_way() -> void:
	mgr.set_anchor(0, Vector2(100.0, 100.0))
	var back: int = OrbitShot.start(mgr, 0, 40.0, 0.0, -3.0, 5.0)
	mgr.step(DT)
	check(mgr.get_position_of(back).y < 100.0, "a negative speed turns the other way")


func test_only_an_actors_shot_circles_an_anchor() -> void:
	mgr.set_anchor(0, Vector2(100.0, 100.0))
	check(OrbitShot.start(mgr, ManagerScript.ACTORS, 40.0, 0.0, 3.0, 5.0) == -1 and OrbitShot.start(mgr, -1, 40.0, 0.0, 3.0, 5.0) == -1, "only an actor's shot circles an anchor")
	check_equal(mgr.get_count(), 0, "refused orbits took no slot")


func test_an_orbit_with_bad_numbers_is_refused() -> void:
	mgr.set_anchor(0, Vector2(100.0, 100.0))
	check(OrbitShot.start(mgr, 0, 40.0, 0.0, 3.0, 0.0) == -1 and OrbitShot.start(mgr, 0, INF, 0.0, 3.0, 1.0) == -1, "bad numbers are refused")
	check_equal(mgr.get_count(), 0, "refused orbits took no slot")


# --- set_orbit -----------------------------------------------------------------------------


## `set_orbit` turns a live straight shot onto its circle, and only that: a shot already circling,
## an empty slot, bad numbers and a shot with no centre (no `centre` given and no anchor for its
## actor) are refused, and the shot is left as it was.
func _a_bolt_of_seat_1() -> int:
	return mgr.spawn(1, Vector2(50.0, 50.0), Vector2(100.0, 0.0), 5.0)


func test_set_orbit_with_no_centre_is_refused_and_leaves_the_shot() -> void:
	var bolt: int = _a_bolt_of_seat_1()
	check(not mgr.set_orbit(bolt, 30.0, 0.0, 1.0), "no anchor for its actor and no centre: refused")
	check(mgr._motion[bolt] == ManagerScript.MOTION_STRAIGHT and mgr.get_position_of(bolt) == Vector2(50.0, 50.0) and mgr.get_velocity_of(bolt) == Vector2(100.0, 0.0), "and the shot is left as it was")


func test_set_orbit_refuses_bad_numbers() -> void:
	var bolt: int = _a_bolt_of_seat_1()
	check(not (mgr.set_orbit(bolt, INF, 0.0, 1.0, Vector2.ZERO) or mgr.set_orbit(bolt, 30.0, NAN, 1.0, Vector2.ZERO) or mgr.set_orbit(bolt, 30.0, 0.0, INF, Vector2.ZERO)), "bad numbers are refused")


func test_set_orbit_refuses_a_slot_that_is_no_live_shot() -> void:
	check(not (mgr.set_orbit(-1, 30.0, 0.0, 1.0, Vector2.ZERO) or mgr.set_orbit(mgr._cap, 30.0, 0.0, 1.0, Vector2.ZERO)), "a slot that is no live shot is refused")


## A still shot circles too (5B), keeping its quad body: a rune, by its drift alone (no speed).
func test_a_still_shot_circles_keeping_its_runes_body() -> void:
	var rune: int = mgr.spawn(1, Vector2(80.0, 50.0), Vector2.ZERO, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	check(mgr.set_orbit(rune, 30.0, 0.0, 1.0, Vector2(100.0, 100.0)) and mgr._motion[rune] == ManagerScript.MOTION_ORBIT, "a still shot circles")
	check(mgr._kind_of(rune) == ManagerScript.KIND_RUNE and mgr.mesh_of(rune) == ManagerScript.MESH_QUAD, "and keeps its rune's body")


func test_a_straight_shot_circles_a_centre_given() -> void:
	var bolt: int = _a_bolt_of_seat_1()
	check(mgr.set_orbit(bolt, 30.0, 0.0, 1.0, Vector2(200.0, 200.0)), "a straight shot circles a centre given")
	check(mgr._motion[bolt] == ManagerScript.MOTION_ORBIT and mgr.get_position_of(bolt).is_equal_approx(Vector2(230.0, 200.0)), "on the circle at its angle")


func test_set_orbit_refuses_a_shot_already_circling() -> void:
	var bolt: int = _a_bolt_of_seat_1()
	mgr.set_orbit(bolt, 30.0, 0.0, 1.0, Vector2(200.0, 200.0))
	check(not mgr.set_orbit(bolt, 30.0, 0.0, 1.0, Vector2(200.0, 200.0)), "a shot already circling is refused")


func test_with_an_anchor_its_actors_body_is_the_centre() -> void:
	mgr.set_anchor(1, Vector2(300.0, 300.0))
	var other: int = _a_bolt_of_seat_1()
	check(mgr.set_orbit(other, 20.0, PI * 0.5, 1.0) and mgr.get_position_of(other).is_equal_approx(Vector2(300.0, 320.0)), "with an anchor its actor's body is the centre")


func test_a_shot_of_no_actor_circles_only_a_point_given() -> void:
	var nobody: int = mgr.spawn(EventsScript.NO_PLAYER, Vector2(50.0, 50.0), Vector2(100.0, 0.0), 5.0)
	check(not mgr.set_orbit(nobody, 20.0, 0.0, 1.0), "a shot of no actor has no anchor to circle")
	check(mgr.set_orbit(nobody, 20.0, 0.0, 1.0, Vector2(400.0, 100.0)), "but circles a point given")


## Its turn is its speed over its radius plus its drift (`_orbit_turn`): a faster shot goes round
## faster, one with no speed turns by its drift only, and its velocity is the tangent at that turn.
## Five shots of seat 0 on 40 px circles round CENTRE, `steps` steps on: slow (40 px/s), fast
## (80 px/s, fired up), drifting (40 px/s and a drift of 0.5), still (no speed, a drift of a third
## of a turn a second) and against (40 px/s against a drift of -1).
func _five_orbits(steps: int) -> Dictionary:
	mgr.set_anchor(0, CENTRE)
	var slots: Dictionary = {
		"slow": mgr.spawn(0, Vector2(10.0, 10.0), Vector2(40.0, 0.0), 5.0),
		"fast": mgr.spawn(0, Vector2(10.0, 10.0), Vector2(0.0, -80.0), 5.0),
		"drifting": mgr.spawn(0, Vector2(10.0, 10.0), Vector2(40.0, 0.0), 5.0),
		"still": mgr.spawn(0, Vector2(10.0, 10.0), Vector2.ZERO, 5.0),
		"against": mgr.spawn(0, Vector2(10.0, 10.0), Vector2(40.0, 0.0), 5.0),
	}
	mgr.set_orbit(slots["slow"], 40.0, 0.0, 0.0)
	mgr.set_orbit(slots["fast"], 40.0, 0.0, 0.0)
	mgr.set_orbit(slots["drifting"], 40.0, 0.0, 0.5)
	mgr.set_orbit(slots["still"], 40.0, 0.0, TAU / 3.0)
	mgr.set_orbit(slots["against"], 40.0, 0.0, -1.0)
	_run(steps)
	return slots


func test_an_orbits_velocity_is_the_tangent_at_its_speed() -> void:
	var fast: int = _five_orbits(0)["fast"]
	check(mgr.get_velocity_of(fast).distance_to(Vector2(0.0, 80.0)) < 0.001, "its velocity is the tangent, at its speed, whichever way it flew (%s)" % mgr.get_velocity_of(fast))


func test_an_orbit_turns_its_speed_over_its_radius() -> void:
	var slots: Dictionary = _five_orbits(60)
	check(absf(_angle_of(slots["slow"]) - 1.0) < 0.001, "40 px/s on a 40 px circle turns 1 rad a second (%f)" % _angle_of(slots["slow"]))
	check(absf(_angle_of(slots["fast"]) - 2.0) < 0.001, "twice as fast turns twice as far (%f)" % _angle_of(slots["fast"]))


func test_an_orbits_drift_adds_to_its_speeds_turn() -> void:
	var slots: Dictionary = _five_orbits(60)
	check(absf(_angle_of(slots["drifting"]) - 1.5) < 0.001, "a drift adds to its speed's turn (%f)" % _angle_of(slots["drifting"]))


func test_an_orbit_with_no_speed_turns_by_its_drift_alone() -> void:
	var slots: Dictionary = _five_orbits(60)
	check(absf(_angle_of(slots["still"]) - TAU / 3.0) < 0.001, "with no speed it turns by its drift alone: a third of a turn (%f)" % _angle_of(slots["still"]))


func test_a_drift_against_an_orbits_speed_holds_it_still() -> void:
	var against: int = _five_orbits(60)["against"]
	check(absf(_angle_of(against)) < 0.001 and mgr.get_velocity_of(against).length() < 0.001, "a drift against its speed holds it still (%f)" % _angle_of(against))


func test_an_orbits_velocity_stays_the_tangent_at_its_turn() -> void:
	var slots: Dictionary = _five_orbits(60)
	check(is_equal_approx(mgr.get_velocity_of(slots["fast"]).length(), 80.0), "a shot with speed keeps it (%s)" % mgr.get_velocity_of(slots["fast"]))
	var tangent: Vector2 = Vector2.from_angle(TAU / 3.0).orthogonal() * (-40.0 * TAU / 3.0)
	check(mgr.get_velocity_of(slots["still"]).distance_to(tangent) < 0.01, "its velocity stays the tangent at its turn (%s)" % mgr.get_velocity_of(slots["still"]))


func test_every_orbit_keeps_its_radius_whatever_its_turn() -> void:
	var slots: Dictionary = _five_orbits(60)
	for key: String in slots:
		check(absf(mgr.get_position_of(slots[key]).distance_to(CENTRE) - 40.0) < 0.01, "the %s orbit keeps its radius" % key)


## A speed curve (`set_speed_curve`, before or after `set_orbit`) changes the turn over the shot's
## life: from 2x its speed to 0 at an ease of 1, a 1 rad/s orbit of 2 s turns 1.5 rad in its first
## second and 0.375 rad in the next half (the curve read at each step's middle, so exact for a line).
## Two such orbits of seat 0 round CENTRE, the curve set before and after; their slots.
func _two_curved_orbits() -> Vector2i:
	mgr.set_anchor(0, CENTRE)
	var before: int = mgr.spawn(0, Vector2(10.0, 10.0), Vector2(40.0, 0.0), 2.0)
	check(mgr.set_speed_curve(before, 2.0, 0.0, 1.0), "a curve on the straight shot")
	check(mgr.set_orbit(before, 40.0, 0.0, 0.0), "then the orbit")
	var after: int = mgr.spawn(0, Vector2(10.0, 10.0), Vector2(40.0, 0.0), 2.0)
	check(mgr.set_orbit(after, 40.0, 0.0, 0.0), "the orbit first")
	check(mgr.set_speed_curve(after, 2.0, 0.0, 1.0), "then a curve on the circling shot")
	_run(60)
	return Vector2i(before, after)


func test_a_speed_curve_changes_an_orbits_turn_in_its_first_second() -> void:
	var slots: Vector2i = _two_curved_orbits()
	check(absf(_angle_of(slots.x) - 1.5) < 0.001, "it turned 1.5 rad in its first second (%f)" % _angle_of(slots.x))


func test_a_speed_curve_set_before_or_after_the_orbit_turns_it_alike() -> void:
	var slots: Vector2i = _two_curved_orbits()
	check(absf(_angle_of(slots.y) - _angle_of(slots.x)) < 0.0001, "the same, the curve set before or after")


func test_a_speed_curve_slows_an_orbit_later_in_its_life() -> void:
	var slots: Vector2i = _two_curved_orbits()
	var at_one: float = _angle_of(slots.x)
	_run(30)
	var later: float = _angle_of(slots.x) - at_one
	check(absf(later - 0.375) < 0.001, "0.375 rad in the next half second, slowing (%f)" % later)


# --- Orbits and walls ----------------------------------------------------------------------


## No special rule keeps a circling shot from walls (orbit as a modifier, 5A): it is not born inside
## one, a room wall across its circle ends it as any shot, and a ghost one passes. Seat 0 anchored at
## (100, 100), a wall across the right of its 40 px circle.
func _an_anchor_by_a_wall() -> void:
	mgr.set_bounds(ROOM)
	mgr.set_anchor(0, Vector2(100.0, 100.0))
	mgr.set_walls([Rect2(130.0, 80.0, 32.0, 40.0)] as Array[Rect2])


func test_an_orbit_is_not_born_inside_a_wall() -> void:
	_an_anchor_by_a_wall()
	check_equal(OrbitShot.start(mgr, 0, 40.0, 0.0, 2.0, 5.0), -1, "an orbit shot is not born inside a wall")


func test_a_wall_across_its_circle_ends_an_orbit() -> void:
	_an_anchor_by_a_wall()
	# From the far side of the circle, turning 2 rad/s, it reaches the wall at about -0.52 rad (1.3 s).
	var walled: int = OrbitShot.start(mgr, 0, 40.0, PI, 2.0, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 6)
	check(walled >= 0, "it starts outside the wall")
	_run(70)
	check(mgr.is_alive(walled), "it circles until it reaches the wall")
	_run(30)
	check(not mgr.is_alive(walled) and mgr.wall_hits == 1, "the wall ends it (%d wall hits)" % mgr.wall_hits)
	check(expired.size() == 1 and expired[0][2] == 6 and absf((expired[0][1] as Vector2).y - 80.0) < 1.0, "with its expiry, on the wall's top face (%s)" % str(expired))


func test_a_ghost_orbit_circles_on_through_a_wall() -> void:
	_an_anchor_by_a_wall()
	var ghost: int = OrbitShot.start(mgr, 0, 40.0, PI, 2.0, 5.0)
	check(ghost >= 0 and mgr.set_ghost(ghost), "a circling shot takes ghost")
	_run(160)
	check(mgr.is_alive(ghost) and absf(mgr.get_position_of(ghost).distance_to(Vector2(100.0, 100.0)) - 40.0) < 0.01, "a ghost one circles on through it")
	check_equal(mgr.wall_hits, 0, "it met no wall")


# --- Travel cards on orbits and runes ------------------------------------------------------


## Rules R4h: growth grows any shot (a rune's trigger circle too); on an orbit, linger stops the
## circling, spiral weaves the radius and sticky takes the shot off its circle onto what it hits; a
## still shot does not move, so linger, spiral and sticky are refused for it. Seat 0 anchored at
## ORBIT_CENTRE in the room.
func _an_anchor_in_the_room() -> void:
	mgr.set_bounds(ROOM)
	mgr.set_anchor(0, ORBIT_CENTRE)


func _a_rune() -> int:
	return mgr.spawn(0, Vector2(400.0, 100.0), Vector2.ZERO, 5.0, 6.0, ManagerScript.LAYER_ENEMY, 0, 1, ManagerScript.MOTION_STILL)


func test_a_rune_grows_by_its_factor_where_it_stands() -> void:
	_an_anchor_in_the_room()
	var rune: int = _a_rune()
	check(mgr.set_growth(rune, 2.0), "a rune takes growth")
	_run(60)
	check(absf(mgr.get_growth_of(rune) - 2.0) < 0.05, "a rune grows by the factor a second (%f)" % mgr.get_growth_of(rune))
	check(mgr.get_position_of(rune).is_equal_approx(Vector2(400.0, 100.0)), "the rune stays where it is")


func test_a_rune_refuses_linger_spiral_and_sticky() -> void:
	var rune: int = _a_rune()
	check(not (mgr.set_linger(rune, 1.0) or mgr.set_spiral(rune, 10.0) or mgr.set_sticky(rune, 1.0)), "a rune does not move: no linger, spiral or sticky")


func test_an_orbit_grows_by_its_factor() -> void:
	_an_anchor_in_the_room()
	var grown: int = OrbitShot.start(mgr, 0, 40.0, 0.0, 1.0, 5.0)
	check(mgr.set_growth(grown, 2.0), "an orbit takes growth")
	_run(60)
	check(absf(mgr.get_growth_of(grown) - 2.0) < 0.05, "an orbit shot grows by the factor a second (%f)" % mgr.get_growth_of(grown))


## Linger: half way through its 2 s life the orbit stops turning for 1 s, still round its caster.
## A lingering orbit 66 steps on, then its caster 30 px to the right; its slot and the angle it
## stopped at.
func _a_lingering_orbit() -> Array:
	_an_anchor_in_the_room()
	var held: int = OrbitShot.start(mgr, 0, 40.0, 0.0, 1.0, 2.0)
	check(mgr.set_linger(held, 1.0), "an orbit takes linger")
	_run(66)
	var angle: float = (mgr.get_position_of(held) - ORBIT_CENTRE).angle()
	mgr.set_anchor(0, ORBIT_CENTRE + Vector2(30.0, 0.0))
	return [held, angle]


func test_a_lingering_orbit_stops_circling_and_keeps_to_its_caster() -> void:
	var held: Array = _a_lingering_orbit()
	_run(30)
	var now: Vector2 = mgr.get_position_of(held[0]) - ORBIT_CENTRE - Vector2(30.0, 0.0)
	check(absf(angle_difference(now.angle(), held[1])) < 0.01 and absf(now.length() - 40.0) < 0.01, "a lingering orbit stops circling and keeps to its caster (%f -> %f)" % [held[1], now.angle()])


func test_a_lingering_orbit_circles_on_after_its_stop() -> void:
	var held: Array = _a_lingering_orbit()
	_run(90)
	var now: Vector2 = mgr.get_position_of(held[0]) - ORBIT_CENTRE - Vector2(30.0, 0.0)
	check(mgr.is_alive(held[0]) and absf(angle_difference(now.angle(), held[1])) > 0.3, "then it circles on, its life made longer by the linger")


## Spiral: the radius weaves `width` pixels (half each way) round the circle.
func test_a_spiral_orbit_weaves_its_radius() -> void:
	_an_anchor_in_the_room()
	var weave: int = OrbitShot.start(mgr, 0, 40.0, 0.0, 1.0, 5.0)
	check(mgr.set_spiral(weave, 10.0), "an orbit takes spiral")
	var nearest: float = INF
	var farthest: float = 0.0
	for _i in 60:
		mgr.step(DT)
		var reach: float = mgr.get_position_of(weave).distance_to(ORBIT_CENTRE)
		nearest = minf(nearest, reach)
		farthest = maxf(farthest, reach)
	check(absf(nearest - 35.0) < 0.2 and absf(farthest - 45.0) < 0.2, "a spiral orbit weaves its radius 10 px (%f to %f)" % [nearest, farthest])


## Sticky: the orbit shot that hits leaves its circle and rides its target.
func test_a_sticky_orbit_shot_leaves_its_circle_and_rides_its_target() -> void:
	_an_anchor_in_the_room()
	var foe: Node2D = _target(ORBIT_CENTRE + Vector2(0.0, 40.0), 6.0)
	var sticker: int = OrbitShot.start(mgr, 0, 40.0, 0.0, 2.0, 5.0)
	check(mgr.set_sticky(sticker, 1.0), "an orbit takes sticky")
	_run(60)
	check(hits.size() == 1 and mgr.is_alive(sticker), "it hits once and stays (%d hits)" % hits.size())
	var off: Vector2 = mgr.get_position_of(sticker) - foe.global_position
	foe.global_position += Vector2(100.0, 0.0)
	_run(10)
	check(off.length() < 50.0 and (mgr.get_position_of(sticker) - foe.global_position).is_equal_approx(off) and mgr.get_position_of(sticker).distance_to(ORBIT_CENTRE) > 60.0, "a sticky orbit shot leaves its circle and rides its target")


# --- Orbits: anchors and hits --------------------------------------------------------------


## One orbit for each of the four seats, each round its own anchor, the anchors moving for 30
## steps; the slots by seat.
func _four_orbits_on_moving_anchors() -> Array[int]:
	var slots: Array[int] = []
	for p in 4:
		mgr.set_anchor(p, Vector2(100.0 * float(p + 1), 50.0))
		slots.append(OrbitShot.start(mgr, p, 20.0, 0.0, 2.0, 5.0))
	for i in 30:
		for p in 4:
			mgr.set_anchor(p, Vector2(100.0 * float(p + 1) + float(i), 50.0 + float(p)))
		mgr.step(DT)
	return slots


func test_each_actors_orbit_circles_its_own_moving_anchor() -> void:
	var slots: Array[int] = _four_orbits_on_moving_anchors()
	for p in 4:
		var anchor := Vector2(100.0 * float(p + 1) + 29.0, 50.0 + float(p))
		check(absf(mgr.get_position_of(slots[p]).distance_to(anchor) - 20.0) < 0.01, "actor %d's orbit shot circles its own, moving anchor" % p)


func test_clearing_an_anchor_ends_that_actors_orbits_only() -> void:
	var slots: Array[int] = _four_orbits_on_moving_anchors()
	mgr.clear_anchor(2)
	mgr.step(DT)
	check(not mgr.is_alive(slots[2]) and mgr.is_alive(slots[1]) and mgr.is_alive(slots[3]), "clearing an anchor ends that actor's orbit shots only")
	check(expired.is_empty(), "and sends no expiry")
	check_equal(mgr.get_count_for(2), 0, "the owner's count follows")


## An orbit of seat 0 (tag 3, no pierce) whose circle round (100, 100) passes an enemy, half a turn on.
func _an_orbit_over_an_enemy() -> int:
	mgr.set_bounds(ROOM)
	mgr.set_anchor(0, Vector2(100.0, 100.0))
	_target(Vector2(100.0, 140.0), 8.0)
	var slot: int = OrbitShot.start(mgr, 0, 40.0, 0.0, PI, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 3)
	_run(30)
	return slot


func test_an_orbit_hits_an_enemy_on_its_circle_with_its_tag() -> void:
	_an_orbit_over_an_enemy()
	check(hits.size() == 1 and hits[0][1] == targets[0] and hits[0][3] == 3, "an orbit shot hits an enemy that stands on its circle, with its tag")


func test_an_orbit_without_pierce_ends_on_its_hit() -> void:
	var slot: int = _an_orbit_over_an_enemy()
	check(not mgr.is_alive(slot), "an orbit shot ends on a hit without pierce")


## A piercing orbit of seat 1 (tag 8, 0.5 s) that begins on an enemy, with another across its circle.
func _a_piercing_orbit_on_an_enemy() -> int:
	mgr.set_anchor(1, Vector2(200.0, 200.0))
	_target(Vector2(240.0, 200.0), 10.0)
	_target(Vector2(160.0, 200.0), 10.0)
	var slot: int = OrbitShot.start(mgr, 1, 40.0, 0.0, 1.0, 0.5, 4.0, ManagerScript.LAYER_ENEMY, 5, 8)
	_run(20)
	return slot


func test_a_piercing_orbit_hits_the_enemy_it_began_on_once() -> void:
	var slot: int = _a_piercing_orbit_on_an_enemy()
	check(mgr.is_alive(slot), "a piercing orbit shot survives its hits (%d)" % hits.size())
	check_equal(hits.size(), 1, "it hit the enemy it began on once, not again while it stays there")


func test_an_orbit_expires_at_the_end_of_its_life_with_its_tag() -> void:
	var slot: int = _a_piercing_orbit_on_an_enemy()
	_run(20)
	check(not mgr.is_alive(slot) and expired.size() == 1 and expired[0][2] == 8, "it expires at the end of its life with its tag")


## Five enemies stacked under a ring that stands still (speed 0). The rule (owner, 2026-10-29):
## a piercing shot hits a target once while it touches it, however many it touches.
func test_a_standing_ring_hits_each_of_a_crowd_once() -> void:
	mgr.set_anchor(0, Vector2(200.0, 200.0))
	for i in 5:
		_target(Vector2(240.0 + float(i), 200.0), 10.0)
	var slot: int = OrbitShot.start(mgr, 0, 40.0, 0.0, 0.0, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 100, 1)
	_run(10)
	check(mgr.is_alive(slot), "a ring with pierce left survives a crowd")
	check_equal(hits.size(), 5, "a ring standing on five enemies hits each once, not again while it stays")
	check_equal(mgr._pierce[slot], 100 - hits.size(), "pierce left is 100 minus the hits")


func test_a_ring_with_pierce_0_ends_on_its_first_touch() -> void:
	mgr.set_anchor(0, Vector2(200.0, 200.0))
	for i in 5:
		_target(Vector2(240.0 + float(i), 200.0), 10.0)
	var thin: int = OrbitShot.start(mgr, 0, 40.0, 0.0, 0.0, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 1)
	mgr.step(DT)
	check(not mgr.is_alive(thin) and hits.size() == 1, "a ring with pierce 0 ends on its first touch, like any shot")


func test_a_ring_hits_a_target_again_each_time_it_comes_round() -> void:
	mgr.set_anchor(0, Vector2(200.0, 200.0))
	_target(Vector2(240.0, 200.0), 6.0)
	# One turn a second; it starts on the target, so it touches it at 0, 1, 2 and 3 seconds.
	var slot: int = OrbitShot.start(mgr, 0, 40.0, 0.0, TAU, 3.4, 4.0, ManagerScript.LAYER_ENEMY, 100, 1)
	_run(200)
	check_equal(hits.size(), 4, "a ring hits a target again each time it comes round to it")
	check(not mgr.is_alive(slot) or mgr._pierce[slot] == 96, "each a hit of its own")


func test_a_piercing_shot_hits_everything_it_passes_in_one_step() -> void:
	for i in 10:
		_target(Vector2(120.0 + 8.0 * i, 100.0), 3.0)
	# 120 px a step: the whole row in one step, more than the old three a step.
	var slot: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2(7200.0, 0.0), 0.1, 2.0, ManagerScript.LAYER_ENEMY, 20, 1)
	mgr.step(DT)
	check_equal(hits.size(), 10, "all ten in the one step")
	check(mgr.is_alive(slot), "with pierce to spare")


# --- Homing --------------------------------------------------------------------------------


## The general rule (owner, 2026-10-29): a bounce turns a shot, it takes none of its cards away.
## Fired right and a little down at a wall, the shot comes no nearer than 43 px to the target on
## its way there (its homing reaches 20 px past the target's edge, 26 from its centre), and on its
## way back, further down, it passes 13 px from it: too far to hit flying straight, close enough
## to home onto it, if it still homes after the bounce. The bouncing shot's slot.
func _a_bounce_past_a_target(homing: bool) -> int:
	mgr.set_walls([Rect2(100.0, 0.0, 16.0, 360.0)] as Array[Rect2])
	_target(Vector2(40.0, 150.0), 6.0)
	var slot: int = mgr.spawn(0, Vector2(20.0, 100.0), Vector2(150.0, 40.0), 3.0, 3.0)
	mgr.set_bounce(slot, 1)
	if homing:
		mgr.set_homing(slot, 6.0, 20.0)
	for _i in 120:
		mgr.step(DT)
		if not mgr.is_alive(slot):
			break
	return slot


func test_a_homing_shot_homes_after_it_bounces() -> void:
	_a_bounce_past_a_target(true)
	check(hits.size() == 1 and hits[0][1] == targets[0], "it bounced, then homed onto the target (%d hits)" % hits.size())


func test_a_bounced_shot_without_homing_flies_past_the_target() -> void:
	_a_bounce_past_a_target(false)
	check(hits.is_empty(), "without homing the bounced shot flies past it")


func test_a_homing_shot_fired_past_a_target_bends_and_hits_it() -> void:
	var enemy: Node2D = _target(Vector2(300.0, 150.0), 8.0)
	var slot: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2(200.0, 0.0), 3.0, 4.0)
	check(mgr.set_homing(slot, 6.0, HOMING_REACH), "a straight shot can home")
	for _i in 120:
		mgr.step(DT)
		if not mgr.is_alive(slot):
			break
	check(hits.size() == 1 and hits[0][1] == enemy, "a homing shot fired past a target bends and hits it")


func test_the_same_shot_without_homing_misses() -> void:
	_target(Vector2(300.0, 150.0), 8.0)
	mgr.spawn(0, Vector2(100.0, 100.0), Vector2(200.0, 0.0), 3.0, 4.0)
	_run(120)
	check(hits.is_empty(), "the same shot without homing misses")


## Homing is a curve, not a rate (the owner, 2026-10-30: "it should just work at all speeds"): a
## shot on a curve of 50 px turns its speed / 50 radians a second, whatever its speed.
func test_homing_turns_on_the_same_curve_at_any_speed() -> void:
	_target(Vector2(100.0, 400.0), 8.0)
	for pace: float in [100.0, 1100.0]:
		mgr.clear()
		var slot: int = mgr.spawn(0, Vector2(0.0, 100.0), Vector2(pace, 0.0), 5.0, 2.0)
		check(mgr.set_homing_curve(slot, 50.0, 400.0), "a shot of %d px/s takes a curve" % pace)
		_run(4)
		# Turned on its search step and after: at most the angle of its path on that curve.
		var turned: float = (mgr._vel[slot] as Vector2).angle()
		var most: float = pace * 4.0 * DT / 50.0
		check(turned > 0.0 and turned <= most * 1.01, "at %d px/s it turned %f rad, the curve allows %f" % [pace, turned, most])


## A rate is kept as a curve, so the shot keeps that curve when its speed changes later.
func test_a_homing_rate_is_taken_as_the_curve_it_gives_at_the_shots_speed() -> void:
	var shot: int = mgr.spawn(0, Vector2.ZERO, Vector2(200.0, 0.0), 5.0, 2.0)
	mgr.set_homing(shot, 4.0, 100.0)
	check(is_equal_approx(mgr._turn[shot], 4.0 / 200.0), "a rate is taken as the curve it gives at the shot's speed then")


## A swing's or beam's guard tests a shot along its last step, not only where it is now: an atom
## (1.5 px, 1100 px/s, 18 px a step) crossing a beam's line or a swing's slice between two steps is
## met (it slipped past both before). An enemy guard's id, the atom one step on.
func _an_atom_one_step_on() -> int:
	var guard: int = table.open(ActorSeats.ActorsScript.TEAM_ENEMIES, ActorSeats.ActorsScript.RAMP_ENEMY)
	var slot: int = mgr.spawn(0, Vector2.ZERO, Vector2(1100.0, 0.0), 1.0, 1.5)
	mgr.step(DT)
	check((mgr.get_position_of(slot) as Vector2).x > 15.0, "the atom went past the line in one step")
	return guard


func test_a_beams_line_meets_a_small_fast_shot_it_crossed_between_steps() -> void:
	var guard: int = _an_atom_one_step_on()
	check_equal(mgr.shots_on_segment(guard, Vector2(9.0, -50.0), Vector2(9.0, 50.0), 1.0), 1, "a beam's line it crossed meets it")


func test_a_swings_slice_meets_a_small_fast_shot_it_crossed_between_steps() -> void:
	var guard: int = _an_atom_one_step_on()
	check_equal(mgr.shots_in_wedge(guard, Vector2(9.0, -20.0), Vector2.DOWN, 1, -0.3, 0.3, 24.0), 1, "a swing's slice it crossed meets it")


func test_a_guards_line_behind_where_a_shot_came_from_does_not_meet_it() -> void:
	var guard: int = _an_atom_one_step_on()
	check_equal(mgr.shots_on_segment(guard, Vector2(-9.0, -50.0), Vector2(-9.0, 50.0), 1.0), 0, "a line behind where it came from does not")


## A shot of 100 px/s homing at 0.5 rad/s on a target off its line, 20 steps on; its slot.
func _a_slow_homing_turn() -> int:
	_target(Vector2(100.0, 220.0), 8.0)
	var slot: int = mgr.spawn(0, Vector2(0.0, 100.0), Vector2(100.0, 0.0), 5.0, 4.0)
	mgr.set_homing(slot, 0.5, HOMING_REACH)
	_run(20)
	return slot


func test_homing_keeps_the_speed() -> void:
	var velocity: Vector2 = mgr._vel[_a_slow_homing_turn()]
	check(absf(velocity.length() - 100.0) < 0.01, "homing keeps the speed (%s)" % velocity)


func test_homing_never_turns_faster_than_its_rate() -> void:
	var velocity: Vector2 = mgr._vel[_a_slow_homing_turn()]
	check(velocity.angle() > 0.0 and velocity.angle() <= 0.5 * 20.0 * DT * 1.01, "it never turns faster than the rate (%f rad)" % velocity.angle())


func test_a_still_shot_can_home_but_an_orbit_cannot() -> void:
	var rune: int = mgr.spawn(0, Vector2(50.0, 50.0), Vector2.ZERO, 1.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	mgr.set_anchor(0, Vector2(200.0, 200.0))
	var orbit: int = OrbitShot.start(mgr, 0, 10.0, 0.0, 1.0, 1.0)
	check(mgr.set_homing(rune, 3.0, HOMING_REACH), "a still shot can home: it creeps (rules R4i)")
	check(not mgr.set_homing(orbit, 3.0, HOMING_REACH), "an orbit shot cannot")


func test_set_homing_refuses_bad_slots_rates_and_ranges() -> void:
	var slot: int = mgr.spawn(0, Vector2(0.0, 100.0), Vector2(100.0, 0.0), 5.0, 4.0)
	check(not mgr.set_homing(-1, 3.0, HOMING_REACH) and not mgr.set_homing(slot, -1.0, HOMING_REACH) and not mgr.set_homing(slot, NAN, HOMING_REACH), "bad slots and rates are refused")
	check(not mgr.set_homing(slot, 3.0, 0.0) and not mgr.set_homing(slot, 3.0, INF), "a range not above 0 and finite is refused")


func test_a_homing_rate_of_0_turns_homing_off() -> void:
	var slot: int = mgr.spawn(0, Vector2(0.0, 100.0), Vector2(100.0, 0.0), 5.0, 4.0)
	mgr.set_homing(slot, 0.5, HOMING_REACH)
	check(mgr.set_homing(slot, 0.0, HOMING_REACH) and mgr._turn[slot] == 0.0, "a rate of 0 turns homing off and is accepted")


func test_a_reused_slot_starts_without_homing() -> void:
	var gone: int = mgr.spawn(0, Vector2.ZERO, Vector2(1.0, 0.0), 1.0)
	mgr.set_homing(gone, 4.0, HOMING_REACH)
	mgr.clear()
	var again: int = mgr.spawn(0, Vector2.ZERO, Vector2(1.0, 0.0), 1.0)
	check(again == gone and mgr._turn[again] == 0.0, "a reused slot starts without homing")


## A homing rune (rules R4i, owner 2026-10-30): a shot with no speed creeps toward the target its
## homing picks at SpellLimits.HOMING_DRIFT, the same pick and reach as a bolt's; with nothing
## in reach it stays put. A homing rune 150 px from an enemy and one with nothing in reach, a
## second on; their slots.
func _two_homing_runes() -> Vector2i:
	_target(Vector2(250.0, 100.0), 8.0)
	var lone: int = mgr.spawn(0, Vector2(100.0, 400.0), Vector2.ZERO, 30.0, 14.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	mgr.set_homing(lone, 3.0, HOMING_REACH)
	var rune: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2.ZERO, 30.0, 14.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
	check(mgr.set_homing(rune, 3.0, HOMING_REACH), "a rune takes homing")
	_run(60)
	return Vector2i(rune, lone)


func test_a_homing_rune_creeps_straight_toward_its_target_at_homing_drift() -> void:
	var rune: int = _two_homing_runes().x
	var moved: float = mgr.get_position_of(rune).x - 100.0
	check(absf(moved - SpellLimits.HOMING_DRIFT) < SpellLimits.HOMING_DRIFT * DT * ManagerScript.HOMING_PERIOD + 0.01, "it creeps toward its target at HOMING_DRIFT: %s px in a second" % moved)
	check(is_equal_approx(mgr.get_position_of(rune).y, 100.0), "straight at it")


func test_a_homing_rune_with_nothing_in_reach_stays_put() -> void:
	var lone: int = _two_homing_runes().y
	check_equal(mgr.get_position_of(lone), Vector2(100.0, 400.0), "a rune with nothing in reach stays put")


func test_a_homing_rune_reaches_its_target() -> void:
	_two_homing_runes()
	for _i in 600:
		mgr.step(DT)
		if not hits.is_empty():
			break
	check(hits.size() == 1 and hits[0][1] == targets[0], "the creeping rune reaches its target")


func test_a_homing_shot_does_not_turn_toward_its_own_wizard() -> void:
	_target(Vector2(100.0, 130.0), 8.0, ManagerScript.LAYER_PLAYER, 0)
	var slot: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2(100.0, 0.0), 5.0, 4.0)
	mgr.set_homing(slot, 8.0, HOMING_REACH)
	_run(30)
	check((mgr._vel[slot] as Vector2).normalized().is_equal_approx(Vector2.RIGHT), "a homing shot does not turn toward its own wizard")


## A piercing homing shot past a near target; the second starts just out of reach (the pick is
## random among the targets in reach). 150 steps on.
func _a_piercing_homing_shot_past_two() -> void:
	_target(Vector2(180.0, 100.0), 8.0)
	_target(Vector2(320.0, 130.0), 8.0)
	var pierce: int = mgr.spawn(1, Vector2(150.0, 100.0), Vector2(100.0, 0.0), 5.0, 4.0, ManagerScript.LAYER_ENEMY, 3)
	mgr.set_homing(pierce, 8.0, HOMING_REACH)
	_run(150)


func test_a_piercing_homing_shot_goes_on_to_a_second_target() -> void:
	_a_piercing_homing_shot_past_two()
	check(_hit(targets[0]) and _hit(targets[1]), "a piercing homing shot goes on to a second target after the first")


func test_a_piercing_homing_shot_does_not_turn_back_to_the_first() -> void:
	_a_piercing_homing_shot_past_two()
	check_equal(hits.size(), 2, "it does not turn back to hit the first again")


func test_homing_searches_every_fourth_step_with_the_slots_taking_turns() -> void:
	var slots: Array[int] = []
	for i in 8:
		slots.append(mgr.spawn(0, Vector2(100.0, 100.0), Vector2(0.0, 0.0001), 5.0, 4.0))
		mgr.set_homing(slots[i], 1.0, HOMING_REACH)
	_target(Vector2(150.0, 100.0), 8.0)
	var searched: Array[int] = []
	for _n in 4:
		var found: int = 0
		for s in slots:
			mgr._home_at[s] = Vector2.INF
		mgr.step(DT)
		for s in slots:
			if mgr._home_at[s].is_finite():
				found += 1
		searched.append(found)
	check(searched == [2, 2, 2, 2], "each shot searches once in four steps, and the slots take turns (%s)" % str(searched))


## A homing shot among 20 targets, the manager at its turn in the hit pass (`_catch_up`); its slot.
func _a_homing_search_in_the_hit_pass() -> int:
	for i in 20:
		_target(Vector2(300.0 + float(i), 100.0), 6.0)
	var slot: int = mgr.spawn(0, Vector2(200.0, 100.0), Vector2(10.0, 0.0), 5.0, 4.0)
	mgr.set_homing(slot, 1.0, HOMING_REACH)
	mgr._refresh_targets()
	mgr._step_index = (4 - slot % 4) % 4
	mgr._catching_up = true
	mgr._state[slot] = ManagerScript.S_MOVING
	return slot


func test_a_homing_search_waits_when_the_budget_is_spent() -> void:
	var slot: int = _a_homing_search_in_the_hit_pass()
	mgr._work_left = 0
	mgr._pass_homing(PackedInt32Array([slot]), 0, 1, DT)
	mgr._catching_up = false
	check(not mgr._home_at[slot].is_finite(), "with the budget spent a search waits")


func test_a_homing_search_pays_for_the_targets_it_examined() -> void:
	var slot: int = _a_homing_search_in_the_hit_pass()
	mgr._work_left = 1000
	mgr._pass_homing(PackedInt32Array([slot]), 0, 1, DT)
	mgr._catching_up = false
	check(mgr._home_at[slot].is_finite() and mgr._work_left < 1000, "with budget it searches and pays for the targets it examined")


func test_homing_picks_neither_another_wizard_nor_a_freed_target() -> void:
	_target(Vector2(300.0, 160.0), 8.0, ManagerScript.LAYER_PLAYER, 1)
	var gone: Node2D = _target(Vector2(300.0, 40.0), 8.0)
	var slot: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2(100.0, 0.0), 5.0, 4.0)
	mgr.set_homing(slot, 3.0, HOMING_REACH)
	mgr._refresh_targets()
	gone.free()
	check(not mgr._homing_point(slot, mgr.get_position_of(slot)).is_finite(), "homing neither picks another wizard (though it would hit one) nor a freed target")


## Four targets 60 px round CENTRE and one far off (`targets[4]`); their keys (the four in reach).
func _four_in_reach_and_one_far() -> Array[int]:
	var ids: Array[int] = []
	for offset: Vector2 in [Vector2(60.0, 0.0), Vector2(-60.0, 0.0), Vector2(0.0, 60.0), Vector2(0.0, -60.0)]:
		ids.append(mgr.key_of(_target(CENTRE + offset, 8.0)))
	_target(CENTRE + Vector2(400.0, 0.0), 8.0)
	return ids


func _pick(kept: int, pick_seed: int) -> Vector2:
	return mgr.homing_point(0, CENTRE, Vector2.RIGHT, PI, ManagerScript.LAYER_ENEMY, HOMING_REACH, kept, pick_seed)


func test_a_homing_pick_is_one_of_the_targets_in_reach() -> void:
	var ids: Array[int] = _four_in_reach_and_one_far()
	for pick_seed in 32:
		_pick(0, pick_seed)
		check(ids.has(mgr.homing_target), "a pick (seed %d) is one of the targets in reach, never the far one" % pick_seed)


func test_different_seeds_pick_different_targets() -> void:
	_four_in_reach_and_one_far()
	var picked: Dictionary = {}
	for pick_seed in 32:
		_pick(0, pick_seed)
		picked[mgr.homing_target] = true
	check(picked.size() >= 3, "different seeds pick different targets (%d of 4)" % picked.size())


func test_the_same_seed_picks_the_same_target() -> void:
	_four_in_reach_and_one_far()
	var first: Vector2 = _pick(0, 7)
	check_equal(_pick(0, 7), first, "the same seed picks the same target")


func test_a_kept_target_stays_the_pick_while_it_is_in_reach() -> void:
	_four_in_reach_and_one_far()
	_pick(0, 7)
	var kept: int = mgr.homing_target
	for pick_seed in 16:
		_pick(kept, pick_seed)
		check(mgr.homing_target == kept, "a kept target stays the pick while it is in reach (seed %d)" % pick_seed)


func test_a_kept_target_out_of_reach_gives_way_to_a_new_pick() -> void:
	var ids: Array[int] = _four_in_reach_and_one_far()
	_pick(mgr.key_of(targets[4]), 3)
	check(ids.has(mgr.homing_target), "a kept target out of reach gives way to a new pick")


func test_a_fan_of_homing_shots_spreads_over_the_group() -> void:
	_four_in_reach_and_one_far()
	var slots: Array[int] = []
	for i in 8:
		var slot: int = mgr.spawn(0, CENTRE + Vector2(0.0, 120.0), Vector2(0.0, -60.0), 3.0, 2.0)
		mgr.set_homing(slot, 0.5, HOMING_REACH)
		slots.append(slot)
	_run(ManagerScript.HOMING_PERIOD)
	var chosen: Dictionary = {}
	for slot in slots:
		if mgr._home_target[slot] != 0:
			chosen[mgr._home_target[slot]] = true
	check(chosen.size() >= 2, "eight shots from one point home on more than one target (%d)" % chosen.size())


# --- homing_aim and home_velocity ----------------------------------------------------------


func _aim(from: Vector2, aim: Vector2, cone_deg: float, layers: int = ManagerScript.LAYER_ENEMY, reach: float = HOMING_REACH) -> Vector2:
	return mgr.homing_aim(0, from, aim, deg_to_rad(cone_deg), layers, reach, 0, 0)


## An enemy inside a 30-degree cone to the right of AIM_FROM (returned) and one outside it.
func _one_inside_the_cone() -> Node2D:
	var inside: Node2D = _target(Vector2(200.0, 130.0), 8.0)
	_target(Vector2(120.0, 0.0), 8.0)
	return inside


func test_a_beam_bends_toward_the_nearest_target_inside_its_cone() -> void:
	var inside: Node2D = _one_inside_the_cone()
	check(_aim(AIM_FROM, Vector2.RIGHT, 30.0).is_equal_approx(AIM_FROM.direction_to(inside.global_position)), "a beam bends toward the nearest target inside the cone")


func test_a_beam_keeps_its_aim_when_no_target_is_in_its_cone() -> void:
	_one_inside_the_cone()
	check_equal(_aim(AIM_FROM, Vector2.RIGHT, 10.0), Vector2.RIGHT, "it keeps its aim when none is that close to it")


func test_a_target_behind_the_aim_is_not_chosen() -> void:
	_one_inside_the_cone()
	check_equal(_aim(AIM_FROM, Vector2.LEFT, 30.0), Vector2.LEFT, "a target behind the aim is not chosen")


func test_a_zero_aim_comes_back_unchanged() -> void:
	_one_inside_the_cone()
	check_equal(_aim(AIM_FROM, Vector2.ZERO, 30.0), Vector2.ZERO, "a zero aim comes back unchanged")


func test_a_target_exactly_on_the_aims_origin_is_skipped() -> void:
	_target(Vector2(500.0, 300.0), 8.0)
	check_equal(_aim(Vector2(500.0, 300.0), Vector2.RIGHT, 30.0), Vector2.RIGHT, "a target exactly on the origin is skipped, never a zero aim")


func test_a_beam_never_bends_toward_a_wizard() -> void:
	var inside: Node2D = _one_inside_the_cone()
	_target(Vector2(140.0, 100.0), 8.0, ManagerScript.LAYER_PLAYER, 1)
	check(_aim(AIM_FROM, Vector2.RIGHT, 30.0, ManagerScript.LAYER_ENEMY | ManagerScript.LAYER_PLAYER).is_equal_approx(AIM_FROM.direction_to(inside.global_position)), "a beam never bends toward a wizard")


func test_a_beams_aim_reaches_as_far_as_its_range() -> void:
	var far: Node2D = _target(Vector2(100.0, 900.0), 8.0)
	var from := Vector2(100.0, 650.0)
	check_equal(_aim(from, Vector2.DOWN, 30.0), Vector2.DOWN, "past a homing shot's range a target is not found")
	check(_aim(from, Vector2.DOWN, 30.0, ManagerScript.LAYER_ENEMY, 260.0).is_equal_approx(from.direction_to(far.global_position)), "with a longer range (a beam's length) it is")
	check_equal(_aim(from, Vector2.DOWN, 30.0, ManagerScript.LAYER_ENEMY, 0.0), Vector2.DOWN, "a zero reach finds nothing")


func test_a_beam_is_as_long_as_it_says_however_long() -> void:
	var ray_len: float = mgr.ray(0, Vector2(10.0, 600.0), Vector2.RIGHT, 1000.0)
	check(is_equal_approx(ray_len, 1000.0), "a beam is as long as it says, however long (%f)" % ray_len)


## `home_velocity` from HOME_FROM at HOME_VELOCITY for 0.1 s.
func _home(rate: float, reach: float) -> Vector2:
	return mgr.home_velocity(0, HOME_FROM, HOME_VELOCITY, rate, reach, 0.1, 0, 0)


func test_home_velocity_keeps_the_speed() -> void:
	_target(Vector2(100.0, 200.0), 8.0)
	check(is_equal_approx(_home(3.0, HOMING_REACH).length(), 200.0), "it keeps its speed")


func test_home_velocity_turns_at_most_the_rate_toward_the_target() -> void:
	_target(Vector2(100.0, 200.0), 8.0)
	var turned: Vector2 = _home(3.0, HOMING_REACH)
	check(is_equal_approx(HOME_VELOCITY.angle_to(turned), 0.3), "turning at most the rate for the time, toward the target (%f)" % HOME_VELOCITY.angle_to(turned))


func test_home_velocity_does_not_turn_past_its_reach_or_at_rate_0() -> void:
	_target(Vector2(100.0, 200.0), 8.0)
	check_equal(_home(3.0, 50.0), HOME_VELOCITY, "a target past its reach is not homed on")
	check_equal(_home(0.0, HOMING_REACH), HOME_VELOCITY, "a rate of 0 does not turn")


func test_home_velocity_never_homes_on_a_wizard() -> void:
	_target(Vector2(100.0, 150.0), 8.0, ManagerScript.LAYER_PLAYER, 1)
	mgr.step(0.0)
	check_equal(_home(3.0, HOMING_REACH), HOME_VELOCITY, "a wizard is never homed on")


func test_a_shots_homing_move_turns_toward_the_target() -> void:
	var slot: int = mgr.spawn(0, Vector2(300.0, 300.0), Vector2.ZERO, 2.0, 2.0)
	_target(Vector2(420.0, 360.0), 8.0)
	check(mgr.move_shot(slot, Vector2(60.0, 0.0), 0.5, 3.0, HOMING_REACH), "a homing move is taken")
	_run(30)
	check(mgr.get_position_of(slot).y > 300.5, "a shot's homing move turns toward the target: %s" % mgr.get_position_of(slot))


# --- A card's moves on a shot --------------------------------------------------------------


## Rules R1e: the moves a shot is given add up while they run, each on its own time, as the
## wizard's pushes do (a later move replaced the one under way before).
func test_two_opposite_pushes_on_a_shot_cancel() -> void:
	var slot: int = mgr.spawn(0, Vector2(300.0, 300.0), Vector2.ZERO, 2.0, 2.0)
	mgr.move_shot(slot, Vector2(-20.0, 0.0), 0.1)
	mgr.move_shot(slot, Vector2(20.0, 0.0), 0.1)
	_run(12)
	check(mgr.get_position_of(slot).is_equal_approx(Vector2(300.0, 300.0)), "two opposite pushes cancel: %s" % mgr.get_position_of(slot))


func test_a_pull_after_a_push_gets_both() -> void:
	var slot: int = mgr.spawn(0, Vector2(300.0, 300.0), Vector2.ZERO, 2.0, 2.0)
	mgr.move_shot(slot, Vector2(-20.0, 0.0), 0.1)
	mgr.step(DT)
	mgr.move_shot(slot, Vector2(0.0, 60.0), 0.15)
	_run(12)
	check(mgr.get_position_of(slot).is_equal_approx(Vector2(280.0, 360.0)), "a pull after a push gets both: %s" % mgr.get_position_of(slot))


func test_a_blink_keeps_the_move_under_way() -> void:
	var slot: int = mgr.spawn(0, Vector2(280.0, 360.0), Vector2.ZERO, 2.0, 2.0)
	mgr.move_shot(slot, Vector2(30.0, 0.0), 0.1)
	mgr.step(DT)
	mgr.move_shot(slot, Vector2(0.0, -40.0), 0.0)
	_run(12)
	check(mgr.get_position_of(slot).is_equal_approx(Vector2(310.0, 320.0)), "a blink keeps the move under way: %s" % mgr.get_position_of(slot))


# --- Rays ----------------------------------------------------------------------------------


## Enemies on a line ahead of RAY_FROM at 70 (`targets[1]`), 150 (`targets[2]`) and 250
## (`targets[0]`, registered first) px, and one off the line.
func _three_on_a_beam() -> void:
	_target(Vector2(300.0, 100.0))
	_target(Vector2(120.0, 104.0))
	_target(Vector2(200.0, 96.0))
	_target(Vector2(250.0, 160.0))


func test_a_ray_without_pierce_hits_only_the_nearest_target_with_the_tag() -> void:
	_three_on_a_beam()
	var reach: float = mgr.ray(0, RAY_FROM, Vector2.RIGHT, 400.0, 0, ManagerScript.LAYER_ENEMY, 6)
	check(hits.size() == 1 and hits[0][1] == targets[1] and hits[0][3] == 6, "a ray without pierce hits only the nearest target, with the tag")
	check(absf(reach - 70.0) < 0.01, "and stops there (%f)" % reach)


func test_a_piercing_ray_hits_in_order_along_the_beam_and_reaches_the_last() -> void:
	_three_on_a_beam()
	var reach: float = mgr.ray(0, RAY_FROM, Vector2.RIGHT, 400.0, 2)
	check(hits.size() == 3 and hits[0][1] == targets[1] and hits[1][1] == targets[2] and hits[2][1] == targets[0], "pierce 2 hits three in the order along the beam")
	check(absf(reach - 250.0) < 0.01, "and reaches the third (%f)" % reach)


func test_a_rays_hit_point_is_where_the_beam_passes_closest() -> void:
	_three_on_a_beam()
	mgr.ray(0, RAY_FROM, Vector2.RIGHT, 400.0, 2)
	check(not hits.is_empty() and (hits[0][2] as Vector2).is_equal_approx(Vector2(120.0, 100.0)), "the hit point is where the beam passes closest")


func test_a_ray_with_pierce_to_spare_reaches_its_full_length() -> void:
	_three_on_a_beam()
	var reach: float = mgr.ray(0, RAY_FROM, Vector2.RIGHT, 300.0, 10)
	check(hits.size() == 3 and absf(reach - 300.0) < 0.001, "a ray with pierce to spare, and nothing more to hit, reaches its full length")


func test_a_ray_normalises_its_direction_and_stops_at_its_length() -> void:
	_three_on_a_beam()
	var reach: float = mgr.ray(0, RAY_FROM, Vector2.RIGHT * 7.0, 150.0, 5)
	check(hits.size() == 2 and absf(reach - 150.0) < 0.001, "a non-unit direction is normalised; targets past the length are not hit")


func test_a_ray_holds_no_row_in_the_pool() -> void:
	_three_on_a_beam()
	mgr.ray(0, RAY_FROM, Vector2.RIGHT, 400.0, 2)
	check_equal(mgr.get_count(), 0, "a ray holds no row in the pool")


func test_a_thin_beam_misses_a_target_off_it() -> void:
	_target(Vector2(200.0, 125.0), 10.0)
	mgr.ray(0, RAY_FROM, Vector2.RIGHT, 400.0, 3)
	check(hits.is_empty(), "a target 25 px off a thin beam is missed")


func test_a_wide_beam_reaches_a_target_off_its_line() -> void:
	var off: Node2D = _target(Vector2(200.0, 125.0), 10.0)
	mgr.ray(0, RAY_FROM, Vector2.RIGHT, 400.0, 3, ManagerScript.LAYER_ENEMY, 0, 20.0)
	check(hits.size() == 1 and hits[0][1] == off, "a wide beam reaches it")


func _wizard_0() -> Node2D:
	return _target(Vector2(100.0, 100.0), 8.0, ManagerScript.LAYER_PLAYER, 0)


func test_a_beam_spares_the_body_it_is_cast_from_while_it_starts_on_it() -> void:
	var wizard: Node2D = _wizard_0()
	mgr.ray(0, Vector2(100.0, 100.0), Vector2.RIGHT, 400.0, 3, ManagerScript.LAYER_PLAYER, 0, 0.0, wizard)
	check(hits.is_empty(), "a beam spares the body it is cast from (`exclude`) while it starts on it")


func test_a_beams_path_that_turns_back_into_its_body_hits_it() -> void:
	var wizard: Node2D = _wizard_0()
	mgr.ray_points(0, PackedVector2Array([Vector2(100.0, 100.0), Vector2(160.0, 100.0), Vector2(100.0, 102.0)]), 0, 3, 400.0, 3, ManagerScript.LAYER_PLAYER, 0, 0.0, wizard)
	check(hits.size() == 1 and hits[0][1] == wizard, "its path that turns back into it hits it")


func test_a_beam_hits_its_own_wizard_ahead_of_it() -> void:
	var wizard: Node2D = _wizard_0()
	mgr.ray(0, RAY_FROM, Vector2.RIGHT, 400.0, 3, ManagerScript.LAYER_PLAYER)
	check(hits.size() == 1 and hits[0][1] == wizard, "its own wizard ahead of it is hit (owner, 2026-11-06)")


func test_a_teammates_beam_hits_a_wizard_though_it_asked_for_enemies() -> void:
	var wizard: Node2D = _wizard_0()
	mgr.ray(1, RAY_FROM, Vector2.RIGHT, 400.0, 3)
	check(hits.size() == 1 and hits[0][1] == wizard, "a teammate's beam hits the wizard, though it asked for enemies (G3c)")


func test_a_beam_of_no_actor_hits_the_wizard_and_the_enemy() -> void:
	_wizard_0()
	_target(Vector2(300.0, 100.0))
	mgr.ray(EventsScript.NO_PLAYER, RAY_FROM, Vector2.RIGHT, 400.0, 3, ManagerScript.LAYER_PLAYER)
	check_equal(hits.size(), 2, "a beam of no actor hits the wizard and the enemy")


## The room with a wall at x 96..128, an enemy in front of it (`targets[0]`) and one behind; a
## piercing beam from x 40 toward them; its reach.
func _a_beam_at_a_wall() -> float:
	mgr.set_bounds(ROOM)
	mgr.set_walls([Rect2(96.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	_target(Vector2(80.0, 100.0))
	_target(Vector2(200.0, 100.0))
	return mgr.ray(0, Vector2(40.0, 100.0), Vector2.RIGHT, 400.0, 5)


func test_a_beam_ends_at_a_wall() -> void:
	var reach: float = _a_beam_at_a_wall()
	check(absf(reach - 56.0) < 0.01, "the beam ends at the wall (%f)" % reach)


func test_a_beam_hits_what_is_in_front_of_a_wall_not_behind_it() -> void:
	_a_beam_at_a_wall()
	check(hits.size() == 1 and hits[0][1] == targets[0], "it hits what is in front of the wall, not behind it")


func test_a_beam_sends_a_wall_impact_where_it_ends() -> void:
	_a_beam_at_a_wall()
	check(impacts.size() == 2 and impacts[1][0] == null and (impacts[1][1] as Vector2).is_equal_approx(Vector2(96.0, 100.0)), "it sends a wall impact where it ends (%s)" % str(impacts))


func test_wall_hits_counts_shots_not_beams() -> void:
	_a_beam_at_a_wall()
	check_equal(mgr.wall_hits, 0, "wall_hits counts shots, not beams")


func test_a_beam_that_starts_in_a_wall_gets_nowhere() -> void:
	mgr.set_bounds(ROOM)
	mgr.set_walls([Rect2(96.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	check_equal(mgr.ray(0, Vector2(100.0, 100.0), Vector2.RIGHT, 400.0, 5), 0.0, "a beam that starts in a wall gets nowhere")


func test_a_ray_with_bad_arguments_gets_nowhere() -> void:
	_target(Vector2(100.0, 100.0))
	check_equal(mgr.ray(0, Vector2(0.0, 100.0), Vector2.ZERO, 100.0), 0.0, "no direction")
	check_equal(mgr.ray(0, Vector2(0.0, 100.0), Vector2.RIGHT, 0.0), 0.0, "no length")
	check_equal(mgr.ray(0, Vector2(0.0, 100.0), Vector2.RIGHT, NAN), 0.0, "NaN length")
	check_equal(mgr.ray(0, Vector2.INF, Vector2.RIGHT, 100.0), 0.0, "infinite origin")
	check_equal(mgr.ray(ManagerScript.ACTORS, Vector2(0.0, 100.0), Vector2.RIGHT, 100.0), 0.0, "bad caster")
	check(hits.is_empty(), "none of them hit anything")


func test_a_rays_negative_pierce_counts_as_0() -> void:
	_target(Vector2(100.0, 100.0))
	check(absf(mgr.ray(0, Vector2(0.0, 100.0), Vector2.RIGHT, 50.0, -3) - 50.0) < 0.001, "a negative pierce counts as 0")


func test_a_ray_skips_a_target_freed_by_an_earlier_hits_handler() -> void:
	var a: Node2D = _target(Vector2(100.0, 100.0))
	var b: Node2D = _target(Vector2(150.0, 100.0))
	var seen: Array[Node] = []
	bus.projectile_hit.connect(func(_p: int, target: Node, _at: Vector2, _tag: int, _shot: int) -> void:
		seen.append(target)
		if target == a and is_instance_valid(b):
			mgr.remove_target(b)
			b.free())
	mgr.ray(0, Vector2(0.0, 100.0), Vector2.RIGHT, 300.0, 3, ManagerScript.LAYER_ENEMY, 0)
	check(seen.size() == 1 and seen[0] == a, "a target freed by an earlier hit's handler is skipped, not sent")


func test_a_ray_handler_may_fire_another_ray() -> void:
	_target(Vector2(50.0, 300.0))
	var nested: Array[float] = []
	bus.projectile_hit.connect(func(_p: int, _target: Node, _at: Vector2, tag: int, _shot: int) -> void:
		if tag == 1:
			nested.append(mgr.ray(0, Vector2(0.0, 300.0), Vector2.RIGHT, 100.0, 1, ManagerScript.LAYER_ENEMY, 2)))
	mgr.ray(0, Vector2(0.0, 300.0), Vector2.RIGHT, 100.0, 1, ManagerScript.LAYER_ENEMY, 1)
	check(nested.size() == 1 and nested[0] > 0.0 and hits.size() == 2, "a handler may fire another ray (%s)" % str(nested))
	check_equal(mgr._ray_depth, 0, "the nesting count is back to 0")


func test_random_beams_agree_with_a_brute_force_search() -> void:
	mgr.set_bounds(ROOM)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var radii: Array[float] = []
	for i in 120:
		var radius: float = rng.randf_range(4.0, 16.0)
		radii.append(radius)
		_target(Vector2(rng.randf_range(0.0, 640.0), rng.randf_range(0.0, 360.0)), radius)
	mgr.step(DT)
	var wrong: int = 0
	var skipped: int = 0
	for _q in 100:
		var origin := Vector2(rng.randf_range(0.0, 640.0), rng.randf_range(0.0, 360.0))
		var dir: Vector2 = Vector2.from_angle(rng.randf_range(0.0, TAU))
		var length: float = rng.randf_range(20.0, 500.0)
		var width: float = rng.randf_range(0.0, 12.0)
		var pierce: int = rng.randi_range(0, 4)
		var expected: Array = []
		for i in targets.size():
			var along: float = clampf((targets[i].global_position - origin).dot(dir), 0.0, length)
			if (origin + dir * along).distance_to(targets[i].global_position) <= width + radii[i]:
				expected.append([along, targets[i]])
		expected.sort_custom(func(l: Array, r: Array) -> bool: return l[0] < r[0])
		# Targets level with the beam's start or each other tie: either order is right.
		var tied: bool = false
		for i in mini(expected.size() - 1, pierce + 1):
			tied = tied or absf(expected[i + 1][0] - expected[i][0]) < 0.001
		if tied:
			skipped += 1
			continue
		expected = expected.slice(0, pierce + 1)
		hits.clear()
		var reach: float = mgr.ray(0, origin, dir, length, pierce, ManagerScript.LAYER_ENEMY, 0, width)
		if hits.size() != expected.size():
			wrong += 1
			continue
		for i in expected.size():
			if hits[i][1] != expected[i][1]:
				wrong += 1
				break
		if expected.size() == pierce + 1 and absf(reach - expected[-1][0]) > 0.01:
			wrong += 1
	check(skipped < 30, "few random beams are skipped for ties (%d)" % skipped)
	check(wrong == 0, "random beams agree with a brute-force search (%d differ)" % wrong)
