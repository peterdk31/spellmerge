extends AIBehaviour
## A teammate is downed (`AIBrain.downed_mate`, the nearest): walk to it and stand beside it, so
## the coop rule revives it (a standing teammate near enough for long enough; gameplay/coop), when
## that is safe enough: no foe within SAFE of the one downed (`AIBrain.foe_within`; a bot never
## walks into a crowd to revive), its own health not under LOW, and no shot about to hit it (an
## urgent dodge goes first). With the fight over (no target) it wants it most; with a fight on,
## more than a ready attack, and it fires the best ready staff that hurts the target from where it
## walks or stands (`AIBrain.can_fire`), never one that would carry it off: one that moves its
## caster, winds up or is held (the brain presses on toward its target through a wind-up and a
## channel, `AIProfile.press_on`).
## A wall between walks round it (`AISight.detour`). Only with `AIProfile.revives` above 0 (the test
## bots'); an enemy never looks. It reads no coop rule: NEAR is its own, well inside the revive's
## range (tests/gameplay/ai/test_ai_revive.gd checks it against Coop's).

## How near the one downed it stands (pixels, feet to feet).
const NEAR: float = 20.0
## No foe this near the one downed (pixels), or it stays out of it.
const SAFE: float = 96.0
## Under this share of its health it does not go (it would be downed beside it).
const LOW: float = 0.3
## Its want with no fight on, and with one on (above a ready fight's, about 0.8-1.15, and an
## urgent dodge of the bot's, 1.12).
const CLEAR: float = 2.0
const FIGHTING: float = 1.2
## Pixels clear of its own blast a target must stand (as a fight's).
const BLAST_MARGIN: float = 8.0
## How far it probes a way round a wall (as the brain's detour).
const PROBE: float = 40.0


func name() -> String:
	return "revive"


func want(brain: AIBrain) -> float:
	brain.memo[index] = -1.0
	if brain.profile.revives <= 0.0:
		return 0.0
	if brain.health_fraction < LOW:
		return 0.0
	if brain.threat_time >= 0.0 and brain.threat_time < AIBrain.URGENT_TIME:
		return 0.0
	var mate: Actor = brain.downed_mate()
	if mate == null or brain.foe_within(mate.global_position + mate.body_offset, SAFE):
		return 0.0
	brain.memo[index] = float(mate.id)
	return brain.profile.revives * (CLEAR if brain.target == null else FIGHTING)


func act(brain: AIBrain) -> void:
	var who: int = int(brain.memo[index])
	var mate: Actor = brain.actor.actors.node_of(who) as Actor if who >= 0 and brain.actor.actors != null else null
	if mate == null:
		return
	var from: Vector2 = brain.actor.global_position
	var to: Vector2 = mate.global_position
	if from.distance_to(to) <= NEAR:
		# Beside it: stand (a point where it is, so a bot that presses on does not walk off).
		brain.plan_move = AIBrain.Move.POINT
		brain.plan_point = from
	elif brain.actor.projectiles != null and not AISight.walk_clear(brain.actor.projectiles, from, to):
		brain.plan_move = AIBrain.Move.WAY
		brain.plan_way = AISight.detour(brain.actor.projectiles, from, to, PROBE)
	else:
		brain.plan_move = AIBrain.Move.POINT
		brain.plan_point = to
	brain.plan_staff = fire_pick(brain)


## The ready staff that hurts the target from here and deals most, never one that moves its
## caster, winds up or is held (any would walk it off); -1 for none.
static func fire_pick(brain: AIBrain) -> int:
	var best: int = -1
	var most: float = -1.0
	for at in brain.staff_count:
		var sense: CastSense = brain.senses[at]
		if brain.ready[at] == 0 or not brain.can_fire(sense, at, BLAST_MARGIN):
			continue
		if sense.moves_caster or sense.wind_up > 0.0 or sense.repeats_held:
			continue
		if sense.damage > most:
			most = sense.damage
			best = at
	return best
