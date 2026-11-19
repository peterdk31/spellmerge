extends RefCounted
## Hand-made biome maps for the tests (connected biomes CB2, docs/milestones/connected-biomes.md):
## crypt rooms joined west to east by the crypt's bridge, each room placed where its socket meets the
## bridge's. `walk_through()` is CB2's test map: the antechamber, the nave and the ossuary court, two
## bridges. `twelve_rooms()` is a biome of twelve for measuring the hash and the snapshot: the nave
## ten times between them, every other one mirrored up and down or both ways.

const ROOM_FOLDER: StringName = &"rooms"
const BRIDGE: StringName = &"crypt_bridge"
const FIRST: StringName = &"arena_01"
const MIDDLE: StringName = &"arena_02"
const LAST: StringName = &"arena_03"


## The test map (three rooms, two bridges), its rooms' shapes read from `registry`.
static func walk_through(registry: Object) -> BiomeMap:
	return _row(registry, [FIRST, MIDDLE, LAST] as Array[StringName], [0, 0, 0] as Array[int])


## CB3's split map: the nave the start room (room 0), the antechamber west of it (room 1) and the
## ossuary court east of it (room 2), each joined to the nave by a bridge, so a party can split to two
## fights at once. `mirrors`: the antechamber's, the nave's and the court's mirrorings. `templates`:
## other rooms in their places, west, middle (the start room) and east (connected biomes CB11).
## `kinds`: the rooms' kinds, west, middle and east (empty: a fight, the start room and a fight;
## connected biomes CB12b, where a room's kind is its look).
static func split(registry: Object, mirrors: Array[int] = [0, 0, 0], templates: Array[StringName] = [FIRST, MIDDLE, LAST], kinds: Array[StringName] = []) -> BiomeMap:
	var row: BiomeMap = _row(registry, templates, mirrors)
	var map := BiomeMap.new()
	map.biome = row.biome
	# The row's room 1 (the nave) first, then its rooms 0 and 2.
	var order: Array[int] = [1, 0, 2]
	for room: int in order:
		var kind: StringName = kinds[room] if room < kinds.size() else (&"start" if room == 1 else &"fight")
		map.add_room(row.room_templates[room], row.room_places[room], row.room_mirrors[room], kind)
	for bridge in row.bridges():
		map.add_bridge(row.bridge_templates[bridge], row.bridge_places[bridge], row.bridge_mirrors[bridge], order.find(row.end_room(bridge, 0)), row.end_socket(bridge, 0), order.find(row.end_room(bridge, 1)), row.end_socket(bridge, 1))
	map.work_out_depths()
	return map


## Every template `map` names, unmirrored (template id to `PieceShape`), as `BiomeMap.problems` takes them.
static func shapes(registry: Object, map: BiomeMap) -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in map.room_templates + map.bridge_templates:
		out[id] = shape(registry, id)
	return out


## The world point where room `room`'s socket facing `facing` is, in `map` (its rooms' shapes read
## from `registry`).
static func socket_point(registry: Object, map: BiomeMap, room: int, facing: int) -> Vector2:
	var room_shape: PieceShape = shape(registry, map.room_templates[room]).mirrored(map.room_mirrors[room])
	return map.room_places[room] + room_shape.socket_at[room_shape.socket_facing.find(facing)]


## Twelve rooms in a row, eleven bridges.
static func twelve_rooms(registry: Object) -> BiomeMap:
	var templates: Array[StringName] = [FIRST]
	var mirrors: Array[int] = [0]
	for i in 10:
		templates.append(MIDDLE)
		mirrors.append([0, PieceShape.MIRROR_Y, PieceShape.MIRROR_X, PieceShape.MIRROR_X | PieceShape.MIRROR_Y][i % 4])
	templates.append(LAST)
	mirrors.append(0)
	return _row(registry, templates, mirrors)


## The unmirrored shape of template `id` in `registry`.
static func shape(registry: Object, id: StringName) -> PieceShape:
	return PieceShape.of_room(registry.call(&"get_resource", ROOM_FOLDER, id) as RoomBase)


## Rooms of `templates` (mirrored by `mirrors`) west to east, each joined to the next by a bridge
## from its east socket to the next one's west socket, kinds `fight` (the first `start`).
static func _row(registry: Object, templates: Array[StringName], mirrors: Array[int]) -> BiomeMap:
	var map := BiomeMap.new()
	map.biome = &"crypt"
	var bridge: PieceShape = shape(registry, BRIDGE)
	var bridge_west: int = bridge.socket_facing.find(RoomSocket.Facing.WEST)
	var bridge_east: int = bridge.socket_facing.find(RoomSocket.Facing.EAST)
	var place := Vector2.ZERO
	var last_east: int = -1
	for i in templates.size():
		var room: PieceShape = shape(registry, templates[i]).mirrored(mirrors[i])
		var west: int = room.socket_facing.find(RoomSocket.Facing.WEST)
		if i > 0:
			# The bridge's west socket on the last room's east socket; this room's west socket on the
			# bridge's east one.
			var previous: int = i - 1
			var previous_shape: PieceShape = shape(registry, templates[previous]).mirrored(mirrors[previous])
			var joint: Vector2 = map.room_places[previous] + previous_shape.socket_at[last_east]
			var bridge_at: Vector2 = joint - bridge.socket_at[bridge_west]
			place = bridge_at + bridge.socket_at[bridge_east] - room.socket_at[west]
			map.add_room(templates[i], place, mirrors[i], &"fight")
			map.add_bridge(BRIDGE, bridge_at, 0, previous, last_east, i, west)
		else:
			map.add_room(templates[i], place, mirrors[i], &"start")
		last_east = room.socket_facing.find(RoomSocket.Facing.EAST)
	map.work_out_depths()
	return map


## A biome world of `map` (default: `twelve_rooms`) laid into `into` over `projectiles`' grid.
static func laid(registry: Object, projectiles: Object, into: Node2D, map: BiomeMap = null) -> BiomeWorld:
	var biome := BiomeWorld.new()
	biome.registry = registry as BiomeWorld.RegistryScript
	biome.projectiles = projectiles as BiomeWorld.ProjectileManagerScript
	var problems: PackedStringArray = biome.lay(into, map if map != null else twelve_rooms(registry))
	assert(problems.is_empty(), "\n".join(problems))
	return biome


## The bytes of every leaf of the state of `areas` (name to object), as a snapshot keeps them and the
## hash reads them (each leaf's `var_to_bytes`).
static func state_bytes(areas: Dictionary) -> int:
	var walk := StateWalk.new()
	var total: Array[int] = [0]
	for name: String in areas:
		walk.walk(name, areas[name], func(_path: String, value: Variant) -> void: total[0] += var_to_bytes(value).size())
	return total[0]


## The bytes of the room grid's layers and what is worked out from them (its DERIVED members): what
## the hash and every snapshot would hold if they were state.
static func grid_layer_bytes(grid: RoomGrid) -> int:
	var total: int = 0
	for member: String in StateWalk.listed(RoomGrid, "DERIVED"):
		total += var_to_bytes(grid.get(member)).size()
	return total
