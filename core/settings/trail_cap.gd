class_name TrailCap
extends RefCounted
## The "Trailed shots" setting (shot scale H4, docs/milestones/shot-scale.md): at most how many shots
## draw a trail at once (the projectile manager's `trail_cap`); past it the newest shots draw their
## core and light alone, with no sparks. The trails are what a crowd of shots costs to draw (their
## texture is sent whole each time they take their points), so fewer suit a slow machine and more a
## fast one. View only: no hit or damage reads a trail, so machines in one game may differ. Its
## numbers live in core, so the pause menu that sets it (hud) and the manager that applies it
## (`shot_trails_changed`) read the same ones.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")

## The counts the slider steps through, smallest first.
const STOPS: Array[int] = [250, 500, 1000, 2000, 3000, 4000, 6000, 8000, 10000, 15000, 20000]


## The platform's count: the web's or the desktop's.
static func default_cap() -> int:
	return ManagerScript.DEFAULT_TRAILS_WEB if OS.has_feature("web") else ManagerScript.DEFAULT_TRAILS_DESKTOP


## The index in STOPS of the stop nearest `count` (the lower one on a tie).
static func index_of(count: int) -> int:
	return SettingStops.nearest(STOPS, float(count))


## `count` snapped to the nearest stop.
static func snap(count: int) -> int:
	return STOPS[index_of(count)]
