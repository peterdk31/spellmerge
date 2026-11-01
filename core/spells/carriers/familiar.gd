class_name CarrierFamiliar
extends CarrierEntity
## A helper that circles its caster and casts what its triggers give it, from its orb
## (`&"familiar"`, `Spells.familiar_at`). It hits nothing itself: only a blast hits for it.


func id() -> StringName:
	return &"familiar"


func traits() -> int:
	return LASTS | SPEED | SHOTS | SPREAD | SPAWNS
