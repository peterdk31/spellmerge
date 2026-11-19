extends "res://tests/support/suite.gd"
## The split screen's frame-time budget (gameplay/feel/split_budget.gd; connected biomes CB6, decision
## 31: 16.7 ms a frame on the desktop, 33 ms on the web, with four views): over the target while
## split, a rung of CB1's fallbacks at a time; well under, back down; never with one view.
const SplitBudgetScript := preload("res://gameplay/feel/split_budget.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")


## `seconds` of frames `delta` long with `views` views.
static func _run(budget: SplitBudgetScript, delta: float, views: int, seconds: float) -> void:
	for i in int(seconds / delta):
		budget.step(delta, views)


func test_the_targets_are_the_owners() -> void:
	check(is_equal_approx(SplitBudgetScript.new(false).target, 1.0 / 60.0), "desktop: 16.7 ms")
	check(is_equal_approx(SplitBudgetScript.new(true).target, 0.033), "web: 33 ms")


func test_slow_split_frames_step_up_one_rung_at_a_time_and_back_down() -> void:
	var budget := SplitBudgetScript.new(false)
	_run(budget, 0.016, 4, 5.0)
	check_equal(budget.rung, 0, "frames within the target: no fallback")
	check_equal(budget.mote_share(), 1.0, "every mote")
	check_equal(budget.light_downscale(), SpellLightScript.DOWNSCALE, "the light as the first view's")
	_run(budget, 0.025, 4, 1.6)
	check_equal(budget.rung, 1, "over the target a second: the first rung, a cheaper light a view")
	check_equal(budget.light_downscale(), SpellLightScript.DOWNSCALE * 2, "the buffers past the first twice as small again")
	_run(budget, 0.025, 4, 10.0)
	check_equal(budget.rung, SplitBudgetScript.RUNG_MOTES.size() - 1, "still over: the last rung")
	check_equal(budget.mote_share(), 0.25, "a quarter of the motes")
	_run(budget, 0.010, 4, 4.0)
	check_equal(budget.rung, SplitBudgetScript.RUNG_MOTES.size() - 2, "well under for a while: a rung down")


func test_one_view_and_switched_off_change_nothing() -> void:
	var budget := SplitBudgetScript.new(false)
	_run(budget, 0.05, 1, 5.0)
	check_equal(budget.rung, 0, "one picture: no fallback however slow")
	budget.switched_off = true
	_run(budget, 0.05, 4, 5.0)
	check_equal(budget.rung, 0, "switched off: none")
