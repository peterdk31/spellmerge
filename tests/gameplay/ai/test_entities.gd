extends SceneTree
## Tests for the entity kit (staffs B5, gameplay/ai/entities.gd and its use in ai.gd): decoys
## that enemies chase and shoot down, familiars that circle their wizard (they cast nothing
## themselves: core/spells fires their triggers, rules R4 F3), the per-player cap, ending by tag, quiet clears, swap moves, and four
## players at once. Time moves by fixed binary-fraction deltas.
##
## godot --headless --path . --script res://tests/gameplay/ai/test_entities.gd

const AiFixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const EntitiesScript := preload("res://gameplay/ai/entities.gd")
const EventsScript := preload("res://core/events/events.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

const STEP: float = 0.0625
const TAG: int = 1 << 20

var _failures: Array[String] = []
var _world: AiFixture = null
var _entities: EntitiesScript = null
## Every entity_ended as [caster, kind, position, tag] (the owner's actor id; the fixture's
## wizards are the actors 0-3, seated 0-3).
var _ended: Array[Array] = []


func _initialize() -> void:
	await process_frame
	_test_decoy_is_chased_before_a_nearer_wizard()
	_test_enemy_shots_break_a_decoy()
	_test_every_hit_wears_a_decoy()
	_test_decoy_runs_out()
	_test_decoy_copies_its_wizard()
	_test_familiar_circles_its_wizard()
	_test_a_familiar_from_a_trigger_circles_the_shot_then_where_it_ended()
	_test_cap_ends_the_oldest()
	_test_end_requested_by_tag()
	_test_held_entity_lasts()
	_test_room_and_run_clear_quietly()
	_test_four_players_keep_their_own()
	_test_bad_requests_are_ignored()
	_test_swap_moves_only_the_named_enemy()
	_teardown()
	if _failures.is_empty():
		print("TEST OK: gameplay/ai entities (decoys, familiars, swap)")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _setup(player_count: int = 1) -> void:
	_teardown()
	_world = AiFixture.new(root, player_count)
	_entities = EntitiesScript.new()
	_entities.events = _world.bus
	_entities.projectiles = _world.projectiles
	# In the tree, so the decoys are projectile targets at their real positions.
	root.add_child(_entities)
	_ended.clear()
	_world.bus.entity_ended.connect(func(player: int, kind: StringName, at: Vector2, tag: int) -> void:
		_ended.append([player, kind, at, tag]))


func _teardown() -> void:
	if _entities != null and is_instance_valid(_entities):
		_entities.free()
	_entities = null
	if _world != null:
		_world.free_all()
	_world = null


## An imp of the fixture (an actor) whose AI asks these Entities for decoys.
func _imp(at: Vector2) -> Actor:
	_world.entities = _entities
	return _world.imp(at)


## A still enemy as the projectile manager knows one (a target on LAYER_ENEMY), in the tree.
func _enemy_target(at: Vector2) -> Node2D:
	var enemy := Node2D.new()
	enemy.position = at
	_entities.add_child(enemy)
	_world.projectiles.add_target(enemy, 10.0, ProjectileManagerScript.LAYER_ENEMY)
	return enemy


func _spawn(caster: int, kind: StringName, at: Vector2, seconds: float = 5.0, tag: int = TAG) -> void:
	_world.bus.entity_spawn_requested.emit(caster, kind, at, seconds, tag, -1)


## `count` physics frames of the whole world: every imp, Combat, the projectiles, Spells (the
## imps cast their staffs), the entities.
func _run(count: int) -> void:
	for i in count:
		for enemy in _world.enemies:
			if is_instance_valid(enemy):
				enemy.step(STEP)
				enemy.position += enemy.velocity * STEP
		_world.combat.step(STEP)
		_world.projectiles.step(STEP)
		_world.spells.call("step", STEP)
		_entities.step(STEP)


# --- Tests ------------------------------------------------------------------

func _test_decoy_is_chased_before_a_nearer_wizard() -> void:
	_setup(1)
	_world.players[0].position = Vector2(60.0, 0.0)
	_spawn(0, EntitiesScript.DECOY, Vector2(-150.0, 0.0))
	var imp: Actor = _imp(Vector2.ZERO)
	_run(1)
	_check(AiFixture.ai(imp).target != null and AiFixture.ai(imp).target != _world.players[0], "an imp near a decoy chases the decoy, not the nearer wizard")
	_check(imp.velocity.x < 0.0, "the imp walks toward the decoy")
	_world.players[0].position = Vector2(1000.0, 0.0)
	var far: Actor = _imp(Vector2(600.0, 0.0))
	_run(1)
	_check(AiFixture.ai(far).target == _world.players[0], "an imp beyond the lure range chases the wizard")


func _test_enemy_shots_break_a_decoy() -> void:
	_setup(1)
	_world.players[0].position = Vector2(5000.0, 0.0)
	_spawn(0, EntitiesScript.DECOY, Vector2(80.0, 0.0), 60.0)
	var imp: Actor = _imp(Vector2.ZERO)
	# Wind up, shoot and recover: about 3 s an attack. Three hits break the decoy.
	_run(int(12.0 / STEP))
	_check(_ended.size() == 1, "the decoy breaks once after enemy shots, got %d ends" % _ended.size())
	if _ended.size() == 1:
		_check(_ended[0][0] == 0 and _ended[0][1] == EntitiesScript.DECOY and _ended[0][3] == TAG, "entity_ended names the player, the kind and the tag")
		_check((_ended[0][2] as Vector2).is_equal_approx(Vector2(80.0, 0.0)), "a decoy ends where it stood")
	_check(_entities.count() == 0, "the broken decoy is gone")
	_run(2)
	_check(AiFixture.ai(imp).target == _world.players[0], "the imp goes back to the wizard once the decoy breaks")


## Every hit wears a decoy down, a teammate's as well as an enemy's (actors G3c: no sides).
func _test_every_hit_wears_a_decoy() -> void:
	_setup(2)
	_spawn(0, EntitiesScript.DECOY, Vector2(0.0, 0.0))
	var decoy: Node2D = _entities.lure(Vector2.ZERO)
	_world.bus.projectile_hit.emit(1, decoy, Vector2.ZERO, TAG)
	for i in EntitiesScript.DECOY_HITS - 2:
		_world.bus.projectile_hit.emit(EventsScript.NO_PLAYER, decoy, Vector2.ZERO, 1000)
	_check(_entities.count(EntitiesScript.DECOY) == 1 and _ended.is_empty(), "it holds until its last hit")
	_world.bus.projectile_hit.emit(EventsScript.NO_PLAYER, decoy, Vector2.ZERO, 1000)
	_check(_entities.count() == 0 and _ended.size() == 1, "DECOY_HITS hits break it, a teammate's among them")


func _test_decoy_runs_out() -> void:
	_setup(1)
	_spawn(0, EntitiesScript.DECOY, Vector2(30.0, 40.0), 1.0)
	_run(int(0.9 / STEP))
	_check(_entities.count() == 1, "a decoy lasts its seconds")
	_run(int(0.2 / STEP))
	_check(_entities.count() == 0 and _ended.size() == 1, "and then ends, once")
	var decoy: Node2D = _entities.lure(Vector2(30.0, 40.0))
	_check(decoy == null, "an ended decoy lures nobody")


func _test_decoy_copies_its_wizard() -> void:
	_setup(1)
	# The wizard is the real scene (living staffs H3): its Sprite shows a frame of its head sheet.
	var sprite := _world.players[0].get_node("Sprite") as Sprite2D
	sprite.frame_coords = Vector2i(9, 0)
	_spawn(0, EntitiesScript.DECOY, Vector2(10.0, 10.0))
	var decoy: EntitiesScript.Decoy = _entities.lure(Vector2(10.0, 10.0)) as EntitiesScript.Decoy
	_check(decoy != null and decoy.visible, "the decoy shows")
	if decoy != null:
		_check(decoy.sprite.texture == sprite.texture and decoy.sprite.frame == sprite.frame, "it copies the wizard's sprite and the way it points")
		var material := decoy.sprite.material as ShaderMaterial
		_check(decoy.modulate.a == 1.0 and material != null, "never see-through (the glow look): drawn by the shot shader")
		_check((material.get_shader_parameter(&"dissolve") as float) > 0.0, "part fallen apart, so it never reads as a second wizard")
		_check(material.get_shader_parameter(&"dissolve_color") != Color(0.957, 0.945, 0.918, 1.0), "in its player's colour")
		_check(decoy.position.is_equal_approx(Vector2(10.0, 10.0)), "it stands where the card put it")


func _test_familiar_circles_its_wizard() -> void:
	_setup(1)
	var wizard: Node2D = _world.players[0]
	wizard.position = Vector2(100.0, 100.0)
	_spawn(0, EntitiesScript.FAMILIAR, wizard.position + Vector2(30.0, 0.0))
	var centre: Vector2 = wizard.position + EntitiesScript.FAMILIAR_CENTRE
	var first: Vector2 = _entities.positions_of(0, TAG)[0]
	_check(is_equal_approx(first.distance_to(centre), EntitiesScript.FAMILIAR_ORBIT), "a familiar starts on its circle round the wizard")
	_run(8)
	var later: Vector2 = _entities.positions_of(0, TAG)[0]
	_check(not later.is_equal_approx(first) and is_equal_approx(later.distance_to(centre), EntitiesScript.FAMILIAR_ORBIT), "it turns round the wizard")
	wizard.position += Vector2(200.0, 0.0)
	_run(1)
	var moved: Vector2 = _entities.positions_of(0, TAG)[0]
	_check(is_equal_approx(moved.distance_to(wizard.position + EntitiesScript.FAMILIAR_CENTRE), EntitiesScript.FAMILIAR_ORBIT), "it follows the wizard")
	# Drawn as an orbit shot by the shots' shader (the glow look): its player, the orbit kind and
	# the bend of its circle, flying along it.
	_check(_entities.drawn_familiars() == 1, "one familiar drawn")
	var buffer: PackedFloat32Array = _entities._familiar_node.multimesh.buffer
	var coded: float = (1.0 - buffer[15]) * ProjectileManagerScript.KIND_STEPS
	_check(floori(coded + 0.5) == ProjectileManagerScript.KIND_ORBIT, "as an orbit shot")
	_check(is_equal_approx(coded - ProjectileManagerScript.KIND_ORBIT, ProjectileManagerScript.bend_code(1.0 / EntitiesScript.FAMILIAR_ORBIT)), "bending round its circle")
	_check(roundi(buffer[8] * 255.0) % 4 == 0, "in player 1's colours")
	var along := Vector2(buffer[0], buffer[4]).normalized()
	var round_about: Vector2 = (moved - (wizard.position + EntitiesScript.FAMILIAR_CENTRE)).normalized()
	_check(absf(along.dot(round_about)) < 0.2, "flying along its circle, not out of it")
	_check(not _entities.has_method("_draw"), "no flat circles drawn any more")


## A familiar a trigger made (its caster a shot) circles that shot, not the wizard; once the shot
## is gone it circles where the shot was last.
func _test_a_familiar_from_a_trigger_circles_the_shot_then_where_it_ended() -> void:
	_setup(1)
	_world.players[0].position = Vector2(-300.0, 0.0)
	var shot: int = _world.projectiles.spawn(0, Vector2(100.0, 0.0), Vector2(40.0, 0.0), 2.0, 2.0, 0)
	_world.bus.entity_spawn_requested.emit(0, EntitiesScript.FAMILIAR, Vector2(100.0, 0.0), 5.0, TAG, shot)
	_run(10)
	var at: Vector2 = _entities.positions_of(0, TAG)[0]
	var centre: Vector2 = _world.projectiles.get_position_of(shot)
	_check(absf(at.distance_to(centre) - EntitiesScript.FAMILIAR_ORBIT) < 4.0, "it circles the shot as it flies: %s round %s" % [at, centre])
	_run(40)
	_check(not _world.projectiles.is_alive(shot), "the shot is gone")
	var last: Vector2 = _entities.positions_of(0, TAG)[0]
	_run(10)
	var later: Vector2 = _entities.positions_of(0, TAG)[0]
	_check(not later.is_equal_approx(last) and absf(later.distance_to(Vector2(180.0, 0.0)) - EntitiesScript.FAMILIAR_ORBIT) < 6.0, "it keeps circling where the shot ended: %s" % later)


func _test_cap_ends_the_oldest() -> void:
	_setup(1)
	for i in EntitiesScript.PER_PLAYER:
		_spawn(0, EntitiesScript.DECOY, Vector2(float(i) * 10.0, 0.0), 5.0, TAG + i)
	_spawn(0, EntitiesScript.FAMILIAR, Vector2.ZERO, 5.0, TAG + 50)
	_check(_ended.is_empty(), "PER_PLAYER decoys and a familiar fit")
	_spawn(0, EntitiesScript.DECOY, Vector2(99.0, 0.0), 5.0, TAG + 9)
	_check(_ended.size() == 1 and _ended[0][3] == TAG, "one more decoy ends the player's oldest decoy")
	_check(_entities.count(EntitiesScript.DECOY, 0) == EntitiesScript.PER_PLAYER, "the player keeps PER_PLAYER decoys")
	_check(_entities.count(EntitiesScript.FAMILIAR, 0) == 1, "the familiar is untouched")


func _test_end_requested_by_tag() -> void:
	_setup(2)
	_spawn(0, EntitiesScript.FAMILIAR, Vector2.ZERO, INF, TAG)
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO, INF, TAG)
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO, INF, TAG + 1)
	_spawn(1, EntitiesScript.DECOY, Vector2.ZERO, INF, TAG)
	_world.bus.entity_end_requested.emit(0, TAG)
	_check(_ended.size() == 2, "entity_end_requested ends both entities of that player and tag")
	_check(_entities.count() == 2, "and leaves the other tag, and the other player's same tag")


func _test_held_entity_lasts() -> void:
	_setup(1)
	_spawn(0, EntitiesScript.FAMILIAR, Vector2.ZERO, INF)
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO, 0.0)
	_run(int(30.0 / STEP))
	_check(_entities.count() == 2 and _ended.is_empty(), "INF or 0 seconds last until asked to end")


func _test_room_and_run_clear_quietly() -> void:
	_setup(1)
	_spawn(0, EntitiesScript.FAMILIAR, Vector2.ZERO)
	_spawn(0, EntitiesScript.DECOY, Vector2(5.0, 0.0))
	_world.bus.room_entered.emit(&"next")
	_check(_entities.count() == 0 and _ended.is_empty(), "a new room clears every entity without entity_ended")
	_check(_entities.lure(Vector2(5.0, 0.0)) == null, "and its decoys lure nobody")
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO)
	_world.bus.run_ended.emit(false)
	_check(_entities.count() == 0 and _ended.is_empty(), "so does the end of the run")


func _test_four_players_keep_their_own() -> void:
	_setup(4)
	for player in 4:
		for i in EntitiesScript.PER_PLAYER:
			_spawn(player, EntitiesScript.DECOY, Vector2(float(player) * 100.0, float(i)), 5.0, TAG + player)
			_spawn(player, EntitiesScript.FAMILIAR, Vector2(float(player) * 100.0, float(i)), 5.0, TAG + player)
	_check(_entities.count() == EntitiesScript.PLAYER_ROWS and _ended.is_empty(), "four players fill their rows without ending each other's")
	_spawn(2, EntitiesScript.DECOY, Vector2.ZERO, 5.0, TAG + 2)
	_check(_ended.size() == 1 and _ended[0][0] == 2, "a full pool ends only the asking player's oldest")
	for player in 4:
		_check(_entities.count(EntitiesScript.DECOY, player) == EntitiesScript.PER_PLAYER, "player %d keeps their decoys" % (player + 1))


func _test_bad_requests_are_ignored() -> void:
	_setup(1)
	_spawn(EntitiesScript.ACTORS, EntitiesScript.DECOY, Vector2.ZERO)
	_spawn(-1, EntitiesScript.DECOY, Vector2.ZERO)
	_spawn(0, EntitiesScript.DECOY, Vector2(NAN, 0.0))
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO, NAN)
	_spawn(0, EntitiesScript.DECOY, Vector2.ZERO, 5.0, SpellTag.make(1, 0, 0, 1))
	_check(_entities.count() == 0, "bad actor ids, positions and times make nothing, nor a spell tag of another caster")


func _test_swap_moves_only_the_named_enemy() -> void:
	_setup(1)
	var moved: Actor = _imp(Vector2(50.0, 0.0))
	var other: Actor = _imp(Vector2(-50.0, 0.0))
	_world.bus.target_move_requested.emit(0, moved, Vector2(300.0, 200.0))
	_check(moved.position.is_equal_approx(Vector2(300.0, 200.0)), "target_move_requested moves the enemy it names")
	_check(other.position.is_equal_approx(Vector2(-50.0, 0.0)), "and no other")
	_world.bus.target_move_requested.emit(0, moved, Vector2(INF, 0.0))
	_check(moved.position.is_equal_approx(Vector2(300.0, 200.0)), "a move to nowhere is ignored")
