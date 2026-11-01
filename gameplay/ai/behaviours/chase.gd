extends AIBehaviour
## Walk to the target: the fallback, and all an actor with no staff that hurts does (it walks into
## its target and hurts by touch). With a staff it chases only while out of its range band.


func name() -> String:
	return "chase"


func want(brain: AIBrain) -> float:
	if brain.target == null:
		return 0.0
	if brain.band_max > 0.0 and brain.distance <= brain.band_max:
		return 0.0
	return 0.1


func act(brain: AIBrain) -> void:
	brain.plan_move = AIBrain.Move.TOWARD
