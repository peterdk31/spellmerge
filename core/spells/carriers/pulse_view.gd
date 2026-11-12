class_name PulseView
extends RefCounted
## What a viewer may know of the live Pulse rings this frame (props W9a): the Pulse carrier fills
## one (`CarrierPulse.read_view`), so the area that draws them (Feel's `pulse_rings.gd`) reads one
## typed thing, not the carrier's rows or getters by name, as the portals' look reads a
## `PortalView`. The rings' arrays hold `rings`; ring `r`'s segments are `stop[r * SEGMENTS + k]`.
## Grown only when a frame has more than ever before: filling it allocates nothing. Read it when
## filled; it changes next frame.

## View only: the simulation never reads it (core/sim/README.md).
const VIEW_ONLY: bool = true
const SEGMENTS: int = SpellLimits.PULSE_SEGMENTS

var rings: int = 0
## Each ring's centre, its radius now (the middle of its edge), its caster (its ramp), its spell's
## tag (its cards' motes), look bits and core colour.
var centre: PackedVector2Array = PackedVector2Array()
var radius: PackedFloat32Array = PackedFloat32Array()
var caster: PackedInt32Array = PackedInt32Array()
var tag: PackedInt64Array = PackedInt64Array()
var look: PackedInt32Array = PackedInt32Array()
var core: PackedColorArray = PackedColorArray()
## How far each of its segments goes out before it stopped (a wall, or a body it struck), INF
## when nothing stopped it (`CarrierPulse._pu_stop`).
var stop: PackedFloat32Array = PackedFloat32Array()


## Room for `wanted` rings: grows, never shrinks.
func hold(wanted: int) -> void:
	if centre.size() >= wanted:
		return
	var room: int = maxi(wanted, centre.size() * 2)
	centre.resize(room)
	radius.resize(room)
	caster.resize(room)
	tag.resize(room)
	look.resize(room)
	core.resize(room)
	stop.resize(room * SEGMENTS)


## How far ring `r` goes out along `way` from its centre before its segment there stopped.
func stop_toward(r: int, way: Vector2) -> float:
	return stop[r * SEGMENTS + CarrierPulse.segment_of(way)]
