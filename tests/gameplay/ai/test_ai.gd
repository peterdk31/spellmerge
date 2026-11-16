extends "res://tests/support/suite.gd"
## gameplay/ai and the ember imp: the imp's data and scene, the chase, nearest-target targeting
## with up to four players, and the attack itself: the imp casts its staff (`fire · bolt`, staffs
## F9) through a real Spells with the real cards. Since actors G6 the imp is an actor
## (gameplay/actor) driven by its AIController; targets come from the projectile manager's target
## grid (another team's hurt circles). Each test builds its own small world (ai_fixture.gd: its own
## bus, actors, projectiles, Spells and Combat, wizards and imps stepped by hand), with as many
## wizards as it needs; time moves by fixed binary-fraction steps and the fixture moves the body by
## its velocity (without walls). The telegraph and the step aside are test_ai_telegraph.gd's.

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ImpData := preload("res://content/enemies/ember_imp/ember_imp.tres")

const STEP: float = Fixture.STEP

var fx: Fixture = null


func after_each() -> void:
	if fx != null:
		fx.free_all()
	fx = null


## A world of `player_count` wizards.
func _world(player_count: int) -> Fixture:
	fx = Fixture.new(root, player_count)
	return fx


func _players() -> Array[Actor]:
	return fx.players


func _ai(imp: Actor) -> AIController:
	return Fixture.ai(imp)


## The imp's bolt card (its hit circle is the shot's).
func _bolt() -> CarrierCard:
	return fx.registry.call("get_resource", &"spells", &"bolt") as CarrierCard


## A new imp of the real scene, not in the tree, freed after the test.
func _scene_imp() -> Actor:
	return own(ImpData.scene.instantiate()) as Actor


# --- The imp's data and scene ---------------------------------------------------------------

func test_the_imp_resource_has_an_id_health_a_walk_and_a_scene() -> void:
	check_equal(ImpData.id, &"ember_imp", "the imp's id")
	check(ImpData.max_health > 0, "the imp has health")
	check(ImpData.move_speed > 0.0, "the imp walks")
	check(ImpData.scene != null, "the imp resource points to its scene")


func test_the_imp_scene_is_an_actor_driven_by_its_ai_and_drawn_by_its_look() -> void:
	var imp: Actor = _scene_imp()
	check(imp != null, "the scene root is an actor")
	check(Fixture.ai(imp) != null, "driven by its AIController")
	check(Fixture.look(imp) != null, "drawn by its CreatureLook")


func test_the_imp_scene_has_every_actor_component() -> void:
	var imp: Actor = _scene_imp()
	for kind: String in ["Health", "Hurtbox", "Contact", "Mover", "Caster"]:
		check(imp.get_node_or_null(kind) != null, "the scene has its %s" % kind)


func test_the_imp_scene_shows_a_sprite() -> void:
	var imp: Actor = _scene_imp()
	var sprite: Sprite2D = imp.get_node_or_null("Sprite") as Sprite2D
	check(sprite != null and sprite.texture != null, "the scene shows the part 4 sprite")


func test_the_imp_scene_has_no_telegraph_node() -> void:
	# Its lane is Feel's, the card's wind cue (docs/milestones/cast-timing.md, T6b).
	check(_scene_imp().get_node_or_null("Telegraph") == null, "the scene has no telegraph node")


func test_the_imps_spells_start_at_its_hurt_circle() -> void:
	var imp: Actor = _scene_imp()
	var hurtbox: Hurtbox = imp.get_node("Hurtbox") as Hurtbox
	check(hurtbox.radius > 0.0, "it has a hurt circle")
	check_equal(imp.hand_offset, hurtbox.offset, "its hand is the centre of its hurt circle, on its body")
	check_equal(imp.staff_reach, 0.0, "its spells start at its body, not at a staff's tip")


## Regression (#5): the shot starts at the body (the hand, (0, -12)), not the feet.
func test_its_shot_leaves_from_its_body_not_its_feet() -> void:
	_world(0)
	var imp: Actor = fx.imp(Vector2(10.0, 20.0))
	imp.aim = Vector2.RIGHT
	imp.caster.cast(0)
	# Its staff winds up first (docs/milestones/cast-timing.md): the shot leaves when that is over.
	var guard: int = 0
	while fx.projectiles.get_count() == 0 and guard < 120:
		fx.run(imp, 1)
		guard += 1
	check_equal(fx.projectiles.get_count(), 1, "the imp's cast spawns one shot")
	var from: Vector2 = Vector2(10.0, 20.0) + imp.hand_offset
	var at: Vector2 = fx.projectiles.get_position_of(0)
	check(is_equal_approx(at.y, from.y) and at.x >= from.x and at.x <= from.x + _bolt().speed * STEP * 3.0, "the shot leaves from the body (%s, from %s)" % [at, from])


# --- The chase -------------------------------------------------------------------------------

func test_it_chases_the_one_player_closer() -> void:
	_world(1)
	_players()[0].position = Vector2(300.0, 0.0)
	var imp: Actor = fx.imp()
	var start: float = imp.position.distance_to(_players()[0].position)
	fx.run(imp, 8)
	check(_ai(imp).target == _players()[0], "the imp chases the one player")
	check(imp.position.distance_to(_players()[0].position) < start, "it got closer")


func test_it_walks_straight_at_its_move_speed() -> void:
	_world(1)
	_players()[0].position = Vector2(300.0, 0.0)
	var imp: Actor = fx.imp()
	fx.run(imp, 8)
	check(is_equal_approx(imp.position.x, ImpData.move_speed * STEP * 8.0), "it walked at move_speed along x")
	check(is_zero_approx(imp.position.y), "it walked straight")


func test_from_afar_it_chases_without_attacking() -> void:
	_world(1)
	_players()[0].position = Vector2(300.0, 0.0)
	var imp: Actor = fx.imp()
	fx.run(imp, 8)
	check_equal(_ai(imp).state, AIController.State.CHASE, "still chasing, not attacking, from afar")


func test_with_no_player_it_stands_still() -> void:
	_world(0)
	var imp: Actor = fx.imp()
	fx.run(imp, 4)
	check_equal(imp.velocity, Vector2.ZERO, "with no player the imp stands still")
	check(_ai(imp).target == null, "with no player there is no target")


func test_knockback_is_added_to_the_chase() -> void:
	_world(1)
	_players()[0].position = Vector2(500.0, 0.0)
	var imp: Actor = fx.imp()
	fx.combat.hit(0, imp, 1, Vector2.LEFT, 100.0)
	imp.step(STEP)
	check(imp.velocity.x < ImpData.move_speed, "knockback is added to the chase velocity")


func test_the_imp_is_registered_in_combat_with_its_health() -> void:
	_world(1)
	_players()[0].position = Vector2(500.0, 0.0)
	var imp: Actor = fx.imp()
	fx.combat.hit(0, imp, 1, Vector2.LEFT, 100.0)
	check_equal(fx.combat.health_of(imp), ImpData.max_health - 1, "Combat keeps the imp's health")


# --- Targets ---------------------------------------------------------------------------------

## Four wizards all beyond its staff's range (enemy AI: it keeps the range its staffs give), so
## it walks.
func _four_far() -> void:
	_world(4)
	_players()[0].position = Vector2(1000.0, 0.0)
	_players()[1].position = Vector2(0.0, 800.0)
	_players()[2].position = Vector2(-400.0, 0.0)
	_players()[3].position = Vector2(0.0, -600.0)


func test_it_walks_toward_the_nearest_of_four() -> void:
	_four_far()
	var imp: Actor = fx.imp()
	imp.step(STEP)
	check(_ai(imp).target == _players()[2], "the nearest of four players is chased")
	check(imp.velocity.x < 0.0, "it walks toward player 2 (left)")


func test_it_retargets_the_nearest_after_its_target_moves_away() -> void:
	_four_far()
	var imp: Actor = fx.imp()
	imp.step(STEP)
	_players()[2].position = Vector2(900.0, 900.0)
	fx.run(imp, int(AIController.RETARGET_TIME / STEP) + 1)
	check(_ai(imp).target == _players()[3], "after player 2 moves away it retargets the nearest, player 3")


## It looks in rings, nearest first (`AIBrain.LOOKS`, enemy AI L1): the nearest of all is found
## wherever it stands, also just past a ring's edge with a farther one inside the next ring.
func test_it_finds_the_nearest_in_every_ring() -> void:
	_world(3)
	var cases: Array[Array] = [
		# Where the three players stand, and which is nearest.
		[Vector2(1800.0, 0.0), Vector2(0.0, 2000.0), Vector2(-1900.0, 0.0), 0],
		[Vector2(1800.0, 0.0), Vector2(0.0, 470.0), Vector2(-490.0, 0.0), 1],
		[Vector2(165.0, 0.0), Vector2(0.0, 185.0), Vector2(-300.0, 0.0), 0],
		[Vector2(485.0, 0.0), Vector2(0.0, -150.0), Vector2(-200.0, 0.0), 1],
	]
	for row: Array in cases:
		for index in 3:
			_players()[index].position = row[index]
		fx.projectiles.step(STEP)
		var imp: Actor = fx.imp()
		imp.step(STEP)
		check(_ai(imp).target == _players()[row[3]], "the nearest player (%d) is chased with players at %s" % [row[3], row.slice(0, 3)])
		fx.enemies.erase(imp)
		imp.free()


func test_each_of_four_players_is_chased_when_nearest() -> void:
	for chosen in 4:
		_world(4)
		for index in 4:
			_players()[index].position = Vector2(2000.0, 2000.0)
		_players()[chosen].position = Vector2(100.0, 0.0)
		var imp: Actor = fx.imp()
		imp.step(STEP)
		check(_ai(imp).target == _players()[chosen], "player %d is chased when nearest" % chosen)
		fx.free_all()


## Two wizards: player 0 near, player 1 farther.
func _near_and_far() -> void:
	_world(2)
	_players()[0].position = Vector2(100.0, 0.0)
	_players()[1].position = Vector2(400.0, 0.0)


func test_a_downed_player_is_skipped_for_a_farther_one() -> void:
	_near_and_far()
	_players()[0].health.take(_players()[0].health.max_health)
	check(_players()[0].is_downed(), "player 0 is downed")
	var imp: Actor = fx.imp()
	imp.step(STEP)
	check(_ai(imp).target == _players()[1], "a downed player is not chased, the farther one is")


func test_it_turns_to_the_other_player_the_step_its_target_goes_down() -> void:
	_near_and_far()
	var imp: Actor = fx.imp()
	imp.step(STEP)
	check(_ai(imp).target == _players()[0], "starts on the near player")
	_players()[0].health.take(_players()[0].health.max_health)
	imp.step(STEP)
	check(_ai(imp).target == _players()[1], "the imp leaves a downed player on the very next step")


func test_a_freed_player_is_dropped() -> void:
	_near_and_far()
	var imp: Actor = fx.imp()
	imp.step(STEP)
	var gone: Actor = _players()[0]
	fx.players.remove_at(0)
	gone.free()
	imp.step(STEP)
	check(_ai(imp).target == _players()[0], "a freed player is dropped without errors")


## Teams only aim: an imp never chases another enemy (an imp, a dummy), only another team.
func test_another_enemy_beside_it_is_never_its_target() -> void:
	_world(1)
	_players()[0].position = Vector2(600.0, 0.0)
	var imp: Actor = fx.imp()
	var other: Actor = fx.imp(Vector2(30.0, 0.0))
	imp.step(STEP)
	check_equal(fx.actors.team_of(other.id), ActorsScript.TEAM_ENEMIES, "the other imp is on the enemies' team")
	check(_ai(imp).target == _players()[0], "the far wizard is chased, not the imp beside it")


func test_with_nobody_standing_it_looks_only_every_retarget_time() -> void:
	_world(2)
	var imp: Actor = fx.imp()
	_players()[0].health.take(_players()[0].health.max_health)
	_players()[1].health.take(_players()[1].health.max_health)
	imp.step(STEP)
	var before: int = _ai(imp).lookup_count
	var steps: int = 160
	for i in steps:
		imp.step(STEP)
	var allowed: int = int(float(steps) * STEP / AIController.RETARGET_TIME) + 1
	check(_ai(imp).target == null, "nobody stands, so there is no target")
	check(_ai(imp).lookup_count - before <= allowed, "with no target the players are looked up only every RETARGET_TIME (%d lookups)" % (_ai(imp).lookup_count - before))


# --- The attack ------------------------------------------------------------------------------

## An imp 60 px from the one wizard, run until its first shot has landed; the damage_dealt events
## heard, each [actor id, target, amount]. The imp is `fx.enemies[0]`.
func _first_shot() -> Array:
	_world(1)
	_players()[0].position = Vector2(60.0, 0.0)
	var imp: Actor = fx.imp()
	var damaged: Array = []
	fx.bus.damage_dealt.connect(func(by: int, target: Node, amount: int, _at: Vector2) -> void:
		damaged.append([by, target, amount]))
	fx.run(imp, int(_ai(imp).windup_time / STEP) + 2)
	fx.run(imp, 6)
	return damaged


func test_its_bolt_hurts_the_wizard_once_as_the_imps_actor() -> void:
	var damaged: Array = _first_shot()
	check_equal(damaged.size(), 1, "one hit")
	if damaged.size() == 1:
		check_equal(damaged[0][0], fx.enemies[0].id, "the hit is the imp's actor's")
		check(damaged[0][1] == _players()[0], "the hit is on player 0")


func test_its_bolt_deals_at_least_the_bolts_damage() -> void:
	var damaged: Array = _first_shot()
	check(damaged.size() == 1 and int(damaged[0][2]) >= _bolt().base_damage, "for at least the bolt's damage")


func test_the_wizard_loses_the_damage_dealt() -> void:
	var damaged: Array = _first_shot()
	check(damaged.size() == 1 and _players()[0].health.health == _players()[0].health.max_health - int(damaged[0][2]), "the wizard lost that health")


## Enemy shots are small bullets (#4): a wizard (hit circle 8) is hit by the imp's bolt passing
## inside 8 + its radius, and clears it with a 15 px sidestep. Whether the shot that left passes
## `offset` px from the wizard hits.
func _hit_passing_at(offset: float) -> bool:
	_world(1)
	_players()[0].position = Vector2(60.0, 0.0)
	var imp: Actor = fx.imp()
	imp.step(STEP)
	fx.run(imp, int(_ai(imp).windup_time / STEP) + 1)
	_players()[0].position = Vector2(60.0, offset)
	fx.run(imp, 20)
	return _players()[0].health.health < _players()[0].health.max_health


func test_a_shot_passing_inside_both_hit_circles_hits() -> void:
	check(_hit_passing_at(10.0), "a shot passing 10 px from the wizard hits")
	check(10.0 < 8.0 + _bolt().radius, "10 px is inside the wizard's circle and the bolt's")


func test_a_15_px_sidestep_clears_the_shot() -> void:
	check(not _hit_passing_at(15.0), "a shot passing 15 px from the wizard misses")


## An imp 60 px from the one wizard, run until its first shot has left.
func _after_a_shot() -> AIController:
	_world(1)
	_players()[0].position = Vector2(60.0, 0.0)
	var imp: Actor = fx.imp()
	fx.run(imp, int(_ai(imp).windup_time / STEP) + 2)
	return _ai(imp)


func test_after_a_shot_it_recovers() -> void:
	check_equal(_after_a_shot().state, AIController.State.RECOVER, "after the shot the imp recovers")


func test_after_recovering_close_by_it_winds_up_again() -> void:
	var ai: AIController = _after_a_shot()
	var imp: Actor = fx.enemies[0]
	fx.run(imp, int(ai.recover_time / STEP) + 1)
	check(ai.state != AIController.State.RECOVER, "recovery ends")
	fx.run(imp, 1)
	check_equal(ai.state, AIController.State.WINDUP, "close to the player, it telegraphs the next attack")
