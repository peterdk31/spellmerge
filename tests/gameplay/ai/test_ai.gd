extends SceneTree
## Tests for gameplay/ai and the ember imp: chase, nearest-player targeting with
## up to four players, the telegraph before the attack, and the attack itself.
## Time moves by fixed binary-fraction deltas; the test moves the body by its
## velocity like move_and_slide() would.
##
## godot --headless --path . --script res://tests/gameplay/ai/test_ai.gd

const AiScript := preload("res://gameplay/ai/ai.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ImpData := preload("res://content/enemies/ember_imp/ember_imp.tres")

const STEP: float = 0.0625

var _failures: Array[String] = []
var _bus: Node
var _combat: Node
var _projectiles: Node
var _enemies: Array[AiScript] = []
var _players: Array[PlayerScript] = []


func _initialize() -> void:
	_test_imp_resource_and_scene()
	_test_chase_walks_toward_player()
	_test_chase_stops_without_players()
	_test_targets_nearest_of_four()
	_test_downed_player_is_skipped()
	_test_downed_event_retargets_at_once()
	_test_freed_player_is_dropped()
	_test_telegraph_comes_before_the_shot()
	_test_telegraph_standing_still_and_aim_locked()
	_test_shot_hurts_wizard_through_combat()
	_test_shot_can_be_dodged_by_stepping_aside()
	_test_no_lookups_while_nobody_stands()
	_test_telegraph_nodes_follow_the_windup()
	_test_recover_then_chase_again()
	_test_knockback_moves_the_enemy()
	_test_group_players_are_found()
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
	_bus = EventsScript.new()
	_projectiles = ProjectileManagerScript.new()
	_projectiles.events = _bus
	_combat = CombatScript.new()
	_combat.events = _bus
	_combat.projectiles = _projectiles
	_combat._ready()
	for index in player_count:
		var wizard := PlayerScript.new()
		wizard.index = index
		wizard.events = _bus
		# In the tree, or the projectile manager never sees the wizard as a target.
		root.add_child(wizard)
		wizard.position = Vector2(1000.0, 1000.0 * index)
		_players.append(wizard)
		_combat.register_player(index, wizard, 8.0)


func _teardown() -> void:
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.free()
	_enemies.clear()
	for wizard in _players:
		if is_instance_valid(wizard):
			wizard.free()
	_players.clear()
	for node: Node in [_combat, _projectiles, _bus]:
		if node != null:
			node.free()
	_combat = null
	_projectiles = null
	_bus = null


## An imp with the real numbers, aimed at `_players` (not the group).
func _imp(at: Vector2 = Vector2.ZERO) -> AiScript:
	var imp := AiScript.new()
	imp.data = ImpData
	imp.position = at
	imp.events = _bus
	imp.combat = _combat
	imp.projectiles = _projectiles
	for wizard in _players:
		imp.targets.append(wizard)
	imp._ready()
	_enemies.append(imp)
	return imp


## One physics frame: the AI, then the body moves, then Combat and projectiles.
func _run(imp: AiScript, count: int) -> void:
	for i in count:
		imp.step(STEP)
		imp.position += imp.velocity * STEP
		_combat.step(STEP)
		_projectiles.step(STEP)


# --- Tests ------------------------------------------------------------------

func _test_imp_resource_and_scene() -> void:
	_check(ImpData.id == &"ember_imp" and ImpData.max_health > 0, "the imp resource has an id and health")
	_check(ImpData.move_speed > 0.0, "the imp walks")
	_check(ImpData.scene != null, "the imp resource points to its scene")
	var imp: Node = ImpData.scene.instantiate()
	_check(imp is AiScript, "the scene root carries the AI script")
	_check(imp.get_node_or_null("Sprite") is Sprite2D and (imp.get_node("Sprite") as Sprite2D).texture != null, "the scene shows the part 4 sprite")
	_check(imp.get_node_or_null("Telegraph") is Line2D, "the scene has a telegraph line")
	imp.free()


func _test_chase_walks_toward_player() -> void:
	_setup(1)
	_players[0].position = Vector2(300.0, 0.0)
	var imp := _imp()
	var start: float = imp.position.distance_to(_players[0].position)
	_run(imp, 8)
	_check(imp.target == _players[0], "the imp chases the one player")
	_check(imp.position.distance_to(_players[0].position) < start, "it got closer")
	_check(is_equal_approx(imp.position.x, ImpData.move_speed * STEP * 8.0), "it walked at move_speed along x")
	_check(is_zero_approx(imp.position.y), "it walked straight")
	_check(imp.state == AiScript.State.CHASE, "still chasing, not attacking, from afar")


func _test_chase_stops_without_players() -> void:
	_setup(0)
	var imp := _imp()
	_run(imp, 4)
	_check(imp.velocity == Vector2.ZERO and imp.target == null, "with no player the imp stands still")


func _test_targets_nearest_of_four() -> void:
	_setup(4)
	_players[0].position = Vector2(500.0, 0.0)
	_players[1].position = Vector2(0.0, 400.0)
	_players[2].position = Vector2(-200.0, 0.0)
	_players[3].position = Vector2(0.0, -300.0)
	var imp := _imp()
	imp.step(STEP)
	_check(imp.target == _players[2], "the nearest of four players is chased")
	_check(imp.velocity.x < 0.0, "it walks toward player 2 (left)")
	_players[2].position = Vector2(900.0, 900.0)
	_run(imp, int(AiScript.RETARGET_TIME / STEP) + 1)
	_check(imp.target == _players[3], "after player 2 moves away it retargets the nearest, player 3")


func _test_downed_player_is_skipped() -> void:
	_setup(2)
	_players[0].position = Vector2(100.0, 0.0)
	_players[1].position = Vector2(400.0, 0.0)
	_players[0].take_damage(PlayerScript.MAX_HEALTH)
	_check(_players[0].is_downed(), "player 0 is downed")
	var imp := _imp()
	imp.step(STEP)
	_check(imp.target == _players[1], "a downed player is not chased, the farther one is")


func _test_downed_event_retargets_at_once() -> void:
	_setup(2)
	_players[0].position = Vector2(100.0, 0.0)
	_players[1].position = Vector2(400.0, 0.0)
	var imp := _imp()
	imp.step(STEP)
	_check(imp.target == _players[0], "starts on the near player")
	_players[0].take_damage(PlayerScript.MAX_HEALTH)
	imp.step(STEP)
	_check(imp.target == _players[1], "the imp leaves a downed player on the very next step")


func _test_freed_player_is_dropped() -> void:
	_setup(2)
	_players[0].position = Vector2(100.0, 0.0)
	_players[1].position = Vector2(400.0, 0.0)
	var imp := _imp()
	imp.step(STEP)
	var gone: PlayerScript = _players[0]
	_players.remove_at(0)
	gone.free()
	imp.step(STEP)
	_check(imp.target == _players[0], "a freed player is dropped without errors")


func _test_telegraph_comes_before_the_shot() -> void:
	_setup(1)
	_players[0].position = Vector2(80.0, 0.0)
	var imp := _imp()
	_check(not imp.is_telegraphing() and imp.telegraph_progress() == 0.0, "not telegraphing before it sees a player")
	imp.step(STEP)
	_check(imp.is_telegraphing(), "in range, the windup (telegraph) starts")
	_check(_projectiles.get_count() == 0, "no shot yet at the start of the telegraph")
	var steps: int = int(imp.windup_time / STEP)
	_run(imp, steps - 2)
	_check(imp.is_telegraphing() and _projectiles.get_count() == 0, "still telegraphing, still no damage, just before the end")
	_check(imp.telegraph_progress() > 0.8 and imp.telegraph_progress() < 1.0, "progress is near the end")
	_run(imp, 2)
	_check(not imp.is_telegraphing(), "the telegraph ended")
	_check(_projectiles.get_count() == 1, "exactly one shot left when the telegraph ended")


func _test_telegraph_standing_still_and_aim_locked() -> void:
	_setup(1)
	_players[0].position = Vector2(60.0, 0.0)
	var imp := _imp()
	imp.step(STEP)
	_check(imp.is_telegraphing() and imp.aim.is_equal_approx(Vector2.RIGHT), "aim points at the player")
	var at: Vector2 = imp.position
	_players[0].position = Vector2(0.0, 60.0)
	_run(imp, 4)
	_check(imp.position == at and imp.velocity == Vector2.ZERO, "the imp stands still while telegraphing")
	_check(imp.aim.is_equal_approx(Vector2.RIGHT), "the aim stays locked on where the player was")


func _test_shot_hurts_wizard_through_combat() -> void:
	_setup(1)
	_players[0].position = Vector2(60.0, 0.0)
	var imp := _imp()
	var damaged: Array = []
	_bus.damage_dealt.connect(func(p: int, target: Node, amount: int, _at: Vector2) -> void:
		damaged.append([p, target, amount]))
	_run(imp, int(imp.windup_time / STEP) + 2)
	_run(imp, 16)
	_check(damaged == [[EventsScript.NO_PLAYER, _players[0], imp.attack_damage]], "the shot hurt player 0 once, as an enemy (NO_PLAYER)")
	_check(_players[0].health == PlayerScript.MAX_HEALTH - imp.attack_damage, "the wizard lost attack_damage health")


func _test_shot_can_be_dodged_by_stepping_aside() -> void:
	# Control: the same shot does hit a player who stays put.
	_setup(1)
	_players[0].position = Vector2(60.0, 0.0)
	var control := _imp()
	control.step(STEP)
	_run(control, int(control.windup_time / STEP) + 20)
	_check(_players[0].health < PlayerScript.MAX_HEALTH, "control: a player who stays on the line is hit")
	_setup(1)
	_players[0].position = Vector2(60.0, 0.0)
	var imp := _imp()
	imp.step(STEP)
	_players[0].position = Vector2(60.0, 40.0)
	_run(imp, int(imp.windup_time / STEP) + 20)
	_check(_players[0].health == PlayerScript.MAX_HEALTH, "a player who stepped aside during the telegraph is not hit")


func _test_no_lookups_while_nobody_stands() -> void:
	_setup(2)
	var imp := _imp()
	imp.targets.clear()
	_players[0].take_damage(PlayerScript.MAX_HEALTH)
	_players[1].take_damage(PlayerScript.MAX_HEALTH)
	imp.step(STEP)
	var before: int = imp.lookup_count
	var steps: int = 160
	for i in steps:
		imp.step(STEP)
	var allowed: int = int(float(steps) * STEP / AiScript.RETARGET_TIME) + 1
	_check(imp.target == null, "nobody stands, so there is no target")
	_check(imp.lookup_count - before <= allowed, "with no target the players are looked up only every RETARGET_TIME (%d lookups)" % (imp.lookup_count - before))


func _test_telegraph_nodes_follow_the_windup() -> void:
	_setup(1)
	_players[0].position = Vector2(0.0, 80.0)
	var imp: AiScript = ImpData.scene.instantiate()
	imp.data = ImpData
	imp.events = _bus
	imp.combat = _combat
	imp.projectiles = _projectiles
	imp.targets.append(_players[0])
	imp._ready()
	_enemies.append(imp)
	var line: Line2D = imp.get_node("Telegraph")
	var sprite: Sprite2D = imp.get_node("Sprite")
	var reach: float = imp.attack_speed * imp.attack_lifetime
	_check(is_equal_approx(line.get_point_position(1).x, reach), "the telegraph line is as long as the shot flies")
	_check(not line.visible, "the telegraph is hidden before the windup")
	imp.step(STEP)
	_check(line.visible and is_equal_approx(line.rotation, imp.aim.angle()), "the telegraph shows, turned toward the locked aim")
	_check(sprite.modulate != Color.WHITE, "the sprite flashes during the windup")
	var early_width: float = line.width
	var early_alpha: float = line.modulate.a
	_run(imp, int(imp.windup_time / STEP) - 4)
	_check(line.width > early_width and line.modulate.a > early_alpha, "the telegraph grows wider and brighter with progress")
	_run(imp, 4)
	_check(not line.visible and sprite.modulate == Color.WHITE, "after the shot the telegraph is hidden and the sprite is white again")


func _test_recover_then_chase_again() -> void:
	_setup(1)
	_players[0].position = Vector2(60.0, 0.0)
	var imp := _imp()
	_run(imp, int(imp.windup_time / STEP) + 2)
	_check(imp.state == AiScript.State.RECOVER, "after the shot the imp recovers")
	_run(imp, int(imp.recover_time / STEP) + 1)
	_check(imp.state != AiScript.State.RECOVER, "recovery ends")
	_run(imp, 1)
	_check(imp.state == AiScript.State.WINDUP, "close to the player, it telegraphs the next attack")


func _test_knockback_moves_the_enemy() -> void:
	_setup(1)
	_players[0].position = Vector2(500.0, 0.0)
	var imp := _imp()
	_combat.hit(0, imp, 1, Vector2.LEFT, 100.0)
	imp.step(STEP)
	_check(imp.velocity.x < ImpData.move_speed, "knockback is added to the chase velocity")
	_check(_combat.get_health(imp) == ImpData.max_health - 1, "the imp is registered in Combat with its health")


func _test_group_players_are_found() -> void:
	_setup(0)
	var wizard := PlayerScript.new()
	wizard.index = 3
	wizard.events = _bus
	root.add_child(wizard)
	wizard.position = Vector2(200.0, 0.0)
	var imp := AiScript.new()
	imp.data = ImpData
	imp.events = _bus
	imp.combat = _combat
	imp.projectiles = _projectiles
	root.add_child(imp)
	_enemies.append(imp)
	imp.step(STEP)
	_check(imp.target == wizard, "with no explicit targets the players group is used (player 3)")
	_check(wizard.is_in_group(&"players"), "a wizard puts itself in the players group")
	root.remove_child(wizard)
	root.remove_child(imp)
	wizard.free()


func _test_each_of_four_players_can_be_chased() -> void:
	for chosen in 4:
		_setup(4)
		for index in 4:
			_players[index].position = Vector2(2000.0, 2000.0)
		_players[chosen].position = Vector2(100.0, 0.0)
		var imp := _imp()
		imp.step(STEP)
		_check(imp.target == _players[chosen], "player %d is chased when nearest" % chosen)
