class_name CompiledStaff
extends RefCounted
## A staff's cards compiled into its cycle (`Spells.compile_staff`, staffs A4): the casts it
## makes from its first card until it recharges. Reading is deterministic, so the cycle is
## computed once per build change. Read-only data for the spell runtime and the builder view.

## The staff the cards sit in, and the card ids by slot (`&""` for an empty slot).
var staff: StaffBase = null
var cards: Array[StringName] = []
## The casts of one cycle, in order; empty when the staff holds no card.
var casts: Array[CompiledCast] = []
## Every compiled spell of the cycle, payloads and fallbacks included; a spell's `node` is
## its index here (the tag of its shots carries it, staffs A5).
var nodes: Array[CompiledSpell] = []
## Slots whose card did nothing in any cast that read it -> the reason, for the builder to
## grey out. A card that is useful in one cast and wasted in another is not listed.
var wasted: Dictionary = {}


func is_empty() -> bool:
	return casts.is_empty()
