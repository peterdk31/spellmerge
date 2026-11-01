extends AIBehaviour
## A shot will hit it soon (`Projectiles.threat`): step off its line, and when it is close dash
## that way if a staff's next cast moves it (the move step does the dash). Only with
## `AIProfile.dodge` above 0; the sooner the shot, the more it wants to.


func name() -> String:
	return "dodge"


func want(brain: AIBrain) -> float:
	if brain.threat_time < 0.0 or brain.profile.dodge <= 0.0:
		return 0.0
	var urgency: float = clampf(1.0 - brain.threat_time / AIBrain.DODGE_HORIZON, 0.0, 1.0)
	return brain.profile.dodge * (0.5 + 0.9 * urgency)


func act(brain: AIBrain) -> void:
	brain.plan_move = AIBrain.Move.WAY
	brain.plan_way = brain.threat_away
	brain.plan_urgent = brain.threat_time < AIBrain.URGENT_TIME
