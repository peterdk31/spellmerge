class_name ItemStack
extends RefCounted
## A stack (items I3, docs/milestones/items.md, "The model"): anything held or, later, lying on the
## ground. A kind (`ItemKinds`), an id (the content's own: `bolt` under the spells, `curl` under the
## wizard's staffs) and a count; for a staff also its `number` in its inventory, the staff itself
## (`staff`), its cards by slot and the mana it keeps while it is on no hand.
##
## State, as any object a simulation script holds (core/sim/README.md): every member is walked and
## snapshotted, and `new()` with no arguments makes a blank one.
##
##     var cards := ItemStack.card(&"bolt", 20)
##     var staff := ItemStack.of_staff(curl, [&"bolt"] as Array[StringName])

## A stack no inventory has numbered.
const NO_NUMBER: int = -1

## Its kind (a row of `ItemKinds.RULES`) and its id.
var kind: StringName = &""
var id: StringName = &""
## How many copies: 1 for a kind that does not stack.
var count: int = 1
## A staff's number in its inventory (stable while it is there: the builder and the hands name it),
## NO_NUMBER for anything else.
var number: int = NO_NUMBER
## A staff's staff (content, never changed), its cards by slot (`&""` an empty slot, exactly
## `staff.slots` long) and the mana it keeps while on no hand (on a hand its pool is the Caster's).
var staff: StaffBase = null
var cards: Array[StringName] = []
var mana: float = 0.0


## `count` copies of the card `card_id`.
static func card(card_id: StringName, copies: int = 1) -> ItemStack:
	var made := ItemStack.new()
	made.kind = ItemKinds.CARD
	made.id = card_id
	made.count = copies
	return made


## The staff `base` holding `with_cards` (cut or padded to its slots), its pool full.
static func of_staff(base: StaffBase, with_cards: Array[StringName] = []) -> ItemStack:
	var made := ItemStack.new()
	made.kind = ItemKinds.STAFF
	made.staff = base
	made.id = base.id if base != null else &""
	made.cards = made.fit(with_cards)
	made.mana = base.max_mana if base != null else 0.0
	return made


## How many slots it has (a staff's; 0 for anything else).
func slots() -> int:
	return staff.slots if staff != null else 0


## `row` cut or padded with empty slots to exactly `slots()` (a copy).
func fit(row: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for slot in slots():
		out.append(row[slot] if slot < row.size() else &"")
	return out


## How many of the card `card_id` its cards hold.
func holds_card(card_id: StringName) -> int:
	return cards.count(card_id)


## A copy of it (its cards too; the staff is content, shared).
func copy() -> ItemStack:
	var made := ItemStack.new()
	made.kind = kind
	made.id = id
	made.count = count
	made.number = number
	made.staff = staff
	made.cards = cards.duplicate()
	made.mana = mana
	return made
