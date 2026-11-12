class_name CarrierPulsePoint
extends CarrierPulse
## The Pulse card's carrier in a payload that nothing but a point casts (`&"pulse_point"`,
## docs/CARRIERS.md, "Pulse: a strike round what casts it"): it strikes round the point the payload
## began at (where a shot that is gone hit or ended, where a beam's tip ticked):
## `on hit · bolt · blast · pulse` explodes where the bolt hits. A point meets no shots and has
## nothing to push, so a shield, a deflect or a recoil does nothing there. A payload that a body or
## a live shot may cast is round that instead (`CarrierPulseBearer`). No card names it: the compiler
## takes it for the Pulse card in such a payload (`Carriers.placed`).


func id() -> StringName:
	return &"pulse_point"


func traits() -> int:
	return super() | CASTERLESS


## Only ever a payload's (no card names it in a cast's own group), which adds no wind-down to its
## staff, so a card's wind-down factor has nothing to shorten.
func has_wind_down() -> bool:
	return false
