extends SceneTree
## Tests for gameplay/combat: damage, knockback, death and contact hit boxes,
## with several players at once. Hits arrive through the event bus like the
## real ones (`projectile_hit`); time moves by fixed binary-fraction deltas.
##
## godot --headless --path . --script res://tests/gameplay/combat/test_combat.gd

const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const WizardScene := preload("res://content/wizard/base/wizard.tscn")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")

const STEP: float = 0.0625

var _failures: Array[String] = []
var _bus: Node
var _combat: Node
var _projectiles: Node
## Where Combat reads what a shot does (`hit_profile`); `_profile` fills it.
var _spells: Node
var _enemies: Array = []
var _players: Array[Actor] = []
## The wizards' actor table (not the autoload).
var _actors: ActorsScript
## Each damage_dealt as [player, target, amount].
var _damage: Array = []
## Each enemy_died as [player, enemy].
var _deaths: Array = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
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
	_test_freed_enemy_target_is_pruned()
	_test_death_frees_enemy_in_tree()
	_test_reregister_resets_numbers_and_target()
	_test_listener_may_change_registrations()
	_test_wizard_is_a_projectile_target_for_enemy_shots()
	_test_downed_wizard_is_not_a_projectile_target()
	_test_hit_circles_follow_the_body_offset()
	_test_contact_uses_the_body_offset()
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
	_spells = SpellsScript.new()
	_combat.spells = _spells
	if with_projectiles:
		_projectiles = ProjectileManagerScript.new()
		_combat.projectiles = _projectiles
	_combat._ready()
	_bus.damage_dealt.connect(func(p: int, target: Node, amount: int, _at: Vector2) -> void:
		_damage.append([p, target, amount]))
	_bus.enemy_died.connect(func(p: int, enemy: Node, _at: Vector2, _shot: int) -> void:
		_deaths.append([p, enemy]))
	_actors = ActorsScript.new()
	# One actor table for the wizards, Combat and the projectile manager (teams aim contact).
	_combat.actors = _actors
	if _projectiles != null:
		_projectiles.actors = _actors
	for index in player_count:
		# A wizard actor of the real scene (actors G7), in the tree: its hurtbox registers it in
		# Combat's seat slot (8 px, at the body).
		var wizard := WizardScene.instantiate() as Actor
		PlayerController.seat_wizard(wizard, index, null, [[], [], [], []])
		wizard.events = _bus
		wizard.combat = _combat
		wizard.spells = _spells
		wizard.projectiles = _projectiles
		wizard.actors = _actors
		wizard.position = Vector2(1000.0 * index, 1000.0)
		root.add_child(wizard)
		wizard.set_physics_process(false)
		_players.append(wizard)


func _teardown() -> void:
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.free()
	_enemies.clear()
	for wizard in _players:
		wizard.free()
	_players.clear()
	for node: Node in [_combat, _spells, _projectiles, _actors, _bus]:
		if node != null:
			node.free()
	_combat = null
	_spells = null
	_projectiles = null
	_actors = null
	_bus = null
	_damage.clear()
	_deaths.clear()


## Say what a shot with `tag` does, as a spell's hit profile in Spells (staffs F9b: Combat's own
## table is gone).
func _profile(tag: int, damage: int, knockback: float = 0.0) -> void:
	var hit := HitProfile.new()
	hit.damage = damage
	hit.knockback = knockback
	var spell := CompiledSpell.new()
	spell.hit = hit
	_spells.get("_profiles")[tag] = spell


func _enemy(health: int, at: Vector2 = Vector2.ZERO, contact: int = 0) -> Node2D:
	var enemy := Node2D.new()
	enemy.position = at
	_enemies.append(enemy)
	_combat.register_actor(enemy, health, 10.0, contact)
	return enemy


func _run(count: int) -> void:
	for i in count:
		_combat.step(STEP)


# --- Tests ------------------------------------------------------------------

func _test_damage_reduces_health_and_sends_event() -> void:
	_setup()
	var enemy := _enemy(10)
	_check(_combat.hit(2, enemy, 3), "a hit for 3 counts")
	_check(_combat.health_of(enemy) == 7, "health 10 minus 3 is 7")
	_check(_damage == [[2, enemy, 3]], "damage_dealt names player 2, the enemy and 3")
	_check(_deaths.is_empty(), "no death yet")


func _test_bad_hits_do_nothing() -> void:
	_setup()
	var enemy := _enemy(5)
	_check(not _combat.hit(0, enemy, 0), "0 damage does not count")
	_check(not _combat.hit(0, enemy, -4), "negative damage does not count")
	_check(not _combat.hit(0, null, 3), "a null target does not count")
	_check(_combat.health_of(enemy) == 5 and _damage.is_empty(), "nothing changed, nothing sent")


func _test_unknown_target_is_ignored() -> void:
	_setup()
	var stranger := Node2D.new()
	_enemies.append(stranger)
	_check(not _combat.hit(0, stranger, 3), "a node that is not registered cannot be hit")
	_check(_damage.is_empty() and not _combat.is_registered(stranger), "no event, still not an enemy")


func _test_death_sends_event_with_killer() -> void:
	_setup()
	var enemy := _enemy(4, Vector2(5.0, 6.0))
	_combat.hit(0, enemy, 2)
	_combat.hit(3, enemy, 9)  # overkill: health stops at 0
	_check(_deaths == [[3, enemy]], "enemy_died names the player with the last hit")
	_check(_combat.health_of(enemy) == -1 and not _combat.is_registered(enemy), "a dead enemy is no longer registered")
	_check(_damage.size() == 2 and _damage[1][2] == 9, "both hits sent damage_dealt")
	_check(_combat.actor_count() == 0, "no enemies left")


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
	_check(_combat.knockback_of(enemy) == Vector2(160.0, 0.0), "knockback velocity is direction times strength")
	_run(4)
	_check(enemy.position == Vector2(10.0, 0.0), "Combat never moves the enemy itself")
	_check(_combat.knockback_of(enemy) == Vector2(160.0, 0.0), "step() does not fade knockback")
	var first: Vector2 = _combat.consume_knockback(enemy, STEP)
	_check(first == Vector2(160.0, 0.0), "the mover gets the full velocity on the first step")
	_check(_combat.knockback_of(enemy).x < 160.0, "the stored knockback fades after a step")
	var travelled: float = first.x * STEP
	for i in 8:
		travelled += _combat.consume_knockback(enemy, STEP).x * STEP
	_check(_combat.knockback_of(enemy) == Vector2.ZERO, "knockback fades to zero")
	_check(_combat.consume_knockback(enemy, STEP) == Vector2.ZERO, "nothing left to consume")
	_check(travelled > 0.0 and travelled < 160.0, "knockback travels a short distance only")
	var stranger := Node2D.new()
	_enemies.append(stranger)
	_check(_combat.consume_knockback(stranger, STEP) == Vector2.ZERO, "an unregistered node has no knockback")


func _test_knockback_zero_strength_does_not_move() -> void:
	_setup()
	var enemy := _enemy(10, Vector2(3.0, 3.0))
	_combat.hit(0, enemy, 1, Vector2.RIGHT, 0.0)
	_check(_combat.consume_knockback(enemy, STEP) == Vector2.ZERO, "strength 0 pushes nothing")


func _test_projectile_hit_uses_profile() -> void:
	_setup()
	var enemy := _enemy(20, Vector2(10.0, 0.0))
	_profile(7, 5, 100.0)
	_bus.projectile_hit.emit(1, enemy, Vector2(0.0, 0.0), 7, -1)
	_check(_damage == [[1, enemy, 5]], "projectile_hit with tag 7 deals the profile's damage for the shooter")
	_check(_combat.health_of(enemy) == 15, "health 20 minus 5")
	_check(_combat.knockback_of(enemy).x > 0.0, "pushed away from the hit position")


func _test_projectile_hit_without_profile_is_ignored() -> void:
	_setup()
	var enemy := _enemy(5)
	_bus.projectile_hit.emit(0, enemy, Vector2.ZERO, 0, -1)
	_bus.projectile_hit.emit(0, enemy, Vector2.ZERO, 99, -1)
	_check(_damage.is_empty() and _combat.health_of(enemy) == 5, "tags without a profile do no damage")


func _test_projectile_target_added_and_removed() -> void:
	_setup(0, true)
	var enemy := _enemy(1)
	_check(_projectiles.get_target_count() == 1, "a registered enemy is a projectile target")
	_combat.hit(0, enemy, 5)
	_check(_projectiles.get_target_count() == 0, "a dead enemy is no longer a target")


func _test_player_takes_damage_through_event() -> void:
	_setup(2)
	_check(_combat.hit(EventsScript.NO_PLAYER, _players[1], 3), "a hit on a wizard counts")
	_check(_players[1].health.health == _players[1].health.max_health - 3, "the wizard lost 3 health through damage_dealt")
	_check(_players[0].health.health == _players[0].health.max_health, "the other wizard is untouched")
	var other := Node2D.new()
	_enemies.append(other)
	_check(not _combat.hit(0, other, 3), "an unregistered node is not a wizard")


func _test_dodging_and_downed_player_get_no_event() -> void:
	_setup(2)
	_players[0].health.protect(0.25)
	_check(not _combat.hit(EventsScript.NO_PLAYER, _players[0], 3), "a dodging wizard is not hit")
	_check(_damage.is_empty() and _players[0].health.health == _players[0].health.max_health, "no event, no damage")
	_players[1].health.take(1000)
	_check(not _combat.hit(EventsScript.NO_PLAYER, _players[1], 3), "a downed wizard is not hit")
	_check(_damage.is_empty(), "still no event")


func _test_contact_damage_and_cooldown() -> void:
	_setup(1)
	var enemy := _enemy(10, _players[0].position + Vector2(5.0, 0.0), 2)
	_run(1)
	_check(_players[0].health.health == _players[0].health.max_health - 2, "touching the enemy costs its contact damage")
	_check(_damage.size() == 1 and _damage[0][0] == _combat.actor_of(enemy), "the source is the actor that touched (actors G5)")
	_run(8)
	_check(_players[0].health.health == _players[0].health.max_health - 2, "no second hit inside the cooldown")
	_run(int(CombatScript.CONTACT_COOLDOWN / STEP))
	_check(_players[0].health.health == _players[0].health.max_health - 4, "a second hit after the cooldown")
	enemy.position += Vector2(500.0, 0.0)
	var before: int = _players[0].health.health
	_run(int(CombatScript.CONTACT_COOLDOWN / STEP) + 1)
	_check(_players[0].health.health == before, "an enemy out of reach does nothing")


func _test_contact_hurts_only_the_one_touched() -> void:
	_setup(4)
	_enemy(10, _players[2].position, 1)
	_run(1)
	for index in 4:
		var expected: int = _players[index].health.max_health - (1 if index == 2 else 0)
		_check(_players[index].health.health == expected, "player %d health is %d" % [index, expected])


func _test_four_players_kill_credit() -> void:
	_setup(4)
	_profile(1, 1)
	var enemy := _enemy(4)
	for index in 4:
		_bus.projectile_hit.emit(index, enemy, Vector2.ZERO, 1, -1)
	_check(_damage.size() == 4, "four hits, four damage events")
	_check(_deaths == [[3, enemy]], "player 3 landed the last hit and gets the kill")
	var second := _enemy(1)
	_bus.projectile_hit.emit(0, second, Vector2.ZERO, 1, -1)
	_check(_deaths.size() == 2 and _deaths[1] == [0, second], "the next kill goes to player 0")


func _test_freed_enemy_is_dropped() -> void:
	_setup()
	var enemy := _enemy(5)
	var keep := _enemy(5)
	enemy.free()
	_run(1)
	_check(_combat.actor_count() == 1 and _combat.is_registered(keep), "a freed enemy is dropped, the other stays")
	_check(_combat.hit(0, keep, 1), "the remaining enemy can still be hit")


func _test_freed_enemy_target_is_pruned() -> void:
	_setup(0, true)
	var enemy := _enemy(5)
	enemy.free()
	_run(1)
	_projectiles.step(STEP)
	_check(_projectiles.get_target_count() == 0, "the projectile manager prunes a freed enemy's target")


func _test_death_frees_enemy_in_tree() -> void:
	_setup()
	var enemy := _enemy(1)
	root.add_child(enemy)
	_combat.hit(0, enemy, 1)
	_check(enemy.is_queued_for_deletion(), "an enemy in the tree is queue_free'd on death")
	_check(_deaths == [[0, enemy]], "its death was sent")


func _test_reregister_resets_numbers_and_target() -> void:
	_setup(0, true)
	var enemy := _enemy(5)
	_combat.hit(0, enemy, 2)
	_combat.register_actor(enemy, 9, 30.0, 2)
	_check(_combat.health_of(enemy) == 9 and _combat.actor_count() == 1, "registering twice resets health, one row")
	_check(_projectiles.get_target_count() == 1, "still one projectile target")
	_check(is_equal_approx(_projectiles._target_radius[0], 30.0), "the projectile target radius follows the new hurt radius")


func _test_listener_may_change_registrations() -> void:
	_setup(1)
	var first := _enemy(5, _players[0].position, 1)
	var second := _enemy(5, _players[0].position, 1)
	_bus.damage_dealt.connect(func(_p: int, target: Node, _a: int, _at: Vector2) -> void:
		if target == _players[0]:
			_combat.unregister_actor(first)
			_combat.unregister_actor(second))
	_run(1)
	_check(_combat.actor_count() == 1, "a listener removed both enemies during step without errors (the wizard is left)")
	var third := _enemy(5)
	_bus.damage_dealt.connect(func(_p: int, target: Node, _a: int, _at: Vector2) -> void:
		if target == third:
			_combat.unregister_actor(third))
	_check(_combat.hit(0, third, 1), "a hit still counts when a listener unregisters the enemy")
	_check(_deaths.is_empty(), "no death is sent for an enemy a listener removed")


func _test_wizard_is_a_projectile_target_for_enemy_shots() -> void:
	_setup(2, true)
	_check(_projectiles.get_target_count() == 2, "both wizards are projectile targets")
	_combat.unregister_actor(_players[0])
	_check(_projectiles.get_target_count() == 1, "an unregistered wizard stops being a target")
	_combat.register_actor(_players[0], 1, 8.0)
	_check(_projectiles.get_target_count() == 2, "registered again, it is a target again")
	_combat.register_actor(_players[0], 1, 8.0)
	_check(_projectiles.get_target_count() == 2, "registering it twice keeps one target")


func _test_downed_wizard_is_not_a_projectile_target() -> void:
	_setup(2, true)
	_players[0].health.take(1000)
	_check(_players[0].is_downed(), "the wizard is downed")
	_check(_projectiles.get_target_count() == 1, "a downed wizard stops being a projectile target")
	Downed.of(_players[0]).revive(1)
	_check(_projectiles.get_target_count() == 2, "a revived wizard is a projectile target again")
	_players[0].health.take(1000)
	_combat.register_actor(_players[0], 1, 8.0)
	_check(_projectiles.get_target_count() == 1, "registering a downed wizard does not make it a target")


## Regression (#5): the hurt and hit circles sat at the feet, below the drawn body.
## Shots through the body hit and shots along the feet miss, for the wizard (also after
## a revive) and for an enemy.
func _test_hit_circles_follow_the_body_offset() -> void:
	_setup(1, true)
	_projectiles.events = _bus
	_profile(9, 1)
	var body := Vector2(0.0, -12.0)
	var wizard: Actor = _players[0]
	wizard.position = Vector2(100.0, 0.0)
	_combat.register_actor(wizard, 1, 8.0, 0, body)
	_shoot_at_wizard(-12.0)
	_check(_damage.size() == 1, "an enemy shot through the wizard's body hits")
	_shoot_at_wizard(0.0)
	_check(_damage.size() == 1, "an enemy shot along the wizard's feet misses")
	wizard.health.take(1000)
	Downed.of(wizard).revive(1)
	_damage.clear()
	_shoot_at_wizard(-12.0)
	_check(_damage.size() == 1, "a revived wizard is still hit at the body")
	var enemy := Node2D.new()
	root.add_child(enemy)
	enemy.position = Vector2(100.0, 0.0)
	_enemies.append(enemy)
	_combat.register_actor(enemy, 5, 11.0, 0, body)
	_damage.clear()
	_projectiles.spawn(0, Vector2(0.0, -12.0), Vector2(600.0, 0.0), 1.0, 2.0, ProjectileManagerScript.LAYER_ENEMY, 0, 9)
	_projectiles.step(0.2)
	_check(_damage.size() == 1 and _damage[0][1] == enemy, "a player shot through the enemy's body hits it")
	_damage.clear()
	# At the feet (y = 2): 14 px from the circle's centre, beyond 11 + 2.
	_projectiles.spawn(0, Vector2(0.0, 2.0), Vector2(600.0, 0.0), 1.0, 2.0, ProjectileManagerScript.LAYER_ENEMY, 0, 9)
	_projectiles.step(0.2)
	_check(_damage.is_empty(), "a player shot along the enemy's feet misses it")


## Fire an enemy shot (tag 9) at the wizard at (100, 0) along height `y`.
func _shoot_at_wizard(y: float) -> void:
	_projectiles.spawn(EventsScript.NO_PLAYER, Vector2(0.0, y), Vector2(600.0, 0.0), 1.0, 2.0, ProjectileManagerScript.LAYER_PLAYER, 0, 9)
	_projectiles.step(0.2)


## Contact compares the bodies, not the feet.
func _test_contact_uses_the_body_offset() -> void:
	_setup(1)
	var body := Vector2(0.0, -12.0)
	_combat.register_actor(_players[0], 1, 8.0, 0, body)
	var enemy := Node2D.new()
	enemy.position = _players[0].position + Vector2(0.0, -29.0)
	_enemies.append(enemy)
	_combat.register_actor(enemy, 5, 10.0, 2)
	_run(1)
	_check(_players[0].health.health == _players[0].health.max_health - 2, "contact when the wizard's body touches the enemy (17 px, though the origins are 29 apart)")
