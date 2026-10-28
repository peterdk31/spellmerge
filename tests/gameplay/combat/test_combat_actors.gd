extends "res://tests/support/suite.gd"
## Combat by actor (actors G5, docs/milestones/M2-actors.md, "Combat: one rule"): one row per
## actor id for every body. A kit Actor is kept under its own id and hurt through its Health; a
## body with no id gets one Combat opens and gives back; an id and a node find the same row;
## death, being downed instead, contact by team, and rows freed in any order. The world is the
## actor kit's test world (its own bus, projectile manager, Spells, Combat and actor table).
##
## godot --headless --path . --script res://tests/gameplay/combat/test_combat_actors.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")

var _world: Fixture
var _deaths: Array = []
var _kills: Array = []


func before_each() -> void:
	_world = Fixture.new(root, Fixture.FakeRegistry.new())
	_deaths.clear()
	_kills.clear()
	_world.bus.enemy_died.connect(func(killer: int, body: Node, _at: Vector2) -> void: _deaths.append([killer, body]))
	_world.bus.kill_landed.connect(func(caster: int, body: Node, _at: Vector2, tag: int) -> void: _kills.append([caster, body, tag]))


func after_each() -> void:
	_world.free_all()


## A kit actor with Health (`health`), a Hurtbox and a Contact of `touch` damage, on `team`.
func _actor(at: Vector2, team: int, touch: int = 0, health: int = 50) -> Actor:
	var body := Actor.new()
	body.idle_team = team
	var hp := Health.new()
	hp.max_health = health
	body.add_child(hp)
	body.add_child(Hurtbox.new())
	var contact := Contact.new()
	contact.damage = touch
	body.add_child(contact)
	return _world.add(body, at)


## A plain body (no kit, no id of its own) Combat keeps the health of.
func _plain(at: Vector2, health: int = 20) -> Node2D:
	var body := own(Node2D.new()) as Node2D
	body.position = at
	root.add_child(body)
	_world.combat.register_actor(body, health, 10.0)
	return body


func test_a_kit_actor_is_kept_under_its_own_id_and_hurt_through_its_health() -> void:
	var imp: Actor = _actor(Vector2.ZERO, ActorsScript.TEAM_ENEMIES)
	check_equal(_world.combat.actor_of(imp), imp.id, "its row is its actor id")
	check(_world.combat.hit(3, imp, 12), "a hit counts")
	check_equal(imp.health.health, 38, "its Health took it")
	check_equal(_world.combat.health_of(imp.id), 38, "and Combat reads it from there")


func test_an_id_and_the_node_find_the_same_actor() -> void:
	var imp: Actor = _actor(Vector2.ZERO, ActorsScript.TEAM_ENEMIES)
	check(_world.combat.apply_status(0, imp.id, CombatScript.HEX, 2.0, 50.0), "a status by id")
	check(_world.combat.has_status(imp, CombatScript.HEX), "is on the node")
	_world.combat.give_shield(imp, 2, 1.0)
	check_equal(_world.combat.shield(imp.id), 2, "a barrier by node is on the id")
	check_equal(_world.combat.pace(imp), _world.combat.pace_of(imp.id), "pace by node and by id agree")


func test_a_kit_actor_combat_kills_dies_and_counts_as_an_enemy() -> void:
	var imp: Actor = _actor(Vector2.ZERO, ActorsScript.TEAM_ENEMIES, 0, 10)
	var died: Array[int] = []
	imp.died.connect(func(killer: int) -> void: died.append(killer))
	check(_world.combat.hit(2, imp, 25), "the killing hit counts")
	check_equal(died, [2] as Array[int], "the actor died, killed by the hitter")
	check(imp.is_queued_for_deletion(), "and frees itself")
	check_equal(_deaths, [[2, imp]], "enemy_died is sent for a body not on the wizards' team")
	check(not _world.combat.is_registered(imp), "its row is free")
	check(not _world.combat.hit(2, imp, 1), "a dead actor is hit no more")


func test_a_wizard_side_actor_that_dies_sends_no_enemy_died() -> void:
	var mage: Actor = _actor(Vector2.ZERO, ActorsScript.TEAM_WIZARDS, 0, 10)
	_world.combat.hit(1, mage, 25)
	check(mage.is_dying(), "it died")
	check(_deaths.is_empty(), "the wave does not count it")


func test_a_downable_actor_at_zero_is_downed_not_killed() -> void:
	var mage: Actor = _actor(Vector2.ZERO, ActorsScript.TEAM_WIZARDS, 0, 10)
	mage.downable = true
	mage.health.depleted.connect(func(_killer: int) -> void: mage.set_down(true))
	_world.combat.hit(1, mage, 25)
	check(not mage.is_dying(), "something else downs it")
	check(_deaths.is_empty() and _kills.is_empty(), "no death is told")
	check(not _world.combat.hit(1, mage, 5), "and a down actor is not hurt")


func test_a_spell_kill_on_a_kit_actor_is_the_spells() -> void:
	var imp: Actor = _actor(Vector2.ZERO, ActorsScript.TEAM_ENEMIES, 0, 4)
	var hit := HitProfile.new()
	hit.damage = 10
	var spell := CompiledSpell.new()
	spell.hit = hit
	var tag: int = SpellTag.make(0, 0, 1, 1)
	_world.spells._profiles[tag] = spell
	_world.bus.projectile_hit.emit(0, imp, Vector2(-5.0, -12.0), tag)
	check_equal(_kills, [[0, imp, tag]], "kill_landed names the caster, the actor and the tag")


func test_a_body_without_an_id_gets_one_and_gives_it_back() -> void:
	var dummy := _plain(Vector2.ZERO)
	var id: int = _world.combat.actor_of(dummy)
	check(id >= 0, "Combat opened an actor for it")
	check_equal(_world.table.team_of(id), ActorsScript.TEAM_ENEMIES, "on the enemies' team")
	check_equal(_world.table.node_of(id), dummy, "naming its node")
	check_equal(_world.projectiles.target_owner_of(dummy), id, "and its target is owned by it")
	_world.combat.unregister_actor(id)
	check(not _world.table.is_open(id), "unregistering gives the id back")


func test_a_plain_body_killed_gives_its_id_back() -> void:
	var dummy := _plain(Vector2.ZERO, 3)
	var id: int = _world.combat.actor_of(dummy)
	_world.combat.hit(0, dummy, 5)
	check_equal(_deaths, [[0, dummy]], "it died as an enemy")
	check(not _world.table.is_open(id), "and its id is free again")


func test_rows_freed_in_any_order_keep_the_rest_whole() -> void:
	var bodies: Array[Node2D] = []
	for i in 40:
		bodies.append(_plain(Vector2(float(i) * 30.0, 0.0), 10 + i))
	for i in range(0, 40, 2):
		_world.combat.unregister_actor(bodies[i])
	_world.combat.unregister_actor(bodies[39])
	check_equal(_world.combat.actor_count(), 19, "19 left")
	for i in range(1, 39, 2):
		check_equal(_world.combat.health_of(bodies[i]), 10 + i, "body %d keeps its own row" % i)
	_world.combat.step(Fixture.STEP)
	check(_world.combat.hit(0, bodies[1], 1), "and can still be hit")


func test_contact_hurts_actors_of_other_teams_only() -> void:
	var imp: Actor = _actor(Vector2.ZERO, ActorsScript.TEAM_ENEMIES, 3)
	var kin: Actor = _actor(Vector2(6.0, 0.0), ActorsScript.TEAM_ENEMIES, 3)
	var mage: Actor = _actor(Vector2(-6.0, 0.0), ActorsScript.TEAM_WIZARDS)
	_world.combat.step(Fixture.STEP)
	check_equal(mage.health.health, 47, "an actor of another team is hurt by the touch (once, whoever touched first)")
	check_equal(imp.health.health, 50, "an imp walking through imps hurts none")
	check_equal(kin.health.health, 50, "nor is it hurt")
	for i in 8:
		_world.combat.step(Fixture.STEP)
	check_equal(mage.health.health, 47, "not again inside the cooldown")
	for i in int(CombatScript.CONTACT_COOLDOWN / Fixture.STEP):
		_world.combat.step(Fixture.STEP)
	check_equal(mage.health.health, 44, "again after it")


func test_contact_is_credited_to_the_actor_that_touched() -> void:
	var imp: Actor = _actor(Vector2.ZERO, ActorsScript.TEAM_ENEMIES, 2)
	var mage: Actor = _actor(Vector2(5.0, 0.0), ActorsScript.TEAM_WIZARDS)
	var dealt: Array = []
	_world.bus.damage_dealt.connect(func(caster: int, target: Node, amount: int, _at: Vector2) -> void: dealt.append([caster, target, amount]))
	_world.combat.step(Fixture.STEP)
	check_equal(dealt, [[imp.id, mage, 2]], "damage_dealt names the toucher's actor")


func test_contact_in_a_crowd_of_two_touching_teams_uses_the_grid() -> void:
	# More victims than CONTACT_DIRECT: each asks the projectile manager's grid what touches it.
	var reds: Array[Actor] = []
	var blues: Array[Actor] = []
	for i in CombatScript.CONTACT_DIRECT + 2:
		reds.append(_actor(Vector2(float(i) * 60.0, 0.0), ActorsScript.TEAM_ENEMIES, 1))
		blues.append(_actor(Vector2(float(i) * 60.0 + 4.0, 0.0), ActorsScript.TEAM_WIZARDS, 1))
	var far: Actor = _actor(Vector2(0.0, 300.0), ActorsScript.TEAM_WIZARDS, 1)
	_world.projectiles.step(Fixture.STEP)
	_world.combat.step(Fixture.STEP)
	for i in reds.size():
		check_equal(reds[i].health.health, 49, "red %d was touched by its blue" % i)
		check_equal(blues[i].health.health, 49, "blue %d was touched by its red" % i)
	check_equal(far.health.health, 50, "one touching nobody is not hurt")


func test_a_step_and_a_hit_make_no_objects() -> void:
	var imp: Actor = _actor(Vector2.ZERO, ActorsScript.TEAM_ENEMIES, 1, 1000)
	var mage: Actor = _actor(Vector2(200.0, 0.0), ActorsScript.TEAM_WIZARDS, 0, 1000)
	_world.combat.apply_status(0, imp, CombatScript.BURN, 5.0, 4.0)
	_world.combat.apply_status(0, mage, CombatScript.CHILL, 5.0, 40.0)
	for i in 4:
		_world.combat.step(Fixture.STEP)
		_world.combat.hit(0, imp, 1)
	var before: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	for i in 16:
		_world.combat.step(Fixture.STEP)
		_world.combat.hit(0, imp, 1)
		_world.combat.pace(imp)
		_world.combat.consume_knockback(mage, Fixture.STEP)
	check_equal(int(Performance.get_monitor(Performance.OBJECT_COUNT)), before, "no objects made")
