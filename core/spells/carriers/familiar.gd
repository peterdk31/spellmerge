class_name CarrierFamiliar
extends CarrierEntity
## A helper that circles its caster and casts what its triggers give it, from its orb
## (`&"familiar"`, `Spells.familiar_at`). It hits nothing itself: only a blast hits for it.


func id() -> StringName:
	return &"familiar"


## What draws its look: Entities draws its orbs.
func look_drawer() -> int:
	return LOOK_ORB


func traits() -> int:
	return LASTS | SHOTS | SPREAD | SPAWNS
