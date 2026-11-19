class_name RoomFill
extends RefCounted
## What fills a map's fight room (run generation RG2 and enemy spawning EA4; `BiomeGenerator` and the
## run area): its enemies bought from a pool by a budget, and how they come in.


## Enemies of `pool` by chance (`dice`'s step `step`) until `budget` is spent: one of the whole pool
## first (a room always has a fight), then any the rest of the budget affords, until none does.
static func spend(pool: Array[EnemyBase], budget: int, dice: MapDice, step: int) -> Array[StringName]:
	var picked: Array[StringName] = []
	var left: int = budget
	var from: Array[EnemyBase] = pool
	while not from.is_empty():
		var enemy: EnemyBase = from[dice.below(step, from.size())]
		picked.append(enemy.id)
		left -= enemy.cost
		var affordable: Array[EnemyBase] = []
		for other: EnemyBase in pool:
			if other.cost <= left:
				affordable.append(other)
		from = affordable
	return picked


## How a room's enemies come in at its scaled budget `budget` (enemy spawning EA4): `spawning`'s
## shares of it, as costs: [group, refill_at, stagger]; with no `SpawnRules`, the whole list at once
## ([0, 0, 0.0]).
static func pace(spawning: SpawnRules, budget: int) -> Array:
	if spawning == null:
		return [0, 0, 0.0]
	return [spawning.group_cost(budget), spawning.refill_cost(budget), spawning.stagger]
