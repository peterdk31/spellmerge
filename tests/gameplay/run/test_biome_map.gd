extends "res://tests/support/suite.gd"
## A biome's map (connected biomes CB2, `BiomeMap`, docs/milestones/connected-biomes.md, "The model"):
## the hand-made test map and a twelve-room one keep the rules; each rule is named when broken
## (places on the 32 px grid, sockets that meet and face each other, a socket joined once, rooms
## apart, a bridge over its own rooms only, every room reached); depths count bridges from the start
## room; a copy is the same map, and the map is plain state.
const RegistryScript := preload("res://core/registry/registry.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")

var _registry: RegistryScript = null
var _shapes: Dictionary = {}


func before_each() -> void:
	super.before_each()
	_registry = own(RegistryScript.new()) as RegistryScript
	_registry.scan()
	_shapes.clear()
	for id: StringName in [BiomeMaps.FIRST, BiomeMaps.MIDDLE, BiomeMaps.LAST, BiomeMaps.BRIDGE]:
		_shapes[id] = BiomeMaps.shape(_registry, id)


func test_the_test_maps_keep_the_rules() -> void:
	var map: BiomeMap = BiomeMaps.walk_through(_registry)
	check_equal(map.problems(_shapes), PackedStringArray(), "the walk-through map is sound")
	check_equal(map.rooms(), 3, "three rooms")
	check_equal(map.bridges(), 2, "two bridges")
	check_equal(map.depths, PackedInt32Array([0, 1, 2]), "each a bridge deeper")
	var twelve: BiomeMap = BiomeMaps.twelve_rooms(_registry)
	check_equal(twelve.problems(_shapes), PackedStringArray(), "the twelve-room map is sound, mirrored rooms and all")
	check_equal(twelve.rooms(), 12, "twelve rooms")
	check_equal(twelve.depths[11], 11, "the last is eleven bridges deep")


func _broken(change: Callable, says: String) -> void:
	var map: BiomeMap = BiomeMaps.walk_through(_registry)
	change.call(map)
	var problems: String = "\n".join(map.problems(_shapes))
	check(says in problems, "named: %s (got: %s)" % [says, problems])


func test_every_rule_is_named_when_broken() -> void:
	_broken(func(map: BiomeMap) -> void: map.room_places[1] += Vector2(8.0, 0.0), "off the 32 px grid")
	_broken(func(map: BiomeMap) -> void: map.room_places[2] += Vector2(32.0, 0.0), "they meet at one point")
	_broken(func(map: BiomeMap) -> void: map.room_templates[1] = &"no_such_room", "no such template")
	_broken(func(map: BiomeMap) -> void: map.bridge_templates[0] = BiomeMaps.MIDDLE, "is no walkway")
	_broken(func(map: BiomeMap) -> void: map.room_templates[0] = BiomeMaps.BRIDGE, "is a walkway")
	_broken(func(map: BiomeMap) -> void: map.bridge_ends[5] = 9, "not there")
	_broken(func(map: BiomeMap) -> void: map.room_places[2] = map.room_places[1] + Vector2(64.0, 0.0), "overlap")
	_broken(func(map: BiomeMap) -> void:
		map.bridge_ends.resize(4)
		map.bridge_templates.resize(1)
		map.bridge_places.resize(1)
		map.bridge_mirrors.resize(1), "cannot be reached")
	_broken(func(map: BiomeMap) -> void: map.room_mirrors[0] = PieceShape.MIRROR_X, "face each other")
	_broken(func(map: BiomeMap) -> void: map.add_bridge(BiomeMaps.BRIDGE, map.bridge_places[0], 0, 0, 0, 1, 0), "joined twice")
	_broken(func(map: BiomeMap) -> void: map.room_kinds.append(&"fight"), "not of one length")
	_broken(func(map: BiomeMap) -> void: map.room_mirrors[1] = 4, "none of the four")
	_broken(func(map: BiomeMap) -> void: map.bridge_ends[6] = 1, "to itself")
	_broken(func(map: BiomeMap) -> void: map.depths[2] = 1, "call work_out_depths")
	_broken(func(map: BiomeMap) -> void: map.add_bridge(BiomeMaps.BRIDGE, map.bridge_places[0] + Vector2(32.0, 0.0), 0, 0, 0, 1, 0), "bridges 0 and 2 overlap")


func test_a_copy_is_the_same_map_and_a_change_parts_them() -> void:
	var map: BiomeMap = BiomeMaps.walk_through(_registry)
	var copy: BiomeMap = map.copy()
	check(copy.same_as(map) and copy != map, "a copy is the same map, another object")
	copy.room_mirrors[2] = PieceShape.MIRROR_Y
	check(not copy.same_as(map), "a change parts them")
	check(map.room_mirrors[2] == 0, "the original is untouched")


func test_the_map_is_plain_state() -> void:
	check(StateWalk.is_simulation(BiomeMap), "a simulation script (gameplay/run)")
	check(StateWalk.listed(BiomeMap, "DERIVED").is_empty(), "every member state")
