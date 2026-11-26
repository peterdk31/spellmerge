class_name SigilBase
extends ItemContent
## A sigil (docs/milestones/staff-language.md, L4; the owner, 2026-11-25): an item put on a whole
## staff, not a card in it, that makes the staff cast by itself while its condition holds, along its
## holder's aim, at the staff's own cooldown and mana (its holder may still press it). Kept in the
## sigils bag (`ItemKinds.SIGIL`) until put on one of its holder's staffs in the inventory menu
## (`ItemStack.sigils`, at most `MOST_A_STAFF`, no two the same), and taken off again freely. An
## enemy's staff entry may name some too (`StaffCards.sigils`). One folder each, `content/sigils/<id>/`,
## found by the registry under `sigils`. It has no use from the bag: its point is its staff.

## What a sigil may wait for, by name: `hurt`, its holder's health below `amount` of its most (0.5:
## below half); `close`, a foe's hit shape within `amount` pixels of its holder's body. A new
## condition is a name here and a line in `Caster.sigil_holds`, never a sigil's script.
const WHENS: Array[StringName] = [&"hurt", &"close"]
## The most sigils one staff holds (the owner, 2026-11-25).
const MOST_A_STAFF: int = 3

## What it waits for (one of `WHENS`).
@export var when: StringName = &"hurt"
## Its condition's amount: a share of its holder's most health for `hurt`, pixels for `close`.
@export var amount: float = 0.5
## Its words for the HUD and the builder, after "Casts by itself" ("when hurt").
@export var words: String = ""


## Its words for the HUD and the builder: `words`, else "when " and its condition.
func shown_words() -> String:
	return words if words != "" else "when %s" % when


## What is wrong with it, one line each: its item's, a condition it does not know, an amount that
## means nothing.
func problems() -> PackedStringArray:
	var found: PackedStringArray = super.problems()
	if not WHENS.has(when):
		found.append("The sigil '%s' waits for '%s', which is no condition (%s)." % [id, when, ", ".join(WHENS)])
	elif when == &"hurt" and (amount <= 0.0 or amount > 1.0):
		found.append("The sigil '%s' waits for a health share of %s; it must be above 0 and at most 1." % [id, amount])
	elif when == &"close" and (amount <= 0.0 or amount > 512.0):
		found.append("The sigil '%s' waits for a foe within %s px; it must be above 0 and at most 512." % [id, amount])
	return found
