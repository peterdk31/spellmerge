class_name GroundSight
extends RefCounted
## What a body sees lying round it (items I9, docs/milestones/items.md, "I9"): the answer to
## `ground_looked`, which the Items area (gameplay/items) fills at once, so an area that wants to
## know what lies near (the AI) asks through the bus and never calls the Items area. Up to MOST
## items, the nearest first (the lower number on a tie), each its number on the ground, where it lies,
## whether it is in reach of the feet asked from (the pickup rule's reach) and its stack.
##
## The stacks are the ground's own: read them, never change them (a take is `actor_take_requested`).
## One is made once per asker and filled again at each look (`clear`, `add`), so a look allocates
## nothing. Scratch: whoever holds one lists it as DERIVED (core/sim/README.md); it is filled and read
## within one step.

## The most items one look holds.
const MOST: int = 8

## How many it holds now.
var count: int = 0
## By entry: the item's number on the ground, where it lies, 1 when it is in reach, and its stack.
var numbers: PackedInt32Array = PackedInt32Array()
var places: PackedVector2Array = PackedVector2Array()
var in_reach: PackedByteArray = PackedByteArray()
var stacks: Array[ItemStack] = []
## How far each entry is from the feet asked from, squared (the order they are kept in).
var _far: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	numbers.resize(MOST)
	places.resize(MOST)
	in_reach.resize(MOST)
	stacks.resize(MOST)
	_far.resize(MOST)


## Nothing seen.
func clear() -> void:
	for at in count:
		stacks[at] = null
	count = 0


## See the item `number` lying at `at` (`far_squared` from the feet asked from), `stack` it is,
## in reach or not: kept in order, nearest first (the lower number on a tie), the farthest let go
## once MOST are held.
func add(number: int, at: Vector2, far_squared: float, reachable: bool, stack: ItemStack) -> void:
	var place: int = count
	while place > 0 and (_far[place - 1] > far_squared or (_far[place - 1] == far_squared and numbers[place - 1] > number)):
		place -= 1
	if place >= MOST:
		return
	var last: int = mini(count, MOST - 1)
	var i: int = last
	while i > place:
		numbers[i] = numbers[i - 1]
		places[i] = places[i - 1]
		in_reach[i] = in_reach[i - 1]
		stacks[i] = stacks[i - 1]
		_far[i] = _far[i - 1]
		i -= 1
	numbers[place] = number
	places[place] = at
	in_reach[place] = 1 if reachable else 0
	stacks[place] = stack
	_far[place] = far_squared
	count = mini(count + 1, MOST)
