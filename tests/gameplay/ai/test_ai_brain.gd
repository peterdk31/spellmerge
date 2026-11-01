extends "res://tests/support/suite.gd"
## The brain (enemy AI AI5, docs/milestones/M2-enemy-ai.md): an enemy plays whatever staffs it
## holds by what each casts next. Real cards from the registry, enemies from the imp's scene with
## staffs made here, stepped by hand.
##
## godot --headless --path . --script res://tests/gameplay/ai/test_ai_brain.gd

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const ImpData: EnemyBase = preload("res://content/enemies/ember_imp/ember_imp.tres")

var fx: Fixture
## Casts per staff of the enemy under test (`Caster.cast_done`).
var casts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])


func before_each() -> void:
	fx = Fixture.new(root)
	casts = PackedInt32Array([0, 0, 0, 0])


func after_each() -> void:
	fx.free_all()


## Enemy data: the imp's body with one plain staff (big pool, no delay) per row of `rows`.
func _data(rows: Array) -> EnemyBase:
	var data: EnemyBase = ImpData.duplicate() as EnemyBase
	data.staffs = [] as Array[StaffCards]
	for row: Array in rows:
		var cards: Array[StringName] = []
		for id: Variant in row:
			cards.append(StringName(str(id)))
		var staff := StaffBase.new()
		staff.slots = cards.size()
		staff.cast_delay = 0.0
		staff.recharge = 0.0
		staff.max_mana = 1000.0
		staff.mana_regen = 1000.0
		data.staffs.append(StaffCards.make(staff, cards))
	return data


## An enemy of `rows` at `at`, playing by `profile` (the exact one when null); its casts counted.
func _enemy(rows: Array, at: Vector2 = Vector2.ZERO, profile: AIProfile = null) -> Actor:
	var body: Actor = ImpData.scene.instantiate() as Actor
	(body.get_node("AIController") as AIController).profile = profile if profile != null else Fixture.exact()
	body.data = _data(rows)
	body.position = at
	fx.wire(body)
	root.add_child(body)
	body.set_physics_process(false)
	fx.enemies.append(body)
	if body.caster != null:
		body.caster.cast_done.connect(func(staff: int, _o: Vector2, _d: Vector2) -> void: casts[staff] += 1)
	return body


func _profile() -> AIProfile:
	return Fixture.exact().duplicate() as AIProfile


func test_it_casts_the_staff_that_reaches() -> void:
	fx.players[0].position = Vector2(200.0, 0.0)
	var imp: Actor = _enemy([["nova"], ["fire", "bolt"]])
	fx.run(imp, 40)
	check(casts[1] > 0, "far off it casts the bolt: %s" % casts)
	check_equal(casts[0], 0, "never the nova, which cannot reach")
	fx.players[0].position = imp.position + Vector2(24.0, 0.0)
	casts = PackedInt32Array([0, 0, 0, 0])
	fx.run(imp, 40)
	check(casts[0] > 0, "close by it casts the nova too: %s" % casts)


func test_the_range_band_follows_its_staffs() -> void:
	# The real imp (fire bolt, 10 mana, 3 a second back): between casts it has time to move.
	fx.players[0].position = Vector2(40.0, 0.0)
	var imp: Actor = fx.imp()
	fx.run(imp, 2)
	var brain: AIBrain = Fixture.ai(imp).brain
	check(brain.band_min > 60.0 and brain.band_max > brain.band_min, "a bolt keeps a range: %.0f-%.0f" % [brain.band_min, brain.band_max])
	fx.run(imp, 80)
	check(imp.position.distance_to(fx.players[0].position) > 55.0, "so it steps back from a wizard too close: %.0f" % imp.position.distance_to(fx.players[0].position))
	# The same body handed a swing: now a rusher.
	imp.caster.set_staff(0, [&"swing"] as Array[StringName])
	fx.players[0].position = imp.position + Vector2(200.0, 0.0)
	fx.run(imp, 30)
	check(brain.band_max < 60.0, "a swing gives a short range: %.0f" % brain.band_max)
	var before: float = imp.position.distance_to(fx.players[0].position)
	fx.run(imp, 20)
	check(imp.position.distance_to(fx.players[0].position) < before - 20.0, "so it walks in")


func test_it_closes_in_with_a_move() -> void:
	fx.players[0].position = Vector2(300.0, 0.0)
	var imp: Actor = _enemy([["swing"], ["dash"]])
	fx.run(imp, 20)
	check(casts[1] > 0, "far off it dashes in: %s" % casts)


func test_it_never_blasts_a_target_inside_its_own_blast() -> void:
	fx.players[0].position = Vector2(12.0, 0.0)
	var profile: AIProfile = _profile()
	profile.caution = 0.0
	var imp: Actor = _enemy([["blast", "bolt"]], Vector2.ZERO, profile)
	fx.players[0].set_physics_process(false)
	var brain: AIBrain = Fixture.ai(imp).brain
	for i in 20:
		# Hold it where it is: the test is about the choice, not the walk away.
		fx.run(imp, 1)
		imp.position = Vector2.ZERO
		check(not brain.is_telegraphing(), "no blast at a wizard 12 px away")
	check_equal(casts[0], 0, "nothing cast")


func test_it_dodges_a_shot() -> void:
	fx.players[0].position = Vector2(2000.0, 0.0)
	var profile: AIProfile = _profile()
	profile.dodge = 1.0
	var imp: Actor = _enemy([["fire", "bolt"]], Vector2.ZERO, profile)
	fx.run(imp, 1)
	fx.projectiles.spawn(fx.players[0].id, Vector2(-150.0, -12.0), Vector2(250.0, 0.0), 2.0, 4.0, Fixture.ProjectileManagerScript.ACTOR_LAYERS)
	var brain: AIBrain = Fixture.ai(imp).brain
	var dodged: bool = false
	for i in 8:
		fx.run(imp, 1)
		if brain.behaviour != null and brain.behaviour.name() == "dodge":
			dodged = true
	check(dodged, "a shot coming makes it dodge")
	check(absf(imp.position.y) > 4.0, "off the shot's line: %s" % imp.position)


func test_it_channels_a_beam_while_the_target_stays() -> void:
	fx.players[0].position = Vector2(60.0, 0.0)
	var profile: AIProfile = _profile()
	profile.channel_max = 1.0
	var imp: Actor = _enemy([["beam"]], Vector2.ZERO, profile)
	var brain: AIBrain = Fixture.ai(imp).brain
	var channelled: int = 0
	for i in 40:
		fx.run(imp, 1)
		if brain.state == AIBrain.State.CHANNEL:
			channelled += 1
			check(imp.intent.is_held(0), "it holds the beam's button while it channels")
	check(channelled > 8 and channelled <= int(1.0 / Fixture.STEP) + 1, "it channels a while, no longer than channel_max: %d steps" % channelled)
	check(not imp.intent.is_held(0) or brain.state == AIBrain.State.CHANNEL, "and lets go after")


func test_it_guards_under_fire() -> void:
	fx.players[0].position = Vector2(150.0, 0.0)
	var guarding: AIProfile = _profile()
	guarding.dodge = 1.0
	var imp: Actor = _enemy([["fire", "bolt"], ["wall"]], Vector2.ZERO, guarding)
	fx.run(imp, 1)
	fx.combat.hit(fx.players[0].id, imp, 1)
	fx.run(imp, 50)
	check_equal(casts[1], 0, "a hit alone calls for no wall: %s" % casts)
	# Shots coming: the wizard fires a stream at it.
	for i in 40:
		if i % 8 == 0:
			fx.projectiles.spawn(fx.players[0].id, imp.position + Vector2(120.0, -12.0), Vector2(-200.0, 0.0), 2.0, 4.0, Fixture.ProjectileManagerScript.ACTOR_LAYERS)
		fx.run(imp, 1)
	check(casts[1] > 0, "under fire, it stands a wall: %s" % casts)


func test_it_opens_with_a_familiar_once() -> void:
	fx.players[0].position = Vector2(150.0, 0.0)
	var imp: Actor = _enemy([["fire", "bolt"], ["familiar"]])
	fx.run(imp, 40)
	check_equal(casts[1], 1, "it makes its familiar once while the last lasts: %s" % casts)


func test_aim_error_and_lead() -> void:
	fx.players[0].position = Vector2(200.0, 0.0)
	var sloppy: AIProfile = _profile()
	sloppy.accuracy = 0.0
	var imp: Actor = _enemy([["fire", "bolt"]], Vector2.ZERO, sloppy)
	var brain: AIBrain = Fixture.ai(imp).brain
	var off: float = 0.0
	for i in 60:
		fx.run(imp, 1)
		if brain.state == AIBrain.State.WINDUP:
			off = maxf(off, absf(imp.aim.angle()))
	check(off > 0.001 and off <= AIBrain.AIM_ERROR + 0.001, "a sloppy aim is off, within the widest error: %.3f" % off)
	fx.free_all()
	fx = Fixture.new(root)
	fx.players[0].position = Vector2(200.0, 0.0)
	fx.players[0].velocity = Vector2(0.0, 100.0)
	var leading: AIProfile = _profile()
	leading.lead = 1.0
	var ahead: Actor = _enemy([["fire", "bolt"]], Vector2.ZERO, leading)
	fx.run(ahead, 1)
	check(ahead.aim.y > 0.2, "it aims ahead of a wizard walking down: %s" % ahead.aim)


func test_one_with_no_staff_only_chases() -> void:
	fx.players[0].position = Vector2(100.0, 0.0)
	var data: EnemyBase = ImpData.duplicate() as EnemyBase
	data.staffs = [] as Array[StaffCards]
	var body: Actor = fx.imp(Vector2.ZERO, data)
	fx.run(body, 2)
	var brain: AIBrain = Fixture.ai(body).brain
	check(brain.behaviour != null and brain.behaviour.name() == "chase", "it chases")
	check(body.velocity.x > 0.0, "toward the wizard")


func test_a_teammates_windup_staggers_the_next() -> void:
	var board := TeamBoard.new()
	board.started(1, 7)
	check_equal(board.beat(1, 7, 1.0), 1.0, "its own windup does not slow it")
	check(board.beat(1, 8, 1.0) < 0.5, "a teammate waits a beat")
	check_equal(board.beat(1, 8, 0.0), 1.0, "unless it has no teamwork")
	board.step(TeamBoard.BEAT)
	check_equal(board.beat(1, 8, 1.0), 1.0, "and only for the beat")
	check_equal(board.beat(2, 8, 1.0), 1.0, "another team is not slowed")


func test_the_ai_view_shows_what_it_does() -> void:
	fx.players[0].position = Vector2(150.0, 0.0)
	var imp: Actor = fx.imp()
	CreatureLook.ai_view = true
	fx.run(imp, 2)
	var words: String = Fixture.look(imp).ai_view_text()
	CreatureLook.ai_view = false
	check(words.begins_with("fight"), "the AI view names its behaviour and step: %s" % words)
	fx.run(imp, 1)
	check_equal(Fixture.look(imp).ai_view_text(), "", "nothing once it is off")
