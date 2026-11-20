extends RefCounted
## How much quieter a hit sound plays when it comes again soon (docs/milestones/sound.md, "Hits by
## carrier"): the second hit of one sound within WINDOW seconds of the one before plays STEP
## decibels under it, the third twice that, down to FLOOR, so a stream of hits (a beam ticking,
## four players' bolts landing) is a soft patter, not a row of knocks. A gap of WINDOW lets it
## come back to full. Feel asks `volume` once a hit sound, on its own clock (real time: sound is
## view only).
##
## One entry a sound id, made the first time that id is heard and then reused: a hit allocates
## nothing after its sound's first.

## The most seconds between two hits of one sound for the second to be a repeat.
const WINDOW: float = 0.3
## Decibels each repeat plays under the one before.
const STEP: float = -3.0
## The quietest a repeat plays (decibels).
const FLOOR: float = -9.0

## When each sound was last played, and how many repeats it has had in a row.
var _last: Dictionary[StringName, float] = {}
var _repeats: Dictionary[StringName, int] = {}


## The volume (decibels, 0 or under) for `sound` played at `now` (seconds, any clock that only goes
## forward), and it counts as played. A clock that started again (`now` before the last) is a fresh start.
func volume(sound: StringName, now: float) -> float:
	var last: float = float(_last.get(sound, -INF))
	var repeats: int = 0
	if now >= last and now - last <= WINDOW:
		repeats = int(_repeats.get(sound, 0)) + 1
	_last[sound] = now
	_repeats[sound] = repeats
	return maxf(STEP * float(repeats), FLOOR)
