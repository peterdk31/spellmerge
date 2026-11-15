extends "res://tests/support/suite.gd"
## The run's map generator (run generation RG2, docs/milestones/run-generation.md, "The
## generator"): thousands of seeds through every rule, on the crypt run as the registry finds it
## and on made-up runs that push each rule (wide rows, many branches, at least two branches, kinds
## limited per row and per run, a kind that may not follow another); the same seed gives the same
## map; deleting any room, enemy or boss still gives a valid map or names what is missing; and the
## map is state (walked without problems, hashed, saved and restored by a snapshot).
##
## godot --headless --path . --script res://tests/gameplay/run/test_run_generator.gd
##
## The seeds take seconds a run: the runner plays the tests in processes of their own (tests/support/suite.gd):
# unit-test-shards: 3

const MadeUpRoom := preload("res://tests/support/made_up_room.gd")

const RegistryScript := preload("res://core/registry/registry.gd")

const BIOME: StringName = &"cellar"
## Seeds each made-up run is generated from, and the crypt run.
const SEEDS: int = 1000

var _registry: RegistryScript = null


func before_each() -> void:
	_registry = own(RegistryScript.new()) as RegistryScript
	_registry.scan()


# --- Made-up content -------------------------------------------------------------------------

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


func _enemy(id: StringName, cost: int, min_depth: int = 0, boss: bool = false) -> EnemyBase:
	var enemy := EnemyBase.new()
	enemy.id = id
	enemy.biomes = [BIOME] as Array[StringName]
	enemy.cost = cost
	enemy.min_depth = min_depth
	enemy.boss = boss
	return enemy


## A cellar of three fight halls, two that also host a trap, a boss throne; rats, wolves from row
## 1, an ogre from row 2, and a king.
func _content() -> RunContent:
	var kinds: Array[Resource] = [_kind(&"fight", RoomKind.FILL_ENEMIES), _kind(&"trap", RoomKind.FILL_ENEMIES), _kind(&"boss", RoomKind.FILL_BOSS)]
	var rooms: Array[Resource] = [
		_room(&"hall_a", [&"fight", &"trap"] as Array[StringName]),
		_room(&"hall_b", [&"fight"] as Array[StringName]),
		_room(&"hall_c", [&"fight", &"trap"] as Array[StringName]),
		_room(&"throne", [&"boss"] as Array[StringName]),
	]
	var enemies: Array[Resource] = [_enemy(&"rat", 1), _enemy(&"wolf", 3, 1), _enemy(&"ogre", 7, 2), _enemy(&"king", 10, 0, true)]
	return RunContent.gather(kinds, rooms, enemies)


func _rules(depth_min: int, depth_max: int, width_min: int, width_max: int, branches_min: int, branches_max: int) -> MapRules:
	var rules := MapRules.new()
	rules.biome = BIOME
	rules.depth_min = depth_min
	rules.depth_max = depth_max
	rules.width_min = width_min
	rules.width_max = width_max
	rules.branches_min = branches_min
	rules.branches_max = branches_max
	rules.room_budget = 9
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


## Made-up runs, each pushing a rule.
func _made_up_runs() -> Dictionary:
	var runs: Dictionary = {}
	runs["plain"] = _run(_rules(4, 6, 1, 3, 1, 2))
	runs["wide"] = _run(_rules(3, 8, 2, 5, 1, 3))
	runs["two ways at least"] = _run(_rules(4, 6, 1, 4, 2, 3))
	runs["one room a row"] = _run(_rules(2, 3, 1, 1, 1, 1))
	var traps := _rules(5, 7, 1, 4, 1, 2)
	var trap := KindRule.make(&"trap", 1, -2, 0.5)
	trap.max_per_row = 1
	trap.max_per_run = 2
	trap.not_after = [&"trap"] as Array[StringName]
	traps.kinds.append(trap)
	runs["traps, one a row, two a run, never one after another"] = _run(traps)
	runs["scaled steeply with depth and players"] = _scaled(_run(_rules(4, 6, 1, 3, 1, 2)))
	return runs


## `run` grown three times harder to its deepest row, most of it early, and twice with four players,
## most of it late (run generation RG5).
func _scaled(run: RunDefinition) -> RunDefinition:
	run.scaling = RunScaling.new()
	run.scaling.per_depth = ScaleCurve.make(1.0, 3.0, 2.0)
	run.scaling.per_player = ScaleCurve.make(1.0, 2.0, 0.5)
	return run


# --- The rules every map keeps ---------------------------------------------------------------

## What is wrong with `map` against `definition`'s rules and `content`, one line each.
func _broken(map: RunMap, definition: RunDefinition, content: RunContent) -> PackedStringArray:
	var found := PackedStringArray()
	var rules: MapRules = definition.biomes[0]
	if not map.is_made():
		found.append("not made: %s" % "; ".join(map.problems))
		return found
	if map.biome != rules.biome or map.run != definition.id:
		found.append("the map names run %s, biome %s" % [map.run, map.biome])
	var deepest: int = map.nodes[map.nodes.size() - 1].depth
	if deepest >= rules.depth_max:
		found.append("its last row stands for row %d, past %d rows deep" % [deepest, rules.depth_max])
	if map.rows() < 1 or map.row(0).size() != 1:
		found.append("its first row is not one room")
	var made_at: Array[int] = _made_at(map, rules, content)
	if made_at.is_empty():
		found.append("its rows %s are those of no depth the rules allow" % _depths(map))
	var per_run: Dictionary = {}
	var last_depth: int = -1
	for at in map.rows():
		var here: Array[RunNode] = map.row(at)
		if here.is_empty():
			found.append("row %d is empty" % at)
			continue
		if here[0].depth <= last_depth:
			found.append("row %d stands for row %d, not after the row before's %d" % [at, here[0].depth, last_depth])
		last_depth = here[0].depth
		if at > 0 and here.size() > rules.width_max:
			found.append("row %d holds %d rooms, more than %d" % [at, here.size(), rules.width_max])
		if at > 0 and here.size() < mini(rules.width_min, map.row(at - 1).size() * rules.branches_max) and not _limited(rules):
			found.append("row %d holds %d rooms, fewer than %d" % [at, here.size(), rules.width_min])
		if at == map.rows() - 1:
			for node: RunNode in here:
				if not node.links.is_empty():
					found.append("room %d of the last row leads on" % node.index)
		var per_row: Dictionary = {}
		for node: RunNode in here:
			found.append_array(_node_broken(map, node, rules, content, made_at))
			per_row[node.kind] = int(per_row.get(node.kind, 0)) + 1
			per_run[node.kind] = int(per_run.get(node.kind, 0)) + 1
			if node.depth != here[0].depth:
				found.append("room %d stands for another row than its row's" % node.index)
			var scale: float = definition.room_scale(rules, node.depth, map.players)
			if node.scale != scale:
				found.append("room %d is scaled %s, not %s (row %d, %d players)" % [node.index, node.scale, scale, node.depth, map.players])
		for rule: KindRule in rules.kinds:
			if rule.max_per_row > 0 and int(per_row.get(rule.kind, 0)) > rule.max_per_row:
				found.append("row %d holds %d %s, more than %d" % [at, per_row[rule.kind], rule.kind, rule.max_per_row])
		if at + 1 < map.rows():
			found.append_array(_links_broken(map, here, map.row(at + 1), rules))
	for rule: KindRule in rules.kinds:
		if rule.max_per_run > 0 and int(per_run.get(rule.kind, 0)) > rule.max_per_run:
			found.append("the run holds %d %s, more than %d" % [per_run[rule.kind], rule.kind, rule.max_per_run])
	return found


## The rules one room keeps: its kind takes its row, follows its parents' kinds, its template
## hosts it (and differs from its parents' while another is left), its fill is the pool's.
func _node_broken(map: RunMap, node: RunNode, rules: MapRules, content: RunContent, made_at: Array[int]) -> PackedStringArray:
	var found := PackedStringArray()
	var lines: Array[KindRule] = []
	for rule: KindRule in rules.kinds:
		if rule.kind != node.kind:
			continue
		for depth: int in made_at:
			if rule.takes_row(node.depth, depth) and not lines.has(rule):
				lines.append(rule)
	if lines.is_empty():
		found.append("room %d: kind %s takes no row %d" % [node.index, node.kind, node.depth])
	var parents: PackedInt32Array = map.parents_of(node.index)
	if node.row > 0 and parents.is_empty():
		found.append("room %d is reached from no room" % node.index)
	var taken: Array[StringName] = []
	for parent: int in parents:
		var before: RunNode = map.nodes[parent]
		taken.append(before.room)
		for rule: KindRule in lines:
			if not rule.may_follow(before.kind):
				found.append("room %d: %s after %s" % [node.index, node.kind, before.kind])
	var hosts: Array[RoomBase] = content.templates_for(map.biome, node.kind, node.links.size())
	var host_ids: Array[StringName] = []
	for room: RoomBase in hosts:
		host_ids.append(room.id)
	if not host_ids.has(node.room):
		found.append("room %d: template %s does not host %s with %d exits" % [node.index, node.room, node.kind, node.links.size()])
	elif taken.has(node.room):
		for id: StringName in host_ids:
			if not taken.has(id):
				found.append("room %d: template %s again after a room of it, %s left" % [node.index, node.room, id])
				break
	found.append_array(_fill_broken(map, node, rules, content))
	return found


func _fill_broken(map: RunMap, node: RunNode, rules: MapRules, content: RunContent) -> PackedStringArray:
	var found := PackedStringArray()
	if node.enemies.is_empty():
		found.append("room %d stands no enemy" % node.index)
		return found
	match content.kind(node.kind).fill:
		RoomKind.FILL_ENEMIES:
			var pool: Array[EnemyBase] = content.enemy_pool(map.biome, node.depth)
			var spent: int = 0
			var cheapest: int = 1 << 30
			for enemy: EnemyBase in pool:
				cheapest = mini(cheapest, enemy.cost)
			for id: StringName in node.enemies:
				var enemy: EnemyBase = null
				for other: EnemyBase in pool:
					if other.id == id:
						enemy = other
				if enemy == null:
					found.append("room %d: %s is not of the pool at row %d" % [node.index, id, node.depth])
					return found
				spent += enemy.cost
			# Past the budget (at the room's scale, run generation RG5) only one enemy that alone
			# costs more; within it, nothing more affordable.
			var budget: int = RunScaling.scaled_budget(rules.room_budget, node.scale)
			if node.enemies.size() > 1 and spent > budget:
				found.append("room %d spends %d of a budget of %d" % [node.index, spent, budget])
			if spent <= budget and budget - spent >= cheapest:
				found.append("room %d leaves %d of its budget, enough for another" % [node.index, budget - spent])
		RoomKind.FILL_BOSS:
			var bosses: Array[StringName] = []
			for boss: EnemyBase in content.boss_pool(map.biome, node.depth):
				bosses.append(boss.id)
			if node.enemies.size() != 1 or not bosses.has(node.enemies[0]):
				found.append("room %d: %s is not one boss of the pool" % [node.index, node.enemies])
	return found


## True when a line of `rules` is limited (a row may then hold fewer than `width_min`, where the
## limits leave no more).
func _limited(rules: MapRules) -> bool:
	for rule: KindRule in rules.kinds:
		if rule.max_per_row > 0 or rule.max_per_run > 0:
			return true
	return false


## The depths `map` may have been made at: those whose kept rows are its rows.
func _made_at(map: RunMap, rules: MapRules, content: RunContent) -> Array[int]:
	var rows: Array[int] = _depths(map)
	var found: Array[int] = []
	for depth in range(rules.depth_min, rules.depth_max + 1):
		if rules.kept_rows(content, depth) == rows:
			found.append(depth)
	return found


## The rule row each row of `map` stands for.
func _depths(map: RunMap) -> Array[int]:
	var rows: Array[int] = []
	for at in map.rows():
		rows.append(map.row(at)[0].depth)
	return rows


## Links from `before` to `here`: to the next row only, within the branch limits, never crossing,
## every room of `here` reached; the last row leads nowhere.
func _links_broken(map: RunMap, before: Array[RunNode], here: Array[RunNode], rules: MapRules) -> PackedStringArray:
	var found := PackedStringArray()
	var first: int = here[0].index
	var last: int = here[here.size() - 1].index
	var parents: int = before.size()
	var width: int = here.size()
	var least: int = mini(rules.branches_min, width)
	var most: int = mini(rules.branches_max, width)
	var reach_end: int = -1
	var total: int = 0
	var short: bool = false
	for node: RunNode in before:
		var links: PackedInt32Array = node.links
		total += links.size()
		short = short or links.size() < least
		if links.is_empty() or links.size() > most:
			found.append("room %d leads to %d rooms, not 1 to %d" % [node.index, links.size(), most])
		for k in links.size():
			if links[k] < first or links[k] > last:
				found.append("room %d leads out of the next row (%d)" % [node.index, links[k]])
			if k > 0 and links[k] != links[k - 1] + 1:
				found.append("room %d's links are not one run: %s" % [node.index, links])
		if not links.is_empty():
			if links[0] < reach_end:
				found.append("room %d's links cross the room before's" % node.index)
			reach_end = links[links.size() - 1]
	# Uncrossed links number at most width + parents - 1: a room falls short of branches_min only
	# when every one of them is taken.
	if short and total != width + parents - 1:
		found.append("a room of row %d leads to fewer than %d rooms with %d of %d links free" % [before[0].row, least, width + parents - 1 - total, width + parents - 1])
	for node: RunNode in here:
		if map.parents_of(node.index).is_empty():
			found.append("room %d is reached from no room" % node.index)
	return found


func _check_seeds(definition: RunDefinition, content: RunContent, label: String) -> Dictionary:
	var seen: Dictionary = {"rows": {}, "widths": {}, "branches": {}}
	var broken: int = 0
	for value in SEEDS:
		# One to four players in turn (run generation RG5: the budget scales with them).
		var map: RunMap = RunGenerator.generate(definition, content, Sim.seeded(value), 1 + value % RunScaling.MOST_PLAYERS)
		var problems: PackedStringArray = _broken(map, definition, content)
		if not problems.is_empty():
			broken += 1
			if broken <= 3:
				check(false, "%s, seed %d: %s" % [label, value, "; ".join(problems)])
			continue
		seen["rows"][map.rows()] = true
		for at in map.rows():
			seen["widths"][map.row(at).size()] = true
		for node: RunNode in map.nodes:
			if not node.links.is_empty():
				seen["branches"][node.links.size()] = true
	check_equal(broken, 0, "%s: every seed of %d keeps every rule" % [label, SEEDS])
	return seen


# --- Tests -----------------------------------------------------------------------------------

## The made-up run `label` through every seed: a sound definition, every rule kept, every depth met.
func _check_made_up(label: String) -> Dictionary:
	var content: RunContent = _content()
	var definition: RunDefinition = _made_up_runs()[label]
	check_equal(definition.problems(content), PackedStringArray(), "%s is a sound definition" % label)
	var seen: Dictionary = _check_seeds(definition, content, label)
	var rules: MapRules = definition.biomes[0]
	check_equal(seen["rows"].size(), rules.depth_max - rules.depth_min + 1, "%s: every depth is met" % label)
	return seen


func test_a_plain_run_keeps_its_rules_over_many_seeds() -> void:
	_check_made_up("plain")


func test_a_wide_run_keeps_its_rules_over_many_seeds() -> void:
	var seen: Dictionary = _check_made_up("wide")
	for width in range(1, 6):
		check(seen["widths"].has(width), "a row of %d rooms is met" % width)
	for branches in range(1, 4):
		check(seen["branches"].has(branches), "a room leading to %d is met" % branches)


func test_a_run_of_two_ways_at_least_keeps_its_rules_over_many_seeds() -> void:
	_check_made_up("two ways at least")


func test_a_scaled_run_keeps_its_rules_over_many_seeds() -> void:
	_check_made_up("scaled steeply with depth and players")


func test_a_run_of_one_room_a_row_keeps_its_rules_over_many_seeds() -> void:
	_check_made_up("one room a row")


func test_a_run_with_limited_traps_keeps_its_rules_over_many_seeds() -> void:
	_check_made_up("traps, one a row, two a run, never one after another")


func test_the_crypt_run_keeps_its_rules_over_many_seeds() -> void:
	var crypt := _registry.get_resource(&"runs", &"crypt") as RunDefinition
	var content: RunContent = _registry.run_content()
	check(crypt != null, "the crypt run is found")
	if crypt == null:
		return
	var seen: Dictionary = _check_seeds(crypt, content, "crypt")
	check(seen["widths"].has(3) and seen["branches"].has(2), "the crypt's maps branch")


func test_the_boss_stands_alone_in_the_last_row() -> void:
	var failed: int = _failures.size()  # stop at the first seed that fails
	var content: RunContent = _content()
	var definition: RunDefinition = _made_up_runs()["plain"]
	for value in 200:
		var map: RunMap = RunGenerator.generate(definition, content, Sim.seeded(value))
		var last: Array[RunNode] = map.row(map.rows() - 1)
		check(last.size() == 1 and last[0].kind == &"boss" and last[0].room == &"throne", "seed %d: the last row is the boss's throne" % value)
		check_equal(last[0].enemies, [&"king"] as Array[StringName], "seed %d: the king stands in it" % value)
		for node: RunNode in map.nodes:
			if node != last[0]:
				check_equal(node.kind, &"fight", "seed %d: every other room a fight" % value)
		if _failures.size() > failed:
			return


func test_with_no_boss_the_run_ends_at_its_deepest_fight() -> void:
	var failed: int = _failures.size()  # stop at the first seed that fails
	var kinds: Array[Resource] = [_kind(&"fight", RoomKind.FILL_ENEMIES), _kind(&"boss", RoomKind.FILL_BOSS)]
	var rooms: Array[Resource] = [_room(&"hall_a", [&"fight"] as Array[StringName])]
	var enemies: Array[Resource] = [_enemy(&"rat", 1)]
	var content := RunContent.gather(kinds, rooms, enemies)
	var rules := _rules(4, 6, 1, 3, 1, 2)
	rules.kinds[1].required = false
	var definition := _run(rules)
	var depths: Dictionary = {}
	for value in 300:
		var map: RunMap = RunGenerator.generate(definition, content, Sim.seeded(value))
		check(map.is_made(), "seed %d: made" % value)
		for node: RunNode in map.nodes:
			check_equal(node.kind, &"fight", "seed %d: only fights" % value)
		check(map.row(map.rows() - 1).size() >= 1, "seed %d: a deepest row of fights" % value)
		depths[map.rows()] = true
		if _failures.size() > failed:
			return
	check_equal(depths.keys().size(), 3, "3 to 5 rows: the boss's row left out of 4 to 6")
	check(not depths.has(6), "never the boss's row")


func test_the_same_seed_gives_the_same_map() -> void:
	var content: RunContent = _content()
	var definition: RunDefinition = _made_up_runs()["traps, one a row, two a run, never one after another"]
	var hashes: Dictionary = {}
	for value in 50:
		var one: int = SimHash.of(RunGenerator.generate(definition, content, Sim.seeded(value)))
		var two: int = SimHash.of(RunGenerator.generate(definition, content, Sim.seeded(value)))
		check_equal(one, two, "seed %d: the same map twice" % value)
		hashes[one] = true
	check(hashes.size() > 40, "other seeds, other maps (%d of 50)" % hashes.size())


func test_a_roll_is_named_by_the_seed_only() -> void:
	# The generator keeps nothing between maps: another map made between two of one seed changes nothing.
	var content: RunContent = _content()
	var definition: RunDefinition = _made_up_runs()["wide"]
	var sim := Sim.seeded(77)
	var before: int = SimHash.of(RunGenerator.generate(definition, content, sim))
	RunGenerator.generate(definition, content, Sim.seeded(78))
	check_equal(SimHash.of(RunGenerator.generate(definition, content, sim)), before, "the same map after another")


func test_deleting_any_room_enemy_or_boss_still_makes_a_map_or_says_why() -> void:
	var failed: int = _failures.size()  # stop at the first seed that fails
	var crypt := _registry.get_resource(&"runs", &"crypt") as RunDefinition
	if crypt == null:
		check(false, "the crypt run is found")
		return
	var kinds: Array[Resource] = _registry.get_all(&"room_kinds")
	var rooms: Array[Resource] = _registry.get_all(&"rooms")
	var enemies: Array[Resource] = []
	for folder: StringName in EnemyBase.FOLDERS:
		enemies.append_array(_registry.get_all(folder))
	# The broom joins with OB3: a made-up crypt boss and boss room stand in, so deleting them is tried too.
	var boss := _enemy(&"test_boss", 10, 0, true)
	boss.biomes = [&"crypt"] as Array[StringName]
	enemies.append(boss)
	var throne := MadeUpRoom.new()
	throne.id = &"test_throne"
	throne.biome = &"crypt"
	throne.kinds = [&"boss"] as Array[StringName]
	rooms.append(throne)
	for list: Array[Resource] in [rooms, enemies]:
		for at in list.size():
			var left: Array[Resource] = list.duplicate()
			var gone: Resource = left.pop_at(at)
			var content: RunContent = RunContent.gather(kinds, left if list == rooms else rooms, left if list == enemies else enemies)
			var named: String = String(gone.get(&"id"))
			for value in 40:
				var map: RunMap = RunGenerator.generate(crypt, content, Sim.seeded(value))
				if map.is_made():
					check_equal(_broken(map, crypt, content), PackedStringArray(), "without %s, seed %d: a valid map" % [named, value])
				else:
					check(not map.problems.is_empty(), "without %s: no map, and why" % named)
				var stands: bool = false
				for node: RunNode in map.nodes:
					stands = stands or node.room == gone.get(&"id") or node.enemies.has(gone.get(&"id"))
				check(not stands, "without %s, seed %d: it stands nowhere" % [named, value])
				if _failures.size() > failed:
					return


## Run generation RG4: a room is laid out by a template with an exit for each of its links, never
## fewer; a hall of one exit stands only where a room leads to one room (and in the last row).
func test_a_room_is_laid_out_by_a_template_with_an_exit_a_link() -> void:
	var kinds: Array[Resource] = [_kind(&"fight", RoomKind.FILL_ENEMIES), _kind(&"boss", RoomKind.FILL_BOSS)]
	var narrow := _room(&"hall_narrow", [&"fight"] as Array[StringName]) as MadeUpRoom
	narrow.exits = 1
	var wide := _room(&"hall_wide", [&"fight"] as Array[StringName]) as MadeUpRoom
	wide.exits = 2
	var throne := _room(&"throne", [&"boss"] as Array[StringName]) as MadeUpRoom
	throne.exits = 0
	var content := RunContent.gather(kinds, [narrow, wide, throne] as Array[Resource], [_enemy(&"rat", 1), _enemy(&"king", 10, 0, true)] as Array[Resource])
	var definition: RunDefinition = _run(_rules(4, 6, 1, 3, 1, 2))
	var by_links: Dictionary = {}
	for value in 300:
		var map: RunMap = RunGenerator.generate(definition, content, Sim.seeded(value))
		check_equal(_broken(map, definition, content), PackedStringArray(), "seed %d: a valid map" % value)
		for node: RunNode in map.nodes:
			check(content.exits_of(node.room) >= node.links.size(), "seed %d, room %d: %s has an exit for each of its %d links" % [value, node.index, node.room, node.links.size()])
			by_links["%s %d" % [node.room, node.links.size()]] = true
	check(by_links.has("hall_narrow 1") and by_links.has("hall_wide 2") and by_links.has("hall_wide 1"), "both halls stand, the narrow one where a room leads to one: %s" % [by_links.keys()])
	check(not by_links.has("hall_narrow 2"), "never the narrow hall for two ways")


func test_a_map_that_cannot_be_made_says_why() -> void:
	var content := RunContent.gather([_kind(&"fight", RoomKind.FILL_ENEMIES)] as Array[Resource], [_room(&"hall_a", [&"fight"] as Array[StringName])] as Array[Resource], [] as Array[Resource])
	var map: RunMap = RunGenerator.generate(_run(_rules(3, 4, 1, 2, 1, 2)), content, Sim.seeded(1))
	check(not map.is_made() and map.rows() == 0 and map.first() == null, "no map")
	check(not map.problems.is_empty(), "and why: %s" % map.problems)
	check(not RunGenerator.generate(null, content, Sim.seeded(1)).problems.is_empty(), "no definition, and why")


func test_a_kind_limited_in_the_run_keeps_rooms_for_the_rows_only_it_fills() -> void:
	# Traps only after the first room, two in the run: row 1 may be two rooms wide, but then row 2
	# would hold none. Row 1 keeps one trap for row 2, every time.
	var rules := _rules(3, 3, 1, 2, 1, 2)
	var trap := KindRule.make(&"trap", 1, 2)
	trap.max_per_run = 2
	rules.kinds = [KindRule.make(&"fight", 0, 0), trap] as Array[KindRule]
	var definition := _run(rules)
	check_equal(definition.problems(_content()), PackedStringArray(), "a sound definition")
	var failed: int = _failures.size()  # stop at the first seed that fails
	for value in 200:
		var map: RunMap = RunGenerator.generate(definition, _content(), Sim.seeded(value))
		check_equal(_broken(map, definition, _content()), PackedStringArray(), "seed %d: a valid map" % value)
		check(map.row(1).size() == 1 and map.row(2).size() == 1, "seed %d: one trap a row" % value)
		if _failures.size() > failed:
			return


func test_a_heavy_limited_kind_never_takes_the_room_a_later_row_needs() -> void:
	# Elites in rows 1 and 2, once a run, ten times as likely as a fight in row 1; row 2 only an
	# elite. Row 1 must leave it for row 2 however the weights fall (review of RG2: half the seeds
	# found no map).
	var rules := _rules(3, 3, 1, 1, 1, 1)
	var elite := KindRule.make(&"trap", 1, 2, 10.0)
	elite.max_per_run = 1
	rules.kinds = [KindRule.make(&"fight", 0, 1), elite] as Array[KindRule]
	var definition := _run(rules)
	check_equal(definition.problems(_content()), PackedStringArray(), "a sound definition")
	var failed: int = _failures.size()  # stop at the first seed that fails
	for value in 300:
		var map: RunMap = RunGenerator.generate(definition, _content(), Sim.seeded(value))
		check_equal(_broken(map, definition, _content()), PackedStringArray(), "seed %d: a valid map" % value)
		check(map.is_made() and map.row(1)[0].kind == &"fight" and map.row(2)[0].kind == &"trap", "seed %d: a fight, then the elite" % value)
		if _failures.size() > failed:
			return


func test_limits_that_allow_fewer_rooms_than_width_min_make_rows_narrower() -> void:
	# Rows 1 and 2 each a trap or the boss, each once a run, two rooms a row: two rooms in row 1
	# would leave row 2 none, so each row holds one.
	var rules := _rules(3, 3, 2, 2, 1, 2)
	var trap := KindRule.make(&"trap", 1, 2)
	trap.max_per_run = 1
	var boss := KindRule.make(&"boss", 1, 2)
	boss.max_per_run = 1
	rules.kinds = [KindRule.make(&"fight", 0, 0), trap, boss] as Array[KindRule]
	var definition := _run(rules)
	check_equal(definition.problems(_content()), PackedStringArray(), "a sound definition")
	for value in 100:
		var map: RunMap = RunGenerator.generate(definition, _content(), Sim.seeded(value))
		check_equal(_broken(map, definition, _content()), PackedStringArray(), "seed %d: a valid map" % value)
		check(map.row(1).size() == 1 and map.row(2).size() == 1, "seed %d: one room a row" % value)


func test_a_room_no_kind_may_follow_its_rooms_before_says_so() -> void:
	# Row 1 a fight and a trap; row 2 two rooms, a boss (never after a trap) or a vault (never after
	# a fight), each once a row; every room leads to two. Two rooms leading to two never cross only
	# by sharing one: it follows a fight and a trap, and no kind may. The validator sees kinds, not
	# links; every attempt is cornered, and the map says so.
	var kinds: Array[Resource] = [_kind(&"fight", RoomKind.FILL_ENEMIES), _kind(&"trap", RoomKind.FILL_ENEMIES), _kind(&"vault", RoomKind.FILL_ENEMIES), _kind(&"boss", RoomKind.FILL_BOSS)]
	var rooms: Array[Resource] = [_room(&"hall_a", [&"fight", &"trap", &"vault"] as Array[StringName]), _room(&"throne", [&"boss"] as Array[StringName])]
	var content := RunContent.gather(kinds, rooms, [_enemy(&"rat", 1), _enemy(&"king", 10, 0, true)] as Array[Resource])
	var rules := _rules(3, 3, 2, 2, 2, 2)
	var fight := KindRule.make(&"fight", 0, 1)
	fight.max_per_row = 1
	var trap := KindRule.make(&"trap", 1, 1)
	trap.max_per_row = 1
	var boss := KindRule.make(&"boss", 2, 2)
	boss.max_per_row = 1
	boss.not_after = [&"trap"] as Array[StringName]
	var vault := KindRule.make(&"vault", 2, 2)
	vault.max_per_row = 1
	vault.not_after = [&"fight"] as Array[StringName]
	rules.kinds = [fight, trap, boss, vault] as Array[KindRule]
	var definition := _run(rules)
	check_equal(definition.problems(content), PackedStringArray(), "the validator passes it")
	var map: RunMap = RunGenerator.generate(definition, content, Sim.seeded(3))
	check(not map.is_made(), "no map within the rules")
	check(map.problems.size() == 1 and map.problems[0].contains("tries"), "it says the rules cornered it: %s" % map.problems)


func test_the_map_is_state() -> void:
	var map: RunMap = RunGenerator.generate(_made_up_runs()["wide"], _content(), Sim.seeded(11))
	var holder := Holder.new()
	holder.map = map
	var walk := StateWalk.new()
	walk.values("Run", holder, [])
	check_equal(walk.problems, PackedStringArray(), "the walker walks the map without problems")
	var before: int = SimHash.of(holder)
	var snapshot := Snapshot.take({"Run": holder})
	check_equal(snapshot.problems, PackedStringArray(), "a snapshot takes it")
	var fresh := Holder.new()
	check_equal(snapshot.restore({"Run": fresh}).size(), 0, "restored without problems")
	check_equal(SimHash.of(fresh), before, "the same map restored")
	check(fresh.map != map and fresh.map.nodes.size() == map.nodes.size(), "a map of its own")
	map.nodes[0].links = PackedInt32Array()
	check(SimHash.of(holder) != before, "a change to a link changes the hash")


## What holds the map as an area does (RG3 gives the run's area one).
class Holder:
	extends RefCounted
	var map: RunMap = null


## Run generation RG5: each room's scale is its depth's and the run's players' (the definition's
## curves), its budget grows with it, and only the fill follows the players: the same seed gives the
## same shape, kinds and templates for any number of players.
func test_deeper_rooms_and_more_players_fill_bigger_budgets() -> void:
	var content: RunContent = _content()
	var definition: RunDefinition = _scaled(_run(_rules(5, 5, 1, 1, 1, 1)))
	var rules: MapRules = definition.biomes[0]
	var costs: Dictionary = {}
	for enemy: EnemyBase in content.enemy_pool(BIOME, rules.depth_max):
		costs[enemy.id] = enemy.cost
	for value in 20:
		var maps: Array[RunMap] = []
		for players in range(1, RunScaling.MOST_PLAYERS + 1):
			maps.append(RunGenerator.generate(definition, content, Sim.seeded(value), players))
		var one: RunMap = maps[0]
		var four: RunMap = maps[maps.size() - 1]
		check(one.is_made() and four.is_made(), "seed %d: made for one player and for four" % value)
		if not (one.is_made() and four.is_made()):
			return
		check_equal(one.first().scale, 1.0, "seed %d: the first room with one player is as the data says" % value)
		check(is_equal_approx(four.first().scale, 2.0), "seed %d: with four, twice: %s" % [value, four.first().scale])
		var last: RunNode = one.nodes[one.nodes.size() - 1]
		check(last.kind == &"boss" and is_equal_approx(last.scale, 3.0), "seed %d: the boss's row, the deepest, three times: %s" % [value, last.scale])
		check(is_equal_approx(four.nodes[four.nodes.size() - 1].scale, 6.0), "seed %d: and both, six" % value)
		for at in one.nodes.size():
			if one.nodes[at].kind != &"fight":
				continue
			var spent: Array[int] = []
			for map: RunMap in maps:
				var node: RunNode = map.nodes[at]
				check_equal([node.room, node.kind, node.links], [one.nodes[at].room, one.nodes[at].kind, one.nodes[at].links], "seed %d room %d: the same room for any number of players" % [value, at])
				var cost: int = 0
				for id: StringName in node.enemies:
					cost += int(costs.get(id, 0))
				spent.append(cost)
				check(cost >= RunScaling.scaled_budget(rules.room_budget, node.scale) - 2, "seed %d room %d: %d spent of a budget of %d" % [value, at, cost, RunScaling.scaled_budget(rules.room_budget, node.scale)])
			check(spent[spent.size() - 1] > spent[0], "seed %d room %d: four players' fight costs more than one's (%s)" % [value, at, spent])
