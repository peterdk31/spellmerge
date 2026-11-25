extends "res://tests/support/suite.gd"
## Every crypt room marks where a secret rune lies in it (the owner, 2026-11-25: "Mark every
## template"; docs/milestones/connected-biomes.md, "Answered by the owner (2026-11-25)"): one `rune`
## zone a template (`SpecialPlaces.RUNE_ZONE`), its middle the rune's place as the game lays it
## (`SecretRunes.lay`), in each of the room's four mirrorings: clear of what any of the room's kinds
## holds, its rewards and its props, off its spawns and doorways, and on clear ground, so the place
## chosen is the place it lies. Not checked: its decor and ground cover (looked at when placed).
const RegistryScript := preload("res://core/registry/registry.gd")
const ROOM_KINDS: StringName = &"room_kinds"
const CRYPT: StringName = &"crypt"
## Half a hidden rune's square: it lies off the walls and holes whole.
const RUNE_HALF: float = SecretRunes.ROCK * 0.5
## How far a rune keeps off a reward item (more than a rune's and a reward's reaches together, 12 and
## 14 px), a spawn and a doorway's socket.
const OFF_REWARD: float = 32.0
const OFF_SPAWN: float = 32.0
const OFF_DOORWAY: float = 64.0

var _registry: RegistryScript = null


func before_each() -> void:
	super.before_each()
	_registry = own(RegistryScript.new()) as RegistryScript
	_registry.scan()


## The crypt's rooms a biome's map may hold (sockets; no walkway, no seam).
func _rooms() -> Array[RoomBase]:
	var found: Array[RoomBase] = []
	for item: Resource in _registry.get_all(&"rooms"):
		var room := item as RoomBase
		if room != null and room.biome == CRYPT and not room.walkway and not room.seam and not room.places().socket_at.is_empty():
			found.append(room)
	return found


func test_every_crypt_room_marks_one_rune_zone_where_the_rune_then_lies() -> void:
	var rooms: Array[RoomBase] = _rooms()
	check(rooms.size() >= 27, "the crypt's rooms are found: %d" % rooms.size())
	for room: RoomBase in rooms:
		check_equal(room.places().zone_names.count(SpecialPlaces.RUNE_ZONE), 1, "%s marks one rune zone" % room.id)
		var shape: PieceShape = PieceShape.of_room(room)
		if shape == null or not room.places().zone(SpecialPlaces.RUNE_ZONE).has_area():
			continue
		var kinds: Array = [null]
		for id: StringName in room.kinds:
			kinds.append(_registry.get_resource(ROOM_KINDS, id))
		var layout: Node = own(room.scene.instantiate())
		var solid: Array[Rect2] = RoomPlaces.wall_rects(layout) + RoomPlaces.hole_rects(layout)
		# As a biome stands it (`BiomeWorld`): in each mirroring, its middle its shape's. What lies
		# round the middle (the rewards, the shelf) is not mirrored with the room, so each is its own case.
		var middle: Vector2 = shape.size * 0.5
		for mirror: int in PieceShape.MIRRORINGS:
			var places: RoomPlaces = room.places().placed_in(Vector2.ZERO, mirror, shape.size)
			var spot: Vector2 = places.zone(SpecialPlaces.RUNE_ZONE).get_center().floor()
			var what: String = "%s mirrored %d" % [room.id, mirror]
			for kind: Variant in kinds:
				var keep_off: Array[Rect2] = SecretRunes.keep_off_of(kind as RoomKind, places, middle)
				check_equal(SpecialPlaces.rune_spot(places, middle, keep_off), spot, "%s: its rune lies at its zone as a '%s'" % [what, (kind as RoomKind).id if kind != null else &""])
			for reward: Vector2 in SpecialPlaces.reward_spots(places, middle):
				check(reward.distance_to(spot) >= OFF_REWARD, "%s: nobody opening the reward at %s steps on its rune at %s" % [what, reward, spot])
			for spawn: Vector2 in places.player_spawns + places.enemy_spawns:
				check(spawn.distance_to(spot) >= OFF_SPAWN, "%s: nobody comes in on its rune (the spawn at %s)" % [what, spawn])
			for socket: Vector2 in places.socket_at:
				check(socket.distance_to(spot) >= OFF_DOORWAY, "%s: its rune keeps out of its doorway at %s" % [what, socket])
			var rune := Rect2(spot, Vector2.ZERO).grow(RUNE_HALF)
			for rect: Rect2 in solid:
				check(not _mirrored(rect, mirror, shape.size).intersects(rune), "%s: its rune at %s is on clear ground" % [what, spot])


## `rect` of a room `extent` in size, mirrored as the room is.
func _mirrored(rect: Rect2, mirror: int, extent: Vector2) -> Rect2:
	var at: Vector2 = rect.position
	if mirror & PieceShape.MIRROR_X:
		at.x = extent.x - rect.end.x
	if mirror & PieceShape.MIRROR_Y:
		at.y = extent.y - rect.end.y
	return Rect2(at, rect.size)


## Two secret rooms off one host: the second rune never lies on the first, zone or no zone.
func test_a_second_rune_of_a_room_takes_another_spot() -> void:
	var places := RoomPlaces.new()
	places.zone_names = [SpecialPlaces.RUNE_ZONE]
	places.zone_rects = [Rect2(88, 88, 24, 24)]
	places.zone_data = [null]
	var middle := Vector2(300, 200)
	check_equal(SpecialPlaces.rune_spot(places, middle), Vector2(100, 100), "the first at the zone's middle")
	var taken: Array[Rect2] = [Rect2(Vector2(100, 100), Vector2.ZERO).grow(SecretRunes.PROP_CLEAR)]
	check_equal(SpecialPlaces.rune_spot(places, middle, taken), middle + SpecialPlaces.RUNE_SPOTS[0], "the second at the first spot round the middle")


## The game's own laying: two runes of one host (no world here: no zone, the spots round a middle of
## zero) lie apart, the second off the first and off the first's arrival.
func test_two_runes_laid_in_one_room_lie_apart() -> void:
	var map := BiomeMap.new()
	map.add_rune(0, 1)
	map.add_rune(0, 2)
	var runes := SecretRunes.new()
	runes.lay(map, null, Callable())
	check_equal(runes.runes(), 2, "both laid")
	check_equal(runes.spot_of(0, 0), SpecialPlaces.RUNE_SPOTS[0], "the first at the first spot")
	check_equal(runes.spot_of(1, 0), SpecialPlaces.RUNE_SPOTS[1], "the second host rune at the next spot, not on the first")
	check_equal([runes.spot_of(0, 1), runes.spot_of(1, 1)], [SpecialPlaces.RUNE_SPOTS[0], SpecialPlaces.RUNE_SPOTS[0]], "each secret room's own rune at its own first spot")
