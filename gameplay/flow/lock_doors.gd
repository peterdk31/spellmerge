class_name LockDoors
extends RefCounted
## A biome's key doors and secret rocks (connected biomes CB11, docs/milestones/connected-biomes.md,
## decisions 21 and 22): the doors a party opens by what it carries or casts, never by gathering.
## Flow's state (it holds one, as it holds its `GatherDoors`); pure rules on it. Flow drops the keys
## and hears the floor touched.
##
## - **A locked room** is one whose kind enters by `RoomKind.DOOR_KEY` (a treasure room) or
##   `DOOR_SECRET` (a secret room). Each mouth where a bridge meets a key room is one of its doors; a
##   secret room's door is its bridge's other mouth, where the bridge leaves the room it hangs off
##   (the owner, 2026-11-20: the bridge to a secret room is hidden until the secret is found, so the
##   rock stands in that room's doorway and nobody walks out onto a bridge not drawn). A door is shut
##   (`RoomGrid.shut_mouth`: a wall to everything) until the room opens; then all its doors open, for
##   everyone (decision 21: a key door opens for all).
## - **Keys** (decision 21, as the owner changed it on 2026-11-19: "Multiple treasures can be in each
##   biome. But there should not necessarily be a key for each treasure room available"): a key is
##   no room's own. Any key opens any key door and is spent by it, and the party chooses which doors
##   to open. Flow says how many there are and where each drops (`begin`'s `drops`: a room it picks by
##   the run's chance among those reached from the start without passing a locked door,
##   `open_rooms`); with none said, one a key room, in the room its bridge hangs off (the shallowest
##   beside it). A key drops as its room is cleared (`drop_keys`; a room with no fight is cleared as
##   it is entered, so its key lies on its floor), two in one room each on a spot of its own (Flow's).
## - **A key is an item** (the owner, 2026-11-19: "each player picks up keys individually and uses
##   them individually"): it lies there until the first standing body a seat drives (in seat order:
##   its wizard, or a foe it possesses) whose feet come within KEY_REACH; it goes into that body's
##   own currency bag (`ItemKinds.KEY`, `KeyBase`; nobody else's), and the floor no longer knows it.
##   A shut key door opens by walking into it, as before (no button): the first standing driven body
##   at it (on its bridge, or on the room's lip outside the shut mouth, as at a gather door) with a
##   key in its own bag spends one and the room opens for everyone (decision 21). A body there with
##   none opens nothing, and its seat's hint says a key is needed (`key_needed_shown`).
## - **A secret rock** (decision 22) opens to one element, rolled for its room as the biome begins
##   (Flow's `_begin_locks`): that element touching the floor (`floor_touched`, queued by
##   `queue_touch` and applied at the next `step`, never in the middle of the shots' step) with its
##   circle within TOUCH_REACH of the rock (`rock_of`: the doorway, from its landing inside the room
##   the bridge hangs off to its mouth) breaks it (`touched`), and the room opens.
## - **The view** is told each key door (`key_door_shown`), each rock (`secret_rock_shown`, with its
##   element) and each key lying (`key_shown`) as it changes; -1 when every one is forgotten (the biome
##   left, a restore: told again by `tell_all`), and the rooms opened (`rooms_opened`: as one opens,
##   empty as the biome goes, `again` after a restore; a secret room's symbol shows once found). The HUD is told, by seat, the shut key door its body
##   stands at with no key (`key_needed_shown`), and reads a body's keys from its bag (`bag_changed`).
##   Never read back by the simulation.

const EventsScript := preload("res://core/events/events.gd")

## A room's rule (`rules`): none, a key door, a secret rock.
const RULE_NONE: int = 0
const RULE_KEY: int = 1
const RULE_SECRET: int = 2
## No room, no door, every one (the view's -1).
const NONE: int = -1
## A key's states (`key_states`): not dropped yet, lying on the floor, taken into a body's bag.
const KEY_WAITING: int = 0
const KEY_LYING: int = 1
const KEY_TAKEN: int = 2
## The bag a key goes into (`ItemKinds.KEY`'s: the currency, beside the coins).
const KEY_BAG: StringName = &"currency"
## The most seats told a hint (`key_needed_shown`).
const SEATS: int = 4
## How near a wizard's feet must come to a key to take it, in pixels (a coin's reach).
const KEY_REACH: float = 10.0
## `begin`'s `drops` for "no key at all" (nowhere to drop one), as against none said (the old rule).
const NO_KEYS: PackedInt32Array = [-1]
## How far round a door's mouth its room's lip counts as at that door (as a gather door's).
const LIP_REACH: float = 24.0
## How near a floor touch's circle must come to a secret door's mouth to break its rock, in pixels.
const TOUCH_REACH: float = 8.0

## Not state: the bus (set by Flow), each door's mouth in the world (laid from the map, `lay`) and,
## by seat, the door its hint was last told (`key_needed_shown`: view only, told again after a restore).
const DERIVED: Array[StringName] = [&"events", &"_mouths", &"_rocks", &"_needed"]

var events: EventsScript = null
## Each room's rule (RULE_*), by its number; 1 in `opened` once it opened; a secret room's element.
var rules: PackedByteArray = PackedByteArray()
var opened: PackedByteArray = PackedByteArray()
var elements: Array[StringName] = []
## Each door: the room it leads into, and the bridge (and which end of it) whose mouth it is.
var door_rooms: PackedInt32Array = PackedInt32Array()
var door_bridges: PackedInt32Array = PackedInt32Array()
var door_ends: PackedInt32Array = PackedInt32Array()
## Each key: the room it drops in, its state (KEY_*) and where it lies.
var key_drops: PackedInt32Array = PackedInt32Array()
var key_states: PackedByteArray = PackedByteArray()
var key_at: PackedVector2Array = PackedVector2Array()
## The floor touches heard since the last step (`queue_touch`), applied at the next (`step`), so a
## rock never opens in the middle of the shots' step: each one's element, place and radius.
var touch_elements: Array[StringName] = []
var touch_at: PackedVector2Array = PackedVector2Array()
var touch_radii: PackedFloat32Array = PackedFloat32Array()
var _mouths: Array[Rect2] = []
## Each door's rock (a secret door's doorway, `rock_of`; a key door's mouth), laid with the mouths.
var _rocks: Array[Rect2] = []
var _needed: PackedInt32Array = PackedInt32Array([NONE, NONE, NONE, NONE])


## A biome's locks begin (every door shut, no key dropped): `map`'s rooms, each with its rule of
## `room_rules` (RULE_*, by room) and a secret room's element of `room_elements`; a door at each mouth
## of a locked room, and the keys: one each room of `drops` names (where it drops), or, with none
## named, one a key room dropped in the room at the other end of its bridge (the shallowest of
## them). Laid into the grid by `lay`.
func begin(map: BiomeMap, room_rules: PackedByteArray, room_elements: Array[StringName], drops: PackedInt32Array = PackedInt32Array()) -> void:
	clear()
	var count: int = map.rooms() if map != null else 0
	rules = room_rules.duplicate()
	rules.resize(count)
	opened.resize(count)
	opened.fill(0)
	elements = room_elements.duplicate()
	elements.resize(count)
	if map == null:
		return
	# The key rooms whose keys drop beside them (no `drops` said), by the same index as the keys.
	var beside := PackedInt32Array()
	for bridge in map.bridges():
		for end in 2:
			var room: int = map.end_room(bridge, end)
			if room < 0 or room >= count or rules[room] == RULE_NONE:
				continue
			door_rooms.append(room)
			door_bridges.append(bridge)
			# A secret room's rock stands at the bridge's far end, in the doorway of the room it
			# hangs off: the bridge is hidden until it breaks (the owner, 2026-11-20).
			door_ends.append(1 - end if rules[room] == RULE_SECRET else end)
			var other: int = map.end_room(bridge, 1 - end)
			if not drops.is_empty() or rules[room] != RULE_KEY:
				continue
			var at_key: int = beside.find(room)
			if at_key < 0:
				beside.append(room)
				key_drops.append(other)
			elif other < map.depths.size() and key_drops[at_key] < map.depths.size() and map.depths[other] < map.depths[key_drops[at_key]]:
				# A key room with more than one bridge: its key drops in the shallowest room beside it,
				# the one on the way to it.
				key_drops[at_key] = other
	for room: int in drops:
		if room >= 0 and room < count:
			key_drops.append(room)
	key_states.resize(key_drops.size())
	key_states.fill(KEY_WAITING)
	key_at.resize(key_drops.size())
	key_at.fill(Vector2.ZERO)


## The rooms of `map` the party reaches from its start room (0) without passing a locked door (a
## room whose rule of `room_rules` is not RULE_NONE), in room order, the start room among them: where
## a key may drop.
static func open_rooms(map: BiomeMap, room_rules: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	if map == null or map.rooms() == 0:
		return out
	var reached := PackedByteArray()
	reached.resize(map.rooms())
	reached[0] = 1
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var room: int = queue.pop_front()
		for bridge in map.bridges():
			for end in 2:
				if map.end_room(bridge, end) != room:
					continue
				var other: int = map.end_room(bridge, 1 - end)
				if other < 0 or other >= reached.size() or reached[other] != 0:
					continue
				if other < room_rules.size() and room_rules[other] != RULE_NONE:
					continue
				reached[other] = 1
				queue.append(other)
	for room in reached.size():
		if reached[room] != 0:
			out.append(room)
	return out


## No biome: no door, no key (the view told every one is forgotten, when there was one).
func clear() -> void:
	var had: bool = not door_rooms.is_empty()
	rules.resize(0)
	opened.resize(0)
	elements.clear()
	door_rooms.resize(0)
	door_bridges.resize(0)
	door_ends.resize(0)
	key_drops.resize(0)
	key_states.resize(0)
	key_at.resize(0)
	touch_elements.clear()
	touch_at.resize(0)
	touch_radii.resize(0)
	_mouths.clear()
	_rocks.clear()
	if had:
		_forget(false)
		_tell_opened(false)


## How many doors there are.
func doors() -> int:
	return door_rooms.size()


## The rule of room `room` (RULE_NONE out of the biome).
func rule_of(room: int) -> int:
	return rules[room] if room >= 0 and room < rules.size() else RULE_NONE


## True once room `room` opened (a room with no lock: never shut, so yes).
func is_open(room: int) -> bool:
	return rule_of(room) == RULE_NONE or opened[room] != 0


## The element that breaks secret room `room`'s rock (empty for any other room).
func element_of(room: int) -> StringName:
	return elements[room] if rule_of(room) == RULE_SECRET else &""


## The world rectangle of door `door`'s mouth (laid by `lay`; empty before).
func mouth_of(door: int) -> Rect2:
	return _mouths[door] if door >= 0 and door < _mouths.size() else Rect2()


## The world rectangle of door `door`'s rock, where its element breaks it and the view draws it: a
## secret door's doorway (`BiomeWorld.doorway_rect`: from the landing inside the room the bridge
## hangs off to its mouth, so a spell landing on that room's floor at the wall finds it); a key
## door's mouth. Laid by `lay` (empty before).
func rock_of(door: int) -> Rect2:
	return _rocks[door] if door >= 0 and door < _rocks.size() else Rect2()


## How many keys `body` holds in its own currency bag (0 for none, or no inventory).
static func keys_of(body: Actor) -> int:
	return body.inventory.count_of(KEY_BAG, KeyBase.ID) if body != null and body.inventory != null else 0


## Lay the doors into `grid` from the biome laid in `world` (as the biome starts, and after a restore:
## the grid's layers are not state): each door's mouth found, shut while its room is not open.
func lay(world: BiomeWorld, grid: RoomGrid) -> void:
	_mouths.clear()
	_rocks.clear()
	for door in doors():
		_mouths.append(world.mouth_rect(door_bridges[door], door_ends[door]) if world != null else Rect2())
		var secret: bool = rules[door_rooms[door]] == RULE_SECRET
		_rocks.append(world.doorway_rect(door_bridges[door], door_ends[door]) if world != null and secret else _mouths[door])
	if grid == null:
		return
	for door in doors():
		grid.shut_mouth(_mouths[door], not is_open(door_rooms[door]))


## Room `room` was cleared: each key still waiting to drop there lies at the next of `spots` (Flow
## puts each on clear ground; with fewer spots, the rest on the last), the view told.
func drop_keys(room: int, spots: PackedVector2Array) -> void:
	var dropped: int = 0
	for key in key_drops.size():
		if key_drops[key] == room and key_states[key] == KEY_WAITING:
			key_states[key] = KEY_LYING
			key_at[key] = spots[mini(dropped, spots.size() - 1)] if not spots.is_empty() else Vector2.ZERO
			dropped += 1
			_tell_key(key)


## One tick of the locks with `bodies` (by seat, the body each drives now: its wizard or a foe it
## possesses; null for none) and `life` the rooms' state (`rooms()` of them, whose bridges' places
## follow): the floor touches queued since the last step break their rocks first; then each lying key
## the first standing body's feet reach goes into that body's own bag; then each standing body at a
## shut key door spends one of its own keys and opens that room (one a tick, seat order), or, with
## none, its seat's hint says a key is needed. Returns the key room opened (NONE for none).
func step(bodies: Array[Node2D], life: RoomLife, grid: RoomGrid) -> int:
	for at in touch_elements.size():
		touched(touch_elements[at], touch_at[at], touch_radii[at], grid)
	touch_elements.clear()
	touch_at.resize(0)
	touch_radii.resize(0)
	for key in key_drops.size():
		if key_states[key] != KEY_LYING:
			continue
		for body: Node2D in bodies:
			var actor: Actor = _standing(body)
			if actor == null or actor.inventory == null or actor.position.distance_squared_to(key_at[key]) > KEY_REACH * KEY_REACH:
				continue
			if actor.inventory.add(ItemStack.of(ItemKinds.KEY, KeyBase.ID, 1)):
				key_states[key] = KEY_TAKEN
				_tell_key(key)
				if events != null:
					# For its pickup sound (the owner's ask of 2026-11-19).
					events.item_picked_up.emit(actor.id, ItemKinds.KEY, KeyBase.ID, key_at[key])
				break
	var opened_room: int = NONE
	for seat in bodies.size():
		var actor: Actor = _standing(bodies[seat])
		var door: int = _key_door_at(actor, life)
		var needed: int = NONE
		if door != NONE:
			if keys_of(actor) <= 0:
				needed = door
			elif opened_room == NONE and actor.inventory.take(KEY_BAG, KeyBase.ID):
				opened_room = door_rooms[door]
				open(opened_room, grid)
		_tell_needed(seat, needed)
	return opened_room


## `body` as an Actor while it stands (not downed), else null.
static func _standing(body: Node2D) -> Actor:
	var actor := body as Actor if is_instance_valid(body) else null
	return actor if actor != null and not actor.is_downed() else null


## The first shut key door `actor` stands at (on its bridge, or on its room's lip outside the shut
## mouth); NONE for none, or no actor.
func _key_door_at(actor: Actor, life: RoomLife) -> int:
	if actor == null:
		return NONE
	for door in doors():
		var room: int = door_rooms[door]
		if rules[room] != RULE_KEY or is_open(room):
			continue
		var at_door: int = life.rooms() + door_bridges[door] if life != null else NONE
		if actor.room == at_door or (actor.room == room and mouth_of(door).grow(LIP_REACH).has_point(actor.position)):
			return door
	return NONE


## An element touched the floor (`floor_touched`): kept for the next `step` (as the cover area keeps
## its touches), only when a shut secret rock of that element is there to break.
func queue_touch(element: StringName, at: Vector2, radius: float) -> void:
	for door in doors():
		var room: int = door_rooms[door]
		if rules[room] == RULE_SECRET and not is_open(room) and elements[room] == element:
			touch_elements.append(element)
			touch_at.append(at)
			touch_radii.append(radius)
			return


## An element touched the floor: `element` within `radius` of `at`. Every shut
## secret room of that element with a door's rock (`rock_of`) within the circle's reach (TOUCH_REACH
## more) opens. Returns the first room opened (NONE for none).
func touched(element: StringName, at: Vector2, radius: float, grid: RoomGrid) -> int:
	var found: int = NONE
	for door in doors():
		var room: int = door_rooms[door]
		if rules[room] != RULE_SECRET or is_open(room) or elements[room] != element:
			continue
		var rock: Rect2 = rock_of(door)
		var nearest := Vector2(clampf(at.x, rock.position.x, rock.end.x), clampf(at.y, rock.position.y, rock.end.y))
		var reach: float = maxf(radius, 0.0) + TOUCH_REACH
		if nearest.distance_squared_to(at) <= reach * reach:
			open(room, grid)
			if found == NONE:
				found = room
	return found


## Room `room` opens: every door of it, in `grid` too, and the view told.
func open(room: int, grid: RoomGrid) -> void:
	if rule_of(room) == RULE_NONE or is_open(room):
		return
	opened[room] = 1
	for door in doors():
		if door_rooms[door] != room:
			continue
		if grid != null:
			grid.shut_mouth(mouth_of(door), false)
		_tell_door(door)
	_tell_opened(false)


## After a snapshot was restored: the view forgets every door, rock and key, to draw each as it
## stands when told again (`tell_all`, by Flow once the mouths are laid again, `lay`).
func rebuild_derived() -> void:
	_forget(true)


## Tell the view every door, rock and key as they stand now, and the rooms opened (the biome laid;
## after a restore, `again`).
func tell_all(again: bool = false) -> void:
	for door in doors():
		_tell_door(door)
	for key in key_drops.size():
		_tell_key(key)
	_tell_opened(again)


## The rooms opened told to the view (`rooms_opened`, a copy of `opened`; the owner, 2026-11-20).
func _tell_opened(again: bool) -> void:
	if events != null:
		events.rooms_opened.emit(opened.duplicate(), again)


## The view's number of door `door`: key doors and secret rocks are each counted on their own.
func _view_number(door: int) -> int:
	var number: int = 0
	for other in door:
		if rules[door_rooms[other]] == rules[door_rooms[door]]:
			number += 1
	return number


func _tell_door(door: int) -> void:
	if events == null:
		return
	var room: int = door_rooms[door]
	if rules[room] == RULE_KEY:
		events.key_door_shown.emit(_view_number(door), mouth_of(door), is_open(room))
	elif rules[room] == RULE_SECRET:
		events.secret_rock_shown.emit(_view_number(door), rock_of(door), elements[room], is_open(room))


## Seat `seat`'s body stands at shut key door `door` with no key (NONE: at none), told on a change.
func _tell_needed(seat: int, door: int) -> void:
	if seat < 0 or seat >= SEATS or _needed[seat] == door:
		return
	_needed[seat] = door
	if events != null:
		var at: Vector2 = mouth_of(door).get_center() if door != NONE else Vector2.ZERO
		events.key_needed_shown.emit(seat, at, door != NONE)


func _tell_key(key: int) -> void:
	if events != null and key_states[key] != KEY_WAITING:
		events.key_shown.emit(key, key_at[key], key_states[key] == KEY_LYING)


## Every door, rock and key forgotten (NONE); `restored`: what is told next is drawn as it stands.
func _forget(restored: bool) -> void:
	_needed.fill(NONE)
	if events == null:
		return
	for seat in SEATS:
		events.key_needed_shown.emit(seat, Vector2.ZERO, false)
	events.key_door_shown.emit(NONE, Rect2(), restored)
	events.secret_rock_shown.emit(NONE, Rect2(), &"", restored)
	events.key_shown.emit(NONE, Vector2.ZERO, false)
