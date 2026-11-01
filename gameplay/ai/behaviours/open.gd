extends AIBehaviour
## A staff whose next cast makes a body of its own (a decoy, a familiar) or stays on (`hold`) is
## ready and its last one has run out: cast it once, before anything else, so the fight opens
## with it.


func name() -> String:
	return "open"


func want(brain: AIBrain) -> float:
	brain.picks[index] = -1
	if brain.target == null:
		return 0.0
	for at in brain.staff_count:
		var sense: CastSense = brain.senses[at]
		if sense == null or sense.empty or brain.ready[at] == 0 or brain.holding[at] != 0:
			continue
		if not (sense.spawns or sense.sustained):
			continue
		if brain.clock - brain.memo[index] < maxf(sense.lasts, 3.0):
			continue
		brain.picks[index] = at
		return 0.95
	return 0.0


func act(brain: AIBrain) -> void:
	brain.plan_staff = brain.picks[index]
	brain.memo[index] = brain.clock
