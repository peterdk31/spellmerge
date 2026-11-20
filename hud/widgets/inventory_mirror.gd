extends RefCounted
## What the HUD knows of one player's inventory (items I7): a mirror of what the seat's events say,
## and nothing else. The inventory menu (`hud/menus/inventory/`) and the radial builder
## (`hud/builder/`, items I7b) each keep one, filled by the same events, so the two menus read the
## seat's inventory through one set of rules, and a test can fill one by hand.
##
## - **Bags** (`bag_changed`): each bag's stack ids with their copies and its capacity
##   (`copies`, `capacity`, `fill_text`: "2/4", or "2/∞" with no limit; `count_of`, `ids_in`).
## - **Staffs** (`owned_staff_changed`): every staff owned by its number, its plain view
##   (`plan_of`, `base_of`), and **hands** (`hands_changed`): which number is on which hand
##   (`hand_of`). `staffs()` is the menu's order: the hands' by button, then the rest by number.
##
##     mirror.hear_bag(bag, ids, counts, capacity)
##     mirror.hear_staff(number, plan)        # an empty plan: no longer owned
##     mirror.hear_hands(hands)
##
## - **Quick-use slots** (`quick_bound`; the owner, 2026-11-20): what each d-pad arm is bound to
##   (`quick_slot_of(bag, id)`, `quick_id`).
## - **The body** (`inventory_announced`, items I8): the key of the body all this is of (`body`),
##   which the menus send with their requests so the seat refuses one for a body it no longer shows.

const NONE: int = -1
const HANDS: int = 4
## What `fill_text` writes for a bag with no limit.
const NO_LIMIT: String = "∞"

## By bag: {"ids": Array[StringName], "counts": PackedInt32Array, "capacity": int}.
var _bags: Dictionary = {}
## By staff number: its plain view (`Spells.staff_view`, with its `StaffBase` under "staff").
var _plans: Dictionary = {}
## By hand (button): the number on it, NONE for none.
var _hands: PackedInt32Array = PackedInt32Array([NONE, NONE, NONE, NONE])
## By quick-use slot (0 up, 1 right, 2 down, 3 left): the bag and the id bound (`&""`: none).
var _quick_bags: Array[StringName] = [&"", &"", &"", &""]
var _quick_ids: Array[StringName] = [&"", &"", &"", &""]
## The key of the body it mirrors (`Actor.key`, from `inventory_announced`; 0 before any).
var body: int = 0


## Bag `bag` holds `ids` with `counts` copies each and has room for `capacity` copies (-1: no limit).
func hear_bag(bag: StringName, ids: Array[StringName], counts: PackedInt32Array, capacity: int) -> void:
	_bags[bag] = {"ids": ids.duplicate(), "counts": counts.duplicate(), "capacity": capacity}


## Staff `number` is as `plan` says, or (an empty plan) is no longer owned.
func hear_staff(number: int, plan: Dictionary) -> void:
	if plan.is_empty():
		_plans.erase(number)
	else:
		_plans[number] = plan.duplicate(true)


## By hand (button): the number of the staff on it, -1 for none.
func hear_hands(hands: PackedInt32Array) -> void:
	for hand in HANDS:
		_hands[hand] = hands[hand] if hand < hands.size() else NONE


## Quick-use slot `slot` is bound to `id` of `bag` (`&""`: nothing).
func hear_quick(slot: int, bag: StringName, id: StringName) -> void:
	if slot >= 0 and slot < _quick_ids.size():
		_quick_bags[slot] = bag
		_quick_ids[slot] = id


## The quick-use slot `id` of `bag` is bound to, NONE for none.
func quick_slot_of(bag: StringName, id: StringName) -> int:
	for slot in _quick_ids.size():
		if id != &"" and _quick_ids[slot] == id and _quick_bags[slot] == bag:
			return slot
	return NONE


## The id quick-use slot `slot` is bound to (`&""`: none).
func quick_id(slot: int) -> StringName:
	return _quick_ids[slot] if slot >= 0 and slot < _quick_ids.size() else &""


## Forget everything (a run ended: its wizard is gone), and mirror the body `of` from now on.
func clear(of: int = 0) -> void:
	body = of
	_bags.clear()
	_plans.clear()
	_hands.fill(NONE)
	_quick_bags.fill(&"")
	_quick_ids.fill(&"")


# --- Bags -------------------------------------------------------------------------------

## How many copies bag `bag` holds.
func copies(bag: StringName) -> int:
	var total: int = 0
	for count in _bag(bag)["counts"]:
		total += count
	return total


## The capacity of bag `bag` in copies, -1 for no limit.
func capacity(bag: StringName) -> int:
	return int(_bag(bag)["capacity"])


## How full bag `bag` is, as shown: "2/4", or "2/∞" with no limit.
func fill_text(bag: StringName) -> String:
	var most: int = capacity(bag)
	return "%d/%s" % [copies(bag), NO_LIMIT if most < 0 else str(most)]


## The ids bag `bag` holds, each once, in the order they came.
func ids_in(bag: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _bag(bag)["ids"]:
		if not out.has(id):
			out.append(id)
	return out


## How many copies of `id` bag `bag` holds.
func count_of(bag: StringName, id: StringName) -> int:
	var data: Dictionary = _bag(bag)
	var ids: Array = data["ids"]
	var counts: PackedInt32Array = data["counts"]
	var total: int = 0
	for at in mini(ids.size(), counts.size()):
		if ids[at] == id:
			total += counts[at]
	return total


# --- Staffs and hands -------------------------------------------------------------------

## Every staff owned: the hands' by button, then the rest by number.
func staffs() -> PackedInt32Array:
	var out := PackedInt32Array()
	for number in _hands:
		if number != NONE and _plans.has(number):
			out.append(number)
	var rest: Array[int] = []
	for number: int in _plans:
		if not out.has(number):
			rest.append(number)
	rest.sort()
	for number in rest:
		out.append(number)
	return out


## The hand (button) staff `number` is on, or NONE.
func hand_of(number: int) -> int:
	return _hands.find(number) if number != NONE else NONE


## The number of the staff on hand `hand`, or NONE.
func on_hand(hand: int) -> int:
	return _hands[hand] if hand >= 0 and hand < HANDS else NONE


## Staff `number`'s plain view, or {} for one not owned.
func plan_of(number: int) -> Dictionary:
	return _plans.get(number, {}) as Dictionary


## Staff `number`'s `StaffBase`, or null for one not owned.
func base_of(number: int) -> StaffBase:
	return plan_of(number).get("staff") as StaffBase


## Staff `number`'s cards by slot (`&""` for an empty slot).
func cards_of(number: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in plan_of(number).get("cards", []):
		out.append(StringName(id))
	return out


func _bag(bag: StringName) -> Dictionary:
	if _bags.has(bag):
		return _bags[bag]
	return {"ids": [], "counts": PackedInt32Array(), "capacity": -1}
