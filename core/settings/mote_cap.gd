class_name MoteCap
extends RefCounted
## The "Particles" setting (docs/milestones/spell-spectacle.md, P1a): how many motes, Feel's
## single-pixel particles with no game logic, may be in the world at once (the size of its ring;
## a new mote overwrites the oldest). Its numbers live in core, so the pause menu that sets it
## (hud) and feel that uses it (gameplay) read the same ones and neither reads the other. There
## is no Off: every particle is a mote (docs/milestones/spell-spectacle-2.md, S3; the owner,
## 2026-11-04), so the smallest stop is a Minimal ring, and a saved 0 (Off before S3) loads as it.
## The platform's default is the web's or the desktop's.

## The caps the slider steps through, smallest first: Minimal, Low, Medium, High.
const STOPS: Array[int] = [2048, 8192, 16384, 32768]
## The words the menu shows for each stop.
const WORDS: Array[String] = ["Minimal", "Low", "Medium", "High"]
## The platforms' defaults, measured in P1c (docs/DECISIONS.md, 2026-11-04): the web's ring of
## 8,192 costs about nothing on a laptop's Intel UHD, the desktop's 32,768 about 2 ms of it when
## full, and the sandbox storm's sheds and cues (Motes.FRAME_ROWS a frame, the longest life 2.5 s)
## fill most of the desktop's.
const DEFAULT_WEB: int = 8192
const DEFAULT_DESKTOP: int = 32768


## The platform's cap: the web's or the desktop's.
static func default_cap() -> int:
	return DEFAULT_WEB if OS.has_feature("web") else DEFAULT_DESKTOP


## The index in STOPS of the stop nearest `cap` (the lower one on a tie).
static func index_of(cap: int) -> int:
	return SettingStops.nearest(STOPS, float(cap))


## `cap` snapped to the nearest stop.
static func snap(cap: int) -> int:
	return STOPS[index_of(cap)]


## The menu's word for `cap` ("Minimal", "Low", ...).
static func word_of(cap: int) -> String:
	return WORDS[index_of(cap)]
