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
##     colours = Array[StringName]([&"fire", &"spark", &"arc", &"ice", &"void"])
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
## A source is read once, where its node is when it appears (a room's art and a prop stand still):
## its motes do not follow a node that moves, nor a mask's sprite as it animates or squashes.

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
## The palette materials it cools through, by name (docs/STYLE.md, core/base/palette.gd: &"fire",
## &"ice", &"stone"), one a mote at random: white-hot, then the material's light, base and shadow.
## Never a player's colour nor Blight. Empty: the colours of its art (`mote_art`), lightest first.
@export var colours: Array[StringName] = []
## MASK only: its motes stand on the lit pixels instead of being given off.
@export var stand: bool = false
## A standing mote's round, white-hot to its last shade, in seconds.
@export_range(0.1, 4.0, 0.05) var life: float = 1.2


## Make `node` give off `source` (in the group, as its META), its art (a mask's; else its colours
## when it names no ramps) the sprite at `art` from it (empty: none). The one writer of the
## metadata, as `of` and `art_of` are its readers.
static func put(node: Node, source: MoteSource, art: NodePath = NodePath()) -> void:
	node.add_to_group(GROUP)
	node.set_meta(META, source)
	if not art.is_empty():
		node.set_meta(ART, art)


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
	if colours.is_empty() and not has_art:
		found.append("a mote source has no colours (name palette materials, or give it art to take them from)")
	found.append_array(Palette.world_problems(colours, "a mote source"))
	return found


## The ramps its motes cool through, one a material it names (`Palette.ramp_of`); empty when it
## names none (its art's colours are the reader's to take).
func ramps() -> Array[PackedColorArray]:
	var found: Array[PackedColorArray] = []
	for material in colours:
		var ramp: PackedColorArray = Palette.ramp_of(material)
		if not ramp.is_empty():
			found.append(ramp)
	return found
