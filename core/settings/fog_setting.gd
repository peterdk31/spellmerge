class_name FogSetting
extends RefCounted
## The "Fog" setting (docs/milestones/atmosphere.md, "Settings"): whether Feel draws a room's low
## floor mist (atmosphere F, `RoomBase.mist`). It needs "Dynamic lighting" (`SpellLightSetting`):
## the mist is lit by the light's buffer and is not drawn without it, and the menu shows it greyed.
## Off makes no mist node. Its numbers live in core, so the pause menu that sets it (hud) and feel
## that uses it (gameplay) read the same ones and neither reads the other.

## The platforms' defaults: on everywhere (about 3 ms a frame on a CPU rasteriser, the web's to turn
## off first if its stress run says so).
const DEFAULT_WEB: bool = true
const DEFAULT_DESKTOP: bool = true


## The platform's default: the web's or the desktop's.
static func default_on() -> bool:
	return DEFAULT_WEB if OS.has_feature("web") else DEFAULT_DESKTOP
