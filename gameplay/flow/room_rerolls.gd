class_name RoomRerolls
extends RefCounted
## Room rerolls (the owner, 2026-11-19: "at an unvisited room's bridge mouth (where its kind sign
## shows), pressing X spends one room reroll and rerolls what lies behind that doorway"): Flow's, as
## its doors are (`LockDoors`). Which doorway a body may reroll at, the count of rerolls the run has
## made (the counter of the run's chance for the next one) and the hint each seat is told.
##
## - **A doorway to reroll** (`doorway_of`): the standing body is on a bridge (its place, a bridge's),
##   within REACH of a mouth of it (its middle) into a room that is not the start room, that no wizard
##   has entered (`RoomLife.ENTERED`) and that is neither started nor sealed, whose kind shows a sign
##   (`RoomKind.symbol`: the secret rooms tell nothing, so none of them is rerolled), and that is not
##   the boss's (the owner, 2026-11-19: "any unvisited room except the boss room"; its doorway
##   refuses: no hint, and X does nothing there). The first such mouth, bridge by bridge.
## - **The hint** (`tell`): each seat whose body stands at one is told so as it changes
##   (`room_reroll_shown`, view only), and told none as the biome goes and after a restore.
## - **State:** `rolls` (hashed and snapshotted with Flow); the hints are this machine's (DERIVED).
##
## What a reroll makes is the Run area's (`BiomeGenerator.reroll_room`); laying it is Flow's.

const NONE: int = -1
const SEATS: int = 4
## How near a mouth's middle a body on its bridge must stand, in pixels (about the sign's reach on a
## short bridge's end; a symbol stands GAP beside the mouth, `mouth_symbols.gd`).
const REACH: float = 48.0

const DERIVED: Array[StringName] = [&"events", &"_shown"]

var events: Node = null
## The room rerolls made this run (asked of the Run area: the next one's counter).
var rolls: int = 0
## By seat: the doorway its hint was last told for (bridge * 2 + end; NONE: none).
var _shown: PackedInt32Array = PackedInt32Array([NONE, NONE, NONE, NONE])


## A run's start or a biome left: no rerolls made, no hint shown (said).
func clear() -> void:
	rolls = 0
	forget()


## Every hint forgotten and said gone (the biome left, a snapshot restored).
func forget() -> void:
	_shown.fill(NONE)
	if events != null:
		for seat in SEATS:
			events.room_reroll_shown.emit(seat, Vector2.ZERO, false)


## The doorway `body` may reroll at, as `Vector2i(bridge, end)`, or `Vector2i(NONE, NONE)` (see the
## class doc). `kind_of` gives a room's `RoomKind` (null for none).
static func doorway_of(body: Node2D, biome: BiomeWorld, life: RoomLife, kind_of: Callable) -> Vector2i:
	var actor := body as Actor if is_instance_valid(body) else null
	var map: BiomeMap = biome.map if biome != null else null
	if actor == null or actor.is_downed() or map == null or life == null:
		return Vector2i(NONE, NONE)
	var bridge: int = actor.room - life.rooms()
	if bridge < 0 or bridge >= map.bridges():
		return Vector2i(NONE, NONE)
	for end in 2:
		var room: int = map.end_room(bridge, end)
		if room <= 0 or room >= life.rooms():
			continue
		if life.has(room, RoomLife.ENTERED) or life.has(room, RoomLife.STARTED) or life.has(room, RoomLife.SEALED):
			continue
		var kind: RoomKind = kind_of.call(room) as RoomKind
		if kind == null or kind.symbol_pixels().is_empty() or kind.fill == RoomKind.FILL_BOSS:
			continue
		if actor.position.distance_to(biome.mouth_rect(bridge, end).get_center()) <= REACH:
			return Vector2i(bridge, end)
	return Vector2i(NONE, NONE)


## Tell each seat whether the body it drives (`bodies`, by seat) stands at a doorway to reroll.
func tell(bodies: Array[Node2D], biome: BiomeWorld, life: RoomLife, kind_of: Callable) -> void:
	for seat in mini(bodies.size(), SEATS):
		var door: Vector2i = doorway_of(bodies[seat], biome, life, kind_of)
		var number: int = door.x * 2 + door.y if door.x != NONE else NONE
		if number == _shown[seat]:
			continue
		_shown[seat] = number
		if events != null:
			var at: Vector2 = biome.mouth_rect(door.x, door.y).get_center() if door.x != NONE else Vector2.ZERO
			events.room_reroll_shown.emit(seat, at, door.x != NONE)
