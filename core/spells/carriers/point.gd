class_name CarrierPoint
extends CarrierFallback
## The fallback carrier of a payload that nothing but a point casts (`&"point"`, docs/CARRIERS.md):
## the modifiers and infusions it read with no carrier after them land on the point it began at
## (where a shot that is gone hit or ended, where a beam's tip or a rain's spot ticked). It strikes
## round that point (`CarrierFallback`): `on hit · bolt · blast` explodes where the bolt hits. A point
## meets no shots and has nothing to push, so a shield, a deflect or a recoil does nothing there.
## A payload that a body or a live shot may cast lands on that instead (`CarrierBearer`).


func id() -> StringName:
	return &"point"


func traits() -> int:
	return HITS | CASTERLESS
