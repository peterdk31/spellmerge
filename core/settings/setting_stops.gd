class_name SettingStops
extends RefCounted
## What every stepped setting does with its stops (a slider through a list of values, smallest
## first: `MoteCap`, `MoteDensity`, `ShotCap`): the stop nearest a value, so a setting script holds
## only its numbers and words (docs/milestones/spell-spectacle-2.md, S1).


## The index in `stops` (numbers, smallest first) of the stop nearest `value`, the lower one on a
## tie; 0 for no stops.
static func nearest(stops: Array, value: float) -> int:
	var best: int = 0
	for i in stops.size():
		if absf(float(stops[i]) - value) < absf(float(stops[best]) - value):
			best = i
	return best
