extends "res://tests/support/suite.gd"
## A biome's pace as data (enemy spawning EA4, docs/milestones/enemy-spawning.md, "The data and how it
## reaches Flow"): `SpawnRules`' costs from a room's scaled budget, its problems, and the map rules
## reporting them to the run's validator.


func _rules(group: float, refill: float, stagger: float = 0.15) -> SpawnRules:
	var rules := SpawnRules.new()
	rules.group_share = group
	rules.refill_share = refill
	rules.stagger = stagger
	return rules


func test_its_costs_are_shares_of_the_scaled_budget() -> void:
	var rules: SpawnRules = _rules(0.35, 0.15)
	check_equal(rules.group_cost(16), 6, "a group: 0.35 of 16, rounded")
	check_equal(rules.refill_cost(16), 2, "the refill: 0.15 of 16, rounded")
	check_equal(rules.group_cost(32), 11, "twice the budget, about twice the group")
	check_equal(rules.refill_cost(32), 5, "and the refill")
	check_equal(rules.group_cost(1), 1, "a group is one cost at least")
	check_equal(rules.refill_cost(1), 0, "and its refill below it")
	var close: SpawnRules = _rules(0.3, 0.29)
	check(close.refill_cost(3) < close.group_cost(3), "rounding never brings the refill up to the group: %d, %d" % [close.refill_cost(3), close.group_cost(3)])


func test_a_sound_pace_has_no_problems() -> void:
	check_equal(_rules(0.35, 0.15).problems(), PackedStringArray(), "the starting values")
	check_equal(_rules(1.0, 0.0, 0.0).problems(), PackedStringArray(), "a whole room at once, no stagger")


func test_each_problem_is_named() -> void:
	check_equal(_rules(0.0, 0.0).problems().size(), 2, "a group share of 0 (and a refill not below it)")
	check_equal(_rules(1.5, 0.1).problems().size(), 1, "a group share above 1")
	check_equal(_rules(NAN, 0.1).problems().size(), 2, "a group share that is no number (and a refill not below it)")
	check_equal(_rules(0.35, -0.1).problems().size(), 1, "a refill share below 0")
	check_equal(_rules(0.35, 0.35).problems().size(), 1, "a refill share not below the group share")
	check_equal(_rules(0.35, 0.5).problems().size(), 1, "a refill share above the group share")
	check_equal(_rules(0.35, 0.15, -1.0).problems().size(), 1, "a stagger below 0")
	check_equal(_rules(0.35, 0.15, INF).problems().size(), 1, "a stagger that is not finite")


## The map rules name their spawns' problems (so the run's validator does), and a copy of the rules
## (a rule change's, RG6) has spawns of its own.
func test_the_map_rules_report_them_and_copy_them() -> void:
	var rules := MapRules.new()
	rules.biome = &"cellar"
	rules.kinds = [KindRule.make(&"fight", 0, -1)] as Array[KindRule]
	rules.spawning = _rules(0.35, 0.5)
	var found: PackedStringArray = rules.problems(RunContent.new())
	var named: bool = false
	for line: String in found:
		named = named or line.begins_with("cellar: spawning: refill_share")
	check(named, "the spawning' problem is named with the biome: %s" % [found])
	var made: MapRules = rules.copied()
	check(made.spawning != null and made.spawning != rules.spawning, "the copy's spawning are its own")
	check_equal(made.spawning.refill_share, 0.5, "and the same")


## The game's runs: each biome of the crypt paces its rooms, and the validator holds it sound.
func test_the_crypt_paces_its_rooms() -> void:
	var crypt: RunDefinition = load("res://content/runs/crypt.tres") as RunDefinition
	check(crypt != null and not crypt.biomes.is_empty() and crypt.biomes[0].spawning != null, "the crypt has spawning")
	if crypt != null and not crypt.biomes.is_empty() and crypt.biomes[0].spawning != null:
		check_equal(crypt.biomes[0].spawning.problems(), PackedStringArray(), "with no problems")
