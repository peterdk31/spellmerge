extends RefCounted
## Helpers for tests that build staffs (staffs A6c). The spell runtime only knows staffs of cards
## now; tests written before staffs describe a spell in the old recipe shape (`{"form": &"bolt",
## "element": &"fire", "modifiers": [...], "trigger": &"on_hit", "held": {...}}`), which `cards`
## turns into the card row a staff reads the same way: infusion and modifiers, the trigger, the
## carrier, then the payload. New tests write card rows directly.
##
##     const StaffKit := preload("res://tests/support/staff_kit.gd")
##     var tag: int = StaffKit.build(spells, 0, 1, StaffKit.cards({"form": &"bolt"}))
##     var first: CompiledSpell = StaffKit.first(spells, [&"fire", &"bolt"])


## The card row for a spell in the old recipe shape.
static func cards(recipe: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	if recipe.get("element") != null:
		out.append(StringName(str(recipe["element"])))
	for id: Variant in recipe.get("modifiers", []):
		out.append(StringName(str(id)))
	var trigger: Variant = recipe.get("trigger")
	if trigger != null:
		out.append(StringName(str(trigger)))
	out.append(StringName(str(recipe.get("form", ""))))
	var held: Variant = recipe.get("held")
	if trigger != null and held is Dictionary and not (held as Dictionary).is_empty():
		out.append_array(cards(held as Dictionary))
	return out


## A staff of `slots` slots with no delay or recharge of its own.
static func plain_staff(slots: int) -> StaffBase:
	var staff := StaffBase.new()
	staff.id = &"test"
	staff.slots = clampi(slots, 1, 64)
	staff.cast_delay = 0.0
	staff.recharge = 0.0
	return staff


## `cards` compiled on a plain staff.
static func compile(spells: Node, cards: Array[StringName]) -> CompiledStaff:
	return spells.call("compile_staff", cards, plain_staff(cards.size())) as CompiledStaff


## The first carrier of the first cast of `cards` (what an old recipe's spell was), or null.
static func first(spells: Node, cards: Array[StringName]) -> CompiledSpell:
	var staff: CompiledStaff = compile(spells, cards)
	if staff.is_empty() or staff.casts[0].group.is_empty():
		return null
	return staff.casts[0].group.spells[0]


## Builds `cards` into `player`'s `staff` and returns the tag of its first spell (0 for none).
static func build(spells: Node, player: int, staff: int, cards: Array[StringName]) -> int:
	return int(spells.call("install_staff", player, staff, compile(spells, cards)))
