class_name AmbienceVolume
extends RefCounted
## The "Ambience volume" setting (docs/milestones/atmosphere.md, "Settings"): how loud a room's
## sound is (atmosphere D, `RoomBase.ambience`: its beds and accents), in percent of the room's own
## levels, MIN to MAX by STEP. 0 is silent: the beds' players stop. Its numbers live in core, so the
## pause menu that sets it (hud) and feel that uses it (gameplay) read the same ones and neither
## reads the other.

const MIN: int = 0
const MAX: int = 100
const STEP: int = 10
const DEFAULT: int = 100


## `percent` snapped to a STEP inside MIN to MAX.
static func snap(percent: int) -> int:
	return clampi(roundi(float(percent) / STEP) * STEP, MIN, MAX)


## The share of the room's loudness `percent` plays at (0 to 1; times its amplitude, so in decibels
## `linear_to_db` of it: 50% is about -6 dB).
static func share_of(percent: int) -> float:
	return float(snap(percent)) / float(MAX)


## The menu's words for `percent` ("100%").
static func word_of(percent: int) -> String:
	return "%d%%" % snap(percent)
