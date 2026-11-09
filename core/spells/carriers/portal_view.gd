class_name PortalView
extends RefCounted
## What a viewer may know of the open portals and their gates this frame (docs/milestones/
## carrier-looks-fixes.md, phase 2): the portal carrier fills one (`CarrierPortal.read_view`), so the
## area that draws portals (Feel's portal look, `Carrier.LOOK_PORTAL`) reads one typed thing, not the
## carrier's rows or getters by name. The portals' arrays hold `portals`, the gates' `gates`; portal
## `p`'s gates are `gate_count[p]` from `first_gate[p]` on, its mouth first. Grown only when a frame
## has more than ever before: filling it allocates nothing. Read it when filled; it changes next
## frame.

## View only: the simulation never reads it (core/sim/README.md).
const VIEW_ONLY: bool = true

var portals: int = 0
## Each portal's own number (the same while it is open: its look's dice), its caster (its ramp), its spell's look bits and core colour, how each infusion on
## it looks in slot order (`CompiledSpell.infusion_looks`; shared, never change it), and its seconds
## open and seconds left (INF for a held one).
var key: PackedInt64Array = PackedInt64Array()
var caster: PackedInt32Array = PackedInt32Array()
var look: PackedInt32Array = PackedInt32Array()
var core: PackedColorArray = PackedColorArray()
var infusions: Array[PackedColorArray] = []
var since: PackedFloat32Array = PackedFloat32Array()
var left: PackedFloat32Array = PackedFloat32Array()
var first_gate: PackedInt32Array = PackedInt32Array()
var gate_count: PackedInt32Array = PackedInt32Array()

var gates: int = 0
## Each gate's middle, the way a shot goes through it (a mouth's in, an exit's out), its radius and
## whether it is its portal's mouth (1) or an exit (0).
var centre: PackedVector2Array = PackedVector2Array()
var face: PackedVector2Array = PackedVector2Array()
var radius: PackedFloat32Array = PackedFloat32Array()
var mouth: PackedByteArray = PackedByteArray()


## Room for `wanted` portals: grows, never shrinks.
func hold_portals(wanted: int) -> void:
	if key.size() >= wanted:
		return
	var room: int = maxi(wanted, key.size() * 2)
	key.resize(room)
	caster.resize(room)
	look.resize(room)
	core.resize(room)
	infusions.resize(room)
	since.resize(room)
	left.resize(room)
	first_gate.resize(room)
	gate_count.resize(room)


## Room for `wanted` gates: grows, never shrinks.
func hold_gates(wanted: int) -> void:
	if centre.size() >= wanted:
		return
	var room: int = maxi(wanted, centre.size() * 2)
	centre.resize(room)
	face.resize(room)
	radius.resize(room)
	mouth.resize(room)
