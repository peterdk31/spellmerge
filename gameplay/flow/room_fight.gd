class_name RoomFight
extends RefCounted
## One room's fight in a biome (connected biomes CB3, docs/milestones/connected-biomes.md, "Room
## state"): what the run puts in it (enemy and boss ids, one a body), the pace they come in at (as
## `run_room_filled` tells it: a group's cost, the cost standing that calls the next, the
## seconds between a group's bodies; all 0: the whole list at once), its scale (told as `run_room_scaled` before its enemies stand, 0:
## the level as it is) and the queue of those still to come once it has started (`RoomSpawning`). State,
## Flow's room life's (`RoomLife.fights`), one a room; a room with no enemies has no fight and is
## cleared as it is entered.

var enemies: Array[StringName] = []
var group: int = 0
var refill_at: int = 0
var stagger: float = 0.0
var scale: float = 0.0
## Each enemy's elite card by the same index as `enemies` (connected biomes CB11; empty: no elite,
## a short list: none past its end).
var elites: Array[StringName] = []
var queue: RoomSpawning = RoomSpawning.new()


## A fight of `ids` (one a body), at the pace given and scaled by `room_scale` (0: unscaled), the
## elites' cards `elite_cards` by the same index.
static func of(ids: Array[StringName], group_cost: int = 0, refill_cost: int = 0, seconds_apart: float = 0.0, room_scale: float = 0.0, elite_cards: Array[StringName] = []) -> RoomFight:
	var fight := RoomFight.new()
	fight.enemies = ids.duplicate()
	fight.elites = elite_cards.duplicate()
	fight.group = group_cost
	fight.refill_at = refill_cost
	fight.stagger = seconds_apart
	fight.scale = room_scale
	return fight


## True when there is something to fight.
func has_enemies() -> bool:
	return not enemies.is_empty()


## A copy as it was given (its queue not begun), for a run started again.
func fresh() -> RoomFight:
	return of(enemies, group, refill_at, stagger, scale, elites)


## The elite card of the fight's enemy `at` (empty: no elite).
func elite_of(at: int) -> StringName:
	return elites[at] if at >= 0 and at < elites.size() else &""
