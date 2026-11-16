extends "res://tests/support/suite.gd"
## Boss plan OB14: the aim lock (decision 26: `AIProfile.aim_lock`, the seconds before release that
## the aim stops following the target, measured against the wind-up its cast has left, so a chill
## moves it; a beat on the lane as it locks) and turns (`AIProfile.turns`: after an attack it turns
## to the foe it aimed at longest ago).
##
## godot --headless --path . --script res://tests/support/run.gd -- res://tests/gameplay/ai/test_ai_aim_lock.gd
const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")

var fx: Fixture
var locks: Array = []


func before_each() -> void:
	fx = Fixture.new(root, 2)
	locks.clear()
	fx.bus.aim_locked.connect(func(caster: int, staff: int) -> void: locks.append([caster, staff]))


func after_each() -> void:
	fx.free_all()


func _profile(lock: float, turns: float = 0.0) -> AIProfile:
	var profile: AIProfile = Fixture.exact().duplicate() as AIProfile
	profile.aim_lock = lock
	profile.turns = turns
	return profile


## An enemy winding up a bolt (0.5 s, `Fixture.WIND_UP`) at the first wizard, 100 px to its right;
## the second wizard far off.
func _winding(lock: float) -> Actor:
	fx.players[0].position = Vector2(100.0, 0.0)
	fx.players[1].position = Vector2(2000.0, 2000.0)
	var body: Actor = fx.staffed_enemy([[&"bolt"]], Vector2.ZERO, _profile(lock))
	for i in 8:
		fx.run(body, 1)
		if body.caster.is_winding(0):
			break
	check(body.caster.is_winding(0), "it winds up")
	return body


func test_with_no_lock_the_aim_follows_until_the_cast_leaves() -> void:
	var body: Actor = _winding(0.0)
	fx.players[0].position = Vector2(0.0, 100.0)
	fx.run(body, 1)
	check(body.aim.dot(Vector2.DOWN) > 0.99, "it turns after its target to the end (%s)" % body.aim)
	check(locks.is_empty(), "and never locks")


func test_a_lock_of_its_last_quarter_second() -> void:
	var body: Actor = _winding(0.25)
	fx.players[0].position = Vector2(0.0, 100.0)
	fx.run(body, 1)
	check(body.aim.dot(Vector2.DOWN) > 0.99, "it follows first (%s)" % body.aim)
	check(locks.is_empty(), "not locked yet (%.3f s left)" % body.caster.wind_left(0))
	while body.caster.wind_left(0) > 0.25:
		fx.run(body, 1)
	fx.run(body, 1)
	check_equal(locks, [[body.id, 0]], "locked once, as its last quarter second starts")
	fx.players[0].position = Vector2(-100.0, 0.0)
	fx.run(body, 1)
	check(body.aim.dot(Vector2.DOWN) > 0.99, "then it commits: it no longer follows (%s)" % body.aim)


func test_a_lock_as_long_as_the_wind_up_locks_at_its_start() -> void:
	var body: Actor = _winding(10.0)
	var first: Vector2 = body.aim
	fx.run(body, 1)
	check_equal(locks.size(), 1, "locked at once")
	fx.players[0].position = Vector2(0.0, 100.0)
	fx.run(body, 2)
	check(body.aim.is_equal_approx(first), "it goes where its lane first showed (%s)" % body.aim)


func test_a_chill_moves_the_lock_with_the_wind_up() -> void:
	# The lock is measured against the wind-up its cast has left in Spells, not the brain's clock.
	var body: Actor = _winding(0.25)
	fx.spells.call("hold_winds", body.id, 0.5)
	for i in int(0.375 / Fixture.STEP):
		fx.run(body, 1)
	check(body.caster.is_winding(0), "its wind-up stretched")
	check(locks.is_empty(), "so the lock has not come, though its own time would have (%.3f s left)" % body.caster.wind_left(0))
	while body.caster.wind_left(0) > 0.25:
		fx.run(body, 1)
	fx.run(body, 1)
	check_equal(locks.size(), 1, "it locks with the wind-up's last quarter second")


func test_the_lane_beats_as_the_aim_locks() -> void:
	fx.with_feel()
	var body: Actor = _winding(0.25)
	var lanes: Node = fx.lanes()
	check(lanes.call("sprite_of", body.id) != null, "its lane shows")
	check_equal(float(lanes.call("beat_of", body.id)), 0.0, "no beat before the lock")
	while locks.is_empty() and body.caster.is_winding(0):
		fx.run(body, 1)
	check(float(lanes.call("beat_of", body.id)) > 0.5, "a beat as it locks")
	var material: ShaderMaterial = (lanes.call("sprite_of", body.id) as Sprite2D).material as ShaderMaterial
	check(float(material.get_shader_parameter(&"telegraph_beat")) > 0.5, "drawn by the lane's shader")


## The targets of the attacks `body` starts over `seconds`, in order.
func _attacked(body: Actor, seconds: float) -> Array[Actor]:
	var out: Array[Actor] = []
	var brain: AIBrain = Fixture.ai(body).brain
	var was: AIBrain.State = brain.state
	for i in int(seconds / Fixture.STEP):
		fx.run(body, 1)
		if brain.state == AIBrain.State.WINDUP and was != AIBrain.State.WINDUP:
			out.append(brain.target as Actor)
		was = brain.state
	return out


func test_turns_take_its_attacks_round_the_party() -> void:
	fx.players[0].position = Vector2(80.0, 0.0)
	fx.players[1].position = Vector2(0.0, 120.0)
	var body: Actor = fx.staffed_enemy([[&"bolt"]], Vector2.ZERO, _profile(0.0, 1.0))
	var targets: Array[Actor] = _attacked(body, 6.0)
	check(targets.size() >= 4, "it attacked a few times (%d)" % targets.size())
	if targets.size() < 4:
		return
	check(targets[0] == fx.players[0], "the nearest first")
	for n in range(1, targets.size()):
		check(targets[n] != targets[n - 1], "then each attack at the one it aimed at longest ago (attack %d)" % n)


func test_without_turns_it_keeps_to_the_nearest() -> void:
	fx.players[0].position = Vector2(80.0, 0.0)
	fx.players[1].position = Vector2(0.0, 120.0)
	var body: Actor = fx.staffed_enemy([[&"bolt"]], Vector2.ZERO, _profile(0.0, 0.0))
	var targets: Array[Actor] = _attacked(body, 6.0)
	check(targets.size() >= 4, "it attacked a few times (%d)" % targets.size())
	for target: Actor in targets:
		check(target == fx.players[0], "always the nearest")


func test_a_turn_waits_for_the_attack_to_end() -> void:
	# Review of OB14: a stand (a phase's transition) ending turns nobody; only an attack over does.
	fx.players[0].position = Vector2(80.0, 0.0)
	fx.players[1].position = Vector2(0.0, 120.0)
	var body: Actor = fx.staffed_enemy([[&"bolt"]], Vector2.ZERO, _profile(0.0, 1.0))
	var brain: AIBrain = Fixture.ai(body).brain
	for i in 8:
		fx.run(body, 1)
		if brain.state == AIBrain.State.WINDUP:
			break
	check(brain.state == AIBrain.State.WINDUP and brain.target == fx.players[0], "it attacks the nearest")
	brain.transition(0.25, null)
	fx.run(body, int(1.0 / Fixture.STEP))
	check(brain.target == fx.players[0], "a transition over: no turn, still the nearest")
