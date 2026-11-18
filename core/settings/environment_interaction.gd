class_name EnvironmentInteraction
extends RefCounted
## The "Environment interaction" setting (docs/milestones/atmosphere.md, "Settings"): whether the
## world takes notice of the shots and the blasts (atmosphere E, `gameplay/feel/stirs.gd`): the
## room's lights duck and lean, the ground cover, the dust and the mist are pushed by a shot's wake
## and a blast's wave. Off, the stirs read no shot and start no blast, so what was stirred eases
## back to rest and every shader is handed a still field. Its numbers live in core, so the pause menu
## that sets it (hud) and feel that uses it (gameplay) read the same ones and neither reads the other.

## The platforms' defaults: on everywhere (0.36 ms a frame at worst).
const DEFAULT_WEB: bool = true
const DEFAULT_DESKTOP: bool = true


## The platform's default: the web's or the desktop's.
static func default_on() -> bool:
	return DEFAULT_WEB if OS.has_feature("web") else DEFAULT_DESKTOP
