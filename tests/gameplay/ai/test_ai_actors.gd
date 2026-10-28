extends "res://tests/support/suite.gd"
## Enemies are actors (actors G6, docs/milestones/M2-actors.md): every enemy body has an actor id
## of the enemies' team that owns its hurt circle and is closed when it goes, an enemy without a
## staff only chases (into its target, to hurt by touch), and infighting: an AI hurt by an actor
## of its own team targets that actor for GRUDGE_TIME seconds, then goes back to its team's
## targets.

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ImpData := preload("res://content/enemies/ember_imp/ember_imp.tres")
const ShootingData := preload("res://content/enemies/shooting_dummy/shooting_dummy.tres")
const TrainingData := preload("res://content/enemies/training_dummy/training_dummy.tres")

var fx: Fixture


func before_each() -> void:
	fx = Fixture.new(root, 1)


func after_each() -> void:
	fx.free_all()


## The imp's numbers with no mana, so it chases and winds up never.
func _broke() -> EnemyBase:
	var data: EnemyBase = ImpData.duplicate() as EnemyBase
	data.max_mana = 0.0
	data.mana_regen = 0.0
	return data


## The imp's numbers with no staff.
func _unarmed() -> EnemyBase:
	var data: EnemyBase = ImpData.duplicate() as EnemyBase
	data.staff = null
	data.cards = []
	data.contact_damage = 3
	return data


func test_every_enemy_body_has_an_actor_id_and_closes_it_when_freed() -> void:
	var bodies: Array[Actor] = [
		fx.imp(Vector2.ZERO),
		fx.imp(Vector2(0.0, 40.0), _unarmed()),
		fx.enemy(ShootingData.scene, ShootingData, Vector2(0.0, 80.0)),
		fx.enemy(TrainingData.scene, TrainingData, Vector2(0.0, 120.0)),
	]
	var ids: Array[int] = []
	for body in bodies:
		var what: String = String(body.data.id) + (" (no staff)" if body.caster == null and body.data.id == &"ember_imp" else "")
		check(fx.actors.is_open(body.id), "%s has an open actor id" % what)
		check_equal(fx.actors.team_of(body.id), ActorsScript.TEAM_ENEMIES, "%s is on the enemies' team" % what)
		check_equal(fx.actors.seat_of(body.id), ActorsScript.NONE, "%s is driven by no seat" % what)
		check(fx.actors.node_of(body.id) == body, "%s is its actor's node" % what)
		check_equal(fx.projectiles.target_owner_of(body), body.id, "%s owns its hurt circle, so its own spells pass it" % what)
		check(fx.combat.is_registered(body.id), "%s can be hurt through Combat" % what)
		ids.append(body.id)
	check(not ids.has(fx.players[0].id), "no enemy shares the wizard's id")
	for at in bodies.size():
		bodies[at].free()
		check(not fx.actors.is_open(ids[at]), "a freed enemy's id is closed (%d)" % ids[at])
	check_equal(fx.combat.actor_count(), fx.players.size(), "and Combat forgot them all (only the wizards are left)")


func test_an_enemy_without_a_staff_only_chases_into_its_target() -> void:
	fx.players[0].position = Vector2(60.0, 0.0)
	var imp: Actor = fx.imp(Vector2.ZERO, _unarmed())
	check(imp.caster == null, "no staff, no caster")
	fx.run(imp, int(2.0 / Fixture.STEP))
	var ai: AIController = Fixture.ai(imp)
	check_equal(ai.state, AIController.State.CHASE, "it never winds up")
	check(imp.position.distance_to(fx.players[0].position) < 2.0, "it walked all the way to the wizard (%.1f px off)" % imp.position.distance_to(fx.players[0].position))
	check_equal(fx.projectiles.get_count(), 0, "and cast nothing")
	check_equal((imp.get_node("Contact") as Contact).damage, 3, "it hurts by touch, its data's contact damage")


func test_an_imp_hurt_by_another_imp_turns_on_it_then_back_to_the_wizards() -> void:
	fx.players[0].position = Vector2(300.0, 0.0)
	var imp: Actor = fx.imp(Vector2.ZERO, _broke())
	var other: Actor = fx.imp(Vector2(-200.0, 0.0), _broke())
	var ai: AIController = Fixture.ai(imp)
	fx.run(imp, 1)
	check(ai.target == fx.players[0], "it chases the wizard")
	# A stray hit of its own kind (the other imp's actor).
	fx.combat.hit(other.id, imp, 1)
	fx.run(imp, 1)
	check(ai.target == other, "hurt by another imp, it turns on that imp")
	check(imp.velocity.x < 0.0, "and walks toward it")
	fx.run(imp, int((AIController.GRUDGE_TIME - 0.25) / Fixture.STEP))
	check(ai.target == other, "for a while")
	fx.run(imp, int(0.5 / Fixture.STEP))
	check(ai.target == fx.players[0], "after GRUDGE_TIME it goes back to the wizards")
	check_equal(ai.grudge_left(), 0.0, "the grudge is over")


func test_no_grudge_against_the_other_team_or_itself() -> void:
	fx.players[0].position = Vector2(300.0, 0.0)
	var imp: Actor = fx.imp(Vector2.ZERO, _broke())
	var ai: AIController = Fixture.ai(imp)
	fx.run(imp, 1)
	fx.combat.hit(fx.players[0].id, imp, 1)
	fx.combat.hit(imp.id, imp, 1)
	fx.run(imp, 1)
	check(ai.grudge == null and ai.target == fx.players[0], "a wizard's hit and its own blast earn no grudge")


func test_a_grudge_ends_when_the_teammate_is_gone() -> void:
	fx.players[0].position = Vector2(300.0, 0.0)
	var imp: Actor = fx.imp(Vector2.ZERO, _broke())
	var other: Actor = fx.imp(Vector2(-200.0, 0.0), _broke())
	var ai: AIController = Fixture.ai(imp)
	fx.run(imp, 1)
	fx.combat.hit(other.id, imp, 1)
	fx.run(imp, 1)
	check(ai.target == other, "it turns on the imp that hurt it")
	other.free()
	fx.run(imp, 1)
	check(ai.target == fx.players[0], "and back to the wizard at once when that imp is gone")


## Possess (G9) hands an actor to another controller: the AI starts over when it drives again.
func test_the_ai_starts_over_when_it_drives_again() -> void:
	var imp: Actor = fx.imp_facing_player(60.0)
	var ai: AIController = Fixture.ai(imp)
	fx.run(imp, 2)
	check(ai.is_telegraphing(), "winding up")
	imp.drive(null)
	check(not ai.is_telegraphing() and ai.target == null, "put aside, it forgets its windup and target")
	fx.run(imp, 2)
	check(fx.projectiles.get_count() == 0 and not Fixture.look(imp).telegraph.visible, "with no controller the body casts nothing and shows no telegraph")
	imp.release()
	fx.run(imp, 1)
	check(ai.is_telegraphing() and ai.telegraph_progress() < 0.2, "back home, it winds up from the start")


## Regression (performance pass, 2026-10-28): an enemy hears its own hits on its actor, so a crowd
## adds no listener to the bus's per-hit events (each was called for every hit on anyone).
func test_a_crowd_of_enemies_adds_no_listener_to_the_hit_events() -> void:
	var before: int = fx.bus.damage_dealt.get_connections().size()
	var downed: int = fx.bus.player_downed.get_connections().size()
	for i in 5:
		fx.imp(Vector2(40.0 * float(i), 100.0))
	check_equal(fx.bus.damage_dealt.get_connections().size(), before, "no damage_dealt listener per enemy")
	check_equal(fx.bus.player_downed.get_connections().size(), downed, "no player_downed listener per enemy")
	var imp: Actor = fx.imp(Vector2.ZERO)
	fx.run(imp, 1)
	fx.combat.hit(fx.players[0].id, imp, 1)
	check(Fixture.look(imp).is_hurt(), "its look still shows a hit, heard on the actor")


func test_an_enemy_retargets_at_once_when_its_wizard_goes_down() -> void:
	fx.players[0].position = Vector2(300.0, 0.0)
	var imp: Actor = fx.imp(Vector2.ZERO, _broke())
	var ai: AIController = Fixture.ai(imp)
	fx.run(imp, 1)
	check(ai.target == fx.players[0], "it chases the wizard")
	var looks: int = ai.lookup_count
	fx.players[0].set_down(true)
	fx.run(imp, 1)
	check_equal(ai.lookup_count, looks + 1, "a downed target is dropped at the next step, without player_downed")
	check(ai.target != fx.players[0], "and no longer chased")
