extends "res://tests/support/suite.gd"
## Tests for the caster kit of gameplay/player (staffs B4): teleport (wall-safe), hook, swap and
## recoil moves asked by `caster_move_requested` and answered by `caster_move_finished`; the
## recoil requests of one step added up (so `mirror · recoil` cancels) while a later dash,
## teleport, hook or swap replaces an earlier one; wizard statuses that slow or freeze walking;
## a hit's push; and siphon's mana refund. Wizards are outside the tree, stepped by hand.
##
## godot --headless --path . --script res://tests/gameplay/player/test_player_caster.gd

const PlayerScript := preload("res://gameplay/player/player.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")

const STEP: float = 0.0625
const START: Vector2 = Vector2(100.0, 100.0)


## Combat with the wizard statuses and the push set by hand.
class FakeCombat:
	extends CombatScript
	var factor: float = 1.0
	var push: Vector2 = Vector2.ZERO

	func wizard_speed_factor(_index: int) -> float:
		return factor

	func consume_wizard_knockback(_index: int, _delta: float) -> Vector2:
		return push


var _bus: EventsScript
var _input: InputManagerScript
var _mgr: ManagerScript
var _combat: FakeCombat
## Every caster_move_finished as [player, mode, position, tag].
var _finished: Array = []


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_input = own(InputManagerScript.new()) as InputManagerScript
	_input.events = _bus
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_combat = own(FakeCombat.new()) as FakeCombat
	_finished.clear()
	_bus.caster_move_finished.connect(func(player: int, mode: StringName, position: Vector2, tag: int) -> void:
		_finished.append([player, mode, position, tag]))


func _wizard(index: int) -> PlayerScript:
	_input.add_virtual_device(index)
	var player := own(PlayerScript.new()) as PlayerScript
	player.index = index
	player.input = _input
	player.events = _bus
	player.projectiles = _mgr
	player.combat = _combat
	player._ready()
	player.global_position = START
	return player


## Ask for a move of `player`, measured like the spells do: `offset` from the staff tip.
func _ask(player: PlayerScript, mode: StringName, offset: Vector2, seconds: float, tag: int = 7) -> void:
	_bus.caster_move_requested.emit(player.index, mode, player.muzzle_position() + offset, seconds, tag)


func _run(player: PlayerScript, count: int) -> void:
	for i in count:
		player.step(STEP)
		player.position += player.velocity * STEP


func test_teleport_jumps_at_once_and_answers() -> void:
	var player: PlayerScript = _wizard(0)
	_ask(player, &"teleport", Vector2(60.0, 0.0), 0.0)
	check_equal(player.global_position, START + Vector2(60.0, 0.0), "the wizard is where the teleport aimed")
	check_equal(_finished, [[0, &"teleport", START + Vector2(60.0, 0.0), 7]], "the landing is reported with the card's tag")


func test_teleport_stops_short_of_a_wall() -> void:
	var player: PlayerScript = _wizard(0)
	_mgr.set_walls([Rect2(150.0, 60.0, 40.0, 80.0)])
	_ask(player, &"teleport", Vector2(100.0, 0.0), 0.0)
	check(player.global_position.x < 150.0 - PlayerScript.TELEPORT_CLEARANCE + 0.5, "the wizard stops before the wall, got %s" % player.global_position)
	check(player.global_position.x > START.x + 20.0, "but still gets most of the way, got %s" % player.global_position)
	check_equal(_finished.size(), 1, "the short landing is still reported")
	check_equal(_finished[0][2], player.global_position, "at the place it landed")


func test_teleport_inside_a_wall_does_not_leave_the_start() -> void:
	var player: PlayerScript = _wizard(0)
	_mgr.set_walls([Rect2(100.0, 90.0, 40.0, 20.0)])
	_ask(player, &"teleport", Vector2(80.0, 0.0), 0.0)
	check(player.global_position.distance_to(START) < 0.01, "a wall right at the wizard allows no jump, got %s" % player.global_position)


func test_hook_pulls_to_the_hit_over_the_time_asked() -> void:
	var player: PlayerScript = _wizard(0)
	_bus.caster_move_requested.emit(0, &"hook", START + Vector2(0.0, 50.0), 0.25, 9)
	check(player.is_dashing(), "a hook is a pull in progress")
	_run(player, 5)
	check(not player.is_dashing(), "the pull ends after the time asked")
	check(player.global_position.distance_to(START + Vector2(0.0, 50.0)) < 0.5, "the wizard is at the hit, got %s" % player.global_position)
	check_equal(_finished.size(), 1, "one answer")
	check_equal(_finished[0][1], &"hook", "it answers as a hook")
	check_equal(_finished[0][3], 9, "with the card's tag")


func test_swap_moves_to_the_target_and_sends_no_answer() -> void:
	var player: PlayerScript = _wizard(0)
	_bus.caster_move_requested.emit(0, &"swap", START + Vector2(-40.0, 0.0), 0.125, 3)
	_run(player, 4)
	check(player.global_position.distance_to(START + Vector2(-40.0, 0.0)) < 0.5, "the wizard takes the target's place, got %s" % player.global_position)
	check(_finished.is_empty(), "a swap sends no caster_move_finished (its blast is the target's)")


func test_recoil_pushes_back_over_the_time_asked() -> void:
	var player: PlayerScript = _wizard(0)
	_ask(player, &"recoil", Vector2(-30.0, 0.0), 0.125)
	_run(player, 4)
	check(player.global_position.distance_to(START + Vector2(-30.0, 0.0)) < 0.5, "pushed back 30 px, got %s" % player.global_position)
	check(_finished.is_empty(), "a recoil sends no answer")


func test_recoils_of_one_step_add_up_and_cancel() -> void:
	var player: PlayerScript = _wizard(0)
	_ask(player, &"recoil", Vector2(-20.0, 0.0), 0.125)
	_ask(player, &"recoil", Vector2(-20.0, 0.0), 0.125)
	_run(player, 4)
	check(player.global_position.distance_to(START + Vector2(-40.0, 0.0)) < 0.5, "two recoils of a step add up, got %s" % player.global_position)
	var mirrored: PlayerScript = _wizard(1)
	_ask(mirrored, &"recoil", Vector2(-20.0, 0.0), 0.125)
	_ask(mirrored, &"recoil", Vector2(20.0, 0.0), 0.125)
	_run(mirrored, 4)
	check(mirrored.global_position.distance_to(START) < 0.01, "a recoil and its mirror cancel, got %s" % mirrored.global_position)


func test_a_later_move_replaces_an_earlier_one() -> void:
	var player: PlayerScript = _wizard(0)
	_bus.caster_move_requested.emit(0, &"hook", START + Vector2(0.0, 80.0), 0.5, 1)
	_ask(player, &"teleport", Vector2(0.0, -30.0), 0.0, 2)
	check(not player.is_dashing(), "the teleport ended the hook")
	check_equal(player.global_position, START + Vector2(0.0, -30.0), "the wizard is where the teleport put it")
	check_equal(_finished.size(), 2, "the replaced hook is answered too")
	check_equal(_finished[0][1], &"hook", "first the hook, where the wizard was")
	check_equal(_finished[0][2], START, "which went nowhere")
	check_equal(_finished[1][1], &"teleport", "then the teleport")
	_run(player, 8)
	check(player.global_position.distance_to(START + Vector2(0.0, -30.0)) < 0.01, "the hook does not pull any more, got %s" % player.global_position)


func test_other_players_moves_are_ignored() -> void:
	var one: PlayerScript = _wizard(0)
	var two: PlayerScript = _wizard(1)
	var tip: Vector2 = two.muzzle_position()
	_bus.caster_move_requested.emit(1, &"teleport", tip + Vector2(40.0, 0.0), 0.0, 5)
	check_equal(one.global_position, START, "player 1 stays")
	check_equal(two.global_position, START + Vector2(40.0, 0.0), "player 2 moves")


func test_a_downed_wizard_does_not_move() -> void:
	var player: PlayerScript = _wizard(0)
	player.take_damage(PlayerScript.MAX_HEALTH)
	_ask(player, &"teleport", Vector2(40.0, 0.0), 0.0)
	_ask(player, &"recoil", Vector2(-40.0, 0.0), 0.1)
	_run(player, 3)
	check_equal(player.global_position, START, "a downed wizard stays")
	check(_finished.is_empty(), "and answers nothing")


func test_chill_slows_and_freeze_stops_walking() -> void:
	var player: PlayerScript = _wizard(0)
	_input.send_virtual(0, &"move_right", 1.0)
	_run(player, 1)
	check_equal(player.velocity, Vector2(PlayerScript.MOVE_SPEED, 0.0), "free pace")
	_combat.factor = 0.6
	_run(player, 1)
	check(is_equal_approx(player.velocity.x, PlayerScript.MOVE_SPEED * 0.6), "a chill slows, got %s" % player.velocity)
	_combat.factor = 0.0
	_run(player, 1)
	check_equal(player.velocity, Vector2.ZERO, "a freeze holds the wizard")


func test_freeze_stops_a_dash_but_not_a_hook() -> void:
	var player: PlayerScript = _wizard(0)
	_combat.factor = 0.0
	_ask(player, &"dash", Vector2(55.0, 0.0), 0.25)
	_run(player, 1)
	check_equal(player.velocity, Vector2.ZERO, "a frozen wizard cannot dash")
	var pulled: PlayerScript = _wizard(1)
	_bus.caster_move_requested.emit(1, &"hook", START + Vector2(0.0, 40.0), 0.25, 4)
	_run(pulled, 1)
	check(pulled.velocity.y > 0.0, "a hook still pulls a frozen wizard")


func test_a_hit_pushes_the_wizard() -> void:
	var player: PlayerScript = _wizard(0)
	_combat.push = Vector2(0.0, 120.0)
	_run(player, 1)
	check_equal(player.velocity, Vector2(0.0, 120.0), "the push from combat is added to the movement")


func test_siphon_refunds_mana_up_to_the_most() -> void:
	var player: PlayerScript = _wizard(0)
	player.mana = 10.0
	_bus.mana_refund_requested.emit(0, 5.0)
	check(is_equal_approx(player.mana, 15.0), "mana comes back, got %f" % player.mana)
	_bus.mana_refund_requested.emit(0, 1000.0)
	check_equal(player.mana, PlayerScript.MAX_MANA, "never above the most")
	player.mana = 10.0
	_bus.mana_refund_requested.emit(1, 5.0)
	_bus.mana_refund_requested.emit(0, -3.0)
	check_equal(player.mana, 10.0, "another player's refund and a negative one change nothing")
