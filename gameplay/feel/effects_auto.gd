extends RefCounted
## The "Effects: Auto" setting's watcher (the owner's choice of 2026-11-21; `EffectsSetting.AUTO`):
## it reads the drawn frames' real times and chooses the row of `EffectsQuality` the effects are drawn
## at, a row down while frames stay slow, a row up while they stay fast. View only, on real time: it
## reads the drawn frames' times, nothing in the simulation, and the row changes nothing in the game.
##
## Hysteresis, so it never flips back and forth: a row down after the frames' average has been over
## SLOW_SHARE of the target for DROP_SECONDS; a row up after it has been at or under FAST_SHARE of the
## target for `rise_wait` (RISE_SECONDS at first). A row it rose to that drops again within
## TRIED_SECONDS did not hold: the next rise waits twice as long (up to RISE_MOST), so a machine on
## the edge between two rows settles on the lower one instead of trying the higher every few seconds;
## a rise that holds TRIED_SECONDS halves the wait again (down to RISE_SECONDS), so a busy fight
## early on does not slow every rise for the rest of the session. A drop that did not make the
## frames faster (the average not FASTER_SHARE of what it was when it dropped, DROP_SECONDS on: a
## frame cap, a slow display, a load the effects are not the cost of) is undone, and no row is
## dropped again until the frames have been fast for DROP_SECONDS, or have grown FUTILE_GROWTH times
## slower than then, or RISE_MOST has gone by. The band between the two shares changes nothing
## (vsync's frames, all near the target, count as fast). Feel holds it (`step`'s `hold_rise`,
## `hold_drop`) while the split screen's frame-time budget (`split_budget.gd`) acts: held from rising,
## a rise it would make is `rise_blocked` instead (Feel has the budget give a rung back, a try like a
## rise: `failed_try` when the budget takes it again soon).
##
## The targets are the split budget's (the owner's of 2026-11-19: 16.7 ms on the desktop, 33 ms on
## the web build), never under the frame time the display or a frame cap allows (`set_floor`), and
## its average follows the frames as fast.

const EffectsQualityScript := preload("res://gameplay/feel/effects_quality.gd")
const SplitBudgetScript := preload("res://gameplay/feel/split_budget.gd")

## Over this share of the target the frames are slow; at or under this one, fast.
const SLOW_SHARE: float = 1.2
const FAST_SHARE: float = 1.05
## How long slow before a row down, how long fast before a row up at first, and the longest a rise waits.
const DROP_SECONDS: float = 2.0
const RISE_SECONDS: float = 5.0
const RISE_MOST: float = 60.0
## A drop this soon after a rise: the higher row did not hold (and a rise held this long halves the wait).
const TRIED_SECONDS: float = 10.0
## A drop made the frames faster when their average came to at most this share of what it was.
const FASTER_SHARE: float = 0.95
## A drop that did not help is tried again once the frames are this many times slower than then.
const FUTILE_GROWTH: float = 1.25

## The row chosen now, the target (seconds a frame), the frames' average (seconds) and how long the
## frames must stay fast before the next row up (seconds). Read only.
var level: EffectsQualityScript.Level = EffectsQualityScript.Level.HIGH
var target: float = SplitBudgetScript.DESKTOP_TARGET
var average: float = 0.0
var rise_wait: float = RISE_SECONDS
## True after a step in which it would have risen but was held (`hold_rise`); Feel clears it.
var rise_blocked: bool = false

var _base_target: float = SplitBudgetScript.DESKTOP_TARGET
var _slow: float = 0.0
var _fast: float = 0.0
var _since_rise: float = INF
## Whether the last rise has not been dropped since (so it held, once TRIED_SECONDS on).
var _rise_holding: bool = false
## How long the frames have been fast, held or not (what clears `_futile`).
var _fast_any: float = 0.0
## The average when the last drop was made, and how long until it is judged (0: none to judge).
var _dropped_at: float = 0.0
var _judging: float = 0.0
## A drop did not help: none again until the frames have been fast.
var _futile: bool = false
var _futile_for: float = 0.0


func _init(web: bool = OS.has_feature("web")) -> void:
	_base_target = SplitBudgetScript.WEB_TARGET if web else SplitBudgetScript.DESKTOP_TARGET
	target = _base_target


## The shortest frame the display or a frame cap allows (seconds; 0: none known): the target is never
## under it, so a 50 Hz display's 20 ms frames are not slow.
func set_floor(seconds: float) -> void:
	target = maxf(_base_target, seconds)


## Start again at `at`, nothing counted (Auto chosen anew).
func reset(at: EffectsQualityScript.Level = EffectsQualityScript.Level.HIGH) -> void:
	level = at
	average = 0.0
	rise_wait = RISE_SECONDS
	_slow = 0.0
	_fast = 0.0
	_since_rise = INF
	_judging = 0.0
	_futile = false
	_rise_holding = false
	_fast_any = 0.0
	rise_blocked = false


## A try at a higher step that did not hold (the split budget took back the rung Feel had it give
## back): the next waits twice as long, if it came within TRIED_SECONDS.
func failed_try() -> void:
	if _rise_holding and _since_rise < TRIED_SECONDS:
		rise_wait = minf(rise_wait * 2.0, RISE_MOST)
	_rise_holding = false


## A drawn frame that took `delta` real seconds; `hold_rise` keeps it from rising, `hold_drop` from
## dropping. True when the row changed.
func step(delta: float, hold_rise: bool = false, hold_drop: bool = false) -> bool:
	if delta <= 0.0:
		return false
	average = delta if average <= 0.0 else lerpf(average, delta, 1.0 - exp(-SplitBudgetScript.AVERAGE_SPEED * delta))
	var before: float = _since_rise
	_since_rise += delta
	if before < TRIED_SECONDS and _since_rise >= TRIED_SECONDS and _rise_holding:
		rise_wait = maxf(rise_wait * 0.5, RISE_SECONDS)
	if _futile:
		_futile_for += delta
		if _futile_for >= RISE_MOST or average > _dropped_at * FUTILE_GROWTH:
			_futile = false
	if _judging > 0.0:
		_judging -= delta
		if _judging <= 0.0 and average > _dropped_at * FASTER_SHARE and level != EffectsQualityScript.Level.HIGH:
			level = EffectsQualityScript.higher(level)
			_futile = true
			_futile_for = 0.0
			_slow = 0.0
			_fast = 0.0
			return true
	if average > target * SLOW_SHARE:
		_slow += delta
		_fast = 0.0
		_fast_any = 0.0
		if hold_drop or _judging > 0.0:
			# The split budget acts first (its rung given time to help), or the last drop is judged.
			_slow = 0.0
		if _slow >= DROP_SECONDS and level != EffectsQualityScript.Level.LOW and not _futile:
			failed_try()
			level = EffectsQualityScript.lower(level)
			_slow = 0.0
			_dropped_at = average
			_judging = DROP_SECONDS
			return true
	elif average <= target * FAST_SHARE:
		_fast += delta
		_fast_any += delta
		_slow = 0.0
		if _fast_any >= DROP_SECONDS:
			_futile = false
		if hold_rise and _fast >= rise_wait:
			# The split's fallbacks taken: their rung given back first (Feel), counted as a try.
			rise_blocked = true
			_fast = 0.0
			_since_rise = 0.0
			_rise_holding = true
			return false
		if _fast >= rise_wait and level != EffectsQualityScript.Level.HIGH and not hold_rise:
			level = EffectsQualityScript.higher(level)
			_fast = 0.0
			_since_rise = 0.0
			_rise_holding = true
			_judging = 0.0
			return true
	else:
		_slow = 0.0
		_fast = 0.0
		_fast_any = 0.0
	return false
