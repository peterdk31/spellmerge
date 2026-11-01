extends AIBehaviour
## Keep the range band its staffs give (`AIBrain.band_min` to `band_max`): walk in when farther,
## step back when nearer. A bolt makes a kiter, a swing a rusher, and a new staff changes it at once.


func name() -> String:
	return "keep range"


func want(brain: AIBrain) -> float:
	if brain.target == null or brain.band_max <= 0.0:
		return 0.0
	if brain.distance > brain.band_max:
		return 0.25
	if brain.distance < brain.band_min:
		return 0.3 + 0.9 * brain.profile.caution * (1.0 - brain.distance / brain.band_min)
	return 0.0


func act(brain: AIBrain) -> void:
	brain.plan_move = AIBrain.Move.TOWARD if brain.distance > brain.band_max else AIBrain.Move.AWAY
