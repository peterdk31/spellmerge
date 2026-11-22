extends "res://tests/support/suite.gd"
## The "Effects: Auto" watcher (gameplay/feel/effects_auto.gd; the owner's choice of 2026-11-21): on
## scripted frame times it takes a row down while frames stay slow and a row up while they stay fast,
## with hysteresis (no flicker near the target, on a hitch or on a machine at the edge of a row), undoes
## a drop that made nothing faster, never counts a slow display's frames as slow, and holds while the
## split screen's budget acts. View only: nothing in the simulation hears it.

const EffectsAutoScript := preload("res://gameplay/feel/effects_auto.gd")
const EffectsQualityScript := preload("res://gameplay/feel/effects_quality.gd")
const SplitBudgetScript := preload("res://gameplay/feel/split_budget.gd")

const SLOW: float = 1.0 / 30.0
const FAST: float = 1.0 / 60.0

const HIGH: int = EffectsQualityScript.Level.HIGH
const MEDIUM: int = EffectsQualityScript.Level.MEDIUM
const LOW: int = EffectsQualityScript.Level.LOW


## `seconds` of frames, each as long as `cost` says for the row drawn (a row's ms: [low, medium, high]);
## the rows the watcher changed to, in order.
static func _play(auto: EffectsAutoScript, cost: Array, seconds: float, hold_rise: bool = false, hold_drop: bool = false) -> Array[int]:
	var changes: Array[int] = []
	var clock: float = 0.0
	while clock < seconds - 0.0001:
		var delta: float = float(cost[int(auto.level)]) / 1000.0
		clock += delta
		if auto.step(delta, hold_rise, hold_drop):
			changes.append(int(auto.level))
	return changes


## The same frame time at every row.
static func _flat(ms: float) -> Array:
	return [ms, ms, ms]


func test_the_targets_are_the_split_budgets() -> void:
	check_equal(EffectsAutoScript.new(false).target, SplitBudgetScript.DESKTOP_TARGET, "desktop: 16.7 ms")
	check_equal(EffectsAutoScript.new(true).target, SplitBudgetScript.WEB_TARGET, "web: 33 ms")
	check_equal(int(EffectsAutoScript.new(false).level), HIGH, "high at first")


func test_slow_frames_step_down_a_row_at_a_time_and_fast_ones_back_up() -> void:
	var auto := EffectsAutoScript.new(false)
	# Each row cheaper, all still slow (a busy fight on a slow machine).
	var heavy: Array = [24.0, 30.0, 40.0]
	check(_play(auto, heavy, 1.8).is_empty(), "slow for under 2 s: no change yet")
	check(_play(auto, heavy, 0.5) == [MEDIUM], "slow for 2 s: one row down")
	check(_play(auto, heavy, 1.5).is_empty(), "the next row waits its own 2 s")
	check(_play(auto, heavy, 1.0) == [LOW], "still slow, and the drop helped: low")
	check(_play(auto, heavy, 10.0).is_empty(), "low stays low")
	# The fight ends: fast at every row.
	var light: Array = _flat(14.0)
	check(_play(auto, light, 4.5).is_empty(), "fast for 4.5 s: no change yet")
	check(_play(auto, light, 2.0) == [MEDIUM], "fast for 5 s: one row up")
	check(_play(auto, light, 5.5) == [HIGH], "and another 5 s: high")
	check(_play(auto, light, 30.0).is_empty(), "high stays high")


func test_frames_near_the_target_or_now_and_then_slow_never_flicker() -> void:
	var auto := EffectsAutoScript.new(false)
	# Vsync's frames: all near the target, a little over and under.
	var changes: Array[int] = []
	for i in 60 * 30:
		if auto.step(FAST * (1.03 if i % 2 == 0 else 0.97)):
			changes.append(int(auto.level))
	check(changes.is_empty(), "frames at the target: high for 30 s (%s)" % [changes])
	# A hitch a second (a room loaded, a burst of shots): the average comes back before 2 s are counted.
	changes.clear()
	for second in 30:
		for i in 60:
			if auto.step(0.25 if i == 0 else FAST):
				changes.append(int(auto.level))
	check(changes.is_empty(), "a hitch a second: no change (%s)" % [changes])
	# Between the shares (over the target, not by a fifth): nothing counted either way.
	auto.reset(MEDIUM as EffectsQualityScript.Level)
	check(_play(auto, _flat(FAST * 1120.0), 30.0).is_empty(), "in the band: medium stays")


func test_a_drop_that_made_nothing_faster_is_undone_and_not_tried_again() -> void:
	# A 40 fps cap the watcher does not know of: 25 ms at every row.
	var auto := EffectsAutoScript.new(false)
	check(_play(auto, _flat(25.0), 60.0) == [MEDIUM, HIGH], "one drop, undone once it is seen to help nothing; then none for a minute")
	# Once frames have been fast, a drop may be tried again.
	check(_play(auto, _flat(14.0), 3.0).is_empty(), "fast for a while: high")
	check(_play(auto, [12.0, 12.0, 30.0], 5.0) == [MEDIUM], "slow again, where a row is cheaper: a row down, and kept")


func test_a_slow_displays_frames_are_not_slow() -> void:
	var auto := EffectsAutoScript.new(false)
	auto.set_floor(1.0 / 50.0)
	check(is_equal_approx(auto.target, 0.02), "a 50 Hz display: 20 ms the target")
	check(_play(auto, _flat(20.0), 60.0).is_empty(), "its frames, at its refresh: high for a minute")
	auto.reset(LOW as EffectsQualityScript.Level)
	check(_play(auto, _flat(20.0), 6.0) == [MEDIUM], "and fast enough to rise")
	auto.set_floor(1.0 / 144.0)
	check_equal(auto.target, SplitBudgetScript.DESKTOP_TARGET, "a faster display: the target as it was")


func test_a_machine_at_the_edge_of_a_row_settles_on_the_lower() -> void:
	var auto := EffectsAutoScript.new(false)
	# Fast at medium, slow at high: each rise drops again, and each next rise waits twice as long.
	var edge: Array = [12.0, 14.0, 33.0]
	var changes: Array[int] = _play(auto, edge, 120.0)
	check(changes.size() >= 4 and changes[0] == MEDIUM and changes[1] == HIGH and changes[2] == MEDIUM, "it tries the higher row (%s)" % [changes])
	check(changes.size() <= 10, "but no more than a few times in two minutes (%d changes)" % changes.size())
	check(auto.rise_wait > EffectsAutoScript.RISE_SECONDS * 2.0, "each try that did not hold waits longer (%.1f s)" % auto.rise_wait)
	check(auto.rise_wait <= EffectsAutoScript.RISE_MOST, "up to the longest")
	# The machine is fast at high now (the busy part is over): a rise that holds halves the wait.
	var waited: float = auto.rise_wait
	check(_play(auto, _flat(14.0), waited + 12.0) == [HIGH], "fast: up once the wait is over")
	check(auto.rise_wait < waited, "a rise that held: the wait shorter again (%.1f s)" % auto.rise_wait)
	auto.reset()
	check_equal(auto.rise_wait, EffectsAutoScript.RISE_SECONDS, "Auto chosen anew: the wait as at first")


func test_held_by_the_split_budget() -> void:
	var auto := EffectsAutoScript.new(false)
	auto.reset(LOW as EffectsQualityScript.Level)
	check(_play(auto, _flat(14.0), 20.0, true).is_empty(), "fast while the split's fallbacks are taken: no rise")
	check(_play(auto, _flat(14.0), 3.5).is_empty(), "let go: the fast frames held back are not counted")
	check(_play(auto, _flat(14.0), 2.0) == [MEDIUM], "up after 5 s of its own")
	check(_play(auto, [12.0, 30.0, 30.0], 10.0, false, true).is_empty(), "slow while the budget can still take a rung: the budget acts, not Auto")
	check(_play(auto, [12.0, 30.0, 30.0], 2.5) == [LOW], "the budget on its last rung: Auto drops")


## The setting reaches no line of the simulation (no hash, no SessionRules, no InputFrame): its names
## appear only in feel, the HUD, core/settings, core/events and the benchmarks.
func test_the_setting_is_the_views_alone() -> void:
	var found: PackedStringArray = []
	for folder: String in ["res://core/actors", "res://core/projectiles", "res://core/spells", "res://core/sim", "res://net", "res://gameplay/actor", "res://gameplay/ai", "res://gameplay/combat", "res://gameplay/coop", "res://gameplay/flow", "res://gameplay/player"]:
		_scan(folder, found)
	check(found.is_empty(), "no simulation script names the setting: %s" % [found])


func _scan(folder: String, found: PackedStringArray) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".gd"):
			var text: String = FileAccess.get_file_as_string(folder.path_join(file))
			for name: String in ["EffectsSetting", "effects_changed", "EffectsAuto", "effects_auto.gd", "set_effects_quality"]:
				if text.contains(name):
					found.append("%s (%s)" % [folder.path_join(file), name])
	for sub in dir.get_directories():
		_scan(folder.path_join(sub), found)
