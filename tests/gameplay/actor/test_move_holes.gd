extends "res://tests/support/suite.gd"
## A body's move in a room with holes (hub rework HR-H1, docs/milestones/hub-rework.md, "Holes" 2 and
## 3): its own walk stops at a hole's lip; a dash and what is done to it (a pull, a recoil, Combat's
## push) cross; a teleport, a swap and a portal's exit put it over a hole at once, and the walk after
## does not push it back out; a push into a crack while it walks away keeps it in; a dash may leave
## the room's bounds over a hole. The step is slid in two parts (`Actor.move`), so a body is never
## walked into a hole while it is pushed. Falling is HR-H2's: here a body over a hole stays there.
## Real actors (a Mover each, the default footprint's 6 px circle), moved as the game moves them.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")

const START: Vector2 = Vector2(150.0, 100.0)
## A crack four cells wide across the room, from x 200 to 232.
const CRACK: Rect2 = Rect2(200.0, 0.0, 32.0, 360.0)
## Where a walking body's 6 px circle stops before it.
const LIP: float = 194.0


## Combat with the push set by hand.
class FakeCombat:
	extends CombatScript
	var push: Vector2 = Vector2.ZERO

	func own_pace(_actor: Node2D, _id: int) -> float:
		return 1.0

	func own_knockback(_actor: Node2D, _id: int, _delta: float) -> Vector2:
		return push


var _world: Fixture
var _combat: FakeCombat


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_world.projectiles.set_holes([CRACK] as Array[Rect2])
	_combat = own(FakeCombat.new()) as FakeCombat


func after_each() -> void:
	_world.free_all()


## A wizard-like body on seat `seat` at `at`.
func _walker(at: Vector2 = START, seat: int = 0) -> Actor:
	var controller := Fixture.Scripted.new()
	controller.team = ActorsScript.TEAM_WIZARDS
	controller.seat = seat
	var body: Actor = _world.actor(at, [&"mover", &"caster"], controller)
	body.combat = _combat
	return body


func _controller(body: Actor) -> Fixture.Scripted:
	return body.controller as Fixture.Scripted


## Ask for a move of `body` by `move`, as the spells do.
func _ask(body: Actor, mode: StringName, move: Vector2, seconds: float) -> void:
	_world.bus.caster_move_requested.emit(body.caster_number(), mode, move, seconds, _world.tag_of(body))


## `count` ticks of `step` seconds (the fixture's 1/16 unless said) as the game steps a body: its
## step, then its move (`Actor.tick_step`).
func _run(count: int, step: float = Fixture.STEP) -> void:
	for i in count:
		for body in _world.actors:
			if is_instance_valid(body) and body.is_inside_tree():
				body.tick_step(step)
		_world.projectiles.step(step)
		_world.spells.step(step)


func test_walking_stops_at_a_holes_lip() -> void:
	var body: Actor = _walker()
	_controller(body).move = Vector2.RIGHT
	_run(40)
	check(absf(body.global_position.x - LIP) < 0.01, "it stands at the lip, its circle at the crack's edge: %s" % body.global_position)
	_controller(body).move = Vector2(1.0, 1.0)
	_run(4)
	check(absf(body.global_position.x - LIP) < 0.01 and body.global_position.y > START.y + 10.0, "a walk along it slides on: %s" % body.global_position)


func test_walking_stops_at_a_hole_from_either_side() -> void:
	var body: Actor = _walker(Vector2(300.0, 100.0))
	_controller(body).move = Vector2.LEFT
	_run(40)
	check(absf(body.global_position.x - 238.0) < 0.01, "from the far side too: %s" % body.global_position)


func test_a_dash_crosses_a_hole() -> void:
	var body: Actor = _walker()
	_ask(body, &"dash", Vector2(150.0, 0.0), 0.5)
	_run(10)
	check(body.global_position.distance_to(START + Vector2(150.0, 0.0)) < 0.5, "it dashed over the crack, its whole way: %s" % body.global_position)


func test_a_dash_that_ends_over_a_hole_stays_there() -> void:
	# Falling is HR-H2's: until then the walk after it does not push it back out.
	var body: Actor = _walker()
	_ask(body, &"dash", Vector2(66.0, 0.0), 0.25)
	_run(8)
	check(body.global_position.distance_to(Vector2(216.0, 100.0)) < 0.5, "it ended over the crack and stays: %s" % body.global_position)
	check(_world.projectiles.is_hole(body.global_position), "over a hole")


func test_a_dash_along_a_lip_is_not_held_back_by_it() -> void:
	# Its circle over the crack's edge, its centre on the ground, the whole way.
	var body: Actor = _walker(Vector2(196.0, 40.0))
	_ask(body, &"dash", Vector2(0.0, 120.0), 0.5)
	_run(8)
	check(body.global_position.distance_to(Vector2(196.0, 160.0)) < 0.01, "it dashed its whole way along the lip: %s" % body.global_position)
	_run(2)
	check(absf(body.global_position.x - LIP) < 0.01, "standing, it is nudged back onto the ground: %s" % body.global_position)


func test_a_teleport_crosses_a_hole_and_onto_one() -> void:
	var over: Actor = _walker()
	_ask(over, &"teleport", Vector2(100.0, 0.0), 0.0)
	check_equal(over.global_position, START + Vector2(100.0, 0.0), "over the crack at once")
	var onto: Actor = _walker(START, 1)
	_ask(onto, &"teleport", Vector2(66.0, 0.0), 0.0)
	_controller(onto).move = Vector2.LEFT
	_run(1)
	check(_world.projectiles.is_hole(onto.global_position), "the walk after a jump onto the crack does not push it out: %s" % onto.global_position)


func test_a_swap_and_a_portals_exit_put_a_body_over_a_hole() -> void:
	var body: Actor = _walker()
	_world.bus.target_move_requested.emit(1, body, Vector2(216.0, 100.0))
	check_equal(body.global_position, Vector2(216.0, 100.0), "the swap puts it on the crack at once")
	_controller(body).move = Vector2.RIGHT
	_run(1)
	check(_world.projectiles.is_hole(body.global_position), "and its walk does not push it out: %s" % body.global_position)
	var gone: Actor = _walker(START, 1)
	_world.bus.target_move_requested.emit(0, gone, Vector2(260.0, 100.0))
	_controller(gone).move = Vector2.RIGHT
	_run(4)
	check(gone.global_position.x > 260.0, "out of a portal past the crack it walks on: %s" % gone.global_position)


func test_a_swaps_own_move_a_pull_and_a_recoil_cross_a_hole() -> void:
	for mode: StringName in [&"swap", &"pull", &"recoil"]:
		_world.free_all()
		before_each()
		var body: Actor = _walker()
		_ask(body, mode, Vector2(120.0, 0.0), 0.25)
		_run(8)
		check(body.global_position.distance_to(START + Vector2(120.0, 0.0)) < 0.5, "a %s carries it over the crack: %s" % [mode, body.global_position])


func test_walking_into_a_hole_while_pulled_alongside_stops_at_the_lip() -> void:
	# A pull along the crack does not let the walk into it (one slide of their sum would).
	var body: Actor = _walker(Vector2(190.0, 40.0))
	_ask(body, &"pull", Vector2(0.0, 200.0), 1.0)
	_controller(body).move = Vector2.RIGHT
	_run(10)
	check(absf(body.global_position.x - LIP) < 0.01, "its walk stopped at the lip: %s" % body.global_position)
	check(body.global_position.y > 100.0, "the pull went on: %s" % body.global_position)


func test_a_push_carries_a_body_walking_away_into_the_crack() -> void:
	var body: Actor = _walker(Vector2(LIP, 100.0))
	_controller(body).move = Vector2.LEFT
	_combat.push = Vector2(400.0, 0.0)
	_run(1)
	_combat.push = Vector2.ZERO
	check(absf(body.global_position.x - (LIP + 25.0 - 5.625)) < 0.01, "the hit knocked it in, and its walk away went from there: %s" % body.global_position)
	_run(1)
	check(absf(body.global_position.x - (LIP + 25.0 - 2.0 * 5.625)) < 0.01, "walking away does not pop it out to the lip: %s" % body.global_position)
	check(_world.projectiles.is_hole(body.global_position), "it is still over the crack")


func test_a_slow_push_carries_a_walking_body_in_at_the_games_tick() -> void:
	# Regression (review of HR-H1): a push of a Slam's size moves a body 4 px a tick at 60 ticks a
	# second, less than its radius; the walk's slide once pushed it back out of the lip every tick.
	for walk: Vector2 in [Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2.RIGHT]:
		_world.free_all()
		before_each()
		var body: Actor = _walker(Vector2(LIP, 100.0))
		_controller(body).move = walk
		_combat.push = Vector2(240.0, 0.0)
		_run(6, 1.0 / 60.0)
		check(_world.projectiles.is_hole(body.global_position), "a push carries it in, walking %s: %s" % [walk, body.global_position])


func test_a_slow_pull_carries_a_body_walking_alongside_in() -> void:
	var body: Actor = _walker(Vector2(LIP, 100.0))
	_ask(body, &"pull", Vector2(40.0, 0.0), 1.0)
	_controller(body).move = Vector2.DOWN
	_run(30, 1.0 / 60.0)
	check(_world.projectiles.is_hole(body.global_position), "pulled 40 px a second while it walks along the lip, it goes in: %s" % body.global_position)
	check(body.global_position.y > 120.0, "its walk went on: %s" % body.global_position)


func test_a_slow_push_never_lets_the_walk_step_in() -> void:
	# A push along the lip, the circle over it, and a walk into the crack: the walk is dropped where
	# it would set the centre over the hole.
	var body: Actor = _walker(Vector2(197.0, 100.0))
	_controller(body).move = Vector2.RIGHT
	_combat.push = Vector2(0.0, 120.0)
	_run(20, 1.0 / 60.0)
	check(not _world.projectiles.is_hole(body.global_position), "it never walked in: %s" % body.global_position)
	check(body.global_position.y > 130.0, "the push carried it along: %s" % body.global_position)


func test_knockback_at_the_lip_while_walking_into_it() -> void:
	# A push away from the crack and a walk into it: the walk stops at the lip, the push carries on.
	var body: Actor = _walker(Vector2(LIP, 100.0))
	_controller(body).move = Vector2.RIGHT
	_combat.push = Vector2(-80.0, 0.0)
	_run(1)
	check(body.global_position.x <= LIP + 0.01, "it never steps over the lip: %s" % body.global_position)
	check(not _world.projectiles.is_hole(body.global_position), "and stays on the ground")


func test_a_dash_leaves_the_rooms_bounds_over_a_hole() -> void:
	# A room whose edge is a hole (the island's coast): walking stops at it, a dash goes over and out.
	_world.projectiles.set_holes([Rect2(560.0, 0.0, 80.0, 360.0)] as Array[Rect2])
	var walker: Actor = _walker(Vector2(500.0, 100.0))
	_controller(walker).move = Vector2.RIGHT
	_run(30)
	check(absf(walker.global_position.x - 554.0) < 0.01, "a walk stops at the edge's lip: %s" % walker.global_position)
	var dasher: Actor = _walker(Vector2(500.0, 200.0), 1)
	_ask(dasher, &"dash", Vector2(200.0, 0.0), 0.5)
	_run(10)
	check(dasher.global_position.distance_to(Vector2(700.0, 200.0)) < 0.5, "a dash goes off the edge, out of the bounds: %s" % dasher.global_position)


func test_a_room_with_no_holes_moves_a_body_as_one_slide() -> void:
	# The same move as before holes: one slide of the whole velocity.
	_world.projectiles.set_holes([] as Array[Rect2])
	_world.projectiles.set_walls([Rect2(200.0, 0.0, 32.0, 360.0)] as Array[Rect2])
	var body: Actor = _walker(Vector2(LIP, 100.0))
	_controller(body).move = Vector2.RIGHT
	_combat.push = Vector2(0.0, 80.0)
	var from: Vector2 = body.global_position
	body.step(Fixture.STEP)
	var expected: Vector2 = _world.projectiles.slide_body(from, body.velocity * Fixture.STEP, body.wall_radius())
	body.move(Fixture.STEP)
	check_equal(body.global_position, expected, "one slide of the sum")
	check_equal(body.mover.crossing, Vector2.ZERO, "the crossing share is used by the move")
	# The velocity is summed in the order it was before holes (a pull, the walk, the push), which
	# single-precision vectors would otherwise round apart.
	_world.free_all()
	before_each()
	_world.projectiles.set_holes([] as Array[Rect2])
	var pulled: Actor = _walker(START)
	_ask(pulled, &"pull", Vector2(0.1, 0.3), 0.7)
	_controller(pulled).move = Vector2(0.6, 0.8)
	_combat.push = Vector2(0.7, 0.1)
	pulled.step(Fixture.STEP)
	var pull: Vector2 = Vector2(0.1, 0.3) / 0.7
	var share: Vector2 = pull * Fixture.STEP / Fixture.STEP
	check_equal(pulled.velocity, share + Vector2(0.6, 0.8).limit_length(1.0) * pulled.mover.speed * 1.0 + _combat.push, "moves, then the walk, then the push")



func test_a_snapshot_keeps_the_holes_and_a_walk_stops_at_them_again() -> void:
	# The hole grid is the room's (connected biomes CB2: the grid's room layers are DERIVED, laid by
	# whoever lays the room): a restore leaves it as the room lies, and the walking grid worked out
	# from it is set up again, so a walk stops at the lip as before.
	var areas: Dictionary = {"Projectiles": _world.projectiles}
	var body: Actor = _walker()
	_controller(body).move = Vector2.RIGHT
	var snapshot := Snapshot.take(areas, root)
	check_equal(snapshot.problems, PackedStringArray(), "taken without problems")
	_run(40)
	check(absf(body.global_position.x - LIP) < 0.01, "a walk stops at the lip: %s" % body.global_position)
	check_equal(snapshot.restore(areas, root), PackedStringArray(), "restored without problems")
	check(_world.projectiles.has_holes() and _world.projectiles.is_hole(Vector2(216.0, 100.0)), "the crack is there")
	body.position = START
	_run(40)
	check(absf(body.global_position.x - LIP) < 0.01, "and a walk stops at its lip again: %s" % body.global_position)