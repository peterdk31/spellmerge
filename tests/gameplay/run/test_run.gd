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
	events.emit_signal("run_begun", &"crypt", 1)
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


func test_the_same_seed_gives_the_same_map_and_another_seed_another() -> void:
	var hashes: Dictionary = {}
	for seed: int in [5, 5, 6, 7, 8, 9]:
		tick.begin_run()
		tick.sim.run_seed = seed
		events.emit_signal("run_begun", &"crypt", 1)
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
	events.emit_signal("run_begun", &"crypt", 1)
	check(run.get(&"map") != null, "a map")
	tick.begin_run()
	check(run.get(&"map") == null and int(run.get(&"at")) == -1, "a run's start renews the area: no map")
	check(run.call("room_now") == null, "no room")


func test_an_unknown_run_answers_nothing() -> void:
	events.emit_signal("run_begun", &"no_such_run", 1)
	check(run.get(&"map") == null, "no map")
	check(answers.is_empty(), "no answer")


func test_the_map_is_part_of_the_game_state() -> void:
	tick.begin_run()
	check(tick.state_areas().has("Run"), "the Tick hashes the run's area")
	var before: int = SimHash.of(run)
	events.emit_signal("run_begun", &"crypt", 1)
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
	check_equal(flow.enemies_left(), node.enemies.size(), "every enemy the map puts there stands")
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
	events.emit_signal("run_begun", &"crypt", 1)
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
	events.emit_signal("run_begun", &"crypt", 3)
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
