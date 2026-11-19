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
## A key with no zone tries these spots round the room's middle, in order, for the first clear of
## what the room holds (a shop's items, a fountain's pool: `key_spot`'s `keep_off`).
const KEY_SPOTS: Array[Vector2] = [
	Vector2(0.0, 0.0), Vector2(0.0, 64.0), Vector2(0.0, -64.0), Vector2(64.0, 0.0), Vector2(-64.0, 0.0),
	Vector2(64.0, 64.0), Vector2(-64.0, 64.0), Vector2(64.0, -64.0), Vector2(-64.0, -64.0),
	Vector2(0.0, 128.0), Vector2(0.0, -128.0),
]
## How far a key keeps off a shop's item (pixels).
const KEY_OFF_ITEM: float = 24.0
## The zone a shop's reroll sign stands in (the owner's ask of 2026-11-19), and with none, where it
## stands from the room's middle: under the shelf's row.
const SIGN_ZONE: StringName = &"shelf_sign"
const SIGN_SPOT: Vector2 = Vector2(0.0, 40.0)
## The zone the players' reward items lie in (the owner's ask of 2026-11-19: a reward lies as an item
## in the room's middle), and where each seat's lies from it (or from the room's middle), by seat: a
## row under the middle, its middle column left free, so none is opened from inside the portal home
## (48 px square on the middle) nor lies on a key's first spots.
const REWARD_ZONE: StringName = &"reward"
const REWARD_SPOTS: Array[Vector2] = [Vector2(-60.0, 48.0), Vector2(-36.0, 48.0), Vector2(36.0, 48.0), Vector2(60.0, 48.0)]


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


## Where a shop's reroll sign stands (world pixels): its `shelf_sign` zone, else SIGN_SPOT from the
## room's middle.
static func sign_spot(places: RoomPlaces, middle: Vector2) -> Vector2:
	var zone: Rect2 = places.zone(SIGN_ZONE) if places != null else Rect2()
	return (zone.get_center() if zone.has_area() else middle + SIGN_SPOT).floor()


## Where each seat's reward item lies in a room (world pixels, by seat, before each is put on clear
## ground): REWARD_SPOTS round its `reward` zone's middle, else round the room's middle.
static func reward_spots(places: RoomPlaces, middle: Vector2) -> PackedVector2Array:
	var zone: Rect2 = places.zone(REWARD_ZONE) if places != null else Rect2()
	var from: Vector2 = zone.get_center() if zone.has_area() else middle
	var out := PackedVector2Array()
	for offset: Vector2 in REWARD_SPOTS:
		out.append((from + offset).floor())
	return out


## The fountain's pool of a room (world pixels).
static func pool(places: RoomPlaces, middle: Vector2) -> Rect2:
	var zone: Rect2 = places.zone(FOUNTAIN_ZONE) if places != null else Rect2()
	return zone if zone.has_area() else Rect2((middle - POOL_SIZE * 0.5).floor(), POOL_SIZE)


## Where a key dropped in a room lies (world pixels, before it is put on clear ground): its `key`
## zone, else the first of KEY_SPOTS round its middle that lies outside every rectangle of
## `keep_off` (a fountain's pool, a shop's items grown by KEY_OFF_ITEM; a key may drop in any room
## since the owner's follow-up of 2026-11-19), else its middle.
static func key_spot(places: RoomPlaces, middle: Vector2, keep_off: Array[Rect2] = []) -> Vector2:
	return key_spots(places, middle, keep_off, 1)[0]


## Where `count` keys dropped in one room lie, apart: the first as `key_spot`, each next the next of
## KEY_SPOTS (round the `key` zone's middle when there is one, else the room's) clear of `keep_off`;
## with too few clear, the rest on the first.
static func key_spots(places: RoomPlaces, middle: Vector2, keep_off: Array[Rect2], count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var zone: Rect2 = places.zone(KEY_ZONE) if places != null else Rect2()
	var from: Vector2 = zone.get_center() if zone.has_area() else middle
	for offset: Vector2 in KEY_SPOTS:
		if out.size() >= count:
			break
		var spot: Vector2 = from + offset
		var clear: bool = true
		for rect: Rect2 in keep_off:
			clear = clear and not rect.has_point(spot)
		if clear or (zone.has_area() and offset == Vector2.ZERO):
			out.append(spot.floor())
	while out.size() < maxi(count, 1):
		out.append(out[0] if not out.is_empty() else from.floor())
	return out


## What a key keeps off in a room of `kind` (its fill's things: a fountain's pool, a shop's items,
## each grown by KEY_OFF_ITEM), `places` and `middle` as `shelf` and `pool` take them.
static func taken_by(kind: RoomKind, places: RoomPlaces, middle: Vector2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if kind == null:
		return out
	if kind.fill == RoomKind.FILL_FOUNTAIN:
		out.append(pool(places, middle).grow(KEY_OFF_ITEM))
	elif kind.fill == RoomKind.FILL_SHOP:
		for spot: Vector2 in shelf(places, middle):
			out.append(Rect2(spot, Vector2.ZERO).grow(KEY_OFF_ITEM))
		out.append(Rect2(sign_spot(places, middle), Vector2.ZERO).grow(KEY_OFF_ITEM))
	return out
