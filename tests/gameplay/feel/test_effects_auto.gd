extends "res://tests/support/suite.gd"
## The "Effects: Auto" watcher (gameplay/feel/effects_auto.gd; the owner's choice of 2026-11-21): on a
## scripted run of frame times it takes a row down while frames stay slow and a row up while they stay
## fast, with hysteresis (no flicker on frames near the target or on a machine at the edge of a row),
## and Feel draws its row only while the setting is Auto. View only: nothing in the simulation hears it.

const EffectsAutoScript := preload("res://gameplay/feel/effects_auto.gd")
const EffectsQualityScript := preload("res://gameplay/feel/effects_quality.gd")
const SplitBudgetScript := preload("res://gameplay/feel/split_budget.gd")

const SLOW: float = 1.0 / 30.0
const FAST: float = 1.0 / 60.0

const HIGH: int = EffectsQualityScript.Level.HIGH
const MEDIUM: int = EffectsQualityScript.Level.MEDIUM
const LOW: int = EffectsQualityScript.Level.LOW


## `seconds` of frames `delta` long; the rows the watcher changed to, in order.
static func _run(auto: EffectsAutoScript, delta: float, seconds: float, held: bool = false) -> Array[int]:
	var changes: Array[int] = []
	for i in roundi(seconds / delta):
		if auto.step(delta, held):
			changes.append(int(auto.level))
	return changes


func test_the_targets_are_the_split_budgets() -> void:
	check_equal(EffectsAutoScript.new(false).target, SplitBudgetScript.DESKTOP_TARGET, "desktop: 16.7 ms")
	check_equal(EffectsAutoScript.new(true).target, SplitBudgetScript.WEB_TARGET, "web: 33 ms")
	check_equal(int(EffectsAutoScript.new(false).level), HIGH, "high at first")


func test_slow_frames_step_down_a_row_at_a_time_and_fast_ones_back_up() -> void:
	var auto := EffectsAutoScript.new(false)
	check(_run(auto, SLOW, 1.5).is_empty(), "slow for 1.5 s: no change yet")
	check(_run(auto, SLOW, 1.0) == [MEDIUM], "slow for over 2 s: one row down")
	check(_run(auto, SLOW, 1.2).is_empty(), "the next row waits its own 2 s")
	check(_run(auto, SLOW, 1.0) == [LOW], "still slow: low")
	check(_run(auto, SLOW, 10.0).is_empty(), "low stays low")
	# The average takes under a second to come down from 33 ms; then 5 s fast a row.
	check(_run(auto, FAST, 4.5).is_empty(), "fast for 4.5 s: no change yet")
	check(_run(auto, FAST, 2.0) == [MEDIUM], "fast for 5 s: one row up")
	check(_run(auto, FAST, 5.5) == [HIGH], "and another 5 s: high")
	check(_run(auto, FAST, 30.0).is_empty(), "high stays high")


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
	check(_run(auto, FAST * 1.12, 30.0).is_empty(), "in the band: medium stays")


func test_a_machine_at_the_edge_of_a_row_settles_on_the_lower() -> void:
	var auto := EffectsAutoScript.new(false)
	# Fast at medium, slow at high: each rise drops again, and each next rise waits twice as long.
	var changes: Array[int] = []
	for step in 60 * 120:
		var delta: float = SLOW if auto.level == EffectsQualityScript.Level.HIGH else FAST
		if auto.step(delta):
			changes.append(int(auto.level))
	check(changes.size() >= 4 and changes[0] == MEDIUM and changes[1] == HIGH and changes[2] == MEDIUM, "it tries the higher row (%s)" % [changes])
	check(changes.size() <= 10, "but no more than a few times in two minutes (%d changes)" % changes.size())
	check(auto.rise_wait > EffectsAutoScript.RISE_SECONDS * 2.0, "each try that did not hold waits longer (%.1f s)" % auto.rise_wait)
	check(auto.rise_wait <= EffectsAutoScript.RISE_MOST, "up to the longest")
	auto.reset()
	check_equal(auto.rise_wait, EffectsAutoScript.RISE_SECONDS, "Auto chosen anew: the wait as at first")


func test_held_by_the_split_budget_it_does_not_rise_but_still_drops() -> void:
	var auto := EffectsAutoScript.new(false)
	auto.reset(LOW as EffectsQualityScript.Level)
	check(_run(auto, FAST, 20.0, true).is_empty(), "fast while the split's fallbacks are taken: no rise")
	check(_run(auto, FAST, 5.5) == [MEDIUM], "let go: up after 5 s")
	check(_run(auto, SLOW, 2.5, true) == [LOW], "slow while held: still down")


## The setting reaches no line of the simulation (no hash, no SessionRules, no InputFrame): its names
## appear only in feel, the HUD, core/settings and core/events.
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
