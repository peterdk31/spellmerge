class_name EffectSlots
extends RefCounted
## The "Effect slots" setting (owner, 2026-10-27): how many effects (the glowing flares of casts,
## impacts, rings and dashes) may show at once. Its numbers live in core, so the pause menu that
## sets it (hud) and feel that uses it (gameplay) read the same ones and neither reads the other.
## 256 effects of 24 x 24 px are under 1% of what the shots draw at their cap and hold about 850
## bursts a second; fewer suit a slow machine, more a crowd of effects on a fast one.

const MIN: int = 64
const MAX: int = 1024
const STEP: int = 64
const DEFAULT: int = 256


## `slots` snapped to a STEP inside MIN to MAX.
static func snap(slots: int) -> int:
	return clampi(roundi(float(slots) / STEP) * STEP, MIN, MAX)
