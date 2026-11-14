class_name PickupRule
extends RefCounted
## How a body picks things up (items I6, docs/milestones/items.md, "Picking up"): one small policy,
## apart from the bags (the Inventory) and the ground (the Items area), so it changes alone
## (owner, 2026-11-13: "the way to pickup items could be tweaked"). Walking over an item, holding a
## button, a longer reach: each is a change here only.
##
## - **Reach** (`in_reach`): an item lies within REACH of the body's feet.
## - **The one in reach** (`nearest`): the nearest of those, the lower number on a tie.
## - **What a take does** (`take`, `has_room`): a staff goes onto a free hand if there is one, else
##   into its bag; anything else into its bag; with no room nothing is taken.
##
## Plain arithmetic on the rows (`+ - *`, the same on every machine); it keeps nothing.

## How far from the feet an item can be taken, in pixels: about a body and a half.
const REACH: float = 24.0


## True when an item at `at` is in reach of feet at `feet`.
static func in_reach(feet: Vector2, at: Vector2) -> bool:
	return feet.distance_squared_to(at) <= REACH * REACH


## The index in `rows` of the item in reach of `feet`: the nearest, the lower number on a tie; -1
## for none.
static func nearest(rows: Array[GroundItem], feet: Vector2) -> int:
	var best: int = -1
	var best_distance: float = INF
	for at in rows.size():
		var row: GroundItem = rows[at]
		var distance: float = feet.distance_squared_to(row.at)
		if distance > REACH * REACH:
			continue
		if best < 0 or distance < best_distance or (distance == best_distance and row.number < rows[best].number):
			best = at
			best_distance = distance
	return best


## True when `inventory` has room for `stack`: a free hand for a staff, else room in its bag.
static func has_room(inventory: Inventory, stack: ItemStack) -> bool:
	if inventory == null or stack == null:
		return false
	if ItemKinds.can(stack.kind, ItemKinds.HAND) and inventory.free_hand() >= 0:
		return true
	return inventory.has_room(stack)


## Give `stack` to `inventory` as the class doc says. Returns false, and nothing changes, with no
## room.
static func take(inventory: Inventory, stack: ItemStack) -> bool:
	if not has_room(inventory, stack):
		return false
	if ItemKinds.can(stack.kind, ItemKinds.HAND):
		var hand: int = inventory.free_hand()
		if hand >= 0 and inventory.put_on_hand(stack, hand):
			return true
	return inventory.add(stack)
