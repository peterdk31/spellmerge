extends "res://tests/support/suite.gd"
## The imp respects chill and freeze (gameplay/ai reads Combat's `speed_factor`): a chilled imp
## walks and winds up slower, a frozen one stands still and its attack waits, and it goes on
## when the freeze ends.

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const AiScript := preload("res://gameplay/ai/ai.gd")

var fx: Fixture


func before_each() -> void:
	fx = Fixture.new(root, 1)


func after_each() -> void:
	fx.free_all()


func test_a_chilled_imp_walks_slower() -> void:
	fx.players[0].position = Vector2(1000.0, 0.0)
	var free: AiScript = fx.imp()
	free.step(Fixture.STEP)
	var normal: float = free.velocity.length()
	var chilled: AiScript = fx.imp()
	fx.combat.apply_status(0, chilled, &"chill", 3.0, 50.0)
	chilled.step(Fixture.STEP)
	check(normal > 0.0, "the free imp walks")
	check(is_equal_approx(chilled.velocity.length(), normal * 0.5), "50% chill halves the walk")


func test_a_frozen_imp_stands_still() -> void:
	fx.players[0].position = Vector2(1000.0, 0.0)
	var imp: AiScript = fx.imp()
	fx.combat.apply_status(0, imp, &"chill", 3.0, 50.0)
	for i in 3:
		fx.combat.apply_status(0, imp, &"chill", 3.0, 50.0)
	check(fx.combat.has_status(imp, &"freeze"), "frozen")
	imp.step(Fixture.STEP)
	check_equal(imp.velocity, Vector2.ZERO, "it does not walk")


func test_a_frozen_imp_holds_its_attack_and_then_goes_on() -> void:
	var imp: AiScript = fx.imp_facing_player()
	imp.step(Fixture.STEP)
	check(imp.is_telegraphing(), "winding up")
	var before: float = imp.telegraph_progress()
	for i in 3:
		fx.combat.apply_status(0, imp, &"chill", 3.0, 50.0)
	fx.run(imp, 8)
	check_equal(imp.telegraph_progress(), before, "the windup waits while frozen")
	check_equal(fx.projectiles.get_count(), 0, "no shot while frozen")
	var steps: int = 0
	while imp.is_telegraphing() and steps < 60:
		fx.run(imp, 1)
		steps += 1
	check(steps > 16 - 8, "it waited out the freeze")
	check(not imp.is_telegraphing(), "after the thaw the windup ended")
	check_equal(fx.projectiles.get_count(), 1, "and the shot left")


func test_a_chilled_windup_takes_longer() -> void:
	var slow: AiScript = fx.imp_facing_player()
	fx.combat.apply_status(0, slow, &"chill", 30.0, 50.0)
	slow.step(Fixture.STEP)
	fx.run(slow, int(slow.windup_time / Fixture.STEP) + 1)
	check(slow.is_telegraphing(), "still winding up after the normal windup time")
	fx.run(slow, int(slow.windup_time / Fixture.STEP))
	check(not slow.is_telegraphing(), "done after about twice as long")
