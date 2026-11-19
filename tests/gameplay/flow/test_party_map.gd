extends "res://tests/support/suite.gd"
## The party's map (connected biomes CB9, `PartyMap`): a room is seen once a wizard enters it, the
## run stat `map_reveal` shows rooms past it, and the map is Flow's state: hashed, snapshotted and
## told to the view again after a restore, so a machine that joins mid-run knows it. On the real
## autoloads with the split test map (tests/support/biome_maps.gd: the nave the start room, the
## antechamber west, the ossuary court east).
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const DT: float = 1.0 / 60.0
const WEST: int = 1
const EAST: int = 2

var flow: FlowScript
var events: Node
var tick: TickScript
var input: Node
var registry: Node
var told: Array[Array] = []


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	events = root.get_node("Events")
	tick = root.get_node("Tick") as TickScript
	input = root.get_node("PlayerInput")
	registry = root.get_node("Registry")
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	told.clear()
	events.connect("rooms_seen", _on_seen)


func after_each() -> void:
	events.disconnect("rooms_seen", _on_seen)
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	for seat in 4:
		input.leave(seat)
	tick.begin_run()


func _on_seen(seen: PackedByteArray, again: bool) -> void:
	told.append([seen, again])


func _start(players: int = 1) -> BiomeMap:
	var map: BiomeMap = BiomeMaps.split(registry)
	for seat in players:
		input.add_virtual_device(seat)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new(), RoomFight.new()]
	check(flow.start_biome(0, map, fights), "the biome starts")
	tick.run(DT)
	return map


func _into(map: BiomeMap, room: int, facing: int) -> void:
	(flow.get_wizard(0) as Actor).global_position = BiomeMaps.socket_point(registry, map, room, facing) - RoomSocket.way(facing) * 24.0
	tick.run(DT)


## A line of four rooms, 0-1-2-3, a bridge between each two (only its ends read).
static func _line() -> BiomeMap:
	var map := BiomeMap.new()
	for room in 4:
		map.add_room(&"r%d" % room, Vector2(room * 512, 0), 0, &"fight")
	for bridge in 3:
		map.add_bridge(&"b", Vector2.ZERO, 0, bridge, 0, bridge + 1, 1)
	return map


func test_a_room_entered_is_seen_and_reveal_shows_rooms_past_it() -> void:
	var map: BiomeMap = _line()
	var party := PartyMap.new()
	party.begin(map.rooms(), 0)
	check(party.enter(1, map), "entering changes the map")
	check_equal(party.seen, PackedByteArray([0, 2, 0, 0]), "reveal 0: only the room entered")
	check(not party.enter(1, map), "entering again changes nothing")
	party.begin(map.rooms(), 1)
	party.enter(1, map)
	check_equal(party.seen, PackedByteArray([1, 2, 1, 0]), "reveal 1: its neighbours shown")
	party.enter(2, map)
	check_equal(party.seen, PackedByteArray([1, 2, 2, 1]), "a shown room entered; an entered one never goes back")
	party.begin(map.rooms(), 2)
	party.enter(0, map)
	check_equal(party.seen, PackedByteArray([2, 1, 1, 0]), "reveal 2: two bridges out")


func test_the_runs_map_reveal_is_heard_as_the_run_begins() -> void:
	var change: StatChange = StatChange.make(&"map_reveal", 2.0)
	flow.set("_asking", true)
	events.emit_signal("run_stats_ruled", [change] as Array[StatChange])
	flow.set("_asking", false)
	check_equal(flow.get("_chosen_reveal"), 2, "the run's reveal is the stat worked out from its changes")
	events.emit_signal("run_stats_ruled", [] as Array[StatChange])
	check_equal(flow.get("_chosen_reveal"), 2, "heard only while Flow asks")


func test_the_start_room_is_seen_and_each_room_as_a_wizard_enters_it() -> void:
	var map: BiomeMap = _start()
	check_equal(flow.party_map.seen, PackedByteArray([2, 0, 0]), "the start room is entered as the biome starts")
	check(not told.is_empty() and told[-1][0] == PackedByteArray([2, 0, 0]) and not told[-1][1], "and the view told")
	_into(map, WEST, RoomSocket.Facing.EAST)
	check_equal(flow.party_map.seen, PackedByteArray([2, 2, 0]), "the antechamber entered")
	check(told[-1][0] == PackedByteArray([2, 2, 0]), "told as it changed")
	flow.stop_run()
	check(told[-1][0].is_empty(), "the biome gone: the view forgets the map")


func test_the_seen_rooms_are_hashed_and_survive_a_snapshot() -> void:
	var map: BiomeMap = _start()
	var before := Snapshot.take(tick.state_areas(), root)
	var hash_before: int = SimHash.whole(SimHash.areas(tick.state_areas()))
	_into(map, EAST, RoomSocket.Facing.WEST)
	check_equal(flow.party_map.seen, PackedByteArray([2, 0, 2]), "the court entered")
	var after := Snapshot.take(tick.state_areas(), root)
	var hash_after: int = SimHash.whole(SimHash.areas(tick.state_areas()))
	check(hash_before != hash_after, "the hash changes with the map")
	# A change of the map alone changes Flow's hash: it is state.
	var flow_hash: int = SimHash.areas({"Flow": flow})["Flow"]
	flow.party_map.seen[WEST] = 1
	check(SimHash.areas({"Flow": flow})["Flow"] != flow_hash, "the seen rooms are in Flow's hash")
	flow.party_map.seen[WEST] = 0
	told.clear()
	check(before.restore(tick.state_areas(), root).is_empty(), "restored the start")
	check_equal(flow.party_map.seen, PackedByteArray([2, 0, 0]), "the snapshot's map: the court unseen again")
	check(not told.is_empty() and told[-1][0] == PackedByteArray([2, 0, 0]) and told[-1][1], "told again, as it stands")
	check(after.restore(tick.state_areas(), root).is_empty(), "restored the later one")
	check_equal(flow.party_map.seen, PackedByteArray([2, 0, 2]), "the court seen again")
	check_equal(SimHash.whole(SimHash.areas(tick.state_areas())), hash_after, "the same hash as before it was taken")
