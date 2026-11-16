extends "res://tests/support/suite.gd"
## The AI and holes (hub rework HR-H2, docs/milestones/hub-rework.md, "Holes" 5 and 6): it keeps two
## checks apart. Walking sees a room's holes as a prop's ground (`AISight.walk_clear`, `feet_clear`,
## `detour`, the run-up), so it walks round a crack and never into one; the line of fire and cover do
## not (`line_clear`, `shot_clear`, `cover`), so it shoots across a crack and never hides behind one.
## A dodge or a move of its own whose end would be over a hole is not cast. Real cards, the imp's
## scene, stepped by hand.
##
## godot --headless --path . --script res://tests/support/run.gd -- res://tests/gameplay/ai/test_ai_holes.gd
const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")

## A crack across the room, from x 100 to 132.
const CRACK: Rect2 = Rect2(100.0, -360.0, 32.0, 720.0)

var fx: Fixture
var casts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])


func before_each() -> void:
	fx = Fixture.new(root)
	fx.projectiles.set_bounds(Rect2(-640.0, -360.0, 1280.0, 720.0))
	casts = PackedInt32Array([0, 0, 0, 0])


func after_each() -> void:
	fx.free_all()


func _enemy(rows: Array, at: Vector2 = Vector2.ZERO, profile: AIProfile = null) -> Actor:
	var body: Actor = fx.staffed_enemy(rows, at, profile)
	if body.caster != null:
		body.caster.cast_done.connect(func(staff: int, _o: Vector2, _d: Vector2) -> void: casts[staff] += 1)
	return body


## `count` ticks of `body` as the game steps it (its step, then its move, `Actor.tick_step`), then
## the systems.
func _run(body: Actor, count: int) -> void:
	for i in count:
		body.tick_step(Fixture.STEP)
		fx.combat.step(Fixture.STEP)
		fx.projectiles.step(Fixture.STEP)
		fx.spells.call("step", Fixture.STEP)
		fx.board.step(Fixture.STEP)


func test_sight_keeps_walking_and_the_line_of_fire_apart() -> void:
	var mgr: Fixture.ProjectileManagerScript = fx.projectiles
	var from := Vector2(60.0, 0.0)
	var to := Vector2(180.0, 0.0)
	check(AISight.walk_clear(mgr, from, to) and AISight.feet_clear(mgr, from, to), "no holes: a walk is clear")
	mgr.set_holes([CRACK] as Array[Rect2])
	check(AISight.line_clear(mgr, from, to), "a shot flies over the crack")
	check(AISight.shot_clear(mgr, from, to), "nor is the crack cover")
	check(not AISight.walk_clear(mgr, from, to), "a walk across it is not clear")
	check(not AISight.feet_clear(mgr, from, to), "nor are its feet")
	check(AISight.ground_clear(mgr, from, to), "the line of fire's ground check minds no hole")
	check_equal(AISight.cover(mgr, Vector2(80.0, 0.0), Vector2(200.0, 0.0), 48.0), Vector2.ZERO, "nothing to hide behind: a crack is no cover")
	var way: Vector2 = AISight.detour(mgr, Vector2(80.0, 0.0), Vector2(200.0, 0.0), 40.0)
	check(AISight.walk_clear(mgr, Vector2(80.0, 0.0), Vector2(80.0, 0.0) + way * 40.0), "a detour never walks into the crack: %s" % way)


func test_a_run_up_never_starts_over_a_hole() -> void:
	var mgr: Fixture.ProjectileManagerScript = fx.projectiles
	mgr.set_holes([Rect2(-400.0, -360.0, 360.0, 720.0)] as Array[Rect2])
	var spot: Vector2 = AISight.run_up_spot(mgr, Vector2(100.0, 0.0), Vector2(0.0, 0.0), 120.0, 6.0)
	check(spot != Vector2.INF and not mgr.circle_blocked(spot, 6.0, true), "its start stands on the ground: %s" % spot)


func test_an_enemy_shoots_across_a_crack_and_never_walks_into_it() -> void:
	fx.projectiles.set_holes([CRACK] as Array[Rect2])
	fx.players[0].position = Vector2(260.0, 0.0)
	var imp: Actor = _enemy([["fire", "bolt"]], Vector2(0.0, 0.0))
	var deepest: float = -INF
	for i in 120:
		_run(imp, 1)
		deepest = maxf(deepest, imp.global_position.x)
		check(not imp.is_falling(), "it never falls (tick %d)" % i)
	check(casts[0] > 0, "it shoots across the crack: %s" % casts)
	check(deepest < CRACK.position.x, "and never steps into it: %.1f" % deepest)


func test_a_dodge_does_not_dash_into_a_hole() -> void:
	# A corridor of ground between two wide cracks: any dodge off a shot's line runs at a crack.
	fx.projectiles.set_holes([Rect2(-640.0, 12.0, 1280.0, 300.0), Rect2(-640.0, -312.0, 1280.0, 300.0)] as Array[Rect2])
	fx.players[0].position = Vector2(-400.0, 0.0)
	var profile: AIProfile = Fixture.exact().duplicate() as AIProfile
	profile.dodge = 1.0
	var imp: Actor = _enemy([["dash"], ["fire", "bolt"]], Vector2.ZERO, profile)
	_run(imp, 1)
	var before: int = casts[0]
	var dodges: int = 0
	var dashed: int = 0
	for i in 40:
		if i % 6 == 0:
			fx.projectiles.spawn(fx.players[0].id, imp.global_position + Vector2(-150.0, -12.0), Vector2(250.0, 0.0), 2.0, 4.0, Fixture.ProjectileManagerScript.ACTOR_LAYERS)
		_run(imp, 1)
		if Fixture.ai(imp).brain.behaviour != null and Fixture.ai(imp).brain.behaviour.name() == "dodge":
			dodges += 1
			dashed = maxi(dashed, casts[0] - before)
		check(not imp.is_falling(), "it never falls (tick %d): %s" % [i, imp.global_position])
	check(dodges > 0, "it dodges")
	check_equal(dashed, 0, "but its dash is never cast at a crack")
	check(absf(imp.global_position.y) < 12.0, "it stays on the ground between them: %s" % imp.global_position)
