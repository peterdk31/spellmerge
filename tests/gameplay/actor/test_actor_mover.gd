extends "res://tests/support/suite.gd"
## The Mover (actors G4), the one caster kit: walking at `speed` × the intent's move × Combat's
## pace; a dash the way the intent walks (the aim when standing), a teleport that stops short of
## walls, a hook and a swap to a point, recoils added up per step; a later move replacing an
## earlier one (answered where the actor is); a dash, hook or teleport answered with
## `caster_move_finished`; moves of another caster ignored; a swap that names the actor as target;
## a down actor standing. Ported from tests/gameplay/player/test_player_caster.gd with the same
## expectations, on actors driven by a scripted controller and stepped by hand.
##
## godot --headless --path . --script res://tests/gameplay/actor/test_actor_mover.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")

const START: Vector2 = Vector2(100.0, 100.0)


## Combat with the pace and the push set by hand.
class FakeCombat:
	extends CombatScript
	var factor: float = 1.0
	var push: Vector2 = Vector2.ZERO

	func pace(_actor: Node2D) -> float:
		return factor

	func consume_knockback(_actor: Node2D, _delta: float) -> Vector2:
		return push

	# What an actor's own step asks (by its id).
	func own_pace(_actor: Node2D, _id: int) -> float:
		return factor

	func own_knockback(_actor: Node2D, _id: int, _delta: float) -> Vector2:
		return push


var _world: Fixture
var _combat: FakeCombat
## Every caster_move_finished as [player, mode, position, tag].
var _finished: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_combat = own(FakeCombat.new()) as FakeCombat
	_finished.clear()
	_world.bus.caster_move_finished.connect(func(player: int, mode: StringName, position: Vector2, tag: int) -> void:
		_finished.append([player, mode, position, tag]))


func after_each() -> void:
	_world.free_all()


## A wizard-like actor on seat `seat` (its caster number), with a staff tip 14 px from its hand.
func _mover(seat: int = 0) -> Actor:
	var controller := Fixture.Scripted.new()
	controller.team = ActorsScript.TEAM_WIZARDS
	controller.seat = seat
	var body: Actor = _world.actor(START, [&"mover", &"caster"], controller)
	body.hand_offset = Vector2(0.0, -10.0)
	body.staff_reach = 14.0
	body.combat = _combat
	return body


func _controller(body: Actor) -> Fixture.Scripted:
	return body.controller as Fixture.Scripted


## Ask for a move of `body`, measured like the spells do: `offset` from the staff tip.
func _ask(body: Actor, mode: StringName, offset: Vector2, seconds: float) -> void:
	_world.bus.caster_move_requested.emit(body.caster_number(), mode, body.muzzle_position() + offset, seconds, _world.tag_of(body))


## Ask for a pull of `body` to the world point `to`.
func _pull(body: Actor, mode: StringName, to: Vector2, seconds: float) -> void:
	_world.bus.caster_move_requested.emit(body.caster_number(), mode, to, seconds, _world.tag_of(body))


func test_teleport_jumps_at_once_and_answers() -> void:
	var body: Actor = _mover()
	_ask(body, &"teleport", Vector2(60.0, 0.0), 0.0)
	check_equal(body.global_position, START + Vector2(60.0, 0.0), "the actor is where the teleport aimed")
	check_equal(_finished, [[0, &"teleport", START + Vector2(60.0, 0.0), _world.tag_of(body)]], "the landing is reported with the card's tag")


func test_teleport_stops_short_of_a_wall() -> void:
	var body: Actor = _mover()
	_world.projectiles.set_walls([Rect2(150.0, 60.0, 40.0, 80.0)] as Array[Rect2])
	_ask(body, &"teleport", Vector2(100.0, 0.0), 0.0)
	check(body.global_position.x < 150.0 - Mover.TELEPORT_CLEARANCE + 0.5, "it stops before the wall, got %s" % body.global_position)
	check(body.global_position.x > START.x + 20.0, "but still gets most of the way, got %s" % body.global_position)
	check_equal(_finished.size(), 1, "the short landing is still reported")


func test_teleport_inside_a_wall_does_not_leave_the_start() -> void:
	var body: Actor = _mover()
	_world.projectiles.set_walls([Rect2(100.0, 90.0, 40.0, 20.0)] as Array[Rect2])
	_ask(body, &"teleport", Vector2(80.0, 0.0), 0.0)
	check(body.global_position.distance_to(START) < 0.01, "a wall right at the actor allows no jump, got %s" % body.global_position)


func test_teleport_keeps_the_body_out_of_walls_and_in_the_room() -> void:
	var body: Actor = _mover()
	_world.projectiles.set_walls([Rect2(60.0, 112.0, 200.0, 20.0)] as Array[Rect2])
	_ask(body, &"teleport", Vector2(100.0, 0.0), 0.0)
	check(not _world.projectiles.circle_blocked(body.global_position, body.mover.body_radius), "no part of the body is in the wall, got %s" % body.global_position)
	check(body.global_position.x > START.x + 50.0, "and it still jumped along the wall, got %s" % body.global_position)
	var far: Actor = _mover(1)
	_ask(far, &"teleport", Vector2(900.0, 0.0), 0.0)
	check(not _world.projectiles.circle_blocked(far.global_position, far.mover.body_radius), "the body stays in the room, got %s" % far.global_position)


func test_hook_pulls_to_the_hit_over_the_time_asked() -> void:
	var body: Actor = _mover()
	_pull(body, &"hook", START + Vector2(0.0, 50.0), 0.25)
	check(body.mover.is_moving(), "a hook is a pull in progress")
	_world.run(5)
	check(not body.mover.is_moving(), "the pull ends after the time asked")
	check(body.global_position.distance_to(START + Vector2(0.0, 50.0)) < 0.5, "the actor is at the hit, got %s" % body.global_position)
	check_equal(_finished.size(), 1, "one answer")
	check_equal(_finished[0][1], &"hook", "as a hook")


func test_swap_moves_to_the_target_and_sends_no_answer() -> void:
	var body: Actor = _mover()
	_pull(body, &"swap", START + Vector2(-40.0, 0.0), 0.125)
	_world.run(4)
	check(body.global_position.distance_to(START + Vector2(-40.0, 0.0)) < 0.5, "the actor takes the target's place, got %s" % body.global_position)
	check(_finished.is_empty(), "a swap sends no caster_move_finished (its blast is the target's)")


func test_a_swap_naming_the_actor_as_target_puts_it_there_at_once() -> void:
	var body: Actor = _mover()
	var other: Actor = _mover(1)
	_world.bus.target_move_requested.emit(1, body, Vector2(30.0, 40.0))
	check_equal(body.global_position, Vector2(30.0, 40.0), "the target is there at once")
	check_equal(other.global_position, START, "nobody else moves")


func test_recoil_pushes_back_over_the_time_asked() -> void:
	var body: Actor = _mover()
	_ask(body, &"recoil", Vector2(-30.0, 0.0), 0.125)
	_world.run(4)
	check(body.global_position.distance_to(START + Vector2(-30.0, 0.0)) < 0.5, "pushed back 30 px, got %s" % body.global_position)
	check(_finished.is_empty(), "a recoil sends no answer")


func test_recoils_of_one_step_add_up_and_cancel() -> void:
	var body: Actor = _mover()
	_ask(body, &"recoil", Vector2(-20.0, 0.0), 0.125)
	_ask(body, &"recoil", Vector2(-20.0, 0.0), 0.125)
	var mirrored: Actor = _mover(1)
	_ask(mirrored, &"recoil", Vector2(-20.0, 0.0), 0.125)
	_ask(mirrored, &"recoil", Vector2(20.0, 0.0), 0.125)
	_world.run(4)
	check(body.global_position.distance_to(START + Vector2(-40.0, 0.0)) < 0.5, "two recoils of a step add up, got %s" % body.global_position)
	check(mirrored.global_position.distance_to(START) < 0.01, "a recoil and its mirror cancel, got %s" % mirrored.global_position)


func test_recoils_of_different_times_move_the_sum_of_their_distances() -> void:
	var body: Actor = _mover()
	_ask(body, &"recoil", Vector2(-20.0, 0.0), 0.125)
	_world.run(1)
	_ask(body, &"recoil", Vector2(-20.0, 0.0), 0.5)
	_world.run(12)
	check(body.global_position.distance_to(START + Vector2(-40.0, 0.0)) < 0.01, "two recoils move 20 + 20 px, got %s" % body.global_position)


func test_every_recoil_moves_its_distance_however_many_run() -> void:
	# Regression: at most 8 pushes ran at once and a ninth was dropped.
	var body: Actor = _mover()
	for i: int in 12:
		_ask(body, &"recoil", Vector2(-2.0, 0.0), 1.0)
		_world.run(1)
	_world.run(80)
	check(body.global_position.distance_to(START + Vector2(-24.0, 0.0)) < 0.01, "twelve running recoils move 12 x 2 px, got %s" % body.global_position)


func test_a_dash_walks_its_whole_distance_and_is_answered_one_step_later() -> void:
	var body: Actor = _mover()
	_controller(body).move = Vector2.RIGHT
	_world.run(1)
	var from: Vector2 = body.global_position
	_ask(body, &"dash", Vector2(55.0, 0.0), 0.25)
	for n in 4:
		_world.run(1)
		check(_finished.is_empty(), "no answer while it dashes (step %d)" % n)
	check(body.global_position.distance_to(from + Vector2(55.0, 0.0)) < 0.01, "dashed 55 px, got %s" % (body.global_position - from))
	_world.run(1)
	check_equal(_finished.size(), 1, "answered one step later")
	check_equal(_finished[0][1], &"dash", "as a dash")


func test_a_dash_that_does_not_fit_the_steps_still_goes_its_distance() -> void:
	var body: Actor = _mover()
	_controller(body).aim = Vector2.RIGHT
	_world.run(1)
	_ask(body, &"dash", Vector2(50.0, 0.0), 0.2)
	_world.run(5)
	check(body.global_position.distance_to(START + Vector2(50.0, 0.0)) < 0.01, "the last step is shortened, got %s" % body.global_position)


func test_a_dash_goes_the_way_the_actor_walks_or_else_the_way_it_aims() -> void:
	var walker: Actor = _mover()
	_controller(walker).move = Vector2.UP
	_controller(walker).aim = Vector2.RIGHT
	var stander: Actor = _mover(1)
	_controller(stander).aim = Vector2.LEFT
	_world.run(1)
	var walked: Vector2 = walker.global_position
	_ask(walker, &"dash", Vector2(40.0, 0.0), 0.25)
	_ask(stander, &"dash", Vector2(40.0, 0.0), 0.25)
	_world.run(4)
	check((walker.global_position - walked).y < -39.0, "a walking actor dashes the way it walks: %s" % (walker.global_position - walked))
	check(stander.global_position.distance_to(START + Vector2(-40.0, 0.0)) < 0.01, "a standing one the way it aims: %s" % stander.global_position)


func test_a_homing_dash_turns_toward_a_target() -> void:
	var enemy := own(Node2D.new()) as Node2D
	root.add_child(enemy)
	enemy.global_position = START + Vector2(60.0, 40.0)
	_world.projectiles.add_target(enemy, 8.0, ManagerScript.LAYER_ENEMY)
	var plain: Actor = _mover(1)
	_controller(plain).aim = Vector2.RIGHT
	var homing: Actor = _mover(0)
	_controller(homing).aim = Vector2.RIGHT
	_world.run(1)
	var dash_homing: Homing = _world.spells.move_homing(homing.caster_number())
	dash_homing.turn = 3.0
	dash_homing.reach = 160.0
	_ask(plain, &"dash", Vector2(55.0, 0.0), 0.25)
	_ask(homing, &"dash", Vector2(55.0, 0.0), 0.25)
	_world.run(5)
	check(is_equal_approx(plain.global_position.y, START.y), "a plain dash goes straight: %s" % plain.global_position)
	check(homing.global_position.y > START.y + 3.0, "a homing dash turns toward the target: %s" % homing.global_position)


func test_a_later_move_replaces_an_earlier_one() -> void:
	var body: Actor = _mover()
	_pull(body, &"hook", START + Vector2(0.0, 80.0), 0.5)
	_ask(body, &"teleport", Vector2(0.0, -30.0), 0.0)
	check(not body.mover.is_moving(), "the teleport ended the hook")
	check_equal(body.global_position, START + Vector2(0.0, -30.0), "the actor is where the teleport put it")
	check_equal(_finished.size(), 2, "the replaced hook is answered too")
	check_equal(_finished[0][1], &"hook", "first the hook, where the actor was")
	check_equal(_finished[0][2], START, "which went nowhere")
	_world.run(8)
	check(body.global_position.distance_to(START + Vector2(0.0, -30.0)) < 0.01, "the hook does not pull any more, got %s" % body.global_position)


func test_a_replaced_swap_is_not_answered() -> void:
	var body: Actor = _mover()
	_pull(body, &"swap", START + Vector2(-40.0, 0.0), 0.5)
	_ask(body, &"teleport", Vector2(30.0, 0.0), 0.0)
	check_equal(_finished.size(), 1, "only the teleport answers")
	check_equal(_finished[0][1], &"teleport", "as a teleport")


func test_a_move_due_its_answer_is_answered_when_replaced() -> void:
	# The AI's copy lost this answer when a new move came in the step between.
	var body: Actor = _mover()
	_pull(body, &"hook", START + Vector2(0.0, 20.0), 0.0625)
	_world.run(1)
	_ask(body, &"teleport", Vector2(0.0, -30.0), 0.0)
	check_equal(_finished.size(), 2, "the hook that had arrived is answered, then the teleport")
	check_equal(_finished[0][1], &"hook", "the hook first")


func test_stop_ends_a_move_and_answers_it() -> void:
	var body: Actor = _mover()
	_pull(body, &"hook", START + Vector2(0.0, 80.0), 0.5)
	body.mover.stop()
	check(not body.mover.is_moving(), "the move ended")
	check_equal(_finished.size(), 1, "and was answered")


func test_other_casters_moves_are_ignored() -> void:
	var bodies: Array[Actor] = []
	for seat in 4:
		bodies.append(_mover(seat))
	var imp: Actor = _world.actor(START, [&"mover", &"caster"], Fixture.Scripted.new())
	bodies.append(imp)
	check_equal(imp.caster_number(), imp.id, "the imp casts under its own actor id")
	for mover in bodies.size():
		for other in bodies:
			other.global_position = START
		_ask(bodies[mover], &"teleport", Vector2(40.0, 0.0), 0.0)
		for other in bodies.size():
			var want: Vector2 = START + Vector2(40.0, 0.0) if other == mover else START
			check_equal(bodies[other].global_position, want, "actor %d moves, actor %d stays" % [mover, other])


func test_a_move_without_a_spell_tag_is_nobodys() -> void:
	var body: Actor = _mover()
	_world.bus.caster_move_requested.emit(0, &"teleport", body.muzzle_position() + Vector2(40.0, 0.0), 0.0, 7)
	check_equal(body.global_position, START, "a tag that is no spell's moves nothing")


func test_a_down_actor_does_not_move_and_drops_its_moves() -> void:
	var body: Actor = _mover()
	_pull(body, &"hook", START + Vector2(0.0, 80.0), 0.5)
	_ask(body, &"recoil", Vector2(-40.0, 0.0), 0.5)
	body.set_down(true)
	_ask(body, &"teleport", Vector2(40.0, 0.0), 0.0)
	_world.run(2)
	check(not body.mover.is_moving(), "no pull while down")
	check(_finished.is_empty(), "nothing answered")
	body.set_down(false)
	_world.run(8)
	check_equal(body.global_position, START, "nothing carries over standing up")


func test_chill_slows_and_freeze_stops_walking() -> void:
	var body: Actor = _mover()
	_controller(body).move = Vector2.RIGHT
	_world.run(1)
	check_equal(body.velocity, Vector2(body.mover.speed, 0.0), "free pace")
	_combat.factor = 0.6
	_world.run(1)
	check(is_equal_approx(body.velocity.x, body.mover.speed * 0.6), "a chill slows, got %s" % body.velocity)
	_combat.factor = 0.0
	_world.run(1)
	check_equal(body.velocity, Vector2.ZERO, "a freeze holds the actor")


func test_freeze_stops_a_dash_but_not_a_hook() -> void:
	var body: Actor = _mover()
	_combat.factor = 0.0
	_ask(body, &"dash", Vector2(55.0, 0.0), 0.25)
	_world.run(1)
	check_equal(body.velocity, Vector2.ZERO, "a frozen actor cannot dash")
	var pulled: Actor = _mover(1)
	_pull(pulled, &"hook", START + Vector2(0.0, 40.0), 0.25)
	_world.run(1)
	check(pulled.velocity.y > 0.0, "a hook still pulls a frozen actor")


func test_a_hit_pushes_the_actor() -> void:
	var body: Actor = _mover()
	_combat.push = Vector2(0.0, 120.0)
	_world.run(1)
	check_equal(body.velocity, Vector2(0.0, 120.0), "the push from Combat is added to the movement")


func test_a_stick_tilt_walks_slower_and_never_faster() -> void:
	var body: Actor = _mover()
	_controller(body).move = Vector2(0.5, 0.0)
	_world.run(1)
	check(is_equal_approx(body.velocity.x, body.mover.speed * 0.5), "half a tilt, half the speed")
	_controller(body).move = Vector2(3.0, 0.0)
	_world.run(1)
	check(is_equal_approx(body.velocity.x, body.mover.speed), "never above the speed")
