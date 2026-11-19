extends "res://tests/support/suite.gd"
## A run's rules as data (run generation RG1, docs/milestones/run-generation.md, "The model";
## connected biomes CB8: the biome map's rules alone, the row map's gone): `RunDefinition`,
## `MapRules`, `KindRule` and `RoomKind`, and `RunContent`'s questions, on made-up content. The
## biome map's own rules are named by tests/gameplay/run/test_biome_generator.gd; here the run's.
const MadeUpRoom := preload("res://tests/support/made_up_room.gd")
const MadeUpBiome := preload("res://tests/support/made_up_biome.gd")

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


## The made-up cellar's run and the problems of it (`RunDefinition.biome_problems`).
func _problems(run: RunDefinition) -> PackedStringArray:
	var biome := MadeUpBiome.new()
	return run.biome_problems(biome.content, biome.shapes)


func test_a_sound_definition_has_no_problems() -> void:
	check_equal(_problems(MadeUpBiome.run()), PackedStringArray(), "the made-up cellar, every kind with its content")


func test_negative_rows_count_from_the_deepest() -> void:
	var boss := KindRule.make(&"boss", -1, -1)
	check(boss.takes_row(4, 5) and not boss.takes_row(3, 5), "-1 is the deepest of five depths")
	check(boss.stands_deepest(), "and the line that takes only it stands deepest")
	var fight := KindRule.make(&"fight", 0, -2)
	check(fight.takes_row(0, 5) and fight.takes_row(3, 5) and not fight.takes_row(4, 5), "0 to -2 is all but the deepest")
	check(not fight.stands_deepest(), "a fight does not")


func test_an_unknown_kind_is_named() -> void:
	var run: RunDefinition = MadeUpBiome.run()
	run.biomes[0].kinds.append(KindRule.make(&"feast"))
	check(_names(_problems(run), "'feast': no room kind"), "a rule for a kind there is not")


func test_a_biome_twice_and_an_empty_one_are_named() -> void:
	var run: RunDefinition = MadeUpBiome.run()
	run.biomes.append(MadeUpBiome.rules())
	run.biomes.append(null)
	var problems: PackedStringArray = _problems(run)
	check(_names(problems, "biome 'cellar' twice"), "twice: %s" % problems)
	check(_names(problems, "biome 2 is empty"), "empty: %s" % problems)


## The start room alone (`MapRules.start_only`, a test's pinned room): only a template hosting its
## kind and what fills it are asked of it.
func test_the_start_room_alone_needs_only_its_room() -> void:
	var rules := MapRules.new()
	rules.biome = BIOME
	rules.rooms_min = 0
	rules.rooms_max = 0
	rules.start_kind = &"fight"
	var run: RunDefinition = _run(rules)
	var content: RunContent = _content()
	check(rules.start_only(), "rooms 0 to 0 is the start room alone")
	check_equal(run.biome_problems(content, {&"hall": MadeUpBiome.room_shape(&"hall", Vector2(640, 384), 0)}), PackedStringArray(), "a fight room with no socket stands alone")
	rules.start_kind = &"shop"
	check(_names(run.biome_problems(content, {}), "'shop' is no room kind"), "a kind there is not is named")
	rules.start_kind = &"fight"
	rules.rooms_min = 1
	check(_names(run.biome_problems(content, {}), "the start room alone is 0 to 0"), "rooms 1 to 0 is named")


func test_the_pools_follow_biome_and_depth() -> void:
	var content: RunContent = RunContent.gather([], [], [_enemy(&"rat"), _enemy(&"ghoul", 2), _enemy(&"king", 0, true)])
	check_equal(content.enemy_pool(BIOME, 0).size(), 1, "the rat alone at the first room")
	check_equal(content.enemy_pool(BIOME, 2).size(), 2, "the ghoul joins at row 2")
	check_equal(content.enemy_pool(&"attic", 4).size(), 0, "nobody fights in another biome")
	check_equal(content.boss_pool(BIOME, 0).size(), 1, "the king is the boss pool, not the enemy pool")


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


func test_an_enemy_and_a_boss_of_one_id_count_once() -> void:
	var content: RunContent = RunContent.gather([], [], [_enemy(&"broom"), _enemy(&"broom", 0, true)])
	check_equal(content.enemies.size(), 1, "the first folder's, as the game finds it")
	check_equal(content.boss_pool(BIOME, 0).size(), 0, "so no boss of that id")


# --- Scaling (run generation RG5) ------------------------------------------------------------

func _near(actual: float, expected: float, message: String) -> void:
	check(is_equal_approx(actual, expected), "%s: %s, not %s" % [message, actual, expected])


func test_a_scale_curve_goes_from_its_start_to_its_end_by_its_easing() -> void:
	var even := ScaleCurve.make(1.0, 3.0)
	_near(even.at(0.0), 1.0, "its start")
	_near(even.at(1.0), 3.0, "its end")
	_near(even.at(0.5), 2.0, "evenly: half way at the middle")
	_near(even.at(-1.0), 1.0, "before the span: its start")
	_near(even.at(2.0), 3.0, "past the span: its end")
	_near(ScaleCurve.make(1.0, 3.0, 2.0).at(0.5), 1.0 + 2.0 * 0.75, "an easing above 1: most of the change early")
	_near(ScaleCurve.make(1.0, 3.0, 0.5).at(0.5), 1.0 + 2.0 * (1.0 - sqrt(0.5)), "below 1: most of it late")
	_near(ScaleCurve.make(2.0, 1.0).at(0.5), 1.5, "a curve may fall")
	check_equal(ScaleCurve.make(1.0, 3.0, 1.5).at(0.3), ScaleCurve.make(1.0, 3.0, 1.5).at(0.3), "the same numbers, the same factor")


func test_a_room_s_scale_is_its_depth_s_factor_times_its_players() -> void:
	var scaling := RunScaling.new()
	scaling.per_depth = ScaleCurve.make(1.0, 2.0)
	scaling.per_player = ScaleCurve.make(1.0, 1.6)
	_near(scaling.room_scale(0, 4, 1), 1.0, "the first room, one player")
	_near(scaling.room_scale(4, 4, 1), 2.0, "the deepest row: the depth's end")
	_near(scaling.room_scale(2, 4, 1), 1.5, "half way down")
	_near(scaling.room_scale(0, 4, 4), 1.6, "four players: the players' end")
	_near(scaling.room_scale(0, 4, 2), 1.2, "each extra player a third of the way")
	_near(scaling.room_scale(4, 4, 4), 3.2, "both multiply")
	_near(scaling.room_scale(0, 4, 0), 1.0, "fewer than one player counts as one")
	_near(scaling.room_scale(0, 4, 9), 1.6, "more than four as four")
	_near(scaling.room_scale(0, 0, 1), 1.0, "a map of one row is its start")
	scaling.per_player = null
	_near(scaling.room_scale(4, 4, 4), 2.0, "no curve for players: players change nothing")
	var rules := MapRules.new()
	rules.scale_depth = 4
	var run: RunDefinition = _run(rules)
	_near(run.biome_room_scale(rules, 4, 4), 1.0, "a run with no scaling is the same everywhere")
	run.scaling = scaling
	_near(run.biome_room_scale(rules, 4, 1), 2.0, "the rules' scale_depth is the depth's end")
	_near(run.biome_room_scale(rules, 9, 1), 2.0, "and a deeper room keeps it")


func test_a_budget_is_scaled_and_rounded_and_one_at_least() -> void:
	check_equal(RunScaling.scaled_budget(16, 1.0), 16, "at 1, the budget")
	check_equal(RunScaling.scaled_budget(16, 1.5), 24, "at 1.5")
	check_equal(RunScaling.scaled_budget(10, 1.26), 13, "rounded")
	check_equal(RunScaling.scaled_budget(1, 0.1), 1, "one at least")


func test_a_bad_scaling_curve_is_named() -> void:
	var run: RunDefinition = MadeUpBiome.run()
	run.scaling = RunScaling.new()
	check_equal(_problems(run), PackedStringArray(), "a scaling with no curves is sound")
	run.scaling.per_depth = ScaleCurve.make(1.0, 2.0, 1.5)
	run.scaling.per_player = ScaleCurve.make(1.0, 1.75)
	check_equal(_problems(run), PackedStringArray(), "sound curves")
	run.scaling.per_depth.end = 0.0
	run.scaling.per_player.easing = NAN
	var problems: PackedStringArray = _problems(run)
	check(_names(problems, "scaling per depth: end 0"), "an end of 0 is named: %s" % problems)
	check(_names(problems, "scaling per player: easing"), "an easing that is no number is named: %s" % problems)
