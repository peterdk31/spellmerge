class_name RewardOffer
extends RefCounted
## One player's reward not yet picked (connected biomes CB10): a row of the Rewards area
## (gameplay/rewards/rewards.gd). Its number (handed out once a run), whose it is, the room whose
## clear rolled it and whether the player's wizard was there (`here`), and its choices, one entry of
## each list a choice (an item: its kind, `ItemKinds.RULES`, its id and a count). State, walked and snapshotted member
## by member (core/sim/README.md); `new()` with no arguments makes a blank one.

## Its number (`reward_rolled`, `reward_pick_requested` name it).
var number: int = -1
## The seat it is for.
var seat: int = -1
## The room whose clear rolled it (`room_cleared`'s number).
var room: int = -1
## Whether the seat's wizard was in that room as it was cleared.
var here: bool = false
## Whether it lies as an item in that room (the owner's ask of 2026-11-19: a present player's reward
## is an item in the room's middle, opened with A at it), and where (world pixels). One that lies
## no more (the world went, or none was there) waits on the player's corner panel.
var lying: bool = false
var at: Vector2 = Vector2.ZERO
## The reward table it was rolled from (content/rewards; a reward reroll rolls from it again).
var table: StringName = &""
## The reward room's type it was rolled among (`RewardType.to_row`; empty: none), rolled among again
## by a reward reroll.
var type_row: PackedStringArray = PackedStringArray()
## Its choices: what each gives, the card's id (empty for coins) and how many.
var kinds: Array[StringName] = []
var ids: Array[StringName] = []
var counts: PackedInt32Array = PackedInt32Array()


## How many choices it offers.
func size() -> int:
	return kinds.size()


## True when it already offers a choice of `kind` `id` `count`.
func offers(kind: StringName, id: StringName, count: int) -> bool:
	for at in kinds.size():
		if kinds[at] == kind and ids[at] == id and counts[at] == count:
			return true
	return false


## Add a choice.
func add(kind: StringName, id: StringName, count: int) -> void:
	kinds.append(kind)
	ids.append(id)
	counts.append(count)
