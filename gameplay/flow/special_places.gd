class_name SpecialPlaces
extends RefCounted
## Where a special room's things stand (connected biomes CB11, decisions 19 to 21): a shop's shelf,
## a fountain's pool and a dropped key, read from the room's places (`RoomPlaces`, at its place in
## the biome: its template's zones, mirrored with it), else laid round its middle. Pure rules; Flow
## asks them as a room opens or is cleared.

## The zones a template marks them by: each `shelf` zone an item's spot (in the tree's order), the
## `fountain` zone the pool, the `key` zone where a key dropped in the room lies.
const SHELF_ZONE: StringName = &"shelf"
const FOUNTAIN_ZONE: StringName = &"fountain"
const KEY_ZONE: StringName = &"key"
## A shelf with no zones: three spots in a row round the room's middle.
const SHELF_SPOTS: Array[Vector2] = [Vector2(-48.0, 0.0), Vector2(0.0, 0.0), Vector2(48.0, 0.0)]
## A pool with no zone: this big round the room's middle.
const POOL_SIZE: Vector2 = Vector2(64.0, 48.0)


## The shelf's spots of a room whose places are `places` and whose middle is `middle` (world pixels).
static func shelf(places: RoomPlaces, middle: Vector2) -> PackedVector2Array:
	var spots := PackedVector2Array()
	if places != null:
		for at in places.zone_names.size():
			if places.zone_names[at] == SHELF_ZONE:
				spots.append(places.zone_rects[at].get_center().floor())
	if spots.is_empty():
		for offset: Vector2 in SHELF_SPOTS:
			spots.append((middle + offset).floor())
	return spots


## The fountain's pool of a room (world pixels).
static func pool(places: RoomPlaces, middle: Vector2) -> Rect2:
	var zone: Rect2 = places.zone(FOUNTAIN_ZONE) if places != null else Rect2()
	return zone if zone.has_area() else Rect2((middle - POOL_SIZE * 0.5).floor(), POOL_SIZE)


## Where a key dropped in a room lies (world pixels, before it is put on clear ground).
static func key_spot(places: RoomPlaces, middle: Vector2) -> Vector2:
	var zone: Rect2 = places.zone(KEY_ZONE) if places != null else Rect2()
	return (zone.get_center() if zone.has_area() else middle).floor()
