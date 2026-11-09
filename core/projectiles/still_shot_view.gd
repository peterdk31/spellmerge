class_name StillShotView
extends RefCounted
## What a viewer may know of the still shots of one card body's batch drawn this frame
## (docs/milestones/carrier-looks-fixes.md, phase 1): the projectile manager fills one for each
## watched batch from the rows it drew (`ProjectileManager.watch_body`, `still_shots_drawn`,
## `read_still_rows`), so whoever draws more of a still card (Feel's still motes) reads places, sizes
## and clocks, never the manager's GPU rows. One per watched batch, refilled each frame it draws and
## grown only when a frame draws more than ever before: reading it allocates nothing. Read it when it
## is handed out; it is the manager's, and changes next frame.

## View only: the manager's drawing fills it, the simulation never reads it (core/sim/README.md).
const VIEW_ONLY: bool = true

## The card body its shots are drawn by (`ProjectileManager.register_body`, from 1), and whether this
## is the enemy ramp's batch of the pair.
var body: int = 0
var enemy: bool = false
## The manager's clock when they were drawn (`sim_time`).
var time: float = 0.0
## How many shots are in it this frame (each piece of a solid one, a wall's, is one): the first
## `count` of each array below.
var count: int = 0
## Where each is drawn (its quad's middle, world pixels).
var at: PackedVector2Array = PackedVector2Array()
## The way its quad's +x runs on the screen, a unit vector: along a solid shot's row (a wall's seam).
var across: PackedVector2Array = PackedVector2Array()
## Its hit size as drawn, in pixels: its quad's size x `ProjectileManager.STILL_HIT`, the unit a
## still card's look is shaped in (`FormBase.look_shape`).
var reach: PackedFloat32Array = PackedFloat32Array()
## Its hat ramp (0-3) and its look's bits (`ProjectileManager.ramp_look`: the kinds, the enemy ramp's
## flag), as its shader reads them.
var ramp: PackedInt32Array = PackedInt32Array()
var look: PackedInt32Array = PackedInt32Array()
## Its core colour (its first infusion's tint).
var core: PackedColorArray = PackedColorArray()
## Its still clock (`ProjectileManager.still_code`): seconds since it was placed (STILL_START once
## past them) and seconds of life left (STILL_END while it has more).
var since: PackedFloat32Array = PackedFloat32Array()
var left: PackedFloat32Array = PackedFloat32Array()


## Room for `wanted` shots, keeping what it has: grows, never shrinks.
func hold(wanted: int) -> void:
	if at.size() >= wanted:
		return
	at.resize(wanted)
	across.resize(wanted)
	reach.resize(wanted)
	ramp.resize(wanted)
	look.resize(wanted)
	core.resize(wanted)
	since.resize(wanted)
	left.resize(wanted)
