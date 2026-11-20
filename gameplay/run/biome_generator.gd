class_name BiomeGenerator
extends RefCounted
## Makes a biome's map (connected biomes CB5, docs/milestones/connected-biomes.md, decisions 1, 2, 4,
## 5 and 6): one pure function from a run definition (its first biome's `MapRules`), the content
## there is (`RunContent`), the templates' shapes (`PieceShape`s by id, `Registry.piece_shapes`), the
## run's chance (`Sim`) and its players to a `BiomeMap`. It reads no node and plays nothing, so the
## same inputs give the same map on every machine, in every replay and after every snapshot (the map
## is then state, never made again). Its steps:
##
## 1. **The count and the style:** the rooms (`rooms_min` to `rooms_max`, the start room and the
##    bridges not counted) and one of the rules' `styles` by weight (`MapStyle`).
## 2. **The kinds** (decision 1): each line's `least` (the fixed kinds), each room past it up to
##    `max_per_run` by its `chance` (the chance kinds, within `rooms_max`: the lines with the fewest
##    chance rooms take the slots first, so a challenge room before the treasure rooms), and the rest the lines
##    with no limit, by weight; one room of the line that stands deepest (the boss).
## 3. **The way** (decision 4): the style's `way_share` of the rooms, at least `fights_on_way` + 1,
##    from the start room to the boss, one bridge a room deeper: its rooms by chance from the kinds
##    that take their depth and are no dead end, fights enough among them; the boss at its end, so it
##    stands deepest.
## 4. **The rest off the way:** each room off a room placed (not a dead end, not the boss) whose depth
##    leaves it shallower than the boss and its kind's depths, by the style's weights: `branch_chain`
##    (off the last room placed off the way), `hub_pull` (off a room with more bridges). Rooms that
##    are no dead end first, so a dead end leads nowhere.
## 5. **The loops:** up to the style's `loops` extra bridges between two rooms' free sockets that a
##    bridge's ends meet, each kept only where the rules still hold (the boss still deepest, fights
##    enough on every way to it, every kind at a depth it takes).
## 6. **The fill:** each room's scale (`RunDefinition.biome_room_scale`: its depth, the run's
##    players) and a fight's enemies bought by its scaled budget, the boss's one boss (`RoomFill`);
##    its elites (connected biomes CB11, decision 24): a fight room from `MapRules.elite_depth` on is
##    an elite room by `elite_chance` (its first enemy an elite), a challenge room's
##    (`RoomKind.FILL_ELITES`) every enemy, each elite one card of `elite_cards` by chance.
## 7. **The reward rooms' types** (the owner's ask of 2026-11-19, `RewardType`): each room of a kind
##    with `typed_rewards` (the reward room) one type from its `rewards` table (`RunContent`): a line
##    by weight (its item kind); for a card line one of the card kinds its cards are, evenly (in
##    name order); for the element kind one of its element cards, evenly. Rolled under REWARD_PURPOSE
##    with a key of its own, so the rooms and their fill roll as they did. With no table or no card
##    there, the room is of no type.
##
## A line with no limit (the fights) fills the rooms past the fixed and chance ones only while a
## template is left to host it (a template stands once a biome), so the count rolled is the most
## the content allows (CB11: four fight templates in the crypt until CB13 brings more).
##
## **Placing a room** (decisions 2 and 6): over a free socket of the room it hangs off, a bridge
## (a walkway of the biome, straight or a corner, any mirroring whose end faces the socket), and at the bridge's far end
## a template that hosts the room's kind with a socket facing it, in any of its four mirrorings
## (`BiomeMap.room_mirrors`: BiomeWorld lays its collision mirrored and Feel draws its ground so,
## CB4), never a template the biome holds already (the start room excepted; bridges repeat), with
## its slab GAP clear of every other room and the bridge over its own two rooms only. A placement is
## picked by chance among every one that fits, a loop's `loop_pull` favouring those that leave a
## bridge's span between two free sockets. Every place is on the 32 px grid, as the sockets are; the
## map is moved last so its corner is at (0, 0).
##
## Rolls are `sim.chance(PURPOSE, key, counter)` through `MapDice`, the key a step's and the
## attempt's. A seed whose shapes leave a room no placement is tried again with the next attempt's
## rolls, up to ATTEMPTS; then the map is not made and says why (`BiomeMap.not_made`), as a
## definition with problems does (`RunDefinition.biome_problems`). `rule_problems` checks a made map
## against the rules (the tests read every seed by it).

## What the generator's rolls are named by.
const PURPOSE: StringName = &"biome_map"
## What the reward rooms' types are rolled by (step 7).
const REWARD_PURPOSE: StringName = &"biome_rewards"
## How many times a map is tried before it is given up.
const ATTEMPTS: int = 24
## How much dark a room keeps round its slab from every other room's, in pixels.
const GAP: float = 32.0

## The steps, each rolling under a key of its own.
enum Step { ROOMS, STYLE, KINDS, WAY, PLACE, PARENT, ORDER, LOOPS, FILL }


## The biome map of `definition`'s first biome, made from `content` and `shapes` by `sim`'s chance
## (its run's seed) for a run of `players` players. A map not made (`BiomeMap.is_made` false) says
## why in `BiomeMap.not_made`.
static func generate(definition: RunDefinition, content: RunContent, shapes: Dictionary, sim: Sim, players: int = 1) -> BiomeMap:
	var map := BiomeMap.new()
	if definition == null:
		map.not_made = PackedStringArray(["No run definition."])
		return map
	var problems: PackedStringArray = definition.biome_problems(content, shapes)
	if not problems.is_empty():
		map.not_made = problems
		return map
	var rules: MapRules = definition.biomes[0]
	map.biome = rules.biome
	if rules.start_only():
		return _start_alone(definition, rules, content, shapes, sim, players)
	var why: String = ""
	for attempt in ATTEMPTS:
		var dice := MapDice.new(sim, PURPOSE, attempt, Step.size())
		var growth := Growth.new(rules, content, shapes, dice)
		why = growth.grow()
		if why == "":
			var made: BiomeMap = growth.to_map()
			_fill(made, definition, rules, content, players, dice)
			_type_rewards(made, content, sim)
			return made
	map.not_made = PackedStringArray(["%s: %s: no map after %d tries (the templates' shapes and sockets leave no room for it; the last try: %s)." % [definition.id, rules.biome, ATTEMPTS, why]])
	return map


## What breaks `rules` in `map` (made of `content`, with `shapes`), one line each; empty for a map
## that keeps them: room 0 the start room; the rooms' count (`rooms_min` to `rooms_max`); one room
## of the line that stands deepest, deeper than every other; every room of a kind of the table at a
## depth its line takes, and filled there; each line's `least` and `max_per_run`; a dead end's one
## bridge; at least `fights_on_way` fights on every way from the start room to the boss; no bridge
## from a kind a room may not follow (`not_after`); each template hosting its room's kind, and none
## twice (the start room's excepted); every room's slab GAP clear of every other's. With `whole` false (a map still growing), the counts (of rooms
## and of each line) are not checked. With `capped` false (a room reroll's map, the owner's decision
## of 2026-11-19) a line's `max_per_run` is not checked, only its `least` (the fixed kinds there).
static func rule_problems(map: BiomeMap, rules: MapRules, content: RunContent, shapes: Dictionary, whole: bool = true, capped: bool = true) -> PackedStringArray:
	var found := PackedStringArray()
	if not map.is_made():
		found.append("no map: %s" % "; ".join(map.not_made))
		return found
	var lines: Array[KindRule] = rules.biome_lines(content, shapes)
	var by_kind: Dictionary = {}
	for rule: KindRule in lines:
		by_kind[rule.kind] = rule
	if map.room_kinds[0] != rules.start_kind:
		found.append("room 0 is a '%s', not the start room ('%s')." % [map.room_kinds[0], rules.start_kind])
	var count: int = map.rooms() - 1
	if whole and (count < rules.rooms_min or count > rules.rooms_max):
		found.append("%d rooms past the start room; %d to %d." % [count, rules.rooms_min, rules.rooms_max])
	var deepest: int = -1
	var end_kind: StringName = &""
	for rule: KindRule in lines:
		if rule.stands_deepest():
			end_kind = rule.kind
	var counts: Dictionary = {}
	var seen: Dictionary = {}
	for room in range(1, map.rooms()):
		var kind: StringName = map.room_kinds[room]
		counts[kind] = int(counts.get(kind, 0)) + 1
		if kind == end_kind:
			deepest = room
		var template: StringName = map.room_templates[room]
		if seen.has(template):
			found.append("rooms %d and %d are both %s: a template stands once a biome." % [seen[template], room, template])
		seen[template] = room
	var rects: Array[Rect2] = []
	for room in map.rooms():
		var shape: PieceShape = map.room_shape(room, shapes)
		rects.append(shape.rect_at(map.room_places[room]).grow(GAP * 0.5) if shape != null else Rect2())
	for a in rects.size():
		for b in range(a + 1, rects.size()):
			if rects[a].intersects(rects[b]):
				found.append("rooms %d and %d are less than %d px apart." % [a, b, int(GAP)])
	for room in map.rooms():
		var host: RoomBase = _template(content, map.room_templates[room])
		if host == null or not host.hosts(map.room_kinds[room]):
			found.append("room %d's template %s does not host its kind '%s'." % [room, map.room_templates[room], map.room_kinds[room]])
	if deepest < 0 or int(counts.get(end_kind, 0)) != 1:
		found.append("%d rooms of '%s', the kind that stands deepest; one." % [int(counts.get(end_kind, 0)), end_kind])
		return found
	var end_depth: int = map.depths[deepest]
	for room in map.rooms():
		if room != deepest and map.depths[room] >= end_depth:
			found.append("room %d (%s) is %d bridges deep, the boss's room %d only %d: the boss stands deepest." % [room, map.room_kinds[room], map.depths[room], deepest, end_depth])
		if room == 0:
			continue
		var rule: KindRule = by_kind.get(map.room_kinds[room]) as KindRule
		if rule == null:
			found.append("room %d's kind '%s' is no line of the biome's table the content fills." % [room, map.room_kinds[room]])
		elif not _fills_at(rules, content, rule, map.depths[room], end_depth):
			found.append("room %d's kind '%s' stands %d bridges deep, a depth its line does not take or nothing fills there." % [room, rule.kind, map.depths[room]])
		elif rule.dead_end and _bridges_of(map, room) != 1:
			found.append("room %d's kind '%s' is a dead end, but %d bridges reach it." % [room, rule.kind, _bridges_of(map, room)])
	for rule: KindRule in lines:
		var of_kind: int = int(counts.get(rule.kind, 0))
		if not whole:
			break
		if of_kind < rule.least or (capped and rule.max_per_run > 0 and of_kind > rule.max_per_run):
			found.append("%d rooms of '%s'; at least %d%s." % [of_kind, rule.kind, rule.least, (", %d at most" % rule.max_per_run) if rule.max_per_run > 0 else ""])
	var fights: int = fights_on_way(map, content, deepest)
	if fights < rules.fights_on_way:
		found.append("a way to the boss passes %d fights; %d at least." % [fights, rules.fights_on_way])
	for bridge in map.bridges():
		var a: int = map.end_room(bridge, 0)
		var b: int = map.end_room(bridge, 1)
		for pair: Vector2i in [Vector2i(a, b), Vector2i(b, a)]:
			if map.depths[pair.x] > map.depths[pair.y]:
				continue
			var rule: KindRule = by_kind.get(map.room_kinds[pair.y]) as KindRule
			if rule != null and not rule.may_follow(map.room_kinds[pair.x]):
				found.append("bridge %d leads from a '%s' to a '%s', which may not follow it." % [bridge, map.room_kinds[pair.x], map.room_kinds[pair.y]])
	return found


## The fewest fights (rooms of a kind filled with enemies) on any way from the start room to room
## `goal` over `map`'s bridges (the goal not counted).
static func fights_on_way(map: BiomeMap, content: RunContent, goal: int) -> int:
	if goal < 0 or goal >= map.rooms():
		return 0
	var most: int = map.rooms() + 1
	var best := PackedInt32Array()
	best.resize(map.rooms())
	best.fill(most)
	best[0] = 0
	# Few rooms: relax every bridge until nothing changes (each room costs its own fight to enter).
	var changed: bool = true
	while changed:
		changed = false
		for bridge in map.bridges():
			for end in 2:
				var from: int = map.end_room(bridge, end)
				var to: int = map.end_room(bridge, 1 - end)
				if best[from] >= most:
					continue
				var cost: int = best[from] + (1 if to != goal and _fights(content, map.room_kinds[to]) else 0)
				if cost < best[to]:
					best[to] = cost
					changed = true
	return best[goal]


static func _fights(content: RunContent, kind: StringName) -> bool:
	var of_kind: RoomKind = content.kind(kind)
	return of_kind != null and of_kind.fill == RoomKind.FILL_ENEMIES


## True when a room of `rule` may stand `depth` bridges deep in a map whose boss stands `end_depth`
## deep: its line takes the depth, the boss alone at the deepest, and what fills it is there.
static func _fills_at(rules: MapRules, content: RunContent, rule: KindRule, depth: int, end_depth: int) -> bool:
	if rule.stands_deepest() != (depth == end_depth) or not rule.takes_row(depth, end_depth + 1):
		return false
	match content.kind(rule.kind).fill:
		RoomKind.FILL_ENEMIES, RoomKind.FILL_ELITES:
			return not content.enemy_pool(rules.biome, depth).is_empty()
		RoomKind.FILL_BOSS:
			return not content.boss_pool(rules.biome, depth).is_empty()
	return true


static func _bridges_of(map: BiomeMap, room: int) -> int:
	var count: int = 0
	for bridge in map.bridges():
		if map.end_room(bridge, 0) == room or map.end_room(bridge, 1) == room:
			count += 1
	return count


static func _template(content: RunContent, id: StringName) -> RoomBase:
	for room: RoomBase in content.rooms:
		if room.id == id:
			return room
	return null


## The map of the start room alone (`MapRules.start_only`: a test's pinned room): the first template
## of the biome hosting the start room's kind, unmirrored at (0, 0), filled as its kind fills.
static func _start_alone(definition: RunDefinition, rules: MapRules, content: RunContent, shapes: Dictionary, sim: Sim, players: int) -> BiomeMap:
	var map := BiomeMap.new()
	map.biome = rules.biome
	var host: RoomBase = rules.biome_templates(content, shapes, rules.start_kind, 0)[0]
	map.add_room(host.id, Vector2.ZERO, 0, rules.start_kind)
	map.work_out_depths()
	_fill(map, definition, rules, content, players, MapDice.new(sim, PURPOSE, 0, Step.size()))
	return map


## Step 6: each room its scale (its depth, the run's players) and its enemies, as its kind fills.
static func _fill(map: BiomeMap, definition: RunDefinition, rules: MapRules, content: RunContent, players: int, dice: MapDice) -> void:
	for room in map.rooms():
		var filled: Array = _fill_one(map, room, definition, rules, content, players, dice)
		map.fill_room(room, filled[0], filled[1], filled[2], filled[3])


## Room `room`'s fill as step 6 rolls it: [its scale, its enemies, their elite cards, its depth's
## level: its scale with one player, which an enemy's aim sharpens by (`AimTuning`; the owner,
## 2026-11-19: depth only, never the players)].
static func _fill_one(map: BiomeMap, room: int, definition: RunDefinition, rules: MapRules, content: RunContent, players: int, dice: MapDice) -> Array:
	var depth: int = map.depths[room]
	var scale: float = definition.biome_room_scale(rules, depth, players)
	var enemies: Array[StringName] = []
	var elites: int = 0
	var fill: StringName = content.kind(map.room_kinds[room]).fill
	match fill:
		RoomKind.FILL_ENEMIES, RoomKind.FILL_ELITES:
			enemies = RoomFill.spend(content.enemy_pool(rules.biome, depth), RunScaling.scaled_budget(rules.room_budget, scale), dice, Step.FILL)
			if fill == RoomKind.FILL_ELITES:
				elites = enemies.size()
			elif rules.elite_depth >= 0 and depth >= rules.elite_depth and dice.roll(Step.FILL) < rules.elite_chance:
				elites = 1
		RoomKind.FILL_BOSS:
			var bosses: Array[EnemyBase] = content.boss_pool(rules.biome, depth)
			enemies = [bosses[dice.below(Step.FILL, bosses.size())].id] as Array[StringName]
	var cards: Array[StringName] = []
	if elites > 0 and not rules.elite_cards.is_empty():
		for at in enemies.size():
			cards.append(rules.elite_cards[dice.below(Step.FILL, rules.elite_cards.size())] if at < elites else &"")
	return [scale, enemies, cards, definition.biome_room_scale(rules, depth, 1)]


# --- A room reroll (the owner, 2026-11-19) ----------------------------------------------------

## What a room reroll's rolls are named by, and the rolls a room's reroll counter keys apart.
const REROLL_PURPOSE: StringName = &"room_reroll"
const REROLL_KEYS: int = 256

## `map` with its room `room` rerolled (the owner, 2026-11-19: "rerolls what lies behind that
## doorway: its kind and contents"), its `roll`th reroll this run, by `sim`'s chance
## (REROLL_PURPOSE): a new kind, template and mirroring, placed so that every bridge that reaches it
## still meets one of its sockets where it did, and filled again as its kind fills (the same depth,
## so the same scale). Only what keeps the map valid is a candidate: any kind of the biome's lines
## with the same door as the room's kind has (the owner, 2026-11-19: a treasure room stays a
## treasure room, a challenge a challenge; the rest are the kinds that open freely), not the start
## room's kind, a template the biome holds nowhere else, inside the biome's area as it is laid (its
## bounds never move), and every rule of `problems` and `rule_problems` still kept but a line's
## `max_per_run` (the owner, 2026-11-19: a reroll may break a kind's count, as long as every fixed
## kind, `least`, is still there; the boss deepest, fights enough on every way, rooms apart, sockets
## that meet). A candidate the same as the room (template, mirroring and kind) is one only when its
## kind fights (its foes are rolled again), is a shop (its shelf is rolled again as it opens,
## gameplay/rewards) or a reward room (its reward type is rolled again, `roll_type`; a kind with no
## `typed_rewards` has none). The most change wins: a candidate of another kind if there is one,
## else of another template, else the rest. Among other kinds the kind is picked first, by weight
## (`kind_weight`: its line's `weight` over one more than the rooms of it the biome holds already, so
## a kind the biome holds less of is likelier, and a kind with many templates or mirrorings is no
## likelier for it), then one of its candidates evenly; in the other tiers one candidate evenly.
## Null when there is none: the reroll is refused. A pure function, as `generate`.
static func reroll_room(definition: RunDefinition, content: RunContent, shapes: Dictionary, sim: Sim, players: int, map: BiomeMap, room: int, roll: int) -> BiomeMap:
	if definition == null or definition.biomes.is_empty() or content == null or sim == null or map == null or room <= 0 or room >= map.rooms():
		return null
	var rules: MapRules = definition.biomes[0]
	var now: RoomKind = content.kind(map.room_kinds[room])
	var shape_now: PieceShape = map.room_shape(room, shapes)
	if now == null or shape_now == null:
		return null
	var area: Rect2 = _area_of(map, shapes)
	var joined: Array[Vector4i] = []
	for bridge in map.bridges():
		for end in 2:
			if map.end_room(bridge, end) == room:
				var socket: int = map.end_socket(bridge, end)
				var at: Vector2 = map.room_places[room] + shape_now.socket_at[socket]
				joined.append(Vector4i(bridge, end, roundi(at.x), roundi(at.y)))
	var facings := PackedInt32Array()
	for row: Vector4i in joined:
		facings.append(shape_now.socket_facing[map.end_socket(row.x, row.y)])
	# The candidates by how much they change: another kind (by kind, in the table's order), another
	# template, the rest.
	var kinds_found: Array[KindRule] = []
	var by_kind: Dictionary = {}
	var same_kind: Array = [[], []]
	for rule: KindRule in rules.biome_lines(content, shapes):
		var kind: RoomKind = content.kind(rule.kind)
		if kind == null or kind.door != now.door or rule.kind == rules.start_kind:
			continue
		for host: RoomBase in rules.biome_templates(content, shapes, rule.kind, joined.size()):
			if host.id != map.room_templates[room] and map.room_templates.has(host.id):
				continue
			for mirror: int in PieceShape.MIRRORINGS:
				if host.id == map.room_templates[room] and mirror == map.room_mirrors[room] and rule.kind == map.room_kinds[room] and not kind.fills_with_enemies() and kind.fill != RoomKind.FILL_SHOP and not kind.typed_rewards:
					continue
				var made: BiomeMap = _refit(map, room, host.id, mirror, rule.kind, (shapes[host.id] as PieceShape).mirrored(mirror), joined, facings)
				if made == null or not area.encloses(made.room_shape(room, shapes).rect_at(made.room_places[room])):
					continue
				if made.problems(shapes).is_empty() and rule_problems(made, rules, content, shapes, true, false).is_empty():
					if rule.kind != map.room_kinds[room]:
						if not by_kind.has(rule.kind):
							kinds_found.append(rule)
							by_kind[rule.kind] = []
						(by_kind[rule.kind] as Array).append(made)
					else:
						(same_kind[0 if host.id != map.room_templates[room] else 1] as Array).append(made)
	var dice := MapDice.new(sim, REROLL_PURPOSE, roll * REROLL_KEYS + room, Step.size())
	var found: Array = []
	if not kinds_found.is_empty():
		var weights := PackedFloat32Array()
		for rule: KindRule in kinds_found:
			weights.append(kind_weight(map, room, rule))
		found = by_kind[kinds_found[dice.pick(Step.KINDS, weights)].kind] as Array
	else:
		found = same_kind[0] if not (same_kind[0] as Array).is_empty() else same_kind[1]
	if found.is_empty():
		return null
	var picked: BiomeMap = found[dice.below(Step.PLACE, found.size())] as BiomeMap
	var filled: Array = _fill_one(picked, room, definition, rules, content, players, dice)
	picked.refill_room(room, filled[0], filled[1], filled[2], filled[3])
	# A reward room's type is rolled again (the owner, 2026-11-19), any other kind's is none.
	var picked_kind: RoomKind = content.kind(picked.room_kinds[room])
	var type: RewardType = RewardType.new()
	if picked_kind != null and picked_kind.typed_rewards:
		type = roll_type(content.reward_table(picked_kind.rewards), content.cards, dice)
	if not type.is_any() or room < picked.room_reward_items.size():
		picked.type_room(room, type)
	return picked


## How likely a room reroll of `map`'s room `room` turns it into a room of `rule`'s kind, against
## the other kinds that fit: the line's `weight` over one more than the rooms of that kind the biome
## holds besides `room`.
static func kind_weight(map: BiomeMap, room: int, rule: KindRule) -> float:
	var held: int = 0
	for other in range(1, map.rooms()):
		if other != room and map.room_kinds[other] == rule.kind:
			held += 1
	return rule.weight / float(1 + held)


## A copy of `map` with room `room` as template `template` mirrored `mirror` (its shape `shape`) of
## kind `kind`, placed so that each bridge end of `joined` (bridge, end, the world point its socket
## was at), facing as `facings` says, meets a socket of the new shape there; null when one meets none.
static func _refit(map: BiomeMap, room: int, template: StringName, mirror: int, kind: StringName, shape: PieceShape, joined: Array[Vector4i], facings: PackedInt32Array) -> BiomeMap:
	if joined.is_empty():
		return null
	var first: Vector2 = Vector2(joined[0].z, joined[0].w)
	for anchor in shape.sockets():
		if shape.socket_facing[anchor] != facings[0]:
			continue
		var place: Vector2 = first - shape.socket_at[anchor]
		var sockets := PackedInt32Array()
		var taken: Dictionary = {}
		for at in joined.size():
			var point: Vector2 = Vector2(joined[at].z, joined[at].w)
			var meets: int = -1
			for socket in shape.sockets():
				if not taken.has(socket) and shape.socket_facing[socket] == facings[at] and (place + shape.socket_at[socket]).round() == point:
					meets = socket
					break
			if meets < 0:
				break
			taken[meets] = true
			sockets.append(meets)
		if sockets.size() != joined.size():
			continue
		var made: BiomeMap = map.copy()
		made.room_templates[room] = template
		made.room_mirrors[room] = mirror
		made.room_places[room] = place
		made.room_kinds[room] = kind
		for at in joined.size():
			made.bridge_ends[joined[at].x * BiomeMap.END_FIELDS + joined[at].y * 2 + 1] = sockets[at]
		made.work_out_depths()
		return made
	return null


## What `map`'s pieces cover together (BiomeWorld's area): a reroll keeps inside it.
static func _area_of(map: BiomeMap, shapes: Dictionary) -> Rect2:
	var whole := Rect2()
	for room in map.rooms():
		var shape: PieceShape = map.room_shape(room, shapes)
		if shape != null:
			whole = shape.rect_at(map.room_places[room]) if room == 0 else whole.merge(shape.rect_at(map.room_places[room]))
	for bridge in map.bridges():
		var shape: PieceShape = map.bridge_shape(bridge, shapes)
		if shape != null:
			whole = whole.merge(shape.rect_at(map.bridge_places[bridge]))
	return whole


## Step 7: each room of a kind with `typed_rewards` its reward type, rolled from its kind's table.
static func _type_rewards(map: BiomeMap, content: RunContent, sim: Sim) -> void:
	var dice := MapDice.new(sim, REWARD_PURPOSE, 0, 1)
	for room in map.rooms():
		var kind: RoomKind = content.kind(map.room_kinds[room])
		if kind != null and kind.typed_rewards:
			var type: RewardType = roll_type(content.reward_table(kind.rewards), content.cards, dice)
			if not type.is_any():
				map.type_room(room, type)


## A reward type rolled from `table` (a line by weight; a card line's card kind, then an element
## card, evenly) with `dice`'s step 0; any when the table gives nothing.
static func roll_type(table: RewardTable, cards: RewardCards, dice: MapDice) -> RewardType:
	if table == null:
		return RewardType.new()
	var weights := PackedFloat32Array()
	for entry: RewardEntry in table.entries:
		var weight: float = entry.weight if entry != null and entry.weight > 0.0 else 0.0
		if weight > 0.0 and entry.kind == ItemKinds.CARD and _kinds_given(entry, cards).is_empty():
			weight = 0.0
		weights.append(weight)
	if weights.is_empty() or Array(weights).max() <= 0.0:
		return RewardType.new()
	var line: RewardEntry = table.entries[dice.pick(0, weights)]
	if line.kind != ItemKinds.CARD:
		return RewardType.make(line.kind)
	var kinds: Array[StringName] = _kinds_given(line, cards)
	var kind: StringName = kinds[dice.below(0, kinds.size())]
	if kind != RewardType.ELEMENT_KIND:
		return RewardType.make(line.kind, kind)
	var elements: Array[StringName] = []
	for at in cards.size():
		if cards.kinds[at] == kind and cards.line_gives(line, at):
			elements.append(cards.ids[at])
	return RewardType.make(line.kind, kind, elements[dice.below(0, elements.size())])


## The card kinds the card line `line` gives among `cards`, in name order.
static func _kinds_given(line: RewardEntry, cards: RewardCards) -> Array[StringName]:
	var found: Array[StringName] = []
	for at in cards.size():
		if cards.kinds[at] != &"" and not found.has(cards.kinds[at]) and cards.line_gives(line, at):
			found.append(cards.kinds[at])
	found.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return found


## One attempt's map as it grows (steps 1 to 5): a generator's scratch, never state.
class Growth:
	extends RefCounted
	const DERIVED: Array[StringName] = [&"rules", &"content", &"shapes", &"dice", &"style", &"mirrored", &"crossings", &"room_templates", &"room_places", &"room_mirrors", &"room_lines", &"room_kinds", &"room_shapes", &"room_rects", &"room_depths", &"room_free", &"room_bridges", &"bridge_templates", &"bridge_places", &"bridge_mirrors", &"bridge_ends", &"bridge_rects", &"free_at", &"used", &"end_depth", &"last_off_way", &"loops_left"]

	var rules: MapRules = null
	var content: RunContent = null
	var shapes: Dictionary = {}
	var dice: MapDice = null
	var style: MapStyle = null
	## Mirrored shapes by "id:mirroring".
	var mirrored: Dictionary = {}
	## For each facing of a room's socket (`RoomSocket.Facing`), the bridges that cross from it
	## (`Crossing`), one for each walkway and placement of its ends, its mirrorings that place it so
	## together.
	var crossings: Array = [[], [], [], []]
	var room_templates: Array[StringName] = []
	var room_places: Array[Vector2] = []
	var room_mirrors: Array[int] = []
	## Each room's line (null for the start room) and kind.
	var room_lines: Array[KindRule] = []
	var room_kinds: Array[StringName] = []
	var room_shapes: Array[PieceShape] = []
	var room_rects: Array[Rect2] = []
	## Each room's depth, the fewest bridges from the start room (worked out again after a loop).
	var room_depths: Array[int] = []
	## Each room's sockets, 1 where free.
	var room_free: Array[PackedByteArray] = []
	var room_bridges: Array[int] = []
	var bridge_templates: Array[StringName] = []
	var bridge_places: Array[Vector2] = []
	var bridge_mirrors: Array[int] = []
	var bridge_ends: PackedInt32Array = PackedInt32Array()
	var bridge_rects: Array[Rect2] = []
	## The free sockets of rooms a loop may join, by where they are and the way they face
	## (`Vector3i(x, y, facing)`), to their room and socket (`Vector2i`).
	var free_at: Dictionary = {}
	## The templates the biome holds (the start room's not counted).
	var used: Dictionary = {}
	## How deep the boss stands.
	var end_depth: int = 0
	## The room placed off the way last (-1: none yet).
	var last_off_way: int = -1
	## How many loops the style may still close.
	var loops_left: int = 0

	func _init(of_rules: MapRules, of_content: RunContent, of_shapes: Dictionary, of_dice: MapDice) -> void:
		rules = of_rules
		content = of_content
		shapes = of_shapes
		dice = of_dice
		for walkway: RoomBase in rules.biome_walkways(content, shapes):
			_add_crossings(walkway.id)

	## Grows the map: "" when it is made, else why not.
	func grow() -> String:
		var count: int = rules.rooms_min + dice.below(Step.ROOMS, rules.rooms_max - rules.rooms_min + 1)
		var weights := PackedFloat32Array()
		for of_style: MapStyle in rules.styles:
			weights.append(of_style.weight)
		style = rules.styles[dice.pick(Step.STYLE, weights)]
		loops_left = style.loops
		var lines: Array[KindRule] = rules.biome_lines(content, shapes)
		var end_line: KindRule = null
		for rule: KindRule in lines:
			if rule.stands_deepest():
				end_line = rule
		var pool: Array[KindRule] = _roll_kinds(lines, end_line, count)
		var open_way: int = 0
		for rule: KindRule in pool:
			if not rule.dead_end:
				open_way += 1
		var way: int = roundi(style.way_share * float(pool.size() + 1))
		way = clampi(way, rules.fights_on_way + 1, open_way + 1)
		if way < 2 and not pool.is_empty():
			way = mini(2, open_way + 1)
		end_depth = way
		var on_way: Array[KindRule] = []
		var why: String = _pick_way(pool, way, end_line, on_way)
		if why != "":
			return why
		why = _place_start()
		if why != "":
			return why
		for depth in range(1, way):
			why = _place(on_way[depth - 1], depth - 1, 2)
			if why != "":
				return "on the way, %s" % why
		why = _place(end_line, way - 1, 1)
		if why != "":
			return "the boss's room: %s" % why
		for rule: KindRule in _off_way_order(pool):
			why = _place_off_way(rule)
			if why != "":
				return why
			# A loop is closed as soon as it can be, before a later room stands in its way.
			_close_loops()
		var problems: PackedStringArray = BiomeGenerator.rule_problems(to_map(), rules, content, shapes)
		return problems[0] if not problems.is_empty() else ""

	## The map grown so far, moved so its corner is at (0, 0), its depths worked out.
	func to_map() -> BiomeMap:
		var map := BiomeMap.new()
		map.biome = rules.biome
		map.style = style.id if style != null else &""
		var corner := Vector2(INF, INF)
		for rect: Rect2 in room_rects + bridge_rects:
			corner = corner.min(rect.position)
		if room_rects.is_empty():
			corner = Vector2.ZERO
		for room in room_templates.size():
			map.add_room(room_templates[room], room_places[room] - corner, room_mirrors[room], room_kinds[room])
		for bridge in bridge_templates.size():
			var at: int = bridge * BiomeMap.END_FIELDS
			map.add_bridge(bridge_templates[bridge], bridge_places[bridge] - corner, bridge_mirrors[bridge], bridge_ends[at], bridge_ends[at + 1], bridge_ends[at + 2], bridge_ends[at + 3])
		map.work_out_depths()
		return map

	# --- Step 2: the kinds ---------------------------------------------------------------------

	## The rooms' lines past the start room and the boss: each line's least, the chance rooms within
	## `rooms_max`, then the lines with no limit by weight until `count` rooms (the boss's counted).
	func _roll_kinds(lines: Array[KindRule], end_line: KindRule, count: int) -> Array[KindRule]:
		var pool: Array[KindRule] = []
		for rule: KindRule in lines:
			if rule != end_line:
				for k in rule.least:
					pool.append(rule)
		# The chance rooms: every line's rolls made in line order, then the rooms won take the slots
		# left within `rooms_max` line by line, the lines with the fewest chance rooms first (line
		# order between two alike), so a one-off (a challenge room) is never crowded out by a line of
		# many (the treasure rooms fill what is left: the owner, 2026-11-19). Added in line order.
		var won := PackedInt32Array()
		won.resize(lines.size())
		for at in lines.size():
			var rule: KindRule = lines[at]
			if rule == end_line or rule.chance <= 0.0:
				continue
			for k in rule.max_per_run - rule.least:
				if dice.roll(Step.KINDS) < rule.chance:
					won[at] += 1
		var granted := PackedInt32Array()
		granted.resize(lines.size())
		var slots: int = maxi(rules.rooms_max - 1 - pool.size(), 0)
		for at: int in _chance_order(lines):
			var take: int = mini(won[at], slots)
			granted[at] = take
			slots -= take
		for at in lines.size():
			for k in granted[at]:
				pool.append(lines[at])
		var fillers: Array[KindRule] = []
		var weights := PackedFloat32Array()
		# A filler takes no more rooms than templates host it (a template stands once a biome).
		var room_left := PackedInt32Array()
		for rule: KindRule in lines:
			var left: int = rules.biome_templates(content, shapes, rule.kind, 1).size() - pool.count(rule)
			if rule != end_line and rule.max_per_run == 0 and left > 0:
				fillers.append(rule)
				weights.append(rule.weight)
				room_left.append(left)
		while pool.size() + 1 < count and not fillers.is_empty():
			var at: int = dice.pick(Step.KINDS, weights)
			pool.append(fillers[at])
			room_left[at] -= 1
			if room_left[at] <= 0:
				fillers.remove_at(at)
				weights.remove_at(at)
				room_left.remove_at(at)
		return pool

	## The lines' indices in the order their chance rooms take slots: the fewest chance rooms
	## (`max_per_run` - `least`) first, line order between two alike.
	static func _chance_order(lines: Array[KindRule]) -> PackedInt32Array:
		var order := PackedInt32Array()
		for at in lines.size():
			var rooms: int = lines[at].max_per_run - lines[at].least
			var put: int = order.size()
			while put > 0 and lines[order[put - 1]].max_per_run - lines[order[put - 1]].least > rooms:
				put -= 1
			order.insert(put, at)
		return order

	# --- Step 3: the way -----------------------------------------------------------------------

	## The rooms on the way, depth 1 to `way` - 1, taken out of `pool` into `on_way`: by chance among
	## those that take their depth, are no dead end and may follow the room before, fights only once
	## the fights still needed fill every place left. "" when the way is found, else why not.
	func _pick_way(pool: Array[KindRule], way: int, end_line: KindRule, on_way: Array[KindRule]) -> String:
		var fights_left: int = rules.fights_on_way
		var before: StringName = rules.start_kind
		for depth in range(1, way):
			var places_left: int = way - depth
			var open: Array[int] = []
			for i in pool.size():
				var rule: KindRule = pool[i]
				if rule.dead_end or not rule.may_follow(before) or not BiomeGenerator._fills_at(rules, content, rule, depth, way):
					continue
				if fights_left >= places_left and not BiomeGenerator._fights(content, rule.kind):
					continue
				open.append(i)
			if open.is_empty():
				return "no kind may stand %d bridges deep on the way to the boss." % depth
			var rule: KindRule = pool.pop_at(open[dice.below(Step.WAY, open.size())])
			on_way.append(rule)
			if BiomeGenerator._fights(content, rule.kind):
				fights_left -= 1
			before = rule.kind
		if not end_line.may_follow(before) or not BiomeGenerator._fills_at(rules, content, end_line, way, way):
			return "the boss may not stand %d bridges deep, after a '%s'." % [way, before]
		return ""

	# --- Step 4: the rest off the way ----------------------------------------------------------

	## The rooms off the way in the order they are placed: those that are no dead end first, then
	## the dead ends, each in an order by chance.
	func _off_way_order(pool: Array[KindRule]) -> Array[KindRule]:
		var open: Array[KindRule] = []
		var ends: Array[KindRule] = []
		for rule: KindRule in pool:
			if rule.dead_end:
				ends.append(rule)
			else:
				open.append(rule)
		_shuffle(open)
		_shuffle(ends)
		return open + ends

	func _shuffle(rules_list: Array[KindRule]) -> void:
		for i in range(rules_list.size() - 1, 0, -1):
			var j: int = dice.below(Step.ORDER, i + 1)
			var held: KindRule = rules_list[i]
			rules_list[i] = rules_list[j]
			rules_list[j] = held

	## A room of `rule` off a room placed: the last room off the way by the style's `branch_chain`,
	## else one by weight (1, and `hub_pull` for each of its bridges), each tried until one has a
	## placement. "" when it is placed, else why not.
	func _place_off_way(rule: KindRule) -> String:
		var parents: Array[int] = []
		for room in room_templates.size():
			if _may_lead_to(room, rule):
				parents.append(room)
		if last_off_way >= 0 and parents.has(last_off_way) and dice.roll(Step.PARENT) < style.branch_chain:
			if _place(rule, last_off_way, 1) == "":
				last_off_way = room_templates.size() - 1
				return ""
			parents.erase(last_off_way)
		if style.loop_pull > 0.0 and not parents.is_empty():
			# A style that closes loops weighs every placement off every room at once, so one that
			# leaves a loop to close is found wherever it is.
			var all_weights := PackedFloat32Array()
			for room: int in parents:
				all_weights.append(1.0 + style.hub_pull * float(room_bridges[room]))
			if _place_among(rule, parents, all_weights, 1) == "":
				last_off_way = room_templates.size() - 1
				return ""
			parents.clear()
		while not parents.is_empty():
			var weights := PackedFloat32Array()
			for room: int in parents:
				weights.append(1.0 + style.hub_pull * float(room_bridges[room]))
			var at: int = dice.pick(Step.PARENT, weights)
			if _place(rule, parents[at], 1) == "":
				last_off_way = room_templates.size() - 1
				return ""
			parents.remove_at(at)
		return "no room placed may lead to a '%s' (a free socket, a depth it takes, room round it)." % rule.kind

	## True when room `room` may lead to a room of `rule`: it is no dead end and not the boss's, it
	## has a free socket, and a room one bridge deeper is shallower than the boss and at a depth
	## `rule` takes, after a kind it may follow.
	func _may_lead_to(room: int, rule: KindRule) -> bool:
		var line: KindRule = room_lines[room]
		if line != null and (line.dead_end or line.stands_deepest()):
			return false
		if not room_free[room].has(1):
			return false
		var depth: int = room_depths[room] + 1
		return depth < end_depth and rule.may_follow(room_kinds[room]) and BiomeGenerator._fills_at(rules, content, rule, depth, end_depth)

	# --- Placing -------------------------------------------------------------------------------

	## The start room: a template hosting the start kind, any mirroring, at (0, 0).
	func _place_start() -> String:
		var hosts: Array[RoomBase] = rules.biome_templates(content, shapes, rules.start_kind, 1)
		if hosts.is_empty():
			return "no start room."
		var host: RoomBase = hosts[dice.below(Step.PLACE, hosts.size())]
		var mirror: int = PieceShape.MIRRORINGS[dice.below(Step.PLACE, PieceShape.MIRRORINGS.size())]
		_add_room(host.id, mirror, Vector2.ZERO, null, rules.start_kind, 0)
		return ""

	## A room of `rule` off room `parent`, of a template with `sockets` sockets at least (`_place_among`).
	func _place(rule: KindRule, parent: int, sockets: int) -> String:
		return _place_among(rule, [parent] as Array[int], PackedFloat32Array([1.0]), sockets)

	## A room of `rule` off one of `parents` (each by its weight in `weights`), of a template with
	## `sockets` sockets at least: a template by chance, then every placement of it that fits (the
	## class doc), one picked by its parent's weight (the next template by chance where none fits);
	## in a style with a `loop_pull`, every template's placements at once, each weighed also by 1 and
	## the pull for each bridge's span it leaves between two free sockets.
	## "" when it is placed, else why not.
	func _place_among(rule: KindRule, parents: Array[int], weights: PackedFloat32Array, sockets: int) -> String:
		var hosts: Array[RoomBase] = []
		for room: RoomBase in rules.biome_templates(content, shapes, rule.kind, sockets):
			if not used.has(room.id):
				hosts.append(room)
		if hosts.is_empty():
			return "every %s template hosting '%s' with %d sockets stands in the biome already." % [rules.biome, rule.kind, sockets]
		var pull: float = style.loop_pull if not (rule.dead_end or rule.stands_deepest()) else 0.0
		while not hosts.is_empty():
			# A style that closes loops weighs every template's placements at once (a loop's corner
			# is rare, so it is looked for wherever it is); any other takes a template by chance.
			var trying: Array[RoomBase] = []
			if pull > 0.0:
				trying = hosts.duplicate()
				hosts.clear()
			else:
				trying.append(hosts.pop_at(dice.below(Step.PLACE, hosts.size())))
			var found: Array = []  # [parent, socket, crossing, template, mirroring, its socket, its place, the bridge's place]
			var found_weights := PackedFloat32Array()
			for host: RoomBase in trying:
				for k in parents.size():
					_gather(parents[k], weights[k], pull, host.id, rule.kind, found, found_weights)
			if found.is_empty():
				continue
			var pick: Array = found[dice.pick(Step.PLACE, found_weights)]
			var parent: int = pick[0]
			var crossing: Crossing = pick[2]
			var way: int = dice.below(Step.PLACE, crossing.mirrors.size())
			var room: int = _add_room(pick[3], pick[4], pick[6], rule, rule.kind, room_depths[parent] + 1)
			_add_bridge(crossing, way, pick[7], parent, pick[1], room, pick[5])
			return ""
		return "no placement for a '%s' off room %d (%s)." % [rule.kind, parents[0], room_templates[parents[0]]]

	## Every placement of template `host` off room `parent` (the class doc) into `found`, each
	## weighed in `found_weights` by `weight` times 1 and `pull` for each loop it leaves to close.
	func _gather(parent: int, weight: float, pull: float, host: StringName, kind: StringName, found: Array, found_weights: PackedFloat32Array) -> void:
		var parent_shape: PieceShape = room_shapes[parent]
		for socket in parent_shape.sockets():
			if room_free[parent][socket] == 0:
				continue
			var at: Vector2 = room_places[parent] + parent_shape.socket_at[socket]
			for crossing: Crossing in crossings[parent_shape.socket_facing[socket]]:
				var bridge_place: Vector2 = at - crossing.from_at
				var bridge_rect := Rect2(bridge_place, crossing.size)
				if not _bridge_clear(bridge_rect, parent, -1):
					continue
				var far: Vector2 = at + crossing.span
				var facing: int = RoomSocket.opposite(crossing.far_facing)
				for mirror: int in PieceShape.MIRRORINGS:
					var shape: PieceShape = _shape(host, mirror)
					for its in shape.sockets():
						if shape.socket_facing[its] != facing:
							continue
						var place: Vector2 = far - shape.socket_at[its]
						var rect := Rect2(place, shape.size)
						if not _room_clear(rect) or _crosses_bridges(rect):
							continue
						found.append([parent, socket, crossing, host, mirror, its, place, bridge_place])
						found_weights.append(weight * (1.0 + (pull * float(_closable(shape, place, its, parent, kind)) if pull > 0.0 else 0.0)))

	## True when a room at `rect` keeps GAP clear of every room placed.
	func _room_clear(rect: Rect2) -> bool:
		var grown: Rect2 = rect.grow(GAP)
		for other: Rect2 in room_rects:
			if grown.intersects(other):
				return false
		return true

	## True when a room at `rect` lies over no bridge placed.
	func _crosses_bridges(rect: Rect2) -> bool:
		for other: Rect2 in bridge_rects:
			if rect.intersects(other):
				return true
		return false

	## True when a bridge at `rect` lies over no other bridge, and over no room but `a` and `b`.
	func _bridge_clear(rect: Rect2, a: int, b: int) -> bool:
		for other: Rect2 in bridge_rects:
			if rect.intersects(other):
				return false
		for room in room_rects.size():
			if room != a and room != b and rect.intersects(room_rects[room]):
				return false
		return true

	## How many of a room's free sockets (`shape` at `place`, its socket `joined` taken; of kind
	## `kind`, hung off `parent`) lie a bridge's span from a free socket a loop may join, of a room
	## but `parent`, where a loop's bridge there would keep the rules (checked on the map as it would
	## be, `_loop_keeps`: such spans are few).
	func _closable(shape: PieceShape, place: Vector2, joined: int, parent: int, kind: StringName) -> int:
		var count: int = 0
		for socket in shape.sockets():
			if socket == joined:
				continue
			var at: Vector2 = place + shape.socket_at[socket]
			for crossing: Crossing in crossings[shape.socket_facing[socket]]:
				var far: Vector2 = at + crossing.span
				var key := Vector3i(roundi(far.x), roundi(far.y), RoomSocket.opposite(crossing.far_facing))
				if not free_at.has(key):
					continue
				var other: int = (free_at[key] as Vector2i).x
				if other == parent or not _bridge_clear(Rect2(at - crossing.from_at, crossing.size), other, -1):
					continue
				if _loop_keeps(parent, kind, other):
					count += 1
		return count

	func _shape(id: StringName, mirror: int) -> PieceShape:
		var key: String = "%s:%d" % [id, mirror]
		if not mirrored.has(key):
			mirrored[key] = (shapes[id] as PieceShape).mirrored(mirror)
		return mirrored[key]

	func _add_room(template: StringName, mirror: int, place: Vector2, rule: KindRule, kind: StringName, depth: int) -> int:
		var shape: PieceShape = _shape(template, mirror)
		var room: int = room_templates.size()
		room_templates.append(template)
		room_places.append(place)
		room_mirrors.append(mirror)
		room_lines.append(rule)
		room_kinds.append(kind)
		room_shapes.append(shape)
		room_rects.append(shape.rect_at(place))
		room_depths.append(depth)
		var free := PackedByteArray()
		free.resize(shape.sockets())
		free.fill(1)
		var loops: bool = rule == null or not (rule.dead_end or rule.stands_deepest())
		room_free.append(free)
		room_bridges.append(0)
		if rule != null:
			used[template] = true
		if loops:
			for socket in shape.sockets():
				free_at[_key(room, socket)] = Vector2i(room, socket)
		return room

	func _key(room: int, socket: int) -> Vector3i:
		var at: Vector2 = room_places[room] + room_shapes[room].socket_at[socket]
		return Vector3i(roundi(at.x), roundi(at.y), room_shapes[room].socket_facing[socket])

	## A bridge of `crossing` (its `way`th mirroring) at `place`, its end at room `a`'s socket
	## `socket_a` and its far end at room `b`'s `socket_b`.
	func _add_bridge(crossing: Crossing, way: int, place: Vector2, a: int, socket_a: int, b: int, socket_b: int) -> void:
		var from_end: int = crossing.ends[way]
		var ends: PackedInt32Array = PackedInt32Array([a, socket_a, b, socket_b]) if from_end == 0 else PackedInt32Array([b, socket_b, a, socket_a])
		bridge_templates.append(crossing.template)
		bridge_places.append(place)
		bridge_mirrors.append(crossing.mirrors[way])
		bridge_ends.append_array(ends)
		bridge_rects.append(Rect2(place, crossing.size))
		for end: Vector2i in [Vector2i(a, socket_a), Vector2i(b, socket_b)]:
			room_free[end.x][end.y] = 0
			room_bridges[end.x] += 1
			free_at.erase(_key(end.x, end.y))

	## The crossings of walkway `id`: for each of its mirrorings and each end, the facing of the room
	## socket that end meets, grouped where they place the bridge alike.
	func _add_crossings(id: StringName) -> void:
		for mirror: int in PieceShape.MIRRORINGS:
			var shape: PieceShape = _shape(id, mirror)
			for end in 2:
				var facing: int = RoomSocket.opposite(shape.socket_facing[end])
				var span: Vector2 = shape.socket_at[1 - end] - shape.socket_at[end]
				var far_facing: int = shape.socket_facing[1 - end]
				var same: Crossing = null
				for crossing: Crossing in crossings[facing]:
					if crossing.template == id and crossing.from_at == shape.socket_at[end] and crossing.span == span and crossing.far_facing == far_facing:
						same = crossing
				if same == null:
					same = Crossing.new()
					same.template = id
					same.from_at = shape.socket_at[end]
					same.span = span
					same.far_facing = far_facing
					same.size = shape.size
					crossings[facing].append(same)
				same.mirrors.append(mirror)
				same.ends.append(end)

	# --- Step 5: the loops ---------------------------------------------------------------------

	## Up to the style's loops still left, bridges between two free sockets a bridge's ends meet, of
	## two rooms not yet joined, each by chance among those that keep the rules.
	func _close_loops() -> void:
		while loops_left > 0:
			var found: Array = []  # [crossing, the bridge's place, room a, socket a, room b, socket b]
			for key: Vector3i in free_at:
				var from: Vector2i = free_at[key]
				var at := Vector2(key.x, key.y)
				for crossing: Crossing in crossings[key.z]:
					var far: Vector2 = at + crossing.span
					var other_key := Vector3i(roundi(far.x), roundi(far.y), RoomSocket.opposite(crossing.far_facing))
					if not free_at.has(other_key):
						continue
					var to: Vector2i = free_at[other_key]
					if to.x == from.x or to.x < from.x or _joined(from.x, to.x):
						continue
					var place: Vector2 = at - crossing.from_at
					if not _bridge_clear(Rect2(place, crossing.size), from.x, to.x):
						continue
					found.append([crossing, place, from.x, from.y, to.x, to.y])
			var kept: Array = []
			for loop_bridge: Array in found:
				if _keeps_rules(loop_bridge):
					kept.append(loop_bridge)
			if kept.is_empty():
				return
			var pick: Array = kept[dice.below(Step.LOOPS, kept.size())]
			var crossing: Crossing = pick[0]
			loops_left -= 1
			_add_bridge(crossing, dice.below(Step.LOOPS, crossing.mirrors.size()), pick[1], pick[2], pick[3], pick[4], pick[5])
			# A loop can shorten a way: the depths the next rooms hang off are the map's.
			var depths: PackedInt32Array = to_map().depths
			for room in room_depths.size():
				room_depths[room] = depths[room]

	func _joined(a: int, b: int) -> bool:
		for bridge in bridge_templates.size():
			var at: int = bridge * BiomeMap.END_FIELDS
			if (bridge_ends[at] == a and bridge_ends[at + 2] == b) or (bridge_ends[at] == b and bridge_ends[at + 2] == a):
				return true
		return false

	## True when the map grown so far, with a room of `kind` off room `parent` that is also bridged to
	## room `other`, would keep the rules so far (`rule_problems` of a map still growing): only who
	## joins whom is read.
	func _loop_keeps(parent: int, kind: StringName, other: int) -> bool:
		var map: BiomeMap = to_map()
		var room: int = map.add_room(&"", Vector2.ZERO, 0, kind)
		map.add_bridge(&"", Vector2.ZERO, 0, parent, 0, room, 0)
		map.add_bridge(&"", Vector2.ZERO, 0, other, 0, room, 1)
		map.work_out_depths()
		for line: String in BiomeGenerator.rule_problems(map, rules, content, shapes, false):
			# The made-up room's template is no template: only the rules of who joins whom count.
			if not line.begins_with("room %d's template" % room):
				return false
		return true

	## True when the map with the loop's bridge `loop_bridge` still keeps the rules so far (a loop
	## changes no count; the whole map is checked once grown).
	func _keeps_rules(loop_bridge: Array) -> bool:
		var map: BiomeMap = to_map()
		var crossing: Crossing = loop_bridge[0]
		# Only the joins and kinds are checked: its place is the generator's (checked clear already).
		map.add_bridge(crossing.template, Vector2.ZERO, crossing.mirrors[0], loop_bridge[2], loop_bridge[3], loop_bridge[4], loop_bridge[5])
		map.work_out_depths()
		return BiomeGenerator.rule_problems(map, rules, content, shapes, false).is_empty()


## A way a walkway crosses from a room's socket: placed with its end at the socket (`from_at`, in its
## own pixels), its far end `span` on from there, facing `far_facing`; the mirrorings of it (and
## which of its ends meets the room socket in each) that place it so.
class Crossing:
	extends RefCounted
	var template: StringName = &""
	var from_at: Vector2 = Vector2.ZERO
	var span: Vector2 = Vector2.ZERO
	var far_facing: int = 0
	var size: Vector2 = Vector2.ZERO
	var mirrors: Array[int] = []
	var ends: Array[int] = []
