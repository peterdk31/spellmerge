extends RefCounted
## How a cue made at one size plays at another (`CueBase.size_ref`; the owner, 2026-11-18: a blast
## sounds and looks as big as it is). Its flashes, marks and how far its motes fly already follow
## its `size` by their `reach`; a cue with a `size_ref` also grows the rest by how many times its
## reference size it is played at (`factor`, clamped to LEAST..MOST): its motes' counts, its flashes'
## seconds, its shake and kick, and its sound, deeper and louder when bigger. One rule, read by
## `Feel.play_cue`, so any sized moment (an exploding barrel, a slam) can take it by data.

## The least and most times its reference size a cue grows by (a tiny blast still reads as one; a
## huge one does not shake the screen apart).
const LEAST: float = 0.5
const MOST: float = 3.0
## Powers of the factor each grows by: counts as the factor (more of them over a wider ring),
## seconds and shake slower than it.
const COUNT_POWER: float = 1.0
const SECONDS_POWER: float = 0.35
const SHAKE_POWER: float = 0.5
## Its sound: pitch times the factor to this power (twice as big, about a fifth lower), and this
## many decibels louder each time it doubles, within the volume range.
const PITCH_POWER: float = -0.3
const DB_PER_DOUBLING: float = 3.0
const MOST_DB: float = 5.0


## How many times its reference size `size_ref` a cue played at `size` is (1: no reference, or no size).
static func factor(size_ref: float, size: float) -> float:
	if size_ref <= 0.0 or size <= 0.0:
		return 1.0
	return clampf(size / size_ref, LEAST, MOST)


static func counts(grow: float) -> float:
	return pow(grow, COUNT_POWER)


static func seconds(grow: float) -> float:
	return pow(grow, SECONDS_POWER)


static func shake(grow: float) -> float:
	return pow(grow, SHAKE_POWER)


static func pitch(grow: float) -> float:
	return pow(grow, PITCH_POWER)


static func volume(grow: float) -> float:
	if grow == 1.0:
		return 0.0
	return clampf(DB_PER_DOUBLING * log(grow) / log(2.0), -MOST_DB, MOST_DB)
