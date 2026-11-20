class_name ItemStack
extends RefCounted
## A stack (items I3, docs/milestones/items.md, "The model"): anything held or, later, lying on the
## ground. A kind (`ItemKinds`), an id (the content's own: `bolt` under the spells, `curl` under the
## wizard's staffs) and a count; for a staff also its `number` in its inventory, the staff itself
## (`staff`), its cards by slot and the mana it keeps while it is on no hand; and, for an item whose
## use is kept (an active relic), how long it still recharges (`recharge_left`).
##
## **The recharge travels with the item** (the owner, 2026-11-20): it is the stack's own, never its
## holder's. Whoever holds it counts it down with the simulation's delta (an inventory's `step`, the
## ground's: gameplay/items), so a relic dropped mid-recharge keeps recharging where it lies and
## whoever takes it takes it mid-recharge. A loadout carries none (a run's start begins ready); a
## rejoin gives it back (Flow's `LeftPlayers`).
##
## State, as any object a simulation script holds (core/sim/README.md): every member is walked and
## snapshotted, and `new()` with no arguments makes a blank one.
##
##     var cards := ItemStack.card(&"bolt", 20)
##     var staff := ItemStack.of_staff(curl, [&"bolt"] as Array[StringName])

## A stack no inventory has numbered.
const NO_NUMBER: int = -1
## How finely a recharge is told (`step_recharge`): at each sixteenth of its cooldown, so the HUD
## shows the simulation's own count (16 rows on the inventory's ring, 8 on the cross) and never keeps
## a clock of its own.
const RECHARGE_STEPS: int = 16

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
## Seconds before its use can be used again (0: ready), and the whole cooldown it recharges for
## (0: not recharging): `start_recharge`, `step_recharge`.
var recharge_left: float = 0.0
var recharge_whole: float = 0.0


## `copies` of the item `of_kind` `of_id` (a kind that stacks: one stack of them; a staff: use
## `of_staff`).
static func of(of_kind: StringName, of_id: StringName, copies: int = 1) -> ItemStack:
	var made := ItemStack.new()
	made.kind = of_kind
	made.id = of_id
	made.count = copies
	return made


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
	made.recharge_left = recharge_left
	made.recharge_whole = recharge_whole
	return made


# --- Recharging -------------------------------------------------------------------------

## It recharges for `seconds` (its use's cooldown; nothing for 0 or less).
func start_recharge(seconds: float) -> void:
	if seconds <= 0.0:
		return
	recharge_left = seconds
	recharge_whole = seconds


## True while it recharges.
func is_recharging() -> bool:
	return recharge_left > 0.0


## Count its recharge down by `delta` (the simulation's). True when the step told changed
## (`recharge_step`): a sixteenth passed, or it is ready again.
func step_recharge(delta: float) -> bool:
	if recharge_left <= 0.0:
		return false
	var before: int = recharge_step()
	recharge_left -= delta
	if recharge_left <= 0.0:
		recharge_left = 0.0
		recharge_whole = 0.0
		return true
	return recharge_step() != before


## Which of RECHARGE_STEPS steps of its cooldown are left (0: ready).
func recharge_step() -> int:
	if recharge_whole <= 0.0 or recharge_left <= 0.0:
		return 0
	return ceili(float(RECHARGE_STEPS) * recharge_left / recharge_whole - 0.000001)


## Take on the recharge of `other` (a stack of the same item joining it) when it has more left.
func join_recharge(other: ItemStack) -> void:
	if other.recharge_left > recharge_left:
		recharge_left = other.recharge_left
		recharge_whole = other.recharge_whole
