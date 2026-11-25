extends "res://tests/support/suite.gd"
## The AI steers off harmful ground cover (ground cover GC7, docs/milestones/ground-cover.md, rule 8;
## gameplay/ai/brain.gd, "Harmful floor"; gameplay/ai/behaviours/evade.gd): it asks the floor round it
## through the bus (`cover_danger_looked`, a `CoverSight`), never the cover area. An enemy walking to
## its target across a strip of burning grass turns along it and goes round, never stepping in, and
## reaches its target; with the grass at rest it walks straight through. An enemy and a test bot
## standing in burning grass step out of it, target or none, before they fight; one ringed by fire
## walks on as it would; a way is probed through every cell it crosses. A world of its own (tests/gameplay/ai/ai_fixture.gd) with a cover area on
## its bus, laid with the test grass and stepped only to light it.
const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const CoverScript := preload("res://gameplay/cover/cover.gd")
const GRASS: CoverKind = preload("res://tests/core/fixtures/cover_content/cover/test_grass/test_grass.tres")
const BOT_PROFILE: AIProfile = preload("res://bench/bots/bot_profile.tres")

const ROOM: StringName = &"ai_cover_room"
## The room: SIZE (a wall in its last cell fixes it; a room is never under the screen's size), the
## grass over FIELD.
const SIZE: Vector2 = Vector2(480.0, 320.0)
const FIELD: Rect2 = Rect2(0.0, 0.0, 464.0, 304.0)
const BURNING: int = 1

var _world: Fixture
var _cover: CoverScript
## The test grass, burning until frost puts it out and spreading nothing, so a test lights exactly what it means.
var _grass: CoverKind
## How often anyone looked at the floor (`cover_danger_looked`).
var _looks: int = 0


func before_each() -> void:
	_world = Fixture.new(root)
	_looks = 0
	_world.bus.cover_danger_looked.connect(func(_actor: int, _at: Vector2, _reach: float, _sight: CoverSight) -> void: _looks += 1)
	_grass = GRASS.duplicate(true) as CoverKind
	_grass.states[BURNING].spreads = &""
	_grass.states[BURNING].spread_chance = 0.0
	# Frost still puts it out; its wait to ash is gone.
	var rows: Array[CoverTrigger] = []
	for row in _grass.states[BURNING].triggers:
		if row.when != CoverTrigger.When.AFTER:
			rows.append(row)
	_grass.states[BURNING].triggers = rows
	_cover = CoverScript.new()
	_cover.events = _world.bus
	_cover.actors = _world.actors
	_cover.registry = _world.registry
	_cover.sim = Sim.seeded(5)
	_cover.use_kinds([_grass] as Array[CoverKind])
	root.add_child(_cover)
	_world.bus.room_built.emit(ROOM, 0, _layout())
	_world.bus.room_entered.emit(ROOM, 0)
	# The wizard far off unless a test puts it near.
	_world.players[0].position = Vector2(4000.0, 4000.0)


func after_each() -> void:
	_cover.free()
	_world.free_all()


func _layout() -> Node2D:
	var layout := own(Node2D.new()) as Node2D
	var walls := StaticBody2D.new()
	walls.collision_layer = RoomBase.WALL_LAYER
	layout.add_child(walls)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16.0, 16.0)
	shape.shape = rect
	shape.position = SIZE - Vector2(8.0, 8.0)
	walls.add_child(shape)
	var patch := CoverField.new()
	patch.kind = _grass.id
	patch.density = 1.0
	patch.offset_left = FIELD.position.x
	patch.offset_top = FIELD.position.y
	patch.offset_right = FIELD.end.x
	patch.offset_bottom = FIELD.end.y
	layout.add_child(patch)
	return layout


## Set the cells of columns `x0`..`x1` and rows `y0`..`y1` burning (fire on each, one step).
func _burn(x0: int, x1: int, y0: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_world.bus.floor_touched.emit(0, &"fire", CoverSight.middle(Vector2i(x, y)), 0.0, 0)
	_cover.step(Fixture.STEP)


func _burning_at(at: Vector2) -> bool:
	return _cover.state_at(_cover.layout.cell_of(at)) == BURNING


## An enemy with nothing to cast at `at` (it walks into its target, chase), playing by `profile`.
func _walker(at: Vector2, profile: AIProfile = null) -> Actor:
	var data: EnemyBase = Fixture.staffed([])
	var body: Actor = data.scene.instantiate() as Actor
	Fixture.ai(body).profile = profile if profile != null else Fixture.exact()
	body.data = data
	body.position = at
	_world.wire(body)
	root.add_child(body)
	body.ticking = false
	_world.enemies.append(body)
	return body


func test_the_look_marks_only_the_cells_that_harm() -> void:
	var sight := CoverSight.new()
	_cover.look(Vector2(200.0, 100.0), 64.0, sight)
	check_equal(sight.count, 0, "grass at rest harms nobody: nothing marked")
	_burn(12, 13, 6, 6)
	_cover.look(Vector2(200.0, 100.0), 64.0, sight)
	check_equal(sight.count, 2, "the two burning cells")
	check(sight.harms(CoverSight.middle(Vector2i(12, 6))) and sight.harms(CoverSight.middle(Vector2i(13, 6))), "marked where they burn")
	check(not sight.harms(CoverSight.middle(Vector2i(11, 6))), "the grass beside them not")
	check_equal(sight.columns, CoverSight.SIDE, "a window of at most SIDE cells a side")
	_cover.look(Vector2(8.0, 8.0), 24.0, sight)
	check(sight.origin == Vector2i.ZERO and sight.columns == 3 and sight.rows == 3, "clipped to the room's corner")
	check_equal(sight.count, 0, "nothing burns there")
	_world.bus.cover_danger_looked.emit(0, Vector2(200.0, 100.0), 64.0, sight)
	check_equal(sight.count, 2, "asked through the bus, filled at once")


func test_a_way_harms_through_every_cell_it_crosses_a_corner_too() -> void:
	# Regression: probed at points every 8 px, a diagonal clipped a burning cell's corner between two
	# of them and the enemy walked round a fire's end through it.
	_burn(15, 15, 18, 18)
	var sight := CoverSight.new()
	_cover.look(Vector2(250.0, 300.0), 32.0, sight)
	var from := Vector2(251.56, 305.19)
	var way := Vector2(0.62, -0.785).normalized()
	check(not sight.harms(from + way * 8.0), "the point 8 px on is safe (col 16): the old probe saw nothing")
	check(sight.harms_along(from, from + way * 24.0), "the corner of the burning cell on the way counts")
	check(not sight.harms_along(from, from + Vector2(24.0, 0.0)), "along the row below: clear")
	check(not sight.harms_along(CoverSight.middle(Vector2i(15, 18)), CoverSight.middle(Vector2i(15, 18)) + Vector2(0.0, 24.0)), "the cell it starts in does not count")
	check(sight.harms_along(Vector2(200.0, 296.0), Vector2(260.0, 296.0)), "a long way through it")


func test_ash_and_a_room_with_no_cover_mark_nothing() -> void:
	var ash := GRASS.duplicate(true) as CoverKind
	ash.states[BURNING].spreads = &""
	_cover.free()
	_cover = CoverScript.new()
	_cover.events = _world.bus
	_cover.actors = _world.actors
	_cover.registry = _world.registry
	_cover.sim = Sim.seeded(5)
	_cover.use_kinds([ash] as Array[CoverKind])
	root.add_child(_cover)
	_world.bus.room_built.emit(ROOM, 0, _layout())
	_world.bus.room_entered.emit(ROOM, 0)
	_world.bus.floor_touched.emit(0, &"fire", Vector2(200.0, 100.0), 0.0, 0)
	for i in 30:
		_cover.step(Fixture.STEP)
	var sight := CoverSight.new()
	_cover.look(Vector2(200.0, 100.0), 64.0, sight)
	check(_cover.state_at(_cover.layout.cell_of(Vector2(200.0, 100.0))) == 2, "burnt to ash")
	check_equal(sight.count, 0, "ash harms nobody")
	_cover.use_kinds([] as Array[CoverKind])
	_world.bus.room_built.emit(ROOM, 0, _layout())
	_world.bus.room_entered.emit(ROOM, 0)
	_cover.look(Vector2(200.0, 100.0), 64.0, sight)
	check_equal(sight.count, 0, "a room with no cover: every cell safe")


func test_an_enemy_walks_round_burning_grass_to_its_target() -> void:
	# A strip of fire two cells wide across its way, rows 3 to 18 (y 48 to 304), its target beyond.
	_burn(14, 15, 3, 18)
	var body: Actor = _walker(Vector2(120.0, 168.0))
	_world.players[0].position = Vector2(360.0, 168.0)
	var stepped_in: int = 0
	var reached: bool = false
	for i in 300:
		_world.run(body, 1)
		if _burning_at(body.position):
			stepped_in += 1
		if body.position.distance_to(_world.players[0].position) < 24.0:
			reached = true
			break
	check_equal(stepped_in, 0, "never a step in the fire")
	check(reached, "round it to its target (at %s)" % [body.position])
	check(body.position.x > 256.0, "past the strip")
	check(_looks > 0, "it looked through the bus")


func test_with_the_grass_at_rest_it_walks_straight_through() -> void:
	var body: Actor = _walker(Vector2(120.0, 168.0))
	_world.players[0].position = Vector2(360.0, 168.0)
	var most_off: float = 0.0
	for i in 120:
		_world.run(body, 1)
		most_off = maxf(most_off, absf(body.position.y - 168.0))
	check(body.position.x > 256.0, "through the grass")
	check(most_off < 0.5, "straight, no turn (%s px off)" % most_off)


func test_an_enemy_in_burning_grass_steps_out_with_no_target() -> void:
	_burn(10, 14, 8, 12)
	var body: Actor = _walker(Vector2(200.0, 168.0))
	check(_burning_at(body.position), "it stands in the fire")
	var out_at: int = -1
	for i in 32:
		_world.run(body, 1)
		if not _burning_at(body.position):
			out_at = i
			break
	check(out_at >= 0, "out of it within two seconds (at %s)" % [body.position])
	_world.run(body, 16)
	check(not _burning_at(body.position), "and stays out")


func test_an_enemy_in_burning_grass_steps_out_before_it_fights() -> void:
	_burn(10, 14, 8, 12)
	var body: Actor = _world.staffed_enemy([[&"bolt"]], Vector2(200.0, 168.0))
	_world.players[0].position = Vector2(300.0, 168.0)
	var out_at: int = -1
	for i in 32:
		_world.run(body, 1)
		if not _burning_at(body.position):
			out_at = i
			break
	check(out_at >= 0, "out of it first (at %s)" % [body.position])


func test_a_reckless_random_committed_enemy_steps_out_before_it_fights() -> void:
	# Review: at 1.2 the way out lost to a fight boosted by commitment and a teammate's call, and the
	# random swap to the second best took the fight on some decisions.
	_burn(10, 14, 8, 12)
	var reckless: AIProfile = Fixture.exact().duplicate() as AIProfile
	reckless.caution = 0.0
	reckless.commitment = 1.0
	reckless.randomness = 1.0
	reckless.teamwork = 1.0
	var body: Actor = _world.staffed_enemy([[&"bolt"]], Vector2(200.0, 168.0), reckless)
	_world.players[0].position = Vector2(300.0, 168.0)
	var brain: AIBrain = Fixture.ai(body).brain
	var out_at: int = -1
	for i in 32:
		_world.run(body, 1)
		if brain.behaviour != null:
			check_equal(brain.behaviour.name(), "evade" if brain.in_harm else brain.behaviour.name(), "in the fire it only ever evades")
		if not _burning_at(body.position):
			out_at = i
			break
	check(out_at >= 0, "out of it first (at %s)" % [body.position])
	check(not brain.plan_urgent or brain.behaviour.name() != "evade", "walking out is never urgent: a dash would overshoot")


func test_the_count_of_harming_cells_follows_the_state_and_a_restore() -> void:
	var sight := CoverSight.new()
	var at := CoverSight.middle(Vector2i(12, 6))
	_burn(12, 12, 6, 6)
	_cover.look(at, 32.0, sight)
	check_equal(sight.count, 1, "burning: marked")
	_world.bus.floor_touched.emit(0, &"frost", at, 0.0, 0)
	_cover.step(Fixture.STEP)
	_cover.look(at, 32.0, sight)
	check_equal(sight.count, 0, "put out: nothing harms, the look returns at once")
	_burn(12, 12, 6, 6)
	_cover.rebuild_derived()
	_cover.look(at, 32.0, sight)
	check_equal(sight.count, 1, "counted again from the state after a restore")


func test_a_bot_steps_out_of_burning_grass() -> void:
	_burn(10, 14, 8, 12)
	var wizard: Actor = _world.players[0]
	wizard.position = Vector2(200.0, 168.0)
	var brain := AIBrain.new()
	brain.setup(wizard, BOT_PROFILE, 4111)
	var intent := ActorIntent.new()
	var out_at: int = -1
	for i in 32:
		brain.think(Fixture.STEP, intent)
		wizard.position += intent.move.limit_length(1.0) * 80.0 * Fixture.STEP
		if not _burning_at(wizard.position):
			out_at = i
			break
	check(out_at >= 0, "the bot is out of it (at %s)" % [wizard.position])


func test_ringed_by_fire_it_walks_on_as_it_would() -> void:
	_burn(0, 28, 0, 18)
	var body: Actor = _walker(Vector2(120.0, 168.0))
	_world.players[0].position = Vector2(360.0, 168.0)
	_world.run(body, 4)
	check(body.position.x > 120.0, "it walks on toward its target")
	check(absf(body.position.y - 168.0) < 0.5, "no way out, no turn")
