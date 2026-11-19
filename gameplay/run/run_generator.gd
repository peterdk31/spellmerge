class_name RunGenerator
extends RefCounted
## Makes a run's map (run generation RG2, docs/milestones/run-generation.md, "The generator"): one
## pure function from a run definition, the content there is and the run's chance (`Sim`) to a
## `RunMap`. It reads no node and plays nothing, so the same definition, content and seed give the
## same map on every machine, in every replay and after every snapshot. Four steps, row by row:
##
## 1. **The shape:** the depth within the rules (rows the content fills nothing in are left out),
##    the first row one room, each next row's width within the rules, what the row before can
##    lead to and what the kinds' limits leave for it and the rows after (fewer than `width_min`
##    only where those limits allow no more), and links from each room to an unbroken run of the next row's rooms (`branches_min`
##    to `branches_max`), never crossing, so every room is reached and leads on to the last row.
## 2. **The kinds:** each room a line of the kind table that takes its row, by weight, within the
##    lines' limits (`max_per_row`, `max_per_run`), never after a kind it may not follow, and never
##    one that would leave the rest of its row or a later row no line.
## 3. **The templates:** each room a template of the biome that hosts its kind and has an exit for
##    each of its links (run generation RG4; the validator holds a kind that leads on to a template
##    with exits enough, `MapRules.exit_problems`), by chance, never one a room leading to it has
##    while another is left.
## 4. **The fill**, by its kind's `RoomKind.fill`: each room's scale from its depth and the run's
##    players (`RunDefinition.room_scale`, run generation RG5), then a fight's enemies from the
##    biome's pool at its depth, by chance, until its budget (`MapRules.room_budget` at its scale,
##    `RunScaling.scaled_budget`) is spent (one at least); a boss room's boss from the boss pool.
##    Ids, never files.
##
## Rolls are `sim.chance(PURPOSE, key, counter)`, the key a step's (`Step`) and the attempt's, the
## counter that step's own count, so one step's rolls never shift another's. The limits never corner
## a map; `not_after` can, where a room is led to by kinds no one line may follow (the validator
## checks kinds, not links): then the map is tried
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


## The map of `definition` made from `content` by `sim`'s chance (its run's seed) for a run of
## `players` players (the seats joined at its start: every machine and replay counts the same). A
## map not made (`RunMap.is_made` false) says why in `RunMap.problems`.
static func generate(definition: RunDefinition, content: RunContent, sim: Sim, players: int = 1) -> RunMap:
	var map := RunMap.new()
	map.players = players
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
		var dice := MapDice.new(sim, PURPOSE, attempt, Step.size())
		var nodes: Array[RunNode] = _shape_and_kinds(rules, content, dice)
		if nodes.is_empty():
			continue
		map.nodes = nodes
		var missing: String = _pick_templates(map, content, dice)
		if missing != "":
			# The validator holds every kind that leads on to a template with exits enough
			# (`MapRules.exit_problems`): a map that still finds none is named, never stood.
			map.nodes = [] as Array[RunNode]
			map.problems = PackedStringArray(["%s: %s" % [definition.id, missing]])
			return map
		_fill(map, definition, rules, content, dice)
		return map
	map.problems = PackedStringArray(["%s: %s: no map within its rules after %d tries (the kinds' max_per_row, max_per_run and not_after leave a room no kind)." % [definition.id, rules.biome, ATTEMPTS]])
	return map


## Steps 1 and 2, row by row: the rooms with their rows, links and kinds, or none when the kinds'
## limits leave a room no line.
static func _shape_and_kinds(rules: MapRules, content: RunContent, dice: MapDice) -> Array[RunNode]:
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
			var most: int = mini(rules.width_max, before.size() * rules.branches_max)
			while most > 0 and not _fillable(table, at, most, lines, {}, in_run):
				most -= 1
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
		if not _pick_kinds(before, here, table, at, in_run, dice):
			return []
		before = here
	return nodes


## True when `left` more rooms of row `at` (each a line of `lines`, with `in_row` of them placed in
## the row already) and one room in each later row of `table` can each still take a line, within
## the lines' `max_per_row` (this row's) and `max_per_run` (counting `in_run`). A room with a line
## limited in neither is set aside; the rest, few, are tried line by line.
static func _fillable(table: Array, at: int, left: int, lines: Array[KindRule], in_row: Dictionary, in_run: Dictionary) -> bool:
	var slots: Array = []  # [lines of the room, true for a room of this row]
	for k in left:
		slots.append([lines, true])
	for later in range(at + 1, table.size()):
		slots.append([table[later], false])
	var tight: Array = []
	for slot: Array in slots:
		var free: bool = false
		for rule: KindRule in slot[0]:
			free = free or (rule.max_per_run == 0 and (not slot[1] or rule.max_per_row == 0))
		if not free:
			tight.append(slot)
	return _place_slots(tight, 0, in_row.duplicate(), in_run.duplicate())


static func _place_slots(slots: Array, from: int, in_row: Dictionary, in_run: Dictionary) -> bool:
	if from >= slots.size():
		return true
	var this_row: bool = slots[from][1]
	for rule: KindRule in slots[from][0]:
		if rule.max_per_run > 0 and int(in_run.get(rule, 0)) >= rule.max_per_run:
			continue
		if this_row and rule.max_per_row > 0 and int(in_row.get(rule, 0)) >= rule.max_per_row:
			continue
		in_run[rule] = int(in_run.get(rule, 0)) + 1
		if this_row:
			in_row[rule] = int(in_row.get(rule, 0)) + 1
		if _place_slots(slots, from + 1, in_row, in_run):
			return true
		in_run[rule] = int(in_run[rule]) - 1
		if this_row:
			in_row[rule] = int(in_row[rule]) - 1
	return false


## Links from the rooms of `before` to those of `here`: each room of `before` leads to an unbroken
## run of `here`'s rooms, the runs left to right, each starting where the last ended or just after
## (two neighbours share at most one room), the first at `here`'s first room and the last ending at
## its last. So no links cross, every room of `here` is reached, and each room of `before` leads to
## `branches_min` to `branches_max` rooms, never more than `here` holds. Uncrossed links number at
## most `here` + `before` - 1: where that is too few for every room of `before` to have
## `branches_min`, the fewest rooms fall short, by as little as can be (the longest runs shortened
## first, by chance among equals).
static func _link(before: Array[RunNode], here: Array[RunNode], rules: MapRules, dice: MapDice) -> void:
	var parents: int = before.size()
	var width: int = here.size()
	var most: int = mini(rules.branches_max, width)
	var lengths: Array[int] = []
	lengths.resize(parents)
	lengths.fill(mini(rules.branches_min, width))
	for cut in maxi(0, parents * lengths[0] - (width + parents - 1)):
		var longest: int = lengths.max()
		var open: Array[int] = []
		for k in parents:
			if lengths[k] == longest:
				open.append(k)
		lengths[open[dice.below(Step.LINKS, open.size())]] -= 1
	var least_sum: int = 0
	for length: int in lengths:
		least_sum += length
	# The runs sum to width + shared, sharing `shared` of the parents - 1 borders.
	var shared_min: int = maxi(0, least_sum - width)
	var shared_max: int = mini(parents - 1, parents * most - width)
	var shared: int = shared_min + dice.below(Step.LINKS, shared_max - shared_min + 1)
	for extra in width + shared - least_sum:
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


## Each room of `here` (row `at` of `table`) a line of its row by weight: within the line's
## `max_per_row` and `max_per_run` (counted in `in_run`), one every room leading to it may be
## followed by, and one that leaves the rest of the row and every later row a line
## (`_fillable`). False when a room is left no line (only `not_after` can do that).
static func _pick_kinds(before: Array[RunNode], here: Array[RunNode], table: Array, at: int, in_run: Dictionary, dice: MapDice) -> bool:
	var lines: Array[KindRule] = table[at]
	var in_row: Dictionary = {}  # KindRule -> rooms of it in this row
	for k in here.size():
		var node: RunNode = here[k]
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
			if not follows:
				continue
			if rule.max_per_run > 0 or rule.max_per_row > 0:
				in_row[rule] = int(in_row.get(rule, 0)) + 1
				in_run[rule] = int(in_run.get(rule, 0)) + 1
				var leaves: bool = _fillable(table, at, here.size() - k - 1, lines, in_row, in_run)
				in_row[rule] = int(in_row[rule]) - 1
				in_run[rule] = int(in_run[rule]) - 1
				if not leaves:
					continue
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


## Step 3: each room a template of the map's biome that hosts its kind with an exit for each of its
## links, by chance; one no room leading to it has, while one is left. What is missing, or "" when
## every room has its template.
static func _pick_templates(map: RunMap, content: RunContent, dice: MapDice) -> String:
	for node: RunNode in map.nodes:
		var hosts: Array[RoomBase] = content.templates_for(map.biome, node.kind, node.links.size())
		if hosts.is_empty():
			return "no %s room hosts '%s' with %d exits (room %d)." % [map.biome, node.kind, node.links.size(), node.index]
		var fresh: Array[RoomBase] = []
		var taken: Array[StringName] = []
		for parent: int in map.parents_of(node.index):
			taken.append(map.nodes[parent].room)
		for room: RoomBase in hosts:
			if not taken.has(room.id):
				fresh.append(room)
		var from: Array[RoomBase] = fresh if not fresh.is_empty() else hosts
		node.room = from[dice.below(Step.TEMPLATES, from.size())].id
	return ""


## Step 4: each room its scale (its depth, the run's players), its pace (`_pace`), and filled as
## its kind's `fill` says: a fight by its budget at that scale.
static func _fill(map: RunMap, definition: RunDefinition, rules: MapRules, content: RunContent, dice: MapDice) -> void:
	for node: RunNode in map.nodes:
		node.scale = definition.room_scale(rules, node.depth, map.players)
		var budget: int = RunScaling.scaled_budget(rules.room_budget, node.scale)
		_pace(node, rules.spawning, budget)
		match content.kind(node.kind).fill:
			RoomKind.FILL_ENEMIES:
				node.enemies = RoomFill.spend(content.enemy_pool(map.biome, node.depth), budget, dice, Step.FILL)
			RoomKind.FILL_BOSS:
				var bosses: Array[EnemyBase] = content.boss_pool(map.biome, node.depth)
				node.enemies = [bosses[dice.below(Step.FILL, bosses.size())].id] as Array[StringName]


## How `node`'s enemies come in (enemy spawning EA4): `spawning`'s shares of its scaled budget
## `budget`, as costs; with no `SpawnRules`, the whole list at once (a group of 0).
static func _pace(node: RunNode, spawning: SpawnRules, budget: int) -> void:
	var pace: Array = RoomFill.pace(spawning, budget)
	node.group = pace[0]
	node.refill_at = pace[1]
	node.stagger = pace[2]
