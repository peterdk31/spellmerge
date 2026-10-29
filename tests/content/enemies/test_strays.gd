extends "res://tests/support/suite.gd"
## The strays (living staffs H5, docs/milestones/M2-living-staffs.md, "The strays"): the Cinder
## Rod (`ember_imp`), the Splinter, the Storm Fork, the Rime Crook and the Bone Scepter are actors
## whose art is one 32 px body; each wears the shared Face in a stray style (one eye on the Splinter), angry at rest, its eyes in its
## element's colour, and the face goes furious while it winds up; each has the telegraph parts;
## each staff compiles from player cards and its first cast is affordable on full mana; and they
## hop on their tips while they walk (the face goes with the body) and bob while they stand.
##
## godot --headless --path . --script res://tests/content/enemies/test_strays.gd

const AiFixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const STRAYS: Array[EnemyBase] = [
	preload("res://content/enemies/ember_imp/ember_imp.tres"),
	preload("res://content/enemies/splinter/splinter.tres"),
	preload("res://content/enemies/storm_fork/storm_fork.tres"),
	preload("res://content/enemies/rime_crook/rime_crook.tres"),
	preload("res://content/enemies/bone_scepter/bone_scepter.tres"),
]
## Each stray's face style and eye glow (its element's light shade, docs/STYLE.md).
const STYLES: Array[Face.Style] = [Face.Style.STRAY, Face.Style.STRAY_ONE, Face.Style.STRAY, Face.Style.STRAY, Face.Style.STRAY]
const GLOWS: Array[Color] = [
	Color(1, 0.635, 0.235, 1),
	Color(1, 0.635, 0.235, 1),
	Color(0.706, 0.91, 0.165, 1),
	Color(0.769, 0.965, 0.949, 1),
	Color(0.878, 0.541, 0.847, 1),
]
## The cards each stray's staff holds, in the same order.
const CARDS: Array[Array] = [[&"fire", &"bolt"], [&"dash"], [&"triple", &"lightning", &"bolt"], [&"frost", &"hook"], [&"void", &"rain", &"nova"]]
const FRAME: int = 32

var _world: AiFixture


func before_each() -> void:
	_world = AiFixture.new(root)


func after_each() -> void:
	_world.free_all()


func _face(body: Actor) -> Face:
	return body.get_node_or_null(^"Face") as Face


func test_each_stray_is_one_body_with_its_telegraph_parts() -> void:
	for data in STRAYS:
		var body: Node = own(data.scene.instantiate()) as Node
		var sprite := body.get_node_or_null(^"Sprite") as Sprite2D
		check(sprite != null and sprite.texture != null, "%s: a body sprite" % data.id)
		if sprite != null and sprite.texture != null:
			check_equal(sprite.texture.get_size(), Vector2(FRAME, FRAME), "%s: one 32 px body" % data.id)
		var telegraph := body.get_node_or_null(^"Telegraph") as Sprite2D
		check(telegraph != null and telegraph.material is ShaderMaterial and not telegraph.visible, "%s: a hidden telegraph drawn by a shader" % data.id)
		var look := body.get_node_or_null(^"CreatureLook")
		var face := body.get_node_or_null(^"Face")
		check(look != null and face != null and look.get_index() < face.get_index(), "%s: the body's look steps before the face" % data.id)


func test_each_stray_wears_an_angry_face_in_its_element() -> void:
	for i in STRAYS.size():
		var body: Actor = _world.enemy(STRAYS[i].scene, STRAYS[i], Vector2(-500.0, 0.0))
		var face := _face(body)
		check(face != null, "%s wears a Face" % STRAYS[i].id)
		if face == null:
			continue
		check_equal(face.style, STYLES[i], "%s: its eye style" % STRAYS[i].id)
		check_equal(face.resting_mood, Face.Mood.ANGRY, "%s: angry at rest" % STRAYS[i].id)
		check(face.glow.is_equal_approx(GLOWS[i]), "%s: eyes in its element's colour" % STRAYS[i].id)


func test_the_face_goes_furious_while_it_winds_up() -> void:
	var body: Actor = _world.imp_facing_player()
	var mind: AIController = AiFixture.ai(body)
	var steps: int = 0
	while not mind.is_telegraphing() and steps < 60:
		_world.run(body, 1)
		steps += 1
	check(mind.is_telegraphing(), "the Cinder Rod winds up")
	check_equal(_face(body).mood(), Face.Mood.FURIOUS, "and its brows go furious")


func test_each_staff_compiles_and_its_first_cast_is_affordable() -> void:
	for data in STRAYS:
		check(data.staff != null and not data.cards.is_empty(), "%s has a staff of cards" % data.id)
		if data.staff == null:
			continue
		check_equal(SpellValidator.check_staff(data.staff).size(), 0, "%s: its staff is valid" % data.id)
		var body: Actor = _world.enemy(data.scene, data, Vector2(-500.0, 300.0))
		check(body.caster != null and body.caster.has_staff(0), "%s: its staff compiles and casts" % data.id)
		if body.caster != null and body.caster.has_staff(0):
			var cost: float = body.caster.next_cast_mana(0)
			check(cost >= 0.0 and cost <= data.max_mana, "%s: the first cast (%.1f mana) fits its pool (%.1f)" % [data.id, cost, data.max_mana])


func test_each_stray_casts_the_cards_it_was_planned_with() -> void:
	for i in STRAYS.size():
		var held: Array = []
		for card in STRAYS[i].cards:
			held.append(card)
		check_equal(held, CARDS[i], "%s: its cards" % STRAYS[i].id)


## Four players in the room: the Rime Crook and the Bone Scepter wind up, cast their spells (frost
## · hook, void · rain) at the nearest of them and nobody waits (they are actors on the enemy team).
func test_the_new_strays_attack_four_players() -> void:
	for data in [STRAYS[3], STRAYS[4]]:
		var world := AiFixture.new(root, 4)
		for seat in 4:
			world.players[seat].position = Vector2(60.0 + 20.0 * seat, 10.0 * seat)
		var start: Array[Vector2] = []
		for player in world.players:
			start.append(player.position)
		var body: Actor = world.enemy(data.scene, data, Vector2.ZERO)
		var hits: Array[int] = []
		world.bus.hit_landed.connect(func(caster: int, _t: Node, _a: int, _p: Vector2, _k: StringName) -> void: hits.append(caster))
		var casts: Array[int] = []
		world.bus.actor_cast.connect(func(actor_id: int, _actor: Node) -> void: casts.append(actor_id))
		var winded_up: bool = false
		var mind: AIController = AiFixture.ai(body)
		for step in 480:
			world.run_all(1)
			winded_up = winded_up or mind.is_telegraphing()
		check(winded_up, "%s: winds up against four players" % data.id)
		check(not casts.is_empty(), "%s: casts its staff (%d casts)" % [data.id, casts.size()])
		var moved: bool = false
		var hurt: bool = false
		for seat in 4:
			moved = moved or not world.players[seat].position.is_equal_approx(start[seat])
			hurt = hurt or world.players[seat].health.health < world.players[seat].health.max_health
		check(not hits.is_empty() or moved or hurt, "%s: its spell reaches a player (%d hits)" % [data.id, hits.size()])
		check(body.is_inside_tree() and not body.is_down(), "%s: stays a live actor" % data.id)
		world.free_all()


func test_strays_hop_while_walking_and_the_face_goes_with_them() -> void:
	var body: Actor = _world.imp(Vector2(-400.0, 0.0))
	var look := body.get_node(^"CreatureLook") as CreatureLook
	var face := _face(body)
	var sprite := body.get_node(^"Sprite") as Sprite2D
	var highest: float = 0.0
	for i in 32:
		_world.run(body, 1)
		body.velocity = Vector2(40.0, 0.0)
		highest = maxf(highest, look.lift())
		check_equal(face.body_offset, Vector2(0.0, -look.lift()), "the face is told the lift")
		check_equal(sprite.offset.y, -look.lift(), "the sprite hops by it")
	check(highest >= CreatureLook.HOP_HEIGHT - 0.5, "walking, it hops %d px (got %.1f)" % [int(CreatureLook.HOP_HEIGHT), highest])
	highest = 0.0
	for i in 32:
		body.velocity = Vector2.ZERO
		look.step(AiFixture.STEP)
		highest = maxf(highest, look.lift())
	check(highest <= CreatureLook.HOP_IDLE, "standing, it only bobs (got %.1f)" % highest)
