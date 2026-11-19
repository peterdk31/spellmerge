extends "res://tests/support/suite.gd"
## The run's area (run generation RG3, gameplay/run/run.gd; a biome's map since connected biomes
## CB8), on the real autoloads: a run begun (`run_begun`) makes the run's biome map from the run's
## seed and answers with every room's fight (`run_room_filled`: its enemies, scale and pace) and then
## the map (`run_biome_chosen`, a copy); Flow lays that map and plays those fights; the map is the
## run's state (in the Tick's areas, hashed, gone at the next run's start, as in the hub); a run the
## registry lacks answers nothing; the map is made for the run's players and by the rules the run's
## unlocks leave.

const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")

var run: Node
var flow: FlowScript
var events: Node
var tick: TickScript
var input: Node
## What the area answered: `["filled", room, enemies, scale, group, refill_at, stagger]` and
## `["chosen", map]`, in order.
var answers: Array = []


func before_each() -> void:
	run = root.get_node("Run")
	flow = root.get_node("Flow") as FlowScript
	events = root.get_node("Events")
	tick = root.get_node("Tick") as TickScript
	input = root.get_node("PlayerInput")
	answers.clear()
	events.connect("run_room_filled", _on_filled)
	events.connect("run_biome_chosen", _on_chosen)
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)


func after_each() -> void:
	events.disconnect("run_room_filled", _on_filled)
	events.disconnect("run_biome_chosen", _on_chosen)
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	input.leave(0)
	input.leave(1)
	tick.begin_run()


func _on_filled(room: int, enemies: Array[StringName], scale: float, group: int, refill_at: int, stagger: float) -> void:
	answers.append([&"filled", room, enemies.duplicate(), scale, group, refill_at, stagger])


func _on_chosen(map: RefCounted) -> void:
	answers.append([&"chosen", map])


func _registry() -> Node:
	return root.get_node("Registry")


## The map the generator makes for `definition` on `seed` for `players`, as the area should have it.
func _map_of(definition: RunDefinition, seed_value: int, players: int = 1) -> BiomeMap:
	var registry: Node = _registry()
	return BiomeGenerator.generate(definition, registry.call("run_content") as RunContent, registry.call("run_shapes", definition) as Dictionary, Sim.seeded(seed_value), players)


func _crypt() -> RunDefinition:
	return _registry().call("get_resource", &"runs", &"crypt") as RunDefinition


func test_a_run_begun_makes_its_map_and_tells_each_room_s_fight() -> void:
	tick.begin_run()
	tick.sim.run_seed = 41
	events.emit_signal("run_begun", &"crypt", 1)
	var map: BiomeMap = run.get(&"map") as BiomeMap
	check(map != null and map.is_made(), "the crypt run's map is made")
	if map == null:
		return
	check_equal(SimHash.of(map), SimHash.of(_map_of(_crypt(), 41)), "the map is the generator's for the run's seed")
	check_equal(answers.size(), map.rooms() + 1, "a fight a room, then the map")
	var rules: MapRules = _crypt().biomes[0]
	for room in mini(map.rooms(), answers.size()):
		var told: Array = answers[room]
		check_equal(told[0], &"filled", "room %d: its fight first" % room)
		check_equal(told[1], room, "room %d: by its number" % room)
		check_equal(told[2], map.enemies_of(room), "room %d: what stands in it" % room)
		check(is_equal_approx(told[3], map.room_scales[room]), "room %d: its scale" % room)
		var enemies: Array[StringName] = map.enemies_of(room)
		var pace: Array = RoomFill.pace(rules.spawning, RunScaling.scaled_budget(rules.room_budget, map.room_scales[room])) if not enemies.is_empty() else [0, 0, 0.0]
		check_equal([told[4], told[5]], [pace[0], pace[1]], "room %d: its pace, by its scaled budget" % room)
	check(map.enemies_of(0).is_empty(), "the start room holds no fight")
	var chosen: Array = answers.back()
	check_equal(chosen[0], &"chosen", "the map last")
	check(chosen[1] != map and SimHash.of(chosen[1]) == SimHash.of(map), "a copy of the run's own map")


func test_the_same_seed_gives_the_same_map_and_another_seed_another() -> void:
	var hashes: Dictionary = {}
	for seed_value: int in [5, 5, 6, 7, 8]:
		tick.begin_run()
		tick.sim.run_seed = seed_value
		events.emit_signal("run_begun", &"crypt", 1)
		var made: int = SimHash.of(run.get(&"map"))
		if hashes.has(seed_value):
			check_equal(made, hashes[seed_value], "seed %d: the same map again" % seed_value)
		hashes[seed_value] = made
	check(hashes[5] != hashes[6] or hashes[6] != hashes[7] or hashes[7] != hashes[8], "other seeds make other maps")


func test_a_run_start_takes_the_map_away() -> void:
	tick.begin_run()
	events.emit_signal("run_begun", &"crypt", 1)
	check(run.get(&"map") != null, "a map")
	tick.begin_run()
	check(run.get(&"map") == null, "a run's start (the hub) has none")


func test_an_unknown_run_answers_nothing() -> void:
	tick.begin_run()
	events.emit_signal("run_begun", &"no_such_run", 1)
	check(run.get(&"map") == null and answers.is_empty(), "no map, no answer")


func test_the_map_is_part_of_the_game_state() -> void:
	tick.begin_run()
	check(tick.state_areas().has("Run"), "the Tick hashes the run area")
	var before: int = SimHash.of(run)
	events.emit_signal("run_begun", &"crypt", 1)
	check(SimHash.of(run) != before, "the map changes the run's hash")
	var walk := StateWalk.new()
	walk.values("Run", run, [])
	check_equal(walk.problems, PackedStringArray(), "the area's state walks without problems")


## Flow lays the map the run made and plays its fights: the party starts in its start room.
func test_flow_lays_the_map_the_run_makes() -> void:
	input.add_virtual_device(0)
	check(flow.start_run(0), "the crypt run starts")
	var map: BiomeMap = run.get(&"map") as BiomeMap
	check(map != null and flow.biome.map != null, "a map, laid")
	if map == null or flow.biome.map == null:
		return
	check_equal(SimHash.of(flow.biome.map), SimHash.of(map), "Flow's world is the run's map")
	check(flow.biome.map != map, "Flow keeps a copy of its own")
	check_equal(flow.life.rooms(), map.rooms(), "a room's life for each room")
	for room in map.rooms():
		check_equal(flow.life.fights[room].enemies, map.enemies_of(room), "room %d's fight is the map's" % room)
	check_equal(flow.room_id, map.room_templates[0], "the start room")
	check_equal((flow.get_wizard(0) as Actor).room, 0, "the wizard stands in it")
	check(flow.biome.room_rect(0).has_point(flow.get_wizard(0).position), "at its place in the world")


func test_the_map_is_made_for_the_run_s_players() -> void:
	tick.begin_run()
	tick.sim.run_seed = 9
	events.emit_signal("run_begun", &"crypt", 1)
	var alone: BiomeMap = run.get(&"map") as BiomeMap
	tick.begin_run()
	tick.sim.run_seed = 9
	events.emit_signal("run_begun", &"crypt", 4)
	var four: BiomeMap = run.get(&"map") as BiomeMap
	check(alone != null and four != null, "both made")
	if alone == null or four == null:
		return
	check_equal(four.room_templates, alone.room_templates, "the same rooms for any number of players")
	var deepest: int = alone.room_kinds.find(&"boss")
	check(four.room_scales[deepest] > alone.room_scales[deepest], "four players' rooms are harder")


## Run generation RG6: a run of the crypt's rules with one rule change, harder for more players once
## `test_harder` is unlocked, registered once under an id of its own.
func _unlockable() -> StringName:
	var registry: Node = _registry()
	var id: StringName = &"test_unlockable_crypt"
	if registry.call("get_resource", &"runs", id) == null:
		var made: RunDefinition = _crypt().copied()
		made.id = id
		made.changes = [RunRuleChange.make(&"test_harder", RunRuleChange.Target.SCALE_PLAYER_END, 2.0)] as Array[RunRuleChange]
		check_equal(made.biome_problems(registry.call("run_content") as RunContent, registry.call("run_shapes", made) as Dictionary), PackedStringArray(), "the unlockable run is sound")
		registry.call("add", &"runs", made)
	return id


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
	SaveFile.new(path).set_flag(&"test_harder")
	check_equal((run.call("unlocks_now") as RunUnlocks).flags, [&"test_harder"] as Array[StringName], "a flag the run %s's change names" % id)
	var frames: Node = root.get_node("Frames")
	check_equal((frames.call("next_run_unlocks") as RunUnlocks).flags, [&"test_harder"] as Array[StringName], "the frames service asks the area")
	tick.begin_run()
	check_equal(tick.sim.unlocks.flags, [&"test_harder"] as Array[StringName], "and a run's start takes them")
	run.set(&"save", kept)
	DirAccess.remove_absolute(path)


## Run generation RG6: the map is made by the rules the run's unlocks leave (the run's start's,
## `Sim.unlocks`): with the flag unlocked, the changed definition's map; without (a guest playing the
## host's run: its own save is never read), the definition's own; the registry's never changes.
func test_the_map_is_made_by_the_rules_the_run_s_unlocks_leave() -> void:
	var id: StringName = _unlockable()
	var definition := _registry().call("get_resource", &"runs", id) as RunDefinition
	var before: int = SimHash.of(definition.biomes[0])
	var unlocked := RunUnlocks.of([&"test_harder"] as Array[StringName])
	for seed_value: int in [3, 11]:
		tick.begin_run()
		tick.sim.run_seed = seed_value
		tick.sim.unlocks = unlocked.copy()
		events.emit_signal("run_begun", id, 2)
		var map: BiomeMap = run.get(&"map") as BiomeMap
		check(map != null and map.is_made(), "seed %d: made" % seed_value)
		if map == null:
			continue
		check_equal(SimHash.of(map), SimHash.of(_map_of(definition.changed_by(unlocked), seed_value, 2)), "seed %d: the changed rules' map" % seed_value)
		var plain: BiomeMap = _map_of(definition, seed_value, 2)
		var deepest: int = map.room_kinds.find(&"boss")
		check(map.room_scales[deepest] > plain.room_scales[deepest], "seed %d: the player curve's change in the rooms' scale" % seed_value)
		# The same seed with none unlocked: a guest's run, whatever its own save holds.
		tick.begin_run()
		tick.sim.run_seed = seed_value
		events.emit_signal("run_begun", id, 2)
		check_equal(SimHash.of(run.get(&"map")), SimHash.of(plain), "seed %d: none unlocked, the definition's own map" % seed_value)
	check_equal(SimHash.of(definition.biomes[0]), before, "the registry's definition never changes")
