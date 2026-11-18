extends "res://tests/support/suite.gd"
## The run's area (run generation RG3, gameplay/run/run.gd), on the real autoloads: a run of rooms
## begun (`run_begun`) makes the run's map from the run's seed and answers with its first room and
## what stands in it (`run_room_chosen`); Flow builds that room with those enemies; the map is the
## run's state (in the Tick's areas, hashed, gone at the next run's start, as in the hub); a run the
## registry lacks, or whose map cannot be made, answers nothing.

const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")

var run: Node
var flow: FlowScript
var events: Node
var tick: TickScript
var input: Node
var answers: Array = []


func before_each() -> void:
	run = root.get_node("Run")
	flow = root.get_node("Flow") as FlowScript
	events = root.get_node("Events")
	tick = root.get_node("Tick") as TickScript
	input = root.get_node("PlayerInput")
	answers.clear()
	events.connect("run_room_chosen", _on_chosen)
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)


func after_each() -> void:
	events.disconnect("run_room_chosen", _on_chosen)
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	input.leave(0)
	tick.begin_run()


func _on_chosen(room: StringName, enemies: Array[StringName], ways: Array[StringName]) -> void:
	answers.append([room, enemies, ways])


## The map the generator makes for the crypt run on `seed`, as the area should have it.
func _expected(seed: int) -> RunMap:
	var registry: Node = root.get_node("Registry")
	var definition := registry.call("get_resource", &"runs", &"crypt") as RunDefinition
	return RunGenerator.generate(definition, registry.call("run_content") as RunContent, Sim.seeded(seed))


func test_a_run_begun_makes_its_map_and_names_its_first_room() -> void:
	tick.begin_run()
	tick.sim.run_seed = 41
	events.emit_signal("run_begun", &"crypt", 1, 0)
	var map: RunMap = run.get(&"map") as RunMap
	check(map != null and map.is_made(), "the crypt run's map is made")
	if map == null:
		return
	check_equal(int(run.get(&"at")), 0, "the party is in its first room")
	check_equal(SimHash.of(map), SimHash.of(_expected(41)), "the map is the generator's for the run's seed")
	check_equal(answers.size(), 1, "one answer")
	if answers.size() == 1:
		check_equal(answers[0][0], map.first().room, "the first room's template")
		check_equal(answers[0][1], map.first().enemies, "and what stands in it")
	check(run.call("room_now") == map.first(), "room_now is the first room")


## The hub's lectern (run generation RG7): a run begun at a depth makes the same map from the run's
## seed and the party enters the first room of the row that depth names (`RunMap.start_at`); its
## scale is that room's.
func test_a_run_begun_at_a_depth_enters_its_rows_first_room() -> void:
	var scales: Array[float] = []
	var hear := func(scale: float) -> void: scales.append(scale)
	events.connect("run_room_scaled", hear)
	var depths: int = (root.get_node("Registry").call("get_resource", &"runs", &"crypt") as RunDefinition).start_depths()
	for depth: int in [1, depths - 1]:
		tick.begin_run()
		tick.sim.run_seed = 41
		answers.clear()
		scales.clear()
		events.emit_signal("run_begun", &"crypt", 1, depth)
		var map: RunMap = run.get(&"map") as RunMap
		check(map != null and map.is_made(), "depth %d: the map is made" % depth)
		if map == null:
			continue
		check_equal(SimHash.of(map), SimHash.of(_expected(41)), "depth %d: the same map as from the first room" % depth)
		var at: RunNode = run.call("room_now") as RunNode
		var row: int = map.rows() - 1 if depth == depths - 1 else depth
		check_equal(at.index, map.row(row)[0].index, "depth %d: the first room of row %d" % [depth, row])
		check(answers.size() == 1 and answers[0][0] == at.room, "depth %d: that room named" % depth)
		check_equal(scales, [at.scale] as Array[float], "depth %d: at its scale" % depth)
	events.disconnect("run_room_scaled", hear)


## Where a run started at a depth begins (`RunMap.start_at`), on a map of five rows a lectern
## offering six depths and on one made shallower than it offers.
func test_where_a_depth_starts() -> void:
	var map := RunMap.new()
	var widths: Array[int] = [1, 2, 3, 2, 1]
	for row in widths.size():
		for i in widths[row]:
			var node := RunNode.new()
			node.index = map.nodes.size()
			node.row = row
			map.nodes.append(node)
	check_equal(map.start_at(0, 6), 0, "0: the first room")
	check_equal(map.start_at(-3, 6), 0, "less: the first room")
	check_equal(map.start_at(1, 6), 1, "1: row 1's first room")
	check_equal(map.start_at(2, 6), 3, "2: row 2's first room")
	check_equal(map.start_at(4, 6), 6, "4, past the rows before the last: the deepest before it")
	check_equal(map.start_at(5, 6), 8, "the last of the depths: the last row")
	check_equal(map.start_at(9, 6), 8, "past them: the last row")
	check_equal(map.start_at(3, 4), 8, "the last of fewer depths: the last row")
	check_equal(RunMap.new().start_at(3, 6), 0, "a map not made: 0")


func test_the_same_seed_gives_the_same_map_and_another_seed_another() -> void:
	var hashes: Dictionary = {}
	for seed: int in [5, 5, 6, 7, 8, 9]:
		tick.begin_run()
		tick.sim.run_seed = seed
		events.emit_signal("run_begun", &"crypt", 1, 0)
		var map: RunMap = run.get(&"map") as RunMap
		var value: int = SimHash.of(map)
		if seed == 5 and hashes.has(5):
			check_equal(value, hashes[5], "seed 5 twice: the same map")
		hashes[seed] = value
	var distinct: Dictionary = {}
	for seed: int in hashes:
		distinct[hashes[seed]] = true
	check(distinct.size() > 1, "other seeds, other maps (%d of %d)" % [distinct.size(), hashes.size()])


func test_a_run_start_takes_the_map_away() -> void:
	events.emit_signal("run_begun", &"crypt", 1, 0)
	check(run.get(&"map") != null, "a map")
	tick.begin_run()
	check(run.get(&"map") == null and int(run.get(&"at")) == -1, "a run's start renews the area: no map")
	check(run.call("room_now") == null, "no room")


func test_an_unknown_run_answers_nothing() -> void:
	events.emit_signal("run_begun", &"no_such_run", 1, 0)
	check(run.get(&"map") == null, "no map")
	check(answers.is_empty(), "no answer")


func test_the_map_is_part_of_the_game_state() -> void:
	tick.begin_run()
	check(tick.state_areas().has("Run"), "the Tick hashes the run's area")
	var before: int = SimHash.of(run)
	events.emit_signal("run_begun", &"crypt", 1, 0)
	check(SimHash.of(run) != before, "the map changes the hash")
	var walk := StateWalk.new()
	walk.values("Run", run, [])
	check_equal(walk.problems, PackedStringArray(), "the area's state walks without problems")


## Play: Flow builds the room the map names, with the enemies it puts there; the hub has no map.
func test_flow_builds_the_room_the_map_names() -> void:
	input.add_virtual_device(0)
	events.emit_signal("play_requested", 0)
	var node: RunNode = run.call("room_now") as RunNode
	check(node != null, "a run of rooms has a room")
	if node == null:
		return
	check_equal(flow.room_id, node.room, "Flow is in the map's first room")
	check_equal(flow.enemies_left(), node.enemies.size(), "every enemy the map puts there is to beat")
	# The rest of the room's groups called now (enemy spawning EA5: they come as the room gets quiet).
	flow.stand_all_now()
	var standing: Array[StringName] = []
	for body: Node in flow.world.get_children():
		var enemy := body as Actor
		if enemy != null and enemy.data != null and PlayerController.of(enemy) == null:
			standing.append(enemy.data.id)
	standing.sort()
	var wanted: Array[StringName] = node.enemies.duplicate()
	wanted.sort()
	check_equal(standing, wanted, "the enemies the map names")
	flow.stop_run()
	flow.mode = FlowScript.MODE_HUB
	check(flow.start_run(0), "the hub starts")
	check(run.get(&"map") == null, "the hub has no map")


## Run generation RG4: each room is named with the kinds of the rooms it leads to; a way taken moves
## the run on to the room it links to (a row deeper) and names it; a way the room has not moves nothing.
func test_a_way_taken_moves_on_through_the_map() -> void:
	tick.begin_run()
	tick.sim.run_seed = 7
	events.emit_signal("run_begun", &"crypt", 1, 0)
	var map: RunMap = run.get(&"map") as RunMap
	if map == null or not map.is_made():
		check(false, "the crypt run's map is made")
		return
	var first: RunNode = map.first()
	var kinds: Array[StringName] = []
	for link: int in first.links:
		kinds.append(map.node(link).kind)
	check_equal(answers[0][2], kinds, "the first room is named with the kinds it leads to")
	events.emit_signal("run_way_taken", first.links.size())
	check_equal(int(run.get(&"at")), 0, "a way the room has not: the party stays")
	check_equal(answers.size(), 1, "and nothing is named")
	var way: int = first.links.size() - 1
	events.emit_signal("run_way_taken", way)
	var now: RunNode = run.call("room_now") as RunNode
	check(now != null and now.index == first.links[way], "the room that way links to")
	check(now != null and now.row == 1, "a row deeper")
	check_equal(answers.size(), 2, "named")
	if answers.size() == 2 and now != null:
		check_equal(answers[1][0], now.room, "its template")
		check_equal(answers[1][1], now.enemies, "what stands in it")
	# On to the last room, which leads nowhere.
	while now != null and not now.links.is_empty():
		events.emit_signal("run_way_taken", 0)
		now = run.call("room_now") as RunNode
	check(now != null and now.row == map.rows() - 1, "the last row reached")
	check_equal(answers.back()[2], [] as Array[StringName], "the last room leads nowhere")


## Run generation RG8: the view hears the map as the party sees it (`run_map_changed`): every room's
## row, kind and links in the map's order, and the room the party is in, as it enters each room;
## again after a snapshot's restore; empty as a run starts and for a run that cannot be made.
func test_the_view_hears_the_map_as_the_party_enters_each_room() -> void:
	var told: Array = []
	var hear := func(rows: PackedInt32Array, kinds: Array[StringName], links: Array[PackedInt32Array], at: int) -> void:
		told.append([rows, kinds, links, at])
	events.connect("run_map_changed", hear)
	tick.begin_run()
	check_equal(told.size(), 1, "a run's start tells the view")
	if told.size() == 1:
		check(told[0][0].is_empty() and told[0][1].is_empty() and told[0][2].is_empty(), "no rooms")
		check_equal(told[0][3], -1, "and nowhere")
	tick.sim.run_seed = 7
	told.clear()
	events.emit_signal("run_begun", &"crypt", 1, 0)
	var map: RunMap = run.get(&"map") as RunMap
	if map == null or not map.is_made():
		events.disconnect("run_map_changed", hear)
		check(false, "the crypt run's map is made")
		return
	check_equal(told.size(), 1, "the first room entered tells the view")
	var rows := PackedInt32Array()
	var kinds: Array[StringName] = []
	var links: Array[PackedInt32Array] = []
	for node: RunNode in map.nodes:
		rows.append(node.row)
		kinds.append(node.kind)
		links.append(node.links)
	if told.size() == 1:
		check_equal(told[0][0], rows, "every room's row, in the map's order")
		check_equal(told[0][1], kinds, "its kind")
		check_equal(told[0][2], links, "the rooms it leads to")
		check_equal(told[0][3], 0, "the party is in the first room")
		(told[0][2] as Array[PackedInt32Array])[0].append(99)
		check(not map.first().links.has(99), "what is told is a copy")
	events.emit_signal("run_way_taken", 0)
	check_equal(told.size(), 2, "the next room entered tells it again")
	if told.size() == 2:
		check_equal(told[1][3], map.first().links[0], "where the party is now")
	run.call("rebuild_derived")
	check_equal(told.size(), 3, "a snapshot's restore tells it again")
	if told.size() == 3:
		check_equal(told[2][3], told[1][3], "the same room")
	told.clear()
	events.emit_signal("run_begun", &"no_such_run", 1, 0)
	check(told.size() == 1 and (told[0][0] as PackedInt32Array).is_empty() and told[0][3] == -1, "a run the registry lacks: an empty map")
	events.disconnect("run_map_changed", hear)


## Run generation RG5: the map is made for the players the run begins with (the crypt's scaling),
## and each room's scale is told (`run_room_scaled`) before the room is named, as the party enters it.
func test_the_map_is_made_for_the_run_s_players_and_each_room_s_scale_told_first() -> void:
	var heard: Array = []
	var on_scaled := func(scale: float) -> void: heard.append([&"scaled", scale])
	var on_chosen := func(room: StringName, _enemies: Array[StringName], _ways: Array[StringName]) -> void: heard.append([&"chosen", room])
	events.connect("run_room_scaled", on_scaled)
	events.connect("run_room_chosen", on_chosen)
	tick.begin_run()
	tick.sim.run_seed = 23
	events.emit_signal("run_begun", &"crypt", 3, 0)
	var map: RunMap = run.get(&"map") as RunMap
	var registry: Node = root.get_node("Registry")
	var definition := registry.call("get_resource", &"runs", &"crypt") as RunDefinition
	var expected: RunMap = RunGenerator.generate(definition, registry.call("run_content") as RunContent, Sim.seeded(23), 3)
	check(map != null and map.players == 3, "made for three players")
	check_equal(SimHash.of(map), SimHash.of(expected), "the generator's map for three players")
	check(definition.scaling != null and map != null and map.first().scale > 1.0, "the crypt grows harder with players: %s" % (map.first().scale if map != null else -1.0))
	if map != null:
		check_equal(heard, [[&"scaled", map.first().scale], [&"chosen", map.first().room]], "the first room's scale, then the room")
		heard.clear()
		events.emit_signal("run_way_taken", 0)
		var now: RunNode = run.call("room_now") as RunNode
		check_equal(heard, [[&"scaled", now.scale], [&"chosen", now.room]], "the next room's the same way")
		check(now.scale > map.first().scale, "a row deeper, harder: %s after %s" % [now.scale, map.first().scale])
	events.disconnect("run_room_scaled", on_scaled)
	events.disconnect("run_room_chosen", on_chosen)


## Enemy spawning EA4: as the party enters a room, the run tells its pace (`run_room_paced`) after its
## scale and before the room: plain costs, the crypt's `SpawnRules` shares of the room's scaled
## budget, so a bigger party's room has bigger groups; the room's map node keeps them.
func test_each_room_s_pace_is_told_between_its_scale_and_the_room() -> void:
	var heard: Array = []
	var on_scaled := func(_scale: float) -> void: heard.append(&"scaled")
	var on_paced := func(group: int, refill_at: int, stagger: float) -> void: heard.append([group, refill_at, stagger])
	var on_chosen := func(_room: StringName, _enemies: Array[StringName], _ways: Array[StringName]) -> void: heard.append(&"chosen")
	events.connect("run_room_scaled", on_scaled)
	events.connect("run_room_paced", on_paced)
	events.connect("run_room_chosen", on_chosen)
	var definition := root.get_node("Registry").call("get_resource", &"runs", &"crypt") as RunDefinition
	var rules: MapRules = definition.biomes[0]
	check(rules.spawning != null, "the crypt paces its rooms")
	var groups: Array[int] = []
	for players: int in [1, 4]:
		heard.clear()
		tick.begin_run()
		tick.sim.run_seed = 23
		events.emit_signal("run_begun", &"crypt", players, 0)
		var node: RunNode = run.call("room_now") as RunNode
		if node == null or rules.spawning == null:
			check(false, "%d players: a room" % players)
			continue
		var budget: int = RunScaling.scaled_budget(rules.room_budget, node.scale)
		var paced: Array = [rules.spawning.group_cost(budget), rules.spawning.refill_cost(budget), rules.spawning.stagger]
		check_equal(heard, [&"scaled", paced, &"chosen"], "%d players: the scale, the pace, then the room" % players)
		check_equal([node.group, node.refill_at, node.stagger], paced, "%d players: the map's room keeps its pace" % players)
		check(node.refill_at < node.group, "%d players: the next group is called below a group's cost" % players)
		groups.append(node.group)
	check(groups.size() == 2 and groups[1] > groups[0], "four players' groups are bigger: %s" % [groups])
	events.disconnect("run_room_scaled", on_scaled)
	events.disconnect("run_room_paced", on_paced)
	events.disconnect("run_room_chosen", on_chosen)


## Run generation RG6: a run of the crypt's rules with one rule change, every room as deep as the
## crypt allows once `test_deeper` is unlocked, registered once under an id of its own.
func _unlockable() -> StringName:
	var registry: Node = root.get_node("Registry")
	var id: StringName = &"test_unlockable_crypt"
	if registry.call("get_resource", &"runs", id) == null:
		var crypt := registry.call("get_resource", &"runs", &"crypt") as RunDefinition
		var made: RunDefinition = crypt.copied()
		made.id = id
		var deepest: float = float(crypt.biomes[0].depth_max)
		made.changes = [
			RunRuleChange.make(&"test_deeper", RunRuleChange.Target.DEPTH_MIN, deepest),
			RunRuleChange.make(&"test_deeper", RunRuleChange.Target.SCALE_PLAYER_END, 2.0),
		] as Array[RunRuleChange]
		check_equal(made.problems(registry.call("run_content") as RunContent), PackedStringArray(), "the unlockable run is sound")
		registry.call("add", &"runs", made)
	return id


func _map_of(definition: RunDefinition, seed: int, players: int) -> RunMap:
	var registry: Node = root.get_node("Registry")
	return RunGenerator.generate(definition, registry.call("run_content") as RunContent, Sim.seeded(seed), players)


## Run generation RG6: this machine's unlocks are the flags of its save that some run's rule change
## names, nothing else of the save.
func test_this_machine_s_unlocks_are_its_save_s_flags_a_rule_change_names() -> void:
	var id: StringName = _unlockable()
	var path: String = "user://test_run_unlocks.cfg"
	DirAccess.remove_absolute(path)
	var kept: SaveFile = run.get(&"save") as SaveFile
	run.set(&"save", SaveFile.new(path))
	check((run.call("unlocks_now") as RunUnlocks).is_empty(), "a new save: none")
	SaveFile.new(path).set_flag(&"intro_seen")
	check((run.call("unlocks_now") as RunUnlocks).is_empty(), "a flag no rule change names travels not")
	SaveFile.new(path).set_flag(&"test_deeper")
	check_equal((run.call("unlocks_now") as RunUnlocks).flags, [&"test_deeper"] as Array[StringName], "a flag the run %s's change names" % id)
	var frames: Node = root.get_node("Frames")
	check_equal((frames.call("next_run_unlocks") as RunUnlocks).flags, [&"test_deeper"] as Array[StringName], "the frames service asks the area")
	tick.begin_run()
	check_equal(tick.sim.unlocks.flags, [&"test_deeper"] as Array[StringName], "and a run's start takes them")
	run.set(&"save", kept)
	DirAccess.remove_absolute(path)


## Run generation RG6: the map is made by the rules the run's unlocks leave (the run's start's,
## `Sim.unlocks`): with the flag unlocked, the changed definition's map; without (a guest playing the
## host's run: its own save is never read), the definition's own; the registry's never changes.
func test_the_map_is_made_by_the_rules_the_run_s_unlocks_leave() -> void:
	var id: StringName = _unlockable()
	var registry: Node = root.get_node("Registry")
	var definition := registry.call("get_resource", &"runs", id) as RunDefinition
	var before: int = SimHash.of(definition.biomes[0])
	var unlocked := RunUnlocks.of([&"test_deeper"] as Array[StringName])
	var changed_maps: int = 0
	for seed: int in [3, 11, 19, 27]:
		tick.begin_run()
		tick.sim.run_seed = seed
		tick.sim.unlocks = unlocked.copy()
		events.emit_signal("run_begun", id, 2, 0)
		var map: RunMap = run.get(&"map") as RunMap
		check(map != null and map.is_made(), "seed %d: made" % seed)
		if map == null:
			continue
		var expected: RunMap = _map_of(definition.changed_by(unlocked), seed, 2)
		check_equal(SimHash.of(map), SimHash.of(expected), "seed %d: the changed rules' map" % seed)
		check(map.first().scale > _map_of(definition, seed, 2).first().scale, "seed %d: the player curve's change in each room's scale" % seed)
		var plain: RunMap = _map_of(definition, seed, 2)
		if SimHash.of(plain) != SimHash.of(map):
			changed_maps += 1
		# The same seed with none unlocked: a guest's run, whatever its own save holds.
		tick.begin_run()
		tick.sim.run_seed = seed
		events.emit_signal("run_begun", id, 2, 0)
		check_equal(SimHash.of(run.get(&"map")), SimHash.of(plain), "seed %d: none unlocked, the definition's own map" % seed)
	check_equal(changed_maps, 4, "every changed map differs from its plain one")
	check_equal(SimHash.of(definition.biomes[0]), before, "the registry's definition never changes")
