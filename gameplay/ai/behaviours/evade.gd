extends AIBehaviour
## Low on health, or crowded well inside its range band: get away, to cover behind a wall if one
## is near (`AISight.cover`), else straight back; urgent, so it dashes if it can. Caution makes it
## keener. Standing in harmful cover (ground cover GC7: `AIBrain.in_harm`, burning grass, cobwebs),
## target or none: step out to the nearest cell that does not harm (`AIBrain.harm_exit`), urgent,
## keener than any fight.

## Health (a fraction of the most) under which it wants out.
const LOW: float = 0.3
## How much it wants out of harmful cover (plus `HARM_CAUTION` times its caution): above a ready
## fight's and a shot's dodge, so it does not stand in the fire to cast.
const HARM: float = 1.2
const HARM_CAUTION: float = 0.4


func name() -> String:
	return "evade"


func want(brain: AIBrain) -> float:
	if brain.in_harm and brain.harm_exit != Vector2.INF:
		return HARM + HARM_CAUTION * brain.profile.caution
	if brain.target == null:
		return 0.0
	var low: bool = brain.health_fraction < LOW
	var crowded: bool = brain.band_min > 40.0 and brain.distance < brain.band_min * 0.5
	if not low and not crowded:
		return 0.0
	return brain.profile.caution * (0.5 + (0.4 if low else 0.0))


func act(brain: AIBrain) -> void:
	brain.plan_urgent = true
	if brain.in_harm and brain.harm_exit != Vector2.INF:
		brain.plan_move = AIBrain.Move.POINT
		brain.plan_point = brain.harm_exit
		return
	brain.plan_move = AIBrain.Move.WAY
	var cover: Vector2 = brain.cover_from_target()
	brain.plan_way = cover if cover != Vector2.ZERO else -brain.to_target.normalized()
