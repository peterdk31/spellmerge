extends "res://tests/support/suite.gd"
## A room reroll lays only the rerolled room again (the owner, 2026-11-19; `BiomeWorld.relay_room`,
## Flow's `_reroll_room`): over a crypt map in play with Feel, the other pieces' layout nodes, mists
## and cover views are the same objects after it, Feel's world is not laid again (only that piece is
## relearnt, `RoomHearing.relaid`), the rerolled room's place, dark and Y map entry are its new ones;
## the grid's layers are those of the rerolled map laid fresh; and a restore of the rerolled world
## gives the same state hash, map and grid. It also prints how long a whole lay and a room's relay
## take (the PR's timings).
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const RoomHearingScript := preload("res://gameplay/feel/room_hearing.gd")
const SpectacleScript := preload("res://gameplay/feel/spectacle.gd")
const UnseenDarkScript := preload("res://gameplay/feel/unseen_dark.gd")
const PartyMapViewScript := preload("res://gameplay/feel/party_map_view.gd")
const CoverRoomsScript := preload("res://gameplay/feel/cover_rooms.gd")

const DT: float = 1.0 / 60.0

var flow: FlowScript
var tick: TickScript
var input: Node
var registry: Node
var projectiles: Node
var feel: Node


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	tick = root.get_node("Tick") as TickScript
	input = root.get_node("PlayerInput")
	registry = root.get_node("Registry")
	projectiles = root.get_node("Projectiles")
	feel = root.get_node("Feel")
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)


func after_each() -> void:
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	for seat in 4:
		input.leave(seat)
	tick.begin_run()


func _crypt() -> RunDefinition:
	return registry.call(&"get_resource", &"runs", &"crypt") as RunDefinition


func _map(seed_value: int) -> BiomeMap:
	return BiomeGenerator.generate(_crypt(), registry.call(&"run_content"), registry.call(&"piece_shapes", &"crypt"), Sim.seeded(seed_value))


func _start(map: BiomeMap) -> void:
	var fights: Array[RoomFight] = []
	for room in map.rooms():
		fights.append(RoomFight.new())
	check(flow.start_biome(0, map, fights), "the biome starts")
	tick.run(DT)


## A reroll of `map` whose room moves or changes template (so its walls and place change): [room,
## the map rerolled], or [] for none.
func _moving_reroll(map: BiomeMap, seed_value: int) -> Array:
	var shapes: Dictionary = registry.call(&"piece_shapes", &"crypt")
	for room in range(1, map.rooms()):
		if map.room_kinds[room] == &"boss":
			continue
		for roll in 6:
			var made: BiomeMap = BiomeGenerator.reroll_room(_crypt(), registry.call(&"run_content"), shapes, Sim.seeded(seed_value), 1, map, room, roll)
			if made != null and made.room_templates[room] != map.room_templates[room] and made.room_places[room] != map.room_places[room]:
				return [room, made]
	return []


func _grid() -> RoomGrid:
	return projectiles.call(&"grid") as RoomGrid


## The grid's layers laid from the map (its room walls and mouths, holes, places), not the bodies'.
func _layers() -> Array:
	var grid: RoomGrid = _grid()
	var walls: PackedByteArray = (grid.get(&"_wall_cells") as PackedByteArray).duplicate()
	for cell in walls.size():
		walls[cell] &= RoomGrid.ROOM_CELL | RoomGrid.MOUTH_CELL
	var rects: Array[Rect2] = []
	for place in grid.places():
		rects.append(grid.place_rect(place))
	return [walls, grid.get(&"_hole_cells"), rects, grid.get(&"_place_cells"), grid.get(&"_place_mixed"), grid.bounds() if grid.has_method(&"bounds") else Rect2()]


func _hash() -> int:
	return SimHash.whole(SimHash.areas(tick.state_areas()))


## Feel's views stepped once (they read the pieces and the grid once a frame).
func _step_views() -> void:
	(feel.call(&"unseen_dark") as UnseenDarkScript).step(0.0, _grid())
	(feel.call(&"party_map") as PartyMapViewScript).step(0.0, root.get_node("Actors"), 1, _grid(), null)


func test_only_the_rerolled_room_is_laid_again() -> void:
	var seed_value: int = 2
	var map: BiomeMap = _map(seed_value)
	var found: Array = _moving_reroll(map, seed_value)
	check(not found.is_empty(), "a reroll that moves a room")
	if found.is_empty():
		return
	var room: int = found[0]
	var made: BiomeMap = found[1]
	input.add_virtual_device(0)
	_start(map)
	_step_views()
	var hearing: RoomHearingScript = feel.call(&"room_hearing") as RoomHearingScript
	var spectacle: SpectacleScript = feel.call(&"spectacle") as SpectacleScript
	var covers: CoverRoomsScript = feel.call(&"cover_rooms") as CoverRoomsScript
	var nodes: Array[Node] = []
	for piece in map.rooms() + map.bridges():
		nodes.append(flow.biome.get(&"_layouts")[piece])
	var mists: Array[Node] = []
	mists.assign(spectacle.room_mists)
	var views: Array[Node] = []
	for piece in covers.count():
		views.append(covers.view_of(piece))
	var world: int = hearing.world()
	var relaid: int = hearing.relaid()
	flow.call(&"_reroll_room", room, made, RoomFight.new())
	_step_views()
	check_equal(hearing.world(), world, "Feel's world is not laid again")
	check_equal(hearing.relaid(), relaid + 1, "one piece relearnt")
	check_equal(hearing.version_of(room), 1, "the rerolled room's")
	for piece in nodes.size():
		var now: Node = flow.biome.get(&"_layouts")[piece]
		if piece == room:
			check(now != nodes[piece] and is_instance_valid(now), "the rerolled room's layout is a new one")
			check_equal((now as Node2D).position, made.room_places[room], "at its new place")
		else:
			check(now == nodes[piece], "piece %d's layout untouched" % piece)
	var kept: int = 0
	for mist: Node in mists:
		if is_instance_valid(mist) and spectacle.room_mists.has(mist):
			kept += 1
	check(kept >= mists.size() - 1, "every other room's mist kept (%d of %d)" % [kept, mists.size()])
	for piece in views.size():
		check(covers.view_of(piece) == views[piece], "cover view %d the same" % piece)
	check_equal(_grid().place_rect(room), flow.biome.room_rect(room), "the room's place its new rectangle")
	var dark: UnseenDarkScript = feel.call(&"unseen_dark") as UnseenDarkScript
	check_equal(dark.get(&"_rects")[room], flow.biome.room_rect(room), "its dark over its new rectangle")
	check_equal(hearing.kind_of(room).id, made.room_kinds[room], "its kind relearnt")


func test_the_relaid_grid_is_the_rerolled_map_laid_fresh_and_a_restore_the_same_world() -> void:
	var seed_value: int = 2
	var map: BiomeMap = _map(seed_value)
	var found: Array = _moving_reroll(map, seed_value)
	if found.is_empty():
		check(false, "a reroll that moves a room")
		return
	var room: int = found[0]
	var made: BiomeMap = found[1]
	input.add_virtual_device(0)
	_start(map)
	var before: Snapshot = Snapshot.take(tick.state_areas(), root)
	var began: int = Time.get_ticks_usec()
	flow.call(&"_reroll_room", room, made, RoomFight.new())
	var room_usec: int = Time.get_ticks_usec() - began
	var relaid: Array = _layers()
	# As a reroll laid it before (the whole biome again, as a restore into another map): timed only.
	flow.biome.set(&"_laid", null)
	began = Time.get_ticks_usec()
	flow.call(&"_rebuild_biome", false)
	var whole_usec: int = Time.get_ticks_usec() - began
	print("Room reroll's lay: the whole biome laid again %.1f ms, the rerolled room alone %.1f ms" % [whole_usec / 1000.0, room_usec / 1000.0])
	check(_layers() == relaid, "the whole biome laid again from the rerolled map: the same layers")
	var hash_relaid: int = _hash()
	var after: Snapshot = Snapshot.take(tick.state_areas(), root)
	check_equal(after.problems, PackedStringArray(), "taken without problems")
	check_equal(before.restore(tick.state_areas(), root), PackedStringArray(), "the world before restored")
	check(flow.biome.map.same_as(map), "the map before")
	check_equal(after.restore(tick.state_areas(), root), PackedStringArray(), "the rerolled world restored")
	check(flow.biome.map.same_as(made), "the rerolled map")
	check_equal(_hash(), hash_relaid, "the same state hash as the world relaid")
	check(_layers() == relaid, "the restored grid's layers are the relaid one's")
	check_equal((flow.biome.room_layout(room) as Node2D).position, made.room_places[room], "the room laid at its new place")
	# The rerolled map laid fresh: the same grid.
	flow.stop_run()
	_start(made.copy())
	check(_layers() == relaid, "a fresh lay of the rerolled map gives the relaid grid's layers")
