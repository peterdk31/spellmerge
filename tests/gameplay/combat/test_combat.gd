extends SceneTree
## Tests for gameplay/combat: damage, knockback, death and contact hit boxes,
## with several players at once. Hits arrive through the event bus like the
## real ones (`projectile_hit`); time moves by fixed binary-fraction deltas.
##
## godot --headless --path . --script res://tests/gameplay/combat/test_combat.gd

const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

const STEP: float = 0.0625

var _failures: Array[String] = []
var _bus: Node
var _combat: Node
var _projectiles: Node
var _enemies: Array = []
var _players: Array[PlayerScript] = []
## Each damage_dealt as [player, target, amount].
var _damage: Array = []
## Each enemy_died as [player, enemy].
var _deaths: Array = []


func _initialize() -> void:
	_test_damage_reduces_health_and_sends_event()
	_test_bad_hits_do_nothing()
	_test_unknown_target_is_ignored()
	_test_death_sends_event_with_killer()
	_test_dead_enemy_cannot_die_twice()
	_test_knockback_pushes_away_and_fades()
	_test_knockback_zero_strength_does_not_move()
	_test_projectile_hit_uses_profile()
	_test_projectile_hit_without_profile_is_ignored()
	_test_projectile_target_added_and_removed()
	_test_player_takes_damage_through_event()
	_test_dodging_and_downed_player_get_no_event()
	_test_contact_damage_and_cooldown()
	_test_contact_hurts_only_the_one_touched()
	_test_four_players_kill_credit()
	_test_freed_enemy_is_dropped()
	_teardown()
	if _failures.is_empty():
		print("TEST OK: gameplay/combat (damage, knockback, death)")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _setup(player_count: int = 0, with_projectiles: bool = false) -> void:
	_teardown()
	_bus = EventsScript.new()
	_combat = CombatScript.new()
	_combat.events = _bus
	if with_projectiles:
		_projectiles = ProjectileManagerScript.new()
		_combat.projectiles = _projectiles
	_combat._ready()
	_bus.damage_dealt.connect(func(p: int, target: Node, amount: int, _at: Vector2) -> void:
		_damage.append([p, target, amount]))
	_bus.enemy_died.connect(func(p: int, enemy: Node, _at: Vector2) -> void:
		_deaths.append([p, enemy]))
	for index in player_count:
		var wizard := PlayerScript.new()
		wizard.index = index
		wizard.events = _bus
		wizard._ready()
		wizard.position = Vector2(1000.0 * index, 1000.0)
		_players.append(wizard)
		_combat.register_player(index, wizard, 8.0)


func _teardown() -> void:
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.free()
	_enemies.clear()
	for wizard in _players:
		wizard.free()
	_players.clear()
	for node: Node in [_combat, _projectiles, _bus]:
		if node != null:
			node.free()
	_combat = null
	_projectiles = null
	_bus = null
	_damage.clear()
	_deaths.clear()


func _enemy(health: int, at: Vector2 = Vector2.ZERO, contact: int = 0) -> Node2D:
	var enemy := Node2D.new()
	enemy.position = at
	_enemies.append(enemy)
	_combat.register_enemy(enemy, health, 10.0, contact)
	return enemy


func _run(count: int) -> void:
	for i in count:
		_combat.step(STEP)


# --- Tests ------------------------------------------------------------------

func _test_damage_reduces_health_and_sends_event() -> void:
	_setup()
	var enemy := _enemy(10)
	_check(_combat.hit(2, enemy, 3), "a hit for 3 counts")
	_check(_combat.get_health(enemy) == 7, "health 10 minus 3 is 7")
	_check(_damage == [[2, enemy, 3]], "damage_dealt names player 2, the enemy and 3")
	_check(_deaths.is_empty(), "no death yet")


func _test_bad_hits_do_nothing() -> void:
	_setup()
	var enemy := _enemy(5)
	_check(not _combat.hit(0, enemy, 0), "0 damage does not count")
	_check(not _combat.hit(0, enemy, -4), "negative damage does not count")
	_check(not _combat.hit(0, null, 3), "a null target does not count")
	_check(_combat.get_health(enemy) == 5 and _damage.is_empty(), "nothing changed, nothing sent")


func _test_unknown_target_is_ignored() -> void:
	_setup()
	var stranger := Node2D.new()
	_enemies.append(stranger)
	_check(not _combat.hit(0, stranger, 3), "a node that is not registered cannot be hit")
	_check(_damage.is_empty() and not _combat.is_enemy(stranger), "no event, still not an enemy")


func _test_death_sends_event_with_killer() -> void:
	_setup()
	var enemy := _enemy(4, Vector2(5.0, 6.0))
	_combat.hit(0, enemy, 2)
	_combat.hit(3, enemy, 9)  # overkill: health stops at 0
	_check(_deaths == [[3, enemy]], "enemy_died names the player with the last hit")
	_check(_combat.get_health(enemy) == -1 and not _combat.is_enemy(enemy), "a dead enemy is no longer registered")
	_check(_damage.size() == 2 and _damage[1][2] == 9, "both hits sent damage_dealt")
	_check(_combat.get_enemy_count() == 0, "no enemies left")


func _test_dead_enemy_cannot_die_twice() -> void:
	_setup()
	var enemy := _enemy(1)
	_combat.hit(1, enemy, 1)
	_check(not _combat.hit(1, enemy, 1), "a hit on a dead enemy does not count")
	_check(_deaths.size() == 1 and _damage.size() == 1, "one death, one damage event")


func _test_knockback_pushes_away_and_fades() -> void:
	_setup()
	var enemy := _enemy(100, Vector2(10.0, 0.0))
	_combat.hit(0, enemy, 1, Vector2.RIGHT, 160.0)
	_check(_combat.get_knockback(enemy) == Vector2(160.0, 0.0), "knockback velocity is direction times strength")
	_run(1)
	_check(enemy.position.x > 10.0 and is_equal_approx(enemy.position.y, 0.0), "the enemy moved along the hit direction")
	_run(8)
	_check(_combat.get_knockback(enemy) == Vector2.ZERO, "knockback fades to zero")
	var stopped_at: float = enemy.position.x
	_run(4)
	_check(is_equal_approx(enemy.position.x, stopped_at), "the enemy stands still once knockback ends")
	_check(stopped_at < 10.0 + 160.0, "knockback travels a short distance only")


func _test_knockback_zero_strength_does_not_move() -> void:
	_setup()
	var enemy := _enemy(10, Vector2(3.0, 3.0))
	_combat.hit(0, enemy, 1, Vector2.RIGHT, 0.0)
	_run(2)
	_check(enemy.position == Vector2(3.0, 3.0), "strength 0 pushes nothing")


func _test_projectile_hit_uses_profile() -> void:
	_setup()
	var enemy := _enemy(20, Vector2(10.0, 0.0))
	_combat.set_hit_profile(7, 5, 100.0)
	_bus.projectile_hit.emit(1, enemy, Vector2(0.0, 0.0), 7)
	_check(_damage == [[1, enemy, 5]], "projectile_hit with tag 7 deals the profile's damage for the shooter")
	_check(_combat.get_health(enemy) == 15, "health 20 minus 5")
	_check(_combat.get_knockback(enemy).x > 0.0, "pushed away from the hit position")
	_combat.clear_hit_profile(7)
	_bus.projectile_hit.emit(1, enemy, Vector2.ZERO, 7)
	_check(_combat.get_health(enemy) == 15, "a cleared profile does nothing")


func _test_projectile_hit_without_profile_is_ignored() -> void:
	_setup()
	var enemy := _enemy(5)
	_bus.projectile_hit.emit(0, enemy, Vector2.ZERO, 0)
	_bus.projectile_hit.emit(0, enemy, Vector2.ZERO, 99)
	_check(_damage.is_empty() and _combat.get_health(enemy) == 5, "tags without a profile do no damage")


func _test_projectile_target_added_and_removed() -> void:
	_setup(0, true)
	var enemy := _enemy(1)
	_check(_projectiles.get_target_count() == 1, "a registered enemy is a projectile target")
	_combat.hit(0, enemy, 5)
	_check(_projectiles.get_target_count() == 0, "a dead enemy is no longer a target")


func _test_player_takes_damage_through_event() -> void:
	_setup(2)
	_check(_combat.hit(EventsScript.NO_PLAYER, _players[1], 3), "a hit on a wizard counts")
	_check(_players[1].health == PlayerScript.MAX_HEALTH - 3, "the wizard lost 3 health through damage_dealt")
	_check(_players[0].health == PlayerScript.MAX_HEALTH, "the other wizard is untouched")
	var other := Node2D.new()
	_enemies.append(other)
	_check(not _combat.hit(0, other, 3), "an unregistered node is not a wizard")


func _test_dodging_and_downed_player_get_no_event() -> void:
	_setup(2)
	_players[0]._invulnerable_left = 0.25
	_check(not _combat.hit(EventsScript.NO_PLAYER, _players[0], 3), "a dodging wizard is not hit")
	_check(_damage.is_empty() and _players[0].health == PlayerScript.MAX_HEALTH, "no event, no damage")
	_players[1].take_damage(1000)
	_check(not _combat.hit(EventsScript.NO_PLAYER, _players[1], 3), "a downed wizard is not hit")
	_check(_damage.is_empty(), "still no event")


func _test_contact_damage_and_cooldown() -> void:
	_setup(1)
	var enemy := _enemy(10, _players[0].position + Vector2(5.0, 0.0), 2)
	_run(1)
	_check(_players[0].health == PlayerScript.MAX_HEALTH - 2, "touching the enemy costs its contact damage")
	_check(_damage.size() == 1 and _damage[0][0] == EventsScript.NO_PLAYER, "the source is NO_PLAYER")
	_run(8)
	_check(_players[0].health == PlayerScript.MAX_HEALTH - 2, "no second hit inside the cooldown")
	_run(int(CombatScript.CONTACT_COOLDOWN / STEP))
	_check(_players[0].health == PlayerScript.MAX_HEALTH - 4, "a second hit after the cooldown")
	enemy.position += Vector2(500.0, 0.0)
	var before: int = _players[0].health
	_run(int(CombatScript.CONTACT_COOLDOWN / STEP) + 1)
	_check(_players[0].health == before, "an enemy out of reach does nothing")


func _test_contact_hurts_only_the_one_touched() -> void:
	_setup(4)
	_enemy(10, _players[2].position, 1)
	_run(1)
	for index in 4:
		var expected: int = PlayerScript.MAX_HEALTH - (1 if index == 2 else 0)
		_check(_players[index].health == expected, "player %d health is %d" % [index, expected])


func _test_four_players_kill_credit() -> void:
	_setup(4)
	_combat.set_hit_profile(1, 1, 0.0)
	var enemy := _enemy(4)
	for index in 4:
		_bus.projectile_hit.emit(index, enemy, Vector2.ZERO, 1)
	_check(_damage.size() == 4, "four hits, four damage events")
	_check(_deaths == [[3, enemy]], "player 3 landed the last hit and gets the kill")
	var second := _enemy(1)
	_bus.projectile_hit.emit(0, second, Vector2.ZERO, 1)
	_check(_deaths.size() == 2 and _deaths[1] == [0, second], "the next kill goes to player 0")


func _test_freed_enemy_is_dropped() -> void:
	_setup()
	var enemy := _enemy(5)
	var keep := _enemy(5)
	enemy.free()
	_run(1)
	_check(_combat.get_enemy_count() == 1 and _combat.is_enemy(keep), "a freed enemy is dropped, the other stays")
	_check(_combat.hit(0, keep, 1), "the remaining enemy can still be hit")
