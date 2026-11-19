extends "res://tests/support/suite.gd"
## Meta progression's hook (run generation RG6, docs/milestones/run-generation.md, "Meta progression
## (RG6)"), as data: a rule change (`RunRuleChange`) names a save flag and one number of the run
## definition it changes; the definition a run plays (`RunDefinition.changed_by`) is a copy of its
## own with the changes the run's unlocks hold applied in order, never the registry's; and a change
## that names nothing, or leaves rules that make no map, is named by the validator. On the made-up
## cellar biome (tests/support/made_up_biome.gd; connected biomes CB8: the row map's depth and width
## targets went with it).
const MadeUpBiome := preload("res://tests/support/made_up_biome.gd")

const BIOME: StringName = MadeUpBiome.BIOME

## The made-up content and shapes (made once: they are read, never changed).
var _biome: MadeUpBiome = MadeUpBiome.new()


## The made-up cellar's run: its first kind line the fights, scaled by depth (1 to 2) and players.
func _run() -> RunDefinition:
	return MadeUpBiome.run()


func _problems(run: RunDefinition) -> PackedStringArray:
	return run.biome_problems(_biome.content, _biome.shapes)


func _generate(run: RunDefinition, seed_value: int) -> BiomeMap:
	return BiomeGenerator.generate(run, _biome.content, _biome.shapes, Sim.seeded(seed_value))


func _unlocks(flags: Array[StringName]) -> RunUnlocks:
	return RunUnlocks.of(flags)


func _names(problems: PackedStringArray, part: String) -> bool:
	for line: String in problems:
		if line.contains(part):
			return true
	return false


func test_with_no_flag_held_the_run_plays_its_own_definition() -> void:
	var run: RunDefinition = _run()
	run.changes = [RunRuleChange.make(&"bigger", RunRuleChange.Target.ROOMS_MAX, 11.0)] as Array[RunRuleChange]
	check(run.changed_by(RunUnlocks.new()) == run, "no unlocks: the definition itself, no copy")
	check(run.changed_by(_unlocks([&"other"] as Array[StringName])) == run, "a flag no change names: itself")
	check(run.changed_by(null) == run, "no unlocks at all: itself")
	check_equal(run.flags(), [&"bigger"] as Array[StringName], "the flags its changes name")


func test_a_held_flag_changes_a_copy_and_never_the_definition() -> void:
	var run: RunDefinition = _run()
	run.changes = [
		RunRuleChange.make(&"bigger", RunRuleChange.Target.ROOMS_MAX, 11.0),
		RunRuleChange.make(&"bigger", RunRuleChange.Target.KIND_WEIGHT, 3.0, RunRuleChange.How.TIMES, BIOME, &"fight"),
		RunRuleChange.make(&"harder", RunRuleChange.Target.SCALE_DEPTH_END, 0.5, RunRuleChange.How.ADD),
	] as Array[RunRuleChange]
	var before: int = SimHash.of(run.biomes[0])
	var played: RunDefinition = run.changed_by(_unlocks([&"bigger"] as Array[StringName]))
	check(played != run, "a copy")
	check_equal(played.id, run.id, "of the same run")
	check_equal(played.biomes[0].rooms_max, 11, "its room count set")
	check(is_equal_approx(played.biomes[0].kinds[0].weight, 3.0), "the fight line's weight times 3")
	check(is_equal_approx(played.scaling.per_depth.end, 2.0), "a flag not held changes nothing")
	check_equal(run.biomes[0].rooms_max, 12, "the definition's room count is its own")
	check(is_equal_approx(run.biomes[0].kinds[0].weight, 1.0), "and its kind rule")
	check_equal(SimHash.of(run.biomes[0]), before, "nothing of the definition changed")
	check(played.biomes[0] != run.biomes[0] and played.biomes[0].kinds[0] != run.biomes[0].kinds[0], "every rule copied")
	var both: RunDefinition = run.changed_by(_unlocks([&"harder", &"bigger"] as Array[StringName]))
	check(is_equal_approx(both.scaling.per_depth.end, 2.5), "the scaling's end raised by 0.5")
	check(is_equal_approx(run.scaling.per_depth.end, 2.0), "the definition's curve its own")
	check(played.scaling != run.scaling and played.scaling.per_depth != run.scaling.per_depth, "the scaling copied")


func test_changes_apply_in_their_order() -> void:
	var run: RunDefinition = _run()
	run.changes = [
		RunRuleChange.make(&"a", RunRuleChange.Target.ROOMS_MIN, 1.0, RunRuleChange.How.ADD),
		RunRuleChange.make(&"b", RunRuleChange.Target.ROOMS_MIN, 2.0, RunRuleChange.How.TIMES),
	] as Array[RunRuleChange]
	var played: RunDefinition = run.changed_by(_unlocks([&"b", &"a"] as Array[StringName]))
	check_equal(played.biomes[0].rooms_min, 18, "(8 + 1) x 2: the definition's order, not the unlocks'")


func test_every_target_changes_its_number() -> void:
	var cases: Array = [
		[RunRuleChange.Target.KIND_WEIGHT, &"fight", func(d: RunDefinition) -> float: return d.biomes[0].kinds[0].weight],
		[RunRuleChange.Target.KIND_MAX_PER_RUN, &"fight", func(d: RunDefinition) -> float: return float(d.biomes[0].kinds[0].max_per_run)],
		[RunRuleChange.Target.SCALE_DEPTH_START, &"", func(d: RunDefinition) -> float: return d.scaling.per_depth.start],
		[RunRuleChange.Target.SCALE_DEPTH_END, &"", func(d: RunDefinition) -> float: return d.scaling.per_depth.end],
		[RunRuleChange.Target.SCALE_PLAYER_START, &"", func(d: RunDefinition) -> float: return d.scaling.per_player.start],
		[RunRuleChange.Target.SCALE_PLAYER_END, &"", func(d: RunDefinition) -> float: return d.scaling.per_player.end],
		# A biome's map (connected biomes CB5).
		[RunRuleChange.Target.ROOMS_MIN, &"", func(d: RunDefinition) -> float: return float(d.biomes[0].rooms_min)],
		[RunRuleChange.Target.ROOMS_MAX, &"", func(d: RunDefinition) -> float: return float(d.biomes[0].rooms_max)],
		[RunRuleChange.Target.FIGHTS_ON_WAY, &"", func(d: RunDefinition) -> float: return float(d.biomes[0].fights_on_way)],
		[RunRuleChange.Target.SCALE_DEPTH, &"", func(d: RunDefinition) -> float: return float(d.biomes[0].scale_depth)],
		[RunRuleChange.Target.KIND_LEAST, &"fight", func(d: RunDefinition) -> float: return float(d.biomes[0].kinds[0].least)],
		[RunRuleChange.Target.KIND_CHANCE, &"fight", func(d: RunDefinition) -> float: return d.biomes[0].kinds[0].chance],
		[RunRuleChange.Target.STYLE_WEIGHT, &"", func(d: RunDefinition) -> float: return d.biomes[0].styles[0].weight, &"long"],
	]
	check_equal(cases.size(), RunRuleChange.Target.size(), "every target has a case")
	for case: Array in cases:
		var run: RunDefinition = _run()
		run.changes = [RunRuleChange.make(&"unlocked", case[0], 4.0, RunRuleChange.How.SET, &"", case[1], case[3] if case.size() > 3 else &"")] as Array[RunRuleChange]
		var getter: Callable = case[2]
		var played: RunDefinition = run.changed_by(_unlocks([&"unlocked"] as Array[StringName]))
		check(is_equal_approx(getter.call(played) as float, 4.0), "%s set to 4" % RunRuleChange.Target.find_key(case[0]))
	var run: RunDefinition = _run()
	run.changes = [RunRuleChange.make(&"round", RunRuleChange.Target.ROOMS_MAX, 0.75, RunRuleChange.How.TIMES)] as Array[RunRuleChange]
	check_equal(run.changed_by(_unlocks([&"round"] as Array[StringName])).biomes[0].rooms_max, 9, "a whole number's result is rounded (12 x 0.75)")


func test_a_scaling_change_on_a_run_without_scaling_starts_from_one() -> void:
	var run: RunDefinition = _run()
	run.scaling = null
	run.changes = [RunRuleChange.make(&"crowd", RunRuleChange.Target.SCALE_PLAYER_END, 0.5, RunRuleChange.How.ADD)] as Array[RunRuleChange]
	var played: RunDefinition = run.changed_by(_unlocks([&"crowd"] as Array[StringName]))
	check(played.scaling != null and played.scaling.per_player != null, "a scaling and its curve made")
	check(is_equal_approx(played.scaling.per_player.end, 1.5) and is_equal_approx(played.scaling.per_player.start, 1.0), "from 1")
	check(played.scaling.per_depth == null, "no other curve")
	check(run.scaling == null, "the definition still has none")
	check_equal(_problems(run), PackedStringArray(), "sound")


func test_the_generator_makes_the_map_of_the_changed_rules() -> void:
	var run: RunDefinition = _run()
	run.changes = [
		RunRuleChange.make(&"big", RunRuleChange.Target.ROOMS_MIN, 11.0),
		RunRuleChange.make(&"big", RunRuleChange.Target.ROOMS_MAX, 11.0),
	] as Array[RunRuleChange]
	check_equal(_problems(run), PackedStringArray(), "the changes are sound")
	var held: RunDefinition = run.changed_by(_unlocks([&"big"] as Array[StringName]))
	for seed_value in 12:
		var plain: BiomeMap = _generate(run, seed_value)
		var changed: BiomeMap = _generate(held, seed_value)
		check(plain.is_made() and changed.is_made(), "seed %d: both made" % seed_value)
		check_equal(changed.rooms(), 12, "seed %d: as many rooms as the change says, and the start room" % seed_value)
		check_equal(SimHash.of(changed), SimHash.of(_generate(run.changed_by(_unlocks([&"big"] as Array[StringName])), seed_value)), "seed %d: the same unlocks, the same map" % seed_value)


func test_a_change_that_names_nothing_is_named() -> void:
	var cases: Dictionary = {
		"names no save flag": RunRuleChange.make(&"", RunRuleChange.Target.ROOMS_MAX, 10.0),
		"not a plain id": RunRuleChange.make(&"a flag", RunRuleChange.Target.ROOMS_MAX, 10.0),
		"is not a number": RunRuleChange.make(&"f", RunRuleChange.Target.ROOMS_MAX, NAN),
		"no biome 'attic'": RunRuleChange.make(&"f", RunRuleChange.Target.ROOMS_MAX, 10.0, RunRuleChange.How.SET, &"attic"),
		"names no kind": RunRuleChange.make(&"f", RunRuleChange.Target.KIND_WEIGHT, 2.0),
		"no kind rule of 'feast'": RunRuleChange.make(&"f", RunRuleChange.Target.KIND_WEIGHT, 2.0, RunRuleChange.How.SET, &"", &"feast"),
		"changes the map, so it names no kind": RunRuleChange.make(&"f", RunRuleChange.Target.ROOMS_MAX, 10.0, RunRuleChange.How.SET, &"", &"fight"),
		"changes the run's scaling": RunRuleChange.make(&"f", RunRuleChange.Target.SCALE_DEPTH_END, 2.0, RunRuleChange.How.SET, BIOME),
	}
	for part: String in cases:
		var run: RunDefinition = _run()
		run.changes = [cases[part]] as Array[RunRuleChange]
		var problems: PackedStringArray = _problems(run)
		check(_names(problems, part), "'%s' is named: %s" % [part, problems])
	var run: RunDefinition = _run()
	run.changes = [null] as Array[RunRuleChange]
	check(_names(_problems(run), "an empty rule change"), "an empty entry is named")


func test_rules_a_flag_leaves_that_make_no_map_are_named() -> void:
	var run: RunDefinition = _run()
	run.changes = [RunRuleChange.make(&"broken", RunRuleChange.Target.ROOMS_MIN, 20.0)] as Array[RunRuleChange]
	var problems: PackedStringArray = _problems(run)
	check(_names(problems, "With broken unlocked") and _names(problems, "rooms 20 to 12"), "a flag alone: %s" % problems)
	# Each alone is sound; together the counts cross.
	run.changes = [
		RunRuleChange.make(&"many", RunRuleChange.Target.ROOMS_MIN, 11.0),
		RunRuleChange.make(&"few", RunRuleChange.Target.ROOMS_MAX, 9.0),
	] as Array[RunRuleChange]
	problems = _problems(run)
	check(_names(problems, "With many, few unlocked") or _names(problems, "With few, many unlocked"), "every flag at once: %s" % problems)
	check(not _names(problems, "With many unlocked:") and not _names(problems, "With few unlocked:"), "and not each alone")
	check_equal(run.biomes[0].rooms_min, 8, "checking changed nothing of the definition")


func test_a_save_names_the_flags_it_holds_among_those_asked() -> void:
	var path: String = "user://test_run_rule_changes.cfg"
	DirAccess.remove_absolute(path)
	var save: SaveFile = SaveFile.new(path)
	var asked: Array[StringName] = [&"deeper", &"harder", &"deeper"]
	check_equal(save.flags_among(asked), [] as Array[StringName], "a new save holds none")
	SaveFile.new(path).set_flag(&"harder")
	SaveFile.new(path).set_flag(&"intro_seen")
	check_equal(save.flags_among(asked), [&"harder"] as Array[StringName], "read again: only an asked flag it holds")
	DirAccess.remove_absolute(path)


## Regression (review of RG6): the played copy has no changes of its own, so the generator's check
## never applies a held change twice (an ADD valid once, not twice, made no map).
func test_a_held_change_is_applied_once_through_the_generator() -> void:
	var run: RunDefinition = _run()
	run.changes = [
		RunRuleChange.make(&"small", RunRuleChange.Target.ROOMS_MIN, -1.0, RunRuleChange.How.ADD),
		RunRuleChange.make(&"small", RunRuleChange.Target.ROOMS_MAX, -3.0, RunRuleChange.How.ADD),
	] as Array[RunRuleChange]
	check_equal(_problems(run), PackedStringArray(), "sound: 7 to 9 rooms with it")
	var played: RunDefinition = run.changed_by(_unlocks([&"small"] as Array[StringName]))
	check(played.changes.is_empty(), "the played copy has no changes left")
	check_equal(run.changes.size(), 2, "the definition keeps its own")
	check_equal(_problems(played), PackedStringArray(), "the played rules are sound as they are")
	for seed_value in 8:
		var map: BiomeMap = _generate(played, seed_value)
		check(map.is_made() and map.rooms() >= 8 and map.rooms() <= 10, "seed %d: made, 7 to 9 rooms and the start room: %s" % [seed_value, map.not_made])
	var scaled: RunDefinition = _run()
	scaled.changes = [RunRuleChange.make(&"x", RunRuleChange.Target.SCALE_DEPTH_END, 2.0, RunRuleChange.How.TIMES)] as Array[RunRuleChange]
	var once: RunDefinition = scaled.changed_by(_unlocks([&"x"] as Array[StringName]))
	_generate(once, 1)
	check(is_equal_approx(once.scaling.per_depth.end, 4.0), "a TIMES change once: 2 x 2")


func test_a_change_past_the_rules_most_is_named() -> void:
	var run: RunDefinition = _run()
	run.changes = [RunRuleChange.make(&"huge", RunRuleChange.Target.ROOMS_MAX, 30.0, RunRuleChange.How.ADD)] as Array[RunRuleChange]
	check(_names(_problems(run), "32 at most"), "a room count past the most")
	run.changes = [RunRuleChange.make(&"steep", RunRuleChange.Target.SCALE_DEPTH_END, 1000.0, RunRuleChange.How.TIMES)] as Array[RunRuleChange]
	check(_names(_problems(run), "scaling per depth: end 2000"), "a scaling factor past the most")
	run.changes = [RunRuleChange.make(&"heavy", RunRuleChange.Target.KIND_WEIGHT, 500.0, RunRuleChange.How.SET, &"", &"fight")] as Array[RunRuleChange]
	check(_names(_problems(run), "its weight is 500"), "a weight past the most")
	run.changes = [RunRuleChange.make(&"crowd", RunRuleChange.Target.KIND_MAX_PER_RUN, 80.0, RunRuleChange.How.SET, &"", &"fight")] as Array[RunRuleChange]
	check(_names(_problems(run), "a limit of 80 a run"), "a limit past the most")
	run.changes = []
	for i in RunUnlocks.MAX_FLAGS + 1:
		run.changes.append(RunRuleChange.make(StringName("f%d" % i), RunRuleChange.Target.ROOMS_MAX, 11.0))
	check(_names(_problems(run), "more than the %d a run's start carries" % RunUnlocks.MAX_FLAGS), "more flags than a run's start carries")
