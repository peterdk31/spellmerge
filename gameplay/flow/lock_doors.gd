class_name LockDoors
extends RefCounted
## A biome's key doors and secret rocks (connected biomes CB11, docs/milestones/connected-biomes.md,
## decisions 21 and 22): the doors a party opens by what it carries or casts, never by gathering.
## Flow's state (it holds one, as it holds its `GatherDoors`); pure rules on it. Flow drops the keys
## and hears the floor touched.
##
## - **A locked room** is one whose kind enters by `RoomKind.DOOR_KEY` (a treasure room) or
##   `DOOR_SECRET` (a secret room). Each mouth where a bridge meets it is one of its doors, shut
##   (`RoomGrid.shut_mouth`: a wall to everything) until the room opens; then all its doors open, for
##   everyone (decision 21: a key door opens for all).
## - **A key** (one a key room, decision 21) is dropped on the way to its room: in the room its
##   bridge hangs off (a key room is a dead end; else the shallowest room beside it), as that room is cleared (`drop_keys`; a room with no
##   fight is cleared as it is entered). It lies there until the first standing wizard (in the
##   party's order) whose feet come within KEY_REACH takes it: the party holds it. With it held, the
##   first standing wizard at one of its room's doors (on its bridge, or on the room's lip outside the
##   shut mouth, as at a gather door) opens it, and the key is spent.
## - **A secret rock** (decision 22) opens to one element, rolled for its room as the biome begins
##   (Flow's `_begin_locks`): that element touching the floor (`floor_touched`, queued by
##   `queue_touch` and applied at the next `step`, never in the middle of the shots' step) with its
##   circle within TOUCH_REACH of a door's mouth breaks the rock (`touched`), and the room opens.
## - **The view** is told each key door (`key_door_shown`), each rock (`secret_rock_shown`, with its
##   element) and each key (`key_shown`) as it changes; -1 when every one is forgotten (the biome left,
##   a restore: told again by `tell_all`). Never read back by the simulation.

const EventsScript := preload("res://core/events/events.gd")

## A room's rule (`rules`): none, a key door, a secret rock.
const RULE_NONE: int = 0
const RULE_KEY: int = 1
const RULE_SECRET: int = 2
## No room, no door, every one (the view's -1).
const NONE: int = -1
## A key's states (`key_states`): not dropped yet, lying on the floor, held by the party, spent.
const KEY_WAITING: int = 0
const KEY_LYING: int = 1
const KEY_HELD: int = 2
const KEY_SPENT: int = 3
## How near a wizard's feet must come to a key to take it, in pixels (a coin's reach).
const KEY_REACH: float = 10.0
## How far round a door's mouth its room's lip counts as at that door (as a gather door's).
const LIP_REACH: float = 24.0
## How near a floor touch's circle must come to a secret door's mouth to break its rock, in pixels.
const TOUCH_REACH: float = 8.0

## Not state: the bus (set by Flow) and each door's mouth in the world (laid from the map, `lay`).
const DERIVED: Array[StringName] = [&"events", &"_mouths"]

var events: EventsScript = null
## Each room's rule (RULE_*), by its number; 1 in `opened` once it opened; a secret room's element.
var rules: PackedByteArray = PackedByteArray()
var opened: PackedByteArray = PackedByteArray()
var elements: Array[StringName] = []
## Each door: the room it leads into, and the bridge (and which end of it) whose mouth it is.
var door_rooms: PackedInt32Array = PackedInt32Array()
var door_bridges: PackedInt32Array = PackedInt32Array()
var door_ends: PackedInt32Array = PackedInt32Array()
## Each key: the room it opens, the room it drops in, its state (KEY_*) and where it lies.
var key_rooms: PackedInt32Array = PackedInt32Array()
var key_drops: PackedInt32Array = PackedInt32Array()
var key_states: PackedByteArray = PackedByteArray()
var key_at: PackedVector2Array = PackedVector2Array()
## The floor touches heard since the last step (`queue_touch`), applied at the next (`step`), so a
## rock never opens in the middle of the shots' step: each one's element, place and radius.
var touch_elements: Array[StringName] = []
var touch_at: PackedVector2Array = PackedVector2Array()
var touch_radii: PackedFloat32Array = PackedFloat32Array()
var _mouths: Array[Rect2] = []


## A biome's locks begin (every door shut, no key dropped): `map`'s rooms, each with its rule of
## `room_rules` (RULE_*, by room) and a secret room's element of `room_elements`; a door at each mouth
## of a locked room, and a key for each key room, dropped in the room at the other end of its bridge.
## Laid into the grid by `lay`.
func begin(map: BiomeMap, room_rules: PackedByteArray, room_elements: Array[StringName]) -> void:
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
	for bridge in map.bridges():
		for end in 2:
			var room: int = map.end_room(bridge, end)
			if room < 0 or room >= count or rules[room] == RULE_NONE:
				continue
			door_rooms.append(room)
			door_bridges.append(bridge)
			door_ends.append(end)
			var other: int = map.end_room(bridge, 1 - end)
			var at_key: int = key_rooms.find(room)
			if rules[room] == RULE_KEY and at_key < 0:
				key_rooms.append(room)
				key_drops.append(other)
				key_states.append(KEY_WAITING)
				key_at.append(Vector2.ZERO)
			elif at_key >= 0 and other < map.depths.size() and key_drops[at_key] < map.depths.size() and map.depths[other] < map.depths[key_drops[at_key]]:
				# A key room with more than one bridge: its key drops in the shallowest room beside it,
				# the one on the way to it.
				key_drops[at_key] = other


## No biome: no door, no key (the view told every one is forgotten, when there was one).
func clear() -> void:
	var had: bool = not door_rooms.is_empty()
	rules.resize(0)
	opened.resize(0)
	elements.clear()
	door_rooms.resize(0)
	door_bridges.resize(0)
	door_ends.resize(0)
	key_rooms.resize(0)
	key_drops.resize(0)
	key_states.resize(0)
	key_at.resize(0)
	touch_elements.clear()
	touch_at.resize(0)
	touch_radii.resize(0)
	_mouths.clear()
	if had:
		_forget(false)


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


## The key that opens room `room` (NONE for none).
func key_of(room: int) -> int:
	return key_rooms.find(room)


## Lay the doors into `grid` from the biome laid in `world` (as the biome starts, and after a restore:
## the grid's layers are not state): each door's mouth found, shut while its room is not open.
func lay(world: BiomeWorld, grid: RoomGrid) -> void:
	_mouths.clear()
	for door in doors():
		_mouths.append(world.mouth_rect(door_bridges[door], door_ends[door]) if world != null else Rect2())
	if grid == null:
		return
	for door in doors():
		grid.shut_mouth(_mouths[door], not is_open(door_rooms[door]))


## Room `room` was cleared: each key still waiting to drop there lies at `at` (the view told).
func drop_keys(room: int, at: Vector2) -> void:
	for key in key_rooms.size():
		if key_drops[key] == room and key_states[key] == KEY_WAITING:
			key_states[key] = KEY_LYING
			key_at[key] = at
			_tell_key(key)


## One tick of the locks with `party` (the wizards, in seat order) and `life` the rooms' state
## (`rooms()` of them, whose bridges' places follow): each lying key the first standing wizard's feet
## reach is taken, then each shut key room whose key is held opens once a standing wizard is at one
## of its doors (the key spent); the floor touches queued since the last step break their rocks
## first. Returns the key room opened (NONE for none; one a tick).
func step(party: Array[Node2D], life: RoomLife, grid: RoomGrid) -> int:
	for at in touch_elements.size():
		touched(touch_elements[at], touch_at[at], touch_radii[at], grid)
	touch_elements.clear()
	touch_at.resize(0)
	touch_radii.resize(0)
	for key in key_rooms.size():
		if key_states[key] != KEY_LYING:
			continue
		for wizard: Node2D in party:
			var actor := wizard as Actor if is_instance_valid(wizard) else null
			if actor != null and not actor.is_downed() and actor.position.distance_squared_to(key_at[key]) <= KEY_REACH * KEY_REACH:
				key_states[key] = KEY_HELD
				_tell_key(key)
				break
	for door in doors():
		var room: int = door_rooms[door]
		var key: int = key_of(room)
		if rules[room] != RULE_KEY or is_open(room) or key < 0 or key_states[key] != KEY_HELD:
			continue
		var at_door: int = life.rooms() + door_bridges[door] if life != null else NONE
		for wizard: Node2D in party:
			var actor := wizard as Actor if is_instance_valid(wizard) else null
			if actor != null and not actor.is_downed() and (actor.room == at_door or (actor.room == room and mouth_of(door).grow(LIP_REACH).has_point(actor.position))):
				key_states[key] = KEY_SPENT
				open(room, grid)
				return room
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
## secret room of that element with a door's mouth within the circle's reach (TOUCH_REACH more)
## opens. Returns the first room opened (NONE for none).
func touched(element: StringName, at: Vector2, radius: float, grid: RoomGrid) -> int:
	var found: int = NONE
	for door in doors():
		var room: int = door_rooms[door]
		if rules[room] != RULE_SECRET or is_open(room) or elements[room] != element:
			continue
		var mouth: Rect2 = mouth_of(door)
		var nearest := Vector2(clampf(at.x, mouth.position.x, mouth.end.x), clampf(at.y, mouth.position.y, mouth.end.y))
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


## After a snapshot was restored: the view forgets every door, rock and key, to draw each as it
## stands when told again (`tell_all`, by Flow once the mouths are laid again, `lay`).
func rebuild_derived() -> void:
	_forget(true)


## Tell the view every door, rock and key as they stand now (the biome laid; after a restore).
func tell_all() -> void:
	for door in doors():
		_tell_door(door)
	for key in key_rooms.size():
		_tell_key(key)


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
		events.secret_rock_shown.emit(_view_number(door), mouth_of(door), elements[room], is_open(room))


func _tell_key(key: int) -> void:
	if events != null and key_states[key] != KEY_WAITING:
		events.key_shown.emit(key, key_at[key], key_states[key] == KEY_LYING)


## Every door, rock and key forgotten (NONE); `restored`: what is told next is drawn as it stands.
func _forget(restored: bool) -> void:
	if events == null:
		return
	events.key_door_shown.emit(NONE, Rect2(), restored)
	events.secret_rock_shown.emit(NONE, Rect2(), &"", restored)
	events.key_shown.emit(NONE, Vector2.ZERO, false)
