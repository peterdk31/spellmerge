class_name FloorMarks
extends RefCounted
## The "Floor marks" setting (docs/milestones/spell-spectacle.md, P2a): whether Feel keeps the
## room's mark layer, where scorches, cracks and frost stay on the floor until the room ends. Its
## numbers live in core, so the pause menu that sets it (hud) and feel that uses it (gameplay) read
## the same ones and neither reads the other. Off makes no layer and no nodes.

## The platforms' defaults (a layer is one texture the size of the room, drawn only on a frame a
## mark lands; P2's measurements may turn the web's off).
const DEFAULT_WEB: bool = true
const DEFAULT_DESKTOP: bool = true


## The platform's default: the web's or the desktop's.
static func default_on() -> bool:
	return DEFAULT_WEB if OS.has_feature("web") else DEFAULT_DESKTOP
