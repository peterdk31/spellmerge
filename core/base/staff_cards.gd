class_name StaffCards
extends Resource
## A staff and the cards in it, as an enemy holds it (docs/milestones/M2-enemy-ai.md, "The enemy's
## data"): one entry of `EnemyBase.staffs` or of a phase's staffs. The AI reads what each staff
## casts next (`CastSense`), so nothing here says what the staff is for.

## The staff (`StaffBase`: its slots, draw, delay and mana pool).
@export var staff: StaffBase = null
## Card ids by slot (`&""` for an empty slot); no more than the staff's slots.
@export var cards: Array[StringName] = []
## Sigils on the staff (staff-language L4): it casts by itself while one holds, along the body's aim,
## at its cooldown and mana. At most `SigilBase.MOST_A_STAFF`, no two the same, and only on a staff
## that winds up (its telegraph warns before every cast it makes by itself).
@export var sigils: Array[SigilBase] = []


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
	if not sigils.is_empty():
		if staff.wind_up <= 0.0:
			found.append("It has sigils but its staff has no wind-up, so it would cast by itself without a warning.")
		if sigils.size() > SigilBase.MOST_A_STAFF:
			found.append("It has %d sigils; at most %d." % [sigils.size(), SigilBase.MOST_A_STAFF])
		var seen: Array[StringName] = []
		for sigil: SigilBase in sigils:
			if sigil == null:
				found.append("It has an empty sigil.")
			elif seen.has(sigil.id):
				found.append("It has the sigil %s twice." % sigil.id)
			else:
				seen.append(sigil.id)
	return found


## What is wrong with a body's list of staffs (an enemy's, a prop's), one line each, each line after
## `owner`: more than `most`, an empty entry, an entry's own problems. Staffs are numbered from
## `first` (an enemy's from 0, a prop's from 1, as its triggers name them).
static func list_problems(owner: String, entries: Array[StaffCards], most: int, first: int = 0) -> PackedStringArray:
	var found := PackedStringArray()
	if entries.size() > most:
		found.append("%s has %d staffs; at most %d." % [owner, entries.size(), most])
	for at in entries.size():
		if entries[at] == null:
			found.append("%s: staff %d is empty." % [owner, at + first])
			continue
		for line: String in entries[at].problems():
			found.append("%s: staff %d: %s" % [owner, at + first, line])
	return found
