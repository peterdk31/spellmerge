extends "res://tests/support/suite.gd"
## Boss plan OB14: the AI walks round blocking props (decision 36: a pillar's ground stands in its
## line and its walk as a wall does, for every enemy), and the run-up (a long move that runs its
## caster along, cast from where its line is longest: a wall's foot facing the open room). A room of
## walls and a pillar's ground laid by hand, the bodies moved against them as the game moves them
## (`Actor.move`).
##
## godot --headless --path . --script res://tests/gameplay/ai/test_ai_run_up.gd

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const ImpData: EnemyBase = preload("res://content/enemies/ember_imp/ember_imp.tres")

## An actor id no body has: the pillar's ground is laid under it.
const PILLAR: int = 900
## The room: 800 × 400 inside walls 16 px thick.
const ROOM := Rect2(0.0, 0.0, 800.0, 400.0)

var fx: Fixture


func before_each() -> void:
	fx = Fixture.new(root)
	fx.projectiles.set_bounds(ROOM)
	fx.projectiles.set_walls([
		Rect2(0.0, 0.0, 800.0, 16.0), Rect2(0.0, 384.0, 800.0, 16.0),
		Rect2(0.0, 0.0, 16.0, 400.0), Rect2(784.0, 0.0, 16.0, 400.0)] as Array[Rect2])


func after_each() -> void:
	fx.free_all()


## `count` steps of `body` moved against the walls and the ground, then the systems.
func _walk(body: Actor, count: int) -> void:
	for i in count:
		body.step(Fixture.STEP)
		body.move(Fixture.STEP)
		fx.combat.step(Fixture.STEP)
		fx.projectiles.step(Fixture.STEP)
		fx.spells.call("step", Fixture.STEP)
		fx.board.step(Fixture.STEP)


func _unarmed() -> EnemyBase:
	var data: EnemyBase = ImpData.duplicate() as EnemyBase
	data.staffs = [] as Array[StaffCards]
	data.move_speed = 90.0
	return data


func _behaviour(named: String) -> AIBehaviour:
	for behaviour: AIBehaviour in AIBehaviours.all():
		if behaviour.name() == named:
			return behaviour
	return null


func test_a_pillars_ground_stands_in_the_line_and_the_walk() -> void:
	var from := Vector2(100.0, 200.0)
	var to := Vector2(400.0, 200.0)
	check(AISight.ground_clear(fx.projectiles, from, to) and AISight.walk_clear(fx.projectiles, from, to), "no pillar: clear")
	fx.projectiles.set_footprint(PILLAR, Vector2(250.0, 200.0), Vector2(40.0, 40.0), 0.0)
	check(AISight.line_clear(fx.projectiles, from, to), "a shot's line still sees no wall (it would hit the pillar as a body)")
	check(not AISight.ground_clear(fx.projectiles, from, to), "its ground is in the way")
	check(not AISight.walk_clear(fx.projectiles, from, to), "so the walk is held up")
	check(AISight.ground_clear(fx.projectiles, Vector2(100.0, 100.0), Vector2(400.0, 100.0)), "a line past it is clear")
	var way: Vector2 = AISight.detour(fx.projectiles, from + Vector2(110.0, 0.0), to, 40.0)
	check(absf(way.y) > 0.5, "the way round goes up or down, not into it: %s" % way)
	var run: float = fx.projectiles.clear_run(from, Vector2.RIGHT, 400.0)
	check(absf(run - 130.0) <= 8.0, "a run toward it ends at its ground (%s)" % run)
	check(absf(AISight.run_along(fx.projectiles, from, Vector2.LEFT, 400.0, 10.0) - 74.0) <= 8.0, "and one toward the wall at the wall, less the body's radius (%s)" % AISight.run_along(fx.projectiles, from, Vector2.LEFT, 400.0, 10.0))


func test_an_enemy_walks_round_a_pillar() -> void:
	# Decision 36: the OB8 broom ground into pillars. A chaser with the pillar straight between.
	fx.projectiles.set_footprint(PILLAR, Vector2(250.0, 200.0), Vector2(48.0, 48.0), 0.0)
	var pillar := Rect2(226.0, 176.0, 48.0, 48.0)
	fx.players[0].position = Vector2(420.0, 200.0)
	var body: Actor = fx.imp(Vector2(120.0, 200.0), _unarmed())
	var brain: AIBrain = Fixture.ai(body).brain
	_walk(body, 2)
	check(not brain.ground_clear, "it sees the pillar between")
	var past: bool = false
	for i in int(8.0 / Fixture.STEP):
		_walk(body, 1)
		check(not pillar.grow(-1.0).has_point(body.global_position), "never inside the pillar")
		if body.global_position.x > 300.0:
			past = true
			break
	check(past, "it went round the pillar, not into it (at %s)" % body.global_position)


func test_a_staffed_enemy_flanks_a_pillar_in_its_line() -> void:
	# The line of fire counts the pillar too: it walks round rather than shoot the pillar.
	fx.projectiles.set_footprint(PILLAR, Vector2(250.0, 200.0), Vector2(48.0, 48.0), 0.0)
	fx.players[0].position = Vector2(330.0, 200.0)
	var body: Actor = fx.staffed_enemy([[&"bolt"]], Vector2(170.0, 200.0))
	var brain: AIBrain = Fixture.ai(body).brain
	_walk(body, 2)
	check(not brain.line_clear, "the pillar stands in its line")
	check_equal(brain.behaviour.name() if brain.behaviour != null else "", "flank", "so it flanks")


func _dasher(cards: Array, speed: float = 120.0) -> EnemyBase:
	var data: EnemyBase = Fixture.staffed([cards])
	data.move_speed = speed
	return data


func test_a_long_move_runs_up_to_a_walls_foot_first() -> void:
	# The target in the middle, the enemy close above it: its line down is short, across is long.
	fx.players[0].position = Vector2(400.0, 200.0)
	var body: Actor = fx.imp(Vector2(400.0, 60.0), _dasher([&"reach", &"reach", &"lumber", &"dash"]))
	var brain: AIBrain = Fixture.ai(body).brain
	_walk(body, 1)
	var sense: CastSense = body.caster.next_cast_sense(0)
	check(sense.moves_along and sense.harms(), "a dash with its pass: a move along a line that hurts")
	check(sense.move_reach > 500.0, "a long one (%s px)" % sense.move_reach)
	check(brain.run_here(sense) < sense.move_reach * 0.9, "from here its line is short (%s)" % brain.run_here(sense))
	check_equal(brain.behaviour.name() if brain.behaviour != null else "", "run up", "so it runs up first")
	check(not body.caster.is_winding(0), "and casts nothing yet")
	var cast_from: Vector2 = Vector2.INF
	for i in int(10.0 / Fixture.STEP):
		_walk(body, 1)
		if body.caster.is_winding(0):
			cast_from = body.global_position
			break
	check(cast_from != Vector2.INF, "it casts the move once there")
	if cast_from == Vector2.INF:
		return
	var to_wall: float = minf(minf(cast_from.x - 16.0, 784.0 - cast_from.x), minf(cast_from.y - 16.0, 384.0 - cast_from.y))
	check(to_wall < 60.0, "from a wall's foot (%s, %s px off the wall)" % [cast_from, to_wall])
	check(cast_from.distance_to(Vector2(400.0, 60.0)) > 100.0, "it walked there first (%s)" % cast_from)
	check(brain.run_here(sense) > sense.move_reach * 0.8, "facing the open room: its line from there is long (%s of %s)" % [brain.run_here(sense), sense.move_reach])


func test_a_short_dash_needs_no_run_up() -> void:
	fx.players[0].position = Vector2(400.0, 200.0)
	var body: Actor = fx.imp(Vector2(330.0, 200.0), _dasher([&"dash"]))
	_walk(body, 1)
	var brain: AIBrain = Fixture.ai(body).brain
	check(brain.run_here(body.caster.next_cast_sense(0)) >= body.caster.next_cast_sense(0).move_reach * 0.9, "its line here is as long as it goes")
	check(_behaviour("run up").want(brain) <= 0.0, "no run-up")


func test_a_teleport_never_runs_up() -> void:
	# A jump does not run along its line: only a move that does is worth a run-up.
	fx.players[0].position = Vector2(400.0, 200.0)
	var body: Actor = fx.imp(Vector2(400.0, 60.0), _dasher([&"reach", &"reach", &"teleport"]))
	_walk(body, 1)
	var sense: CastSense = body.caster.next_cast_sense(0)
	check(sense.moves_caster and not sense.moves_along, "a teleport moves its caster, not along")
	check(_behaviour("run up").want(Fixture.ai(body).brain) <= 0.0, "no run-up")
