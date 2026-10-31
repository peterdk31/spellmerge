extends "res://tests/support/suite.gd"
## The swarm's promotion (horde swarm S3, docs/milestones/horde-swarm.md, "Where a rule needs a
## full actor: promotion"), a swarmer's death dissolve and the look's flashes: a possession asked
## for a swarmer replaces it, at the next swarm step, by the full actor of its kind with the same
## actor id, Combat row (health, every status, barrier, push), place, name and parent, whatever
## kept its node keeping the actor (shots, sweeps, chains, status looks, the swarm's own target
## slots), its grudge, and the possession started; a swarmer dies with Feel's dissolve of its body
## as drawn; the look flashes every hit row, as Feel flashes every hit sprite.
##
## godot --headless --path . --script res://tests/gameplay/horde/test_swarm_promotion.gd

const Fixture := preload("res://tests/gameplay/horde/swarm_fixture.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

var _run: Fixture = null
var _feel: Node = null


func after_each() -> void:
	if _feel != null and is_instance_valid(_feel):
		root.remove_child(_feel)
		_feel.free()
	_feel = null
	if _run != null:
		_run.free_all()
	_run = null


func _make() -> Fixture:
	_run = Fixture.new(root)
	return _run


## A look on the fixture's swarm, stepped by hand.
func _look(run: Fixture) -> SwarmLook:
	var look := SwarmLook.new()
	look.real_time = false
	look.setup(run.swarm)
	run.swarm.look = look
	run.horde.add_child(look)
	return look


## A Feel on the fixture's bus (no camera shake, no engine stop), reading Combat's statuses.
func _feel_on(run: Fixture) -> Node:
	_feel = FeelScript.new()
	_feel.set(&"events", run.bus)
	_feel.set(&"combat", run.combat)
	_feel.set(&"projectiles", run.projectiles)
	_feel.set(&"actors", run.actors)
	_feel.set(&"drive_engine", false)
	_feel.set(&"preset", FeelPresetScript.new())
	root.add_child(_feel)
	return _feel


func test_a_possession_promotes_the_swarmer_with_everything_it_had() -> void:
	var run: Fixture = _make()
	var look: SwarmLook = _look(run)
	var wizard: Actor = run.wizard(Vector2(300.0, 0.0))
	var other: Node2D = run.swarmer(Vector2(-60.0, 0.0))
	var node: Node2D = run.swarmer(Vector2(20.0, 10.0))
	node.name = "Picked"
	var id: int = run.combat.actor_of(node)
	var at: Vector2 = node.position
	# Hurt, burnt, chilled twice, hexed, shocked, charged, pushed, then a barrier.
	run.combat.hit(wizard.id, node, 3.0, Vector2.RIGHT, 120.0)
	run.combat.apply_status(wizard.id, node, CombatScript.BURN, 2.0, 1.5)
	run.combat.apply_status(wizard.id, node, CombatScript.CHILL, 2.5, 30.0)
	run.combat.apply_status(wizard.id, node, CombatScript.CHILL, 2.5, 30.0)
	run.combat.apply_status(wizard.id, node, CombatScript.HEX, 3.0, 25.0)
	run.combat.apply_status(wizard.id, node, CombatScript.SHOCK, 1.5, 40.0)
	run.combat.apply_status(wizard.id, node, CombatScript.STATIC, 1.5, 50.0)
	run.combat.give_shield(node, 2, 4.0, 7)
	var before: Dictionary = run.combat.row_state(node)
	check(before["health"] < float(Fixture.MiteData.max_health), "the swarmer is hurt")
	check_equal((before["chill"] as Array)[2], 2, "and has two stacks of chill")
	check((before["knock"] as Vector2) != Vector2.ZERO, "and a push")
	var targets: int = run.projectiles.get_target_count()
	var listed: int = run.projectiles._target_id.find(node.get_instance_id())
	run.bus.possess_requested.emit(wizard.id, id, 5.0, 0)
	run.bus.possess_requested.emit(wizard.id, id, 5.0, 0)
	check_equal(run.swarm.count, 2, "nothing is promoted inside the hit that asked")
	run.swarm.step(Fixture.STEP)
	var actor := run.actors.node_of(id) as Actor
	check(actor != null, "the id belongs to a full actor now")
	if actor == null:
		return
	check(not is_instance_valid(node), "the bare node is freed")
	check_equal(run.swarm.promoted_count, 1, "promoted once for two requests")
	check_equal(run.swarm.count, 1, "its row is gone")
	check_equal(look.row_count(), 1, "and the look was told")
	check_equal(run.swarm.nodes[0], other, "the other swarmer keeps its row")
	check_equal(actor.id, id, "the same actor id")
	check_equal(run.combat.actor_of(actor), id, "the same Combat row")
	check(actor.scene_file_path == Fixture.MiteData.scene.resource_path, "the kind's own scene")
	check_equal(actor.data, Fixture.MiteData, "with its data")
	check_equal(actor.get_parent(), run.horde, "under the Horde node, so the director counts it")
	check_equal(String(actor.name), "Picked", "with the swarmer's name")
	check_equal(actor.position, at, "where the swarmer stood")
	check_equal(run.combat.row_state(actor), before, "health, statuses, barrier and push carried over")
	check_equal(run.combat.chill_stacks(actor), 2, "chill stacks too")
	check_equal(run.combat.shield(actor), 2, "and the barrier")
	check_equal(run.projectiles.get_target_count(), targets, "one target, not two")
	check_equal(run.projectiles._target_id.find(actor.get_instance_id()), listed, "in the swarmer's place among the targets")
	check_equal(run.projectiles.target_owner_of(actor), id, "owned by its id")
	check(actor.possessed_by != null and actor.controller == wizard.home_controller, "the wizard possesses it")
	check_equal(run.actors.team_of(id), ActorsScript.TEAM_WIZARDS, "on the wizard's team while it lasts")
	# It stays a full actor: Combat's hits go to its Health, and its death is an enemy's.
	var died: Array = []
	run.bus.enemy_died.connect(func(_killer: int, enemy: Node, _at: Vector2, _shot: int) -> void: died.append(enemy))
	for n in 3:
		# The first two take the barrier's charges.
		run.combat.hit(wizard.id, actor, 100.0)
	# (Its static charge went off on the other swarmer, an enemy of the wizard's team it is on now.)
	check(died.has(actor), "its death is an enemy's death")
	check(actor.is_dying(), "and it dies as an actor")


func test_whatever_kept_the_swarmer_keeps_the_actor() -> void:
	var run: Fixture = _make()
	var wizard: Actor = run.wizard(Vector2(300.0, 0.0))
	var feel: Node = _feel_on(run)
	var node: Node2D = run.swarmer(Vector2(0.0, 0.0))
	var old_id: int = node.get_instance_id()
	var id: int = run.combat.actor_of(node)
	run.combat.apply_status(wizard.id, node, CombatScript.BURN, 3.0, 1.0)
	check_equal(feel.call(&"status_shown", node), CombatScript.BURN, "Feel shows the swarmer's burn")
	# A shot homing on it, remembering it, sticking to it and skipping it; a chain that came from
	# it; a sweep that struck it.
	var manager: Fixture.ProjectileManagerScript = run.projectiles
	if run.spells._rec_prev.size() < 5:
		# Spells sizes its records with the first shot: a row to write in.
		run.spells._rec_prev.resize(8)
	if manager._cap < 4 or manager._mem_id.size() < 4:
		check(false, "the projectile manager and Spells have rows (cap %d, memory %d, records %d)" % [manager._cap, manager._mem_id.size(), run.spells._rec_prev.size()])
		return
	manager._home_target[0] = old_id
	manager._skip_id[1] = old_id
	manager._stuck_to[2] = node
	manager._mem_id[3] = old_id
	run.spells._rec_prev[4] = old_id
	var swing: CarrierSwing = CarrierSwing.of(run.spells)
	swing._sw_struck[0].append(node)
	swing._sw_prev[1] = old_id
	run.bus.possess_requested.emit(wizard.id, id, 2.0, 0)
	run.swarm.step(Fixture.STEP)
	var actor := run.actors.node_of(id) as Actor
	if actor == null:
		check(false, "promoted")
		return
	var new_id: int = actor.get_instance_id()
	check_equal(manager._home_target[0], new_id, "the homing shot homes on the actor")
	check_equal(manager._skip_id[1], new_id, "a payload skips the actor")
	check_equal(manager._stuck_to[2], actor, "a stuck shot rides the actor")
	check_equal(manager._mem_id[3], new_id, "a shot remembers it hit the actor")
	check_equal(run.spells._rec_prev[4], new_id, "a chain came from the actor")
	check(swing._sw_struck[0].has(actor) and not swing._sw_struck[0].has(null), "a sweep struck the actor")
	check_equal(swing._sw_prev[1], new_id, "and its chain came from it")
	check_equal(feel.call(&"status_shown", actor), CombatScript.BURN, "the burn shows on the actor")
	manager._stuck_to[2] = null


func test_a_promoted_swarmer_keeps_its_grudge() -> void:
	var run: Fixture = _make()
	run.wizard(Vector2(300.0, 0.0))
	var attacker: Node2D = run.swarmer(Vector2(-40.0, 0.0))
	var node: Node2D = run.swarmer(Vector2(40.0, 0.0))
	run.swarm.step(Fixture.STEP)
	run.combat.hit(run.combat.actor_of(attacker), node, 1.0)
	var row: int = run.swarm.row_of(node)
	check(run.swarm._grudge_left[row] > 0.0, "a teammate's hit gives the swarmer a grudge")
	var actor: Actor = run.swarm.promote(row)
	if actor == null:
		check(false, "promoted")
		return
	var ai: AIController = actor.home_controller as AIController
	check(ai != null and ai.grudge == attacker, "the actor's AI holds the grudge on the same swarmer")
	check(ai != null and is_equal_approx(ai.grudge_left(), AIController.GRUDGE_TIME), "for the time it had left")
	check_equal(actor.controller, ai, "its own AI drives it (no possession was asked)")


func test_a_swarmer_dies_with_the_dissolve_of_its_body_as_drawn() -> void:
	var run: Fixture = _make()
	var look: SwarmLook = _look(run)
	var feel: Node = _feel_on(run)
	run.wizard(Vector2(300.0, 0.0))
	var node: Node2D = run.swarmer(Vector2(30.0, 20.0))
	run.swarm.step(Fixture.STEP)
	var scene: Node = Fixture.MiteData.scene.instantiate()
	var sprite := scene.get_node(^"Sprite") as Sprite2D
	var hurt: Texture2D = (scene.get_node(^"CreatureLook") as CreatureLook).hurt_texture
	# Alive: the look gives Feel the swarmer as it is drawn.
	check(node.has_meta(FeelScript.SPRITE_GIVER), "the swarmer names its look to Feel")
	var shown: Sprite2D = look.sprite_of(node)
	check(shown != null and shown.texture == sprite.texture, "its body's texture")
	if shown != null:
		check_equal(shown.global_position, node.global_position + sprite.position, "where its Sprite would be")
		check_equal(shown.offset, sprite.offset + look.row_look(0)["lift"], "the hop in the offset, as CreatureLook puts it")
		check_equal(shown.scale, sprite.scale, "at rest scale")
		check_equal(shown.frame, sprite.frame, "its frame")
	var at: Vector2 = node.global_position
	run.combat.hit(-1, node, 100.0)
	check(not is_instance_valid(node) or node.is_queued_for_deletion(), "the swarmer died")
	check_equal(feel.call(&"live_ghosts"), 1, "Feel's death animation starts")
	var ghost: Sprite2D = feel.call(&"ghost", 0) as Sprite2D
	var strip: Texture2D = hurt if hurt != null else sprite.texture
	check(ghost.texture == strip, "from the body as drawn at its death (the hurt pose after the killing hit)")
	check_equal(ghost.global_position, at + sprite.position, "where the swarmer stood")
	scene.free()


func test_feel_reads_the_look_whichever_hears_the_death_first() -> void:
	var run: Fixture = _make()
	var look: SwarmLook = _look(run)
	run.wizard(Vector2(300.0, 0.0))
	var node: Node2D = run.swarmer(Vector2(0.0, 0.0))
	run.swarm.step(Fixture.STEP)
	# The swarm hears the death first (its row is gone): the look kept the dead row.
	look.on_row_died(0)
	var kept: Node2D = node
	run.swarm._drop(0)
	check(look.sprite_of(kept) != null, "the dead swarmer's sprite is still given")
	var stranger := Node2D.new()
	check(look.sprite_of(stranger) == null, "nothing for a node the look does not draw")
	stranger.free()


func test_the_look_flashes_every_hit_row() -> void:
	# No limit (owner, 2026-10-31): every hit row flashes, as Feel flashes every hit sprite.
	var run: Fixture = _make()
	var look: SwarmLook = _look(run)
	var many: int = 120
	for i in many:
		run.swarmer(Vector2(-240.0 + 4.0 * float(i), 0.0))
	run.swarm.step(Fixture.STEP)
	for row in many:
		look.on_hit(row)
	check_equal(look.flashing(), many, "all %d rows hit in one frame flash" % many)
	look.step_feel(0.01)
	var squashed: int = 0
	for row in many:
		if look.row_look(row)["scale"] != Vector2.ONE:
			squashed += 1
	check_equal(squashed, many, "and squash")
	look.step_feel(1.0)
	check_equal(look.flashing(), 0, "every flash ends")


func test_combat_s_next_step_promotes_before_it_checks_touches() -> void:
	var run: Fixture = _make()
	var wizard: Actor = run.wizard(Vector2(0.0, 0.0))
	# Standing on the wizard: a swarmer would hurt it by touch in Combat's step.
	var node: Node2D = run.swarmer(wizard.position)
	var id: int = run.combat.actor_of(node)
	run.bus.possess_requested.emit(wizard.id, id, 5.0, 0)
	var health: float = run.combat.health_of(wizard)
	run.combat.step(Fixture.STEP)
	var actor := run.actors.node_of(id) as Actor
	check(actor != null and actor.possessed_by != null, "Combat's step promoted it and the possession started")
	check_equal(run.combat.health_of(wizard), health, "the possessed actor, on the wizard's team, did not touch it")
