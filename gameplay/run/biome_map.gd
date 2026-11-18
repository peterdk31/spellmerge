class_name BiomeMap
extends RefCounted
## A biome's map (connected biomes CB2, docs/milestones/connected-biomes.md, "The model"): one
## continuous world of floating rooms joined by bridges. Rooms, each a template (`RoomBase` id), its
## place in the biome's world, its mirroring (`PieceShape.MIRROR_X`, `MIRROR_Y`) and its kind
## (`RoomKind` id); bridges, each a walkway template (`RoomBase.walkway`), its place and mirroring,
## and the two room sockets its own sockets 0 and 1 meet; and each room's depth, the fewest bridges
## from room 0 (the start room). Made once (by hand for now, by the seeded generator from CB5) and
## then **kept as small hashed state**, as `RunMap` is: a joining machine and a restored snapshot
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
## overlap, and a bridge overlaps only the two rooms it joins; and every room is reached from the
## start room.

## How many numbers a bridge's `bridge_ends` row holds: room a, its socket, room b, its socket.
const END_FIELDS: int = 4

## The biome it is a map of (`MapRules.biome`).
var biome: StringName = &""
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
	return other != null and biome == other.biome and room_templates == other.room_templates and room_places == other.room_places and room_mirrors == other.room_mirrors and room_kinds == other.room_kinds and bridge_templates == other.bridge_templates and bridge_places == other.bridge_places and bridge_mirrors == other.bridge_mirrors and bridge_ends == other.bridge_ends and depths == other.depths


## A copy, row for row.
func copy() -> BiomeMap:
	var out := BiomeMap.new()
	out.biome = biome
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
	return found


func _place_problems(what: String, place: Vector2) -> PackedStringArray:
	var found := PackedStringArray()
	if fmod(place.x, PieceShape.GRID) != 0.0 or fmod(place.y, PieceShape.GRID) != 0.0:
		found.append("%s is placed at %s, off the %d px grid." % [what, place, int(PieceShape.GRID)])
	return found
