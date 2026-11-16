extends "res://tests/support/suite.gd"
## The Spitter (content/enemies/spitter/): a stray that sprays acid in a cone at a player with the
## Spray carrier (`spray`, a held hose). It telegraphs first (its lane widening to the cone's width:
## docs/DESIGN.md, "Fair difficulty"), then holds the spray down for a moment, turning slowly after
## its target, and keeps to its spray's short range. It is in the crypt's enemy pool.
const AiFixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const SPITTER: EnemyBase = preload("res://content/enemies/spitter/spitter.tres")
const SPRAY: CarrierCard = preload("res://content/spells/carriers/spray/spray.tres")

var _world: AiFixture


func before_each() -> void:
	_world = AiFixture.new(root)


func after_each() -> void:
	_world.free_all()


## The Spitter in the fixture's world at `at`, playing by its own profile (the fixture's own enemies
## play by its exact one).
func _spitter(at: Vector2 = Vector2.ZERO) -> Actor:
	var body: Actor = SPITTER.scene.instantiate() as Actor
	AiFixture.ai(body).profile = SPITTER.profile
	body.data = SPITTER
	body.position = at
	_world.wire(body)
	root.add_child(body)
	body.ticking = false
	_world.enemies.append(body)
	return body


func test_its_data_is_a_sound_stray_with_a_spray_staff() -> void:
	check_equal(SPITTER.id, &"spitter", "its id is its folder")
	check_equal(SPITTER.problems(), PackedStringArray(), "its data is sound")
	check(SPITTER.has_staffs(), "it holds a staff")
	if not SPITTER.has_staffs():
		return
	check_equal(SPITTER.staffs[0].cards, [&"spray"] as Array[StringName], "its staff sprays")
	check_equal(SpellValidator.check_staff(SPITTER.staffs[0].staff).size(), 0, "its staff is valid")
	check(SPITTER.staffs[0].staff.wind_up >= 0.5, "every attack is telegraphed long enough to read (%.2f s)" % SPITTER.staffs[0].staff.wind_up)
	check_equal(SPITTER.contact_damage, 0, "its only damage is its telegraphed spray")
	check_equal(SPITTER.profile.name, "sprayer", "it plays by the sprayer profile")
	check(SPITTER.profile.channel_max > 0.0, "which holds a held cast down")
	var body: Node = own(SPITTER.scene.instantiate()) as Node
	var face := body.get_node_or_null(^"Face") as Face
	check(face != null and face.style == Face.Style.STRAY_ONE and face.resting_mood == Face.Mood.ANGRY, "it wears an angry one-eyed stray face: a snake staff, side-on (the owner, 2026-11-16)")


func test_its_acid_is_a_jet_in_the_enemies_blight() -> void:
	var staff: StaffBase = SPITTER.staffs[0].staff
	var cue := _world.registry.call("get_resource", &"cues", staff.cast_cue) as CueBase
	check(cue != null, "its staff's cast cue (%s) is a cue" % staff.cast_cue)
	if cue == null:
		return
	check_equal(cue.problems(), PackedStringArray(), "a sound one")
	for part: Dictionary in cue.parts:
		var shade: bool = false
		for blight: Color in Palette.shades_of(&"blight"):
			shade = shade or (part.get("color", Color.BLACK) as Color).is_equal_approx(blight)
		check(part.has("for") and shade, "each part pours, in a shade of Blight: %s" % [part])


func test_it_joins_the_crypt_pool_as_a_mid_strength_enemy() -> void:
	check(SPITTER.biomes.has(&"crypt"), "it fights in the crypt (the owner, 2026-11-16)")
	check(SPITTER.cost >= 2 and SPITTER.cost <= 3, "mid-strength in a room's budget (%d)" % SPITTER.cost)
	# The run's content as the game gathers it from the scanned folders.
	var content: RunContent = _world.registry.call("run_content") as RunContent
	var ids: Array[StringName] = []
	for enemy: EnemyBase in content.enemy_pool(&"crypt", SPITTER.min_depth):
		ids.append(enemy.id)
	check(ids.has(&"spitter"), "the crypt's pool at its first row has it (%s)" % [ids])


## Four seconds of a Spitter with the player `distance` px to its right: when it first telegraphed,
## when the player was first hurt, how many casts it pressed while it held, and the most it held.
func _fight(distance: float, seconds: float = 4.0) -> Dictionary:
	_world.players[0].position = Vector2(distance, 0.0)
	var body: Actor = _spitter()
	var mind: AIController = AiFixture.ai(body)
	var hurt_at: float = -1.0
	var telegraphed_at: float = -1.0
	var held: float = 0.0
	var longest: float = 0.0
	var casts: Array[float] = []
	var now: Array[float] = [0.0]
	_world.bus.actor_cast.connect(func(actor_id: int, _actor: Node) -> void:
		if actor_id == body.id:
			casts.append(now[0]))
	var start: float = _world.players[0].health.health
	var steps: int = int(seconds / AiFixture.STEP)
	for step in steps:
		_world.run(body, 1)
		now[0] += AiFixture.STEP
		if telegraphed_at < 0.0 and mind.is_telegraphing():
			telegraphed_at = now[0]
		if hurt_at < 0.0 and _world.players[0].health.health < start:
			hurt_at = now[0]
		if mind.state == AIController.State.CHANNEL:
			held += AiFixture.STEP
			longest = maxf(longest, held)
		else:
			held = 0.0
	return {"telegraphed": telegraphed_at, "hurt": hurt_at, "casts": casts, "held": longest, "lost": start - _world.players[0].health.health, "body": body}


func test_it_telegraphs_before_its_spray_hurts() -> void:
	var out: Dictionary = _fight(55.0)
	var telegraphed: float = out["telegraphed"]
	var hurt: float = out["hurt"]
	check(telegraphed >= 0.0, "it winds up")
	check(hurt > 0.0, "its spray reaches the player")
	var wind_up: float = SPITTER.staffs[0].staff.wind_up
	check(hurt - telegraphed >= wind_up - AiFixture.STEP, "the player is hurt only after a whole telegraph (%.2f s from %.2f s, wind-up %.2f s)" % [hurt, telegraphed, wind_up])


func test_every_pour_comes_after_a_telegraph() -> void:
	# The review, 2026-11-16: a held spray skips its staff's wind-up, so each attack must start with a
	# press that winds up whole: every hold is right after a telegraph.
	_world.players[0].position = Vector2(55.0, 0.0)
	var body: Actor = _spitter()
	var mind: AIController = AiFixture.ai(body)
	var holds: int = 0
	var was: int = -1
	var told: bool = false
	for step in int(10.0 / AiFixture.STEP):
		_world.run(body, 1)
		told = told or mind.is_telegraphing()
		if mind.state == AIController.State.CHANNEL and was != AIController.State.CHANNEL:
			holds += 1
			check(told, "hold %d came after a telegraph" % holds)
			told = false
		was = mind.state
	check(holds >= 3, "it attacks again and again (%d holds in 10 s)" % holds)


func test_it_holds_the_spray_for_a_moment_and_lets_go() -> void:
	var out: Dictionary = _fight(55.0)
	var casts: Array[float] = out["casts"]
	var held: float = out["held"]
	check(held >= 0.5, "it holds the spray down (%.2f s)" % held)
	# Its hold's clock runs at its own pace (`Combat.own_pace`): a few steps' slack.
	check(held <= SPITTER.profile.channel_max + 4.0 * AiFixture.STEP, "for about its profile's hold, no longer (%.2f s)" % held)
	# One press, then poured on while held: several casts close together.
	var close: int = 0
	for i in range(1, casts.size()):
		if casts[i] - casts[i - 1] < 0.5:
			close += 1
	check(close >= 2, "held, it pours on: casts %s" % [casts])
	check(float(out["lost"]) >= 3.0 * float(SPRAY.base_damage), "the player is struck again and again (%.1f lost)" % float(out["lost"]))


func test_it_walks_in_to_spray_range() -> void:
	var out: Dictionary = _fight(220.0, 6.0)
	var body: Actor = out["body"]
	var gap: float = body.position.distance_to(_world.players[0].position)
	check(gap <= SPRAY.ray_length, "from far off it walks in within its spray's reach (%.0f px)" % gap)
	check(float(out["hurt"]) > 0.0, "and sprays the player")


func test_it_backs_off_to_spray_range() -> void:
	_world.players[0].position = Vector2(12.0, 0.0)
	var body: Actor = _spitter()
	var farthest: float = 0.0
	for step in int(3.0 / AiFixture.STEP):
		_world.run(body, 1)
		farthest = maxf(farthest, body.position.distance_to(_world.players[0].position))
	check(farthest >= 24.0, "too close, it steps back off the player before it sprays (%.0f px)" % farthest)
	check(farthest <= SPRAY.ray_length, "and no farther than its spray reaches (%.0f px)" % farthest)


func test_its_telegraph_widens_to_its_cone() -> void:
	_world.players[0].position = Vector2(55.0, 0.0)
	var body: Actor = _spitter()
	_world.with_feel()
	var lane: Sprite2D = null
	for step in 40:
		_world.run(body, 1)
		lane = _world.lanes().call("sprite_of", body.id) as Sprite2D
		if lane != null:
			break
	check(lane != null, "its wind-up shows a lane")
	if lane == null:
		return
	var material: ShaderMaterial = lane.material as ShaderMaterial
	var near: float = float(material.get_shader_parameter(&"telegraph_lane"))
	var far: float = float(material.get_shader_parameter(&"telegraph_lane_end"))
	var spell := CompiledSpell.new()
	spell.carrier = &"spray"
	spell.ray_length = SPRAY.ray_length
	spell.arc = SPRAY.arc
	spell.radius = SPRAY.radius
	var cone: float = Carriers.of(&"spray").lane_radius(spell)
	check(far >= cone and far > near + 8.0, "it widens from %.0f px to the cone's width at its reach (%.0f px, the cone %.0f px)" % [near, far, cone])
	check(lane.region_rect.size.y >= 2.0 * far, "its sprite is tall enough for the far end (%.0f px)" % lane.region_rect.size.y)
	check(is_equal_approx(lane.region_rect.position.y + lane.region_rect.size.y * 0.5, 16.0), "its middle stays on the texture's middle row")
