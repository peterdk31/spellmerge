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

## Seconds after a teammate's windup during which another waits a little.
const BEAT: float = 0.35
## The most teams it keeps (team ids are small numbers, `core/actors`).
const TEAMS: int = 8

## Seconds it has run (moved on by `step`).
var clock: float = 0.0
var _last_start: PackedFloat32Array = PackedFloat32Array()
var _last_actor: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	_last_start.resize(TEAMS)
	_last_actor.resize(TEAMS)
	clear()


## Forget every team's last windup (a new room).
func clear() -> void:
	for team in TEAMS:
		_last_start[team] = -INF
		_last_actor[team] = -1


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
