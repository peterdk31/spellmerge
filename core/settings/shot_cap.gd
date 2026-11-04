class_name ShotCap
extends RefCounted
## The "Max shots" setting (owner, 2026-11-02): the projectile manager's global cap on live shots
## (`Projectiles.get_cap()`; at the cap the oldest shot of the budget that owns the most is
## dropped). Its numbers live in core, so the pause menu that sets it (hud) and the manager that
## applies it (`projectile_cap_changed`) read the same ones. The default is the platform's
## (`ProjectileManager.DEFAULT_CAP_WEB`, `DEFAULT_CAP_DESKTOP`); fewer suit a slow machine or GPU
## (the trails grow with the shots), more a fast one. The top, 50,000, is the owner's (2026-11-02):
## far past what a frame holds today, for trying how far a machine goes.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")

## The caps the slider steps through, smallest first.
const STOPS: Array[int] = [250, 500, 750, 1000, 1500, 2000, 3000, 4000, 6000, 8000, 10000, 15000, 20000, 30000, 40000, 50000]


## The platform's cap: the web's or the desktop's.
static func default_cap() -> int:
	return ManagerScript.DEFAULT_CAP_WEB if OS.has_feature("web") else ManagerScript.DEFAULT_CAP_DESKTOP


## The index in STOPS of the stop nearest `cap` (the lower one on a tie).
static func index_of(cap: int) -> int:
	return SettingStops.nearest(STOPS, float(cap))


## `cap` snapped to the nearest stop.
static func snap(cap: int) -> int:
	return STOPS[index_of(cap)]
