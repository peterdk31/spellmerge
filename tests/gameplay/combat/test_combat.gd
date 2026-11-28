extends "res://tests/support/suite.gd"
## gameplay/combat on plain registered bodies and real wizards: damage, knockback, death, kill
## credit, contact hit boxes, projectile targets and the hit circles at the body, with several
## players at once. Each test builds its own Combat on its own bus, Spells and actor table (`_setup`:
## with as many wizards of the real scene as it needs, and a projectile manager only when it needs
## one); `after_each` frees it all. Hits arrive through the event bus like the real ones
## (`projectile_hit`); time moves by fixed binary-fraction steps. Contact between actors of teams
## (its cooldown, its credit) is test_combat_actors.gd's.

const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const WizardScene := preload("res://content/wizard/base/wizard.tscn")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")

const STEP: float = 0.0625
## Where a body's hit circle sits above its feet (#5).
const BODY := Vector2(0.0, -12.0)

var bus: EventsScript
var combat: CombatScript
var projectiles: ProjectileManagerScript
## Where Combat reads what a shot does (`hit_profile`); `_profile` fills it.
var spells: SpellsScript
var players: Array[Actor] = []
## The wizards' actor table (not the autoload).
var actors: ActorsScript
## Each damage_dealt as [player, target, amount].
var damage: Array = []
## Each enemy_died as [player, enemy].
var deaths: Array = []


func after_each() -> void:
	for wizard in players:
		if is_instance_valid(wizard):
			wizard.free()
	players.clear()
	for node: Node in [combat, spells, projectiles, actors, bus]:
		if node != null and is_instance_valid(node):
			node.free()
	combat = null
	spells = null
	projectiles = null
	actors = null
	bus = null
	damage.clear()
	deaths.clear()


func _setup(player_count: int = 0, with_projectiles: bool = false) -> void:
	bus = EventsScript.new()
	combat = CombatScript.new()
	combat.events = bus
	spells = SpellsScript.new()
	combat.spells = spells
	if with_projectiles:
		projectiles = ProjectileManagerScript.new()
		combat.projectiles = projectiles
	combat._ready()
	bus.damage_dealt.connect(func(p: int, target: Node, amount: int, _at: Vector2) -> void:
		damage.append([p, target, amount]))
	bus.enemy_died.connect(func(p: int, enemy: Node, _at: Vector2, _shot: int) -> void:
		deaths.append([p, enemy]))
	actors = ActorsScript.new()
	# One actor table for the wizards, Combat and the projectile manager (teams aim contact).
	combat.actors = actors
	if projectiles != null:
		projectiles.actors = actors
	for index in player_count:
		# A wizard actor of the real scene (actors G7), in the tree: its hurtbox registers it in
		# Combat's seat slot (8 px, at the body).
		var wizard := WizardScene.instantiate() as Actor
		PlayerController.seat_wizard(wizard, index, null, [[], [], [], []])
		wizard.events = bus
		wizard.combat = combat
		wizard.spells = spells
		wizard.projectiles = projectiles
		wizard.actors = actors
		wizard.position = Vector2(1000.0 * index, 1000.0)
		root.add_child(wizard)
		wizard.ticking = false
		players.append(wizard)


## Say what a shot with `tag` does, as a spell's hit profile in Spells (staffs F9b: Combat's own
## table is gone).
func _profile(tag: int, amount: int, knockback: float = 0.0) -> void:
	var hit := HitProfile.new()
	hit.damage = amount
	hit.knockback = knockback
	var spell := CompiledSpell.new()
	spell.hit = hit
	spells.get("_profiles")[tag] = spell


## A plain body registered in Combat as an enemy, freed after the test.
func _enemy(health: float, at: Vector2 = Vector2.ZERO, contact: int = 0) -> Node2D:
	var enemy := own(Node2D.new()) as Node2D
	enemy.position = at
	combat.register_actor(enemy, health, 10.0, contact)
	return enemy


## A plain body nobody registered, freed after the test.
func _stranger() -> Node2D:
	return own(Node2D.new()) as Node2D


func _run(count: int) -> void:
	for i in count:
		combat.step(STEP)


# --- Damage and death ------------------------------------------------------------------------

func test_a_hit_takes_its_damage_from_health() -> void:
	_setup()
	var enemy: Node2D = _enemy(10)
	check(combat.hit(2, enemy, 3), "a hit for 3 counts")
	check_equal(combat.health_of(enemy), 7.0, "health 10 minus 3 is 7")


func test_a_hit_sends_damage_dealt_naming_the_player_the_target_and_the_amount() -> void:
	_setup()
	var enemy: Node2D = _enemy(10)
	combat.hit(2, enemy, 3)
	check_equal(damage, [[2, enemy, 3]], "damage_dealt names player 2, the enemy and 3")


func test_a_hit_short_of_death_kills_nothing() -> void:
	_setup()
	combat.hit(2, _enemy(10), 3)
	check(deaths.is_empty(), "no death yet")


func test_bad_hits_do_nothing() -> void:
	_setup()
	var enemy: Node2D = _enemy(5)
	check(not combat.hit(0, enemy, 0), "0 damage does not count")
	check(not combat.hit(0, enemy, -4), "negative damage does not count")
	check(not combat.hit(0, null, 3), "a null target does not count")
	check(combat.health_of(enemy) == 5 and damage.is_empty(), "nothing changed, nothing sent")


func test_a_body_that_is_not_registered_cannot_be_hit() -> void:
	_setup(1)
	var stranger: Node2D = _stranger()
	check(not combat.hit(0, stranger, 3), "a node that is not registered cannot be hit")
	check(damage.is_empty() and not combat.is_registered(stranger), "no event, still not an enemy")


func test_enemy_died_names_the_player_with_the_last_hit() -> void:
	_setup()
	var enemy: Node2D = _enemy(4, Vector2(5.0, 6.0))
	combat.hit(0, enemy, 2)
	combat.hit(3, enemy, 9)  # overkill: health stops at 0
	check_equal(deaths, [[3, enemy]], "enemy_died names the player with the last hit")


func test_a_dead_enemy_is_no_longer_registered() -> void:
	_setup()
	var enemy: Node2D = _enemy(4)
	combat.hit(3, enemy, 9)
	check(combat.health_of(enemy) == -1 and not combat.is_registered(enemy), "a dead enemy is no longer registered")
	check_equal(combat.actor_count(), 0, "no enemies left")


func test_the_killing_hit_also_sends_damage_dealt() -> void:
	_setup()
	var enemy: Node2D = _enemy(4)
	combat.hit(0, enemy, 2)
	combat.hit(3, enemy, 9)
	check(damage.size() == 2 and damage[1][2] == 9, "both hits sent damage_dealt")


func test_a_dead_enemy_cannot_die_twice() -> void:
	_setup()
	var enemy: Node2D = _enemy(1)
	combat.hit(1, enemy, 1)
	check(not combat.hit(1, enemy, 1), "a hit on a dead enemy does not count")
	check(deaths.size() == 1 and damage.size() == 1, "one death, one damage event")


func test_a_death_in_the_tree_frees_the_enemy() -> void:
	_setup()
	var enemy: Node2D = _enemy(1)
	root.add_child(enemy)
	combat.hit(0, enemy, 1)
	check(enemy.is_queued_for_deletion(), "an enemy in the tree is queue_free'd on death")
	check_equal(deaths, [[0, enemy]], "its death was sent")


func test_the_last_of_four_players_to_hit_gets_the_kill() -> void:
	_setup(4)
	_profile(1, 1)
	var enemy: Node2D = _enemy(4)
	for index in 4:
		bus.projectile_hit.emit(index, enemy, Vector2.ZERO, 1, -1)
	check_equal(damage.size(), 4, "four hits, four damage events")
	check_equal(deaths, [[3, enemy]], "player 3 landed the last hit and gets the kill")


func test_a_kill_after_another_goes_to_its_own_player() -> void:
	_setup(4)
	_profile(1, 1)
	var enemy: Node2D = _enemy(1)
	bus.projectile_hit.emit(3, enemy, Vector2.ZERO, 1, -1)
	var second: Node2D = _enemy(1)
	bus.projectile_hit.emit(0, second, Vector2.ZERO, 1, -1)
	check(deaths.size() == 2 and deaths[1] == [0, second], "the next kill goes to player 0")


# --- Knockback -------------------------------------------------------------------------------

## An enemy at (10, 0) hit to the right with strength 160.
func _pushed() -> Node2D:
	_setup()
	var enemy: Node2D = _enemy(100, Vector2(10.0, 0.0))
	combat.hit(0, enemy, 1, Vector2.RIGHT, 160.0)
	return enemy


func test_knockback_is_its_direction_times_its_strength() -> void:
	check_equal(combat.knockback_of(_pushed()), Vector2(160.0, 0.0), "knockback velocity is direction times strength")


func test_combat_never_moves_or_fades_a_push_by_itself() -> void:
	var enemy: Node2D = _pushed()
	_run(4)
	check_equal(enemy.position, Vector2(10.0, 0.0), "Combat never moves the enemy itself")
	check_equal(combat.knockback_of(enemy), Vector2(160.0, 0.0), "step() does not fade knockback")


func test_the_mover_gets_the_full_knockback_on_its_first_step() -> void:
	var enemy: Node2D = _pushed()
	check_equal(combat.consume_knockback(enemy, STEP), Vector2(160.0, 0.0), "the mover gets the full velocity on the first step")
	check(combat.knockback_of(enemy).x < 160.0, "the stored knockback fades after a step")


func test_knockback_fades_to_nothing_over_a_short_distance() -> void:
	var enemy: Node2D = _pushed()
	var travelled: float = 0.0
	for i in 9:
		travelled += combat.consume_knockback(enemy, STEP).x * STEP
	check_equal(combat.knockback_of(enemy), Vector2.ZERO, "knockback fades to zero")
	check_equal(combat.consume_knockback(enemy, STEP), Vector2.ZERO, "nothing left to consume")
	check(travelled > 0.0 and travelled < 160.0, "knockback travels a short distance only")


func test_an_unregistered_body_has_no_knockback() -> void:
	_setup()
	check_equal(combat.consume_knockback(_stranger(), STEP), Vector2.ZERO, "an unregistered node has no knockback")


func test_a_push_of_zero_strength_pushes_nothing() -> void:
	_setup()
	var enemy: Node2D = _enemy(10, Vector2(3.0, 3.0))
	combat.hit(0, enemy, 1, Vector2.RIGHT, 0.0)
	check_equal(combat.consume_knockback(enemy, STEP), Vector2.ZERO, "strength 0 pushes nothing")


# --- Projectile hits -------------------------------------------------------------------------

func test_a_projectile_hit_deals_its_profiles_damage_for_the_shooter() -> void:
	_setup()
	var enemy: Node2D = _enemy(20, Vector2(10.0, 0.0))
	_profile(7, 5, 100.0)
	bus.projectile_hit.emit(1, enemy, Vector2(0.0, 0.0), 7, -1)
	check_equal(damage, [[1, enemy, 5]], "projectile_hit with tag 7 deals the profile's damage for the shooter")
	check_equal(combat.health_of(enemy), 15.0, "health 20 minus 5")


func test_a_projectile_hit_pushes_away_from_where_it_hit() -> void:
	_setup()
	var enemy: Node2D = _enemy(20, Vector2(10.0, 0.0))
	_profile(7, 5, 100.0)
	bus.projectile_hit.emit(1, enemy, Vector2(0.0, 0.0), 7, -1)
	check(combat.knockback_of(enemy).x > 0.0, "pushed away from the hit position")


## Regression: measured to the hit circle's centre, not the feet: a hit under a raised circle (but
## above the feet) pushes up, away from the hit.
func test_a_hit_below_a_raised_hit_circle_pushes_it_up() -> void:
	_setup()
	_profile(7, 5, 100.0)
	var raised: Node2D = _enemy(20, Vector2(100.0, 0.0))
	combat.register_actor(raised, 20.0, 10.0, 0, Vector2(0.0, -14.0))
	bus.projectile_hit.emit(1, raised, Vector2(100.0, -6.0), 7, -1)
	check(combat.knockback_of(raised).y < 0.0 and is_zero_approx(combat.knockback_of(raised).x), "a hit below a raised hit circle pushes it up (%s)" % combat.knockback_of(raised))


func test_a_projectile_hit_without_a_profile_is_ignored() -> void:
	_setup()
	var enemy: Node2D = _enemy(5)
	bus.projectile_hit.emit(0, enemy, Vector2.ZERO, 0, -1)
	bus.projectile_hit.emit(0, enemy, Vector2.ZERO, 99, -1)
	check(damage.is_empty() and combat.health_of(enemy) == 5, "tags without a profile do no damage")


# --- Wizards ---------------------------------------------------------------------------------

func test_a_hit_on_a_wizard_takes_its_health() -> void:
	_setup(2)
	check(combat.hit(EventsScript.NO_PLAYER, players[1], 3), "a hit on a wizard counts")
	check_equal(players[1].health.health, players[1].health.max_health - 3, "the wizard lost 3 health through damage_dealt")


func test_a_hit_on_one_wizard_leaves_the_other() -> void:
	_setup(2)
	combat.hit(EventsScript.NO_PLAYER, players[1], 3)
	check_equal(players[0].health.health, players[0].health.max_health, "the other wizard is untouched")


func test_a_dodging_wizard_is_not_hit() -> void:
	_setup(2)
	players[0].health.protect(0.25)
	check(not combat.hit(EventsScript.NO_PLAYER, players[0], 3), "a dodging wizard is not hit")
	check(damage.is_empty() and players[0].health.health == players[0].health.max_health, "no event, no damage")


func test_a_downed_wizard_is_not_hit() -> void:
	_setup(2)
	players[1].health.take(1000)
	check(not combat.hit(EventsScript.NO_PLAYER, players[1], 3), "a downed wizard is not hit")
	check(damage.is_empty(), "no event")


# --- Contact ---------------------------------------------------------------------------------

func test_touching_an_enemy_costs_its_contact_damage() -> void:
	_setup(1)
	_enemy(10, players[0].position + Vector2(5.0, 0.0), 2)
	_run(1)
	check_equal(players[0].health.health, players[0].health.max_health - 2, "touching the enemy costs its contact damage")


func test_an_enemy_out_of_reach_does_no_contact_damage() -> void:
	_setup(1)
	_enemy(10, players[0].position + Vector2(505.0, 0.0), 2)
	_run(int(CombatScript.CONTACT_COOLDOWN / STEP) + 1)
	check_equal(players[0].health.health, players[0].health.max_health, "an enemy out of reach does nothing")


func test_contact_hurts_only_the_wizard_touched() -> void:
	_setup(4)
	_enemy(10, players[2].position, 1)
	_run(1)
	for index in 4:
		var expected: float = players[index].health.max_health - (1.0 if index == 2 else 0.0)
		check_equal(players[index].health.health, expected, "player %d health" % index)


## Contact compares the bodies, not the feet.
func test_contact_compares_the_bodies_not_the_feet() -> void:
	_setup(1)
	combat.register_actor(players[0], 1, 8.0, 0, BODY)
	var enemy: Node2D = _stranger()
	enemy.position = players[0].position + Vector2(0.0, -29.0)
	combat.register_actor(enemy, 5, 10.0, 2)
	_run(1)
	check_equal(players[0].health.health, players[0].health.max_health - 2, "contact when the wizard's body touches the enemy (17 px, though the origins are 29 apart)")


# --- Registrations ---------------------------------------------------------------------------

func test_a_freed_enemy_is_dropped_and_the_other_stays_hittable() -> void:
	_setup()
	var enemy: Node2D = _enemy(5)
	var keep: Node2D = _enemy(5)
	enemy.free()
	_run(1)
	check(combat.actor_count() == 1 and combat.is_registered(keep), "a freed enemy is dropped, the other stays")
	check(combat.hit(0, keep, 1), "the remaining enemy can still be hit")


func test_registering_twice_resets_the_health_in_one_row() -> void:
	_setup(0, true)
	var enemy: Node2D = _enemy(5)
	combat.hit(0, enemy, 2)
	combat.register_actor(enemy, 9, 30.0, 2)
	check(combat.health_of(enemy) == 9 and combat.actor_count() == 1, "registering twice resets health, one row")


func test_registering_twice_keeps_one_projectile_target_of_the_new_radius() -> void:
	_setup(0, true)
	var enemy: Node2D = _enemy(5)
	combat.register_actor(enemy, 9, 30.0, 2)
	check_equal(projectiles.get_target_count(), 1, "still one projectile target")
	check(is_equal_approx(projectiles._target_radius[0], 30.0), "the projectile target radius follows the new hurt radius")


func test_a_listener_may_unregister_enemies_during_a_step() -> void:
	_setup(1)
	var first: Node2D = _enemy(5, players[0].position, 1)
	var second: Node2D = _enemy(5, players[0].position, 1)
	bus.damage_dealt.connect(func(_p: int, target: Node, _a: int, _at: Vector2) -> void:
		if target == players[0]:
			combat.unregister_actor(first)
			combat.unregister_actor(second))
	_run(1)
	check_equal(combat.actor_count(), 1, "a listener removed both enemies during step without errors (the wizard is left)")


func test_a_hit_on_an_enemy_a_listener_unregisters_counts_with_no_death() -> void:
	_setup()
	var third: Node2D = _enemy(5)
	bus.damage_dealt.connect(func(_p: int, target: Node, _a: int, _at: Vector2) -> void:
		if target == third:
			combat.unregister_actor(third))
	check(combat.hit(0, third, 1), "a hit still counts when a listener unregisters the enemy")
	check(deaths.is_empty(), "no death is sent for an enemy a listener removed")


# --- The hit table (perf plan H1) -------------------------------------------------------------

func test_a_hit_the_manager_sends_is_applied_once_from_its_row() -> void:
	_setup(0, true)
	projectiles.events = bus
	_profile(1, 2)
	var enemy: Node2D = _enemy(10, Vector2(100.0, 100.0))
	var health_when_heard: Array[float] = []
	# A listener connected after Combat still hears the hit before Combat applies it.
	bus.projectile_hit.connect(func(_c: int, target: Node, _at: Vector2, _tag: int, _shot: int) -> void:
		health_when_heard.append(combat.health_of(target)))
	check(projectiles.strike(0, enemy, Vector2(100.0, 100.0), Vector2.RIGHT, 1, &"swing"), "the strike was sent")
	check_equal(damage.size(), 1, "one hit, applied once (from its row, not also by the listener)")
	check_equal(health_when_heard, [10.0] as Array[float], "every listener heard it before Combat applied it")
	check(is_equal_approx(combat.health_of(enemy), 8.0), "its damage taken once")
	check_equal(projectiles.hit_table.rows, 1, "one row in the table")


func test_a_hit_sent_by_hand_is_still_applied() -> void:
	_setup(0, true)
	projectiles.events = bus
	_profile(1, 3)
	var enemy: Node2D = _enemy(10)
	bus.projectile_hit.emit(0, enemy, Vector2.ZERO, 1, -1)
	check(is_equal_approx(combat.health_of(enemy), 7.0), "a hit no row stands for is applied by the listener")


func test_merged_hits_land_as_their_row_counts_them() -> void:
	_setup(0, true)
	projectiles.events = bus
	projectiles.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_profile(1, 2)
	var enemy: Node2D = _enemy(50, Vector2(200.0, 100.0))
	root.add_child(enemy)
	for i in 3:
		projectiles.spawn(0, Vector2(150.0, 100.0 + float(i)), Vector2(600.0, 0.0), 5.0, 4.0, ProjectileManagerScript.LAYER_ENEMY, 0, 1)
	for _i in 10:
		projectiles.step(1.0 / 60.0)
	check_equal(damage.size(), 1, "three shots of one spell in one pass: one merged hit")
	check(is_equal_approx(combat.health_of(enemy), 44.0), "the merged hit took three hits' damage (%s)" % combat.health_of(enemy))


# --- Projectile targets ----------------------------------------------------------------------

func test_a_registered_enemy_is_a_projectile_target() -> void:
	_setup(0, true)
	_enemy(1)
	check_equal(projectiles.get_target_count(), 1, "a registered enemy is a projectile target")


func test_a_dead_enemy_is_no_projectile_target() -> void:
	_setup(0, true)
	combat.hit(0, _enemy(1), 5)
	check_equal(projectiles.get_target_count(), 0, "a dead enemy is no longer a target")


func test_a_freed_enemys_target_is_pruned() -> void:
	_setup(0, true)
	var enemy: Node2D = _enemy(5)
	enemy.free()
	_run(1)
	projectiles.step(STEP)
	check_equal(projectiles.get_target_count(), 0, "the projectile manager prunes a freed enemy's target")


func test_both_wizards_are_projectile_targets() -> void:
	_setup(2, true)
	check_equal(projectiles.get_target_count(), 2, "both wizards are projectile targets")


func test_an_unregistered_wizard_is_a_target_again_once_registered() -> void:
	_setup(2, true)
	combat.unregister_actor(players[0])
	check_equal(projectiles.get_target_count(), 1, "an unregistered wizard stops being a target")
	combat.register_actor(players[0], 1, 8.0)
	check_equal(projectiles.get_target_count(), 2, "registered again, it is a target again")


func test_a_wizard_registered_twice_is_one_target() -> void:
	_setup(2, true)
	combat.register_actor(players[0], 1, 8.0)
	check_equal(projectiles.get_target_count(), 2, "registering it twice keeps one target")


func test_a_downed_wizard_is_no_projectile_target() -> void:
	_setup(2, true)
	players[0].health.take(1000)
	check(players[0].is_downed(), "the wizard is downed")
	check_equal(projectiles.get_target_count(), 1, "a downed wizard stops being a projectile target")


func test_a_revived_wizard_is_a_projectile_target_again() -> void:
	_setup(2, true)
	players[0].health.take(1000)
	Downed.of(players[0]).revive(1)
	check_equal(projectiles.get_target_count(), 2, "a revived wizard is a projectile target again")


func test_registering_a_downed_wizard_makes_no_target() -> void:
	_setup(2, true)
	players[0].health.take(1000)
	combat.register_actor(players[0], 1, 8.0)
	check_equal(projectiles.get_target_count(), 1, "registering a downed wizard does not make it a target")


# --- Hit circles at the body -----------------------------------------------------------------
# Regression (#5): the hurt and hit circles sat at the feet, below the drawn body. Shots through
# the body hit and shots along the feet miss, for the wizard (also after a revive) and for an enemy.

## One wizard at (100, 0) with its hit circle at the body, and enemy shots (tag 9) of 1 damage.
func _wizard_at_the_body() -> Actor:
	_setup(1, true)
	projectiles.events = bus
	_profile(9, 1)
	var wizard: Actor = players[0]
	wizard.position = Vector2(100.0, 0.0)
	combat.register_actor(wizard, 1, 8.0, 0, BODY)
	return wizard


## Fire an enemy shot (tag 9) at the wizard at (100, 0) along height `y`.
func _shoot_at_wizard(y: float) -> void:
	projectiles.spawn(EventsScript.NO_PLAYER, Vector2(0.0, y), Vector2(600.0, 0.0), 1.0, 2.0, ProjectileManagerScript.LAYER_PLAYER, 0, 9)
	projectiles.step(0.2)


## An enemy at (100, 0) with its hit circle (11 px) at the body, and player shots (tag 9).
func _enemy_at_the_body() -> Node2D:
	_setup(0, true)
	projectiles.events = bus
	_profile(9, 1)
	var enemy: Node2D = _stranger()
	root.add_child(enemy)
	enemy.position = Vector2(100.0, 0.0)
	combat.register_actor(enemy, 5, 11.0, 0, BODY)
	return enemy


## Fire a player shot (tag 9) at the enemy at (100, 0) along height `y`.
func _shoot_at_enemy(y: float) -> void:
	projectiles.spawn(0, Vector2(0.0, y), Vector2(600.0, 0.0), 1.0, 2.0, ProjectileManagerScript.LAYER_ENEMY, 0, 9)
	projectiles.step(0.2)


func test_an_enemy_shot_through_the_wizards_body_hits() -> void:
	_wizard_at_the_body()
	_shoot_at_wizard(BODY.y)
	check_equal(damage.size(), 1, "an enemy shot through the wizard's body hits")


func test_an_enemy_shot_along_the_wizards_feet_misses() -> void:
	_wizard_at_the_body()
	_shoot_at_wizard(0.0)
	check(damage.is_empty(), "an enemy shot along the wizard's feet misses")


func test_a_revived_wizard_is_still_hit_at_the_body() -> void:
	var wizard: Actor = _wizard_at_the_body()
	wizard.health.take(1000)
	Downed.of(wizard).revive(1)
	damage.clear()
	_shoot_at_wizard(BODY.y)
	check_equal(damage.size(), 1, "a revived wizard is still hit at the body")


func test_a_player_shot_through_an_enemys_body_hits_it() -> void:
	var enemy: Node2D = _enemy_at_the_body()
	_shoot_at_enemy(BODY.y)
	check(damage.size() == 1 and damage[0][1] == enemy, "a player shot through the enemy's body hits it")


func test_a_player_shot_along_an_enemys_feet_misses_it() -> void:
	_enemy_at_the_body()
	# At the feet (y = 2): 14 px from the circle's centre, beyond 11 + 2.
	_shoot_at_enemy(2.0)
	check(damage.is_empty(), "a player shot along the enemy's feet misses it")
