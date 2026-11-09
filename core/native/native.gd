extends RefCounted
## The native module (native/README.md): Spellmerge's own C++, built from source for each platform
## and loaded as a GDExtension (`native/spellmerge.gdextension`, written by `ci/build/native.sh`).
## It holds only faster versions of GDScript the game already has (the projectile manager's hot
## loops, `ShotKernel`; the horde swarm's, `SwarmKernel` and `SwarmLookKernel`; the motes' trail
## births, `MoteKernel`; the deterministic maths, `DMathKernel`; a body's move against the walls, `BodyKernel`), so the game runs
## the same without it: a checkout where it was never built (slower). This file is the one place
## that asks whether it is there.
##
##     var kernel: Object = NativeScript.shot_kernel()   # null without the native module
##
## Every exported build ships the module (owner, 2026-11-02), so an exported game without it logs
## an error once (a packaging fault), and runs the GDScript.
##
## The classes are made through ClassDB by a literal name of one of the module's classes, in this
## file only (ci/smbot/rules.py, NATIVE_FILE): naming one in GDScript would not parse without the
## module.

static var _missing_told: bool = false


## A new `ShotKernel`, or null when the native module is not loaded.
static func shot_kernel() -> Object:
	if not _loaded_or_tell():
		return null
	return ClassDB.instantiate(&"ShotKernel")


## A new `SwarmKernel` (the horde swarm's loops), or null when the module is not loaded.
static func swarm_kernel() -> Object:
	if not _loaded_or_tell():
		return null
	return ClassDB.instantiate(&"SwarmKernel")


## A new `SwarmLookKernel` (the swarm look's loops), or null when the module is not loaded.
static func swarm_look_kernel() -> Object:
	if not _loaded_or_tell():
		return null
	return ClassDB.instantiate(&"SwarmLookKernel")


## A new `DMathKernel` (the deterministic maths of online-ready N7, `DMath` in core/sim/dmath.gd), or
## null when the module is not loaded.
static func dmath_kernel() -> Object:
	if not _loaded_or_tell():
		return null
	return ClassDB.instantiate(&"DMathKernel")


## A new `BodyKernel` (a body's move against the wall grid, online-ready N6: `WallSlide` in
## core/projectiles/wall_slide.gd), or null when the module is not loaded.
static func body_kernel() -> Object:
	if not _loaded_or_tell():
		return null
	return ClassDB.instantiate(&"BodyKernel")


## A new `MoteKernel` (the motes' trail births), or null when the module is not loaded.
static func mote_kernel() -> Object:
	if not _loaded_or_tell():
		return null
	return ClassDB.instantiate(&"MoteKernel")


## Whether the native module is loaded.
static func loaded() -> bool:
	return ClassDB.class_exists(&"ShotKernel")


static func _loaded_or_tell() -> bool:
	if loaded():
		return true
	if OS.has_feature("template") and not _missing_told:
		_missing_told = true
		push_error("The native module did not load (native/spellmerge.gdextension); running its GDScript, slower")
	return false
