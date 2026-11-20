class_name BiomeMap
extends RefCounted
## A biome's map (connected biomes CB2, docs/milestones/connected-biomes.md, "The model"): one
## continuous world of floating rooms joined by bridges. Rooms, each a template (`RoomBase` id), its
## place in the biome's world, its mirroring (`PieceShape.MIRROR_X`, `MIRROR_Y`) and its kind
## (`RoomKind` id); bridges, each a walkway template (`RoomBase.walkway`), its place and mirroring,
## and the two room sockets its own sockets 0 and 1 meet; and each room's depth, the fewest bridges
## from room 0 (the start room); and, once filled (the generator, `BiomeGenerator`, CB5), each room's
## scale and its enemies. Made once (by hand in the tests, by the seeded generator) and
## then **kept as small hashed state** (the run area's and Flow's): a joining machine and a restored snapshot
## never make their own. Only the nodes and the grid's layers are laid again from it
## (`BiomeWorld`, `rebuild_derived`).
##
## Kept as plain packed rows, so its hash and snapshot cost a few bytes a room (CB2 measures a
## 12-room biome: `test_state_declared.gd`, `test_snapshot.gd`, `test_snapshot_game.gd`).
##
## **The rules** (`problems`, from the templates' shapes): every place on the 32 px grid
## (`PieceShape.GRID`, decision 2); every template known, a room's no walkway and a bridge's one,
## each keeping its own rules (`PieceShape.problems`) in its mirroring; a bridge's sockets meet the
## room sockets it names at the same point, facing each other; no socket joined twice; no two rooms
## overlap, nor two bridges, and a bridge joins two rooms and overlaps only those; every mirroring
## one of the four; every room reached from the start room; and its depths worked out.

## How many numbers a bridge's `bridge_ends` row holds: room a, its socket, room b, its socket.
const END_FIELDS: int = 4

## The biome it is a map of (`MapRules.biome`).
var biome: StringName = &""
## The map style it was made in (`MapStyle.id`; empty for a hand-made map).
var style: StringName = &""
## Why the generator made no map (empty for a map made, or made by hand): `is_made`.
var not_made: PackedStringArray = PackedStringArray()
## Its rooms, by number (0: the start room): template ids, places (world pixels, whole and on the
## grid), mirrorings and kinds.
var room_templates: Array[StringName] = []
var room_places: PackedVector2Array = PackedVector2Array()
var room_mirrors: PackedByteArray = PackedByteArray()
var room_kinds: Array[StringName] = []
## Its bridges, by number: template ids, places, mirrorings, and END_FIELDS numbers a bridge in
## `bridge_ends` (the room and socket its socket 0 meets, then its socket 1's).
var bridge_templates: Array[StringName] = []
var bridge_places: PackedVector2Array = PackedVector2Array()
var bridge_mirrors: PackedByteArray = PackedByteArray()
var bridge_ends: PackedInt32Array = PackedInt32Array()
## Each room's depth: the fewest bridges from room 0 (-1: not reached). Worked out by `work_out_depths`
## once the map is made, and kept with it.
var depths: PackedInt32Array = PackedInt32Array()
## Each room's fill, once filled (empty rows for a map not filled): its scale (`RunScaling`, by its
## depth and the run's players) and its enemies (ids, one per body: a fight's bought by its scaled
## budget, the boss's one boss), room by room in `room_enemies`, room `r`'s ending at
## `room_enemy_ends[r]` (`enemies_of`).
var room_scales: PackedFloat32Array = PackedFloat32Array()
var room_enemy_ends: PackedInt32Array = PackedInt32Array()
var room_enemies: Array[StringName] = []
## Each enemy's elite card (connected biomes CB11, decision 24), by the same index as `room_enemies`:
## the card an elite gets in its staff, empty for an enemy that is no elite (`elites_of`).
var room_elites: Array[StringName] = []
## Each room's reward type (the owner's ask of 2026-11-19, `RewardType`): a reward room's item kind,
## card kind and element, decided as the biome is made (`BiomeGenerator`), empty names for a room of
## no type; by room, empty rows for a map not typed (made by hand).
var room_reward_items: Array[StringName] = []
var room_reward_card_kinds: Array[StringName] = []
var room_reward_elements: Array[StringName] = []


## Room `room`'s reward type (any: a room of no type, or a map not typed).
func reward_type_of(room: int) -> RewardType:
	if room < 0 or room >= room_reward_items.size():
		return RewardType.new()
	return RewardType.make(room_reward_items[room], room_reward_card_kinds[room], room_reward_elements[room])


## Room `room`'s reward type made `type` (the rows grown to every room, any for the others).
func type_room(room: int, type: RewardType) -> void:
	while room_reward_items.size() < rooms():
		room_reward_items.append(&"")
		room_reward_card_kinds.append(&"")
		room_reward_elements.append(&"")
	room_reward_items[room] = type.item
	room_reward_card_kinds[room] = type.card_kind
	room_reward_elements[room] = type.element


## A room of template `template` at `place`, mirrored by `mirror`, of kind `kind`: its number.
func add_room(template: StringName, place: Vector2, mirror: int = 0, kind: StringName = &"") -> int:
	room_templates.append(template)
	room_places.append(place)
	room_mirrors.append(mirror)
	room_kinds.append(kind)
	return room_templates.size() - 1


## A bridge of template `template` at `place`, mirrored by `mirror`, its socket 0 meeting room
## `room_a`'s socket `socket_a` and its socket 1 room `room_b`'s socket `socket_b`: its number.
func add_bridge(template: StringName, place: Vector2, mirror: int, room_a: int, socket_a: int, room_b: int, socket_b: int) -> int:
	bridge_templates.append(template)
	bridge_places.append(place)
	bridge_mirrors.append(mirror)
	bridge_ends.append_array(PackedInt32Array([room_a, socket_a, room_b, socket_b]))
	return bridge_templates.size() - 1


## True when it has rooms: a map made (else `not_made` says why).
func is_made() -> bool:
	return rooms() > 0


## Room `room`'s enemies (ids), once filled (none for a map not filled).
func enemies_of(room: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if room < 0 or room >= room_enemy_ends.size():
		return out
	var from: int = room_enemy_ends[room - 1] if room > 0 else 0
	for i in range(from, room_enemy_ends[room]):
		out.append(room_enemies[i])
	return out


## Each of room `room`'s enemies' elite card (`room_elites`; empty: no elite), by the same index as
## `enemies_of`.
func elites_of(room: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if room < 0 or room >= room_enemy_ends.size():
		return out
	var from: int = room_enemy_ends[room - 1] if room > 0 else 0
	for i in range(from, room_enemy_ends[room]):
		out.append(room_elites[i] if i < room_elites.size() else &"")
	return out


## Room `room`'s fill: its scale, its enemies and their elite cards (`elite_cards` by the same index,
## empty or short: no elite past its end; rooms filled in order, from room 0).
func fill_room(room: int, scale: float, enemies: Array[StringName], elite_cards: Array[StringName] = []) -> void:
	room_scales.resize(room + 1)
	room_scales[room] = scale
	for at in enemies.size():
		room_elites.append(elite_cards[at] if at < elite_cards.size() else &"")
	room_enemies.append_array(enemies)
	room_enemy_ends.resize(room + 1)
	room_enemy_ends[room] = room_enemies.size()


## How many rooms and bridges it has.
func rooms() -> int:
	return room_templates.size()


func bridges() -> int:
	return bridge_templates.size()


## The room bridge `bridge`'s socket `end` (0 or 1) meets, and that room's socket.
func end_room(bridge: int, end: int) -> int:
	return bridge_ends[bridge * END_FIELDS + end * 2]


func end_socket(bridge: int, end: int) -> int:
	return bridge_ends[bridge * END_FIELDS + end * 2 + 1]


## Each room's depth, the fewest bridges from room 0 (`depths`), worked out again from the bridges.
func work_out_depths() -> void:
	depths.resize(rooms())
	depths.fill(-1)
	if rooms() == 0:
		return
	depths[0] = 0
	var queue := PackedInt32Array([0])
	var head: int = 0
	while head < queue.size():
		var room: int = queue[head]
		head += 1
		for bridge in bridges():
			for end in 2:
				if end_room(bridge, end) != room:
					continue
				var other: int = end_room(bridge, 1 - end)
				if other >= 0 and other < rooms() and depths[other] < 0:
					depths[other] = depths[room] + 1
					queue.append(other)


## True when `other` is the same map, row for row.
func same_as(other: BiomeMap) -> bool:
	return other != null and biome == other.biome and style == other.style and not_made == other.not_made and room_scales == other.room_scales and room_enemy_ends == other.room_enemy_ends and room_enemies == other.room_enemies and room_elites == other.room_elites and room_reward_items == other.room_reward_items and room_reward_card_kinds == other.room_reward_card_kinds and room_reward_elements == other.room_reward_elements and room_templates == other.room_templates and room_places == other.room_places and room_mirrors == other.room_mirrors and room_kinds == other.room_kinds and bridge_templates == other.bridge_templates and bridge_places == other.bridge_places and bridge_mirrors == other.bridge_mirrors and bridge_ends == other.bridge_ends and depths == other.depths


## A copy, row for row.
func copy() -> BiomeMap:
	var out := BiomeMap.new()
	out.biome = biome
	out.style = style
	out.not_made = not_made.duplicate()
	out.room_scales = room_scales.duplicate()
	out.room_enemy_ends = room_enemy_ends.duplicate()
	out.room_enemies = room_enemies.duplicate()
	out.room_elites = room_elites.duplicate()
	out.room_reward_items = room_reward_items.duplicate()
	out.room_reward_card_kinds = room_reward_card_kinds.duplicate()
	out.room_reward_elements = room_reward_elements.duplicate()
	out.room_templates = room_templates.duplicate()
	out.room_places = room_places.duplicate()
	out.room_mirrors = room_mirrors.duplicate()
	out.room_kinds = room_kinds.duplicate()
	out.bridge_templates = bridge_templates.duplicate()
	out.bridge_places = bridge_places.duplicate()
	out.bridge_mirrors = bridge_mirrors.duplicate()
	out.bridge_ends = bridge_ends.duplicate()
	out.depths = depths.duplicate()
	return out


## The shape of room `room` as it is placed (its template's, mirrored), from `shapes` (template id to
## its unmirrored `PieceShape`); null when the template is not there.
func room_shape(room: int, shapes: Dictionary) -> PieceShape:
	var shape: PieceShape = shapes.get(room_templates[room]) as PieceShape
	return shape.mirrored(room_mirrors[room]) if shape != null else null


## The shape of bridge `bridge` as it is placed, as `room_shape`.
func bridge_shape(bridge: int, shapes: Dictionary) -> PieceShape:
	var shape: PieceShape = shapes.get(bridge_templates[bridge]) as PieceShape
	return shape.mirrored(bridge_mirrors[bridge]) if shape != null else null


## What breaks the rules (the class doc), one line each; empty for a sound map. `shapes`: template id
## to its unmirrored `PieceShape` (`PieceShape.of_room`).
func problems(shapes: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	if rooms() == 0:
		found.append("the map has no rooms.")
		return found
	if room_places.size() != rooms() or room_mirrors.size() != rooms() or room_kinds.size() != rooms() or bridge_places.size() != bridges() or bridge_mirrors.size() != bridges() or bridge_ends.size() != bridges() * END_FIELDS:
		found.append("the map's rows are not of one length: make it with add_room and add_bridge.")
		return found
	if (room_scales.size() != 0 or room_enemy_ends.size() != 0) and (room_scales.size() != rooms() or room_enemy_ends.size() != rooms() or room_enemy_ends[rooms() - 1] != room_enemies.size()):
		found.append("the map's fill is not one a room: fill every room with fill_room, in order.")
		return found
	for room in rooms():
		if room_mirrors[room] > (PieceShape.MIRROR_X | PieceShape.MIRROR_Y):
			found.append("room %d's mirroring %d is none of the four (0 to 3)." % [room, room_mirrors[room]])
			return found
	for bridge in bridges():
		if bridge_mirrors[bridge] > (PieceShape.MIRROR_X | PieceShape.MIRROR_Y):
			found.append("bridge %d's mirroring %d is none of the four (0 to 3)." % [bridge, bridge_mirrors[bridge]])
			return found
	var room_rects: Array[Rect2] = []
	var room_shapes: Array[PieceShape] = []
	for room in rooms():
		var shape: PieceShape = room_shape(room, shapes)
		room_shapes.append(shape)
		room_rects.append(shape.rect_at(room_places[room]) if shape != null else Rect2())
		var what: String = "room %d (%s)" % [room, room_templates[room]]
		if shape == null:
			found.append("%s: no such template." % what)
			continue
		if shape.walkway:
			found.append("%s is a walkway: a room's template is a room." % what)
		found.append_array(_place_problems(what, room_places[room]))
		found.append_array(shape.problems())
	for a in rooms():
		for b in range(a + 1, rooms()):
			if room_rects[a].intersects(room_rects[b]):
				found.append("rooms %d and %d overlap: move them apart." % [a, b])
	var used: Dictionary = {}
	var bridge_rects: Array[Rect2] = []
	for bridge in bridges():
		var shape: PieceShape = bridge_shape(bridge, shapes)
		var what: String = "bridge %d (%s)" % [bridge, bridge_templates[bridge]]
		if shape == null:
			found.append("%s: no such template." % what)
			continue
		if not shape.walkway:
			found.append("%s is no walkway: a bridge's template is one (RoomBase.walkway)." % what)
		found.append_array(_place_problems(what, bridge_places[bridge]))
		found.append_array(shape.problems())
		if shape.sockets() != 2:
			found.append("%s has %d sockets: a bridge has two, one at each end." % [what, shape.sockets()])
			continue
		var rect: Rect2 = shape.rect_at(bridge_places[bridge])
		for other in bridge_rects.size():
			if bridge_rects[other].intersects(rect):
				found.append("bridges %d and %d overlap: move them apart." % [other, bridge])
		bridge_rects.append(rect)
		if end_room(bridge, 0) == end_room(bridge, 1):
			found.append("%s joins room %d to itself: a bridge joins two rooms." % [what, end_room(bridge, 0)])
		var ends: Array[int] = []
		for end in 2:
			var room: int = end_room(bridge, end)
			var socket: int = end_socket(bridge, end)
			ends.append(room)
			if room < 0 or room >= rooms() or room_shapes[room] == null or socket < 0 or socket >= room_shapes[room].sockets():
				found.append("%s's end %d names room %d's socket %d, which is not there." % [what, end, room, socket])
				continue
			var key: Vector2i = Vector2i(room, socket)
			if used.has(key):
				found.append("room %d's socket %d is joined twice (bridges %d and %d)." % [room, socket, used[key], bridge])
			used[key] = bridge
			var room_at: Vector2 = room_places[room] + room_shapes[room].socket_at[socket]
			var bridge_at: Vector2 = bridge_places[bridge] + shape.socket_at[end]
			if room_at != bridge_at:
				found.append("%s's socket %d is at %s, room %d's socket %d at %s: they meet at one point." % [what, end, bridge_at, room, socket, room_at])
			if shape.socket_facing[end] != RoomSocket.opposite(room_shapes[room].socket_facing[socket]):
				found.append("%s's socket %d faces %s, room %d's socket %d %s: they face each other." % [what, end, RoomSocket.name_of(shape.socket_facing[end]), room, socket, RoomSocket.name_of(room_shapes[room].socket_facing[socket])])
		for room in rooms():
			if not ends.has(room) and rect.intersects(room_rects[room]):
				found.append("%s overlaps room %d, which it does not join: move it." % [what, room])
	var reach: BiomeMap = copy()
	reach.work_out_depths()
	for room in rooms():
		if reach.depths[room] < 0:
			found.append("room %d cannot be reached from the start room: join it with a bridge." % room)
	if reach.depths != depths:
		found.append("its depths are not its bridges' (%s, worked out %s): call work_out_depths once it is made." % [depths, reach.depths])
	return found


func _place_problems(what: String, place: Vector2) -> PackedStringArray:
	var found := PackedStringArray()
	if fmod(place.x, PieceShape.GRID) != 0.0 or fmod(place.y, PieceShape.GRID) != 0.0:
		found.append("%s is placed at %s, off the %d px grid." % [what, place, int(PieceShape.GRID)])
	return found
