class_name AmbienceVolume
extends RefCounted
## The "Ambience volume" setting (docs/milestones/atmosphere.md, "Settings"): how loud a room's
## sound is (atmosphere D, `RoomBase.ambience`: its beds and accents), in percent, MIN to MAX by
## STEP, heard on a perceptual curve (`share_of`). 0 is silent: the beds' players stop. Its numbers live in core, so the
## pause menu that sets it (hud) and feel that uses it (gameplay) read the same ones and neither
## reads the other.

const MIN: int = 0
const MAX: int = 100
const STEP: int = 10
const DEFAULT: int = 100


## `percent` snapped to a STEP inside MIN to MAX.
static func snap(percent: int) -> int:
	return clampi(roundi(float(percent) / STEP) * STEP, MIN, MAX)


## The quietest stop above silence (STEP, 10%) is this many decibels under the room's own level;
## the stops between are even in decibels up to 0 dB at MAX.
const QUIETEST_DB: float = -40.0


## The share of the room's amplitude `percent` plays at (0 to 1), on a perceptual curve: even steps
## in decibels from QUIETEST_DB at 10% to 0 dB at 100% (each stop of 10% about 4.4 dB louder, as an
## ear hears even steps), and 0% silent. In decibels it is `linear_to_db` of this.
static func share_of(percent: int) -> float:
	var at: int = snap(percent)
	if at <= MIN:
		return 0.0
	var span: float = float(MAX - STEP)
	var db: float = QUIETEST_DB * (1.0 - float(maxi(at - STEP, 0)) / span) if span > 0.0 else 0.0
	return db_to_linear(db)


## The menu's words for `percent` ("100%").
static func word_of(percent: int) -> String:
	return "%d%%" % snap(percent)
