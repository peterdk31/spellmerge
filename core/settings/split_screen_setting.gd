class_name SplitScreenSetting
extends RefCounted
## The "Split screen" setting (the owner, 2026-11-19): how this machine's screen splits once its
## players part. DYNAMIC (the default) is the Voronoi split (connected biomes CB6: a view a group,
## cut along the bisectors between where the groups stand); EQUAL is equal panes, a view a player:
## two players left and right halves, three or four a 2×2 grid of quarters (with three, the fourth
## quarter is empty). In both, players near each other share the one picture. A view setting of
## this machine alone: saved with the other settings (`user://`), never in the simulation (no
## hash, no `SessionRules`, no `InputFrame`). Its numbers live in core, so the pause menu that sets
## it (hud) and feel that uses it (gameplay) read the same ones and neither reads the other.

const DYNAMIC: int = 0
const EQUAL: int = 1
## The default: the Voronoi split.
const DEFAULT: int = DYNAMIC
## The saved setting's key.
const KEY: StringName = &"split_screen"
## The menu's words for each mode, by mode.
const WORDS: Array[String] = ["Dynamic", "Equal"]


## `mode` as a known mode (a saved value from elsewhere: the default).
static func snap(mode: int) -> int:
	return mode if mode >= 0 and mode < WORDS.size() else DEFAULT


## The menu's word for `mode`.
static func word_of(mode: int) -> String:
	return WORDS[snap(mode)]
