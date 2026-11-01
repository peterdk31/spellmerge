extends SceneTree
## Tests for gameplay/ai and the ember imp: chase, nearest-target targeting with up to four
## players, the telegraph before the attack, and the attack itself: the imp casts its staff
## (`fire · bolt`, staffs F9) through a real Spells with the real cards. Since actors G6 the imp is
## an actor (gameplay/actor) driven by its AIController; targets come from the projectile
## manager's target grid (another team's hurt circles). Time moves by fixed binary-fraction
## deltas; the test moves the body by its velocity like move_and_slide() would.
##
## godot --headless --path . --script res://tests/gameplay/ai/test_ai.gd

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ImpData := preload("res://content/enemies/ember_imp/ember_imp.tres")

const STEP: float = Fixture.STEP

var _failures: Array[String] = []
var _fx: Fixture = null


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	_test_imp_resource_and_scene()
	_test_chase_walks_toward_player()
	_test_chase_stops_without_players()
	_test_targets_nearest_of_four()
	_test_downed_player_is_skipped()
	_test_downed_event_retargets_at_once()
	_test_freed_player_is_dropped()
	_test_shot_hurts_wizard_through_combat()
	_test_shot_can_be_dodged_by_stepping_aside()
	_test_shot_and_telegraph_start_at_the_body()
	_test_shot_is_small_and_dodgeable()
	_test_no_lookups_while_nobody_stands()
	_test_recover_then_chase_again()
	_test_knockback_moves_the_enemy()
	_test_other_enemies_are_never_targets()
	_test_each_of_four_players_can_be_chased()
	_teardown()
	if _failures.is_empty():
		print("TEST OK: gameplay/ai (chase, telegraph, attack)")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _setup(player_count: int = 0) -> void:
	_teardown()
	_fx = Fixture.new(root, player_count)


func _teardown() -> void:
	if _fx != null:
		_fx.free_all()
	_fx = null


func _players() -> Array[Actor]:
	return _fx.players


func _imp(at: Vector2 = Vector2.ZERO) -> Actor:
	return _fx.imp(at)


func _ai(imp: Actor) -> AIController:
	return Fixture.ai(imp)


func _run(imp: Actor, count: int) -> void:
	_fx.run(imp, count)


## The imp's bolt card (its hit circle is the shot's).
func _bolt() -> FormBase:
	return _fx.registry.call("get_resource", &"spells", &"bolt") as FormBase


# --- Tests ------------------------------------------------------------------

func _test_imp_resource_and_scene() -> void:
	_check(ImpData.id == &"ember_imp" and ImpData.max_health > 0, "the imp resource has an id and health")
	_check(ImpData.move_speed > 0.0, "the imp walks")
	_check(ImpData.scene != null, "the imp resource points to its scene")
	var imp: Node = ImpData.scene.instantiate()
	_check(imp is Actor, "the scene root is an actor")
	_check(Fixture.ai(imp as Actor) != null and Fixture.look(imp as Actor) != null, "driven by its AIController, drawn by its CreatureLook")
	for kind: String in ["Health", "Hurtbox", "Contact", "Mover", "Caster"]:
		_check(imp.get_node_or_null(kind) != null, "the scene has its %s" % kind)
	_check(imp.get_node_or_null("Sprite") is Sprite2D and (imp.get_node("Sprite") as Sprite2D).texture != null, "the scene shows the part 4 sprite")
	_check(imp.get_node_or_null("Telegraph") is Sprite2D, "the scene has a telegraph, drawn by its shader")
	_check(is_equal_approx((imp.get_node("Hurtbox") as Hurtbox).radius, 11.0) and (imp.get_node("Hurtbox") as Hurtbox).offset == Vector2(0.0, -12.0), "its hurt circle is 11 px round the body")
	_check((imp as Actor).hand_offset == Vector2(0.0, -12.0) and (imp as Actor).staff_reach == 0.0, "its spells start at its body")
	imp.free()


func _test_chase_walks_toward_player() -> void:
	_setup(1)
	_players()[0].position = Vector2(300.0, 0.0)
	var imp := _imp()
	var start: float = imp.position.distance_to(_players()[0].position)
	_run(imp, 8)
	_check(_ai(imp).target == _players()[0], "the imp chases the one player")
	_check(imp.position.distance_to(_players()[0].position) < start, "it got closer")
	_check(is_equal_approx(imp.position.x, ImpData.move_speed * STEP * 8.0), "it walked at move_speed along x")
	_check(is_zero_approx(imp.position.y), "it walked straight")
	_check(_ai(imp).state == AIController.State.CHASE, "still chasing, not attacking, from afar")


func _test_chase_stops_without_players() -> void:
	_setup(0)
	var imp := _imp()
	_run(imp, 4)
	_check(imp.velocity == Vector2.ZERO and _ai(imp).target == null, "with no player the imp stands still")


func _test_targets_nearest_of_four() -> void:
	_setup(4)
	# All beyond its staff's range (enemy AI: it keeps the range its staffs give), so it walks.
	_players()[0].position = Vector2(1000.0, 0.0)
	_players()[1].position = Vector2(0.0, 800.0)
	_players()[2].position = Vector2(-400.0, 0.0)
	_players()[3].position = Vector2(0.0, -600.0)
	var imp := _imp()
	imp.step(STEP)
	_check(_ai(imp).target == _players()[2], "the nearest of four players is chased")
	_check(imp.velocity.x < 0.0, "it walks toward player 2 (left)")
	_players()[2].position = Vector2(900.0, 900.0)
	_run(imp, int(AIController.RETARGET_TIME / STEP) + 1)
	_check(_ai(imp).target == _players()[3], "after player 2 moves away it retargets the nearest, player 3")


func _test_downed_player_is_skipped() -> void:
	_setup(2)
	_players()[0].position = Vector2(100.0, 0.0)
	_players()[1].position = Vector2(400.0, 0.0)
	_players()[0].health.take(_players()[0].health.max_health)
	_check(_players()[0].is_downed(), "player 0 is downed")
	var imp := _imp()
	imp.step(STEP)
	_check(_ai(imp).target == _players()[1], "a downed player is not chased, the farther one is")


func _test_downed_event_retargets_at_once() -> void:
	_setup(2)
	_players()[0].position = Vector2(100.0, 0.0)
	_players()[1].position = Vector2(400.0, 0.0)
	var imp := _imp()
	imp.step(STEP)
	_check(_ai(imp).target == _players()[0], "starts on the near player")
	_players()[0].health.take(_players()[0].health.max_health)
	imp.step(STEP)
	_check(_ai(imp).target == _players()[1], "the imp leaves a downed player on the very next step")


func _test_freed_player_is_dropped() -> void:
	_setup(2)
	_players()[0].position = Vector2(100.0, 0.0)
	_players()[1].position = Vector2(400.0, 0.0)
	var imp := _imp()
	imp.step(STEP)
	var gone: Actor = _players()[0]
	_fx.players.remove_at(0)
	gone.free()
	imp.step(STEP)
	_check(_ai(imp).target == _players()[0], "a freed player is dropped without errors")


func _test_shot_hurts_wizard_through_combat() -> void:
	_setup(1)
	_players()[0].position = Vector2(60.0, 0.0)
	var imp := _imp()
	var damaged: Array = []
	_fx.bus.damage_dealt.connect(func(p: int, target: Node, amount: int, _at: Vector2) -> void:
		damaged.append([p, target, amount]))
	_run(imp, int(_ai(imp).windup_time / STEP) + 2)
	_run(imp, 6)
	_check(damaged.size() == 1 and damaged[0][0] == imp.id and damaged[0][1] == _players()[0], "the bolt hurt player 0 once, as the imp's actor")
	_check(damaged.size() == 1 and damaged[0][2] >= _bolt().base_damage, "for at least the bolt's damage")
	_check(damaged.size() == 1 and _players()[0].health.health == _players()[0].health.max_health - int(damaged[0][2]), "the wizard lost that health")


## Regression (#5): the shot and the telegraph start at the body (the hand, (0, -12)), not the
## feet.
func _test_shot_and_telegraph_start_at_the_body() -> void:
	_setup(0)
	var imp := _imp(Vector2(10.0, 20.0))
	imp.aim = Vector2.RIGHT
	imp.caster.cast(0)
	_check(_fx.projectiles.get_count() == 1, "the imp's cast spawns one shot")
	_check(_fx.projectiles.get_position_of(0) == Vector2(10.0, 20.0) + Vector2(0.0, -12.0), "the shot leaves from the body")
	var line: Node2D = imp.get_node("Telegraph") as Node2D
	_check(line.position == imp.hand_offset, "the scene's telegraph starts where the shot does")


func _test_shot_can_be_dodged_by_stepping_aside() -> void:
	# Control: the same shot does hit a player who stays put.
	_setup(1)
	_players()[0].position = Vector2(60.0, 0.0)
	var control := _imp()
	control.step(STEP)
	_run(control, int(_ai(control).windup_time / STEP) + 20)
	_check(_players()[0].health.health < _players()[0].health.max_health, "control: a player who stays on the line is hit")
	_setup(1)
	_players()[0].position = Vector2(60.0, 0.0)
	var imp := _imp()
	imp.step(STEP)
	_players()[0].position = Vector2(60.0, 40.0)
	_run(imp, int(_ai(imp).windup_time / STEP) + 20)
	_check(_players()[0].health.health == _players()[0].health.max_health, "a player who stepped aside during the telegraph is not hit")


## Enemy shots are small bullets (#4): a wizard (hit circle 8) is hit by the imp's bolt passing
## inside 8 + its radius (5: 13 px), and clears it with a 15 px sidestep.
func _test_shot_is_small_and_dodgeable() -> void:
	_setup(1)
	var reach: float = 8.0 + _bolt().radius
	for offset: float in [10.0, 15.0]:
		_setup(1)
		_players()[0].position = Vector2(60.0, 0.0)
		var imp := _imp()
		imp.step(STEP)
		_players()[0].position = Vector2(60.0, offset)
		_run(imp, int(_ai(imp).windup_time / STEP) + 20)
		var hit: bool = _players()[0].health.health < _players()[0].health.max_health
		_check(hit == (offset < reach), "a shot passing %.0f px from the wizard %s" % [offset, "hits" if offset < reach else "misses"])


func _test_no_lookups_while_nobody_stands() -> void:
	_setup(2)
	var imp := _imp()
	_players()[0].health.take(_players()[0].health.max_health)
	_players()[1].health.take(_players()[1].health.max_health)
	imp.step(STEP)
	var before: int = _ai(imp).lookup_count
	var steps: int = 160
	for i in steps:
		imp.step(STEP)
	var allowed: int = int(float(steps) * STEP / AIController.RETARGET_TIME) + 1
	_check(_ai(imp).target == null, "nobody stands, so there is no target")
	_check(_ai(imp).lookup_count - before <= allowed, "with no target the players are looked up only every RETARGET_TIME (%d lookups)" % (_ai(imp).lookup_count - before))


func _test_recover_then_chase_again() -> void:
	_setup(1)
	_players()[0].position = Vector2(60.0, 0.0)
	var imp := _imp()
	var ai: AIController = _ai(imp)
	_run(imp, int(ai.windup_time / STEP) + 2)
	_check(ai.state == AIController.State.RECOVER, "after the shot the imp recovers")
	_run(imp, int(ai.recover_time / STEP) + 1)
	_check(ai.state != AIController.State.RECOVER, "recovery ends")
	_run(imp, 1)
	_check(ai.state == AIController.State.WINDUP, "close to the player, it telegraphs the next attack")


func _test_knockback_moves_the_enemy() -> void:
	_setup(1)
	_players()[0].position = Vector2(500.0, 0.0)
	var imp := _imp()
	_fx.combat.hit(0, imp, 1, Vector2.LEFT, 100.0)
	imp.step(STEP)
	_check(imp.velocity.x < ImpData.move_speed, "knockback is added to the chase velocity")
	_check(_fx.combat.health_of(imp) == ImpData.max_health - 1, "the imp is registered in Combat with its health")


## Teams only aim: an imp never chases another enemy (an imp, a dummy), only another team.
func _test_other_enemies_are_never_targets() -> void:
	_setup(1)
	_players()[0].position = Vector2(600.0, 0.0)
	var imp := _imp()
	var other := _imp(Vector2(30.0, 0.0))
	imp.step(STEP)
	_check(_fx.actors.team_of(other.id) == ActorsScript.TEAM_ENEMIES, "the other imp is on the enemies' team")
	_check(_ai(imp).target == _players()[0], "the far wizard is chased, not the imp beside it")


func _test_each_of_four_players_can_be_chased() -> void:
	for chosen in 4:
		_setup(4)
		for index in 4:
			_players()[index].position = Vector2(2000.0, 2000.0)
		_players()[chosen].position = Vector2(100.0, 0.0)
		var imp := _imp()
		imp.step(STEP)
		_check(_ai(imp).target == _players()[chosen], "player %d is chased when nearest" % chosen)
