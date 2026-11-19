class_name GatherDoors
extends RefCounted
## A biome's gather doors (connected biomes CB7, docs/milestones/connected-biomes.md, decisions 7, 23
## and 25): the doors that open only when the party is there together. Flow's state (it holds one, as
## it holds its `RoomLife`); pure rules on it. Flow moves the bodies and sends the room events.
##
## - **A gated room** is one whose kind has a door (`RoomKind.door`): DOOR_GATHER (a challenge room)
##   or DOOR_GATE (the boss's). Each mouth where a bridge meets it is one of its doors, shut
##   (`RoomGrid.shut_mouth`: a wall to everything, a wizard too) until the room opens.
## - **At a door** is on its bridge (a wizard's own body whose place, `Actor.room`, is that bridge's,
##   or the gated room's own while it is shut, beside that door's mouth: its lip outside the shut
##   mouth, where its place reaches),
##   counted where the wizard's own body stands, as the row run's exits are (a seat driving another
##   body holds the party until it comes back). **Standing** is not downed (one falling into a hole
##   stands: the party waits for its return).
## - **A gather door opens** when there is a standing wizard and every one is at it (`count_doors`).
##   **The gate** also stays shut (`held`) while any sealed fight holds a wizard, downed or standing
##   (decision 25). As a room opens (`open`), all its doors open: who comes in is Flow's (a gather
##   door's standing wizards, the gate's everyone, downed or far away, onto its player spawns).
## - **The portal home** (decision 7): a room whose kind has `RoomKind.portal_home` (the boss's),
##   cleared, opens a portal on its floor (`open_portal`); once every standing wizard stands in it,
##   the run is won and ends back in the hub (`count_portal`, Flow's).
## - **The view** is told each door as it changes (`gather_door_shown`: its rule, its area, who is
##   gathered of who stands, held, open), the portal after the doors; and door -1 when every door is
##   forgotten (the biome left, a restore: the doors are told again at the next count). Never read
##   back by the simulation.

const EventsScript := preload("res://core/events/events.gd")

## A room's rule (`rules`): none, a gather door, the gate.
const RULE_NONE: int = 0
const RULE_GATHER: int = 1
const RULE_GATE: int = 2
## No room (`count_doors`), no portal (`portal_room`), every door (`gather_door_shown`'s door -1).
const NONE: int = -1
## How far round a door's mouth its room's lip counts as at that door (a room's place reaches up to
## 16 px past its socket, CB2; and a wizard's half).
const LIP_REACH: float = 24.0
## The portal home's floor: a square this wide round its middle (as a room exit's area).
const PORTAL_SIZE: Vector2 = Vector2(48.0, 48.0)

## Not state: the bus (set by Flow), each door's mouth in the world (laid from the map, `lay`), and
## what the view was last told of each door (only drawn, so a game whose state a snapshot replaced
## tells it again).
const DERIVED: Array[StringName] = [&"events", &"_mouths", &"_shown"]

var events: EventsScript = null
## Each room's rule (RULE_*), by its number; 1 in `opened` once it opened; 1 in `homes` for a room
## that opens the portal home once cleared.
var rules: PackedByteArray = PackedByteArray()
var opened: PackedByteArray = PackedByteArray()
var homes: PackedByteArray = PackedByteArray()
## Each door: the room it leads into, and the bridge (and which end of it) whose mouth it is.
var door_rooms: PackedInt32Array = PackedInt32Array()
var door_bridges: PackedInt32Array = PackedInt32Array()
var door_ends: PackedInt32Array = PackedInt32Array()
## The portal home: the room it stands in (NONE: none yet) and its floor in the world.
var portal_room: int = NONE
var portal_area: Rect2 = Rect2()
var _mouths: Array[Rect2] = []
var _shown: PackedInt32Array = PackedInt32Array()


## A biome's doors begin (every door shut, no portal): `map`'s rooms, each with its rule of
## `room_rules` (RULE_*, by room) and its portal mark of `room_homes`; a door at each mouth of a gated
## room. Laid into the grid by `lay`.
func begin(map: BiomeMap, room_rules: PackedByteArray, room_homes: PackedByteArray) -> void:
	clear()
	var count: int = map.rooms() if map != null else 0
	rules = room_rules.duplicate()
	rules.resize(count)
	homes = room_homes.duplicate()
	homes.resize(count)
	opened.resize(count)
	opened.fill(0)
	if map == null:
		return
	for bridge in map.bridges():
		for end in 2:
			var room: int = map.end_room(bridge, end)
			if room >= 0 and room < count and rules[room] != RULE_NONE:
				door_rooms.append(room)
				door_bridges.append(bridge)
				door_ends.append(end)


## No biome: no door, no portal (the view told every door is forgotten, when it had one).
func clear() -> void:
	var had: bool = not door_rooms.is_empty() or portal_room != NONE
	rules.resize(0)
	opened.resize(0)
	homes.resize(0)
	door_rooms.resize(0)
	door_bridges.resize(0)
	door_ends.resize(0)
	portal_room = NONE
	portal_area = Rect2()
	_mouths.clear()
	_shown.resize(0)
	if had:
		_forget()


## How many doors there are (the portal not among them).
func doors() -> int:
	return door_rooms.size()


## The rule of room `room` (RULE_NONE out of the biome).
func rule_of(room: int) -> int:
	return rules[room] if room >= 0 and room < rules.size() else RULE_NONE


## True once room `room` opened (a room with no door: never shut, so yes).
func is_open(room: int) -> bool:
	return rule_of(room) == RULE_NONE or opened[room] != 0


## True when room `room` opens the portal home once cleared.
func opens_home(room: int) -> bool:
	return room >= 0 and room < homes.size() and homes[room] != 0


## The world rectangle of door `door`'s mouth (laid by `lay`; empty before).
func mouth_of(door: int) -> Rect2:
	return _mouths[door] if door >= 0 and door < _mouths.size() else Rect2()


## Lay the doors into `grid` from the biome laid in `world` (as the biome starts, and after a restore:
## the grid's layers are not state): each door's mouth found, shut while its room is not open, open
## once it is.
func lay(world: BiomeWorld, grid: RoomGrid) -> void:
	_mouths.clear()
	for door in doors():
		_mouths.append(world.mouth_rect(door_bridges[door], door_ends[door]) if world != null else Rect2())
	if grid == null:
		return
	for door in doors():
		grid.shut_mouth(_mouths[door], not is_open(door_rooms[door]))


## Count `party` (the wizards) at the doors of the rooms not yet open, `life` the rooms' state
## (`rooms()` of them, whose bridges' places follow), tell the view what changed, and return the room
## whose door every standing wizard is at, free to open (a gate not held), or NONE.
func count_doors(party: Array[Node2D], life: RoomLife) -> int:
	var standing: int = 0
	var held: bool = false
	for wizard: Node2D in party:
		var actor := wizard as Actor if is_instance_valid(wizard) else null
		if actor == null:
			continue
		if not actor.is_downed():
			standing += 1
		if life != null and life.has(actor.room, RoomLife.SEALED):
			held = true
	var found: int = NONE
	for door in doors():
		var room: int = door_rooms[door]
		var at_door: int = life.rooms() + door_bridges[door] if life != null else NONE
		var gathered: int = 0
		for wizard: Node2D in party:
			var actor := wizard as Actor if is_instance_valid(wizard) else null
			# On its bridge, or on the lip of its room outside the shut mouth (the room's place
			# reaches past its socket; nobody is further in before it opens).
			if actor != null and not actor.is_downed() and (actor.room == at_door or (actor.room == room and not is_open(room) and mouth_of(door).grow(LIP_REACH).has_point(actor.position))):
				gathered += 1
		var gate_held: bool = rules[room] == RULE_GATE and held
		if not is_open(room):
			if found == NONE and standing > 0 and gathered == standing and not gate_held:
				found = room
		_tell(door, _rule_name(rules[room]), mouth_of(door), gathered, standing, gate_held and not is_open(room), is_open(room))
	return found


## Room `room` opens: every door of it, in `grid` too, and the view told.
func open(room: int, grid: RoomGrid) -> void:
	if rule_of(room) == RULE_NONE:
		return
	opened[room] = 1
	for door in doors():
		if door_rooms[door] != room:
			continue
		if grid != null:
			grid.shut_mouth(mouth_of(door), false)
		var last: int = _shown[door] if door < _shown.size() else 0
		_tell(door, _rule_name(rules[room]), mouth_of(door), maxi(last, 0) & 15, (maxi(last, 0) >> 4) & 15, false, true)


## The portal home opens in room `room`, its floor centred on `middle` (once: a second is ignored).
func open_portal(room: int, middle: Vector2) -> void:
	if portal_room != NONE:
		return
	portal_room = room
	portal_area = Rect2(middle - PORTAL_SIZE * 0.5, PORTAL_SIZE)


## True while the portal home stands, a standing wizard is there and every one stands in it (where
## its own body is): the run is won. The view is told who is gathered.
func count_portal(party: Array[Node2D]) -> bool:
	if portal_room == NONE:
		return false
	var standing: int = 0
	var gathered: int = 0
	for wizard: Node2D in party:
		var actor := wizard as Actor if is_instance_valid(wizard) else null
		if actor == null or actor.is_downed():
			continue
		standing += 1
		if portal_area.has_point(actor.position):
			gathered += 1
	_tell(doors(), RoomKind.DOOR_PORTAL_HOME, portal_area, gathered, standing, false, true)
	return standing > 0 and gathered == standing


## After a snapshot was restored: the view forgets every door, to draw each as it stands when told it
## again (`tell_all`, by Flow once the mouths are laid again, `lay`).
func rebuild_derived() -> void:
	_shown.resize(0)
	_forget(true)


## Tell the view every door and the portal as they stand now, opening nothing (after a restore, which
## may stand still for a while: a boss's intro, a pause).
func tell_all(party: Array[Node2D], life: RoomLife) -> void:
	count_doors(party, life)
	count_portal(party)


static func _rule_name(rule: int) -> StringName:
	match rule:
		RULE_GATHER:
			return RoomKind.DOOR_GATHER
		RULE_GATE:
			return RoomKind.DOOR_GATE
	return RoomKind.DOOR_NONE


## Door `door` told to the view, when it differs from what it was last told.
func _tell(door: int, rule: StringName, area: Rect2, gathered: int, standing: int, held: bool, is_opened: bool) -> void:
	var key: int = mini(gathered, 15) | (mini(standing, 15) << 4) | ((1 if held else 0) << 8) | ((1 if is_opened else 0) << 9)
	if _shown.size() <= door:
		var from: int = _shown.size()
		_shown.resize(door + 1)
		for at in range(from, door + 1):
			_shown[at] = -1
	if _shown[door] == key:
		return
	_shown[door] = key
	if events != null:
		events.gather_door_shown.emit(door, rule, area, gathered, standing, held, is_opened)


## Every door forgotten (door NONE); `restored`: what is told next is drawn as it stands (`open` true).
func _forget(restored: bool = false) -> void:
	if events != null:
		events.gather_door_shown.emit(NONE, &"", Rect2(), 0, 0, false, restored)
