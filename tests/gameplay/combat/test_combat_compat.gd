extends "res://tests/support/suite.gd"
## The deprecated Combat calls (actors G5) are thin wrappers over the actor rows, so code written
## before G5 (player.gd, ai.gd, flow, Feel, the training dummy) keeps working until G6-G8 move it
## onto the actor API: each wrapper reads and writes the same row as its new call. G8/G10 remove
## the wrappers and this test.
##
## godot --headless --path . --script res://tests/gameplay/combat/test_combat_compat.gd

const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const STEP: float = 0.0625

var _bus: EventsScript
var _projectiles: ManagerScript
var _combat: CombatScript
var _actors: ActorSeats.ActorsScript


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_projectiles = own(ManagerScript.new()) as ManagerScript
	_projectiles.events = _bus
	_actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	_projectiles.actors = _actors
	_combat = own(CombatScript.new()) as CombatScript
	_combat.events = _bus
	_combat.projectiles = _projectiles
	_combat.actors = _actors
	_combat._ready()


func _enemy(at: Vector2, health: int = 20) -> Node2D:
	var enemy := own(Node2D.new()) as Node2D
	enemy.position = at
	root.add_child(enemy)
	_combat.register_enemy(enemy, health, 10.0, 2)
	return enemy


func _wizard(index: int, at: Vector2) -> PlayerScript:
	var wizard := own(PlayerScript.new()) as PlayerScript
	wizard.index = index
	wizard.events = _bus
	wizard.actors = _actors
	wizard.actor_id = _actors.actor_of_seat(index)
	wizard.projectiles = _projectiles
	wizard.combat = _combat
	wizard.position = at
	root.add_child(wizard)
	_combat.register_player(index, wizard, 8.0)
	return wizard


func test_the_enemy_calls_are_the_actor_calls() -> void:
	var enemy := _enemy(Vector2.ZERO)
	var id: int = _combat.actor_of(enemy)
	check(id >= 0 and _combat.is_enemy(enemy), "register_enemy registers an actor of the enemies' team")
	check_equal(_combat.get_enemy_count(), 1, "one enemy")
	check_equal(_combat.get_health(enemy), _combat.health_of(id), "get_health is health_of")
	_combat.hit(0, enemy, 1, Vector2.RIGHT, 100.0)
	check_equal(_combat.get_knockback(enemy), _combat.knockback_of(id), "get_knockback is knockback_of")
	check_equal(_combat.consume_knockback_step(enemy, STEP), Vector2(100.0, 0.0), "consume_knockback_step is consume_knockback")
	_combat.apply_status(0, id, CombatScript.CHILL, 2.0, 50.0)
	check_equal(_combat.speed_factor(enemy), _combat.pace_of(id), "speed_factor is pace")
	_combat.unregister_enemy(enemy)
	check(not _combat.is_registered(id), "unregister_enemy is unregister_actor")
	check_equal(_combat.get_enemy_count(), 0, "no enemy left")


func test_the_wizard_calls_by_seat_are_the_actor_calls_by_id() -> void:
	_wizard(0, Vector2(300.0, 0.0))
	var wizard := _wizard(2, Vector2.ZERO)
	var id: int = wizard.actor_id
	check_equal(_combat.actor_of(wizard), id, "register_player keeps the wizard under its actor id")
	check(not _combat.is_enemy(wizard), "a wizard is no enemy")
	check_equal(_combat.wizard_of(2), wizard, "wizard_of finds it by seat")
	check(_combat.apply_wizard_status(1, 2, CombatScript.CHILL, 3.0, 40.0), "apply_wizard_status")
	check_equal(_combat.wizard_status_left(2, CombatScript.CHILL), _combat.status_left(id, CombatScript.CHILL), "wizard_status_left is status_left")
	check_equal(_combat.wizard_speed_factor(2), _combat.pace(wizard), "wizard_speed_factor is pace")
	_combat.give_wizard_shield(2, 2, 1.0, 4)
	check_equal(_combat.wizard_shield(2), _combat.shield(id), "give_wizard_shield and wizard_shield are the barrier")
	_combat.give_shield(id, 0, 0.0)
	_combat.hit(1, wizard, 1)
	_combat.hit(1, wizard, 1)
	_combat.hit(1, wizard, 1000)
	check(wizard.is_downed(), "downed")
	check_equal(_combat.downed_note(2), _combat.downed_note_of(id), "downed_note is downed_note_of")
	check(_combat.consume_wizard_knockback(2, STEP) == _combat.knockback_of(id), "consume_wizard_knockback reads the same push")
	_combat.unregister_player(2)
	check(not _combat.is_registered(id), "unregister_player is unregister_actor")
	check(_combat.wizard_of(2) == null, "and the seat is empty")
	check(_combat.wizard_of(0) != null, "the other seat is kept")
