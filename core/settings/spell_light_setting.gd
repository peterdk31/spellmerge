class_name SpellLightSetting
extends RefCounted
## The "Spell light" setting (docs/milestones/spell-spectacle.md, P3a): whether shots light the
## floor, walls and bodies round them (Feel's light buffer and the rect that applies it). On or
## off; off makes no light nodes at all. Its numbers live in core, so the pause menu that sets it
## (hud) and feel that uses it (gameplay) read the same ones and neither reads the other.

## The platforms' defaults: on everywhere (P3a measured the pass at well under a millisecond on
## llvmpipe; the web's default is the one to turn off first if its stress run says so).
const DEFAULT_WEB: bool = true
const DEFAULT_DESKTOP: bool = true


## The platform's default: the web's or the desktop's.
static func default_on() -> bool:
	return DEFAULT_WEB if OS.has_feature("web") else DEFAULT_DESKTOP
