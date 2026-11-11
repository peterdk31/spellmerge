class_name RoomBase
extends Resource
## What kind of room it is (props W8a, docs/milestones/props.md, "W8a: a room is its scene"): its
## id, its scene and the rules over the whole room. Where things are (spawns, doors, props,
## dummies, zones) is written in its scene only, edited by hand in the Godot editor, and read by
## `RoomPlaces` from the layout it builds (`build()`); nothing here is one room's own (the hub's stone
## is a self-contained prop placed in its scene). M3 extends it with the biome and the door rules,
## and with rooms built from pieces.

## Unique name of the room, also its file name; the registry finds it by this.
@export var id: StringName = &""
## The layout scene: its art and walls, and what is where (`RoomPlaces`). No scripts.
@export var scene: PackedScene
## True for a room where wizards take nothing from hits (the hub): a hit still lands (its flash, its
## push, its statuses) but takes no health (`Health.invincible`), so nobody is downed there.
@export var invincible: bool = false
## The colours of what its walls shed when struck (Feel's surface motes: chips), lightest first:
## light, base, shadow. Empty (the default): sampled from the room's own art (`surface_colors`),
## so new tiles change the chips with no edit here; set it only when the sample looks wrong.
@export var debris_colors: PackedColorArray = PackedColorArray()
## The mote kinds its walls shed when struck (`MoteKind` ids, content/motes; spell-spectacle-2.md,
## S2): a wooden room's splinters where the crypt's walls shed chips. Empty (the default): every
## `surface` kind. In the walls' colours either way.
@export var surface_kinds: Array[StringName] = []
## The colours of its floor, for the floor marks drawn in the floor's own shades (Feel's mark
## layer: a scorch, a crack), lightest first: light, base, shadow. Empty (the default): sampled
## from the room's `Floor` sprite (`floor_colors`); set it only when the sample looks wrong.
@export var floor_mark_colors: PackedColorArray = PackedColorArray()
## The room's light where no spell or torch lights it (Feel's spell light, docs/milestones/
## spell-spectacle.md, P3b): 1.0 (the default) is the room as its art is drawn, below it darker,
## so spells and torches read as the light in it. Only drawn while the "Spell light" setting is
## on; at most 1.0 (light only brightens past it).
@export_range(0.3, 1.0, 0.05) var ambient: float = 1.0

## The share of the most common colour a floor's colour needs to count (a wall's is the art rule's,
## `ArtPixels.MIN_SHARE`): a floor is mostly one colour, its seams and highlights a few pixels in a
## hundred (the crypt's shadow is 7 %, its light 1.4 %).
const FLOOR_MIN_SHARE: float = 0.01
## The layer of the walls' bodies (as Flow tells the projectile manager).
const WALL_LAYER: int = 1
## The z of a layout's `Floor` sprite: under Feel's floor marks (one above it) and under the
## bodies (0), so a mark lies on the floor and never over anyone.
const FLOOR_Z: int = -2

## `surface_colors()`, `floor_colors()` and `places()` once worked out (empty until then).
var _surface: PackedColorArray = PackedColorArray()
var _floor: PackedColorArray = PackedColorArray()
var _places: RoomPlaces = null


## A new instance of its layout (props W8c): its scene, its placements, zones and spawns in it.
## The game builds it once a run and reads what is where from that instance (`RoomPlaces.read`), the
## one it shows. A generated room (M3) overrides it to put pieces together by the run's chance
## (`sim.chance`, the run's seed among its rules, so a joining machine builds the same); with no
## `sim` (tests, tools, a colour sample) it builds its default layout. A fixed room is its scene
## either way. Null with no scene.
func build(_sim: Sim = null) -> Node:
	return scene.instantiate() if scene != null else null


## What is where in it (`RoomPlaces`: spawns, doors, placements, zones, its size), read once from
## its default layout (`build()` with no sim), for tests and tools; the game reads the layout it
## shows.
func places() -> RoomPlaces:
	if _places == null:
		var layout: Node = build()
		_places = RoomPlaces.read(layout)
		if layout != null:
			layout.free()
	return _places


## The colours its walls shed, lightest first (light, base, shadow; always three, a colour
## repeated when the art has fewer): `debris_colors` when set, else sampled once from the art of
## its scene. The sample is the colours of the sprites on its wall bodies (static bodies on the
## wall layer), most common first, leaving out the floor's own colour (the `Floor` sprite's most
## common one), so debris lying on the floor always shows. Empty when there is no art to read.
func surface_colors() -> PackedColorArray:
	if not debris_colors.is_empty():
		return ArtPixels.three(debris_colors)
	if _surface.is_empty() and scene != null:
		_surface = ArtPixels.three(sample_surface(build()))
	return _surface


## The colours of its floor, lightest first (light, base, shadow; always three, a colour repeated
## when the art has fewer): `floor_mark_colors` when set, else sampled once from the `Floor`
## sprite of its scene, its most common colours as it shows them (times its modulate). Empty
## when there is no art to read.
func floor_colors() -> PackedColorArray:
	if not floor_mark_colors.is_empty():
		return ArtPixels.three(floor_mark_colors)
	if _floor.is_empty() and scene != null:
		_floor = ArtPixels.three(sample_floor(build()))
	return _floor


## The floor colours of the layout `layout` (its `Floor` sprite's, most common first, ArtPixels.SHADES
## at most, none on fewer than FLOOR_MIN_SHARE of the most common's pixels); frees it.
static func sample_floor(layout: Node) -> PackedColorArray:
	var found := PackedColorArray()
	if layout == null:
		return found
	var floor_sprite := layout.get_node_or_null("Floor") as Sprite2D
	var counts: Dictionary = ArtPixels.count_colours(floor_sprite.texture, {}) if floor_sprite != null else {}
	# As it is shown: a tinted floor's marks are tinted the same.
	var tint: Color = floor_sprite.modulate * floor_sprite.self_modulate if floor_sprite != null else Color.WHITE
	layout.free()
	var most: int = 0
	for rgba: int in counts:
		most = maxi(most, int(counts[rgba]))
	while found.size() < ArtPixels.SHADES and not counts.is_empty():
		var top: int = ArtPixels.most_common(counts)
		if float(counts[top]) < float(most) * FLOOR_MIN_SHARE:
			break
		var colour: Color = Color.hex(top) * tint
		colour.a = 1.0
		found.append(colour)
		counts.erase(top)
	return found


## The wall colours of the layout `layout` (see `surface_colors`), most common first; frees it.
static func sample_surface(layout: Node) -> PackedColorArray:
	var found := PackedColorArray()
	if layout == null:
		return found
	var floor_main: int = -1
	var floor_sprite := layout.get_node_or_null("Floor") as Sprite2D
	if floor_sprite != null:
		var floor_counts: Dictionary = ArtPixels.count_colours(floor_sprite.texture, {})
		floor_main = ArtPixels.most_common(floor_counts)
	var counts: Dictionary = {}
	for node: Node in layout.find_children("*", "StaticBody2D", true, false):
		if ((node as StaticBody2D).collision_layer & WALL_LAYER) == 0:
			continue
		for child: Node in node.get_children():
			if child is Sprite2D:
				ArtPixels.count_colours((child as Sprite2D).texture, counts)
	layout.free()
	counts.erase(floor_main)
	return ArtPixels.top_colours(counts)
