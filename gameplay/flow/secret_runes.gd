class_name SecretRunes
extends RefCounted
## A biome's secret runes (the owner, 2026-11-20: a secret room may be reached "by a secret rune: no
## bridge at all: a hidden rune or crack in a room, once found, teleports a player to the secret room
## and back"): Flow's, as its doors are (`LockDoors`). A rune of the map (`BiomeMap.add_rune`) has two
## ends: the hidden rune in its host room (end 0) and the rune leading back in its secret room (end 1).
##
## - **Where they lie** (`lay`, as the biome begins: state, as a key's place is, so a restore never
##   lays them again round bodies standing since): each end at its room's `rune` zone, else at the
##   first spot round the room's middle clear of what the room holds (`SpecialPlaces.rune_spot`: its
##   shop or pool, its rewards, PROP_CLEAR round each of its props), on clear ground; a wizard arrives
##   ARRIVE from the other end's rune, on clear ground. The hidden rune's square (ROCK px, `rocks`) is the rune door's rock
##   (`LockDoors.lay`): the secret room's element touching the floor near it finds it, as a rock.
## - **The teleport** (`step`): once its secret room is open (`LockDoors.is_open`), a seat's own wizard
##   (not a foe it possesses), standing and not spawning in, whose feet come within REACH of either
##   end's rune, in a room with no fight under way and not sealed (`MapTeleport.calm`), goes to the
##   other end alone and materializes there (`MapTeleport.arrive`: as a teleport from the map, the
##   stepped vanish where it left). Its seat's runes then rest REST seconds (`rest`, state), so a wizard
##   arriving beside a rune is not sent straight back; nobody else moves or waits.
## - **The view** is told each rune (`secret_rune_shown`: its two ends, its element, whether it was
##   found) as it is found, and every rune again after a restore (`tell_all`); -1 as the biome goes.
##
## **State:** `rest` (by seat, seconds of `delta`) and where the runes lie (`spots`, `arrivals`);
## whether one is found is the locks' (`LockDoors.opened`).

const NONE: int = -1
const SEATS: int = 4
## How near a wizard's feet come to a rune's middle to step on it, in pixels.
const REACH: float = 12.0
## The side of a hidden rune's square, where its element finds it (`LockDoors.rock_of`), in pixels.
const ROCK: float = 24.0
## Where a wizard arrives from the rune it teleports to (pixels from that rune's middle; then on
## clear ground): beside it, out of its REACH.
const ARRIVE: Vector2 = Vector2(0.0, 32.0)
## How long a seat's runes rest after it teleported by one, in seconds.
const REST: float = 1.0
## The radius a rune and an arrival are put on clear ground with (a wizard's footprint).
const GROUND_RADIUS: float = 8.0
## How far a rune keeps off each of its room's props (pixels: a pillar's footprint and a wizard's).
const PROP_CLEAR: float = 32.0

## Not state: the bus, and which runes the view was told found (by rune: NONE untold, 0 hidden, 1
## found; told again after a restore).
const DERIVED: Array[StringName] = [&"events", &"_told"]

var events: Node = null
## By seat: seconds before its wizard may take a rune again.
var rest: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## Where each rune's ends lie and where a wizard taking it to that end arrives (by rune * 2 + end).
var spots: PackedVector2Array = PackedVector2Array()
var arrivals: PackedVector2Array = PackedVector2Array()
var _told: PackedInt32Array = PackedInt32Array()


## Lay the runes of `map` from the biome laid in `world` (as the biome begins): each end's rune and
## arrival, put on clear ground by `on_ground` (`on_ground.call(spot, radius)` -> the spot moved;
## unset: as it is), keeping off what a room of kind `kind_of.call(room)` (a `RoomKind`, or null)
## holds and its props. Every seat rested; the view is told nothing yet (`tell_all`).
func lay(map: BiomeMap, world: BiomeWorld, kind_of: Callable, on_ground: Callable = Callable()) -> void:
	spots.resize(0)
	arrivals.resize(0)
	rest.fill(0.0)
	var count: int = map.runes() if map != null else 0
	_told.resize(count)
	_told.fill(NONE)
	for rune in count:
		for end in 2:
			var room: int = map.rune_room(rune, end)
			var places: RoomPlaces = world.room_places(room) if world != null else null
			var middle: Vector2 = world.room_rect(room).get_center() if world != null else Vector2.ZERO
			var kind: RoomKind = kind_of.call(room) as RoomKind if kind_of.is_valid() else null
			var keep_off: Array[Rect2] = SpecialPlaces.taken_by(kind, places, middle)
			for spot: Vector2 in SpecialPlaces.reward_spots(places, middle):
				keep_off.append(Rect2(spot, Vector2.ZERO).grow(SpecialPlaces.KEY_OFF_ITEM))
			if places != null:
				for prop: Vector2 in places.placed_at:
					keep_off.append(Rect2(prop, Vector2.ZERO).grow(PROP_CLEAR))
			var spot: Vector2 = _put(SpecialPlaces.rune_spot(places, middle, keep_off), on_ground)
			spots.append(spot)
			arrivals.append(_put(spot + ARRIVE, on_ground))


## No biome: no rune (the view told every one is forgotten, when there was one); every seat rested.
func clear() -> void:
	var had: bool = not spots.is_empty()
	spots.resize(0)
	arrivals.resize(0)
	_told.resize(0)
	rest.fill(0.0)
	if had:
		forget(false)


## How many runes are laid.
func runes() -> int:
	return spots.size() / 2


## Where rune `rune`'s end `end` lies (0: its hidden rune, 1: the one leading back), world pixels.
func spot_of(rune: int, end: int) -> Vector2:
	var at: int = rune * 2 + end
	return spots[at] if rune >= 0 and end >= 0 and end < 2 and at < spots.size() else Vector2.ZERO


## Where a wizard taking rune `rune` to its end `end` arrives, world pixels.
func arrival_of(rune: int, end: int) -> Vector2:
	var at: int = rune * 2 + end
	return arrivals[at] if rune >= 0 and end >= 0 and end < 2 and at < arrivals.size() else Vector2.ZERO


## Each rune's hidden square (by rune), where its element finds it: the rune door's rock.
func rocks() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for rune in runes():
		out.append(Rect2(spot_of(rune, 0) - Vector2.ONE * ROCK * 0.5, Vector2.ONE * ROCK))
	return out


## One tick (`delta` seconds) of the runes of `map`, the locks `locks` saying which are found: each
## seat's rest runs down, then each seat's own wizard (`wizard_of.call(seat)`, the body it drives
## `driven[seat]`) standing on a found rune in a calm room goes to its other end (see the class doc);
## the view told each rune found since it was told. Returns how many wizards went.
func step(delta: float, map: BiomeMap, locks: LockDoors, life: RoomLife, wizard_of: Callable, driven: Array[Node2D]) -> int:
	var went: int = 0
	if map == null or locks == null or runes() == 0:
		return went
	_tell_found(map, locks)
	for seat in SEATS:
		if rest[seat] > 0.0:
			rest[seat] = maxf(rest[seat] - delta, 0.0)
			continue
		var wizard := wizard_of.call(seat) as Actor if wizard_of.is_valid() else null
		var body: Node2D = driven[seat] if seat < driven.size() else null
		if not _may_go(wizard, body):
			continue
		for rune in runes():
			var end: int = _end_at(map, rune, wizard, locks, life)
			if end == NONE:
				continue
			MapTeleport.arrive(seat, wizard, arrival_of(rune, 1 - end), events)
			rest[seat] = REST
			went += 1
			break
	return went


## After a snapshot was restored: the view forgets every rune, to draw each as it stands when told
## again (`tell_all`, by Flow).
func rebuild_derived() -> void:
	forget(true)


## Tell the view every rune as it stands now, `locks` saying which are found (the biome laid; after
## a restore, drawn as it stands).
func tell_all(map: BiomeMap, locks: LockDoors) -> void:
	_told.resize(runes())
	_told.fill(NONE)
	_tell_found(map, locks)


## Every rune forgotten by the view (rune -1); `restored`: what is told next is drawn as it stands.
func forget(restored: bool) -> void:
	if events != null:
		events.secret_rune_shown.emit(NONE, Vector2.ZERO, Vector2.ZERO, &"", restored)


static func _may_go(wizard: Actor, body: Node2D) -> bool:
	if wizard == null or not is_instance_valid(wizard) or body != wizard:
		return false
	return not (wizard.is_down() or wizard.is_leaving() or wizard.is_dying() or wizard.is_spawning())


## The end of rune `rune` (of `map`) whose rune `wizard`'s feet stand on now, with its secret room
## found and the room it stands in calm; NONE for none.
func _end_at(map: BiomeMap, rune: int, wizard: Actor, locks: LockDoors, life: RoomLife) -> int:
	if not locks.is_open(map.rune_room(rune, 1)):
		return NONE
	for end in 2:
		var room: int = map.rune_room(rune, end)
		if wizard.room != room or (life != null and not MapTeleport.calm(room, life)):
			continue
		if wizard.position.distance_squared_to(spot_of(rune, end)) <= REACH * REACH:
			return end
	return NONE


## Each rune whose found state the view was not told yet, told.
func _tell_found(map: BiomeMap, locks: LockDoors) -> void:
	if _told.size() != runes():
		# After a restore, before Flow told them again: every one told now.
		_told.resize(runes())
		_told.fill(NONE)
	for rune in runes():
		var secret: int = map.rune_room(rune, 1)
		var found: int = 1 if locks.is_open(secret) else 0
		if _told[rune] == found:
			continue
		_told[rune] = found
		if events != null:
			events.secret_rune_shown.emit(rune, spot_of(rune, 0), spot_of(rune, 1), locks.element_of(secret), found == 1)


static func _put(spot: Vector2, on_ground: Callable) -> Vector2:
	return (on_ground.call(spot, GROUND_RADIUS) as Vector2) if on_ground.is_valid() else spot
