extends RefCounted
## The pick on the open Y map (the owner, 2026-11-19: "with the Y map open and not in a fight, the
## player can pick a cleared room on the map and teleport there alone"; and on 2026-11-20: "the D-pad
## moves the teleport cursor", the left stick no longer, so the wizard keeps walking while its player
## picks). The HUD's, one a seat, polled by `panels.gd`:
##
## - **What may be picked:** the rooms Flow says the seat's wizard may teleport to now and their
##   middles (`teleport_rooms_shown`; none while it is in a fight, down or driving another body).
## - **While the map is held** (`map` held, its input not captured by a menu: the map's own rule,
##   `party_map_view.gd`) and there is a room to go to, the pick is the room picked last if it still
##   may be, else the first; a press of a d-pad arm (`quick_*`, InputManager.QUICK_WAYS; 1-4 on the
##   keyboard) moves it to the nearest room that way (within CONE, 60 degrees either side, of its
##   middle's way from the picked one's); A (`take`) sends `map_teleport_requested(seat, room)` once a
##   press, and the map's A does nothing else. While the map is held the d-pad is the map's, never a
##   quick-use (`panels.gd`).
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
## How far off a flick's way a room may lie and still be its next (the cosine of the cone's half: 60°).
const CONE: float = 0.5

var events: EventsScript = null
## By seat: the rooms it may go to and their middles (world pixels), as told.
var _rooms: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
var _at: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
## By seat: the room picked (NONE: none) and the room picked last (kept while the map is shut).
var _pick: PackedInt32Array = PackedInt32Array([NONE, NONE, NONE, NONE])
var _last: PackedInt32Array = PackedInt32Array([NONE, NONE, NONE, NONE])


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


## True while seat `seat` may pick a room now (the map held with somewhere to go: `poll`'s last word).
func picking(seat: int) -> bool:
	return pick_of(seat) != NONE


## Seat `seat`'s poll: the map held or not (`held`), the way of a d-pad arm pressed since the last
## poll (`way`, Vector2.ZERO: none) and whether A was pressed since then (`take_now`). True when A
## was the map's (a teleport asked).
func poll(seat: int, held: bool, way: Vector2, take_now: bool) -> bool:
	if seat < 0 or seat >= SEATS:
		return false
	if not held or _rooms[seat].is_empty():
		_set_pick(seat, NONE)
		return false
	if _pick[seat] == NONE or not _rooms[seat].has(_pick[seat]):
		_set_pick(seat, _last[seat] if _rooms[seat].has(_last[seat]) else _rooms[seat][0])
	if way != Vector2.ZERO:
		_set_pick(seat, next_room(_rooms[seat], _at[seat], _pick[seat], way.normalized()))
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
