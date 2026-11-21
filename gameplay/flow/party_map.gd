class_name PartyMap
extends RefCounted
## The party's map of a biome (connected biomes CB9, docs/milestones/connected-biomes.md, "Room
## state" and decision 28): which rooms the party has seen. Flow's state, hashed and snapshotted with
## the rest of its world, so every machine and a machine that joins mid-run (a restore) knows the same
## map; the view only draws it (Feel's dark over the unvisited rooms, the held Y map).
##
## **Each room** (by its number in the biome's map) is UNSEEN, SHOWN (on the map but never entered:
## within `reveal` bridges of a room entered) or ENTERED (a wizard's own body stepped onto it, as
## `RoomLife.ENTERED` says; Flow enters both together). A room never goes back.
##
## **Reveal** is the run stat `map_reveal` (`RunStats`, CB10): how many rooms past the entered ones the
## map shows, worked out from the run's own changes as the run begins (`run_stats_ruled`). The map is
## the party's, one for everyone, so a player's relics (none yet, decision 26) would raise it for the
## party when they come: the most of any player's.
##
## Pure rules on state; Flow tells the view (`rooms_seen`) as it changes and after a restore.

## A room's level on the map (`seen`).
const UNSEEN: int = 0
const SHOWN: int = 1
const ENTERED: int = 2

## Not state: scratch for the walk out from a room entered (the rooms to visit and their distance).
const DERIVED: Array[StringName] = [&"_queue", &"_distance"]

## Each room's level (UNSEEN, SHOWN, ENTERED), by its number.
var seen: PackedByteArray = PackedByteArray()
## How many bridges past a room entered the map shows (`map_reveal`).
var reveal: int = 0
var _queue: PackedInt32Array = PackedInt32Array()
var _distance: PackedInt32Array = PackedInt32Array()


## A biome's map begins: `rooms` rooms, none seen yet, `reveal_by` bridges shown past a room entered.
func begin(rooms: int, reveal_by: int) -> void:
	seen.resize(rooms)
	seen.fill(UNSEEN)
	reveal = maxi(reveal_by, 0)


## Nothing: no biome.
func clear() -> void:
	seen.resize(0)
	reveal = 0


## How many rooms it knows (0: no biome).
func rooms() -> int:
	return seen.size()


## Room `room`'s level (UNSEEN for a room it does not know).
func level_of(room: int) -> int:
	return seen[room] if room >= 0 and room < seen.size() else UNSEEN


## Room `room` of `map` is entered: ENTERED, and every room within `reveal` joins (bridges and runes,
## `BiomeMap.neighbours`) of it SHOWN if it was not seen (a secret room is still drawn only once
## found: Feel's map). True when anything changed.
func enter(room: int, map: BiomeMap) -> bool:
	if room < 0 or room >= seen.size():
		return false
	var changed: bool = seen[room] != ENTERED
	seen[room] = ENTERED
	if reveal <= 0 or map == null:
		return changed
	_distance.resize(seen.size())
	_distance.fill(-1)
	_distance[room] = 0
	_queue.resize(0)
	_queue.append(room)
	var head: int = 0
	while head < _queue.size():
		var at: int = _queue[head]
		head += 1
		if _distance[at] >= reveal:
			continue
		for other: int in map.neighbours(at):
			if other < 0 or other >= seen.size() or _distance[other] >= 0:
				continue
			_distance[other] = _distance[at] + 1
			_queue.append(other)
			if seen[other] == UNSEEN:
				seen[other] = SHOWN
				changed = true
	return changed
