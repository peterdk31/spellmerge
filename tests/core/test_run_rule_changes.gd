extends "res://tests/support/suite.gd"
## Meta progression's hook (run generation RG6, docs/milestones/run-generation.md, "Meta progression
## (RG6)"), as data: a rule change (`RunRuleChange`) names a save flag and one number of the run
## definition it changes; the definition a run plays (`RunDefinition.changed_by`) is a copy of its
## own with the changes the run's unlocks hold applied in order, never the registry's; and a change
## that names nothing, or leaves rules that make no map, is named by the validator. On made-up
## content.
const MadeUpRoom := preload("res://tests/support/made_up_room.gd")

const BIOME: StringName = &"cellar"


func _kind(id: StringName, fill: StringName) -> RoomKind:
	var kind := RoomKind.new()
	kind.id = id
	kind.fill = fill
	return kind


func _room(id: StringName, kinds: Array[StringName]) -> RoomBase:
	var room := MadeUpRoom.new()
	room.id = id
	room.biome = BIOME
	room.kinds = kinds
	return room


func _enemy(id: StringName, boss: bool = false) -> EnemyBase:
	var enemy := EnemyBase.new()
	enemy.id = id
	enemy.biomes = [BIOME] as Array[StringName]
	enemy.boss = boss
	return enemy


## A cellar with a fight room and a boss room, a rat and a boss.
func _content() -> RunContent:
	var kinds: Array[Resource] = [_kind(&"fight", RoomKind.FILL_ENEMIES), _kind(&"boss", RoomKind.FILL_BOSS)]
	var rooms: Array[Resource] = [_room(&"hall", [&"fight"] as Array[StringName]), _room(&"throne", [&"boss"] as Array[StringName])]
	var enemies: Array[Resource] = [_enemy(&"rat"), _enemy(&"king", true)]
	return RunContent.gather(kinds, rooms, enemies)


## Fights then a boss, 3 to 5 rows deep, scaled by depth.
func _run() -> RunDefinition:
	var rules := MapRules.new()
	rules.biome = BIOME
	rules.depth_min = 3
	rules.depth_max = 5
	var boss := KindRule.make(&"boss", -1, -1)
	boss.max_per_row = 1
	boss.max_per_run = 1
	rules.kinds = [KindRule.make(&"fight", 0, -2), boss] as Array[KindRule]
	rules.styles = [MapStyle.make(&"long", 0.75)] as Array[MapStyle]
	var run := RunDefinition.new()
	run.id = &"cellar_run"
	run.biomes = [rules] as Array[MapRules]
	run.scaling = RunScaling.new()
	run.scaling.per_depth = ScaleCurve.make(1.0, 2.0)
	return run


func _unlocks(flags: Array[StringName]) -> RunUnlocks:
	return RunUnlocks.of(flags)


func _names(problems: PackedStringArray, part: String) -> bool:
	for line: String in problems:
		if line.contains(part):
			return true
	return false


func test_with_no_flag_held_the_run_plays_its_own_definition() -> void:
	var run: RunDefinition = _run()
	run.changes = [RunRuleChange.make(&"deeper", RunRuleChange.Target.DEPTH_MAX, 6.0)] as Array[RunRuleChange]
	check(run.changed_by(RunUnlocks.new()) == run, "no unlocks: the definition itself, no copy")
	check(run.changed_by(_unlocks([&"other"] as Array[StringName])) == run, "a flag no change names: itself")
	check(run.changed_by(null) == run, "no unlocks at all: itself")
	check_equal(run.flags(), [&"deeper"] as Array[StringName], "the flags its changes name")


func test_a_held_flag_changes_a_copy_and_never_the_definition() -> void:
	var run: RunDefinition = _run()
	run.changes = [
		RunRuleChange.make(&"deeper", RunRuleChange.Target.DEPTH_MAX, 6.0),
		RunRuleChange.make(&"deeper", RunRuleChange.Target.KIND_WEIGHT, 3.0, RunRuleChange.How.TIMES, BIOME, &"fight"),
		RunRuleChange.make(&"harder", RunRuleChange.Target.SCALE_DEPTH_END, 0.5, RunRuleChange.How.ADD),
	] as Array[RunRuleChange]
	var before: int = SimHash.of(run.biomes[0])
	var played: RunDefinition = run.changed_by(_unlocks([&"deeper"] as Array[StringName]))
	check(played != run, "a copy")
	check_equal(played.id, run.id, "of the same run")
	check_equal(played.biomes[0].depth_max, 6, "its depth set")
	check(is_equal_approx(played.biomes[0].kinds[0].weight, 3.0), "the fight line's weight times 3")
	check(is_equal_approx(played.scaling.per_depth.end, 2.0), "a flag not held changes nothing")
	check_equal(run.biomes[0].depth_max, 5, "the definition's depth is its own")
	check(is_equal_approx(run.biomes[0].kinds[0].weight, 1.0), "and its kind rule")
	check_equal(SimHash.of(run.biomes[0]), before, "nothing of the definition changed")
	check(played.biomes[0] != run.biomes[0] and played.biomes[0].kinds[0] != run.biomes[0].kinds[0], "every rule copied")
	var both: RunDefinition = run.changed_by(_unlocks([&"harder", &"deeper"] as Array[StringName]))
	check(is_equal_approx(both.scaling.per_depth.end, 2.5), "the scaling's end raised by 0.5")
	check(is_equal_approx(run.scaling.per_depth.end, 2.0), "the definition's curve its own")
	check(played.scaling != run.scaling and played.scaling.per_depth != run.scaling.per_depth, "the scaling copied")


func test_changes_apply_in_their_order() -> void:
	var run: RunDefinition = _run()
	run.changes = [
		RunRuleChange.make(&"a", RunRuleChange.Target.WIDTH_MAX, 1.0, RunRuleChange.How.ADD),
		RunRuleChange.make(&"b", RunRuleChange.Target.WIDTH_MAX, 2.0, RunRuleChange.How.TIMES),
	] as Array[RunRuleChange]
	var played: RunDefinition = run.changed_by(_unlocks([&"b", &"a"] as Array[StringName]))
	check_equal(played.biomes[0].width_max, 8, "(3 + 1) x 2: the definition's order, not the unlocks'")


func test_every_target_changes_its_number() -> void:
	var cases: Array = [
		[RunRuleChange.Target.KIND_WEIGHT, &"fight", func(d: RunDefinition) -> float: return d.biomes[0].kinds[0].weight],
		[RunRuleChange.Target.KIND_MAX_PER_ROW, &"fight", func(d: RunDefinition) -> float: return float(d.biomes[0].kinds[0].max_per_row)],
		[RunRuleChange.Target.KIND_MAX_PER_RUN, &"fight", func(d: RunDefinition) -> float: return float(d.biomes[0].kinds[0].max_per_run)],
		[RunRuleChange.Target.DEPTH_MIN, &"", func(d: RunDefinition) -> float: return float(d.biomes[0].depth_min)],
		[RunRuleChange.Target.DEPTH_MAX, &"", func(d: RunDefinition) -> float: return float(d.biomes[0].depth_max)],
		[RunRuleChange.Target.WIDTH_MIN, &"", func(d: RunDefinition) -> float: return float(d.biomes[0].width_min)],
		[RunRuleChange.Target.WIDTH_MAX, &"", func(d: RunDefinition) -> float: return float(d.biomes[0].width_max)],
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
	# The run stats' target is the one more (connected biomes CB10): it changes a stat, not the map.
	check_equal(cases.size() + 1, RunRuleChange.Target.size(), "every target has a case")
	var stat_run: RunDefinition = _run()
	var stat_change := RunRuleChange.make(&"unlocked", RunRuleChange.Target.RUN_STAT, 4.0)
	stat_change.stat = &"start_coins"
	stat_run.changes = [stat_change] as Array[RunRuleChange]
	check_equal(RunStats.value_of(&"start_coins", stat_run.stat_changes_by(_unlocks([&"unlocked"] as Array[StringName]))), 4.0, "RUN_STAT set to 4")
	check_equal(stat_run.problems(_content()), PackedStringArray(), "a run stat's change is sound")
	for case: Array in cases:
		var run: RunDefinition = _run()
		run.changes = [RunRuleChange.make(&"unlocked", case[0], 4.0, RunRuleChange.How.SET, &"", case[1], case[3] if case.size() > 3 else &"")] as Array[RunRuleChange]
		var getter: Callable = case[2]
		var played: RunDefinition = run.changed_by(_unlocks([&"unlocked"] as Array[StringName]))
		check(is_equal_approx(getter.call(played) as float, 4.0), "%s set to 4" % RunRuleChange.Target.find_key(case[0]))
	var run: RunDefinition = _run()
	run.changes = [RunRuleChange.make(&"round", RunRuleChange.Target.DEPTH_MAX, 1.4, RunRuleChange.How.TIMES)] as Array[RunRuleChange]
	check_equal(run.changed_by(_unlocks([&"round"] as Array[StringName])).biomes[0].depth_max, 7, "a whole number's result is rounded (5 x 1.4)")


func test_a_scaling_change_on_a_run_without_scaling_starts_from_one() -> void:
	var run: RunDefinition = _run()
	run.scaling = null
	run.changes = [RunRuleChange.make(&"crowd", RunRuleChange.Target.SCALE_PLAYER_END, 0.5, RunRuleChange.How.ADD)] as Array[RunRuleChange]
	var played: RunDefinition = run.changed_by(_unlocks([&"crowd"] as Array[StringName]))
	check(played.scaling != null and played.scaling.per_player != null, "a scaling and its curve made")
	check(is_equal_approx(played.scaling.per_player.end, 1.5) and is_equal_approx(played.scaling.per_player.start, 1.0), "from 1")
	check(played.scaling.per_depth == null, "no other curve")
	check(run.scaling == null, "the definition still has none")
	check_equal(run.problems(_content()), PackedStringArray(), "sound")


func test_the_generator_makes_the_map_of_the_changed_rules() -> void:
	var run: RunDefinition = _run()
	run.changes = [
		RunRuleChange.make(&"long", RunRuleChange.Target.DEPTH_MIN, 5.0),
		RunRuleChange.make(&"long", RunRuleChange.Target.WIDTH_MIN, 2.0),
	] as Array[RunRuleChange]
	check_equal(run.problems(_content()), PackedStringArray(), "the changes are sound")
	var held: RunDefinition = run.changed_by(_unlocks([&"long"] as Array[StringName]))
	for seed in 40:
		var plain: RunMap = RunGenerator.generate(run, _content(), Sim.seeded(seed))
		var changed: RunMap = RunGenerator.generate(held, _content(), Sim.seeded(seed))
		check(plain.is_made() and changed.is_made(), "seed %d: both made" % seed)
		check_equal(changed.rows(), 5, "seed %d: as deep as the change says" % seed)
		for row in range(1, changed.rows() - 1):
			check(changed.row(row).size() >= 2, "seed %d: row %d as wide" % [seed, row])
		check_equal(SimHash.of(changed), SimHash.of(RunGenerator.generate(run.changed_by(_unlocks([&"long"] as Array[StringName])), _content(), Sim.seeded(seed))), "seed %d: the same unlocks, the same map" % seed)


func test_a_change_that_names_nothing_is_named() -> void:
	var cases: Dictionary = {
		"names no save flag": RunRuleChange.make(&"", RunRuleChange.Target.DEPTH_MAX, 5.0),
		"not a plain id": RunRuleChange.make(&"a flag", RunRuleChange.Target.DEPTH_MAX, 5.0),
		"is not a number": RunRuleChange.make(&"f", RunRuleChange.Target.DEPTH_MAX, NAN),
		"no biome 'attic'": RunRuleChange.make(&"f", RunRuleChange.Target.DEPTH_MAX, 5.0, RunRuleChange.How.SET, &"attic"),
		"names no kind": RunRuleChange.make(&"f", RunRuleChange.Target.KIND_WEIGHT, 2.0),
		"no kind rule of 'shop'": RunRuleChange.make(&"f", RunRuleChange.Target.KIND_WEIGHT, 2.0, RunRuleChange.How.SET, &"", &"shop"),
		"changes the map, so it names no kind": RunRuleChange.make(&"f", RunRuleChange.Target.DEPTH_MAX, 5.0, RunRuleChange.How.SET, &"", &"fight"),
		"changes the run's scaling": RunRuleChange.make(&"f", RunRuleChange.Target.SCALE_DEPTH_END, 2.0, RunRuleChange.How.SET, BIOME),
	}
	for part: String in cases:
		var run: RunDefinition = _run()
		run.changes = [cases[part]] as Array[RunRuleChange]
		var problems: PackedStringArray = run.problems(_content())
		check(_names(problems, part), "'%s' is named: %s" % [part, problems])
	var run: RunDefinition = _run()
	run.changes = [null] as Array[RunRuleChange]
	check(_names(run.problems(_content()), "an empty rule change"), "an empty entry is named")


func test_rules_a_flag_leaves_that_make_no_map_are_named() -> void:
	var run: RunDefinition = _run()
	run.changes = [RunRuleChange.make(&"broken", RunRuleChange.Target.DEPTH_MIN, 9.0)] as Array[RunRuleChange]
	var problems: PackedStringArray = run.problems(_content())
	check(_names(problems, "With broken unlocked") and _names(problems, "depth 9 to 5"), "a flag alone: %s" % problems)
	# Each alone is sound; together the widths cross.
	run.changes = [
		RunRuleChange.make(&"wide", RunRuleChange.Target.WIDTH_MIN, 2.0),
		RunRuleChange.make(&"narrow", RunRuleChange.Target.WIDTH_MAX, 1.0),
	] as Array[RunRuleChange]
	problems = run.problems(_content())
	check(_names(problems, "With wide, narrow unlocked") or _names(problems, "With narrow, wide unlocked"), "every flag at once: %s" % problems)
	check(not _names(problems, "With wide unlocked:") and not _names(problems, "With narrow unlocked:"), "and not each alone")
	check_equal(run.biomes[0].width_min, 1, "checking changed nothing of the definition")


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
	run.biomes[0].depth_min = 4
	run.changes = [
		RunRuleChange.make(&"short", RunRuleChange.Target.DEPTH_MIN, -1.0, RunRuleChange.How.ADD),
		RunRuleChange.make(&"short", RunRuleChange.Target.DEPTH_MAX, -2.0, RunRuleChange.How.ADD),
	] as Array[RunRuleChange]
	check_equal(run.problems(_content()), PackedStringArray(), "sound: 3 to 3 rows with it")
	var played: RunDefinition = run.changed_by(_unlocks([&"short"] as Array[StringName]))
	check(played.changes.is_empty(), "the played copy has no changes left")
	check_equal(run.changes.size(), 2, "the definition keeps its own")
	check_equal(played.problems(_content()), PackedStringArray(), "the played rules are sound as they are")
	for seed in 10:
		var map: RunMap = RunGenerator.generate(played, _content(), Sim.seeded(seed))
		check(map.is_made() and map.rows() == 3, "seed %d: made, 3 rows deep: %s" % [seed, map.problems])
	var scaled: RunDefinition = _run()
	scaled.changes = [RunRuleChange.make(&"x", RunRuleChange.Target.SCALE_DEPTH_END, 2.0, RunRuleChange.How.TIMES)] as Array[RunRuleChange]
	var once: RunDefinition = scaled.changed_by(_unlocks([&"x"] as Array[StringName]))
	RunGenerator.generate(once, _content(), Sim.seeded(1))
	check(is_equal_approx(once.scaling.per_depth.end, 4.0), "a TIMES change once: 2 x 2")


func test_a_change_past_the_rules_most_is_named() -> void:
	var run: RunDefinition = _run()
	run.changes = [RunRuleChange.make(&"huge", RunRuleChange.Target.DEPTH_MAX, 30.0, RunRuleChange.How.ADD)] as Array[RunRuleChange]
	check(_names(run.problems(_content()), "35; 32 at most"), "a depth past the most")
	run.changes = [RunRuleChange.make(&"wide", RunRuleChange.Target.WIDTH_MAX, 3.0, RunRuleChange.How.TIMES)] as Array[RunRuleChange]
	check(_names(run.problems(_content()), "width up to 9"), "a width past the most")
	run.changes = [RunRuleChange.make(&"steep", RunRuleChange.Target.SCALE_DEPTH_END, 1000.0, RunRuleChange.How.TIMES)] as Array[RunRuleChange]
	check(_names(run.problems(_content()), "scaling per depth: end 2000"), "a scaling factor past the most")
	run.changes = [RunRuleChange.make(&"heavy", RunRuleChange.Target.KIND_WEIGHT, 500.0, RunRuleChange.How.SET, &"", &"fight")] as Array[RunRuleChange]
	check(_names(run.problems(_content()), "its weight is 500"), "a weight past the most")
	run.changes = [RunRuleChange.make(&"crowd", RunRuleChange.Target.KIND_MAX_PER_ROW, 40.0, RunRuleChange.How.SET, &"", &"fight")] as Array[RunRuleChange]
	check(_names(run.problems(_content()), "limits 40 a row"), "a limit past the most")
	run.changes = []
	for i in RunUnlocks.MAX_FLAGS + 1:
		run.changes.append(RunRuleChange.make(StringName("f%d" % i), RunRuleChange.Target.WIDTH_MAX, 3.0))
	check(_names(run.problems(_content()), "more than the %d a run's start carries" % RunUnlocks.MAX_FLAGS), "more flags than a run's start carries")
