extends "res://tests/support/suite.gd"
## A run's rules as data (run generation RG1, docs/milestones/run-generation.md, "The model"):
## `RunDefinition`, `MapRules`, `KindRule` and `RoomKind`, and `RunContent`'s questions, on made-up
## content. Every problem the validator names is named, and a sound definition has none.
##
## godot --headless --path . --script res://tests/core/test_run_rules.gd

const MadeUpRoom := preload("res://tests/support/made_up_room.gd")

const BIOME: StringName = &"cellar"


func _kind(id: StringName, fill: StringName) -> RoomKind:
	var kind := RoomKind.new()
	kind.id = id
	kind.fill = fill
	return kind


func _room(id: StringName, kinds: Array[StringName], biome: StringName = BIOME) -> RoomBase:
	var room := MadeUpRoom.new()
	room.id = id
	room.biome = biome
	room.kinds = kinds
	return room


func _enemy(id: StringName, min_depth: int = 0, boss: bool = false) -> EnemyBase:
	var enemy := EnemyBase.new()
	enemy.id = id
	enemy.biomes = [BIOME] as Array[StringName]
	enemy.min_depth = min_depth
	enemy.boss = boss
	return enemy


## A cellar with a fight room and a boss room, a rat and a boss.
func _content(with_boss: bool = true) -> RunContent:
	var kinds: Array[Resource] = [_kind(&"fight", RoomKind.FILL_ENEMIES), _kind(&"boss", RoomKind.FILL_BOSS)]
	var rooms: Array[Resource] = [_room(&"hall", [&"fight"] as Array[StringName])]
	var enemies: Array[Resource] = [_enemy(&"rat")]
	if with_boss:
		rooms.append(_room(&"throne", [&"boss"] as Array[StringName]))
		enemies.append(_enemy(&"king", 0, true))
	return RunContent.gather(kinds, rooms, enemies)


## Fights then a boss, 3 to 5 rows deep.
func _rules() -> MapRules:
	var rules := MapRules.new()
	rules.biome = BIOME
	rules.depth_min = 3
	rules.depth_max = 5
	var boss := KindRule.make(&"boss", -1, -1)
	boss.max_per_row = 1
	boss.max_per_run = 1
	rules.kinds = [KindRule.make(&"fight", 0, -2), boss] as Array[KindRule]
	return rules


func _run(rules: MapRules) -> RunDefinition:
	var run := RunDefinition.new()
	run.id = &"cellar_run"
	run.biomes = [rules] as Array[MapRules]
	return run


func _names(problems: PackedStringArray, part: String) -> bool:
	for line: String in problems:
		if line.contains(part):
			return true
	return false


func test_a_sound_definition_has_no_problems() -> void:
	check_equal(_run(_rules()).problems(_content()), PackedStringArray(), "fights then a boss, with content for both")


func test_negative_rows_count_from_the_end() -> void:
	var boss := KindRule.make(&"boss", -1, -1)
	check(boss.takes_row(4, 5) and not boss.takes_row(3, 5), "-1 is the last row of five")
	check(boss.takes_row(2, 3) and not boss.takes_row(1, 3), "-1 is the last row of three")
	var fight := KindRule.make(&"fight", 0, -2)
	check(fight.takes_row(0, 5) and fight.takes_row(3, 5) and not fight.takes_row(4, 5), "0 to -2 is all but the last")


func test_the_pools_follow_biome_and_depth() -> void:
	var content: RunContent = RunContent.gather([], [], [_enemy(&"rat"), _enemy(&"ghoul", 2), _enemy(&"king", 0, true)])
	check_equal(content.enemy_pool(BIOME, 0).size(), 1, "the rat alone at the first room")
	check_equal(content.enemy_pool(BIOME, 2).size(), 2, "the ghoul joins at row 2")
	check_equal(content.enemy_pool(&"attic", 4).size(), 0, "nobody fights in another biome")
	check_equal(content.boss_pool(BIOME, 0).size(), 1, "the king is the boss pool, not the enemy pool")


func test_an_optional_kind_with_no_content_leaves_its_row_out() -> void:
	var rules: MapRules = _rules()
	rules.kinds[1].required = false
	var content: RunContent = _content(false)
	check_equal(_run(rules).problems(content), PackedStringArray(), "no boss: the run ends at its deepest fight")
	check_equal(rules.kept_rows(content, 4), [0, 1, 2] as Array[int], "the boss's row is left out")


func test_a_required_kind_with_no_content_is_a_problem() -> void:
	var problems: PackedStringArray = _run(_rules()).problems(_content(false))
	check(_names(problems, "'boss' is required"), "a required boss with none: %s" % problems)


func test_no_template_for_a_kind_is_named() -> void:
	var content: RunContent = RunContent.gather([_kind(&"fight", RoomKind.FILL_ENEMIES)], [_room(&"hall", [&"fight"] as Array[StringName], &"attic")], [_enemy(&"rat")])
	check(content.cannot_fill(BIOME, &"fight", 0).contains("no cellar room"), "a fight room of another biome is not the cellar's")


func test_an_enemy_too_deep_for_the_first_room_is_named() -> void:
	var content: RunContent = RunContent.gather([_kind(&"fight", RoomKind.FILL_ENEMIES)], [_room(&"hall", [&"fight"] as Array[StringName])], [_enemy(&"ghoul", 1)])
	check(content.cannot_fill(BIOME, &"fight", 0).contains("no enemy"), "nobody fights in the first room")
	check_equal(content.cannot_fill(BIOME, &"fight", 1), "", "the ghoul fights from row 1")


func test_an_unknown_kind_is_named() -> void:
	var rules: MapRules = _rules()
	rules.kinds.append(KindRule.make(&"shop"))
	check(_names(_run(rules).problems(_content()), "'shop': no room kind"), "a rule for a kind there is not")


func test_a_row_no_rule_takes_is_named() -> void:
	var rules: MapRules = _rules()
	rules.kinds[0].last_row = 0
	check(_names(_run(rules).problems(_content()), "no kind rule takes row 1"), "fights in the first row only leave row 1 empty")


func test_ranges_out_of_order_are_named() -> void:
	var rules: MapRules = _rules()
	rules.depth_min = 6
	rules.width_min = 0
	rules.branches_max = 0
	var problems: PackedStringArray = _run(rules).problems(_content())
	check(_names(problems, "depth 6 to 5"), "depth: %s" % problems)
	check(_names(problems, "width 0 to 3"), "width: %s" % problems)
	check(_names(problems, "branches 1 to 0"), "branches: %s" % problems)


func test_too_few_rooms_allowed_in_the_run_is_named() -> void:
	var rules: MapRules = _rules()
	rules.kinds[0].max_per_run = 1
	check(_names(_run(rules).problems(_content()), "max_per_run"), "one fight cannot fill two fight rows")


func test_a_kind_that_may_follow_nothing_before_it_is_named() -> void:
	var rules: MapRules = _rules()
	rules.kinds[1].not_after = [&"fight"] as Array[StringName]
	check(_names(_run(rules).problems(_content()), "not_after"), "a boss that may not follow a fight, after fights only")


func test_a_row_too_wide_to_reach_is_named() -> void:
	var rules: MapRules = _rules()
	rules.width_min = 3
	rules.width_max = 3
	rules.branches_max = 2
	check(_names(_run(rules).problems(_content()), "more than the 1 of row 0"), "one first room leading to 2 at most cannot reach a row of 3")


func test_a_biome_twice_and_an_empty_one_are_named() -> void:
	var run: RunDefinition = _run(_rules())
	run.biomes.append(_rules())
	run.biomes.append(null)
	var problems: PackedStringArray = run.problems(_content())
	check(_names(problems, "biome 'cellar' twice"), "twice: %s" % problems)
	check(_names(problems, "biome 2 is empty"), "empty: %s" % problems)


func test_a_room_kind_with_an_unknown_fill_is_named() -> void:
	var kind: RoomKind = _kind(&"shop", &"wares")
	check_equal(kind.problems().size(), 1, "the fill is named: %s" % kind.problems())


func test_a_template_with_kinds_and_no_biome_is_named() -> void:
	var known: Array[StringName] = [&"fight"]
	check(_names(_room(&"hall", [&"fight"] as Array[StringName], &"").template_problems(known), "names no biome"), "kinds need a biome")
	check(_names(_room(&"hall", [&"fight", &"fight"] as Array[StringName]).template_problems(known), "twice"), "a kind twice")
	check(_names(_room(&"hall", [&"feast"] as Array[StringName]).template_problems(known), "no room kind"), "an unknown kind")
	check_equal(_room(&"hub", [] as Array[StringName], &"").template_problems(known), PackedStringArray(), "a room for no run is fine")


func test_an_enemy_with_a_bad_cost_is_named() -> void:
	var enemy: EnemyBase = _enemy(&"rat")
	enemy.cost = 0
	enemy.biomes.append(BIOME)
	var problems: PackedStringArray = enemy.problems()
	check(_names(problems, "cost is 0"), "the cost: %s" % problems)
	check(_names(problems, "twice"), "the biome twice: %s" % problems)


func test_rows_out_of_order_are_named() -> void:
	var rules: MapRules = _rules()
	rules.kinds[1].first_row = -1
	rules.kinds[1].last_row = -2
	var problems: PackedStringArray = _run(rules).problems(_content())
	check(_names(problems, "the first after the last"), "rows -1 to -2: %s" % problems)


func test_a_required_kind_that_takes_no_row_is_named() -> void:
	var rules: MapRules = _rules()
	var shop := KindRule.make(&"fight", 8, 9)
	rules.kinds.append(shop)
	check(_names(_run(rules).problems(_content()), "takes no row"), "rows 8 and 9 of a map at most 5 deep")


func test_a_row_whose_only_kind_cannot_lead_on_is_named() -> void:
	# The fights may not lead to the boss and nothing else stands in the last row, so the row
	# before it has no line left; one more kind there that may lead on makes it sound again.
	var rules: MapRules = _rules()
	rules.kinds[1].not_after = [&"fight"] as Array[StringName]
	check(_names(_run(rules).problems(_content()), "not_after"), "no fight may lead to the boss")
	var hall := KindRule.make(&"boss", -2, -2)
	hall.max_per_run = 0
	var content: RunContent = _content()
	rules.kinds.append(hall)
	check(not _names(_run(rules).problems(content), "not_after"), "a boss line in the row before leads on: %s" % _run(rules).problems(content))


func test_a_line_capped_in_the_run_limits_its_row() -> void:
	var rules: MapRules = _rules()
	rules.width_min = 3
	rules.width_max = 3
	rules.branches_max = 2
	var only := KindRule.make(&"fight", 1, 1)
	only.max_per_run = 1
	rules.kinds[0].first_row = 0
	rules.kinds[0].last_row = 0
	rules.kinds.insert(1, only)
	rules.kinds.insert(2, KindRule.make(&"fight", 2, -2))
	rules.depth_min = 4
	rules.depth_max = 4
	# Row 1 holds one room at most (its only line, once a run), so it is no wider than the one
	# room before it can reach, and row 2's three are more than that one room leads to.
	var problems: PackedStringArray = _run(rules).problems(_content())
	check(not _names(problems, "row 1 holds"), "row 1 is one room: %s" % problems)
	check(_names(problems, "row 2 holds at least 3 rooms, more than the 1 of row 1"), "the run's cap is the row's: %s" % problems)


func test_a_boss_keeps_to_its_depth() -> void:
	var content: RunContent = RunContent.gather([_kind(&"boss", RoomKind.FILL_BOSS)], [_room(&"throne", [&"boss"] as Array[StringName])], [_enemy(&"king", 5, true)])
	check(content.cannot_fill(BIOME, &"boss", 3).contains("no boss"), "a boss from row 5 is not offered in row 3")
	check_equal(content.cannot_fill(BIOME, &"boss", 5), "", "it is in row 5")


func test_an_enemy_and_a_boss_of_one_id_count_once() -> void:
	var content: RunContent = RunContent.gather([], [], [_enemy(&"broom"), _enemy(&"broom", 0, true)])
	check_equal(content.enemies.size(), 1, "the first folder's, as the game finds it")
	check_equal(content.boss_pool(BIOME, 0).size(), 0, "so no boss of that id")


func test_with_no_room_kinds_every_kind_is_unknown() -> void:
	var content: RunContent = RunContent.gather([], [_room(&"hall", [&"fight"] as Array[StringName])], [_enemy(&"rat")])
	var rules: MapRules = _rules()
	rules.kinds[1].required = false
	check(_names(_run(rules).problems(content), "'boss': no room kind"), "an optional kind no file defines is still named")


## Run generation RG4: a room leads to as many rooms as it has exits, so a kind that leads on needs a
## template with an exit for every way a room may lead (`MapRules.most_ways`); the last row's needs none.
func test_a_kind_that_leads_on_with_too_few_exits_is_named() -> void:
	var kinds: Array[Resource] = [_kind(&"fight", RoomKind.FILL_ENEMIES), _kind(&"boss", RoomKind.FILL_BOSS)]
	var hall := _room(&"hall", [&"fight"] as Array[StringName]) as MadeUpRoom
	var throne := _room(&"throne", [&"boss"] as Array[StringName]) as MadeUpRoom
	var rooms: Array[Resource] = [hall, throne]
	var enemies: Array[Resource] = [_enemy(&"rat"), _enemy(&"king", 0, true)]
	hall.exits = 1
	var content: RunContent = RunContent.gather(kinds, rooms, enemies)
	check_equal(content.exits_of(&"hall"), 1, "the hall's exits are gathered")
	var rules: MapRules = _rules()
	check_equal(rules.most_ways(), 2, "a room may lead to two")
	check(_names(_run(rules).problems(content), "'fight' leads on, but no cellar room"), "one exit for two ways: %s" % _run(rules).problems(content))
	rules.branches_max = 1
	check_equal(_run(rules).problems(content), PackedStringArray(), "one way, one exit")
	rules.branches_max = 2
	rules.width_max = 1
	check_equal(rules.most_ways(), 1, "a row of one room: one way at most")
	check_equal(_run(rules).problems(content), PackedStringArray(), "so one exit is enough")
	hall.exits = 0
	throne.exits = 0
	content = RunContent.gather(kinds, rooms, enemies)
	check(_names(_run(rules).problems(content), "'fight' leads on"), "a fight room with no exit leads nowhere")
	check(not _names(_run(rules).problems(content), "'boss' leads on"), "the boss's room, the last, needs none")
	check(content.templates_for(BIOME, &"fight").size() == 1 and content.templates_for(BIOME, &"fight", 1).is_empty(), "templates_for counts exits")
