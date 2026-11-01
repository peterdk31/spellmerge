extends AIBehaviour
## A teammate on the board is hurt (under `TeamBoard.HURT`) and a staff whose next cast heals and
## hurts nobody is ready, with the teammate in its reach along a clear line: cast it at the
## teammate (`plan_target`). Hurt itself, a cast whose heal lands on its caster (`heals_self`)
## will do. The more hurt the one healed, the keener; the most hurt in reach is chosen
## (`AIBrain.hurt_mate`). It never heals another team: a teammate is one the board names and the
## actor table puts on its own team.

## Its want for a heal: BASE, plus HURT_BONUS times the share of health the one healed has lost.
const BASE: float = 0.9
const HURT_BONUS: float = 0.3


func name() -> String:
	return "heal ally"


func want(brain: AIBrain) -> float:
	brain.picks[index] = -1
	brain.memo[index] = -1.0
	var best: float = 0.0
	for at in brain.staff_count:
		var sense: CastSense = brain.senses[at]
		if sense == null or sense.empty or not sense.heals or brain.ready[at] == 0 or brain.holding[at] != 0:
			continue
		if sense.heals_self and brain.health_fraction < TeamBoard.HURT:
			var own: float = BASE + HURT_BONUS * (1.0 - brain.health_fraction)
			if own > best:
				best = own
				brain.picks[index] = at
				brain.memo[index] = -1.0
		if sense.reach <= 0.0 or sense.harms():
			continue
		var mate: Actor = brain.hurt_mate(sense)
		if mate == null:
			continue
		var value: float = BASE + HURT_BONUS * (1.0 - AIBrain.health_of(mate))
		if value > best:
			best = value
			brain.picks[index] = at
			brain.memo[index] = float(mate.id)
	return best


func act(brain: AIBrain) -> void:
	brain.plan_staff = brain.picks[index]
	var who: int = int(brain.memo[index])
	if who >= 0 and brain.actor.actors != null:
		brain.plan_target = brain.actor.actors.node_of(who) as Node2D
