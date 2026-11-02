extends RefCounted
## The native module (native/README.md): Spellmerge's own C++, built from source for each platform
## and loaded as a GDExtension (`native/spellmerge.gdextension`, written by `ci/build/native.sh`).
## It holds only faster versions of GDScript the game already has (the projectile manager's hot
## loops, `ShotKernel`; the horde swarm's, `SwarmKernel`), so the game runs the same without it: a checkout where it was never built,
## a platform it was not built for. This file is the one place that asks whether it is there.
##
##     var kernel: Object = NativeScript.shot_kernel()   # null without the native module
##
## The class is made through ClassDB by a literal name of one of the module's classes, in this file
## only (ci/smbot/rules.py, NATIVE_FILE): naming it in GDScript would not parse without the module.


## A new `ShotKernel`, or null when the native module is not loaded.
static func shot_kernel() -> Object:
	if not ClassDB.class_exists(&"ShotKernel"):
		return null
	return ClassDB.instantiate(&"ShotKernel")


## A new `SwarmKernel` (the horde swarm's and its look's loops), or null when the module is not loaded.
static func swarm_kernel() -> Object:
	if not ClassDB.class_exists(&"SwarmKernel"):
		return null
	return ClassDB.instantiate(&"SwarmKernel")


## Whether the native module is loaded.
static func loaded() -> bool:
	return ClassDB.class_exists(&"ShotKernel")
