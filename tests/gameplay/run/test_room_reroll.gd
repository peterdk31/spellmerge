extends "res://tests/support/suite.gd"
## A room reroll's map (the owner, 2026-11-19; `BiomeGenerator.reroll_room`): over the crypt's own
## maps, a reroll of a room past the start room changes that room alone (its kind, template,
## mirroring, place and fill), keeps every bridge where it was, its sockets meeting them, inside the
## biome's area, and keeps every rule of the map (`problems`, `rule_problems`: the fixed kinds there,
## the boss deepest, a template once a biome; a kind's `max_per_run` may be broken, never its
## `least`); a door's kind stays its door's; in the crypt a room changes kind, to more than one kind,
## weighed by `kind_weight`; the same roll the same map, another roll another; the start room is
## never rerolled; refills keep the other rooms' foes.
const RegistryScript := preload("res://core/registry/registry.gd")
const MadeUpBiome := preload("res://tests/support/made_up_biome.gd")

var _registry: RegistryScript
var _crypt: RunDefinition
var _content: RunContent
var _shapes: Dictionary


func before_each() -> void:
	_registry = own(RegistryScript.new()) as RegistryScript
	_registry.scan()
	_crypt = _registry.get_resource(&"runs", &"crypt") as RunDefinition
	_content = _registry.run_content()
	_shapes = _registry.piece_shapes(&"crypt")


func _sim(seed_value: int) -> Sim:
	return Sim.seeded(seed_value)


func _door(map: BiomeMap, room: int) -> StringName:
	return _content.kind(map.room_kinds[room]).door


func test_a_reroll_changes_that_room_alone_and_keeps_the_map_valid() -> void:
	var rules: MapRules = _crypt.biomes[0]
	var tried: int = 0
	var rerolled: int = 0
	for seed_value in 3:
		var sim: Sim = _sim(seed_value)
		var map: BiomeMap = BiomeGenerator.generate(_crypt, _content, _shapes, sim)
		check(map.is_made(), "seed %d: made" % seed_value)
		for room in range(1, map.rooms()):
			tried += 1
			var made: BiomeMap = BiomeGenerator.reroll_room(_crypt, _content, _shapes, sim, 1, map, room, 0)
			if made == null:
				continue
			rerolled += 1
			var what: String = "seed %d room %d" % [seed_value, room]
			check_equal(made.problems(_shapes) + BiomeGenerator.rule_problems(made, rules, _content, _shapes, true, false), PackedStringArray(), "%s: sound (a kind's count may be broken, never its least)" % what)
			check_equal(made.bridge_templates, map.bridge_templates, "%s: the same bridges" % what)
			check_equal(made.bridge_places, map.bridge_places, "%s: where they were" % what)
			check_equal(made.depths, map.depths, "%s: the same depths" % what)
			check_equal(_door(made, room), _door(map, room), "%s: the same door" % what)
			for other in map.rooms():
				if other == room:
					continue
				check(made.room_templates[other] == map.room_templates[other] and made.room_places[other] == map.room_places[other] and made.room_kinds[other] == map.room_kinds[other], "%s: room %d as it was" % [what, other])
				check_equal(made.enemies_of(other), map.enemies_of(other), "%s: room %d's foes as they were" % [what, other])
			check(BiomeGenerator._area_of(map, _shapes).encloses(made.room_shape(room, _shapes).rect_at(made.room_places[room])), "%s: inside the biome's area" % what)
			check(made.room_templates[room] != map.room_templates[room] or made.room_mirrors[room] != map.room_mirrors[room] or made.room_kinds[room] != map.room_kinds[room] or _content.kind(made.room_kinds[room]).fills_with_enemies() or _content.kind(made.room_kinds[room]).fill == RoomKind.FILL_SHOP or not made.reward_type_of(room).same_as(map.reward_type_of(room)) or _content.kind(made.room_kinds[room]).typed_rewards, "%s: something behind the doorway changed (its foes, shelf or reward type rolled again at least)" % what)
			check(map.same_as(BiomeGenerator.generate(_crypt, _content, _shapes, sim)), "%s: the map asked is left as it was" % what)
	check(rerolled > tried / 2, "most rooms reroll (%d of %d)" % [rerolled, tried])


func test_the_same_roll_the_same_map_and_the_start_room_never() -> void:
	var sim: Sim = _sim(3)
	var map: BiomeMap = BiomeGenerator.generate(_crypt, _content, _shapes, sim)
	check(BiomeGenerator.reroll_room(_crypt, _content, _shapes, sim, 1, map, 0, 0) == null, "the start room is never rerolled")
	var room: int = -1
	for at in range(1, map.rooms()):
		if _content.kind(map.room_kinds[at]).fills_with_enemies():
			room = at
			break
	var one: BiomeMap = BiomeGenerator.reroll_room(_crypt, _content, _shapes, sim, 1, map, room, 0)
	check(one != null, "a fight room rerolls")
	check(one.same_as(BiomeGenerator.reroll_room(_crypt, _content, _shapes, sim, 1, map, room, 0)), "the same roll, the same map")
	var differs: bool = false
	for roll in range(1, 8):
		if not one.same_as(BiomeGenerator.reroll_room(_crypt, _content, _shapes, sim, 1, map, room, roll)):
			differs = true
	check(differs, "another roll, another map")


func test_a_refill_keeps_the_rooms_after_it() -> void:
	var map := BiomeMap.new()
	for room in 3:
		map.add_room(&"t%d" % room, Vector2.ZERO)
	map.fill_room(0, 1.0, [&"a"] as Array[StringName])
	map.fill_room(1, 1.0, [&"b", &"c"] as Array[StringName], [&"", &"fire"] as Array[StringName])
	map.fill_room(2, 1.0, [&"d"] as Array[StringName])
	map.refill_room(1, 2.0, [&"e", &"f", &"g"] as Array[StringName], [&"ice"] as Array[StringName])
	check_equal(map.enemies_of(0), [&"a"] as Array[StringName], "the room before as it was")
	check_equal(map.enemies_of(1), [&"e", &"f", &"g"] as Array[StringName], "the room's new foes")
	check_equal(map.elites_of(1), [&"ice", &"", &""] as Array[StringName], "and their elites")
	check_equal(map.enemies_of(2), [&"d"] as Array[StringName], "the room after as it was")
	check_equal(map.room_scales[1], 2.0, "its scale")


func test_a_rerolled_reward_room_rolls_its_type_again() -> void:
	var differs: int = 0
	var rerolled: int = 0
	for seed_value in 8:
		var sim: Sim = _sim(seed_value)
		var map: BiomeMap = BiomeGenerator.generate(_crypt, _content, _shapes, sim)
		var room: int = map.room_kinds.find(&"reward")
		if room < 0:
			continue
		for roll in 3:
			var made: BiomeMap = BiomeGenerator.reroll_room(_crypt, _content, _shapes, sim, 1, map, room, roll)
			if made == null:
				continue
			rerolled += 1
			check(not made.reward_type_of(room).is_any(), "seed %d: a reward room keeps a type" % seed_value)
			if not made.reward_type_of(room).same_as(map.reward_type_of(room)):
				differs += 1
	check(rerolled > 0, "reward rooms reroll (%d)" % rerolled)
	check(differs > 0, "and their type is rolled again (%d differ)" % differs)


func test_a_reroll_can_change_the_kind_breaking_a_count_and_every_fixed_kind_survives() -> void:
	# The owner, 2026-11-19: any kind of the same door, a kind's count broken if need be, as long as
	# every fixed kind is still somewhere (and fights enough on every way to the boss). The made-up
	# biome holds two templates of the reward and the shop, so a room may become a second one.
	var biome: MadeUpBiome = MadeUpBiome.new()
	var rules: MapRules = MadeUpBiome.rules()
	var definition: RunDefinition = MadeUpBiome.run(rules)
	var changed: int = 0
	var broke: int = 0
	var into: Dictionary = {}
	for seed_value in 6:
		var sim: Sim = _sim(seed_value)
		var map: BiomeMap = BiomeGenerator.generate(definition, biome.content, biome.shapes, sim)
		for room in range(1, map.rooms()):
			if map.room_kinds[room] == &"boss":
				continue
			for roll in 2:
				var made: BiomeMap = BiomeGenerator.reroll_room(definition, biome.content, biome.shapes, sim, 1, map, room, roll)
				if made == null:
					continue
				var what: String = "seed %d room %d roll %d" % [seed_value, room, roll]
				check_equal(made.problems(biome.shapes) + BiomeGenerator.rule_problems(made, rules, biome.content, biome.shapes, true, false), PackedStringArray(), "%s: sound" % what)
				for rule: KindRule in rules.biome_lines(biome.content, biome.shapes):
					check(made.room_kinds.count(rule.kind) >= rule.least, "%s: at least %d of '%s' still" % [what, rule.least, rule.kind])
					if rule.max_per_run > 0 and made.room_kinds.count(rule.kind) > rule.max_per_run:
						broke += 1
				check(BiomeGenerator.fights_on_way(made, biome.content, made.room_kinds.find(&"boss")) >= rules.fights_on_way, "%s: fights enough on every way" % what)
				check_equal(made.room_kinds.count(&"boss"), 1, "%s: the boss still one" % what)
				check(made.room_kinds[room] != &"boss" and made.room_kinds[room] != rules.start_kind, "%s: never the boss or the start room" % what)
				if made.room_kinds[room] != map.room_kinds[room]:
					changed += 1
					into[made.room_kinds[room]] = true
					check_equal(biome.content.kind(made.room_kinds[room]).door, biome.content.kind(map.room_kinds[room]).door, "%s: the same door" % what)
	check(changed > 0, "rooms change their kind (%d)" % changed)
	check(broke > 0, "a kind's count may be broken (%d)" % broke)
	check(into.size() > 1, "into more than one kind (%s)" % [into.keys()])


func test_a_kind_is_weighed_by_how_many_the_biome_holds() -> void:
	var map := BiomeMap.new()
	for kind: StringName in [&"start", &"fight", &"fight", &"fight", &"shop", &"reward"]:
		map.add_room(&"t", Vector2.ZERO, 0, kind)
	var fight := KindRule.make(&"fight")
	var shop := KindRule.make(&"shop", 0, -1, 2.0)
	var fountain := KindRule.make(&"fountain")
	check_equal(BiomeGenerator.kind_weight(map, 5, fight), 0.25, "three fights held: a quarter")
	check_equal(BiomeGenerator.kind_weight(map, 1, fight), 1.0 / 3.0, "the room itself not counted")
	check_equal(BiomeGenerator.kind_weight(map, 5, shop), 1.0, "its line's weight over two")
	check_equal(BiomeGenerator.kind_weight(map, 5, fountain), 1.0, "a kind the biome holds none of: its weight")
