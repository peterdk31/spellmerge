extends RefCounted
## The hits' share of the motes' rows (the owner, 2026-11-05: a lone cast's impacts stay whole
## beside a Storm's, as its tail does since #567). A hit's motes (a shot's shed on a body or a wall,
## a cue's `often` sparks, a status's motes) are one spray, and the sprays of a frame are shared by
## group, the caster's staff (the projectile manager's `group_of`; OTHER for a hit of no one's,
## STATUSES for the statuses' motes): a group whose sprays fit an even share of the frame's hit rows
## gets them all, and the crowded groups share what is left alike.
##
## A thinned group's hits are a fair random subset that spray whole (each hit rolls its group's
## `chance` once: all of its motes or none), never every hit a little: a storm keeps the look of
## sprays, only fewer of them. The shares are planned at each step from the frame before (as the
## tails are, `_plan_groups`): a group's ask is its hits then times the rows a spray of it took
## (`_per_spray`, SPRAY_ROWS until one is seen), so nothing waits for the frame's end. A group new
## since the last plan sprays whole, and a group not thinned beside one that is (`beside_crowd`) may take the pool's
## FRESH_ROWS of the moments' rows too, so a lone cast's hit is never cut by a crowd's sprays; a
## thinned group stops at its share of rows (`_allow`) if its rolls run over it.
##
## The pool (`mote.gd`) owns one: `opens` and `spent` from `open_hit` and `close_hit`, `plan` from
## `step`. Nothing is allocated while playing.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## The groups: the projectile manager's (an actor's staff), then the hits of no one's and the
## statuses' motes.
const OTHER: int = ProjectilesScript.GROUPS
const STATUSES: int = ProjectilesScript.GROUPS + 1
const GROUPS: int = ProjectilesScript.GROUPS + 2
## A group's rows a spray before one of its sprays is seen.
const SPRAY_ROWS: float = 12.0

## Hits left out by their group's share since this was made (for tests and the benchmarks).
var shared_out: int = 0

## Per group: this frame's hits, the rows its sprays took and its sprays (from the frame it was
## last touched in, `_frame`), the rows a spray of it takes, its ask at the last plan, and this
## frame's chance to spray and most rows (INF: whole).
var _hits: PackedInt32Array = PackedInt32Array()
var _rows: PackedInt32Array = PackedInt32Array()
var _sprays: PackedInt32Array = PackedInt32Array()
var _frame: PackedInt32Array = PackedInt32Array()
var _per_spray: PackedFloat32Array = PackedFloat32Array()
var _ask: PackedFloat32Array = PackedFloat32Array()
var _chance: PackedFloat32Array = PackedFloat32Array()
var _allow: PackedFloat32Array = PackedFloat32Array()
## The frame (counted by `plan`), the groups touched in it, the groups thinned by the last plan, and
## the scratch `fair_level` reads, sorted.
var _frame_no: int = 1
var _touched: PackedInt32Array = PackedInt32Array()
var _touched_count: int = 0
var _thinned: PackedInt32Array = PackedInt32Array()
var _thinned_count: int = 0
var _sort: PackedFloat32Array = PackedFloat32Array()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	_hits.resize(GROUPS)
	_rows.resize(GROUPS)
	_sprays.resize(GROUPS)
	_frame.resize(GROUPS)
	_touched.resize(GROUPS)
	_thinned.resize(GROUPS)
	_per_spray.resize(GROUPS)
	_ask.resize(GROUPS)
	_chance.resize(GROUPS)
	_allow.resize(GROUPS)
	_hits.fill(0)
	_rows.fill(0)
	_sprays.fill(0)
	_frame.fill(0)
	_per_spray.fill(SPRAY_ROWS)
	_ask.fill(0.0)
	_chance.fill(1.0)
	_allow.fill(INF)
	_rng.seed = 0x5EED


## A hit of `group` (0 to GROUPS - 1): counted toward its next ask; true when it sprays (its
## group's chance, while its rows last).
func opens(group: int) -> bool:
	if _frame[group] != _frame_no:
		_frame[group] = _frame_no
		_hits[group] = 0
		_rows[group] = 0
		_sprays[group] = 0
		_touched[_touched_count] = group
		_touched_count += 1
	_hits[group] += 1
	var chance: float = _chance[group]
	if (chance < 1.0 and _rng.randf() >= chance) or float(_rows[group]) >= _allow[group]:
		shared_out += 1
		return false
	return true


## A spray of `group` took `rows` (`spray`: a hit that `opens` let through; false for more rows of
## one already counted, its damage's part).
func spent(group: int, rows: int, spray: bool = true) -> void:
	if _frame[group] != _frame_no:
		return
	_rows[group] += rows
	_sprays[group] += 1 if spray else 0


## At a step: share the next frame's `budget` hit rows out among the groups touched this frame (see
## the top). The groups not touched spray whole.
func plan(budget: int) -> void:
	for i in _thinned_count:
		var group: int = _thinned[i]
		_chance[group] = 1.0
		_allow[group] = INF
	_thinned_count = 0
	if _sort.size() != _touched_count:
		_sort.resize(_touched_count)
	for i in _touched_count:
		var group: int = _touched[i]
		if _sprays[group] > 0:
			_per_spray[group] = float(_rows[group]) / float(_sprays[group])
		_ask[group] = float(_hits[group]) * _per_spray[group]
		_sort[i] = _ask[group]
	_sort.sort()
	var level: float = ProjectilesScript.fair_level(_sort, float(maxi(budget, 0)))
	if level < INF:
		for i in _touched_count:
			var group: int = _touched[i]
			if _ask[group] > level:
				_chance[group] = level / _ask[group]
				_allow[group] = level
				_thinned[_thinned_count] = group
				_thinned_count += 1
	_touched_count = 0
	_frame_no += 1


## The chance a hit of `group` sprays this frame (1: whole; for tests and the benchmarks).
func chance_of(group: int) -> float:
	return _chance[group]


## Whether a hit of `group` may take the pool's FRESH_ROWS of the moments' rows this frame: it is
## not thinned (new, or its ask fits its share) while another group is (a crowd it sprays beside).
func beside_crowd(group: int) -> bool:
	return _thinned_count > 0 and _chance[group] >= 1.0
