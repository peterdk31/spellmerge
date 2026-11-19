class_name RoomSpawning
extends RefCounted
## How a room's enemies come in (enemy spawning EA5, docs/milestones/enemy-spawning.md, "Pacing"): the
## run's list for the room, split into groups by cost, the next group only when the room gets quiet
## (the owner, 2026-11-17: no timer). Pure rules, no nodes: Flow holds one, asks it each tick which id
## to stand next (`next`) and where (`spawn_for`), and stands it. Flow's state (all of it is saved in
## snapshots, so a restored room goes on from the same point of its groups).
##
## - **A group** takes ids from the front of the list until its cost reaches `group` (always one at
##   least, so an enemy that costs more than a group still comes); with `group` 0, the whole list.
## - **The first group** starts as the list is handed over (`begin`); **the next** only once the
##   current one has all started and the cost standing or spawning drops to `refill_at` or below.
## - **Its bodies** start `stagger` seconds apart (the first at once), so a group ripples in.
## - **Where:** a group's bodies take the spawns farthest from every standing wizard first (`rank`,
##   worked out as the group's first body stands), skipping a spawn over a hole and one within
##   `NEAR` of a wizard (a body never starts spawning on a player), round them in turn, stacked where
##   a spawn is used again within the group (`Flow.stacked_position`).

## Pixels from a standing wizard within which a spawn is not used (unless every spawn is that near:
## then the farthest alone).
const NEAR: float = 64.0

## The ids not yet called, in the run's order, and what each costs (`EnemyBase.cost`).
var waiting: Array[StringName] = []
var costs: PackedInt32Array = PackedInt32Array()
## Each waiting id's elite card (connected biomes CB11; empty: no elite), and the card of the id
## `next` gave last.
var cards: Array[StringName] = []
var card: StringName = &""
## The run's numbers for the room (`run_room_filled`): a group's cost (0: the whole list at once), the
## cost standing at or below which the next group comes, the seconds between two bodies of a group.
var group: int = 0
var refill_at: int = 0
var stagger: float = 0.0
## Seconds to the current group's next body, and how many of its bodies are still to start (0: no
## group under way).
var stagger_left: float = 0.0
var group_left: int = 0
## How many of the current group's bodies have been placed (`spawn_for`), and the room's spawns in the
## order the group takes them (`rank`, as its first body was placed).
var placed: int = 0
var order: PackedInt32Array = PackedInt32Array()


## The room's list `ids` (each costing `cost_of[i]`) comes in at the run's pace (`group`, `refill_at`,
## `stagger`): the first group starts now (its first body is the next `next` returns). `elite_cards`:
## each id's elite card by the same index (short or empty: none past its end).
func begin(ids: Array[StringName], cost_of: PackedInt32Array, group_cost: int, refill_cost: int, seconds_apart: float, elite_cards: Array[StringName] = []) -> void:
	clear()
	waiting = ids.duplicate()
	costs = cost_of.duplicate()
	for at in ids.size():
		cards.append(elite_cards[at] if at < elite_cards.size() else &"")
	group = maxi(group_cost, 0)
	refill_at = maxi(refill_cost, 0)
	stagger = seconds_apart if is_finite(seconds_apart) and seconds_apart > 0.0 else 0.0
	_start_group()


## The id to stand now, `delta` seconds on, with `standing_cost` of the room's enemies standing or
## spawning (Flow's count); &"" for none this time. Call it again with `delta` 0 until it gives &"":
## a group with no stagger stands all at once. Its elite card is `card` then.
func next(delta: float, standing_cost: int) -> StringName:
	if waiting.is_empty():
		group_left = 0
		return &""
	if group_left <= 0:
		if standing_cost > refill_at:
			return &""
		_start_group()
	stagger_left -= delta
	if stagger_left > 0.0:
		return &""
	stagger_left = stagger
	group_left -= 1
	costs.remove_at(0)
	card = cards.pop_front() if not cards.is_empty() else &""
	return waiting.pop_front()


## Every id still waiting, taken now (`Flow.stand_all_now`, for tests): the queue is empty after.
func take_all() -> Array[StringName]:
	var taken: Array[StringName] = waiting.duplicate()
	waiting.clear()
	costs.clear()
	cards.clear()
	group_left = 0
	return taken


## True when every id has been called.
func is_done() -> bool:
	return waiting.is_empty()


## How many ids are still to come.
func left() -> int:
	return waiting.size()


## Nothing to come (the room's enemies went).
func clear() -> void:
	waiting.clear()
	costs.clear()
	cards.clear()
	card = &""
	group = 0
	refill_at = 0
	stagger = 0.0
	stagger_left = 0.0
	group_left = 0
	placed = 0
	order.clear()


## Where the body being stood now stands, of `spawns` (the room's enemy spawns, never empty), with the
## standing wizards at `wizards`: the group's first body ranks the spawns (`rank`, with `touches_hole`
## saying which a body would stand over a hole on), and each body takes the next of them in turn,
## stacked where one is used again (`stack`, Flow's `stacked_position`).
func spawn_for(spawns: PackedVector2Array, wizards: PackedVector2Array, touches_hole: Callable, stack: Callable) -> Vector2:
	if placed == 0 or order.is_empty():
		order = rank(spawns, wizards, touches_hole)
	var nth: int = placed
	placed += 1
	var spawn: int = order[nth % order.size()]
	return stack.call(spawns[spawn], nth / order.size())


## The spawns of `spawns` by how far they are from the nearest of `wizards`, farthest first (ties by
## their index; with no wizards, in their order), leaving out those `touches_hole` (a spawn's place to
## true) says are over a hole, unless every one is, and those within `NEAR` of a wizard, unless every
## one left is (then the farthest alone). The same on every machine: places only.
static func rank(spawns: PackedVector2Array, wizards: PackedVector2Array, touches_hole: Callable) -> PackedInt32Array:
	var kept := PackedInt32Array()
	for i in spawns.size():
		if not touches_hole.is_valid() or not bool(touches_hole.call(spawns[i])):
			kept.append(i)
	if kept.is_empty():
		for i in spawns.size():
			kept.append(i)
	var gaps := PackedFloat64Array()
	gaps.resize(spawns.size())
	for i: int in kept:
		var gap: float = INF
		for wizard: Vector2 in wizards:
			gap = minf(gap, spawns[i].distance_squared_to(wizard))
		gaps[i] = gap
	# An insertion sort: a room has a handful of spawns, and it keeps ties in index order.
	for at in range(1, kept.size()):
		var spawn: int = kept[at]
		var back: int = at - 1
		while back >= 0 and gaps[kept[back]] < gaps[spawn]:
			kept[back + 1] = kept[back]
			back -= 1
		kept[back + 1] = spawn
	var far := PackedInt32Array()
	for spawn: int in kept:
		if gaps[spawn] > NEAR * NEAR:
			far.append(spawn)
	if far.is_empty():
		far.append(kept[0])
	return far


## The next group starts: as many ids from the front as reach `group` in cost (one at least; all with
## a group of 0), its first body at once, its spawns ranked again.
func _start_group() -> void:
	var count: int = 0
	var cost: int = 0
	while count < waiting.size() and (count == 0 or group <= 0 or cost < group):
		cost += costs[count] if count < costs.size() else 1
		count += 1
	group_left = count
	stagger_left = 0.0
	placed = 0
