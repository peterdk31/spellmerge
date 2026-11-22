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
## the edge between two rows settles on the lower one instead of trying the higher every few seconds.
## The band between the two shares changes nothing (vsync's frames, all near the target, count as
## fast). While `held` (the split screen's frame-time budget, `split_budget.gd`, has a rung of its
## own taken) it does not rise: those frames are fast because of the split's fallbacks.
##
## The targets are the split budget's (the owner's of 2026-11-19: 16.7 ms on the desktop, 33 ms on
## the web build), and its average follows the frames as fast.

const EffectsQualityScript := preload("res://gameplay/feel/effects_quality.gd")
const SplitBudgetScript := preload("res://gameplay/feel/split_budget.gd")

## Over this share of the target the frames are slow; at or under this one, fast.
const SLOW_SHARE: float = 1.2
const FAST_SHARE: float = 1.05
## How long slow before a row down, how long fast before a row up at first, and the longest a rise waits.
const DROP_SECONDS: float = 2.0
const RISE_SECONDS: float = 5.0
const RISE_MOST: float = 60.0
## A drop this soon after a rise: the higher row did not hold.
const TRIED_SECONDS: float = 10.0

## The row chosen now, the target (seconds a frame), the frames' average (seconds) and how long the
## frames must stay fast before the next row up (seconds). Read only.
var level: EffectsQualityScript.Level = EffectsQualityScript.Level.HIGH
var target: float = SplitBudgetScript.DESKTOP_TARGET
var average: float = 0.0
var rise_wait: float = RISE_SECONDS

var _slow: float = 0.0
var _fast: float = 0.0
var _since_rise: float = INF


func _init(web: bool = OS.has_feature("web")) -> void:
	target = SplitBudgetScript.WEB_TARGET if web else SplitBudgetScript.DESKTOP_TARGET


## Start again at `at`, nothing counted (Auto chosen anew).
func reset(at: EffectsQualityScript.Level = EffectsQualityScript.Level.HIGH) -> void:
	level = at
	average = 0.0
	rise_wait = RISE_SECONDS
	_slow = 0.0
	_fast = 0.0
	_since_rise = INF


## A drawn frame that took `delta` real seconds; `held` keeps it from rising. True when the row changed.
func step(delta: float, held: bool = false) -> bool:
	if delta <= 0.0:
		return false
	average = delta if average <= 0.0 else lerpf(average, delta, 1.0 - exp(-SplitBudgetScript.AVERAGE_SPEED * delta))
	_since_rise += delta
	if average > target * SLOW_SHARE:
		_slow += delta
		_fast = 0.0
		if _slow >= DROP_SECONDS and level != EffectsQualityScript.Level.LOW:
			if _since_rise < TRIED_SECONDS:
				rise_wait = minf(rise_wait * 2.0, RISE_MOST)
			level = EffectsQualityScript.lower(level)
			_slow = 0.0
			return true
	elif average <= target * FAST_SHARE and not held:
		_fast += delta
		_slow = 0.0
		if _fast >= rise_wait and level != EffectsQualityScript.Level.HIGH:
			level = EffectsQualityScript.higher(level)
			_fast = 0.0
			_since_rise = 0.0
			return true
	else:
		_slow = 0.0
		_fast = 0.0
	return false
