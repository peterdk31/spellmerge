extends AIBehaviour
## Far beyond its range band with a staff whose next cast moves it (a dash, a teleport) ready:
## cast it at the target, so it closes in at once. Aggression makes it keener.


func name() -> String:
	return "close in"


func want(brain: AIBrain) -> float:
	brain.picks[index] = -1
	if brain.target == null or brain.distance <= maxf(brain.band_max, 1.0):
		return 0.0
	for at in brain.staff_count:
		var sense: CastSense = brain.senses[at]
		if sense == null or not sense.moves_caster or brain.ready[at] == 0 or brain.holding[at] != 0:
			continue
		if sense.move_reach > 0.0 and brain.distance > sense.move_reach * 0.6:
			brain.picks[index] = at
			return 0.35 + 0.4 * brain.profile.aggression
	return 0.0


func act(brain: AIBrain) -> void:
	brain.plan_staff = brain.picks[index]
	brain.plan_move = AIBrain.Move.TOWARD
