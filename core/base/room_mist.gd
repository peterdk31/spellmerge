class_name RoomMist
extends Resource
## A room's low floor mist (docs/milestones/atmosphere.md, F; `RoomBase.mist`): a soft, see-through
## layer lying on the floor, drifting slowly, thin over the room's middle and thicker toward its edges
## and its pits, so the fight stays readable (crypt rework, rule 6). Drawn by Feel
## (gameplay/feel/mist.gd) under the bodies and over the floor, its cover, its marks and the bodies'
## shadows; pushed aside by shots and blasts, parted by bodies walking through it, and lit by the
## spell light. The mist alone may be soft and see-through (the owner, 2026-11-18; docs/STYLE.md).
## Rooms of one biome share one file. Drawn only: nothing in the game reads it.

## The most a mist may hide what is under it (an opacity), and how small and big its billows may be
## (px).
const THICKEST: float = 0.6
const SCALE_LEAST: float = 16.0
const SCALE_MOST: float = 512.0
## The furthest from a wall or a pit its thickening may reach (px): the mask's (Feel's `MistMask`).
const REACH_MOST: float = 128.0
## The fastest it may drift (px/s): slowly, under a fight.
const DRIFT_MOST: float = 24.0

## Its colour (its own alpha is not read: `thickness` is how much it hides).
@export var colour: Color = Color(0.72, 0.78, 0.92, 1.0)
## How much it hides the floor where it is thickest (0 to THICKEST): at a wall's foot or a pit's lip,
## in a billow.
@export_range(0.0, 0.6, 0.01) var thickness: float = 0.3
## How thick it is over the room's open middle, a share of `thickness` (rule 6: thin over the fight).
@export_range(0.0, 1.0, 0.01) var middle: float = 0.25
## How far from the room's edge (the void round a floating room's slab or the hub's island; a low wall
## standing in the room is no edge: thin over the fight) and from a pit inside it it thickens (px, at
## most REACH_MOST), and how much thicker a pit makes it than the edge (a share: 1 as thick).
@export_range(0.0, 128.0, 1.0) var edge_reach: float = 72.0
@export_range(0.0, 128.0, 1.0) var pit_reach: float = 64.0
@export_range(0.0, 1.0, 0.01) var pit_share: float = 1.0
## How far it spills over a wall's edge before it is gone (px; a floating room's lip, the void below).
@export_range(0.0, 64.0, 1.0) var spill: float = 12.0
## How patchy it is (0: an even sheet; 1: billows with clear floor between) and how big its billows
## are (px).
@export_range(0.0, 1.0, 0.01) var patchy: float = 0.6
@export_range(16.0, 512.0, 1.0) var scale: float = 96.0
## Which way and how fast it drifts (px/s, at most DRIFT_MOST long).
@export var drift: Vector2 = Vector2(4.0, 1.0)
## How plainly it shows where no light falls (a share; the room's dark darkens it besides) and how
## much a light brings it out and tints it its own colour (a candle's pool glows warm in it).
@export_range(0.0, 1.0, 0.01) var in_dark: float = 0.5
@export_range(0.0, 2.0, 0.01) var lit: float = 1.0


## What is wrong with it, one line each (empty when it is fine): a number out of its range, a colour
## or a drift that is not a number.
func problems(owner: String) -> PackedStringArray:
	var found := PackedStringArray()
	var name: String = "%s's mist" % owner
	if not (thickness > 0.0 and thickness <= THICKEST):
		found.append("%s: its thickness is not above 0 and at most %s" % [name, THICKEST])
	if not (middle >= 0.0 and middle <= 1.0):
		found.append("%s: its middle is not a share (0 to 1)" % name)
	if not (edge_reach >= 0.0 and edge_reach <= REACH_MOST) or not (pit_reach >= 0.0 and pit_reach <= REACH_MOST):
		found.append("%s: its edge_reach and pit_reach are not within 0 to %s px" % [name, REACH_MOST])
	if not (pit_share >= 0.0 and pit_share <= 1.0) or not (patchy >= 0.0 and patchy <= 1.0) or not (in_dark >= 0.0 and in_dark <= 1.0):
		found.append("%s: its pit_share, patchy and in_dark are not shares (0 to 1)" % name)
	if not (spill >= 0.0 and spill <= 64.0):
		found.append("%s: its spill is not within 0 to 64 px" % name)
	if not (scale >= SCALE_LEAST and scale <= SCALE_MOST):
		found.append("%s: its scale is not within %s to %s px" % [name, SCALE_LEAST, SCALE_MOST])
	if not drift.is_finite() or drift.length() > DRIFT_MOST:
		found.append("%s: its drift is more than %s px/s" % [name, DRIFT_MOST])
	if not (lit >= 0.0 and lit <= 2.0):
		found.append("%s: its lit is not within 0 to 2" % name)
	if not (is_finite(colour.r) and is_finite(colour.g) and is_finite(colour.b)):
		found.append("%s: its colour is not a colour" % name)
	return found
