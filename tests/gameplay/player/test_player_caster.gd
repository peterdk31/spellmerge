extends "res://tests/support/suite.gd"
## Tests for the caster kit on the wizard (staffs B4; the kit's Mover since actors G7 and G5): teleport (wall-safe), pull, swap and recoil moves asked by
## `caster_move_requested` and answered by `caster_move_finished`; every move adding up (so
## `mirror · recoil` cancels; rules R4 F1); wizard statuses from Combat (`apply_status` on its actor id) that slow or
## freeze walking; a hit's push (`consume_knockback`); and siphon's mana refund. Wizards
## are the real scene (content/wizard/base/wizard.tscn) in the tree, stepped by hand. A move is
## the wizard's when its card's tag names the wizard's caster number (its actor id).
## The kit's own Mover is tested on bare actors in tests/gameplay/actor/test_actor_mover.gd.
##
## godot --headless --path . --script res://tests/gameplay/player/test_player_caster.gd

const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")

const START: Vector2 = Vector2(100.0, 100.0)

var _world: Fixture
## Every caster_move_finished as [caster, mode, position, tag].
var _finished: Array = []


func before_each() -> void:
	_world = Fixture.new(root, true)
	_world.projectiles.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_finished.clear()
	_world.bus.caster_move_finished.connect(func(caster: int, mode: StringName, position: Vector2, tag: int) -> void:
		_finished.append([caster, mode, position, tag]))


func after_each() -> void:
	_world.free_all()


func _wizard(seat: int) -> Actor:
	return _world.wizard(seat, START)


## The tag a card of `wizard`'s staff `staff` carries.
func _tag(wizard: Actor, staff: int = 0) -> int:
	return SpellTag.make(wizard.id, staff, 0, 0)


## Ask for a move of `wizard` by `move` (the way and the distance), as the spells do.
func _ask(wizard: Actor, mode: StringName, move: Vector2, seconds: float, staff: int = 0) -> void:
	_world.bus.caster_move_requested.emit(wizard.id, mode, move, seconds, _tag(wizard, staff))


## Ask for a pull of `wizard` to the world point `to`.
func _pull(wizard: Actor, mode: StringName, to: Vector2, seconds: float, staff: int = 0) -> void:
	_ask(wizard, mode, to - wizard.global_position, seconds, staff)


func _run(count: int) -> void:
	_world.run(count)


## Chill `wizard` three times: a freeze.
func _freeze(wizard: Actor) -> void:
	for n in CombatScript.CHILL_STACKS_TO_FREEZE:
		_world.combat.apply_status(EventsScript.NO_PLAYER, wizard.id, CombatScript.CHILL, 5.0, 40.0)


func test_teleport_jumps_at_once_and_answers() -> void:
	var player: Actor = _wizard(0)
	_ask(player, &"teleport", Vector2(60.0, 0.0), 0.0)
	check_equal(player.global_position, START + Vector2(60.0, 0.0), "the wizard is where the teleport aimed")
	check_equal(_finished, [[player.id, &"teleport", START + Vector2(60.0, 0.0), _tag(player)]], "the landing is reported with the card's tag")


func test_teleport_stops_short_of_a_wall() -> void:
	var player: Actor = _wizard(0)
	_world.projectiles.set_walls([Rect2(150.0, 60.0, 40.0, 80.0)])
	_ask(player, &"teleport", Vector2(100.0, 0.0), 0.0)
	check(player.global_position.x < 150.0 - Mover.TELEPORT_CLEARANCE + 0.5, "the wizard stops before the wall, got %s" % player.global_position)
	check(player.global_position.x > START.x + 20.0, "but still gets most of the way, got %s" % player.global_position)
	check_equal(_finished.size(), 1, "the short landing is still reported")
	check_equal(_finished[0][2], player.global_position, "at the place it landed")


func test_teleport_inside_a_wall_does_not_leave_the_start() -> void:
	var player: Actor = _wizard(0)
	_world.projectiles.set_walls([Rect2(100.0, 90.0, 40.0, 20.0)])
	_ask(player, &"teleport", Vector2(80.0, 0.0), 0.0)
	check(player.global_position.distance_to(START) < 0.01, "a wall right at the wizard allows no jump, got %s" % player.global_position)


func test_a_pull_moves_to_the_hit_over_the_time_asked() -> void:
	var player: Actor = _wizard(0)
	_pull(player, &"pull", START + Vector2(0.0, 50.0), 0.25, 2)
	check(player.mover.is_moving(), "a pull in progress")
	_run(5)
	check(not player.mover.is_moving(), "the pull ends after the time asked")
	check(player.global_position.distance_to(START + Vector2(0.0, 50.0)) < 0.5, "the wizard is at the hit, got %s" % player.global_position)
	check_equal(_finished.size(), 1, "one answer")
	check_equal(_finished[0][1], &"pull", "it answers as a pull")
	check_equal(_finished[0][3], _tag(player, 2), "with the card's tag")


func test_swap_moves_to_the_target_and_is_answered() -> void:
	var player: Actor = _wizard(0)
	_pull(player, &"swap", START + Vector2(-40.0, 0.0), 0.125)
	_run(4)
	check(player.global_position.distance_to(START + Vector2(-40.0, 0.0)) < 0.5, "the wizard takes the target's place, got %s" % player.global_position)
	check(_finished.size() == 1 and _finished[0][1] == &"swap", "every move is answered: %s" % [_finished])


func test_recoil_pushes_back_over_the_time_asked() -> void:
	var player: Actor = _wizard(0)
	_ask(player, &"recoil", Vector2(-30.0, 0.0), 0.125)
	_run(4)
	check(player.global_position.distance_to(START + Vector2(-30.0, 0.0)) < 0.5, "pushed back 30 px, got %s" % player.global_position)
	check(_finished.size() == 1 and _finished[0][1] == &"recoil", "a recoil is a move like the others: %s" % [_finished])


func test_recoils_of_one_step_add_up_and_cancel() -> void:
	var player: Actor = _wizard(0)
	_ask(player, &"recoil", Vector2(-20.0, 0.0), 0.125)
	_ask(player, &"recoil", Vector2(-20.0, 0.0), 0.125)
	var mirrored: Actor = _wizard(1)
	_ask(mirrored, &"recoil", Vector2(-20.0, 0.0), 0.125)
	_ask(mirrored, &"recoil", Vector2(20.0, 0.0), 0.125)
	_run(4)
	check(player.global_position.distance_to(START + Vector2(-40.0, 0.0)) < 0.5, "two recoils of a step add up, got %s" % player.global_position)
	check(mirrored.global_position.distance_to(START) < 0.01, "a recoil and its mirror cancel, got %s" % mirrored.global_position)


func test_recoils_of_different_times_move_the_sum_of_their_distances() -> void:
	# Regression: a running short recoil kept its full speed for a later, longer one.
	var player: Actor = _wizard(0)
	_ask(player, &"recoil", Vector2(-20.0, 0.0), 0.125)
	_run(1)
	_ask(player, &"recoil", Vector2(-20.0, 0.0), 0.5)
	_run(12)
	check(player.global_position.distance_to(START + Vector2(-40.0, 0.0)) < 0.01, "two recoils move 20 + 20 px, got %s" % player.global_position)


func test_recoil_works_without_input() -> void:
	var player: Actor = _wizard(0)
	Fixture.controller(player).input = null
	_ask(player, &"recoil", Vector2(-30.0, 0.0), 0.125)
	_run(4)
	check(player.global_position.distance_to(START + Vector2(-30.0, 0.0)) < 0.01, "pushed without an input manager, got %s" % player.global_position)


func test_a_dash_walks_its_whole_distance_and_is_answered_one_step_later() -> void:
	# Regression: the move's last step was cut off and answered a step early.
	var player: Actor = _wizard(0)
	_ask(player, &"dash", Vector2(55.0, 0.0), 0.25)
	for n in 4:
		_run(1)
		check(_finished.is_empty(), "no answer while it walks (step %d)" % n)
	check(player.global_position.distance_to(START + Vector2(55.0, 0.0)) < 0.01, "walked 55 px, got %s" % player.global_position)
	_run(1)
	check_equal(_finished.size(), 1, "answered one step later")
	check_equal(_finished[0][1], &"dash", "as a dash")


func test_a_homing_dash_turns_toward_an_enemy_and_goes_its_whole_distance() -> void:
	var enemy := own(Node2D.new()) as Node2D
	root.add_child(enemy)
	enemy.global_position = START + Vector2(60.0, 40.0)
	_world.projectiles.add_target(enemy, 8.0, ManagerScript.LAYER_ENEMY)
	var plain: Actor = _wizard(0)
	plain.aim = Vector2.RIGHT
	var homing: Actor = _wizard(1)
	homing.aim = Vector2.RIGHT
	var dash_homing: Homing = _world.spells.dashes().move_homing(homing.id)
	dash_homing.turn = 3.0
	dash_homing.reach = 160.0
	_ask(plain, &"dash", Vector2(55.0, 0.0), 0.25)
	_ask(homing, &"dash", Vector2(55.0, 0.0), 0.25)
	_run(5)
	check(is_equal_approx(plain.global_position.y, START.y), "a plain dash goes straight: %s" % plain.global_position)
	var moved: Vector2 = homing.global_position - START
	check(moved.y > 3.0, "a homing dash turns toward the enemy: %s" % moved)
	check(homing.global_position.distance_to(enemy.global_position) < plain.global_position.distance_to(enemy.global_position), "and ends nearer it")
	check(absf(moved.length() - 55.0) < 1.0 or moved.length() < 55.0, "no farther than its distance: %s" % moved.length())


func test_teleport_along_a_wall_keeps_the_body_out_of_it() -> void:
	var player: Actor = _wizard(0)
	_world.projectiles.set_walls([Rect2(60.0, 112.0, 200.0, 20.0)])
	_ask(player, &"teleport", Vector2(100.0, 0.0), 0.0)
	check(not _world.projectiles.circle_blocked(player.global_position, player.mover.body_radius), "no part of the body is in the wall, got %s" % player.global_position)
	check(player.global_position.x > START.x + 50.0, "and it still jumped along the wall, got %s" % player.global_position)


func test_teleport_into_a_corner_keeps_the_body_out_of_the_walls() -> void:
	var player: Actor = _wizard(0)
	_world.projectiles.set_walls([Rect2(140.0, 60.0, 40.0, 40.0), Rect2(140.0, 100.0, 8.0, 80.0)])
	_ask(player, &"teleport", Vector2(45.0, 0.0), 0.0)
	check(not _world.projectiles.circle_blocked(player.global_position, player.mover.body_radius), "clear of the corner, got %s" % player.global_position)


func test_teleport_does_not_leave_the_room() -> void:
	var player: Actor = _wizard(0)
	_ask(player, &"teleport", Vector2(900.0, 0.0), 0.0)
	check(not _world.projectiles.circle_blocked(player.global_position, player.mover.body_radius), "the body stays in the room, got %s" % player.global_position)
	check(player.global_position.x > START.x, "but it still moves, got %s" % player.global_position)


func test_an_overlay_ends_a_pull_and_answers_it() -> void:
	var player: Actor = _wizard(0)
	_pull(player, &"pull", START + Vector2(0.0, 80.0), 0.5)
	_world.input.set_captured(0, true)
	_run(1)
	check(not player.mover.is_moving(), "the move ended")
	check_equal(_finished.size(), 1, "and was answered")
	check_equal(_finished[0][1], &"pull", "as a pull")


func test_downing_clears_moves_and_recoil() -> void:
	var player: Actor = _wizard(0)
	_pull(player, &"pull", START + Vector2(0.0, 80.0), 0.5)
	_ask(player, &"recoil", Vector2(-40.0, 0.0), 0.5)
	_world.hurt(player, player.health.max_health)
	_run(2)
	check(not player.mover.is_moving(), "no pull while downed")
	Fixture.downed(player).revive(1)
	_run(8)
	check_equal(player.global_position, START, "nothing carries over a revive")


func test_other_players_moves_are_ignored() -> void:
	var wizards: Array[Actor] = []
	for at in 4:
		wizards.append(_wizard(at))
	for mover in 4:
		for other in 4:
			wizards[other].global_position = START
		_ask(wizards[mover], &"teleport", Vector2(40.0, 0.0), 0.0)
		for other in 4:
			var want: Vector2 = START + Vector2(40.0, 0.0) if other == mover else START
			check_equal(wizards[other].global_position, want, "player %d moves, player %d stays: %d" % [mover, mover, other])


func test_a_move_is_matched_by_the_tag_not_the_event_caster() -> void:
	# Actors G7: the old wizard checked the event's caster; the Mover checks the card's tag.
	var player: Actor = _wizard(0)
	var other: Actor = _wizard(1)
	_world.bus.caster_move_requested.emit(player.id, &"teleport", Vector2(40.0, 0.0), 0.0, _tag(other))
	check_equal(player.global_position, START, "a card of another wizard does not move this one")
	check_equal(other.global_position, START + Vector2(40.0, 0.0), "it moves the wizard its tag names")


func test_a_downed_wizard_does_not_move() -> void:
	var player: Actor = _wizard(0)
	_world.hurt(player, player.health.max_health)
	_ask(player, &"teleport", Vector2(40.0, 0.0), 0.0)
	_ask(player, &"recoil", Vector2(-40.0, 0.0), 0.1)
	_run(3)
	check_equal(player.global_position, START, "a downed wizard stays")
	check(_finished.is_empty(), "and answers nothing")


func test_chill_slows_and_freeze_stops_walking() -> void:
	var player: Actor = _wizard(0)
	var other: Actor = _wizard(1)
	_world.hold(0, &"move_right")
	_world.hold(1, &"move_right")
	_run(1)
	check_equal(player.velocity, Vector2(player.mover.speed, 0.0), "free pace")
	check(_world.combat.apply_status(EventsScript.NO_PLAYER, player.id, CombatScript.CHILL, 5.0, 40.0), "the chill takes on seat 0's wizard")
	_run(1)
	check(is_equal_approx(player.velocity.x, player.mover.speed * 0.6), "a chill slows, got %s" % player.velocity)
	check_equal(other.velocity, Vector2(other.mover.speed, 0.0), "another seat's chill does not slow this wizard")
	_freeze(player)
	_run(1)
	check_equal(player.velocity, Vector2.ZERO, "a freeze holds the wizard")


func test_freeze_stops_a_dash_but_not_a_pull() -> void:
	var player: Actor = _wizard(0)
	player.aim = Vector2.RIGHT
	_freeze(player)
	_ask(player, &"dash", Vector2(55.0, 0.0), 0.25)
	_run(1)
	check_equal(player.velocity, Vector2.ZERO, "a frozen wizard cannot dash")
	var pulled: Actor = _wizard(1)
	_freeze(pulled)
	_pull(pulled, &"pull", START + Vector2(0.0, 40.0), 0.25)
	_run(1)
	check(pulled.velocity.y > 0.0, "a pull still pulls a frozen wizard")


func test_a_hit_pushes_the_wizard() -> void:
	var player: Actor = _wizard(0)
	check(_world.combat.hit(EventsScript.NO_PLAYER, player, 1, Vector2.DOWN, 120.0), "the hit lands")
	_run(1)
	check_equal(player.velocity, Vector2(0.0, 120.0), "the push from combat is added to the movement")


func test_siphon_refunds_mana_up_to_the_most() -> void:
	var player: Actor = _wizard(0)
	var caster: Caster = player.caster
	caster.mana = 10.0
	_world.bus.mana_refund_requested.emit(player.id, 5.0)
	check(is_equal_approx(caster.mana, 15.0), "mana comes back, got %f" % caster.mana)
	_world.bus.mana_refund_requested.emit(player.id, 1000.0)
	check_equal(caster.mana, caster.max_mana, "never above the most")
	caster.mana = 10.0
	_world.bus.mana_refund_requested.emit(player.id + 1, 5.0)
	_world.bus.mana_refund_requested.emit(player.id, -3.0)
	check_equal(caster.mana, 10.0, "another caster's refund and a negative one change nothing")
