extends "res://tests/support/suite.gd"
## Tests for the run stats (connected biomes CB10, core/base/run_stats.gd): a stat's base; the run's
## rule changes, then a player's relics, each in order; held to the row's range and rounded when
## whole; an unknown stat; a run rule change of the `RUN_STAT` target becomes a stat change, changes
## no map, and is checked (`RunRuleChange.problems`); a run definition gives the changes its
## unlocks hold (`stat_changes_by`); a relic's own problems.


func _relic(changes: Array[StatChange]) -> RelicBase:
	var made := RelicBase.new()
	made.id = &"test_relic"
	made.stat_changes = changes
	return made


func test_a_stat_is_its_base_with_no_change() -> void:
	check_equal(RunStats.value_of(&"reward_choices"), 2.0, "pick 1 of 2 (decision 17)")
	check_equal(RunStats.whole_of(&"start_coins"), 0, "no coins to start with")
	check_equal(RunStats.value_of(&"price_scale"), 1.0, "prices as they are")
	for stat: StringName in RunStats.names():
		check(RunStats.has(stat), "%s is a row" % stat)


func test_the_runs_changes_come_first_then_the_relics_each_in_order() -> void:
	var run: Array[StatChange] = [StatChange.make(&"start_coins", 10.0), StatChange.make(&"start_coins", 2.0, StatChange.How.TIMES)]
	check_equal(RunStats.whole_of(&"start_coins", run), 20, "(0 + 10) * 2")
	var relics: Array[Resource] = [_relic([StatChange.make(&"start_coins", 5.0)] as Array[StatChange])]
	check_equal(RunStats.whole_of(&"start_coins", run, relics), 25, "the relic after the run's changes")
	var setter: Array[Resource] = [_relic([StatChange.make(&"start_coins", 3.0, StatChange.How.SET)] as Array[StatChange])]
	check_equal(RunStats.whole_of(&"start_coins", run, setter), 3, "a relic that sets the number has the last word")
	check_equal(RunStats.whole_of(&"reward_choices", run, relics), 2, "a change of another stat changes nothing")


func test_a_stat_is_held_to_its_range_and_whole_numbers_round() -> void:
	var many: Array[StatChange] = [StatChange.make(&"reward_choices", 40.0)]
	check_equal(RunStats.whole_of(&"reward_choices", many), 4, "at most 4 choices")
	var none: Array[StatChange] = [StatChange.make(&"reward_choices", -9.0)]
	check_equal(RunStats.whole_of(&"reward_choices", none), 1, "at least 1")
	var part: Array[StatChange] = [StatChange.make(&"reward_choices", 0.6)]
	check_equal(RunStats.value_of(&"reward_choices", part), 3.0, "a whole stat rounds")
	var scale: Array[StatChange] = [StatChange.make(&"price_scale", 0.75, StatChange.How.TIMES)]
	check_equal(RunStats.value_of(&"price_scale", scale), 0.75, "a stat that is not whole keeps its part")


func test_an_unknown_stat_is_nothing() -> void:
	check_equal(RunStats.value_of(&"no_such_stat"), 0.0, "0, with a warning")
	check(not RunStats.has(&"no_such_stat"), "no row")
	check(not StatChange.make(&"no_such_stat", 1.0).problems("A test").is_empty(), "a change of it is a problem")


func test_a_run_rule_change_of_a_stat_is_a_stat_change_and_no_map_change() -> void:
	var change := RunRuleChange.make(&"richer", RunRuleChange.Target.RUN_STAT, 7.0, RunRuleChange.How.ADD)
	change.stat = &"start_coins"
	check(change.is_stat_target(), "its target is a run stat")
	var made: StatChange = change.as_stat_change()
	check_equal([made.stat, made.how, made.amount], [&"start_coins", StatChange.How.ADD, 7.0], "the same change, as a stat change")
	check(RunRuleChange.make(&"x", RunRuleChange.Target.DEPTH_MAX, 1.0).as_stat_change() == null, "another target makes none")
	var rules := MapRules.new()
	rules.biome = &"crypt"
	rules.depth_max = 5
	var biomes: Array[MapRules] = [rules]
	check(change.apply_to(biomes, null) == null, "it changes no scaling")
	check_equal(rules.depth_max, 5, "nor the map")
	check(change.problems(biomes, "A run").is_empty(), "a known stat is fine: %s" % [change.problems(biomes, "A run")])
	change.stat = &"no_such_stat"
	check(not change.problems(biomes, "A run").is_empty(), "an unknown stat is a problem")
	var map_change := RunRuleChange.make(&"y", RunRuleChange.Target.DEPTH_MAX, 1.0, RunRuleChange.How.ADD, &"crypt")
	map_change.stat = &"start_coins"
	check(not map_change.problems(biomes, "A run").is_empty(), "another target naming a stat is a problem")


func test_a_run_definition_gives_the_stat_changes_its_unlocks_hold() -> void:
	var definition := RunDefinition.new()
	definition.id = &"test_run"
	var held := RunRuleChange.make(&"richer", RunRuleChange.Target.RUN_STAT, 5.0, RunRuleChange.How.ADD)
	held.stat = &"start_coins"
	var other := RunRuleChange.make(&"choosier", RunRuleChange.Target.RUN_STAT, 1.0, RunRuleChange.How.ADD)
	other.stat = &"reward_choices"
	var map_change := RunRuleChange.make(&"richer", RunRuleChange.Target.DEPTH_MAX, 1.0, RunRuleChange.How.ADD)
	definition.changes = [held, other, map_change] as Array[RunRuleChange]
	var made: Array[StatChange] = definition.stat_changes_by(RunUnlocks.of([&"richer"] as Array[StringName]))
	check_equal(made.size(), 1, "only the stat change whose flag is held")
	check_equal([made[0].stat, made[0].amount], [&"start_coins", 5.0], "as it says")
	check(definition.stat_changes_by(RunUnlocks.new()).is_empty(), "none with no flag held")


func test_a_relics_problems() -> void:
	var fine := _relic([StatChange.make(&"reward_choices", 1.0)] as Array[StatChange])
	check(fine.problems().is_empty(), "a relic of known stats is fine")
	var bad := _relic([StatChange.make(&"no_such_stat", 1.0), null] as Array[StatChange])
	bad.id = &""
	check_equal(bad.problems().size(), 3, "no id, an unknown stat and an empty change")
