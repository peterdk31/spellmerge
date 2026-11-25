class_name CompiledCast
extends RefCounted
## One cast of a staff's cycle (docs/milestones/M2-staffs.md, "Reading a staff"): the group it
## fires, the slots it read and its numbers. Made by `StaffCompiler`; read-only.

## Made whole by the staff compiler and never changed after: the state walk hashes it once
## (core/sim/README.md).
const FROZEN: bool = true

## The group the cast fires; payloads hang below its spells.
var group: CompiledGroup = null
## The slots the cast read, in reading order (a slot read after a wrap comes after the end).
var slots: PackedInt32Array = PackedInt32Array()
## Mana the cast takes: every carrier, payloads included, and its multicast cards.
var mana: float = 0.0
## Seconds the staff is busy after the cast leaves (docs/milestones/cast-timing.md): the
## wind-down of every carrier of its own group (times its modifiers' `wind_down_mult`) and its
## multicast cards'. A payload adds none: no staff waits on it.
var wind_down: float = 0.0
## Seconds the cast winds up before it leaves: its staff's `wind_up` plus its group's.
var wind_up: float = 0.0
## Seconds the staff waits after this cast in all: `wind_down`, plus the staff's `cooldown` when
## `ends_cycle`.
var delay: float = 0.0
## True when the staff starts over after this cast (it reached the end of its cards); its
## cooldown follows.
var ends_cycle: bool = false
## True when the reading went past the last slot and on from the first.
var wrapped: bool = false
## The conditions the cast leaves only while (docs/milestones/staff-language.md, L2): each a
## `ModifierBase.WHEN_IDS` name and its amount (`when_amounts`, same order); empty for none.
var when_ids: Array[StringName] = []
var when_amounts: PackedFloat32Array = PackedFloat32Array()
## Its conditions in plain words, for the builder ("only when hurt"); empty for none.
var when_text: String = ""
## What each modifier, infusion and trigger read in this cast attached to: card slot -> the
## slot of its carrier.
var targets: Dictionary = {}
## Slots whose card did nothing in this cast -> true.
var wasted: Dictionary = {}
## What the cast does, in plain words, for the builder's cast plan.
var description: String = ""
## What the cast does, for an AI (`CastSense`, docs/milestones/M2-enemy-ai.md): made by the
## compiler once the cast is read.
var sense: CastSense = null
## The carrier cards of its own group's spells, and the infusion cards they carry, each once in
## the order they come (Feel's cast sounds, `gameplay/feel/cast_sounds.gd`: what a cast sounds of,
## read without its spells' fields). Made by the compiler with `sense`.
var carrier_cards: Array[StringName] = []
var infusion_cards: Array[StringName] = []


## Fills `carrier_cards` and `infusion_cards` from its group (the compiler, once).
func list_cards() -> void:
	carrier_cards.clear()
	infusion_cards.clear()
	if group == null:
		return
	for spell: CompiledSpell in group.spells:
		if not carrier_cards.has(spell.carrier_card_id):
			carrier_cards.append(spell.carrier_card_id)
		for element: StringName in spell.element_ids:
			if not infusion_cards.has(element):
				infusion_cards.append(element)
