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
## The hit kind: `&"shot"`, `&"ray"`, `&"swing"` (melee) or `&"burst"` (an area hit is always `burst`). Combat sets
## `reaction` and `status` for the hits it makes itself.
var kind: StringName = &"shot"
## Health a hit gives a wizard instead of damage (mend); 0 for none. An enemy still takes `damage`.
var heal: int = 0
## Damage an enemy takes when this hit knocks it into a wall (heavy); 0 for none.
var slam: int = 0
## The spell's own name, for "downed by your own <name>"; empty when not known.
var source_name: String = ""


## A new profile with everything this one has: every element and status, the kind, heal and slam.
## For a hit that changes later (`relay`), so the shared one is never written.
func copy() -> HitProfile:
	return scaled(1.0, 1.0)


## This hit at `share` of its strength (an echo, an arc zap): damage (at least 1), heal and slam
## scaled, knockback by `knock_share`, and the rest (elements, statuses, kind) all kept, so a scaled
## hit is the same hit, weaker: an echoed mend still heals, an echoed heavy hit still slams.
func scaled(share: float, knock_share: float) -> HitProfile:
	var made: HitProfile = HitProfile.new()
	made.damage = damage if share == 1.0 else maxi(roundi(float(damage) * share), 1)
	made.heal = heal if share == 1.0 else roundi(float(heal) * share)
	made.slam = slam if share == 1.0 else roundi(float(slam) * share)
	made.knockback = knockback * knock_share
	made.element_id = element_id
	made.element_ids = element_ids.duplicate()
	made.status_id = status_id
	made.status_duration = status_duration
	made.status_strength = status_strength
	made.later_status_ids = later_status_ids.duplicate()
	made.later_status_durations = later_status_durations.duplicate()
	made.later_status_strengths = later_status_strengths.duplicate()
	made.kind = kind
	made.source_name = source_name
	return made
