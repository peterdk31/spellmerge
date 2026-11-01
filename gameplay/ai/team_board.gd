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
## Everything is in small packed arrays made once, a row of PLACES slots per team: nothing is
## allocated after `_init`.

## Seconds after a teammate's windup during which another waits a little.
const BEAT: float = 0.35
## The most teams it keeps (team ids are small numbers, `core/actors`).
const TEAMS: int = 8
## Reports kept per team, and how long one counts (seconds).
const PLACES: int = 16
const REPORT_LIFE: float = 2.0
## Under this share of its most health a teammate is hurt: worth a heal.
const HURT: float = 0.7

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


func _init() -> void:
	_last_start.resize(TEAMS)
	_last_actor.resize(TEAMS)
	_who.resize(TEAMS * PLACES)
	_at.resize(TEAMS * PLACES)
	_health.resize(TEAMS * PLACES)
	_when.resize(TEAMS * PLACES)
	clear()


## Forget every team's last windup and every report (a new room).
func clear() -> void:
	for team in TEAMS:
		_last_start[team] = -INF
		_last_actor[team] = -1
	_who.fill(-1)
	_when.fill(-INF)


func step(delta: float) -> void:
	clock += delta


## The actor `who` of `team` starts a windup now.
func started(team: int, who: int) -> void:
	if team < 0 or team >= TEAMS:
		return
	_last_start[team] = clock
	_last_actor[team] = who


## How keen `who` of `team` may be to start an attack now, 0-1: 1, less just after a teammate
## started one (by up to `teamwork`).
func beat(team: int, who: int, teamwork: float) -> float:
	if team < 0 or team >= TEAMS or _last_actor[team] == who or teamwork <= 0.0:
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
