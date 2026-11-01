extends "res://tests/support/suite.gd"
## The horde's swarmers (horde H4, docs/milestones/horde.md): the Crypt Mite and the Bone Husk are
## cheap, touch-only strays for a horde of 500+. Each is an actor with one 32 px body and the
## stray Face, no staff, no cards and no mana, so it has no Caster and no Telegraph: it only
## chases and hurts by touch (the enemy AI with nothing to cast, by the `swarmer` profile). The mite is small, fast and dies to two plain bolts; the husk is
## slow, tough and hits harder. Both die like any enemy (`enemy_died`).
##
## godot --headless --path . --script res://tests/content/enemies/test_swarmers.gd

const AiFixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const MiteData: EnemyBase = preload("res://content/enemies/crypt_mite/crypt_mite.tres")
const HuskData: EnemyBase = preload("res://content/enemies/bone_husk/bone_husk.tres")
const ImpData: EnemyBase = preload("res://content/enemies/ember_imp/ember_imp.tres")
const BoltData: Resource = preload("res://content/spells/forms/bolt/bolt.tres")
const FRAME: int = 32

var _world: AiFixture


func before_each() -> void:
	_world = AiFixture.new(root)


func after_each() -> void:
	_world.free_all()


func _swarmers() -> Array[EnemyBase]:
	return [MiteData, HuskData]


func test_each_is_demo_content_with_its_own_id() -> void:
	check_equal(MiteData.id, &"crypt_mite", "the mite's id is its folder")
	check_equal(HuskData.id, &"bone_husk", "the husk's id is its folder")
	for data in _swarmers():
		check(data.demo, "%s: in every build, so the horde has it on the web too" % data.id)
		check(data.staffs.is_empty() and not data.has_staffs(), "%s: no staff and no cards" % data.id)
		check(data.contact_damage > 0, "%s: hurts by touch" % data.id)


func test_each_is_a_cheap_body_with_a_stray_face() -> void:
	for data in _swarmers():
		var body: Node = own(data.scene.instantiate()) as Node
		var sprite := body.get_node_or_null(^"Sprite") as Sprite2D
		check(sprite != null and sprite.texture != null, "%s: a body sprite" % data.id)
		if sprite != null and sprite.texture != null:
			check_equal(sprite.texture.get_size(), Vector2(FRAME, FRAME), "%s: one 32 px body" % data.id)
		check(body.get_node_or_null(^"Telegraph") == null, "%s: no telegraph (it never casts)" % data.id)
		check(body.get_node_or_null(^"Caster") == null, "%s: no caster node" % data.id)
		var look := body.get_node_or_null(^"CreatureLook")
		var face := body.get_node_or_null(^"Face") as Face
		check(look != null and face != null and look.get_index() < face.get_index(), "%s: the look steps before the face" % data.id)
		if face != null:
			check(face.style == Face.Style.STRAY or face.style == Face.Style.STRAY_ONE, "%s: a stray's eyes" % data.id)
			check_equal(face.resting_mood, Face.Mood.ANGRY, "%s: angry at rest" % data.id)
		# No more nodes than the Cinder Rod's scene: nothing per enemy that a horde would multiply.
		check(body.get_child_count() < (own(ImpData.scene.instantiate()) as Node).get_child_count(), "%s: fewer nodes than the Cinder Rod" % data.id)


func test_the_mite_is_fast_and_fragile_the_husk_slow_and_tough() -> void:
	var bolt: int = int(BoltData.get("base_damage"))
	check(MiteData.max_health > bolt and MiteData.max_health <= 2 * bolt, "the mite dies to two plain bolts (%d health, a bolt does %d)" % [MiteData.max_health, bolt])
	check(MiteData.move_speed > ImpData.move_speed and HuskData.move_speed < ImpData.move_speed, "the mite outruns the Cinder Rod, the husk lags behind it")
	check(HuskData.max_health > ImpData.max_health, "the husk is tougher than the Cinder Rod")
	check(HuskData.contact_damage > MiteData.contact_damage, "the husk hits harder than the mite")
	var wizard_speed: float = _world.players[0].mover.speed
	check(MiteData.move_speed < wizard_speed, "a wizard still outruns the mite (%.0f < %.0f)" % [MiteData.move_speed, wizard_speed])


func test_each_chases_into_a_wizard_and_hurts_it_by_touch() -> void:
	for data in _swarmers():
		var world := AiFixture.new(root)
		var wizard: Actor = world.players[0]
		wizard.position = Vector2(60.0, 0.0)
		var body: Actor = world.enemy(data.scene, data, Vector2.ZERO)
		check(body.caster == null, "%s: no caster" % data.id)
		var start: int = wizard.health.health
		world.run(body, int(4.0 / AiFixture.STEP))
		check_equal(AiFixture.ai(body).state, AIController.State.CHASE, "%s: never winds up" % data.id)
		check_equal(world.projectiles.get_count(), 0, "%s: casts nothing" % data.id)
		check(wizard.health.health < start, "%s: hurts the wizard by touch (%d of %d left)" % [data.id, wizard.health.health, start])
		world.free_all()


func test_each_dies_and_sends_enemy_died() -> void:
	for data in _swarmers():
		var body: Actor = _world.enemy(data.scene, data, Vector2(-300.0, 0.0))
		var died: Array[Node] = []
		_world.bus.enemy_died.connect(func(_killer: int, enemy: Node, _at: Vector2, _shot: int) -> void: died.append(enemy))
		var bolt: int = int(BoltData.get("base_damage"))
		var hits: int = ceili(float(data.max_health) / float(bolt))
		for i in hits:
			_world.combat.hit(_world.players[0].id, body, bolt)
		_world.run_all(1)
		check(died.has(body), "%s: dies to %d bolts and sends enemy_died" % [data.id, hits])
