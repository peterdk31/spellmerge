extends "res://tests/support/suite.gd"
## The imp respects chill and freeze (Combat's `pace`: the imp's Mover slows its walk by it and its
## AIController its windup): a chilled imp walks and winds up slower, a frozen one stands still and
## its attack waits, and it goes on when the freeze ends.

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")

var fx: Fixture


func before_each() -> void:
	fx = Fixture.new(root, 1)


func after_each() -> void:
	fx.free_all()


func test_a_chilled_imp_walks_slower() -> void:
	fx.players[0].position = Vector2(1000.0, 0.0)
	var free: Actor = fx.imp()
	free.step(Fixture.STEP)
	var normal: float = free.velocity.length()
	var chilled: Actor = fx.imp()
	fx.combat.apply_status(0, chilled, &"chill", 3.0, 50.0)
	chilled.step(Fixture.STEP)
	check(normal > 0.0, "the free imp walks")
	check(is_equal_approx(chilled.velocity.length(), normal * 0.5), "50% chill halves the walk")


func test_a_frozen_imp_stands_still() -> void:
	fx.players[0].position = Vector2(1000.0, 0.0)
	var imp: Actor = fx.imp()
	for i in 3:
		fx.combat.apply_status(0, imp, &"chill", 3.0, 50.0)
	check(fx.combat.has_status(imp, &"freeze"), "frozen")
	imp.step(Fixture.STEP)
	check_equal(imp.velocity, Vector2.ZERO, "it does not walk")


func test_a_frozen_imp_holds_its_attack_and_then_goes_on() -> void:
	var imp: Actor = fx.imp_facing_player()
	imp.step(Fixture.STEP)
	check(Fixture.ai(imp).is_telegraphing(), "winding up")
	var before: float = Fixture.ai(imp).telegraph_progress()
	for i in 3:
		fx.combat.apply_status(0, imp, &"chill", 3.0, 50.0)
	fx.run(imp, 8)
	check_equal(Fixture.ai(imp).telegraph_progress(), before, "the windup waits while frozen")
	check_equal(fx.projectiles.get_count(), 0, "no shot while frozen")
	var steps: int = 0
	while Fixture.ai(imp).is_telegraphing() and steps < 60:
		fx.run(imp, 1)
		steps += 1
	var frozen_steps: int = int(CombatScript.FREEZE_TIME / Fixture.STEP) - 8
	var windup_steps: int = ceili(Fixture.ai(imp).windup_time * (1.0 - before) / Fixture.STEP)
	check(absi(steps - (frozen_steps + windup_steps)) <= 2, "it waited out the freeze, then the rest of the windup")
	check(not Fixture.ai(imp).is_telegraphing(), "after the thaw the windup ended")
	check_equal(fx.projectiles.get_count(), 1, "and the shot left")


func test_a_chilled_windup_takes_longer() -> void:
	var slow: Actor = fx.imp_facing_player()
	fx.combat.apply_status(0, slow, &"chill", 30.0, 50.0)
	slow.step(Fixture.STEP)
	fx.run(slow, int(Fixture.ai(slow).windup_time / Fixture.STEP) + 1)
	check(Fixture.ai(slow).is_telegraphing(), "still winding up after the normal windup time")
	fx.run(slow, int(Fixture.ai(slow).windup_time / Fixture.STEP))
	check(not Fixture.ai(slow).is_telegraphing(), "done after about twice as long")
