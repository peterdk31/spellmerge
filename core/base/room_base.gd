class_name RoomBase
extends Resource
## What kind of room it is (props W8a, docs/milestones/props.md, "W8a: a room is its scene"): its
## id, its scene and the rules over the whole room. Where things are (spawns, doors, props,
## dummies, zones) is written in its scene only, edited by hand in the Godot editor, and read by
## `RoomPlaces` from the layout it builds (`build()`); nothing here is one room's own (the hub's stone
## is a self-contained prop placed in its scene). As a run's template (run generation RG1,
## docs/milestones/run-generation.md) it says its biome and the room kinds it can host; what fights
## in it is the run's map's (RG3: rooms hold layout only). M3 extends it with the door rules and with
## rooms built from pieces.

## Unique name of the room, also its file name; the registry finds it by this.
@export var id: StringName = &""
## Its name for people (a menu lists it by this); empty: its id in words.
@export var display_name: String = ""
## The layout scene: its art and walls, and what is where (`RoomPlaces`). No scripts.
@export var scene: PackedScene
## The shape its ground is drawn from when it is laid out (connected biomes CB4: its `<room>.shape.json`,
## content/rooms/README.md, "A room's ground from a shape"): Feel draws its floor, rock face, glow,
## wall art and edge motes again from it as placed, mirrored or not, over its `Floor`'s baked art
## (gameplay/feel/ground/). Null (the hub): the baked art stays. Drawn only.
@export var ground_shape: JSON = null
## The biome it is a room of (run generation RG1): a run's map of that biome may use it
## (`MapRules.biome`). Empty: no biome's.
@export var biome: StringName = &""
## The room kinds it can host (`RoomKind` ids: `fight`, `boss`), as a template a run's map picks for
## a room of that kind. Empty: it is offered for no run (the hub).
@export var kinds: Array[StringName] = []
## Seconds after which a downed wizard stands up by itself at full health (the hub: hits hurt there,
## but a fall costs nothing; owner, 2026-11-13). Below 0 (the default): never by itself, only by a
## teammate's revive or the restart. In such a room everyone down starts no restart.
@export var stand_up_after: float = -1.0
## True where a fall into a hole costs a wizard nothing (hub rework HR-H2, question 10: the hub);
## elsewhere it costs `HoleRules.FALL_COST` of its most health (Combat, as the room is entered).
@export var falls_free: bool = false
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
## so spells and torches read as the light in it. Only drawn while the "Dynamic lighting" setting is
## on; at most 1.0 (light only brightens past it).
@export_range(0.3, 1.0, 0.05) var ambient: float = 1.0
## The colour of the room's dark (docs/milestones/atmosphere.md, A): where no spell or torch lights
## it, a pixel is its art times `ambient` times this, channel by channel, so warm light falls on a
## cool dark. White (the default) is an even dark, as `ambient` alone. Drawn only with spell light.
@export var shade: Color = Color.WHITE
## What drifts in the room's air (docs/milestones/atmosphere.md, B): a `MoteSource` given off over
## the whole room by Feel (gameplay/feel/air_motes.gd), its `rate` the motes a second for every
## AIR_AREA square pixels of the room in view, from anywhere in it, each shown `height` px over a
## point of the floor, thrown its `way` within its `spread`, in its `colours`; its `from`, `at`,
## `size` and the rest of where a source leaves from are neither read nor checked
## (`problems_of_air`). Its kind is usually lit only (`MoteKind.lit_only`: the crypt's dust, seen
## only in a candle's pool, a wizard's light or a passing spell's). Null (the default): nothing
## drifts, the room is as it was. Drawn only.
@export var air: MoteSource = null
## Whether its biome's cover kinds fill its open floor by themselves (ground cover GC2,
## `CoverLayout.of`: each `CoverKind` whose `biomes` names its `biome`). Off: only its fields
## (`CoverField`) put cover in it.
@export var cover_fill: bool = true
## Its music (boss plan OB15, `MusicTrack`; null: silence), played while the room is the one in play
## unless an enemy with music of its own lives (`EnemyBase.music`). Rooms of one biome may share a
## track's file (a `.tres` beside them) or each hold their own.
@export var music: MusicTrack = null
## Its sound under the music (docs/milestones/atmosphere.md, D; `Ambience`): looping layers and
## sounds heard now and then (the crypt's drips and a far rumble, the hub's wind), played quietly
## while the room is in play and faded in and out with it by Feel (gameplay/feel/room_ambience.gd).
## Rooms of one biome share a file beside them. Null (the default): silent, as before. Heard only.
@export var ambience: Ambience = null
## Its low floor mist (docs/milestones/atmosphere.md, F; `RoomMist`): soft and see-through, thin over
## the middle and thicker toward its edges and pits, drifting, parted by bodies and pushed by shots and
## blasts, lit by the spell light (drawn only while the "Dynamic lighting" setting is on: Feel's
## gameplay/feel/mist.gd). Rooms of one biome share a file beside them. Null (the default): no mist,
## the room is as it was. Drawn only.
@export var mist: RoomMist = null

## The share of the most common colour a floor's colour needs to count (a wall's is the art rule's,
## `ArtPixels.MIN_SHARE`): a floor is mostly one colour, its seams and highlights a few pixels in a
## hundred (the crypt's shadow is 7 %, its light 1.4 %).
const FLOOR_MIN_SHARE: float = 0.01
## The role of a room's exits (`PropBase.role`; run generation RG4): props of it placed in its scene
## are the ways a run's party leaves the room by, lit once it is cleared, each leading to a room of
## the next row of the run's map. A template leads to as many rooms as it has exits (`exit_count`).
const EXIT_ROLE: StringName = &"room_exit"
## The layer of the walls' bodies (as Flow tells the projectile manager).
const WALL_LAYER: int = 1
## The layer of the holes' bodies (hub rework HR-H1, docs/milestones/hub-rework.md, "Holes"): a
## `StaticBody2D` whose `collision_layer` is exactly this, its `RectangleShape2D`s over the cells a
## walking body cannot step into and nothing else minds (shots, sight and gates pass over a hole).
## A body that is also on the wall layer is a wall; where a wall and a hole cover one cell, the wall
## wins (`RoomPlaces.hole_rects`, `RoomGrid.set_holes`).
const HOLE_LAYER: int = 2
## The z of a layout's `Floor` sprite: under Feel's floor marks (one above it) and under the
## bodies (0), so a mark lies on the floor and never over anyone.
const FLOOR_Z: int = -2
## The floor `air`'s rate is for: a second's motes for every 100 x 100 px of the room in view.
const AIR_AREA: float = 10000.0

## `surface_colors()`, `floor_colors()` and `places()` once worked out (empty until then).
var _surface: PackedColorArray = PackedColorArray()
var _floor: PackedColorArray = PackedColorArray()
var _places: RoomPlaces = null


## Its name for people: `display_name`, else its id in words.
func shown_name() -> String:
	return display_name if display_name != "" else String(id).capitalize()


## True when it can host a room of kind `kind_id` in a run (`kinds`).
func hosts(kind_id: StringName) -> bool:
	return kinds.has(kind_id)


## What is wrong with it as a run's template, one line each (empty when it is fine): kinds with no
## biome, a kind twice, a kind not in `known` (the room kinds there are).
func template_problems(known: Array[StringName]) -> PackedStringArray:
	var found := PackedStringArray()
	if not kinds.is_empty() and biome == &"":
		found.append("%s hosts %s but names no biome." % [id, kinds])
	for at in kinds.size():
		if kinds.find(kinds[at]) != at:
			found.append("%s: kind '%s' twice." % [id, kinds[at]])
		elif not known.has(kinds[at]):
			found.append("%s: kind '%s' is no room kind." % [id, kinds[at]])
	if music != null:
		found.append_array(music.problems(String(id)))
	if ambience != null:
		found.append_array(ambience.problems(String(id)))
	found.append_array(air_problems())
	if mist != null:
		found.append_array(mist.problems(String(id)))
	return found


## What is wrong with its `air`, one line each (empty when it is fine or there is none).
func air_problems() -> PackedStringArray:
	var found := PackedStringArray()
	for problem in problems_of_air(air):
		found.append("%s's air: %s" % [id, problem])
	return found


## What is wrong with `source` as a room's air (empty when it is fine or null): what it gives off
## (`MoteSource.stream_problems`, with no art to take colours from), never where a source leaves
## from, which the air does not read; and its motes are given off, never standing.
static func problems_of_air(source: MoteSource) -> PackedStringArray:
	var found := PackedStringArray()
	if source == null:
		return found
	found.append_array(source.stream_problems(false))
	if source.stand:
		found.append("the air's motes are given off, never standing")
	return found


## How many exits its layout places (props of EXIT_ROLE, read once from its default layout:
## `places()`): as a run's template it can lead to that many rooms of the next row (run generation
## RG4). 0 with no scene.
func exit_count() -> int:
	var count: int = 0
	for data: Resource in places().placed_of(PropBase):
		if (data as PropBase).role == EXIT_ROLE:
			count += 1
	return count


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
