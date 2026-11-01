class_name CompiledCast
extends RefCounted
## One cast of a staff's cycle (docs/milestones/M2-staffs.md, "Reading a staff"): the group it
## fires, the slots it read and its numbers. Made by `StaffCompiler`; read-only.

## The group the cast fires; payloads hang below its spells.
var group: CompiledGroup = null
## The slots the cast read, in reading order (a slot read after a wrap comes after the end).
var slots: PackedInt32Array = PackedInt32Array()
## Mana the cast takes: every carrier, payloads included, and its multicast cards.
var mana: float = 0.0
## Seconds before the staff may cast again: the staff's delay, every carrier's cooldown and
## the multicast cards', plus the staff's recharge when `recharges`.
var delay: float = 0.0
## True when the staff starts over after this cast (it reached the end of its cards).
var recharges: bool = false
## True when the reading went past the last slot and on from the first.
var wrapped: bool = false
## What each modifier, infusion and trigger read in this cast attached to: card slot -> the
## slot of its carrier, or `StaffCompiler.TARGET_CASTER` / `TARGET_POINT` for a fallback.
var targets: Dictionary = {}
## Slots whose card did nothing in this cast -> true.
var wasted: Dictionary = {}
## What the cast does, in plain words, for the builder's cast plan.
var description: String = ""
## What the cast does, for an AI (`CastSense`, docs/milestones/M2-enemy-ai.md): made by the
## compiler once the cast is read.
var sense: CastSense = null
