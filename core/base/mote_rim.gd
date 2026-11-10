class_name MoteRim
extends Resource
## A rim of motes: what the edge of a room's floor gives off all the time, as art (the hub's island:
## embers in the elements' colours rising off its edge into the void; docs/milestones/online-lobby.md,
## L1, the owner's pick "A, mixed elements", 2026-11-10). Room scenes carry no scripts, so a rim is
## data on a plain node: a `Line2D` in the group `mote_rim` (GROUP), its points the edge (closed or
## not), running clockwise as seen on screen so the outside is on its left, hidden (it draws
## nothing itself), with this resource as its metadata `mote_rim` (META):
##
##     [sub_resource type="Resource" id="MoteRim_1"]
##     script = ExtResource("<core/base/mote_rim.gd>")
##     kind = &"rim_ember"
##     rate = 3.2
##     ramps = Array[PackedColorArray]([PackedColorArray(...), ...])
##
##     [node name="Rim" type="Line2D" parent="." groups=["mote_rim"]]
##     visible = false
##     closed = true
##     points = PackedVector2Array(...)
##     metadata/mote_rim = SubResource("MoteRim_1")
##
## Feel gives the motes off (gameplay/feel/rim_motes.gd), view only: nothing in the game reads a rim,
## and a room without one, or with the node taken out, simply has none. Changing the look is changing
## these numbers, the kind (content/motes) or the node; no code.

## The group a rim's node is in, and the metadata key that holds this resource.
const GROUP: StringName = &"mote_rim"
const META: StringName = &"mote_rim"

## The mote kind it gives off (an id in content/motes).
@export var kind: StringName = &"rim_ember"
## Motes a second for every 100 pixels of rim, at the "Particle amount" setting's Full.
@export_range(0.0, 50.0, 0.1) var rate: float = 3.0
## How far a mote is thrown out from the edge (the kind's own speed carries it no further), pixels.
@export_range(0.0, 64.0, 0.5) var reach: float = 6.0
## How much of its flight goes outward, against along the edge: the spread round the outward way,
## in degrees (360: any way).
@export_range(0.0, 360.0, 1.0) var spread: float = 120.0
## The colours it cools through, one ramp a mote at random (each white-hot, light, base, shadow;
## three shades take the light as the white-hot). Palette colours only (docs/STYLE.md).
@export var ramps: Array[PackedColorArray] = []


## The rim on `node` (its META), or null.
static func of(node: Node) -> MoteRim:
	return node.get_meta(META, null) as MoteRim if node != null else null


## What is wrong with it, in words (empty when nothing).
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if kind == &"":
		found.append("a mote rim names no mote kind")
	if ramps.is_empty():
		found.append("a mote rim has no colours")
	for i in ramps.size():
		if ramps[i].size() < 3 or ramps[i].size() > 4:
			found.append("a mote rim's ramp %d has %d colours, not 3 or 4" % [i, ramps[i].size()])
	return found
