class_name CompiledGroup
extends RefCounted
## One group read from a staff (docs/milestones/M2-staffs.md, "Reading a staff"): the
## carriers that leave together, as compiled spells, and how they leave. A cast is one group;
## a trigger's payload, and the payload of `rain` and `familiar`, is another. Read-only data
## made by `StaffCompiler`; nothing outside `core/spells/` and the builder view reads it.

## The carriers of the group, in slot order; a fallback (the caster or the payload's origin)
## comes last.
var spells: Array[CompiledSpell] = []
## True when a scatter card sends the carriers in random directions (seeded per cast).
var scatter: bool = false
## How often the group fires (burst cards multiply it), `repeat_interval` seconds apart.
var repeats: int = 1
## The multicast cards read into the group, in slot order (for its name).
var multicast_ids: Array[StringName] = []
## Their slots, in the same order (for the builder's tree).
var multicast_slots: PackedInt32Array = PackedInt32Array()
var repeat_interval: float = 0.0


func is_empty() -> bool:
	return spells.is_empty()
