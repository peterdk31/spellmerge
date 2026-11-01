extends AIBehaviour
## Under fire or just hurt, with a staff whose next cast stops shots (a wall, a shield) ready:
## cast it. Caution makes it keener.


func name() -> String:
	return "guard"


func want(brain: AIBrain) -> float:
	brain.picks[index] = -1
	var pressed: bool = (brain.threat_time >= 0.0 and brain.threat_time < 0.8) or brain.hurt_left > 0.0
	if not pressed:
		return 0.0
	for at in brain.staff_count:
		var sense: CastSense = brain.senses[at]
		if sense != null and sense.blocks and brain.ready[at] != 0 and brain.holding[at] == 0:
			brain.picks[index] = at
			return 1.1 + 0.3 * brain.profile.caution
	return 0.0


func act(brain: AIBrain) -> void:
	brain.plan_staff = brain.picks[index]
