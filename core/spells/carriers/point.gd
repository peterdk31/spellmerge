class_name CarrierPoint
extends CarrierFallback
## The fallback carrier of a payload (`&"point"`, docs/CARRIERS.md): the modifiers and infusions a
## payload read with no carrier after them land on the point it began at (where its shot hit, ended
## or ticked). It strikes round that point (`CarrierFallback`): `on hit · bolt · blast` explodes
## where the bolt hits. A point meets no shots, so a shield or a deflect does nothing there.


func id() -> StringName:
	return &"point"
