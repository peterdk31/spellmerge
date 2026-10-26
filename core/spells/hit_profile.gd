class_name HitProfile
extends RefCounted
## What one hit of a spell's shot does, as `Spells.hit_profile(tag)` gives it to
## `gameplay/combat`: the numbers it needs and nothing else, so combat reads no spell
## field. One object per compiled spell, shared and read-only: no hit allocates.

## Damage of one hit.
var damage: int = 1
## Knockback strength of one hit, in pixels per second.
var knockback: float = 0.0
## The element's id, or `&""` for plain arcane damage.
var element_id: StringName = &""
## Every element of the hit in order (staffs: several infusions on one shot); `element_id` is
## the first. Empty for plain arcane damage.
var element_ids: Array[StringName] = []
## The status a hit applies (`&""` for none), for how long, and how strongly.
var status_id: StringName = &""
var status_duration: float = 0.0
var status_strength: float = 0.0
## The statuses of the elements after the first, in order (`element_ids[1]` first): the hit
## puts each on after the one before has reacted. Parallel arrays; shorter than `element_ids`
## means the missing ones carry no status.
var later_status_ids: Array[StringName] = []
var later_status_durations: PackedFloat32Array = PackedFloat32Array()
var later_status_strengths: PackedFloat32Array = PackedFloat32Array()

# Staffs (B3, docs/milestones/M2-staffs.md, "Self-harm and hits").
## The hit kind: `&"shot"`, `&"ray"` or `&"burst"` (an area hit is always `burst`). Combat sets
## `reaction` and `status` for the hits it makes itself.
var kind: StringName = &"shot"
## Health a hit gives a wizard instead of damage (mend); 0 for none. An enemy still takes `damage`.
var heal: int = 0
## Damage an enemy takes when this hit knocks it into a wall (heavy); 0 for none.
var slam: int = 0
## The spell's own name, for "downed by your own <name>"; empty when not known.
var source_name: String = ""
