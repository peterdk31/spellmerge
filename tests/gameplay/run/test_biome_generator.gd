extends "res://tests/support/suite.gd"
## A biome's map generator (connected biomes CB5, `BiomeGenerator`, docs/milestones/
## connected-biomes.md, step CB5), on made-up content (tests/support/made_up_biome.gd: every kind of
## decision 1, until the crypt has their templates): every style makes valid maps over many seeds
## (the map's own rules, `BiomeMap.problems`, and the biome's, `rule_problems`): the boss deepest, at
## least 4 fights on every way to it, the fixed kinds always there and the chance kinds now and then,
## a template once a biome, every mirroring; the styles differ as their weights say; the same seed is
## the same map; the rooms filled and scaled by depth and players; the rule changes on the new
## numbers; the validator names a run whose content makes no map, the crypt's of today among them; and
## a map generated from the crypt's own rooms is laid and walked.
##
## The seeds take seconds: the runner plays the file in processes of their own (tests/support/suite.gd):
# unit-test-shards: 4

const MadeUpBiome := preload("res://tests/support/made_up_biome.gd")
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## Seeds each style is generated from.
const SEEDS: int = 150

var _biome: MadeUpBiome = null


func before_each() -> void:
	super.before_each()
	_biome = MadeUpBiome.new()


func _sim(seed_value: int) -> Sim:
	return Sim.seeded(seed_value)


func _map(definition: RunDefinition, seed_value: int, players: int = 1) -> BiomeMap:
	return BiomeGenerator.generate(definition, _biome.content, _biome.shapes, _sim(seed_value), players)


## The maps of `style` alone over SEEDS seeds, each checked against every rule; returns them.
func _maps_of(style: MapStyle) -> Array[BiomeMap]:
	var rules: MapRules = MadeUpBiome.rules([style] as Array[MapStyle])
	var definition: RunDefinition = MadeUpBiome.run(rules)
	var maps: Array[BiomeMap] = []
	var failed: int = 0
	for seed_value in SEEDS:
		var map: BiomeMap = _map(definition, seed_value)
		if not map.is_made():
			failed += 1
			check(false, "%s, seed %d: no map: %s" % [style.id, seed_value, "\n".join(map.not_made)])
			continue
		var problems: PackedStringArray = map.problems(_biome.shapes) + BiomeGenerator.rule_problems(map, rules, _biome.content, _biome.shapes)
		if not problems.is_empty():
			failed += 1
			check(false, "%s, seed %d: %s" % [style.id, seed_value, "\n".join(problems)])
		maps.append(map)
	check_equal(failed, 0, "every seed of %s makes a sound map" % style.id)
	return maps


func _deepest(map: BiomeMap) -> int:
	return map.room_kinds.find(&"boss")


func _bridges_of(map: BiomeMap, room: int) -> int:
	var count: int = 0
	for bridge in map.bridges():
		if map.end_room(bridge, 0) == room or map.end_room(bridge, 1) == room:
			count += 1
	return count


# --- Every style, many seeds -------------------------------------------------------------------

func test_the_long_style_makes_sound_maps() -> void:
	_sound_maps(MadeUpBiome.four_styles()[0])


func test_the_branching_style_makes_sound_maps() -> void:
	_sound_maps(MadeUpBiome.four_styles()[1])


func test_the_loop_style_makes_sound_maps() -> void:
	_sound_maps(MadeUpBiome.four_styles()[2])


func test_the_hub_style_makes_sound_maps() -> void:
	_sound_maps(MadeUpBiome.four_styles()[3])


## Every seed of `style` a sound map with the boss deepest and 4 fights on every way to it.
func _sound_maps(style: MapStyle) -> void:
	for map: BiomeMap in _maps_of(style):
		var boss: int = _deepest(map)
		check(boss > 0, "%s: a boss" % style.id)
		for room in map.rooms():
			if room != boss and map.depths[room] >= map.depths[boss]:
				check(false, "%s: room %d as deep as the boss" % [style.id, room])
		check(BiomeGenerator.fights_on_way(map, _biome.content, boss) >= 4, "%s: 4 fights on every way to the boss" % style.id)
		check_equal(map.style, style.id, "the map says its style")
		check_equal(map.room_kinds[0], &"start", "room 0 is the start room")
		var past_start: int = map.rooms() - 1
		check(past_start >= 8 and past_start <= 12, "%s: 8 to 12 rooms past the start room (%d)" % [style.id, past_start])


func test_the_fixed_kinds_are_always_there_and_the_chance_kinds_now_and_then() -> void:
	var definition: RunDefinition = MadeUpBiome.run()
	var with_fountain: int = 0
	var with_treasure: int = 0
	var two_secrets: int = 0
	for seed_value in SEEDS:
		var map: BiomeMap = _map(definition, seed_value)
		var count: Dictionary = {}
		for kind: StringName in map.room_kinds:
			count[kind] = int(count.get(kind, 0)) + 1
		check_equal(int(count.get(&"boss", 0)), 1, "one boss")
		check_equal(int(count.get(&"reward", 0)), 1, "a reward room")
		check_equal(int(count.get(&"shop", 0)), 1, "a shop")
		check(int(count.get(&"secret", 0)) in [1, 2], "one or two secret rooms")
		check(int(count.get(&"fight", 0)) + int(count.get(&"challenge", 0)) >= 4, "four fights at least")
		with_fountain += int(count.get(&"fountain", 0))
		with_treasure += int(count.get(&"treasure", 0))
		two_secrets += 1 if int(count.get(&"secret", 0)) == 2 else 0
		for room in map.rooms():
			if map.room_kinds[room] in [&"secret", &"treasure", &"boss"]:
				check_equal(_bridges_of(map, room), 1, "a dead end has one bridge")
	for counted: Array in [["a fountain", with_fountain], ["a treasure room", with_treasure], ["a second secret", two_secrets]]:
		check(counted[1] > SEEDS / 5 and counted[1] < SEEDS * 4 / 5, "%s by chance: %d of %d maps" % [counted[0], counted[1], SEEDS])


func test_a_template_stands_once_and_every_mirroring_is_placed() -> void:
	var mirrors: Dictionary = {}
	for seed_value in SEEDS:
		var map: BiomeMap = _map(MadeUpBiome.run(), seed_value)
		var seen: Dictionary = {}
		for room in range(1, map.rooms()):
			check(not seen.has(map.room_templates[room]), "seed %d: %s once" % [seed_value, map.room_templates[room]])
			seen[map.room_templates[room]] = true
		for mirror: int in map.room_mirrors:
			mirrors[mirror] = true
		for mirror: int in map.bridge_mirrors:
			mirrors[mirror] = true
	check_equal(mirrors.size(), 4, "rooms are placed in all four mirrorings")


func test_the_styles_differ_as_their_weights_say() -> void:
	var boss_depth: Dictionary = {}
	var loops: Dictionary = {}
	var hub: Dictionary = {}
	for style: MapStyle in MadeUpBiome.four_styles():
		var definition: RunDefinition = MadeUpBiome.run(MadeUpBiome.rules([style] as Array[MapStyle]))
		var depth: int = 0
		var looped: int = 0
		var widest: int = 0
		for seed_value in 60:
			var map: BiomeMap = _map(definition, seed_value)
			depth += map.depths[_deepest(map)]
			looped += 1 if map.bridges() >= map.rooms() else 0
			var most: int = 0
			for room in map.rooms():
				most = maxi(most, _bridges_of(map, room))
			widest += most
		boss_depth[style.id] = depth
		loops[style.id] = looped
		hub[style.id] = widest
	# A way of at least fights_on_way + 1 rooms: the branching and hub maps' ways are both near it.
	check(boss_depth[&"long"] > boss_depth[&"branching"] and boss_depth[&"long"] > boss_depth[&"hub"] and boss_depth[&"branching"] >= boss_depth[&"hub"], "the long map's boss stands deepest: %s" % boss_depth)
	check(loops[&"loop"] > 20 and loops[&"long"] == 0 and loops[&"branching"] == 0 and loops[&"hub"] == 0, "the loop style closes loops where the shapes leave room for one (%d of 60 maps), the others none: %s" % [loops[&"loop"], loops])
	check(hub[&"hub"] > hub[&"long"] and hub[&"hub"] > hub[&"branching"], "the hub's busiest room has the most bridges: %s" % hub)


func test_the_same_seed_is_the_same_map() -> void:
	var definition: RunDefinition = MadeUpBiome.run()
	var first: BiomeMap = _map(definition, 7)
	check(first.same_as(_map(definition, 7)), "seed 7 twice")
	check(first.same_as(BiomeGenerator.generate(definition, MadeUpBiome.new().content, MadeUpBiome.new().shapes, _sim(7))), "and with the content gathered again")
	var differ: int = 0
	for seed_value in range(8, 28):
		differ += 0 if _map(definition, seed_value).same_as(first) else 1
	check_equal(differ, 20, "other seeds, other maps")


# --- The fill ----------------------------------------------------------------------------------

func test_each_room_is_filled_by_its_kind_and_scaled_by_its_depth_and_players() -> void:
	var definition: RunDefinition = MadeUpBiome.run()
	var rules: MapRules = definition.biomes[0]
	for seed_value in 40:
		var map: BiomeMap = _map(definition, seed_value, 1 + seed_value % 4)
		check_equal(map.problems(_biome.shapes), PackedStringArray(), "a sound map, its fill too")
		for room in map.rooms():
			var scale: float = definition.biome_room_scale(rules, map.depths[room], 1 + seed_value % 4)
			check(absf(map.room_scales[room] - scale) < 0.0001, "room %d scaled by its depth and the players (%s, %s)" % [room, map.room_scales[room], scale])
			var enemies: Array[StringName] = map.enemies_of(room)
			match map.room_kinds[room]:
				&"fight", &"challenge":
					check(not enemies.is_empty(), "a fight has enemies")
					var cost: int = 0
					for id: StringName in enemies:
						var enemy: EnemyBase = _enemy(id)
						check(enemy != null and not enemy.boss and enemy.min_depth <= map.depths[room], "%s fights at depth %d" % [id, map.depths[room]])
						cost += enemy.cost if enemy != null else 0
					check(cost <= RunScaling.scaled_budget(rules.room_budget, scale) + 10, "within its budget (the first may cost more)")
				&"boss":
					check_equal(enemies, [&"king"] as Array[StringName], "the boss's room its boss")
				_:
					check(enemies.is_empty(), "a %s has no enemies" % map.room_kinds[room])
	check(definition.biome_room_scale(rules, 8, 1) == 2.0 and definition.biome_room_scale(rules, 11, 1) == 2.0, "the scaling reaches its end at scale_depth and keeps it")
	check(definition.biome_room_scale(rules, 0, 4) == 1.5, "four players at the start")
	var map_one: BiomeMap = _map(definition, 3, 1)
	var map_four: BiomeMap = _map(definition, 3, 4)
	check_equal(map_four.room_templates, map_one.room_templates, "the same rooms for any number of players")


func _enemy(id: StringName) -> EnemyBase:
	for enemy: EnemyBase in _biome.content.enemies:
		if enemy.id == id:
			return enemy
	return null


# --- The rules' numbers and their changes ------------------------------------------------------

func test_the_counts_follow_the_rules_and_their_changes() -> void:
	var definition: RunDefinition = MadeUpBiome.run()
	definition.changes = [
		RunRuleChange.make(&"more_rooms", RunRuleChange.Target.ROOMS_MIN, 11.0, RunRuleChange.How.SET, MadeUpBiome.BIOME),
		RunRuleChange.make(&"more_rooms", RunRuleChange.Target.ROOMS_MAX, 12.0, RunRuleChange.How.SET, MadeUpBiome.BIOME),
		RunRuleChange.make(&"fountains", RunRuleChange.Target.KIND_LEAST, 1.0, RunRuleChange.How.SET, MadeUpBiome.BIOME, &"fountain"),
		RunRuleChange.make(&"only_long", RunRuleChange.Target.STYLE_WEIGHT, 0.01, RunRuleChange.How.SET, MadeUpBiome.BIOME, &"", &"hub"),
		RunRuleChange.make(&"more_fights", RunRuleChange.Target.FIGHTS_ON_WAY, 1.0, RunRuleChange.How.ADD, MadeUpBiome.BIOME),
		RunRuleChange.make(&"more_fights", RunRuleChange.Target.KIND_LEAST, 1.0, RunRuleChange.How.ADD, MadeUpBiome.BIOME, &"fight"),
		RunRuleChange.make(&"steep", RunRuleChange.Target.SCALE_DEPTH, 4.0, RunRuleChange.How.SET, MadeUpBiome.BIOME),
		RunRuleChange.make(&"more_secrets", RunRuleChange.Target.KIND_CHANCE, 1.0, RunRuleChange.How.SET, MadeUpBiome.BIOME, &"secret"),
	] as Array[RunRuleChange]
	check_equal(definition.biome_problems(_biome.content, _biome.shapes), PackedStringArray(), "the changes keep a map makeable")
	var changed: RunDefinition = definition.changed_by(RunUnlocks.of([&"more_rooms", &"fountains", &"more_fights", &"steep", &"more_secrets"] as Array[StringName]))
	var rules: MapRules = changed.biomes[0]
	check(rules.rooms_min == 11 and rules.fights_on_way == 5 and rules.scale_depth == 4, "the numbers changed")
	check(definition.biomes[0].rooms_min == 8, "never the definition's own")
	for seed_value in 40:
		var map: BiomeMap = _map(changed, seed_value)
		check_equal(BiomeGenerator.rule_problems(map, rules, _biome.content, _biome.shapes), PackedStringArray(), "seed %d keeps the changed rules" % seed_value)
		check(map.rooms() - 1 >= 11, "11 rooms at least")
		check(map.room_kinds.has(&"fountain"), "a fountain in every map")
		check_equal(map.room_kinds.count(&"secret"), 2, "two secret rooms")
		check(BiomeGenerator.fights_on_way(map, _biome.content, _deepest(map)) >= 5, "five fights on the way")
	var styled: RunDefinition = definition.changed_by(RunUnlocks.of([&"only_long"] as Array[StringName]))
	check_equal(styled.biomes[0].styles[3].weight, 0.01, "a style's weight changed")
	check_equal(definition.biomes[0].styles[3].weight, 1.0, "never the definition's own style")
	var bad: RunRuleChange = RunRuleChange.make(&"nothing", RunRuleChange.Target.STYLE_WEIGHT, 2.0, RunRuleChange.How.SET, MadeUpBiome.BIOME, &"", &"spiral")
	check("no map style 'spiral'" in "\n".join(bad.problems(definition.biomes, "cellar_run")), "a style the biome has not is named")
	var lost: RunRuleChange = RunRuleChange.make(&"nothing", RunRuleChange.Target.STYLE_WEIGHT, 2.0)
	check("names no style" in "\n".join(lost.problems(definition.biomes, "cellar_run")), "a style target naming none is named")


# --- The validator -----------------------------------------------------------------------------

func _named(definition: RunDefinition, content: RunContent, shapes: Dictionary, says: String) -> void:
	var map: BiomeMap = BiomeGenerator.generate(definition, content, shapes, _sim(1))
	var why: String = "\n".join(map.not_made)
	check(not map.is_made() and says in why, "named: %s (got: %s)" % [says, why])


func test_the_validator_names_a_run_whose_content_makes_no_map() -> void:
	var no_throne: Array = []
	for row: Array in MadeUpBiome.ROOMS:
		if not (&"boss" in row[1]):
			no_throne.append(row)
	var without := MadeUpBiome.new(no_throne)
	_named(MadeUpBiome.run(), without.content, without.shapes, "kinds stand deepest")
	var rules: MapRules = MadeUpBiome.rules()
	rules.kinds[0].least = 2
	_named(MadeUpBiome.run(rules), _biome.content, _biome.shapes, "fewer than the 4 on the way")
	rules = MadeUpBiome.rules()
	rules.rooms_min = 30
	rules.rooms_max = 30
	_named(MadeUpBiome.run(rules), _biome.content, _biome.shapes, "fewer than rooms_min 30")
	rules = MadeUpBiome.rules()
	rules.styles = [] as Array[MapStyle]
	_named(MadeUpBiome.run(rules), _biome.content, _biome.shapes, "no map styles")
	var no_bridges: Dictionary = {}
	for id: StringName in _biome.shapes:
		if not (_biome.shapes[id] as PieceShape).walkway:
			no_bridges[id] = _biome.shapes[id]
	_named(MadeUpBiome.run(), _biome.content, no_bridges, "nothing bridges its rooms")
	# Every room's sockets face north and south, and only the bridges across are left: no bridge meets
	# a socket in any mirroring, which only placing finds.
	var upright: Array = []
	for row: Array in MadeUpBiome.ROOMS:
		upright.append([row[0], row[1], row[2], MadeUpBiome.N | MadeUpBiome.S])
	var up := MadeUpBiome.new(upright)
	var across: Dictionary = {}
	for id: StringName in up.shapes:
		if not String(id).begins_with("plank_down"):
			across[id] = up.shapes[id]
	check_equal(MadeUpBiome.run().biome_problems(up.content, across), PackedStringArray(), "nothing the rules can tell")
	_named(MadeUpBiome.run(), up.content, across, "no map after %d tries" % BiomeGenerator.ATTEMPTS)
	# One fight template with two sockets: the way's 4 fights need 4 (a template stands once).
	var one_hall: Array = []
	for row: Array in MadeUpBiome.ROOMS:
		var sockets: int = row[3]
		if &"fight" in row[1] and row[0] != &"hall_a":
			sockets = MadeUpBiome.N
		one_hall.append([row[0], row[1], row[2], sockets])
	var single := MadeUpBiome.new(one_hall)
	_named(MadeUpBiome.run(), single.content, single.shapes, "fewer than the 4 fights on the way")
	# A boss that fights only deeper than the way's shallowest end.
	var deep := MadeUpBiome.new()
	for enemy: EnemyBase in deep.content.enemies:
		if enemy.boss:
			enemy.min_depth = 11
	_named(MadeUpBiome.run(), deep.content, deep.shapes, "no boss fights in cellar by depth 5")
	var chance_line: MapRules = MadeUpBiome.rules()
	chance_line.kinds[0].chance = 0.5
	_named(MadeUpBiome.run(chance_line), _biome.content, _biome.shapes, "its chance does nothing")
	var map: BiomeMap = BiomeGenerator.generate(null, _biome.content, _biome.shapes, _sim(1))
	check(not map.is_made() and "No run definition" in "\n".join(map.not_made), "no definition")


## The crypt's own run is makeable since CB8 (its rooms given sockets, a start room and walkways of
## several lengths): the validator names nothing, and every seed makes a sound map by its rules, of
## the crypt's own templates, each once, the boss's deepest at the way's end.
func test_the_crypt_is_made() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var crypt := registry.get_resource(&"runs", &"crypt") as RunDefinition
	var content: RunContent = registry.run_content()
	var shapes: Dictionary = registry.piece_shapes(&"crypt")
	check_equal(crypt.biome_problems(content, shapes), PackedStringArray(), "the validator names the crypt makeable")
	var rules: MapRules = crypt.biomes[0]
	check(rules.fights_on_way == 4 and rules.styles.size() == 4, "the crypt's fights on the way and styles are decisions 4's and 5's")
	# Connected biomes CB11: decision 1's fixed kinds are back; the owner, 2026-11-19: more rooms,
	# 12 to 16 (a scale depth of 8).
	check(rules.rooms_min == 12 and rules.rooms_max == 16 and rules.scale_depth == 8, "the owner's 12 to 16 rooms and a scale depth of 8")
	var least: Dictionary = {}
	for rule: KindRule in rules.kinds:
		least[rule.kind] = rule.least
	check(least.get(&"reward", 0) == 1 and least.get(&"shop", 0) == 1 and least.get(&"secret", 0) == 1 and least.get(&"fight", 0) == 4 and least.get(&"boss", 0) == 1, "decision 1's fixed kinds: a reward room, a shop, a secret room, 4 fights and the boss: %s" % [least])
	var styles: Dictionary = {}
	var chance_kinds: Dictionary = {}
	var elites: int = 0
	var treasures: int = 0
	for seed_value in 24:
		var map: BiomeMap = BiomeGenerator.generate(crypt, content, shapes, _sim(seed_value))
		check(map.is_made(), "seed %d: made (%s)" % [seed_value, "\n".join(map.not_made)])
		if not map.is_made():
			continue
		check_equal(map.problems(shapes) + BiomeGenerator.rule_problems(map, rules, content, shapes), PackedStringArray(), "seed %d: sound" % seed_value)
		check_equal(map.room_kinds[0], &"start", "seed %d: the start room first" % seed_value)
		check(map.room_kinds.has(&"boss"), "seed %d: the boss stands" % seed_value)
		check(map.rooms() >= rules.rooms_min + 1 and map.rooms() <= rules.rooms_max + 1, "seed %d: %d rooms and the start room" % [seed_value, map.rooms() - 1])
		for kind: StringName in [&"reward", &"shop", &"secret"]:
			check(map.room_kinds.has(kind), "seed %d: a %s room (a fixed kind)" % [seed_value, kind])
		check_equal(map.room_kinds.count(&"shop"), 1, "seed %d: exactly one shop" % seed_value)
		check(map.room_kinds.count(&"fight") >= 4, "seed %d: four fights at least" % seed_value)
		for kind: StringName in [&"fountain", &"treasure", &"challenge"]:
			if map.room_kinds.has(kind):
				chance_kinds[kind] = true
		if map.room_kinds.count(&"secret") == 2:
			chance_kinds[&"second secret"] = true
		if map.room_kinds.has(&"treasure"):
			treasures += 1
		for room in map.rooms():
			for card: StringName in map.elites_of(room):
				if card != &"":
					check(rules.elite_cards.has(card), "seed %d: an elite's card is of the biome's list" % seed_value)
					elites += 1
			if map.room_kinds[room] == &"challenge":
				check(not map.enemies_of(room).is_empty() and not map.elites_of(room).has(&""), "seed %d: a challenge room's enemies are all elites" % seed_value)
		styles[map.style] = true
	check(styles.size() > 1, "more than one style rolled: %s" % [styles.keys()])
	check(chance_kinds.size() == 4, "every chance kind stands now and then (a fountain, a treasure room, a challenge room, a second secret): %s" % [chance_kinds.keys()])
	check(elites > 0, "fight rooms past the elites' depth hold elites now and then")
	# The owner, 2026-11-19: a treasure room (and its key) in about 9 biomes in 10.
	check(treasures >= 18, "a treasure room in most of the crypt's maps (chance 0.9): %d of 24" % treasures)


## The owner, 2026-11-19: a challenge room rolled always gets its slot within `rooms_max`, the
## treasure rooms filling what is left. With every chance room won and too few slots for all, every
## seed's crypt map holds its challenge room (rolled after the treasure rooms, it was crowded out).
func test_a_challenge_room_takes_its_slot_before_the_treasure_rooms() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var crypt := (registry.get_resource(&"runs", &"crypt") as RunDefinition).duplicate(true) as RunDefinition
	var content: RunContent = registry.run_content()
	var shapes: Dictionary = registry.piece_shapes(&"crypt")
	var rules: MapRules = crypt.biomes[0]
	# Slots short, as the crypt's were at 8 to 12 rooms (12 to 16 now, the owner's of 2026-11-19).
	rules.rooms_min = 8
	rules.rooms_max = 12
	var chance_rooms: int = 0
	var fixed: int = 0
	for rule: KindRule in rules.kinds:
		fixed += rule.least
		if rule.chance > 0.0:
			rule.chance = 1.0
			chance_rooms += rule.max_per_run - rule.least
	check(fixed + chance_rooms > rules.rooms_max, "too few slots for every chance room (%d fixed, %d by chance, %d at most)" % [fixed, chance_rooms, rules.rooms_max])
	var treasures: int = 0
	for seed_value in 12:
		var map: BiomeMap = BiomeGenerator.generate(crypt, content, shapes, _sim(seed_value))
		check(map.is_made(), "seed %d: made (%s)" % [seed_value, "\n".join(map.not_made)])
		if not map.is_made():
			continue
		check(map.room_kinds.has(&"challenge"), "seed %d: the challenge room stands" % seed_value)
		check(map.rooms() - 1 <= rules.rooms_max, "seed %d: within rooms_max" % seed_value)
		treasures += map.room_kinds.count(&"treasure")
	check(treasures > 0, "the treasure rooms fill what is left")


## A map generated from the crypt's own rooms (the antechamber as the start, the nave a fight, the
## ossuary court the way's end), laid by the biome world: every seed's shapes keep the rules mirrored,
## and a wizard can cross from the start room's socket onto the first bridge.
func test_a_map_of_the_crypt_s_rooms_is_laid() -> void:
	var world := Fixture.new(root)
	var into := Node2D.new()
	root.add_child(into)
	var registry: Object = world.registry
	var kinds: Array[Resource] = []
	for id: StringName in [&"start", &"fight", &"goal"]:
		var kind := RoomKind.new()
		kind.id = id
		kind.fill = RoomKind.FILL_ENEMIES if id == &"fight" else RoomKind.FILL_NONE
		kinds.append(kind)
	var rooms: Array[Resource] = []
	for pair: Array in [[&"arena_01", &"start"], [&"arena_02", &"fight"], [&"arena_03", &"goal"], [&"crypt_bridge", &""]]:
		var room: RoomBase = (registry.call(&"get_resource", &"rooms", pair[0]) as RoomBase).duplicate() as RoomBase
		var hosted: Array[StringName] = []
		if pair[1] != &"":
			hosted.append(pair[1])
		room.kinds = hosted
		rooms.append(room)
	var enemies: Array[Resource] = []
	enemies.assign((registry.call(&"run_content") as RunContent).enemies)
	var content := RunContent.gather(kinds, rooms, enemies)
	var shapes: Dictionary = registry.call(&"piece_shapes", &"crypt")
	var rules := MapRules.new()
	rules.biome = &"crypt"
	rules.rooms_min = 2
	rules.rooms_max = 2
	rules.fights_on_way = 1
	rules.styles = [MapStyle.make(&"long", 1.0)] as Array[MapStyle]
	var fight := KindRule.make(&"fight", 0, -2)
	fight.least = 1
	var goal := KindRule.make(&"goal", -1, -1)
	goal.least = 1
	goal.max_per_run = 1
	rules.kinds = [fight, goal] as Array[KindRule]
	var definition := RunDefinition.new()
	definition.id = &"crypt_walk"
	definition.biomes = [rules] as Array[MapRules]
	var mirrors: Dictionary = {}
	for seed_value in 8:
		var map: BiomeMap = BiomeGenerator.generate(definition, content, shapes, _sim(seed_value))
		check(map.is_made(), "seed %d: made (%s)" % [seed_value, "\n".join(map.not_made)])
		check_equal(map.problems(shapes), PackedStringArray(), "seed %d: sound" % seed_value)
		check_equal(map.room_templates, [&"arena_01", &"arena_02", &"arena_03"] as Array[StringName], "the three rooms in a row")
		mirrors[map.room_mirrors[0]] = true
	check(mirrors.size() > 1, "the row placed mirrored")
	var laid: BiomeMap = BiomeGenerator.generate(definition, content, shapes, _sim(3))
	var biome := BiomeWorld.new()
	biome.registry = world.registry
	biome.projectiles = world.projectiles
	check_equal(biome.lay(into, laid), PackedStringArray(), "the generated map is laid")
	check_equal(into.get_child_count(), 5, "three rooms and two bridges")
	var grid: RoomGrid = world.projectiles.grid()
	var start_shape: PieceShape = laid.room_shape(0, shapes)
	# The start room's socket the first bridge meets (the antechamber has two since CB8).
	var socket: int = laid.bridge_ends[1] if laid.bridge_ends[0] == 0 else laid.bridge_ends[3]
	var joint: Vector2 = laid.room_places[0] + start_shape.socket_at[socket]
	check(grid.is_mouth(joint + start_shape.way_of(socket) * 4.0), "a mouth just out from the start room's socket")
	check_equal(biome.room_layout(0).get_meta(PieceShape.GROUND_MIRROR_META), Vector2i(laid.room_mirrors[0] & 1, (laid.room_mirrors[0] >> 1) & 1), "the start room's layout says its mirroring, for the ground")
	world.free_all()
	into.free()


## The rules' check names each rule a made map breaks.
func test_the_rule_check_names_what_a_map_breaks() -> void:
	var rules: MapRules = MadeUpBiome.rules()
	var definition: RunDefinition = MadeUpBiome.run(rules)
	var made: BiomeMap = _map(definition, 5)
	check_equal(BiomeGenerator.rule_problems(made, rules, _biome.content, _biome.shapes), PackedStringArray(), "the map as made is sound")
	var fight: int = made.room_kinds.find(&"fight")
	var boss: int = _deepest(made)
	_breaks(made, rules, func(map: BiomeMap) -> void: map.room_kinds[fight] = &"shop", "does not host its kind")
	_breaks(made, rules, func(map: BiomeMap) -> void: map.room_kinds[0] = &"fight", "not the start room")
	_breaks(made, rules, func(map: BiomeMap) -> void: map.room_templates[boss] = map.room_templates[fight], "a template stands once")
	_breaks(made, rules, func(map: BiomeMap) -> void: map.room_places[fight] = map.room_places[boss] + Vector2(16, 0), "px apart")
	# The boss joined straight to the start room: no longer deepest, and no fights on that way.
	_breaks(made, rules, func(map: BiomeMap) -> void:
		map.add_bridge(MadeUpBiome.BRIDGE_ACROSS, Vector2.ZERO, 0, 0, 0, boss, 0)
		map.work_out_depths(), "the boss stands deepest")
	_breaks(made, rules, func(map: BiomeMap) -> void:
		map.add_bridge(MadeUpBiome.BRIDGE_ACROSS, Vector2.ZERO, 0, 0, 0, boss, 0)
		map.work_out_depths(), "a way to the boss passes 0 fights")
	_breaks(made, rules, func(map: BiomeMap) -> void:
		map.add_bridge(MadeUpBiome.BRIDGE_ACROSS, Vector2.ZERO, 0, boss - 1, 0, boss, 0)
		map.work_out_depths(), "is a dead end, but 2 bridges reach it")
	var secret: int = made.room_kinds.find(&"secret")
	_breaks(made, rules, func(map: BiomeMap) -> void: map.room_kinds[secret] = &"boss", "rooms of 'boss'")
	_breaks(made, rules, func(map: BiomeMap) -> void: map.room_kinds[fight] = &"reward", "rooms of 'reward'")
	# A reward room led to from the shop (`not_after`): the first bridge from the way's first room on.
	_breaks(made, rules, func(map: BiomeMap) -> void:
		map.room_kinds[map.room_kinds.find(&"shop")] = &"fight"
		map.room_kinds[map.room_kinds.find(&"reward")] = &"fight"
		map.room_kinds[1] = &"shop"
		map.room_kinds[2] = &"reward", "leads from a 'shop' to a 'reward'")
	var shallow: RunDefinition = MadeUpBiome.run(MadeUpBiome.rules())
	shallow.biomes[0].kinds[4].first_row = 20
	check("a depth its line does not take" in "\n".join(BiomeGenerator.rule_problems(made, shallow.biomes[0], _biome.content, _biome.shapes)), "a room at a depth its line does not take is named")


func _breaks(made: BiomeMap, rules: MapRules, change: Callable, says: String) -> void:
	var map: BiomeMap = made.copy()
	change.call(map)
	var problems: String = "\n".join(BiomeGenerator.rule_problems(map, rules, _biome.content, _biome.shapes))
	check(says in problems, "named: %s (got: %s)" % [says, problems])


## A walkway whose sockets do not face each other (a corner, the owner's answer of 2026-11-19) bridges
## rooms as a straight one does: with corners and only the shortest straight bridges, every seed
## makes a sound map, and the corners are placed in every mirroring.
func test_corner_walkways_bridge_rooms_too() -> void:
	var shapes: Dictionary = {}
	for id: StringName in _biome.shapes:
		var shape: PieceShape = _biome.shapes[id]
		if not shape.walkway or String(id).begins_with("plank_corner") or id == MadeUpBiome.BRIDGE_ACROSS or id == MadeUpBiome.BRIDGE_DOWN:
			shapes[id] = shape
	var rules: MapRules = MadeUpBiome.rules()
	var definition: RunDefinition = MadeUpBiome.run(rules)
	var corners: Dictionary = {}
	for seed_value in 60:
		var map: BiomeMap = BiomeGenerator.generate(definition, _biome.content, shapes, _sim(seed_value))
		check(map.is_made(), "seed %d: made (%s)" % [seed_value, "\n".join(map.not_made)])
		check_equal(map.problems(shapes) + BiomeGenerator.rule_problems(map, rules, _biome.content, shapes), PackedStringArray(), "seed %d: sound" % seed_value)
		for bridge in map.bridges():
			if String(map.bridge_templates[bridge]).begins_with("plank_corner"):
				corners[map.bridge_mirrors[bridge]] = true
	check_equal(corners.size(), 4, "corners placed turning every way: %s" % [corners.keys()])


## The start room alone (`MapRules.start_only`, rooms 0 to 0: a test's pinned room,
## tests/support/pinned_run.gd; connected biomes CB8): one room, the first template hosting the start
## room's kind, unmirrored at the origin, filled as its kind fills; the same for every seed.
func test_the_start_room_alone_is_one_room_at_the_origin() -> void:
	var rules := MapRules.new()
	rules.biome = MadeUpBiome.BIOME
	rules.rooms_min = 0
	rules.rooms_max = 0
	rules.start_kind = &"fight"
	var definition := RunDefinition.new()
	definition.id = &"cellar_alone"
	definition.biomes = [rules] as Array[MapRules]
	check_equal(definition.biome_problems(_biome.content, _biome.shapes), PackedStringArray(), "sound")
	var first: BiomeMap = BiomeGenerator.generate(definition, _biome.content, _biome.shapes, _sim(1))
	check(first.is_made() and first.rooms() == 1 and first.bridges() == 0, "one room, no bridge")
	if not first.is_made():
		return
	check_equal(first.room_templates[0], rules.biome_templates(_biome.content, _biome.shapes, &"fight", 0)[0].id, "the first template hosting its kind")
	check(first.room_places[0] == Vector2.ZERO and first.room_mirrors[0] == 0, "unmirrored at the origin")
	check(not first.enemies_of(0).is_empty(), "filled with its fight")
	check_equal(first.problems(_biome.shapes), PackedStringArray(), "a sound map")
	check_equal(BiomeGenerator.generate(definition, _biome.content, _biome.shapes, _sim(2)).room_templates, first.room_templates, "the same room for any seed")


## The crypt's walkways (connected biomes CB13: straight ones every 32 px both ways and corner ones)
## and its fight rooms with three or four sockets (a way uses two of a room's sockets, so a loop needs
## a third) let its loop style close loops: before them none of 60 loop maps closed one; now at least
## two in five do (34 when measured), and every kind of walkway (west-east, north-south, a corner)
## carries a way somewhere.
## Exactly one shop in every crypt biome (the owner, 2026-11-19), over a sweep of seeds and player
## counts, with its 12 to 16 rooms and the generator's rules kept (the boss deepest, at least 4 fights
## on every way to it).
func test_every_crypt_biome_has_exactly_one_shop() -> void:
	var registry: Node = root.get_node("Registry")
	var crypt := registry.get_resource(&"runs", &"crypt") as RunDefinition
	var content: RunContent = registry.run_content()
	var shapes: Dictionary = registry.piece_shapes(&"crypt")
	var rules: MapRules = crypt.biomes[0]
	var counts: Dictionary = {}
	for seed_value in range(100, 160):
		var map: BiomeMap = BiomeGenerator.generate(crypt, content, shapes, _sim(seed_value), 1 + seed_value % 4)
		check(map.is_made(), "seed %d: made (%s)" % [seed_value, "\n".join(map.not_made)])
		if not map.is_made():
			continue
		check_equal(map.room_kinds.count(&"shop"), 1, "seed %d: exactly one shop" % seed_value)
		var past_start: int = map.rooms() - 1
		check(past_start >= rules.rooms_min and past_start <= rules.rooms_max, "seed %d: %d rooms past the start room, 12 to 16" % [seed_value, past_start])
		counts[past_start] = true
		var boss: int = map.room_kinds.find(&"boss")
		check(BiomeGenerator.fights_on_way(map, content, boss) >= rules.fights_on_way, "seed %d: 4 fights on every way to the boss" % seed_value)
		check_equal(BiomeGenerator.rule_problems(map, rules, content, shapes), PackedStringArray(), "seed %d: every rule kept" % seed_value)
	check(counts.size() >= 3, "the room count varies over the sweep: %s" % [counts.keys()])


func test_the_crypt_s_loop_style_closes_loops() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var crypt := registry.get_resource(&"runs", &"crypt") as RunDefinition
	var content: RunContent = registry.run_content()
	var shapes: Dictionary = registry.piece_shapes(&"crypt")
	var rules := (crypt.biomes[0] as MapRules).duplicate() as MapRules
	var loop: MapStyle = null
	for style: MapStyle in rules.styles:
		if style.id == &"loop":
			loop = style
	check(loop != null, "the crypt has a loop style")
	if loop == null:
		return
	rules.styles = [loop] as Array[MapStyle]
	var definition := crypt.duplicate() as RunDefinition
	definition.biomes = [rules] as Array[MapRules]
	var looped: int = 0
	var made: int = 0
	var used: Dictionary = {}
	for seed_value: int in 60:
		var map: BiomeMap = BiomeGenerator.generate(definition, content, shapes, _sim(seed_value))
		if not map.is_made():
			continue
		made += 1
		looped += 1 if map.bridges() >= map.rooms() else 0
		for bridge: int in map.bridges():
			var id := String(map.bridge_templates[bridge])
			used["corner" if id.begins_with("crypt_corner") else ("north-south" if id.begins_with("crypt_bridge_v") else "west-east")] = true
	check_equal(made, 60, "every loop map is made")
	check(looped >= 24, "the loop style closes a loop in two maps of five at least: %d of 60" % looped)
	check_equal(used.size(), 3, "every kind of walkway carries a way: %s" % [used.keys()])


## Every crypt template is played (connected biomes, "Steps": each template "played once in a
## generated biome"): over 60 crypt maps in the styles its rules roll, every fight room and every
## walkway stands somewhere, so a template no placement can ever fit is named.
func test_every_crypt_fight_room_and_walkway_is_played() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var crypt := registry.get_resource(&"runs", &"crypt") as RunDefinition
	var content: RunContent = registry.run_content()
	var shapes: Dictionary = registry.piece_shapes(&"crypt")
	var placed: Dictionary = {}
	for seed_value: int in 60:
		var map: BiomeMap = BiomeGenerator.generate(crypt, content, shapes, _sim(seed_value))
		for template: StringName in map.room_templates + map.bridge_templates:
			placed[template] = int(placed.get(template, 0)) + 1
	var unplayed := PackedStringArray()
	for item: Resource in registry.get_all(&"rooms"):
		var room := item as RoomBase
		if room != null and room.biome == &"crypt" and (room.walkway or room.kinds.has(&"fight")) and not placed.has(room.id):
			unplayed.append(String(room.id))
	check_equal(unplayed, PackedStringArray(), "every crypt fight room and walkway is played in some map")


## The reward rooms' types (the owner's ask of 2026-11-19, step 7): every crypt reward room gets one,
## a line of its table's item kind, a card's kind among its cards' kinds and an infusion's element
## among the element cards; every other room none; the same seed the same types (and the same rooms
## as a map made without them); the seeds vary them.
func test_each_reward_room_is_given_its_type_from_the_seed() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var crypt := registry.get_resource(&"runs", &"crypt") as RunDefinition
	var content: RunContent = registry.run_content()
	var shapes: Dictionary = registry.piece_shapes(&"crypt")
	var untyped: RunContent = RunContent.gather(registry.get_all(&"room_kinds"), registry.get_all(&"rooms"), registry.get_all(&"enemies") + registry.get_all(&"bosses"))
	var seen: Dictionary = {}
	var table := registry.get_resource(&"rewards", &"reward") as RewardTable
	var items: Array[StringName] = []
	for entry: RewardEntry in table.entries:
		items.append(entry.kind)
	for seed_value in 32:
		var map: BiomeMap = BiomeGenerator.generate(crypt, content, shapes, _sim(seed_value))
		if not map.is_made():
			continue
		var again: BiomeMap = BiomeGenerator.generate(crypt, content, shapes, _sim(seed_value))
		check(map.same_as(again), "seed %d: the same seed, the same types" % seed_value)
		var plain: BiomeMap = BiomeGenerator.generate(crypt, untyped, shapes, _sim(seed_value))
		check(plain.room_reward_items.is_empty(), "seed %d: with no tables nor cards, no room is typed" % seed_value)
		check(plain.room_kinds == map.room_kinds and plain.room_places == map.room_places and plain.room_enemies == map.room_enemies, "seed %d: the types shift no other roll" % seed_value)
		for room in map.rooms():
			var type: RewardType = map.reward_type_of(room)
			if map.room_kinds[room] != &"reward":
				check(type.is_any(), "seed %d: a %s room has no type" % [seed_value, map.room_kinds[room]])
				continue
			check(items.has(type.item), "seed %d: the reward room's item kind is a line of its table's: %s" % [seed_value, type.to_row()])
			if type.item == ItemKinds.CARD:
				check(type.card_kind != &"", "seed %d: a card room names its card kind" % seed_value)
				check_equal(type.element != &"", type.card_kind == RewardType.ELEMENT_KIND, "seed %d: an infusion room, and only one, names its element" % seed_value)
				if type.element != &"":
					check_equal(content.cards.kind_of(type.element), RewardType.ELEMENT_KIND, "its element is an element card")
			seen[",".join(type.to_row())] = true
	check(seen.size() >= 3, "the seeds give the reward room different types: %s" % [seen.keys()])
