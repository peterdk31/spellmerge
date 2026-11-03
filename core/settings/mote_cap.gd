class_name MoteCap
extends RefCounted
## The "Particles" setting (docs/milestones/spell-spectacle.md, P1a): how many motes, Feel's
## single-pixel particles with no game logic, may be in the world at once (the size of its ring;
## a new mote overwrites the oldest). Its numbers live in core, so the pause menu that sets it
## (hud) and feel that uses it (gameplay) read the same ones and neither reads the other. Off
## (0) makes no motes and no nodes; the platform's default is the web's or the desktop's.

## The caps the slider steps through, smallest first: Off, Low, Medium, High.
const STOPS: Array[int] = [0, 8192, 16384, 32768]
## The words the menu shows for each stop.
const WORDS: Array[String] = ["Off", "Low", "Medium", "High"]
## The platforms' defaults (P1c sets them from measurements).
const DEFAULT_WEB: int = 8192
const DEFAULT_DESKTOP: int = 32768


## The platform's cap: the web's or the desktop's.
static func default_cap() -> int:
	return DEFAULT_WEB if OS.has_feature("web") else DEFAULT_DESKTOP


## The index in STOPS of the stop nearest `cap` (the lower one on a tie).
static func index_of(cap: int) -> int:
	var best: int = 0
	for i in STOPS.size():
		if absi(STOPS[i] - cap) < absi(STOPS[best] - cap):
			best = i
	return best


## `cap` snapped to the nearest stop.
static func snap(cap: int) -> int:
	return STOPS[index_of(cap)]


## The menu's word for `cap` ("Off", "Low", ...).
static func word_of(cap: int) -> String:
	return WORDS[index_of(cap)]
