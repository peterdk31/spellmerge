class_name MoteSource
extends Resource
## One stream of motes that something in the world gives off all the time, as art (props W7,
## docs/milestones/props.md; the owner, 2026-11-10: "motes coming off almost everything"): embers
## off a brazier, glimmers off a crystal's facets, dust off a cracked urn, the hub's island edge.
## Scenes carry no scripts, so a source is data on a plain node: any `Node2D` in the group
## `mote_source` (GROUP) with this resource as its metadata `mote_source` (META). Where its motes
## leave from is relative to that node:
##
##     [sub_resource type="Resource" id="MoteSource_rim"]
##     script = ExtResource("<core/base/mote_source.gd>")
##     kind = &"rim_ember"
##     rate = 172.8
##     from = 1
##     ramps = Array[PackedColorArray]([PackedColorArray(...), ...])
##
##     [node name="Rim" type="Line2D" parent="." groups=["mote_source"]]
##     visible = false
##     closed = true
##     points = PackedVector2Array(...)
##     metadata/mote_source = SubResource("MoteSource_rim")
##
## A room's art holds such nodes itself; a prop's look adds them for the state it is in. Feel gives
## the motes off (gameplay/feel/source_motes.gd), view only: nothing in the game reads a source,
## and a node without one, or taken out, simply has none. Changing the look is changing these
## numbers, the kind (content/motes) or the node; no code.
##
## From a **mask** the art is the emitter: the lit pixels (alpha at least a half) of the sprite the
## node's metadata `mote_art` names (a NodePath, as a light spot's `light_art`), read once a
## texture: a crystal's facets, a rune's carvings, the `*` points `tools/pixel_grid.py` writes as a
## mask layer of their own. A mask may also **stand** (`stand`): every lit pixel is a mote that
## stays there, white-hot and cooling through its ramp over `life` seconds, again and again, so
## carvings twinkle as magic rather than lie flat (used sparingly: every pixel is drawn each frame).
##
## The places within an oval are shared with a still card's motes (`StillMoteSource`,
## gameplay/feel/still_motes.gd): `in_oval`, `on_oval`, `on_grid`.

## The group a source's node is in, and the metadata keys of its source and of its mask's art.
const GROUP: StringName = &"mote_source"
const META: StringName = &"mote_source"
const ART: StringName = &"mote_art"

## Where its motes leave from (relative to its node): a point (`at`); a line (`points`, else the
## node's own `Line2D` points; thrown outward, the left of the way the points run, so a rim drawn
## clockwise on screen throws out of the shape); anywhere in a box (`size` across round `at`); on
## an oval's rim (`size` across round `at`; thrown outward from its middle); a mask's lit pixels.
enum From { POINT, LINE, AREA, RIM, MASK }

## The most a second a source gives off, and the most seconds a standing mote's round takes.
const MOST_RATE: float = 2000.0
const MOST_LIFE: float = 4.0

## The mote kind it gives off (an id in content/motes).
@export var kind: StringName = &""
## Motes a second from the whole source, at the "Particle amount" setting's Full (a standing
## mask: none, it places one on every lit pixel).
@export_range(0.0, 2000.0, 0.1) var rate: float = 4.0
@export var from: From = From.POINT
## POINT: the point; AREA and RIM: the middle. Pixels from the node.
@export var at: Vector2 = Vector2.ZERO
## AREA: the box across; RIM: the oval across. Pixels.
@export var size: Vector2 = Vector2.ZERO
## LINE: its points from the node (empty: the node's own, a `Line2D`'s), and whether it closes.
@export var points: PackedVector2Array = PackedVector2Array()
@export var closed: bool = false
## The way its motes are thrown (POINT, AREA and MASK; a line and a rim throw outward), and the
## spread round it in degrees (360: any way).
@export var way: Vector2 = Vector2.UP
@export_range(0.0, 360.0, 1.0) var spread: float = 120.0
## How far a mote is thrown (the kind's own speed carries it no further), pixels.
@export_range(0.0, 64.0, 0.5) var reach: float = 6.0
## How high over where it leaves from a mote shows, in pixels (0: the kind's own height): an ember
## over a brazier's coals.
@export_range(0.0, 128.0, 0.5) var height: float = 0.0
## Pixels between the places along a line or rim, or across a box, a mote may leave from, on the
## world's grid (0: anywhere).
@export_range(0.0, 64.0, 0.5) var spacing: float = 0.0
## Seconds after its node appears (a prop's state is entered, a room is) that it starts, and that
## it stops (0: never): a broken crate's dust for its first seconds.
@export_range(0.0, 600.0, 0.05) var start: float = 0.0
@export_range(0.0, 600.0, 0.05) var stop: float = 0.0
## The colours it cools through, one ramp a mote at random (each white-hot, light, base, shadow;
## three shades take the light as the white-hot). Palette colours only (docs/STYLE.md). Empty: the
## colours of its art (`mote_art`; a mask's, else a point's on it), lightest first.
@export var ramps: Array[PackedColorArray] = []
## MASK only: its motes stand on the lit pixels instead of being given off.
@export var stand: bool = false
## A standing mote's round, white-hot to its last shade, in seconds.
@export_range(0.1, 4.0, 0.05) var life: float = 1.2


## The source on `node` (its META), or null.
static func of(node: Node) -> MoteSource:
	return node.get_meta(META, null) as MoteSource if node != null else null


## The sprite a node's source reads its art from (`mote_art`), or null.
static func art_of(node: Node) -> Sprite2D:
	var path: NodePath = node.get_meta(ART, NodePath()) if node != null else NodePath()
	return node.get_node_or_null(path) as Sprite2D if not path.is_empty() else null


## What is wrong with it, in words (empty when nothing). `has_art`: its node names art to read
## (`mote_art`), which a mask needs, and colours stand in for empty `ramps`.
func problems(has_art: bool = true) -> PackedStringArray:
	var found := PackedStringArray()
	if kind == &"":
		found.append("a mote source names no mote kind")
	if not stand and (rate <= 0.0 or rate > MOST_RATE):
		found.append("a mote source gives off %s a second: above 0, at most %s" % [rate, MOST_RATE])
	if stand and from != From.MASK:
		found.append("only a mask's motes stand")
	if from == From.MASK and not has_art:
		found.append("a mask names no art (metadata mote_art)")
	if (from == From.AREA or from == From.RIM) and (size.x <= 0.0 or size.y <= 0.0):
		found.append("an area or a rim needs a size")
	if way.is_zero_approx() and from != From.LINE and from != From.RIM:
		found.append("a mote source has no way to throw")
	if stop > 0.0 and stop <= start:
		found.append("a mote source stops at %s s, before it starts at %s s" % [stop, start])
	if ramps.is_empty() and not has_art:
		found.append("a mote source has no colours (ramps, or art to take them from)")
	for i in ramps.size():
		if ramps[i].size() < 3 or ramps[i].size() > 4:
			found.append("a mote source's ramp %d has %d colours, not 3 or 4" % [i, ramps[i].size()])
	return found


## A point anywhere in the oval of half-axes `half` round its middle, at most `inside` of the way to
## its rim (a pool's surface; `rng` the caller's own dice).
static func in_oval(rng: RandomNumberGenerator, half: Vector2, inside: float = 1.0) -> Vector2:
	var b: float = rng.randf() * TAU
	return Vector2(cos(b), sin(b)) * half * sqrt(rng.randf()) * inside


## A point on the rim of the oval of half-axes `half` round its middle, in whole pixels; with
## `spacing`, only at that many pixels apart round it (a rune's ring).
static func on_oval(rng: RandomNumberGenerator, half: Vector2, spacing: float = 0.0) -> Vector2:
	var a: float = rng.randf() * TAU
	if spacing > 0.0:
		var steps: float = maxf(roundf(TAU * maxf(half.x, half.y) / spacing), 1.0)
		a = roundf(a / TAU * steps) / steps * TAU
	return (Vector2(cos(a), sin(a)) * half).round()


## `along` (a place on a line `w` from the world's origin along it) put on the world's grid of
## `spacing` pixels, so pieces of a row and sources side by side line up (0: as it is).
static func on_grid(along: float, w: float, spacing: float) -> float:
	if spacing <= 0.0:
		return along
	return roundf((w + along) / spacing) * spacing - w
