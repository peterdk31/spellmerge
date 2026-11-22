class_name EffectsSetting
extends RefCounted
## The "Effects" setting (the owner's choice of 2026-11-21): how much the screen's effects cost on this
## machine. LOW, MEDIUM and HIGH draw a row of `EffectsQuality` each (gameplay/feel/effects_quality.gd:
## the light's cells, the mist's layers, the air's share); AUTO (the default) chooses the row by the
## drawn frames' times, a row down while frames stay slow and back up while they stay fast
## (gameplay/feel/effects_auto.gd). Whether each effect is drawn at all stays its own setting. A view
## setting of this machine alone: saved with the other settings (`user://`), never in the simulation
## (no hash, no `SessionRules`, no `InputFrame`). Its numbers live in core, so the pause menu that sets
## it (hud) and feel that uses it (gameplay) read the same ones and neither reads the other.

const AUTO: int = 0
const LOW: int = 1
const MEDIUM: int = 2
const HIGH: int = 3
## The default: the frames choose.
const DEFAULT: int = AUTO
## The saved setting's key.
const KEY: StringName = &"effects"
## The menu's words for each mode, by mode (the menu steps through them in this order).
const WORDS: Array[String] = ["Auto", "Low", "Medium", "High"]


## `mode` as a known mode (a saved value from elsewhere: the default).
static func snap(mode: int) -> int:
	return mode if mode >= 0 and mode < WORDS.size() else DEFAULT


## The menu's word for `mode`.
static func word_of(mode: int) -> String:
	return WORDS[snap(mode)]
