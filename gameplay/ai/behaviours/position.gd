extends AIBehaviour
## Keep the range band its staffs give (`AIBrain.band_min` to `band_max`): walk in when farther,
## step back when nearer. A bolt makes a kiter, a swing a rusher, and a new staff changes it at once.
## A profile that presses on steps back only from nearer still (`AIProfile.press_on`; at 1 never).


func name() -> String:
	return "keep range"


func want(brain: AIBrain) -> float:
	if brain.target == null or brain.band_max <= 0.0:
		return 0.0
	if brain.distance > brain.band_max:
		return 0.25
	var near: float = brain.band_min * (1.0 - brain.profile.press_on)
	if brain.distance < near:
		return 0.3 + 0.9 * brain.profile.caution * (1.0 - brain.distance / near)
	return 0.0


func act(brain: AIBrain) -> void:
	brain.plan_move = AIBrain.Move.TOWARD if brain.distance > brain.band_max else AIBrain.Move.AWAY
