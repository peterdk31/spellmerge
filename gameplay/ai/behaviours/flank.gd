extends AIBehaviour
## A staff's aimed cast reaches the target but a wall stands in the line (a room's or a Wall
## card's, `AISight`): walk round it (`AISight.detour`) rather than shoot the wall.


func name() -> String:
	return "flank"


func want(brain: AIBrain) -> float:
	if brain.target == null or brain.line_clear:
		return 0.0
	for at in brain.staff_count:
		var sense: CastSense = brain.senses[at]
		if sense != null and sense.harms() and sense.reach > 0.0 and brain.reaches(sense):
			return 0.65
	return 0.0


func act(brain: AIBrain) -> void:
	brain.reposition()
