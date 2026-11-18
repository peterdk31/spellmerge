class_name AmbientParticles
extends RefCounted
## The "Ambient particles" setting (docs/milestones/atmosphere.md, "Settings"): whether a room's air
## gives off its drifting dust (atmosphere B, `RoomBase.air`). The dust is lit only, so it also
## needs "Dynamic lighting" (`SpellLightSetting`; the menu shows it greyed without it). Off, no air
## mote is given off (those in the air live out their short lives). Its numbers live in core, so the
## pause menu that sets it (hud) and feel that uses it (gameplay) read the same ones and neither
## reads the other.

## The platforms' defaults: on everywhere (the dust is at most an eighth of the motes' ring).
const DEFAULT_WEB: bool = true
const DEFAULT_DESKTOP: bool = true


## The platform's default: the web's or the desktop's.
static func default_on() -> bool:
	return DEFAULT_WEB if OS.has_feature("web") else DEFAULT_DESKTOP
