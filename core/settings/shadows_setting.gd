class_name ShadowsSetting
extends RefCounted
## The "Shadows" setting (docs/milestones/atmosphere.md, "Settings"): whether the light is blocked
## by the room's standing walls and pillars and the bodies cast shadows (atmosphere C). It needs
## "Dynamic lighting" (`SpellLightSetting`): with no light there is nothing to block, and the menu
## shows it greyed. Off, Feel makes no shadow batch and hands the light no blockers, and a body's
## own drawn shadow (the staff's) shows again. Its numbers live in core, so the pause menu that sets
## it (hud) and feel that uses it (gameplay) read the same ones and neither reads the other.

## The platforms' defaults: on everywhere, as the light is.
const DEFAULT_WEB: bool = true
const DEFAULT_DESKTOP: bool = true


## The platform's default: the web's or the desktop's.
static func default_on() -> bool:
	return DEFAULT_WEB if OS.has_feature("web") else DEFAULT_DESKTOP
