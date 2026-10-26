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
