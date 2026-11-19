extends RefCounted
## Each room kind's air motes (connected biomes CB12b, docs/milestones/connected-biomes.md): what a
## kind names to drift in its rooms' air (`RoomKind.air_motes`, a `MoteSource`), besides the room's
## own (`RoomBase.air`, gameplay/feel/air_motes.gd). Every room of a biome whose kind names air motes
## gives them off over its own place alone (the grid's place rectangle: a room's slab, 32 px clear
## of every other), within the part of the world in view (`AirMotes.area_of`), so a fountain's
## glimmer never drifts out over its bridge or the fight beside it. Each room is an `AirMotes` of its
## own (its colours rows of the ramp table, its owed motes), made as the biome is laid, never in a
## frame.
##
## **Within the motes' limits:** together they hold at most SHARE of the motes' ring at once, split
## evenly between the rooms near the view; the pool's density (the "Particles" setting, CB6's split
## budget's rungs) thins them as every mote. View only: nothing in the game reads it; it knows the
## rooms only by the grid's places and Feel's room hearing (`kind_of`, `is_walkway`), and the motes
## only by their pool.

const AirMotesScript := preload("res://gameplay/feel/air_motes.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")
const RoomHearingScript := preload("res://gameplay/feel/room_hearing.gd")

## The most of the motes' ring every kind's air together may hold at once: half the room's air's.
const SHARE: float = AirMotesScript.RING_SHARE * 0.5

## The pieces (Feel's room hearing: each place's kind, which places are walkways).
var pieces: RoomHearingScript = null
var _table: RampTableScript = null
## By room with air motes: its air, its place on the grid and its rectangle.
var _airs: Array[AirMotesScript] = []
var _places: PackedInt32Array = PackedInt32Array()
var _rects: Array[Rect2] = []
var _laid_places: int = -1
var _laid_world: int = -1


## Air whose colours are rows of `table` (the spectacle's, shared with the motes).
func _init(table: RampTableScript) -> void:
	_table = table


## Once a frame, from `grid` (null: no places): the rooms read again for a new biome (a new world,
## a restore's), each room whose kind names air motes made an air of its own.
func lay(grid: RoomGrid) -> void:
	var places: int = grid.places() if grid != null else 0
	var world: int = pieces.world() if pieces != null else 0
	if places == _laid_places and world == _laid_world:
		return
	_laid_places = places
	_laid_world = world
	_airs.clear()
	_places.resize(0)
	_rects.clear()
	if pieces == null:
		return
	for place in places:
		if pieces.is_walkway(place):
			continue
		var kind: RoomKind = pieces.kind_of(place)
		if kind == null or kind.air_motes == null:
			continue
		var air := AirMotesScript.new(_table)
		air.use(kind.air_motes)
		if air.look == null:
			continue
		_airs.append(air)
		_places.append(place)
		_rects.append(grid.place_rect(place))


## Give off every room's motes owed since the last call, at Feel's clock `now`, into `pool` (null:
## none: the particles, the light or the ambient particles are off), each over its own room within
## `view` (the world's part on screen; empty: all of each room).
func give_off(now: float, pool: MotesScript, view: Rect2) -> void:
	var near: int = 0
	for i in _airs.size():
		if AirMotesScript.area_of(view, _rects[i]).has_area():
			near += 1
	var share: float = SHARE / float(maxi(near, 1))
	for i in _airs.size():
		_airs[i].give_off(now, pool, view, _rects[i], share)


## The rooms with air motes, and room `i`'s place, rectangle and air (for tests).
func rooms() -> int:
	return _airs.size()


func place_of(i: int) -> int:
	return _places[i]


func rect_of(i: int) -> Rect2:
	return _rects[i]


func air_of(i: int) -> AirMotesScript:
	return _airs[i]
