class_name MapTeleport
extends RefCounted
## A teleport from the held Y map (the owner, 2026-11-19: "with the Y map open and not in a fight,
## the player can pick a cleared room on the map and teleport there alone"): Flow's, as its doors are
## (`LockDoors`). Which rooms a seat's wizard may go to now, the hint each seat is told of them, and
## the teleport itself.
##
## - **Who may** (`may_go`): the seat's own wizard (not a foe it possesses: "only that player"),
##   standing (not down, falling or spawning in), in a biome, where no fight is under way round it:
##   the place it stands on is not a room whose fight is started and not cleared, nor sealed, and on
##   a bridge neither end's room is in a fight.
## - **Where to** (`rooms_for`): every cleared room of the biome (`RoomLife.CLEARED`: a fight won, or
##   a room with none, the start room among them) but the one it stands in.
## - **The hint** (`tell`): each seat is told its rooms and their middles as they change
##   (`teleport_rooms_shown`, view only: the HUD's map picker), and told none as the biome goes and
##   after a restore (`forget`).
## - **The teleport** (`go`, the command `map_teleport_requested`'s, at the tick's start): checked
##   again (a pick from a stale hint does nothing), the wizard is put at the room's spawn nearest its
##   middle (`spot_in`), on clear ground, and materializes there (`Actor.spawn` for ARRIVE_SECONDS in
##   ARRIVE_STYLE: it cannot be hurt or act meanwhile, and Feel draws it built out of light by whole
##   pixels), and
##   `wizard_teleported` tells Feel where it left (its stepped vanish). Nobody else moves; nothing
##   waits (a free split).
##
## **State:** none of its own: who may go is read from the room life and the bodies, and the teleport
## is the body's position and its spawn (state). The hints are this machine's (DERIVED).

const NONE: int = -1
const SEATS: int = 4
## How long a teleported wizard materializes, in seconds, and in which spawn style (content/spawn_styles).
const ARRIVE_SECONDS: float = 0.6
const ARRIVE_STYLE: StringName = &"materialize"

const DERIVED: Array[StringName] = [&"events", &"_told"]

var events: Node = null
## By seat: the rooms it was last told it may go to, as a bit a room (-1: none told yet).
var _told: PackedInt64Array = PackedInt64Array([NONE, NONE, NONE, NONE])


## Every hint forgotten and told empty (the biome left, a snapshot restored): the next `tell` says
## each seat's again.
func forget() -> void:
	_told.fill(NONE)
	if events != null:
		for seat in SEATS:
			events.teleport_rooms_shown.emit(seat, PackedInt32Array(), PackedVector2Array())


## True when `wizard` (a seat's own, which it drives now: `driven`) may teleport from the map now
## (see the class doc).
static func may_go(wizard: Actor, driven: Node2D, life: RoomLife, map: BiomeMap) -> bool:
	if wizard == null or not is_instance_valid(wizard) or driven != wizard or map == null or life == null or life.rooms() <= 0:
		return false
	if wizard.is_down() or wizard.is_leaving() or wizard.is_dying():
		return false
	var place: int = wizard.room
	if place < 0:
		return false
	if place < life.rooms():
		return calm(place, life)
	var bridge: int = place - life.rooms()
	if bridge >= map.bridges():
		return false
	for end in 2:
		if _fighting(map.end_room(bridge, end), life):
			return false
	return true


## The rooms `wizard` may teleport to now, as a bit a room (0 when it may not go at all).
static func rooms_for(wizard: Actor, driven: Node2D, life: RoomLife, map: BiomeMap) -> int:
	if not may_go(wizard, driven, life, map):
		return 0
	var rooms: int = 0
	for room in mini(life.rooms(), 63):
		if room != wizard.room and life.has(room, RoomLife.CLEARED):
			rooms |= 1 << room
	return rooms


## Tell each seat (its own wizard `wizard_of.call(seat)`, the body it drives `driven[seat]`) the
## rooms it may teleport to, where they changed.
func tell(wizard_of: Callable, driven: Array[Node2D], biome: BiomeWorld, life: RoomLife) -> void:
	for seat in SEATS:
		var wizard := wizard_of.call(seat) as Actor
		var body: Node2D = driven[seat] if seat < driven.size() else null
		var rooms: int = rooms_for(wizard, body, life, biome.map)
		if rooms == _told[seat]:
			continue
		_told[seat] = rooms
		if events == null:
			continue
		var numbers := PackedInt32Array()
		var middles := PackedVector2Array()
		for room in mini(life.rooms(), 63):
			if rooms & (1 << room) != 0:
				numbers.append(room)
				middles.append(biome.room_rect(room).get_center())
		events.teleport_rooms_shown.emit(seat, numbers, middles)


## Teleport seat `seat`'s `wizard` to `room` if it may (see the class doc): put at `at` (clear
## ground in the room, found by the caller) and materializing there. True when it went.
func go(seat: int, wizard: Actor, driven: Node2D, life: RoomLife, map: BiomeMap, room: int, at: Vector2) -> bool:
	if room < 0 or room >= 63 or rooms_for(wizard, driven, life, map) & (1 << room) == 0:
		return false
	arrive(seat, wizard, at, events)
	return true


## Seat `seat`'s `wizard` put at `at` and materializing there (`Actor.spawn` for ARRIVE_SECONDS in
## ARRIVE_STYLE), `bus` (the events, or null) told where it left (`wizard_teleported`): a teleport's
## arrival, from the map or a secret rune (`SecretRunes`).
static func arrive(seat: int, wizard: Actor, at: Vector2, bus: Node) -> void:
	var from: Vector2 = wizard.position
	wizard.position = at
	wizard.velocity = Vector2.ZERO
	wizard.find_room()
	wizard.spawn(ARRIVE_SECONDS, ARRIVE_STYLE)
	if bus != null:
		bus.wizard_teleported.emit(seat, from, at)


## True when room `room` has no fight under way and is not sealed (a teleport may leave it).
static func calm(room: int, life: RoomLife) -> bool:
	return not _fighting(room, life) and not life.has(room, RoomLife.SEALED)


## Where a wizard teleported into a room of rectangle `rect` and places `places` stands: the room's
## spawn nearest its middle (a player's first, else an enemy's: open floor, clear of its props), else
## its middle. The caller puts it on clear ground.
static func spot_in(places: RoomPlaces, rect: Rect2) -> Vector2:
	var middle: Vector2 = rect.get_center()
	if places == null:
		return middle
	var spawns: PackedVector2Array = places.player_spawns if not places.player_spawns.is_empty() else places.enemy_spawns
	var best: Vector2 = middle
	var best_distance: float = INF
	for spawn in spawns:
		var distance: float = spawn.distance_squared_to(middle)
		if distance < best_distance:
			best_distance = distance
			best = spawn
	return best


static func _fighting(room: int, life: RoomLife) -> bool:
	return room >= 0 and room < life.rooms() and life.has(room, RoomLife.STARTED) and not life.has(room, RoomLife.CLEARED)
