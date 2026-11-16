extends AIBehaviour
## The run-up (boss plan OB14): a ready staff whose next cast runs its caster along a way and hurts
## (a dash with its pass; `CastSense.moves_along`) goes as far as its line is clear, so before it
## is cast from where its line is short, walk first to where that line is longest: a wall's foot
## facing the open room, with the target between (`AIBrain.run_up`, `AISight.run_up_spot`), and cast
## it from there. Every dashing enemy has it; a short dash's line is almost always long enough, so
## it is mostly a long one's (a boss's Big Sweep). Keener than a fight, so the long move is not cast
## from a poor place meanwhile; once there (or with no better place to go), it casts the move it ran
## up for. Its memo is the staff it is running up for (-INF for none, and again once that staff is
## not ready: its move left); where it walks to is the
## brain's `run_up_point` (Vector2.INF: cast now).

## Its want while it runs up, and as it casts from its start: above a fight's.
const RUN_UP: float = 1.25
## A line at least this share of the move's reach is long enough: no run-up.
const LONG_ENOUGH: float = 0.9
## A start is worth walking to when its run is longer than the line here by this share of the
## reach, and by at least GAIN_LEAST pixels.
const GAIN: float = 0.2
const GAIN_LEAST: float = 24.0
## Nearer its start than this (pixels) it is there.
const THERE: float = 12.0


func name() -> String:
	return "run up"


func want(brain: AIBrain) -> float:
	brain.picks[index] = -1
	if brain.target == null:
		return 0.0
	# The longest of the ready moves that run it along and hurt.
	var best: int = -1
	for at in brain.staff_count:
		var sense: CastSense = brain.senses[at]
		if sense == null or sense.empty or not sense.moves_along or not sense.harms() or sense.move_reach <= 0.0:
			continue
		if brain.ready[at] == 0 or brain.holding[at] != 0:
			continue
		if best < 0 or sense.move_reach > brain.senses[best].move_reach:
			best = at
	var running: bool = best >= 0 and brain.memo[index] == float(best)
	if not running:
		# Its move left (or was never ready): no run-up under way.
		brain.memo[index] = -INF
	if best < 0:
		return 0.0
	var sense: CastSense = brain.senses[best]
	var here: float = brain.run_here(sense)
	if here >= sense.move_reach * LONG_ENOUGH:
		# Long enough here: cast it if it ran up for it; else a fight may cast it as any.
		return _cast_now(brain, best) if running else 0.0
	var start: Vector3 = brain.run_up(sense)
	var spot: Vector2 = Vector2(start.x, start.y)
	if start.z < here + maxf(sense.move_reach * GAIN, GAIN_LEAST) or brain.actor.global_position.distance_to(spot) <= THERE:
		# No better place to go (or it is there): cast it from here if it ran up for it.
		return _cast_now(brain, best) if running else 0.0
	brain.picks[index] = best
	brain.run_up_point = spot
	return RUN_UP


func act(brain: AIBrain) -> void:
	var at: int = brain.picks[index]
	if at < 0:
		return
	if brain.run_up_point == Vector2.INF:
		# There: the move leaves from here (the run-up is over once it is no longer ready).
		brain.plan_staff = at
		brain.plan_move = AIBrain.Move.STAND
		return
	brain.memo[index] = float(at)
	brain.plan_move = AIBrain.Move.POINT
	brain.plan_point = brain.run_up_point


## Cast staff `at` from here: wanted as much as running up was.
func _cast_now(brain: AIBrain, at: int) -> float:
	brain.picks[index] = at
	brain.run_up_point = Vector2.INF
	return RUN_UP
