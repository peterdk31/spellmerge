extends "res://tests/support/suite.gd"
# unit-test-alone
## Tests for core/projectiles, the projectile kit (staffs B1), one behaviour each: bounce (off a
## wall, a floor, a corner, on a circle, until it runs out), ghost, spiral, return (out and back,
## homing on the way, always home), linger, growth, speed over life (`set_speed_curve`, and the
## default curve `Spells._apply_travel` gives every spell's shot), sticky, shield, shots that hit
## their caster (and pass the body they start on), every shot hitting both sides (actors G3c), the
## wall flag of an expiry, `Spells._apply_travel` mapping cards to the shot, the setters' refusals,
## and the time 1,500 shots with behaviours take a step.
##
## Each test gets a fresh manager in a 640 x 360 room with an event bus and a table of four wizards
## at ids 0-3 and one enemy, `imp` (`before_each`); the manager is stepped by hand.
##
## The last test times the machine (a budget in wall time), so the runner runs this file in a
## process of its own (`# unit-test-alone`; ci/build/unit_tests.sh, TIMED_TESTS).
##
## godot --headless --path . --script res://tests/support/run.gd -- res://tests/core/test_projectiles_kit.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const OrbitShot := preload("res://tests/support/orbit_shot.gd")

const DT: float = 1.0 / 60.0
## The wall most tests put in a shot's way: x 96..128, y 0..200.
const WALL: Rect2 = Rect2(96.0, 0.0, 32.0, 200.0)
## The caster's place in the return and self-hit tests.
const HOME: Vector2 = Vector2(50.0, 100.0)
## The centre of the circling shot that bounces (`_a_circling_shot_by_a_wall`).
const CIRCLE: Vector2 = Vector2(100.0, 100.0)

var bus: EventsScript
var mgr: ManagerScript
## Wizards at ids 0-3 (seated 0-3) and one enemy, `imp`.
var table: ActorSeats.ActorsScript
var imp: int = -1
## Every projectile_hit as [caster, target, position, tag].
var hits: Array = []
## Every projectile_expired as [caster, position, tag, on_wall].
var expired: Array = []
## Every shot_blocked as [caster, position, tag].
var blocked: Array = []
## The two enemies of `_a_sticky_shot_in_a_pair`.
var pair: Array[Node2D] = []


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	table = own(ActorSeats.table()) as ActorSeats.ActorsScript
	imp = ActorSeats.enemy(table)
	mgr.actors = table
	mgr.events = bus
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	hits.clear()
	expired.clear()
	blocked.clear()
	pair.clear()
	bus.projectile_expired.connect(func(caster: int, position: Vector2, tag: int, _shot: int) -> void: expired.append([caster, position, tag, mgr.expired_on_wall]))
	bus.projectile_hit.connect(func(caster: int, target: Node, position: Vector2, tag: int, _shot: int) -> void: hits.append([caster, target, position, tag]))
	bus.shot_blocked.connect(func(caster: int, position: Vector2, tag: int, _shot: int) -> void: blocked.append([caster, position, tag]))


func _target(position: Vector2, radius: float = 10.0, layer: int = ManagerScript.LAYER_ENEMY, owner: int = EventsScript.NO_PLAYER) -> Node2D:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.global_position = position
	mgr.add_target(node, radius, layer, owner)
	return node


func _run(steps: int) -> void:
	for _i in steps:
		mgr.step(DT)


func _fire(velocity: Vector2, at: Vector2 = HOME, life: float = 3.0, tag: int = 1, caster: int = 0) -> int:
	return mgr.spawn(caster, at, velocity, life, 3.0, ManagerScript.LAYER_ENEMY, 0, tag)


func _walls(rects: Array[Rect2]) -> void:
	mgr.set_walls(rects)


## A Spells service bound to this manager and bus (owned).
func _spells() -> SpellsScript:
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.bind(mgr, bus)
	return spells


# --- A plain shot and the wall flag --------------------------------------------------------


func test_a_plain_shot_flies_straight() -> void:
	var slot: int = _fire(Vector2(120.0, 0.0), HOME, 1.0)
	_run(30)
	check(mgr.get_position_of(slot).is_equal_approx(Vector2(110.0, 100.0)), "a plain shot flies straight (%s)" % mgr.get_position_of(slot))


func test_a_plain_shot_has_no_growth_or_shield() -> void:
	var slot: int = _fire(Vector2(120.0, 0.0), HOME, 1.0)
	_run(30)
	check(is_equal_approx(mgr.get_growth_of(slot), 1.0) and mgr.get_shield_of(slot) == 0, "a plain shot has no growth or shield")


func test_a_plain_shot_expires_by_its_life_not_on_a_wall() -> void:
	_fire(Vector2(120.0, 0.0), HOME, 1.0)
	_run(70)
	check(expired.size() == 1 and not expired[0][3], "it expires by its life, not on a wall")


func test_a_shot_that_ends_on_a_wall_has_the_wall_flag_in_its_expiry() -> void:
	_walls([WALL])
	_fire(Vector2(300.0, 0.0))
	_run(30)
	check(expired.size() == 1 and expired[0][3], "a shot that ends on a wall has the wall flag in its expiry")


func test_the_wall_flag_is_down_again_after_the_expiry() -> void:
	_walls([WALL])
	_fire(Vector2(300.0, 0.0))
	_run(30)
	check(not mgr.expired_on_wall, "the flag is down again afterwards")


# --- Bounce and ghost ----------------------------------------------------------------------


func test_a_shot_bounces_straight_back_off_a_vertical_wall() -> void:
	_walls([WALL])
	var slot: int = _fire(Vector2(300.0, 0.0))
	check(mgr.set_bounce(slot, 1), "bounce is accepted")
	_run(20)
	check(mgr.is_alive(slot) and mgr.get_velocity_of(slot).x < 0.0 and is_zero_approx(mgr.get_velocity_of(slot).y), "a shot bounces straight back off a vertical wall (%s)" % mgr.get_velocity_of(slot))
	check(mgr.get_position_of(slot).x < 96.0, "and stays out of the wall")


func test_a_bounce_is_a_wall_hit_but_not_an_expiry() -> void:
	_walls([WALL])
	var slot: int = _fire(Vector2(300.0, 0.0))
	mgr.set_bounce(slot, 1)
	_run(20)
	check(expired.is_empty() and mgr.wall_hits == 1, "a bounce is a wall hit but not an expiry")


func test_a_floor_flips_only_the_vertical_speed() -> void:
	_walls([Rect2(0.0, 150.0, 400.0, 32.0)] as Array[Rect2])
	var slot: int = _fire(Vector2(200.0, 200.0), HOME)
	mgr.set_bounce(slot, 2)
	_run(20)
	var velocity: Vector2 = mgr.get_velocity_of(slot)
	check(mgr.is_alive(slot) and is_equal_approx(velocity.x, 200.0) and is_equal_approx(velocity.y, -200.0), "a floor flips only the vertical speed (%s)" % velocity)


func test_a_bouncing_shot_in_a_corner_never_ends_up_inside_a_wall() -> void:
	_walls([WALL, Rect2(0.0, 200.0, 400.0, 32.0)] as Array[Rect2])
	var corner: int = _fire(Vector2(200.0, 200.0), Vector2(40.0, 60.0))
	mgr.set_bounce(corner, 4)
	_run(60)
	check(mgr.is_alive(corner) and mgr.get_position_of(corner).x < 96.0 and mgr.get_position_of(corner).y < 200.0, "a shot in a corner turns right round, never inside a wall (%s)" % mgr.get_position_of(corner))


func test_after_its_bounces_a_shot_ends_on_the_next_wall() -> void:
	_walls([WALL, Rect2(0.0, 0.0, 16.0, 200.0)] as Array[Rect2])
	var slot: int = _fire(Vector2(300.0, 0.0), HOME, 5.0)
	mgr.set_bounce(slot, 2)
	_run(120)
	check(not mgr.is_alive(slot) and expired.size() == 1 and expired[0][3], "after its bounces a shot ends on the next wall, with the wall flag")
	check_equal(mgr.wall_hits, 3, "that took three wall hits")


## Bounce on a circling shot (orbit as a modifier, 5A; owner: "Build it"): at a wall across its
## circle it turns back round the way it came, staying on its circle and out of the wall, one bounce
## spent each time, and it ends on the wall once they are spent. A 50 px circle round CIRCLE and
## a wall from x 140 cut it at about +-37 degrees; at 2 rad/s it meets the wall after 1.25 s, then
## every 2.5 s on the open arc's other end. A circling shot with 3 bounces; its slot.
func _a_circling_shot_by_a_wall() -> int:
	_walls([Rect2(140.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	var slot: int = OrbitShot.start(mgr, 0, 50.0, PI, 2.0, 10.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 1, CIRCLE)
	check(mgr.set_bounce(slot, 3), "a circling shot takes bounce")
	return slot


## Steps the shot in `slot` `steps` times; whether it was ever inside the wall.
func _run_circling(slot: int, steps: int) -> bool:
	var inside: bool = false
	for _i in steps:
		mgr.step(DT)
		inside = inside or (mgr.is_alive(slot) and mgr.get_position_of(slot).x > 141.0)
	return inside


func test_a_circling_shot_bounces_back_round_its_circle() -> void:
	var slot: int = _a_circling_shot_by_a_wall()
	_run(90)
	check(mgr.is_alive(slot) and mgr.wall_hits == 1 and expired.is_empty(), "it met the wall once and lives on (%d wall hits)" % mgr.wall_hits)
	check(absf(mgr.get_position_of(slot).distance_to(CIRCLE) - 50.0) < 0.5, "still on its circle (%s)" % mgr.get_position_of(slot))
	var away: Vector2 = mgr.get_position_of(slot) - CIRCLE
	check(away.cross(mgr.get_velocity_of(slot)) < 0.0, "going round the other way now")


func test_a_circling_shot_swings_to_and_fro_never_inside_the_wall() -> void:
	var slot: int = _a_circling_shot_by_a_wall()
	check(not _run_circling(slot, 480), "never inside the wall")
	check(mgr.wall_hits == 3 and mgr.is_alive(slot), "it swings to and fro on the open arc, a bounce each end (%d wall hits)" % mgr.wall_hits)


func test_a_circling_shot_ends_on_the_wall_once_its_bounces_are_spent() -> void:
	var slot: int = _a_circling_shot_by_a_wall()
	_run(570)
	check(not mgr.is_alive(slot) and expired.size() == 1 and expired[0][3], "its bounces spent, it ends on the wall (%d wall hits)" % mgr.wall_hits)


func test_a_ghost_shot_flies_through_a_wall_and_hits_what_is_behind_it() -> void:
	_walls([WALL])
	var slot: int = _fire(Vector2(300.0, 0.0))
	mgr.set_ghost(slot)
	var enemy: Node2D = _target(Vector2(250.0, 100.0), 8.0)
	_run(40)
	check(mgr.wall_hits == 0 and hits.size() == 1 and hits[0][1] == enemy, "a ghost shot flies through a wall and hits what is behind it")


# --- Spiral --------------------------------------------------------------------------------


## A shot weaving a spiral 20 px wide, a second on; its slot, and the lowest and highest it went
## off its line.
func _a_spiral_for_a_second() -> Array:
	var slot: int = _fire(Vector2(100.0, 0.0), HOME, 4.0)
	mgr.set_spiral(slot, 20.0)
	var low: float = 0.0
	var high: float = 0.0
	for _i in 60:
		mgr.step(DT)
		var y: float = mgr.get_position_of(slot).y - 100.0
		low = minf(low, y)
		high = maxf(high, y)
	return [slot, low, high]


func test_a_spiral_swings_half_its_width_either_side() -> void:
	var run: Array = _a_spiral_for_a_second()
	check(absf(run[2] - 10.0) < 0.5 and absf(run[1] + 10.0) < 0.5, "a spiral 20 px wide swings 10 px either side (%f, %f)" % [run[1], run[2]])


func test_a_spiral_shot_still_travels_at_its_speed() -> void:
	var slot: int = _a_spiral_for_a_second()[0]
	check(absf(mgr.get_position_of(slot).x - 150.0) < 0.5 or mgr.get_position_of(slot).x > 140.0, "a spiral shot still travels at its speed (%s)" % mgr.get_position_of(slot))


func test_a_spiral_needs_a_width() -> void:
	var straight: int = _fire(Vector2(100.0, 0.0), Vector2(50.0, 200.0), 4.0, 2)
	check(not mgr.set_spiral(straight, 0.0), "a spiral needs a width")


# --- Return --------------------------------------------------------------------------------


## A returning shot of seat 0 (pierce 5, tag 7) from its caster at HOME past an enemy, 70 steps
## on; its slot and the farthest it went.
func _a_return_past_an_enemy() -> Array:
	mgr.set_anchor(0, HOME)
	_target(Vector2(110.0, 100.0), 8.0)
	var slot: int = mgr.spawn(0, HOME, Vector2(120.0, 0.0), 1.0, 3.0, ManagerScript.LAYER_ENEMY, 5, 7)
	check(mgr.set_return(slot), "return is accepted")
	var farthest: float = 0.0
	for _i in 70:
		mgr.step(DT)
		if mgr.is_alive(slot):
			farthest = maxf(farthest, mgr.get_position_of(slot).x)
	return [slot, farthest]


func test_a_returning_shot_flies_out_for_half_its_life() -> void:
	var farthest: float = _a_return_past_an_enemy()[1]
	check(farthest > 105.0 and farthest < 125.0, "it flies out for half its life (%f)" % farthest)


func test_a_returning_shot_hits_on_the_way_out_and_again_on_the_way_back() -> void:
	_a_return_past_an_enemy()
	check_equal(hits.size(), 2, "it hits the enemy on the way out and again on the way back")


func test_a_returning_shot_ends_back_at_its_caster_not_on_a_wall() -> void:
	var slot: int = _a_return_past_an_enemy()[0]
	check(not mgr.is_alive(slot) and expired.size() == 1 and (expired[0][1] as Vector2).distance_to(HOME) < 8.0, "it ends back at its caster")
	check(expired.size() == 1 and not expired[0][3], "not on a wall")


func test_a_returning_shot_with_no_caster_to_return_to_ends() -> void:
	mgr.set_anchor(0, HOME)
	mgr.clear_anchor(0)
	var lost: int = mgr.spawn(0, HOME, Vector2(120.0, 0.0), 1.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 8)
	mgr.set_return(lost)
	_run(40)
	check(not mgr.is_alive(lost), "a returning shot with no caster to return to ends")


## Rules R4a: a returning shot keeps homing on its way back: its way home bends toward a target
## near its path at the homing rate, and it still gets home (the bend stays under a right angle).
## A homing returning shot on its way back, its caster moved to (150, 100) and a target off its
## straight way home (the way out never saw it), stepped until it ends; the target.
func _a_homing_return_on_its_way_back() -> Node2D:
	mgr.set_anchor(0, HOME)
	var slot: int = mgr.spawn(0, HOME, Vector2(240.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_ENEMY, 5, 7)
	mgr.set_return(slot)
	mgr.set_homing(slot, 4.0, 80.0)
	_run(95)
	check(mgr.is_alive(slot) and mgr.get_velocity_of(slot).x < 0.0, "it is on its way back")
	mgr.set_anchor(0, Vector2(150.0, 100.0))
	var enemy: Node2D = _target(Vector2(330.0, 128.0), 8.0)
	var steps: int = 0
	while mgr.is_alive(slot) and steps < 120:
		mgr.step(DT)
		steps += 1
	check(not mgr.is_alive(slot), "it ended")
	return enemy


func test_a_returning_shot_homes_on_its_way_back() -> void:
	var enemy: Node2D = _a_homing_return_on_its_way_back()
	check(hits.size() == 1 and hits[0][1] == enemy, "it turned to the target near its path (%d hits)" % hits.size())


func test_a_homing_returning_shot_still_ends_back_at_its_caster() -> void:
	_a_homing_return_on_its_way_back()
	check(expired.size() == 1 and (expired[0][1] as Vector2).distance_to(Vector2(150.0, 100.0)) < 12.0, "it still ended back at its caster (%s)" % [expired])


## Regression (rules R4 F4): the way home took life, so a shot whose caster walked away expired
## half way home. A boomerang always comes home: the way back takes no life. A returning shot on
## its way back, its caster walked away so the way home is twice its whole life's flight; its slot.
func _a_return_whose_caster_walked_away() -> int:
	mgr.set_anchor(0, HOME)
	var slot: int = mgr.spawn(0, HOME, Vector2(120.0, 0.0), 1.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 7)
	mgr.set_return(slot)
	_run(35)
	check(mgr.is_alive(slot) and mgr.get_velocity_of(slot).x < 0.0, "it is on its way back")
	mgr.set_anchor(0, Vector2(50.0, 340.0))
	return slot


func test_a_returning_shot_outlives_its_life_on_the_way_home() -> void:
	var slot: int = _a_return_whose_caster_walked_away()
	_run(120)
	check(mgr.is_alive(slot), "it is still on its way home long after its life (%s)" % mgr.get_position_of(slot))


func test_a_returning_shot_ends_at_a_caster_who_walked_away() -> void:
	var slot: int = _a_return_whose_caster_walked_away()
	var steps: int = 0
	while mgr.is_alive(slot) and steps < 720:
		mgr.step(DT)
		steps += 1
	check(expired.size() == 1 and (expired[0][1] as Vector2).distance_to(Vector2(50.0, 340.0)) < 8.0, "it ends at its caster (%s)" % [expired])


# --- Linger --------------------------------------------------------------------------------


## A 1 s shot lingering 0.5 s, 31 steps on (half its life); its slot and where it stopped.
func _a_lingering_shot() -> Array:
	var slot: int = _fire(Vector2(100.0, 0.0), HOME, 1.0)
	mgr.set_linger(slot, 0.5)
	_run(31)
	return [slot, mgr.get_position_of(slot)]


func test_a_lingering_shot_hangs_in_the_air_half_way_through_its_flight() -> void:
	var held: Array = _a_lingering_shot()
	_run(15)
	check(mgr.get_position_of(held[0]).is_equal_approx(held[1]), "a lingering shot hangs in the air")
	check(absf((held[1] as Vector2).x - 100.0) < 4.0, "after half its life (%s)" % held[1])


func test_a_lingering_shot_flies_on_after_its_stop() -> void:
	var held: Array = _a_lingering_shot()
	_run(45)
	check(mgr.is_alive(held[0]) and mgr.get_position_of(held[0]).x > (held[1] as Vector2).x + 10.0, "then flies on")


func test_a_lingering_shot_flies_its_whole_flight_before_its_life_ends() -> void:
	var held: Array = _a_lingering_shot()
	_run(105)
	check(not mgr.is_alive(held[0]) and expired.size() == 1, "it ends by its life, which the stop did not use up")
	check(expired.size() == 1 and absf((expired[0][1] as Vector2).x - 100.0 - 50.0) < 6.0, "having flown the whole flight (%s)" % [expired])


# --- Speed over life -----------------------------------------------------------------------


## Speed over life (`set_speed_curve`): a bursting curve (every shot's is 2.2 to 0.2, ease 1.5; here
## 3 to 0, ease 2) leaves faster and eases out to a stop as its life runs out, about as far as a
## plain shot, only sooner; an even curve the other way speeds up. A plain 1 s shot (tag 1) and a
## bursting one (tag 2) beside it; their slots (plain, bursting).
func _a_plain_and_a_bursting_shot() -> Vector2i:
	var plain: int = _fire(Vector2(100.0, 0.0), HOME, 1.0, 1)
	var slot: int = _fire(Vector2(100.0, 0.0), Vector2(50.0, 200.0), 1.0, 2)
	check(mgr.set_speed_curve(slot, 3.0, 0.0, 2.0), "a speed curve is accepted on a flying shot")
	return Vector2i(plain, slot)


func test_a_bursting_shot_leaves_faster() -> void:
	var slot: int = _a_plain_and_a_bursting_shot().y
	check(mgr.get_velocity_of(slot).is_equal_approx(Vector2(300.0, 0.0)), "it leaves three times faster (%s)" % mgr.get_velocity_of(slot))


func test_a_bursting_shot_is_well_ahead_after_a_fifth_of_its_life() -> void:
	var slots: Vector2i = _a_plain_and_a_bursting_shot()
	_run(12)
	var ahead: float = mgr.get_position_of(slots.y).x - mgr.get_position_of(slots.x).x
	check(ahead > 20.0, "after a fifth of its life it is well ahead of a plain shot (%f px)" % ahead)


func test_a_bursting_shot_slows_keeping_its_heading() -> void:
	var slot: int = _a_plain_and_a_bursting_shot().y
	_run(12)
	var before: float = mgr.get_velocity_of(slot).x
	_run(18)
	var half: float = mgr.get_velocity_of(slot).x
	# (Speed at half its life, read at the middle of the step: 100 x 3 x (0.5 + 1/120)^2 = 77.5.)
	check(half < before and absf(half - 77.5) < 1.0, "it slows down: %f px/s at half its life" % half)
	check(absf(mgr.get_velocity_of(slot).y) < 0.001, "keeping its heading")


func test_a_bursting_shot_eases_to_a_stop_as_its_life_ends() -> void:
	var slots: Vector2i = _a_plain_and_a_bursting_shot()
	_run(59)
	check(mgr.is_alive(slots.y) and mgr.get_velocity_of(slots.y).x < 1.0, "it is all but still at the end of its life (%f)" % mgr.get_velocity_of(slots.y).x)
	_run(3)
	check(not mgr.is_alive(slots.y) and not mgr.is_alive(slots.x), "and ends with its life")


func test_a_bursting_shot_goes_as_far_as_a_plain_shot() -> void:
	_a_plain_and_a_bursting_shot()
	_run(62)
	var ends: Dictionary = {}
	for row: Array in expired:
		ends[row[2]] = row[1]
	# Its curve's mean is 1 (3 + (0 - 3) x 2 / 3), so it goes as far: read at the middle of each
	# step, within a pixel (read at the step's end, a front-loaded curve fell a step's change short).
	check(ends.has(1) and ends.has(2) and absf((ends[2] as Vector2).x - (ends[1] as Vector2).x) < 1.0, "as far as the plain shot went (%s)" % [ends])


func test_an_even_speed_curve_is_half_way_at_half_its_life() -> void:
	var speeding: int = _fire(Vector2(100.0, 0.0), HOME, 1.0)
	mgr.set_speed_curve(speeding, 0.5, 2.0, 1.0)
	_run(30)
	# (100 x (0.5 + 1.5 x (1 - (0.5 + 1/120))) = 123.75: read at the middle of the step.)
	check(absf(mgr.get_velocity_of(speeding).x - 123.75) < 0.5, "an even curve is half way at half its life (%f)" % mgr.get_velocity_of(speeding).x)


func test_a_still_shot_takes_no_speed_curve() -> void:
	var still: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2.ZERO, 1.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 1, ManagerScript.MOTION_STILL)
	check(not mgr.set_speed_curve(still, 2.0, 0.0, 1.0), "a still shot takes no curve")


## A circling shot takes one (orbit as a modifier, 5A): the orbit pass turns it by the curve's
## speed; its velocity is left to that pass, not scaled here.
func test_a_circling_shot_takes_a_speed_curve_read_by_the_orbit_pass() -> void:
	mgr.set_anchor(0, Vector2(100.0, 100.0))
	var orbit: int = OrbitShot.start(mgr, 0, 30.0, 0.0, 1.0, 1.0)
	var round_velocity: Vector2 = mgr.get_velocity_of(orbit)
	check(mgr.set_speed_curve(orbit, 2.0, 0.0, 1.0) and mgr.get_velocity_of(orbit) == round_velocity, "a circling shot takes a curve, read by the orbit pass")


func test_a_speed_curve_with_bad_numbers_or_no_shot_is_refused() -> void:
	var flyer: int = _fire(Vector2(10.0, 0.0))
	check(not (mgr.set_speed_curve(flyer, 0.0, 1.0, 1.0) or mgr.set_speed_curve(flyer, 1.0, -1.0, 1.0) or mgr.set_speed_curve(flyer, 1.0, 1.0, 0.0) or mgr.set_speed_curve(flyer, INF, 0.0, 1.0) or mgr.set_speed_curve(-1, 2.0, 0.0, 1.0)), "bad numbers or no shot are refused")


func test_a_huge_speed_start_counts_as_given() -> void:
	var flyer: int = _fire(Vector2(10.0, 0.0))
	check(mgr.set_speed_curve(flyer, 100.0, 0.0, 1.0) and mgr.get_velocity_of(flyer).is_equal_approx(Vector2(1000.0, 0.0)), "a huge start counts as given: no cap (owner, 2026-11-09)")


func test_a_fresh_shot_in_a_curved_shots_slot_keeps_its_speed() -> void:
	var flyer: int = _fire(Vector2(10.0, 0.0))
	mgr.set_speed_curve(flyer, 3.0, 0.0, 2.0)
	mgr.clear()
	var again: int = _fire(Vector2(10.0, 0.0), HOME, 1.0)
	_run(30)
	check(again == flyer and mgr.get_velocity_of(again).is_equal_approx(Vector2(10.0, 0.0)), "a fresh shot in its slot keeps its speed")


func test_every_spells_shot_takes_the_default_speed_curve() -> void:
	var spells: SpellsScript = _spells()
	var plain_spell: int = _fire(Vector2(100.0, 0.0))
	spells._apply_travel(plain_spell, CompiledSpell.new())
	check(mgr.get_velocity_of(plain_spell).is_equal_approx(Vector2(100.0 * SpellLimits.SHOT_SPEED_START, 0.0)), "every spell's shot bursts out, cards or none (%s)" % mgr.get_velocity_of(plain_spell))


func test_a_cards_speed_start_reaches_the_shot() -> void:
	var spells: SpellsScript = _spells()
	var spell := CompiledSpell.new()
	spell.speed_start = 1.5
	var carded: int = _fire(Vector2(100.0, 0.0))
	spells._apply_travel(carded, spell)
	check(mgr.get_velocity_of(carded).is_equal_approx(Vector2(150.0, 0.0)), "a card's start reaches the shot")


# --- Growth --------------------------------------------------------------------------------


## A slow shot (radius 3) growing x2 a second; its slot.
func _a_growing_shot() -> int:
	var slot: int = _fire(Vector2(10.0, 0.0), HOME, 10.0)
	mgr.set_growth(slot, 2.0)
	return slot


func test_a_shot_growing_x2_a_second_is_twice_as_big_after_a_second() -> void:
	var slot: int = _a_growing_shot()
	_run(60)
	check(absf(mgr.get_growth_of(slot) - 2.0) < 0.05, "twice as big after a second (%f)" % mgr.get_growth_of(slot))


func test_growth_has_no_cap_at_a_few_times() -> void:
	var slot: int = _a_growing_shot()
	_run(120)
	check(absf(mgr.get_growth_of(slot) - 4.0) < 0.1, "four times after two: no cap at a few times (%f)" % mgr.get_growth_of(slot))


func test_a_shot_grows_until_it_is_as_big_as_the_room() -> void:
	var slot: int = _a_growing_shot()
	_run(120)
	mgr.set_growth(slot, 1000.0)
	_run(60)
	# Its radius starts at 3 px (`_fire`).
	check(absf(mgr.get_growth_of(slot) * 3.0 - 640.0) < 1.0, "it grows until it is as big as the room, 640 px (%f)" % (mgr.get_growth_of(slot) * 3.0))


func test_a_grown_shot_hits_an_enemy_off_its_line() -> void:
	var big: int = _fire(Vector2(20.0, 0.0), HOME, 10.0)
	mgr.set_growth(big, 3.0)
	var enemy: Node2D = _target(Vector2(130.0, 112.0), 6.0)
	_run(200)
	check(hits.size() == 1 and hits[0][1] == enemy, "a grown shot hits an enemy off its line")


func test_growth_must_be_more_than_1() -> void:
	var slot: int = _fire(Vector2(20.0, 0.0), HOME, 10.0)
	check(not mgr.set_growth(slot, 1.0), "growth must be more than 1")


# --- Sticky --------------------------------------------------------------------------------


## A sticky shot (tag 9, 0.5 s) into two overlapping enemies, 20 steps on; its slot.
func _a_sticky_shot_in_a_pair() -> int:
	pair.append(_target(Vector2(100.0, 100.0), 8.0))
	pair.append(_target(Vector2(104.0, 100.0), 8.0))
	var slot: int = _fire(Vector2(200.0, 0.0), HOME, 3.0, 9)
	mgr.set_sticky(slot, 0.5)
	_run(20)
	return slot


## Both enemies 30 px down; the one the shot is stuck to.
func _move_the_pair_down() -> Node2D:
	for node in pair:
		node.global_position += Vector2(0.0, 30.0)
	return hits[0][1] as Node2D


func test_a_sticky_shot_hits_once_and_stays() -> void:
	var slot: int = _a_sticky_shot_in_a_pair()
	check(hits.size() == 1 and mgr.is_alive(slot), "a sticky shot hits once and stays")


func test_a_sticky_shot_rides_on_its_target_hitting_nothing_more() -> void:
	var slot: int = _a_sticky_shot_in_a_pair()
	var stuck_at: Vector2 = hits[0][2]
	var carrier: Node2D = _move_the_pair_down()
	_run(10)
	check(absf(mgr.get_position_of(slot).y - (carrier.global_position.y + (stuck_at.y - 100.0))) < 0.01, "it rides on its target")
	check_equal(hits.size(), 1, "and hits nothing more while stuck")


func test_a_sticky_shot_expires_on_its_target_when_its_time_is_up() -> void:
	var slot: int = _a_sticky_shot_in_a_pair()
	var carrier: Node2D = _move_the_pair_down()
	_run(50)
	check(not mgr.is_alive(slot) and expired.size() == 1 and expired[0][2] == 9, "it expires where it sticks when the time is up")
	check(expired.size() == 1 and (expired[0][1] as Vector2).distance_to(carrier.global_position) < 12.0, "on its target")


func test_a_shot_stuck_to_a_freed_target_ends() -> void:
	var doomed: Node2D = _target(Vector2(100.0, 100.0), 8.0)
	var stuck: int = _fire(Vector2(200.0, 0.0), HOME, 3.0, 4)
	mgr.set_sticky(stuck, 5.0)
	_run(15)
	mgr.remove_target(doomed)
	doomed.free()
	_run(2)
	check(not mgr.is_alive(stuck), "a shot stuck to a freed target ends")


## A sticky shot sticks where its line of flight comes closest to the target's centre, the same
## spot whichever moment of a step it met the target in (regression: it stuck at the point of
## that step's path nearest the centre, anywhere from the centre to the rim, so a nova it fired
## from inside hit all or half of its ring by chance).
func test_a_sticky_shot_sticks_on_its_line_whatever_the_step() -> void:
	var enemy: Node2D = _target(Vector2(100.0, 103.0), 8.0)
	for n in 6:
		mgr.clear()
		hits.clear()
		# Start a little further back each time: it meets the target at another moment of a step.
		var slot: int = _fire(Vector2(400.0, 0.0), Vector2(30.0 - 1.1 * n, 100.0), 3.0, 9)
		mgr.set_sticky(slot, 1.0)
		_run(15)
		var off: Vector2 = mgr.get_position_of(slot) - enemy.global_position
		check(hits.size() == 1 and off.distance_to(Vector2(0.0, -3.0)) < 0.01, "start %d: it sticks where its line passes the centre: %s" % [n, off])


func test_a_stuck_shot_still_reports_the_way_it_was_flying() -> void:
	_target(Vector2(100.0, 100.0), 8.0)
	var slot: int = _fire(Vector2(200.0, 0.0), HOME, 3.0, 9)
	mgr.set_sticky(slot, 1.0)
	_run(20)
	check(mgr.get_velocity_of(slot).x > 100.0, "a stuck shot still reports the way it was flying")


## It sticks on the step it also reaches a wall: it stays, it does not bounce or end.
func test_a_shot_that_sticks_at_a_wall_stays_stuck() -> void:
	_walls([Rect2(104.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	_target(Vector2(100.0, 100.0), 8.0)
	var wall_slot: int = _fire(Vector2(300.0, 0.0), HOME, 3.0, 8)
	mgr.set_bounce(wall_slot, 2)
	mgr.set_sticky(wall_slot, 1.0)
	_run(12)
	check(mgr.is_alive(wall_slot) and hits.size() == 1 and mgr.get_velocity_of(wall_slot).x > 100.0, "a shot that sticks at a wall stays stuck")


# --- Shield --------------------------------------------------------------------------------


## A standing shield of seat 0 with two charges (tag 5) and three of the imp's shots coming at it,
## 90 steps on; the shield's slot and the imp's shots'.
func _a_shield_and_three_shots() -> Array:
	var shield: int = _fire(Vector2(0.0, 0.0), Vector2(100.0, 100.0), 3.0, 5)
	mgr.set_shield(shield, 2)
	var spawned: Array[int] = []
	for i in 3:
		spawned.append(mgr.spawn(imp, Vector2(160.0 + 20.0 * i, 100.0), Vector2(-100.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_PLAYER, 0, 0))
	_run(90)
	return [shield, spawned]


func test_a_shield_blocks_as_many_enemy_shots_as_its_charges_and_says_so() -> void:
	_a_shield_and_three_shots()
	check(blocked.size() == 2 and blocked[0][0] == 0 and blocked[0][2] == 5, "a shield with two charges blocks two enemy shots and says so (%d)" % blocked.size())


func test_a_shield_with_no_charge_left_survives() -> void:
	var shield: int = _a_shield_and_three_shots()[0]
	check(mgr.get_shield_of(shield) == 0 and mgr.is_alive(shield), "the shield survives with no charge left")


func test_an_enemy_shot_past_the_shields_charges_gets_through() -> void:
	var spawned: Array[int] = _a_shield_and_three_shots()[1]
	var alive: int = 0
	for slot in spawned:
		if mgr.is_alive(slot):
			alive += 1
	check_equal(alive, 1, "the third enemy shot gets through")


func test_a_very_fast_shot_cannot_tunnel_through_a_shield() -> void:
	var wall: int = _fire(Vector2(0.0, 0.0), Vector2(100.0, 100.0), 3.0, 6)
	mgr.set_shield(wall, 1)
	var fast: int = mgr.spawn(EventsScript.NO_PLAYER, Vector2(300.0, 100.0), Vector2(-3000.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_PLAYER, 0, 0)
	_run(6)
	check(not mgr.is_alive(fast) and blocked.size() == 1, "a very fast shot (of no actor: no team) is still stopped")


func test_a_shot_of_no_actor_cannot_have_a_shield() -> void:
	var stray: int = mgr.spawn(EventsScript.NO_PLAYER, Vector2(100.0, 100.0), Vector2.ZERO, 1.0, 3.0, ManagerScript.LAYER_PLAYER, 0, 0)
	check(not mgr.set_shield(stray, 1), "a shot of no actor cannot have a shield")


func test_a_shield_never_stops_a_teammates_shot() -> void:
	var mine: int = _fire(Vector2.ZERO, Vector2(100.0, 100.0))
	var friend: int = _fire(Vector2.ZERO, Vector2(100.0, 100.0), 1.0, 2, 1)
	mgr.set_shield(mine, 1)
	_run(5)
	check(mgr.is_alive(friend) and blocked.is_empty(), "a shield stops other teams' shots only, never a teammate's")


func test_a_moving_shield_blocks_a_fast_shot_in_a_higher_slot() -> void:
	var shield: int = _fire(Vector2(600.0, 0.0), Vector2(100.0, 100.0), 3.0, 5)
	mgr.set_shield(shield, 1)
	var enemy: int = mgr.spawn(EventsScript.NO_PLAYER, Vector2(300.0, 100.0), Vector2(-1500.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_PLAYER, 0, 0)
	_run(8)
	check(enemy > shield and not mgr.is_alive(enemy) and blocked.size() == 1, "a moving shield blocks a fast shot in a higher slot")


func test_a_moving_shield_blocks_a_fast_shot_in_a_lower_slot() -> void:
	var first: int = mgr.spawn(EventsScript.NO_PLAYER, Vector2(300.0, 100.0), Vector2(-1500.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_PLAYER, 0, 0)
	var second: int = _fire(Vector2(600.0, 0.0), Vector2(100.0, 100.0), 3.0, 5)
	mgr.set_shield(second, 1)
	_run(8)
	check(first < second and not mgr.is_alive(first) and blocked.size() == 1, "and a fast shot in a lower slot")


## Regression (rules R4a): a shield's scan was charged to the hit-work budget, so in a step a
## crowd spent it, an enemy shot crossing the shield flew through.
func test_a_shield_blocks_in_a_step_whose_hit_work_is_spent() -> void:
	mgr.set_cap(2000)
	var shield: int = _fire(Vector2.ZERO, Vector2(100.0, 100.0), 3.0, 5)
	mgr.set_shield(shield, 1)
	var enemy: int = mgr.spawn(imp, Vector2(125.0, 100.0), Vector2(-1500.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_PLAYER, 0, 0)
	# A crowd that spends the step's hit work on a target far away.
	_target(Vector2(500.0, 300.0))
	for i in 3 * ManagerScript.WORK_PER_STEP / ManagerScript.HIT_WORK:
		mgr.spawn(i % 4, Vector2(500.0 + float(i % 5), 300.0), Vector2(1.0, 0.0), 10.0)
	mgr.step(DT)
	check(mgr._work_left <= 0, "the crowd spent the step's hit work (%d left)" % mgr._work_left)
	check(not mgr.is_alive(enemy) and blocked.size() == 1, "the shield still blocks the enemy shot crossing it")


# --- Shots and their caster ----------------------------------------------------------------


## Seat 0's wizard at HOME and a wall at x 160.
func _a_caster_by_a_wall() -> Node2D:
	_walls([Rect2(160.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	return _target(HOME, 8.0, ManagerScript.LAYER_PLAYER, 0)


## The manager spares nothing by itself: a shot born in its caster with no `exclude` hits them.
func test_a_shot_never_spares_its_caster_by_itself() -> void:
	var caster: Node2D = _a_caster_by_a_wall()
	var plain: int = _fire(Vector2(200.0, 0.0))
	_run(2)
	check(hits.size() == 1 and hits[0][1] == caster and not mgr.is_alive(plain), "a shot never spares its caster by itself")


## A bouncing shot born in its caster, sparing them (`exclude`); its slot.
func _a_bouncing_shot_that_spares_its_caster(caster: Node2D) -> int:
	var slot: int = _fire(Vector2(200.0, 0.0))
	mgr.set_bounce(slot, 1)
	mgr.exclude(slot, caster)
	return slot


func test_a_shot_does_not_hit_the_caster_it_starts_inside() -> void:
	var slot: int = _a_bouncing_shot_that_spares_its_caster(_a_caster_by_a_wall())
	_run(3)
	check(hits.is_empty() and mgr.is_alive(slot), "it does not hit the caster it starts inside")


func test_a_shot_hits_its_caster_when_it_comes_back() -> void:
	var caster: Node2D = _a_caster_by_a_wall()
	var slot: int = _a_bouncing_shot_that_spares_its_caster(caster)
	_run(103)
	check(hits.size() == 1 and hits[0][1] == caster and hits[0][0] == 0, "it hits the caster when it comes back")
	check(hits.size() == 1 and (hits[0][2] as Vector2).x > 50.0 and (hits[0][2] as Vector2).x < 70.0, "at the caster")
	check(not mgr.is_alive(slot), "that spends it")


## A shot cast from beside its own caster's body and aimed back across it (a nova's ring from a staff
## tip, owner 2026-11-07) passes that body, however far off it was cast, and hits it when it comes
## back. Cast `off` px from the centre of seat 0's wizard at (100, 100), the reach 11 (8 + the
## shot's 3): a staff tip's place; a wall behind the wizard to bounce it back. The wizard, and the
## steps to pass them.
func _a_shot_cast_beside_its_caster(off: float) -> Array:
	_walls([Rect2(10.0, 0.0, 16.0, 200.0)] as Array[Rect2])
	var caster: Node2D = _target(Vector2(100.0, 100.0), 8.0, ManagerScript.LAYER_PLAYER, 0)
	var slot: int = _fire(Vector2(-200.0, 0.0), Vector2(100.0 + off, 100.0))
	mgr.set_bounce(slot, 1)
	mgr.exclude(slot, caster)
	return [caster, slot, 10 + int(off / 3.0)]


func _passes_its_caster(off: float) -> void:
	var cast: Array = _a_shot_cast_beside_its_caster(off)
	_run(cast[2])
	check(hits.is_empty() and mgr.is_alive(cast[1]), "a shot cast %d px off its caster, aimed back across them, passes them (%d hits)" % [int(off), hits.size()])


func _hits_its_caster_coming_back(off: float) -> void:
	var cast: Array = _a_shot_cast_beside_its_caster(off)
	_run(cast[2] + 80)
	check(hits.size() == 1 and hits[0][1] == cast[0], "cast %d px off, it hits them when it bounces back (%d hits)" % [int(off), hits.size()])


func test_a_shot_cast_18_px_beside_its_caster_and_aimed_back_passes_them() -> void:
	_passes_its_caster(18.0)


func test_a_shot_cast_40_px_beside_its_caster_and_aimed_back_passes_them() -> void:
	_passes_its_caster(40.0)


func test_a_shot_cast_18_px_beside_its_caster_hits_them_when_it_bounces_back() -> void:
	_hits_its_caster_coming_back(18.0)


func test_a_shot_cast_40_px_beside_its_caster_hits_them_when_it_bounces_back() -> void:
	_hits_its_caster_coming_back(40.0)


## A shot that spares a body not its caster's (a payload's source) and starts off it hits it.
func test_a_payload_that_starts_off_its_source_and_comes_at_it_hits_it() -> void:
	var source: Node2D = _target(Vector2(100.0, 100.0), 8.0, ManagerScript.LAYER_ENEMY)
	var payload: int = _fire(Vector2(-200.0, 0.0), Vector2(118.0, 100.0))
	mgr.exclude(payload, source)
	_run(20)
	check(hits.size() == 1 and hits[0][1] == source, "a payload that starts off its source and comes at it hits it (%d hits)" % hits.size())


## Everything hits everything (actors G3c): a wizard's shot hits a teammate, never passes one, and
## spares the body it starts on (`exclude`); an enemy's hits another enemy; a shot of no actor hits
## a wizard and an enemy alike.
func test_a_wizards_shot_hits_the_teammate_in_its_way() -> void:
	var friend: Node2D = _target(Vector2(100.0, 100.0), 8.0, ManagerScript.LAYER_PLAYER, 1)
	var mine: Node2D = _target(Vector2(60.0, 100.0), 8.0, ManagerScript.LAYER_PLAYER, 0)
	var slot: int = _fire(Vector2(200.0, 0.0), HOME, 2.0, 12)
	mgr.exclude(slot, mine)
	_run(30)
	check(hits.size() == 1 and hits[0][1] == friend and hits[0][0] == 0 and hits[0][3] == 12, "a wizard's shot hits the teammate in its way, not its own wizard (%d hits)" % hits.size())
	check(not mgr.is_alive(slot), "the hit spends it")


func test_a_still_shot_over_a_teammate_hits_them() -> void:
	var friend: Node2D = _target(Vector2(100.0, 100.0), 8.0, ManagerScript.LAYER_PLAYER, 2)
	mgr.spawn(3, Vector2(100.0, 100.0), Vector2.ZERO, 1.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 13, ManagerScript.MOTION_STILL)
	_run(5)
	check(hits.size() == 1 and hits[0][1] == friend, "a still shot over a teammate hits them")


func test_an_enemys_shot_hits_another_enemy_never_its_own_body() -> void:
	var own_body: Node2D = _target(HOME, 8.0, ManagerScript.LAYER_ENEMY, imp)
	var other: Node2D = _target(Vector2(100.0, 100.0), 8.0, ManagerScript.LAYER_ENEMY)
	mgr.exclude(mgr.spawn(imp, HOME, Vector2(200.0, 0.0), 2.0, 3.0, ManagerScript.LAYER_PLAYER, 0, 0), own_body)
	_run(30)
	check(hits.size() == 1 and hits[0][1] == other and hits[0][1] != own_body, "an enemy's shot hits another enemy (%d hits)" % hits.size())


func test_a_piercing_shot_of_no_actor_hits_a_wizard_then_an_enemy() -> void:
	var wizard: Node2D = _target(Vector2(100.0, 100.0), 8.0, ManagerScript.LAYER_PLAYER, 0)
	var enemy: Node2D = _target(Vector2(150.0, 100.0), 8.0, ManagerScript.LAYER_ENEMY)
	mgr.spawn(EventsScript.NO_PLAYER, HOME, Vector2(200.0, 0.0), 2.0, 3.0, ManagerScript.LAYER_PLAYER, 1, 0)
	_run(40)
	check(hits.size() == 2 and hits[0][1] == wizard and hits[1][1] == enemy, "a shot of no actor hits the wizard, then the enemy (%d hits)" % hits.size())


# --- Spells._apply_travel ------------------------------------------------------------------


func test_a_plain_spell_sets_no_behaviour_on_its_shot() -> void:
	var spells: SpellsScript = _spells()
	var plain_slot: int = _fire(Vector2(100.0, 0.0))
	spells._apply_travel(plain_slot, CompiledSpell.new())
	check(mgr.get_shield_of(plain_slot) == 0 and mgr.get_growth_of(plain_slot) == 1.0, "a plain spell sets nothing")


## A spell with every behaviour cast at a wall (passed: the shot is a ghost) from its caster at
## HOME; the shot's slot.
func _a_spell_with_every_behaviour() -> int:
	var spells: SpellsScript = _spells()
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
	_walls([Rect2(100.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	mgr.set_anchor(0, HOME)
	var slot: int = _fire(Vector2(200.0, 0.0), HOME, 1.2)
	spells._apply_travel(slot, spell)
	return slot


func test_a_spells_shield_strength_is_rounded() -> void:
	var slot: int = _a_spell_with_every_behaviour()
	check_equal(mgr.get_shield_of(slot), 3, "shield strength 2.6 is rounded")


func test_a_spell_with_growth_grows_its_shot() -> void:
	var slot: int = _a_spell_with_every_behaviour()
	_run(28)
	check(mgr.get_growth_of(slot) > 1.0, "the shot grows")


func test_a_ghost_spells_shot_passes_a_wall_without_bouncing() -> void:
	var slot: int = _a_spell_with_every_behaviour()
	_run(28)
	check(mgr.is_alive(slot) and mgr.get_position_of(slot).x > 132.0 and mgr.get_velocity_of(slot).x > 0.0, "a ghost passes the wall without bouncing")


func test_a_returning_spells_shot_flies_back_to_the_caster() -> void:
	var slot: int = _a_spell_with_every_behaviour()
	_run(178)
	check(not mgr.is_alive(slot) and not expired.is_empty() and (expired.back()[1] as Vector2).distance_to(HOME) < 1.0, "a returning shot flies back to the caster")


func test_a_bounce_card_turns_the_shot_at_a_wall() -> void:
	var spells: SpellsScript = _spells()
	var bouncer := CompiledSpell.new()
	bouncer.behaviours.resize(ModifierBase.Behaviour.size())
	# 1.4 rounds to one bounce.
	bouncer.behaviours[ModifierBase.Behaviour.BOUNCE] = 1.4
	_walls([Rect2(160.0, 0.0, 32.0, 200.0)] as Array[Rect2])
	var bounced: int = _fire(Vector2(200.0, 0.0), HOME, 3.0)
	spells._apply_travel(bounced, bouncer)
	_run(60)
	check(mgr.is_alive(bounced) and mgr.get_velocity_of(bounced).x < 0.0, "a bounce card turns the shot at a wall")


# --- The setters' refusals -----------------------------------------------------------------


func test_travel_behaviours_are_refused_for_still_shots() -> void:
	var still: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2.ZERO, 1.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 1, ManagerScript.MOTION_STILL)
	check(not (mgr.set_bounce(still, 1) or mgr.set_ghost(still) or mgr.set_return(still) or mgr.set_sticky(still, 1.0)), "travel behaviours are refused for still shots")


func test_return_is_refused_for_an_orbit_shot() -> void:
	mgr.set_anchor(0, Vector2(100.0, 100.0))
	var orbit: int = OrbitShot.start(mgr, 0, 30.0, 0.0, 1.0, 1.0)
	check(not mgr.set_return(orbit), "return, which steers a straight flight, is refused for orbit shots")


func test_the_setters_refuse_empty_or_unknown_slots() -> void:
	check(not (mgr.set_bounce(-1, 1) or mgr.set_bounce(99999, 1) or mgr.set_linger(5, 1.0)), "behaviours are refused for empty or unknown slots")


func test_the_setters_refuse_bad_numbers() -> void:
	var flyer: int = _fire(Vector2(10.0, 0.0))
	check(not (mgr.set_bounce(flyer, -1) or mgr.set_linger(flyer, 0.0) or mgr.set_sticky(flyer, INF)), "bad numbers are refused")


func test_a_fresh_shot_has_no_leftovers_from_its_slots_last_one() -> void:
	var flyer: int = _fire(Vector2(10.0, 0.0))
	mgr.set_bounce(flyer, 3)
	mgr.set_ghost(flyer)
	mgr.set_growth(flyer, 2.0)
	mgr.set_shield(flyer, 2)
	mgr.clear()
	var again: int = _fire(Vector2(10.0, 0.0))
	check(again == flyer and is_equal_approx(mgr.get_growth_of(again), 1.0) and mgr.get_shield_of(again) == 0, "a fresh shot has no leftovers from the slot's last one")


# --- The cost ------------------------------------------------------------------------------


func test_many_shots_with_behaviours_stay_cheap() -> void:
	mgr.set_cap(3000)
	_walls([Rect2(300.0, 0.0, 16.0, 360.0), Rect2(0.0, 0.0, 16.0, 360.0)] as Array[Rect2])
	for i in 40:
		_target(Vector2(100.0 + float(i % 10) * 20.0, 40.0 + float(i / 10) * 60.0), 8.0)
	mgr.set_anchor(0, Vector2(150.0, 180.0))
	for i in 1500:
		var slot: int = mgr.spawn(i % 4, Vector2(150.0, 20.0 + float(i % 300)), Vector2(100.0 + float(i % 7) * 40.0, float(i % 5) * 20.0 - 40.0), 4.0, 3.0, ManagerScript.LAYER_ENEMY, 2, i + 1)
		match i % 6:
			0: mgr.set_bounce(slot, 3)
			1: mgr.set_spiral(slot, 16.0)
			2: mgr.set_return(slot)
			3: mgr.set_linger(slot, 0.4)
			4: mgr.set_growth(slot, 1.5)
			5: mgr.set_shield(slot, 1)
	var started: int = Time.get_ticks_usec()
	_run(120)
	var per_step: float = float(Time.get_ticks_usec() - started) / 120.0
	# The budget (docs/PLAN.md) is a few milliseconds a frame for the whole manager; headless
	# test machines are slower, so only a gross regression fails.
	check(per_step < 8000.0, "1,500 shots with behaviours step in %d us" % int(per_step))
