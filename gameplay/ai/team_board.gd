class_name TeamBoard
extends RefCounted
## What a team's AIs share, so they look like they work together (docs/milestones/M2-enemy-ai.md,
## "Working together"). One board serves every team; `Entities` (the AI area's autoload) keeps it
## and moves its clock on in its own step, so it is one listener for the whole crowd, never one
## per enemy.
##
## **Staggered fire:** when a teammate has just started a windup, `beat` makes an attack a little
## less wanted for BEAT seconds (scaled by the profile's `teamwork`), so a group's barrage reads as
## a sequence instead of one flash. Who started it is not slowed by its own windup.
##
## **Reports:** at each decision an AI tells its team where it stands and how hurt it is
## (`report`). A team keeps PLACES of them; a new one takes a free slot, else one older than
## REPORT_LIFE, else the oldest of a teammate that is not hurt, so a hurt teammate stays on the
## board for a healer (`mate`, `mate_place`, `mate_health`) even in a crowd.
##
## **Spreading round a target:** at each decision an AI with teamwork notes whom it attacks
## (`note_attack`; ATTACKS per team, the oldest out). Every RECOUNT seconds the board counts, per
## target, the team's attackers noted within NOTE_LIFE and gives each a slot round the target:
## ranked by the angle it stands at, the slots RANK × 360° / count apart, the whole ring turned to
## where they already stand (the mean of their angles less their slots'), so each walks the least
## and none crosses another (`attackers`, `slot_angle`).
##
## **The call:** an AI about to start a windup with a teammate within CALL_REACH (`nearest_mate`,
## from the reports) may first glance at it and call (`call_attack`): for CALL_TIME the teammates
## within CALL_REACH of where it called are keener than ever to attack (`beat` above 1), so they
## join in, and its team calls no more for CALL_GAP seconds (`can_call`).
##
## Everything is in small packed arrays made once, a row per team: nothing is allocated after
## `_init`.

## Seconds after a teammate's windup during which another waits a little.
const BEAT: float = 0.35
## The most teams it keeps (team ids are small numbers, `core/actors`).
const TEAMS: int = 8
## Reports kept per team, and how long one counts (seconds).
const PLACES: int = 16
const REPORT_LIFE: float = 2.0
## Under this share of its most health a teammate is hurt: worth a heal.
const HURT: float = 0.7
## Attacks noted per team, how long a note counts and how often they are counted (seconds).
const ATTACKS: int = 16
const NOTE_LIFE: float = 2.0
const RECOUNT: float = 0.25
## The call: seconds it lasts, how near (pixels) a teammate must be to glance at or to join in,
## seconds before the team calls again, and how much keener a teammate that joins is (× teamwork).
const CALL_TIME: float = 0.5
const CALL_REACH: float = 160.0
const CALL_GAP: float = 3.0
const CALL_BOOST: float = 0.5

## Seconds it has run (moved on by `step`).
var clock: float = 0.0
var _last_start: PackedFloat32Array = PackedFloat32Array()
var _last_actor: PackedInt32Array = PackedInt32Array()
## The reports, PLACES per team (team × PLACES + slot): who (-1 for none), where, its health
## (a share of its most) and when.
var _who: PackedInt32Array = PackedInt32Array()
var _at: PackedVector2Array = PackedVector2Array()
var _health: PackedFloat32Array = PackedFloat32Array()
var _when: PackedFloat32Array = PackedFloat32Array()
## The attacks, ATTACKS per team (team × ATTACKS + slot): who (-1 for none), its target (instance
## id), where the target and the attacker stood, and when; from the last count, how many of the
## team were on that target (0 for a note that no longer counts) and the angle of this one's slot.
var _att_who: PackedInt32Array = PackedInt32Array()
var _att_target: PackedInt64Array = PackedInt64Array()
var _att_from: PackedVector2Array = PackedVector2Array()
var _att_at: PackedVector2Array = PackedVector2Array()
var _att_when: PackedFloat32Array = PackedFloat32Array()
var _att_count: PackedInt32Array = PackedInt32Array()
var _att_angle: PackedFloat32Array = PackedFloat32Array()
## One team's angles and ranks while it is counted.
var _theta: PackedFloat32Array = PackedFloat32Array()
var _rank: PackedInt32Array = PackedInt32Array()
var _recount_left: float = 0.0
## Each team's last call: who called, where it stood and when.
var _call_who: PackedInt32Array = PackedInt32Array()
var _call_at: PackedVector2Array = PackedVector2Array()
var _call_when: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	_last_start.resize(TEAMS)
	_last_actor.resize(TEAMS)
	_who.resize(TEAMS * PLACES)
	_at.resize(TEAMS * PLACES)
	_health.resize(TEAMS * PLACES)
	_when.resize(TEAMS * PLACES)
	_att_who.resize(TEAMS * ATTACKS)
	_att_target.resize(TEAMS * ATTACKS)
	_att_from.resize(TEAMS * ATTACKS)
	_att_at.resize(TEAMS * ATTACKS)
	_att_when.resize(TEAMS * ATTACKS)
	_att_count.resize(TEAMS * ATTACKS)
	_att_angle.resize(TEAMS * ATTACKS)
	_theta.resize(ATTACKS)
	_rank.resize(ATTACKS)
	_call_who.resize(TEAMS)
	_call_at.resize(TEAMS)
	_call_when.resize(TEAMS)
	clear()


## Forget every team's last windup, every report, every attack and every call (a new room).
func clear() -> void:
	for team in TEAMS:
		_last_start[team] = -INF
		_last_actor[team] = -1
		_call_who[team] = -1
		_call_when[team] = -INF
	_who.fill(-1)
	_when.fill(-INF)
	_att_who.fill(-1)
	_att_when.fill(-INF)
	_att_count.fill(0)


func step(delta: float) -> void:
	clock += delta
	_recount_left -= delta
	if _recount_left <= 0.0:
		_recount_left = RECOUNT
		_recount()


## The actor `who` of `team` starts a windup now.
func started(team: int, who: int) -> void:
	if team < 0 or team >= TEAMS:
		return
	_last_start[team] = clock
	_last_actor[team] = who


## How keen `who` of `team`, standing at `at`, may be to start an attack now: above 1 while a
## teammate's call within CALL_REACH of it lasts (by up to CALL_BOOST × `teamwork`), else 1, less
## just after a teammate started one (by up to `teamwork`).
func beat(team: int, who: int, teamwork: float, at: Vector2 = Vector2.INF) -> float:
	if team < 0 or team >= TEAMS or teamwork <= 0.0:
		return 1.0
	if is_calling(team) and _call_who[team] != who and at.distance_squared_to(_call_at[team]) <= CALL_REACH * CALL_REACH:
		return 1.0 + CALL_BOOST * teamwork
	if _last_actor[team] == who:
		return 1.0
	var since: float = clock - _last_start[team]
	if since >= BEAT or since < 0.0:
		return 1.0
	return 1.0 - teamwork * 0.6 * (1.0 - since / BEAT)


## The actor `who` of `team` stands at `at` with `health` (a share of its most). `hint` is the
## slot it was given last time (-1 for none), so a report usually finds its slot at once.
## Returns its slot, or -1 (no such team).
func report(team: int, who: int, at: Vector2, health: float, hint: int = -1) -> int:
	if team < 0 or team >= TEAMS or who < 0:
		return -1
	var base: int = team * PLACES
	var slot: int = hint if hint >= 0 and hint < PLACES and _who[base + hint] == who else -1
	if slot < 0:
		slot = _slot_for(base, who)
	var row: int = base + slot
	_who[row] = who
	_at[row] = at
	_health[row] = health
	_when[row] = clock
	return slot


## The actor id reported in `slot` (0 to PLACES - 1) of `team`, or -1 (none, or older than
## REPORT_LIFE).
func mate(team: int, slot: int) -> int:
	if team < 0 or team >= TEAMS or slot < 0 or slot >= PLACES:
		return -1
	var row: int = team * PLACES + slot
	if _who[row] < 0 or clock - _when[row] > REPORT_LIFE:
		return -1
	return _who[row]


## Where the actor in `slot` of `team` stood at its report.
func mate_place(team: int, slot: int) -> Vector2:
	return _at[team * PLACES + slot]


## Its health at its report (a share of its most).
func mate_health(team: int, slot: int) -> float:
	return _health[team * PLACES + slot]


## The slot in the row from `base` for `who`: its own, else a free one (or one too old to
## count), else the oldest of a teammate that is not hurt, else the oldest.
func _slot_for(base: int, who: int) -> int:
	var free: int = -1
	var oldest_well: int = -1
	var oldest: int = 0
	for slot in PLACES:
		var row: int = base + slot
		if _who[row] == who:
			return slot
		if free < 0 and (_who[row] < 0 or clock - _when[row] > REPORT_LIFE):
			free = slot
			continue
		if _health[row] >= HURT and (oldest_well < 0 or _when[row] < _when[base + oldest_well]):
			oldest_well = slot
		if _when[row] < _when[base + oldest]:
			oldest = slot
	if free >= 0:
		return free
	return oldest_well if oldest_well >= 0 else oldest


## The actor `who` of `team`, standing at `at`, attacks `target` (its instance id), which stands at
## `target_at`. `hint` is the slot it was given last time (-1 for none). Returns its slot, or -1.
func note_attack(team: int, who: int, target: int, target_at: Vector2, at: Vector2, hint: int = -1) -> int:
	if team < 0 or team >= TEAMS or who < 0:
		return -1
	var base: int = team * ATTACKS
	var slot: int = hint if hint >= 0 and hint < ATTACKS and _att_who[base + hint] == who else -1
	if slot < 0:
		slot = _attack_slot_for(base, who)
	var row: int = base + slot
	if _att_who[row] != who or _att_target[row] != target:
		# Somebody else's slot, or another target: it has no place round this one until the count.
		_att_count[row] = 0
	_att_who[row] = who
	_att_target[row] = target
	_att_from[row] = target_at
	_att_at[row] = at
	_att_when[row] = clock
	return slot


## How many of `team` attacked the target of `who` (in `slot`) at the last count, itself too; 0
## when it was not counted yet.
func attackers(team: int, slot: int, who: int) -> int:
	if team < 0 or team >= TEAMS or slot < 0 or slot >= ATTACKS:
		return 0
	var row: int = team * ATTACKS + slot
	return _att_count[row] if _att_who[row] == who else 0


## The angle (radians, from the target) of the slot round its target of the attacker in `slot`.
func slot_angle(team: int, slot: int) -> float:
	return _att_angle[team * ATTACKS + slot]


## Counts every team's attackers per target and gives each its slot round it (see the class doc).
func _recount() -> void:
	for team in TEAMS:
		var base: int = team * ATTACKS
		var live: int = 0
		for at in ATTACKS:
			var row: int = base + at
			if _att_who[row] < 0 or clock - _att_when[row] > NOTE_LIFE:
				_att_count[row] = 0
				_theta[at] = INF
				continue
			live += 1
			_theta[at] = (_att_at[row] - _att_from[row]).angle()
		if live == 0:
			continue
		# Each one's count and its rank by angle among its target's attackers.
		for at in ATTACKS:
			if _theta[at] == INF:
				continue
			var row: int = base + at
			var count: int = 0
			var rank: int = 0
			for other in ATTACKS:
				if _theta[other] == INF or _att_target[base + other] != _att_target[row]:
					continue
				count += 1
				if _theta[other] < _theta[at] or (_theta[other] == _theta[at] and _att_who[base + other] < _att_who[row]):
					rank += 1
			_att_count[row] = count
			_rank[at] = rank
		# The ring turned to where they stand: the mean of each one's angle less its slot's.
		for at in ATTACKS:
			if _theta[at] == INF:
				continue
			var row: int = base + at
			var gap: float = TAU / float(_att_count[row])
			var sum: Vector2 = Vector2.ZERO
			for other in ATTACKS:
				if _theta[other] == INF or _att_target[base + other] != _att_target[row]:
					continue
				sum += Vector2.from_angle(_theta[other] - float(_rank[other]) * gap)
			var turn: float = sum.angle() if sum.length_squared() > 0.0001 else _theta[at] - float(_rank[at]) * gap
			_att_angle[row] = wrapf(turn + float(_rank[at]) * gap, -PI, PI)


## The slot in the attack row from `base` for `who`: its own, else a free one (or one too old to
## count), else the oldest.
func _attack_slot_for(base: int, who: int) -> int:
	var free: int = -1
	var oldest: int = 0
	for slot in ATTACKS:
		var row: int = base + slot
		if _att_who[row] == who:
			return slot
		if free < 0 and (_att_who[row] < 0 or clock - _att_when[row] > NOTE_LIFE):
			free = slot
		if _att_when[row] < _att_when[base + oldest]:
			oldest = slot
	return free if free >= 0 else oldest


## True when `team` may call now: no call of its own in the last CALL_GAP seconds.
func can_call(team: int) -> bool:
	return team >= 0 and team < TEAMS and clock - _call_when[team] >= CALL_GAP


## The actor `who` of `team`, standing at `at`, calls its teammates to attack now.
func call_attack(team: int, who: int, at: Vector2) -> void:
	if team < 0 or team >= TEAMS:
		return
	_call_who[team] = who
	_call_at[team] = at
	_call_when[team] = clock


## True while a call of `team` lasts (CALL_TIME).
func is_calling(team: int) -> bool:
	return team >= 0 and team < TEAMS and clock - _call_when[team] < CALL_TIME


## When `team` last called (seconds on `clock`; -INF for never): a brain that sees a newer call
## decides at once.
func called_at(team: int) -> float:
	return _call_when[team] if team >= 0 and team < TEAMS else -INF


## Of the reports of `team` (not `who`'s), where the nearest teammate within `reach` of `at`
## stood; Vector2.INF for none.
func nearest_mate(team: int, who: int, at: Vector2, reach: float) -> Vector2:
	var best: Vector2 = Vector2.INF
	var nearest: float = reach * reach
	for slot in PLACES:
		var mate_id: int = mate(team, slot)
		if mate_id < 0 or mate_id == who:
			continue
		var there: Vector2 = _at[team * PLACES + slot]
		var far: float = at.distance_squared_to(there)
		if far <= nearest:
			nearest = far
			best = there
	return best
