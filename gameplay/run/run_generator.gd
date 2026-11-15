class_name RunGenerator
extends RefCounted
## Makes a run's map (run generation RG2, docs/milestones/run-generation.md, "The generator"): one
## pure function from a run definition, the content there is and the run's chance (`Sim`) to a
## `RunMap`. It reads no node and plays nothing, so the same definition, content and seed give the
## same map on every machine, in every replay and after every snapshot. Four steps, row by row:
##
## 1. **The shape:** the depth within the rules (rows the content fills nothing in are left out),
##    the first row one room, each next row's width within the rules and what the row before can
##    lead to, and links from each room to an unbroken run of the next row's rooms (`branches_min`
##    to `branches_max`), never crossing, so every room is reached and leads on to the last row.
## 2. **The kinds:** each room a line of the kind table that takes its row, by weight, within the
##    lines' limits (`max_per_row`, `max_per_run`) and never after a kind it may not follow.
## 3. **The templates:** each room a template of the biome that hosts its kind, by chance, never
##    one a room leading to it has while another is left.
## 4. **The fill**, by its kind's `RoomKind.fill`: a fight's enemies from the biome's pool at its
##    depth, by chance, until its budget (`MapRules.room_budget`) is spent (one at least); a boss
##    room's boss from the boss pool. Ids, never files.
##
## Rolls are `sim.chance(PURPOSE, key, counter)`, the key a step's (`Step`) and the attempt's, the
## counter that step's own count, so one step's rolls never shift another's. A line limited in the
## run keeps rooms for the later rows only it can fill. When the kinds' limits still leave a room
## no line (a table the validator passed may corner itself: two limited lines sharing rows, a
## room led to by kinds no one line may follow), the map is tried
## again with the next attempt's rolls, up to `ATTEMPTS`; then it is a map not made, and says why.
## So is a definition with problems (`RunDefinition.problems`): what is missing is named.
##
## The first biome is played until a second biome exists (docs/milestones/run-generation.md,
## "Not in this plan").

## What the generator's rolls are named by.
const PURPOSE: StringName = &"run_map"
## How many times a map is tried before it is given up.
const ATTEMPTS: int = 8

## The steps, each rolling under a key of its own.
enum Step { DEPTH, WIDTH, LINKS, KINDS, TEMPLATES, FILL }


## The map of `definition` made from `content` by `sim`'s chance (its run's seed). A map not made
## (`RunMap.is_made` false) says why in `RunMap.problems`.
static func generate(definition: RunDefinition, content: RunContent, sim: Sim) -> RunMap:
	var map := RunMap.new()
	if definition == null:
		map.problems = PackedStringArray(["No run definition."])
		return map
	map.run = definition.id
	var problems: PackedStringArray = definition.problems(content)
	if not problems.is_empty():
		map.problems = problems
		return map
	var rules: MapRules = definition.biomes[0]
	map.biome = rules.biome
	for attempt in ATTEMPTS:
		var dice := Dice.new(sim, attempt)
		var nodes: Array[RunNode] = _shape_and_kinds(rules, content, dice)
		if nodes.is_empty():
			continue
		map.nodes = nodes
		_pick_templates(map, content, dice)
		_fill(map, rules, content, dice)
		return map
	map.problems = PackedStringArray(["%s: %s: no map within its rules after %d tries (the kinds' max_per_row, max_per_run and not_after leave a room no kind)." % [definition.id, rules.biome, ATTEMPTS]])
	return map


## Steps 1 and 2, row by row: the rooms with their rows, links and kinds, or none when the kinds'
## limits leave a room no line.
static func _shape_and_kinds(rules: MapRules, content: RunContent, dice: Dice) -> Array[RunNode]:
	var nodes: Array[RunNode] = []
	var depth: int = rules.depth_min + dice.below(Step.DEPTH, rules.depth_max - rules.depth_min + 1)
	var rows: Array[int] = rules.kept_rows(content, depth)
	var table: Array = []  # each kept row's lines (Array[KindRule]), kept to those that can lead on
	for row: int in rows:
		table.append(rules.rules_at(content, row, depth))
	for at in range(rows.size() - 2, -1, -1):
		table[at] = MapRules.leading_lines(table[at], table[at + 1])
	var in_run: Dictionary = {}  # KindRule -> rooms of it so far
	var before: Array[RunNode] = []
	for at in rows.size():
		var lines: Array[KindRule] = table[at]
		var width: int = 1
		if at > 0:
			var most: int = mini(mini(rules.width_max, _room(lines, in_run, _kept_for(table, at), rules.width_max)), before.size() * rules.branches_max)
			if most < 1:
				return []
			var least: int = mini(rules.width_min, most)
			width = least + dice.below(Step.WIDTH, most - least + 1)
		var here: Array[RunNode] = []
		for k in width:
			var node := RunNode.new()
			node.index = nodes.size()
			node.row = at
			node.depth = rows[at]
			nodes.append(node)
			here.append(node)
		if at > 0:
			_link(before, here, rules, dice)
		if not _pick_kinds(before, here, lines, in_run, dice):
			return []
		before = here
	return nodes


## How many rows after row `at` of `table` only one line can fill, by line (KindRule -> rows): a
## line limited in the run keeps that many rooms for them.
static func _kept_for(table: Array, at: int) -> Dictionary:
	var kept: Dictionary = {}
	for later in range(at + 1, table.size()):
		var lines: Array[KindRule] = table[later]
		if lines.size() == 1:
			kept[lines[0]] = int(kept.get(lines[0], 0)) + 1
	return kept


## The most rooms a row of `lines` may still hold: `width_max` at most, each line at most its
## `max_per_row` and what its `max_per_run` leaves after `in_run` and the rooms it keeps for later
## rows only it can fill (`kept`).
static func _room(lines: Array[KindRule], in_run: Dictionary, kept: Dictionary, width_max: int) -> int:
	var room: int = 0
	for rule: KindRule in lines:
		var most: int = width_max
		if rule.max_per_row > 0:
			most = mini(most, rule.max_per_row)
		if rule.max_per_run > 0:
			most = mini(most, rule.max_per_run - int(in_run.get(rule, 0)) - int(kept.get(rule, 0)))
		room += maxi(most, 0)
	return mini(room, width_max)


## Links from the rooms of `before` to those of `here`: each room of `before` leads to an unbroken
## run of `here`'s rooms, the runs left to right, each starting where the last ended or just after
## (two neighbours share at most one room), the first at `here`'s first room and the last ending at
## its last. So no links cross, every room of `here` is reached, and each room of `before` leads to
## `branches_min` to `branches_max` rooms, never more than `here` holds (and fewer than
## `branches_min` only where `here` is too narrow for every room of `before` to have that many).
static func _link(before: Array[RunNode], here: Array[RunNode], rules: MapRules, dice: Dice) -> void:
	var parents: int = before.size()
	var width: int = here.size()
	var most: int = mini(rules.branches_max, width)
	var least: int = mini(mini(rules.branches_min, width), (width + parents - 1) / parents)
	# Runs of `least` to `most` rooms sharing `shared` of the parents - 1 borders sum to width + shared.
	var shared_min: int = maxi(0, parents * least - width)
	var shared_max: int = mini(parents - 1, parents * most - width)
	var shared: int = shared_min + dice.below(Step.LINKS, shared_max - shared_min + 1)
	var lengths: Array[int] = []
	lengths.resize(parents)
	lengths.fill(least)
	for extra in width + shared - parents * least:
		var open: Array[int] = []
		for k in parents:
			if lengths[k] < most:
				open.append(k)
		lengths[open[dice.below(Step.LINKS, open.size())]] += 1
	var borders: Array[int] = []
	for k in parents - 1:
		borders.append(k)
	var sharing: Array[bool] = []
	sharing.resize(parents)
	sharing.fill(false)
	for k in shared:
		sharing[borders.pop_at(dice.below(Step.LINKS, borders.size()))] = true
	var start: int = 0
	for k in parents:
		var links := PackedInt32Array()
		for at in range(start, start + lengths[k]):
			links.append(here[at].index)
		before[k].links = links
		start += lengths[k] - (1 if sharing[k] else 0)


## Each room of `here` a line of `lines` by weight: within the line's `max_per_row` and
## `max_per_run` (counted in `in_run`), and one every room leading to it may be followed by. False
## when a room is left no line.
static func _pick_kinds(before: Array[RunNode], here: Array[RunNode], lines: Array[KindRule], in_run: Dictionary, dice: Dice) -> bool:
	var in_row: Dictionary = {}  # KindRule -> rooms of it in this row
	for node: RunNode in here:
		var kinds_before: Array[StringName] = []
		for parent: RunNode in before:
			if parent.links.has(node.index):
				kinds_before.append(parent.kind)
		var open: Array[KindRule] = []
		var total: float = 0.0
		for rule: KindRule in lines:
			if rule.max_per_row > 0 and int(in_row.get(rule, 0)) >= rule.max_per_row:
				continue
			if rule.max_per_run > 0 and int(in_run.get(rule, 0)) >= rule.max_per_run:
				continue
			var follows: bool = true
			for kind: StringName in kinds_before:
				follows = follows and rule.may_follow(kind)
			if follows:
				open.append(rule)
				total += rule.weight
		if open.is_empty():
			return false
		var roll: float = dice.roll(Step.KINDS) * total
		var picked: KindRule = open[open.size() - 1]
		for rule: KindRule in open:
			if roll < rule.weight:
				picked = rule
				break
			roll -= rule.weight
		node.kind = picked.kind
		in_row[picked] = int(in_row.get(picked, 0)) + 1
		in_run[picked] = int(in_run.get(picked, 0)) + 1
	return true


## Step 3: each room a template of the map's biome that hosts its kind, by chance; one no room
## leading to it has, while one is left.
static func _pick_templates(map: RunMap, content: RunContent, dice: Dice) -> void:
	for node: RunNode in map.nodes:
		var hosts: Array[RoomBase] = content.templates_for(map.biome, node.kind)
		var fresh: Array[RoomBase] = []
		var taken: Array[StringName] = []
		for parent: int in map.parents_of(node.index):
			taken.append(map.nodes[parent].room)
		for room: RoomBase in hosts:
			if not taken.has(room.id):
				fresh.append(room)
		var from: Array[RoomBase] = fresh if not fresh.is_empty() else hosts
		node.room = from[dice.below(Step.TEMPLATES, from.size())].id


## Step 4: each room filled as its kind's `fill` says.
static func _fill(map: RunMap, rules: MapRules, content: RunContent, dice: Dice) -> void:
	for node: RunNode in map.nodes:
		match content.kind(node.kind).fill:
			RoomKind.FILL_ENEMIES:
				node.enemies = _spend(content.enemy_pool(map.biome, node.depth), rules.room_budget, dice)
			RoomKind.FILL_BOSS:
				var bosses: Array[EnemyBase] = content.boss_pool(map.biome, node.depth)
				node.enemies = [bosses[dice.below(Step.FILL, bosses.size())].id] as Array[StringName]


## Enemies of `pool` by chance until `budget` is spent: one of the whole pool first (a room always
## has a fight), then any the rest of the budget affords, until none does.
static func _spend(pool: Array[EnemyBase], budget: int, dice: Dice) -> Array[StringName]:
	var picked: Array[StringName] = []
	var left: int = budget
	var from: Array[EnemyBase] = pool
	while not from.is_empty():
		var enemy: EnemyBase = from[dice.below(Step.FILL, from.size())]
		picked.append(enemy.id)
		left -= enemy.cost
		var affordable: Array[EnemyBase] = []
		for other: EnemyBase in pool:
			if other.cost <= left:
				affordable.append(other)
		from = affordable
	return picked


## The generator's rolls in one attempt: each step's own count under a key of its own.
class Dice:
	extends RefCounted
	const DERIVED: Array[StringName] = [&"sim"]
	var sim: Sim = null
	var attempt: int = 0
	var counts: Array[int] = []

	func _init(of_sim: Sim, of_attempt: int) -> void:
		sim = of_sim
		attempt = of_attempt
		counts.resize(Step.size())
		counts.fill(0)

	## A roll in [0, 1) of step `step`.
	func roll(step: int) -> float:
		var value: float = sim.chance(PURPOSE, attempt * Step.size() + step, counts[step])
		counts[step] += 1
		return value

	## A whole number from 0 to `count` - 1 of step `step` (no roll when `count` is 1 or less).
	func below(step: int, count: int) -> int:
		if count <= 1:
			return 0
		var value: int = sim.chance_int(PURPOSE, attempt * Step.size() + step, counts[step], count)
		counts[step] += 1
		return value
