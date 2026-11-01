class_name StaffCards
extends Resource
## A staff and the cards in it, as an enemy holds it (docs/milestones/M2-enemy-ai.md, "The enemy's
## data"): one entry of `EnemyBase.staffs` or of a phase's staffs. The AI reads what each staff
## casts next (`CastSense`), so nothing here says what the staff is for.

## The staff (`StaffBase`: its slots, draw, delay and mana pool).
@export var staff: StaffBase = null
## Card ids by slot (`&""` for an empty slot); no more than the staff's slots.
@export var cards: Array[StringName] = []


## A new entry of `staff` holding `cards`.
static func make(of_staff: StaffBase, of_cards: Array[StringName]) -> StaffCards:
	var made := StaffCards.new()
	made.staff = of_staff
	made.cards = of_cards.duplicate()
	return made


## What is wrong with the entry, one line each (empty when it is fine): no staff, more cards than
## slots (the extra ones would be cut off silently), no card at all.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if staff == null:
		found.append("It has no staff.")
		return found
	if cards.size() > staff.slots:
		found.append("It has %d cards but the staff has %d slots, so %s would be cut off." % [cards.size(), staff.slots, ", ".join(PackedStringArray(cards.slice(staff.slots)))])
	var any: bool = false
	for card: StringName in cards:
		if card != &"":
			any = true
	if not any:
		found.append("It has no card.")
	return found
