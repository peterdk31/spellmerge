class_name MoteDensity
extends RefCounted
## The "Particle amount" setting (docs/milestones/spell-spectacle.md, P1, "Budget and
## degradation"): how many motes each moment throws, as a share of what its data says (a cue's
## `motes` part, a kind's own count). The cap (`MoteCap`) bounds how many are in the world at
## once; this thins or thickens every burst within it. Its numbers live in core, so the pause menu
## that sets it (hud) and feel that uses it (gameplay) read the same ones and neither reads the
## other.

## The shares the slider steps through, smallest first.
const STOPS: Array[float] = [0.0, 0.5, 1.0, 2.0]
## The words the menu shows for each stop.
const WORDS: Array[String] = ["None", "Half", "Full", "Double"]
## The default share (P1c sets it from measurements).
const DEFAULT: float = 1.0


## The index in STOPS of the stop nearest `density` (the lower one on a tie).
static func index_of(density: float) -> int:
	var best: int = 0
	for i in STOPS.size():
		if absf(STOPS[i] - density) < absf(STOPS[best] - density):
			best = i
	return best


## `density` snapped to the nearest stop.
static func snap(density: float) -> float:
	return STOPS[index_of(density)]


## The menu's word for `density` ("None", "Half", ...).
static func word_of(density: float) -> String:
	return WORDS[index_of(density)]
