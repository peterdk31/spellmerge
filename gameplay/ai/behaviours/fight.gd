extends AIBehaviour
## Cast at the target: of the staffs whose next cast hurts and reaches it now (along a clear line
## for an aimed one; round itself for one that is not; never a blast that would catch itself), the
## one that is ready and deals most. With one in reach that is not ready yet it stands and waits,
## so a telegraph only ever shows a cast that comes.

## Its want with a cast ready, plus a little for the damage it deals.
const READY: float = 0.8
const WAITING: float = 0.4
## Pixels clear of its own blast a target must stand.
const BLAST_MARGIN: float = 8.0


func name() -> String:
	return "fight"


func want(brain: AIBrain) -> float:
	brain.picks[index] = -1
	if brain.target == null:
		return 0.0
	var best: float = 0.0
	var waiting: int = -1
	for at in brain.staff_count:
		var sense: CastSense = brain.senses[at]
		if sense == null or sense.empty or not sense.harms() or brain.holding[at] != 0:
			continue
		if not brain.reaches(sense):
			continue
		if sense.blast > 0.0 and not sense.moves_caster and brain.distance < sense.blast + BLAST_MARGIN:
			continue
		if sense.reach > 0.0 and not brain.line_clear:
			continue
		if brain.ready[at] == 0:
			if waiting < 0:
				waiting = at
			continue
		var value: float = READY + minf(sense.damage, 30.0) / 100.0 + (0.05 if sense.status else 0.0)
		if sense.reach > 0.0 and brain.band_min > 0.0 and brain.distance < brain.band_min:
			# Too close for an aimed cast to be its best: a cautious one steps back first.
			value *= 0.4 + 0.6 * brain.distance / brain.band_min
		if value > best:
			best = value
			brain.picks[index] = at
	if brain.picks[index] >= 0:
		return best * brain.team_beat()
	if waiting >= 0 and brain.distance >= brain.band_min:
		# Waiting in its range band; too close, it would rather step back first.
		brain.picks[index] = waiting
		return WAITING
	return 0.0


func act(brain: AIBrain) -> void:
	brain.plan_staff = brain.picks[index]
