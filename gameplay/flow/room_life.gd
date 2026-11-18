class_name RoomLife
extends RefCounted
## A biome's room life (connected biomes CB3, docs/milestones/connected-biomes.md, "Room state" and
## "A room is awake"): Flow's state of each room of the biome laid (`BiomeWorld`), and the rules that
## read it. Pure rules on state; Flow stands the bodies and sends the events.
##
## **Each room** (by its number in the map) is, as play goes: ENTERED (a wizard's own body stepped
## onto it: `room_entered`), STARTED (its fight began as it was entered), SEALED (while its fight is
## under way: nothing inside leaves, a wizard outside still walks in; `RoomGrid.set_sealed`) and
## CLEARED (its fight is over, or it had none: `room_cleared`, once). Its fight (`RoomFight`: what
## stands in it, its pace, its scale and its queue) is the run's, given as the biome starts. What lies
## on its floor is the Items area's, which keeps it (a room never forgets); a shop's shelf, a
## fountain's pool and the party's map come with their kinds (CB9 to CB11).
##
## **Each place** (the rooms, then the bridges: the grid's places) is awake while anything acts in it
## (`wake`): a body no world prop is (a wizard, standing or downed, an enemy, a decoy, a familiar) that
## is not still, or a shot flying there. It wakes as soon as one is there and sleeps the tick after
## the last went; only the state decides it, so every machine sleeps and wakes it alike. A sleeping
## place's bodies are skipped (`Actors.asleep`: the Tick steps none of them, Combat counts none of
## their statuses down), so what keeps time there (a prop's timer, a burn on a barrel) waits until it
## wakes, as if no time had passed for it (tests/gameplay/flow/test_room_life.gd).
##
## **Who is where** is each body's own state (`Actor.room`, kept as it moves), made current here for
## every open body each tick (`wake`), so a body stood, put somewhere or never moving is right too.

const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

## A room's flags (`flags`).
const ENTERED: int = 1
const STARTED: int = 2
const SEALED: int = 4
const CLEARED: int = 8

## Not state: scratch reused each tick (the open ids, the places shots are in).
const DERIVED: Array[StringName] = [&"_ids", &"_shot_places"]

## Each room's flags, by its number.
var flags: PackedByteArray = PackedByteArray()
## Each room's fight (one a room).
var fights: Array[RoomFight] = []
## Each place's wakefulness (1 awake), the rooms' then the bridges'.
var awake: PackedByteArray = PackedByteArray()
var _ids: PackedInt32Array = PackedInt32Array()
var _shot_places: PackedByteArray = PackedByteArray()


## A biome's life begins: `rooms` rooms, each its fight of `room_fights` (a room past their end has
## none), and `places` places (rooms and bridges), all awake until the first `wake`.
func begin(rooms: int, places: int, room_fights: Array[RoomFight]) -> void:
	flags.resize(rooms)
	flags.fill(0)
	fights.clear()
	for room in rooms:
		fights.append(room_fights[room].fresh() if room < room_fights.size() and room_fights[room] != null else RoomFight.new())
	awake.resize(places)
	awake.fill(1)
	_ids.resize(ActorsScript.ACTORS)


## Nothing: no biome.
func clear() -> void:
	flags.resize(0)
	fights.clear()
	awake.resize(0)


## How many rooms there are (0: no biome).
func rooms() -> int:
	return flags.size()


## True when room `room` has `flag` (ENTERED, STARTED, SEALED, CLEARED).
func has(room: int, flag: int) -> bool:
	return room >= 0 and room < flags.size() and (flags[room] & flag) != 0


func set_flag(room: int, flag: int, on: bool) -> void:
	if room < 0 or room >= flags.size():
		return
	flags[room] = (flags[room] | flag) if on else (flags[room] & ~flag)


## True while place `place` is awake (a place out of the biome: always).
func is_awake(place: int) -> bool:
	return place < 0 or place >= awake.size() or awake[place] != 0


## The places told to the grid as sealed or not, as the rooms' flags say (as a fight starts and is
## cleared, and after a restore: the grid's seals are not state).
func tell_seals(grid: RoomGrid) -> void:
	for room in flags.size():
		grid.set_sealed(room, has(room, SEALED))


## One tick's waking (see the class doc): every open body's place made current (`Actor.find_room`),
## each place awake while a body that acts or a shot is in it, and every body of a sleeping place
## asleep in the actor table (`Actors.set_asleep`), the rest awake.
func wake(table: ActorsScript, projectiles: ProjectileManagerScript) -> void:
	if table == null or awake.is_empty():
		return
	awake.fill(0)
	var count: int = table.open_ids(_ids)
	for n in count:
		var body := table.node_of(_ids[n]) as Actor
		if body == null or not body.is_inside_tree():
			continue
		body.find_room()
		if body.room >= 0 and body.room < awake.size() and keeps_awake(body, table):
			awake[body.room] = 1
	if projectiles != null:
		projectiles.shot_places(projectiles.grid(), _shot_places)
		for place in mini(awake.size(), _shot_places.size()):
			if _shot_places[place] != 0:
				awake[place] = 1
	for n in count:
		var body := table.node_of(_ids[n]) as Actor
		var place: int = body.room if body != null else RoomGrid.NO_PLACE
		table.set_asleep(_ids[n], place >= 0 and place < awake.size() and awake[place] == 0)


## True when `body` keeps the place it is in awake: it acts (no world prop, not still, not dying).
static func keeps_awake(body: Actor, table: ActorsScript) -> bool:
	return not body.is_dying() and not table.is_still(body.id) and body.own_team() != ActorsScript.TEAM_WORLD
