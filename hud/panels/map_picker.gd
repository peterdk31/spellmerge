extends RefCounted
## The pick on the open Y map (the owner, 2026-11-19: "with the Y map open and not in a fight, the
## player can pick a cleared room on the map and teleport there alone. Pick with the stick/D-pad and
## A on the open map"). The HUD's, one a seat, polled by `panels.gd`:
##
## - **What may be picked:** the rooms Flow says the seat's wizard may teleport to now and their
##   middles (`teleport_rooms_shown`; none while it is in a fight, down or driving another body).
## - **While the map is held** (`map` held, its input not captured by a menu: the map's own rule,
##   `party_map_view.gd`) and there is a room to go to, the pick is the room picked last if it still
##   may be, else the first; a flick of the stick or the D-pad (`menu_move` past FLICK from below
##   REST) moves it to the nearest room that way (within a half turn's cone, CONE, its middle's way
##   from the picked one's), so the wizard keeps walking while its player picks; A (`take`) sends
##   `map_teleport_requested(seat, room)` once a press, and the map's A does nothing else.
## - **Told to the view** (`map_pick_changed`, Feel draws it on that seat's map) as it changes, -1 as
##   the map is let go or nothing may be picked.
##
## View only: the pick is this machine's, never the simulation's; the teleport is a command.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")

const SEATS: int = 4
const NONE: int = -1
## The map's action (project.godot: Y, M on the keyboard): the same as the map view's.
const MAP_ACTION: StringName = &"map"
## A flick: the stick past FLICK, from below REST.
const FLICK: float = 0.6
const REST: float = 0.3
## How far off a flick's way a room may lie and still be its next (the cosine of the cone's half).
const CONE: float = 0.5

var events: EventsScript = null
## By seat: the rooms it may go to and their middles (world pixels), as told.
var _rooms: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
var _at: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
## By seat: the room picked (NONE: none), the room picked last (kept while the map is shut), and
## whether its stick was at rest since its last flick.
var _pick: PackedInt32Array = PackedInt32Array([NONE, NONE, NONE, NONE])
var _last: PackedInt32Array = PackedInt32Array([NONE, NONE, NONE, NONE])
var _rested: Array[bool] = [true, true, true, true]


func bind(bus: EventsScript) -> void:
	events = bus
	if events != null:
		events.teleport_rooms_shown.connect(_on_teleport_rooms_shown)


## The room seat `seat` has picked (NONE: none).
func pick_of(seat: int) -> int:
	return _pick[seat] if seat >= 0 and seat < SEATS else NONE


## True while seat `seat` holds the open map (its A is the map's, never the room's).
func holds(seat: int, input: InputManagerScript) -> bool:
	return input != null and input.is_joined(seat) and not input.is_captured(seat) and input.is_held(seat, MAP_ACTION)


## Seat `seat`'s poll: the map held or not (`held`), its stick (`move`) and whether A was pressed
## since the last poll (`take_now`). True when A was the map's (a teleport asked).
func poll(seat: int, held: bool, move: Vector2, take_now: bool) -> bool:
	if seat < 0 or seat >= SEATS:
		return false
	if not held or _rooms[seat].is_empty():
		_set_pick(seat, NONE)
		_rested[seat] = true
		return false
	if _pick[seat] == NONE or not _rooms[seat].has(_pick[seat]):
		_set_pick(seat, _last[seat] if _rooms[seat].has(_last[seat]) else _rooms[seat][0])
	var length: float = move.length()
	if length < REST:
		_rested[seat] = true
	elif length >= FLICK and _rested[seat]:
		_rested[seat] = false
		_set_pick(seat, next_room(_rooms[seat], _at[seat], _pick[seat], move / length))
	if take_now and events != null:
		events.map_teleport_requested.emit(seat, _pick[seat])
		return true
	return false


## The room of `rooms` (middles `at`) nearest `from` within CONE of the way `way`, or `from` when
## none lies that way.
static func next_room(rooms: PackedInt32Array, at: PackedVector2Array, from: int, way: Vector2) -> int:
	var here: int = rooms.find(from)
	if here < 0:
		return from
	var best: int = from
	var best_distance: float = INF
	for at_room in rooms.size():
		if at_room == here:
			continue
		var offset: Vector2 = at[at_room] - at[here]
		var distance: float = offset.length()
		if distance <= 0.0 or offset.dot(way) / distance < CONE:
			continue
		if distance < best_distance:
			best_distance = distance
			best = rooms[at_room]
	return best


## Nothing picked for any seat (the HUD's room left).
func clear() -> void:
	for seat in SEATS:
		_rooms[seat] = PackedInt32Array()
		_at[seat] = PackedVector2Array()
		_set_pick(seat, NONE)
		_last[seat] = NONE


func _set_pick(seat: int, room: int) -> void:
	if room == _pick[seat]:
		return
	_pick[seat] = room
	if room != NONE:
		_last[seat] = room
	if events != null:
		events.map_pick_changed.emit(seat, room)


func _on_teleport_rooms_shown(seat: int, rooms: PackedInt32Array, at: PackedVector2Array) -> void:
	if seat < 0 or seat >= SEATS:
		return
	_rooms[seat] = rooms
	_at[seat] = at
