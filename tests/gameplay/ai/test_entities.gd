extends "res://tests/support/suite.gd"
## The entity kit (staffs B5, gameplay/ai/entities.gd and its use in ai.gd): decoys (actors that
## aim themselves) that enemies chase when nearest and shoot down, familiars that circle their
## wizard (they cast nothing themselves: core/spells fires their triggers, rules R4 F3), the
## per-player cap, ending by tag, quiet clears, swap moves, and four players at once. Each test
## builds its own small world (ai_fixture.gd, with as many wizards as it needs) and an Entities on
## it, in the tree so the decoys are projectile targets at their real positions; `after_each` frees
## both. Time moves by fixed binary-fraction steps. Enemies' own decoys and familiars are
## test_ai_entities.gd's.

const AiFixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const EntitiesScript := preload("res://gameplay/ai/entities.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

const STEP: float = 0.0625
const TAG: int = 1 << 20

var world: AiFixture = null
var entities: EntitiesScript = null
## Every entity_ended as [caster, kind, position, tag] (the owner's actor id; the fixture's
## wizards are the actors 0-3, seated 0-3).
var ended: Array[Array] = []


func after_each() -> void:
	if entities != null and is_instance_valid(entities):
		entities.free()
	entities = null
	if world != null:
		world.free_all()
	world = null
	ended.clear()


## A world of `player_count` wizards and Entities on it.
func _setup(player_count: int = 1) -> void:
	world = AiFixture.new(root, player_count)
	entities = EntitiesScript.new()
	entities.events = world.bus
	entities.projectiles = world.projectiles
	entities.spells = world.spells
	entities.actors = world.actors
	entities.combat = world.combat
	# In the tree, so the decoys are projectile targets at their real positions.
	root.add_child(entities)
	world.bus.entity_ended.connect(func(player: int, kind: StringName, at: Vector2, tag: int) -> void:
		ended.append([player, kind, at, tag]))


## An imp of the fixture (an actor) whose AI asks these Entities for decoys.
func _imp(at: Vector2) -> Actor:
	world.entities = entities
	return world.imp(at)


func _spawn(caster: int, kind: StringName, at: Vector2, seconds: float = 5.0, tag: int = TAG) -> void:
	world.bus.entity_spawn_requested.emit(caster, kind, at, seconds, tag, -1)


## `count` physics frames of the whole world: every imp, Combat, the projectiles, Spells (the
## imps cast their staffs), the entities.
func _run(count: int) -> void:
	for i in count:
		for enemy in world.enemies:
			if is_instance_valid(enemy):
				enemy.step(STEP)
				enemy.position += enemy.velocity * STEP
		world.combat.step(STEP)
		world.projectiles.step(STEP)
		world.spells.call("step", STEP)
		entities.step(STEP)


## The first wizard's decoy at the origin, its wizard far off; null (a failure) if none was made.
func _decoy() -> Actor:
	_setup(1)
	world.players[0].position = Vector2(-400.0, 0.0)
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO)
	var decoy: Actor = entities.decoy_of(0)
	check(decoy != null, "a decoy is made")
	return decoy


# --- Decoys as targets -----------------------------------------------------------------------

## No lure (owner, 2026-11-02): a decoy is an actor of its owner's team, chased when it is the
## nearest, as any.
func test_an_imp_nearer_the_decoy_chases_the_decoy() -> void:
	_setup(1)
	world.players[0].position = Vector2(60.0, 0.0)
	_spawn(0, EntitiesScript.DECOY, Vector2(-30.0, 0.0))
	var imp: Actor = _imp(Vector2.ZERO)
	_run(1)
	check(AiFixture.ai(imp).target == entities.decoy_of(0), "an imp nearer the decoy chases the decoy")
	check(imp.aim.x < 0.0, "it turns on the decoy")


func test_a_nearer_wizard_is_chased_before_a_decoy_farther_off() -> void:
	_setup(1)
	world.players[0].position = Vector2(60.0, 0.0)
	_spawn(0, EntitiesScript.DECOY, Vector2(-150.0, 0.0))
	var imp: Actor = _imp(Vector2(10.0, 0.0))
	_run(1)
	check(AiFixture.ai(imp).target == world.players[0], "a nearer wizard is chased before a decoy farther off")


func test_a_decoy_is_an_unseated_actor_of_its_owners_team() -> void:
	var decoy: Actor = _decoy()
	if decoy == null:
		return
	check(decoy.is_inside_tree(), "a decoy is an actor in the world")
	check(decoy.home_controller is DecoyController, "driven by its own controller")
	check_equal(world.actors.team_of(decoy.id), world.actors.team_of(0), "on its owner's team")
	check_equal(world.actors.seat_of(decoy.id), -1, "no seat drives it")


## The decoy aims itself at the nearest actor of another team, and turns when another comes nearer.
func test_a_decoy_aims_at_the_nearest_foe() -> void:
	var decoy: Actor = _decoy()
	if decoy == null:
		return
	_imp(Vector2(0.0, 120.0))
	_run(1)
	check(decoy.aim.dot(Vector2.DOWN) > 0.99, "it aims at the imp below it (%s)" % decoy.aim)


func test_a_decoy_turns_to_a_nearer_foe_once_it_looks_again() -> void:
	var decoy: Actor = _decoy()
	if decoy == null:
		return
	_imp(Vector2(0.0, 120.0))
	_run(1)
	_imp(Vector2(-60.0, 0.0))
	_run(int(AIBrain.RETARGET_TIME / STEP) + 1)
	check(decoy.aim.dot(Vector2.LEFT) > 0.99, "it aims at a nearer one once it looks again (%s)" % decoy.aim)


func test_a_decoy_whose_card_does_not_home_stands() -> void:
	var decoy: Actor = _decoy()
	if decoy == null:
		return
	_imp(Vector2(0.0, 120.0))
	_run(int(AIBrain.RETARGET_TIME / STEP) + 2)
	check(decoy.global_position.is_equal_approx(Vector2.ZERO), "the decoy stands where it was put")


# --- Decoys break ----------------------------------------------------------------------------

## A decoy 80 px from an imp, its wizard far off, shot at for 30 seconds; the decoy and the imp.
func _shot_down() -> Array[Actor]:
	_setup(1)
	world.players[0].position = Vector2(5000.0, 0.0)
	_spawn(0, EntitiesScript.DECOY, Vector2(80.0, 0.0), 60.0)
	var decoy: Actor = entities.decoy_of(0)
	var imp: Actor = _imp(Vector2.ZERO)
	_run(int(30.0 / STEP))
	return [decoy, imp]


func test_enemy_shots_break_a_decoy_once() -> void:
	_shot_down()
	check_equal(ended.size(), 1, "the decoy breaks once after enemy shots")
	check_equal(entities.count(), 0, "the broken decoy is gone")


func test_a_decoy_broken_by_shots_ends_naming_its_owner_kind_tag_and_place() -> void:
	var decoy: Actor = _shot_down()[0]
	check_equal(ended.size(), 1, "one end")
	if ended.size() != 1:
		return
	check(ended[0][0] == 0 and ended[0][1] == EntitiesScript.DECOY and ended[0][3] == TAG, "entity_ended names the player, the kind and the tag")
	# A body like any: the hits push it (its Mover), so it ends where the last one left it.
	check(decoy != null and (ended[0][2] as Vector2).is_equal_approx(decoy.global_position), "a decoy ends where it stood when it broke (%s)" % ended[0][2])


func test_the_imp_goes_back_to_the_wizard_once_the_decoy_breaks() -> void:
	var imp: Actor = _shot_down()[1]
	_run(2)
	check(AiFixture.ai(imp).target == world.players[0], "the imp goes back to the wizard once the decoy breaks")


## It belongs to its owner: the owner's shots pass it (its hurt circle is the owner's target), every
## other actor's hurt it (actors G3c).
func test_a_decoys_hurt_circle_is_its_owners() -> void:
	_setup(2)
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO)
	var decoy: Actor = entities.decoy_of(0)
	check(decoy != null and world.projectiles.target_owner_of(decoy) == 0, "its hurt circle is owned by its owner, whose shots pass it")


func test_combat_knows_a_decoy_with_its_health() -> void:
	_setup(2)
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO)
	var decoy: Actor = entities.decoy_of(0)
	check(decoy != null and is_equal_approx(world.combat.health_of(decoy), EntitiesScript.DECOY_HEALTH), "Combat knows it with DECOY_HEALTH")


func test_a_decoy_holds_until_its_health_is_gone() -> void:
	_setup(2)
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO)
	var decoy: Actor = entities.decoy_of(0)
	if decoy == null:
		check(false, "a decoy")
		return
	decoy.health.take(EntitiesScript.DECOY_HEALTH - 1.0, 1)
	_run(1)
	check(entities.count(EntitiesScript.DECOY) == 1 and ended.is_empty(), "it holds with health left")
	decoy.health.take(1.0, 1)
	_run(1)
	check(entities.count() == 0 and ended.size() == 1, "then it breaks, once")
	check(not decoy.is_inside_tree() and not world.combat.is_registered(decoy), "out of the world: nothing hits or chases it")


## It breaks quietly for Combat: no kill.
func test_a_broken_decoy_is_no_kill() -> void:
	_setup(2)
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO)
	var decoy: Actor = entities.decoy_of(0)
	if decoy == null:
		check(false, "a decoy")
		return
	var kills: Array[int] = [0]
	world.bus.kill_landed.connect(func(_by: int, _node: Node, _at: Vector2, _tag: int, _shot: int) -> void: kills[0] += 1)
	world.bus.enemy_died.connect(func(_by: int, _node: Node, _at: Vector2, _shot: int) -> void: kills[0] += 1)
	decoy.health.take(EntitiesScript.DECOY_HEALTH, 1)
	_run(1)
	check_equal(ended.size(), 1, "it broke")
	check_equal(kills[0], 0, "a broken decoy is no kill")


func test_a_decoy_lasts_its_seconds_then_ends_once() -> void:
	_setup(1)
	_spawn(0, EntitiesScript.DECOY, Vector2(30.0, 40.0), 1.0)
	_run(int(0.9 / STEP))
	check_equal(entities.count(), 1, "a decoy lasts its seconds")
	_run(int(0.2 / STEP))
	check(entities.count() == 0 and ended.size() == 1, "then ends, once")


func test_a_decoy_that_ran_out_is_no_target() -> void:
	_setup(1)
	_spawn(0, EntitiesScript.DECOY, Vector2(30.0, 40.0), 1.0)
	var decoy: Actor = entities.decoy_of(0)
	_run(int(1.1 / STEP))
	check(decoy != null and not AIBrain.can_target(decoy), "an ended decoy is no target")


# --- Decoys look like their wizard -----------------------------------------------------------

## The first wizard's Sprite turned to another frame of its head sheet (the real scene, living
## staffs H3), and its decoy at (10, 10).
func _copied() -> Array:
	_setup(1)
	var sprite := world.players[0].get_node("Sprite") as Sprite2D
	sprite.frame_coords = Vector2i(9, 0)
	_spawn(0, EntitiesScript.DECOY, Vector2(10.0, 10.0))
	return [sprite, entities.decoy_of(0)]


func test_a_decoy_copies_its_wizards_sprite_and_the_way_it_points() -> void:
	var made: Array = _copied()
	var sprite: Sprite2D = made[0]
	var decoy: Actor = made[1]
	check(decoy != null and decoy.visible, "the decoy shows")
	if decoy == null:
		return
	var look := decoy.get_node("Look") as DecoyLook
	check(look.sprite.texture == sprite.texture and look.sprite.frame == sprite.frame, "it copies the wizard's sprite and the way it points")


## Never see-through (the glow look) and part fallen apart, so it never reads as a second wizard.
func test_a_decoy_is_drawn_opaque_by_the_shot_shader_part_dissolved() -> void:
	var decoy: Actor = _copied()[1]
	if decoy == null:
		check(false, "a decoy")
		return
	var material := (decoy.get_node("Look") as DecoyLook).sprite.material as ShaderMaterial
	check(decoy.modulate.a == 1.0 and material != null, "never see-through: drawn by the shot shader")
	check(material != null and (material.get_shader_parameter(&"dissolve") as float) > 0.0, "part fallen apart, so it never reads as a second wizard")


func test_a_decoy_stands_where_the_card_put_it() -> void:
	var decoy: Actor = _copied()[1]
	check(decoy != null and decoy.position.is_equal_approx(Vector2(10.0, 10.0)), "it stands where the card put it")


# --- Decoys placed again ---------------------------------------------------------------------

## A row's decoy is made new each time (online-ready N10b: nothing of an earlier decoy carries over,
## which no snapshot holds): the ended one is freed as its row holds the next, which is full, under a
## fresh id. The first decoy (hurt, then run out) and the next.
func _placed_again() -> Array:
	_setup(1)
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO, 1.0)
	var first: Actor = entities.decoy_of(0)
	if first == null:
		check(false, "a decoy")
		return [null, null]
	first.health.take(5.0, 1)
	_run(int(1.5 / STEP))
	check_equal(entities.count(), 0, "it ran out")
	_spawn(0, EntitiesScript.DECOY, Vector2(50.0, 0.0))
	return [first, entities.decoy_of(0)]


func test_a_decoy_placed_again_is_a_new_actor_in_place_of_the_freed_one() -> void:
	var made: Array = _placed_again()
	var first: Variant = made[0]
	var again: Actor = made[1] as Actor
	check(again != null and is_instance_valid(again) and again != first, "a new actor")
	check(not is_instance_valid(first), "the ended one is freed")


func test_a_decoy_placed_again_is_whole_in_the_world_and_hurtable() -> void:
	var again: Actor = _placed_again()[1] as Actor
	if again == null:
		check(false, "the row's next decoy")
		return
	check(again.is_inside_tree() and again.id >= 0, "in the world with an id")
	check(is_equal_approx(again.health.health, EntitiesScript.DECOY_HEALTH), "with full health")
	check(world.combat.is_registered(again), "hurtable again")


## A decoy placed again with no foe about aims the way it was placed, not where its row's last
## decoy aimed. Regression: the controller's last aim stayed in the actor's intent.
func test_a_decoy_placed_again_aims_the_way_it_was_placed() -> void:
	var decoy: Actor = _decoy()
	if decoy == null:
		return
	var imp: Actor = _imp(Vector2(0.0, 120.0))
	_run(1)
	check(decoy.aim.dot(Vector2.DOWN) > 0.99, "it aims at the imp below it (%s)" % decoy.aim)
	world.bus.entity_end_requested.emit(0, TAG)
	world.enemies.erase(imp)
	imp.free()
	world.players[0].position = Vector2(400.0, 0.0)
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO)
	_run(2)
	decoy = entities.decoy_of(0)
	check(decoy != null, "the row's next decoy")
	if decoy == null:
		return
	check(decoy.aim.dot(Vector2.LEFT) > 0.99, "with no foe it aims the way it was placed, away from its wizard (%s)" % decoy.aim)


# --- Familiars -------------------------------------------------------------------------------

## The first wizard at (100, 100) and its familiar placed 30 px to its right.
func _familiar() -> Node2D:
	_setup(1)
	var wizard: Node2D = world.players[0]
	wizard.position = Vector2(100.0, 100.0)
	_spawn(0, EntitiesScript.FAMILIAR, wizard.position + Vector2(30.0, 0.0))
	return wizard


func test_a_familiar_starts_on_its_circle_round_its_wizard() -> void:
	var wizard: Node2D = _familiar()
	var first: Vector2 = entities.positions_of(0, TAG)[0]
	check(is_equal_approx(first.distance_to(wizard.position + EntitiesScript.FAMILIAR_CENTRE), EntitiesScript.FAMILIAR_ORBIT), "a familiar starts on its circle round the wizard")


func test_a_familiar_turns_round_its_wizard() -> void:
	var wizard: Node2D = _familiar()
	var first: Vector2 = entities.positions_of(0, TAG)[0]
	_run(8)
	var later: Vector2 = entities.positions_of(0, TAG)[0]
	check(not later.is_equal_approx(first), "it moved")
	check(is_equal_approx(later.distance_to(wizard.position + EntitiesScript.FAMILIAR_CENTRE), EntitiesScript.FAMILIAR_ORBIT), "on its circle")


func test_a_familiar_follows_its_wizard() -> void:
	var wizard: Node2D = _familiar()
	_run(8)
	wizard.position += Vector2(200.0, 0.0)
	_run(1)
	var moved: Vector2 = entities.positions_of(0, TAG)[0]
	check(is_equal_approx(moved.distance_to(wizard.position + EntitiesScript.FAMILIAR_CENTRE), EntitiesScript.FAMILIAR_ORBIT), "it follows the wizard")


## Drawn as an orbit shot by the shots' shader (the glow look): the orbit kind and the bend of its
## circle, with no flat circles of its own.
func test_a_familiar_is_drawn_as_an_orbit_shot_bending_round_its_circle() -> void:
	_familiar()
	_run(8)
	check_equal(entities.drawn_familiars(), 1, "one familiar drawn")
	var buffer: PackedFloat32Array = entities._familiar_node.multimesh.buffer
	var coded: float = (1.0 - buffer[15]) * ProjectileManagerScript.KIND_STEPS
	check_equal(floori(coded + 0.5), ProjectileManagerScript.KIND_ORBIT, "as an orbit shot")
	check(is_equal_approx(coded - ProjectileManagerScript.KIND_ORBIT, ProjectileManagerScript.bend_code(1.0 / EntitiesScript.FAMILIAR_ORBIT)), "bending round its circle")
	check(not entities.has_method("_draw"), "no flat circles drawn any more")


func test_a_familiar_is_drawn_in_its_players_colours() -> void:
	_familiar()
	_run(8)
	var buffer: PackedFloat32Array = entities._familiar_node.multimesh.buffer
	check_equal(roundi(buffer[8] * 255.0) % 4, 0, "in player 1's colours")


func test_a_familiar_is_drawn_flying_along_its_circle() -> void:
	var wizard: Node2D = _familiar()
	_run(8)
	var at: Vector2 = entities.positions_of(0, TAG)[0]
	var buffer: PackedFloat32Array = entities._familiar_node.multimesh.buffer
	var along := Vector2(buffer[0], buffer[4]).normalized()
	var round_about: Vector2 = (at - (wizard.position + EntitiesScript.FAMILIAR_CENTRE)).normalized()
	check(absf(along.dot(round_about)) < 0.2, "flying along its circle, not out of it")


## A familiar a trigger made (its caster a shot) circles that shot, not the wizard; once the shot
## is gone it circles where the shot was last. The shot's handle.
func _familiar_of_a_shot() -> int:
	_setup(1)
	world.players[0].position = Vector2(-300.0, 0.0)
	var shot: int = world.projectiles.spawn(0, Vector2(100.0, 0.0), Vector2(40.0, 0.0), 2.0, 2.0, 0)
	world.bus.entity_spawn_requested.emit(0, EntitiesScript.FAMILIAR, Vector2(100.0, 0.0), 5.0, TAG, shot)
	_run(10)
	return shot


func test_a_familiar_from_a_trigger_circles_the_shot_as_it_flies() -> void:
	var shot: int = _familiar_of_a_shot()
	var at: Vector2 = entities.positions_of(0, TAG)[0]
	var centre: Vector2 = world.projectiles.get_position_of(shot)
	check(absf(at.distance_to(centre) - EntitiesScript.FAMILIAR_ORBIT) < 4.0, "it circles the shot as it flies: %s round %s" % [at, centre])


func test_a_familiar_from_a_trigger_keeps_circling_where_the_shot_ended() -> void:
	var shot: int = _familiar_of_a_shot()
	_run(40)
	check(not world.projectiles.is_alive(shot), "the shot is gone")
	var last: Vector2 = entities.positions_of(0, TAG)[0]
	_run(10)
	var later: Vector2 = entities.positions_of(0, TAG)[0]
	check(not later.is_equal_approx(last) and absf(later.distance_to(Vector2(180.0, 0.0)) - EntitiesScript.FAMILIAR_ORBIT) < 6.0, "it keeps circling where the shot ended: %s" % later)


## The familiar card's own look (docs/milestones/card-looks.md, phase 3): every familiar's orb is
## drawn by the shader Spells answers for the familiar card as an orb, set once on the familiars'
## batch.
func test_a_familiar_is_drawn_by_its_cards_shader() -> void:
	_setup()
	var material: ShaderMaterial = entities._familiar_node.material as ShaderMaterial
	check(material.shader == preload("res://content/spells/carriers/familiar/familiar.gdshader"), "drawn by the familiar card's shader, got %s" % material.shader.resource_path)


## With no Spells (or no shader of its own) the plain orbit shot's.
func test_a_familiar_with_no_spells_is_drawn_as_a_plain_orbit_shot() -> void:
	_setup()
	var material: ShaderMaterial = entities._familiar_node.material as ShaderMaterial
	entities.spells = null
	entities.use_familiar_look()
	check(material.shader == EntitiesScript.ORBIT_SHADER, "the plain orbit shot with no Spells")


# --- The cap, ends and clears ----------------------------------------------------------------

## PER_PLAYER decoys (tags TAG and on) and a familiar for the first wizard.
func _full_row() -> void:
	_setup(1)
	for i in EntitiesScript.PER_PLAYER:
		_spawn(0, EntitiesScript.DECOY, Vector2(float(i) * 10.0, 0.0), 5.0, TAG + i)
	_spawn(0, EntitiesScript.FAMILIAR, Vector2.ZERO, 5.0, TAG + 50)


func test_per_player_decoys_and_a_familiar_fit() -> void:
	_full_row()
	check(ended.is_empty(), "PER_PLAYER decoys and a familiar fit")


func test_one_decoy_more_ends_the_players_oldest_decoy() -> void:
	_full_row()
	_spawn(0, EntitiesScript.DECOY, Vector2(99.0, 0.0), 5.0, TAG + 9)
	check(ended.size() == 1 and ended[0][3] == TAG, "one more decoy ends the player's oldest decoy")
	check_equal(entities.count(EntitiesScript.DECOY, 0), EntitiesScript.PER_PLAYER, "the player keeps PER_PLAYER decoys")


func test_one_decoy_more_leaves_the_familiar() -> void:
	_full_row()
	_spawn(0, EntitiesScript.DECOY, Vector2(99.0, 0.0), 5.0, TAG + 9)
	check_equal(entities.count(EntitiesScript.FAMILIAR, 0), 1, "the familiar is untouched")


## Entities of tags TAG and TAG + 1 for player 0, and of TAG for player 1, then an end of player
## 0's TAG asked.
func _end_by_tag() -> void:
	_setup(2)
	_spawn(0, EntitiesScript.FAMILIAR, Vector2.ZERO, INF, TAG)
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO, INF, TAG)
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO, INF, TAG + 1)
	_spawn(1, EntitiesScript.DECOY, Vector2.ZERO, INF, TAG)
	world.bus.entity_end_requested.emit(0, TAG)


func test_an_end_asked_by_tag_ends_every_entity_of_that_player_and_tag() -> void:
	_end_by_tag()
	check_equal(ended.size(), 2, "entity_end_requested ends both entities of that player and tag")


func test_an_end_asked_by_tag_leaves_other_tags_and_players() -> void:
	_end_by_tag()
	check_equal(entities.count(), 2, "it leaves the other tag, and the other player's same tag")


func test_inf_or_zero_seconds_last_until_asked_to_end() -> void:
	_setup(1)
	_spawn(0, EntitiesScript.FAMILIAR, Vector2.ZERO, INF)
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO, 0.0)
	_run(int(30.0 / STEP))
	check(entities.count() == 2 and ended.is_empty(), "INF or 0 seconds last until asked to end")


func test_a_new_room_clears_every_entity_quietly() -> void:
	_setup(1)
	_spawn(0, EntitiesScript.FAMILIAR, Vector2.ZERO)
	_spawn(0, EntitiesScript.DECOY, Vector2(5.0, 0.0))
	world.bus.room_entered.emit(&"next")
	check(entities.count() == 0 and ended.is_empty(), "a new room clears every entity without entity_ended")
	check(entities.decoy_of(0) == null, "its decoys are gone")


func test_the_end_of_the_run_clears_every_entity_quietly() -> void:
	_setup(1)
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO)
	world.bus.run_ended.emit(false)
	check(entities.count() == 0 and ended.is_empty(), "the end of the run clears every entity without entity_ended")


## Four players, each with full rows of decoys and familiars.
func _four_full() -> void:
	_setup(4)
	for player in 4:
		for i in EntitiesScript.PER_PLAYER:
			_spawn(player, EntitiesScript.DECOY, Vector2(float(player) * 100.0, float(i)), 5.0, TAG + player)
			_spawn(player, EntitiesScript.FAMILIAR, Vector2(float(player) * 100.0, float(i)), 5.0, TAG + player)


func test_four_players_fill_their_rows_without_ending_each_others() -> void:
	_four_full()
	check(entities.count() == EntitiesScript.PLAYER_ROWS and ended.is_empty(), "four players fill their rows without ending each other's")


func test_a_full_pool_ends_only_the_asking_players_oldest() -> void:
	_four_full()
	_spawn(2, EntitiesScript.DECOY, Vector2.ZERO, 5.0, TAG + 2)
	check(ended.size() == 1 and ended[0][0] == 2, "a full pool ends only the asking player's oldest")
	for player in 4:
		check_equal(entities.count(EntitiesScript.DECOY, player), EntitiesScript.PER_PLAYER, "player %d keeps their decoys" % (player + 1))


func test_bad_requests_make_nothing() -> void:
	_setup(1)
	_spawn(EntitiesScript.ACTORS, EntitiesScript.DECOY, Vector2.ZERO)
	_spawn(-1, EntitiesScript.DECOY, Vector2.ZERO)
	_spawn(0, EntitiesScript.DECOY, Vector2(NAN, 0.0))
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO, NAN)
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO, 5.0, SpellTag.make(1, 0, 0, 1))
	check_equal(entities.count(), 0, "bad actor ids, positions and times make nothing, nor a spell tag of another caster")


# --- Swap ------------------------------------------------------------------------------------

func test_a_swap_moves_only_the_enemy_it_names() -> void:
	_setup(1)
	var moved: Actor = _imp(Vector2(50.0, 0.0))
	var other: Actor = _imp(Vector2(-50.0, 0.0))
	world.bus.target_move_requested.emit(0, moved, Vector2(300.0, 200.0))
	check(moved.position.is_equal_approx(Vector2(300.0, 200.0)), "target_move_requested moves the enemy it names")
	check(other.position.is_equal_approx(Vector2(-50.0, 0.0)), "and no other")


func test_a_swap_to_nowhere_is_ignored() -> void:
	_setup(1)
	var moved: Actor = _imp(Vector2(50.0, 0.0))
	world.bus.target_move_requested.emit(0, moved, Vector2(INF, 0.0))
	check(moved.position.is_equal_approx(Vector2(50.0, 0.0)), "a move to nowhere is ignored")
