extends AIBehaviour
## Keep the range band its staffs give (`AIBrain.band_min` to `band_max`): walk in when farther,
## step back when nearer. A bolt makes a kiter, a swing a rusher, and a new staff changes it at once.
## A profile that presses on steps back only from nearer still (`AIProfile.press_on`; at 1 never).
## With teammates on the same target (teamwork, `TeamBoard`), it walks to its slot round the target
## at the middle of its band instead, and off its slot it walks round to it.

## Its slot this far round (radians) or less is near enough.
const SLOT_SLACK: float = deg_to_rad(12.0)


func name() -> String:
	return "keep range"


func want(brain: AIBrain) -> float:
	if brain.target == null or brain.band_max <= 0.0:
		return 0.0
	if brain.distance > brain.band_max:
		return maxf(0.25, _spread(brain))
	var near: float = brain.band_min * (1.0 - brain.profile.press_on)
	if brain.distance < near:
		return maxf(0.3 + 0.9 * brain.profile.caution * (1.0 - brain.distance / near), _spread(brain))
	return _spread(brain)


func act(brain: AIBrain) -> void:
	var slot: Vector2 = brain.slot_way()
	if slot != Vector2.ZERO:
		brain.plan_move = AIBrain.Move.WAY
		brain.plan_way = slot
		return
	brain.plan_move = AIBrain.Move.TOWARD if brain.distance > brain.band_max else AIBrain.Move.AWAY


## Off its slot round the target: more than a fight that waits for its staff, so it moves round
## between casts, and more than a ready one only when far round and keen on teamwork (it walks
## round to its side first). Teamwork makes it keener; 0 with no slot to keep.
func _spread(brain: AIBrain) -> float:
	var off: float = brain.slot_off()
	if off <= SLOT_SLACK:
		return 0.0
	return (0.5 + 0.5 * off / PI) * (0.5 + 0.5 * brain.profile.teamwork)
