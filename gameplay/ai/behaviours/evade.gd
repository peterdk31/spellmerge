extends AIBehaviour
## Low on health, or crowded well inside its range band: get away, to cover behind a wall if one
## is near (`AISight.cover`), else straight back; urgent, so it dashes if it can. Caution makes it
## keener.

## Health (a fraction of the most) under which it wants out.
const LOW: float = 0.3


func name() -> String:
	return "evade"


func want(brain: AIBrain) -> float:
	if brain.target == null:
		return 0.0
	var low: bool = brain.health_fraction < LOW
	var crowded: bool = brain.band_min > 40.0 and brain.distance < brain.band_min * 0.5
	if not low and not crowded:
		return 0.0
	return brain.profile.caution * (0.5 + (0.4 if low else 0.0))


func act(brain: AIBrain) -> void:
	brain.plan_move = AIBrain.Move.WAY
	var cover: Vector2 = brain.cover_from_target()
	brain.plan_way = cover if cover != Vector2.ZERO else -brain.to_target.normalized()
	brain.plan_urgent = true
