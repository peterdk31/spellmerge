class_name CarrierFamiliar
extends CarrierEntity
## A helper that circles its caster and casts what its triggers give it (`&"familiar"`).
## It hits nothing itself: only a blast carries hit cards and infusions.


func id() -> StringName:
	return &"familiar"


func noun() -> String:
	return "familiar"


func what() -> String:
	return "a familiar is a body that hits nothing"


func traits() -> int:
	return LASTS | SPEED | SHOTS | SPREAD


func hits_nothing() -> String:
	return "a familiar hits nothing"


## A familiar circles its caster.
func _follows_caster() -> bool:
	return true
