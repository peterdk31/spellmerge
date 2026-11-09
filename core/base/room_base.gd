class_name RoomBase
extends Resource
## The small M1 room: its scene and where things go. M3 extends it with the
## biome, the required doors and validators.

## Unique name of the room, also its file name; the registry finds it by this.
@export var id: StringName = &""
## The layout scene (tiles only, no scripts).
@export var scene: PackedScene
## Where the players start, in room pixels. Index i is player i; four are expected (checked from M3).
@export var player_spawns: PackedVector2Array = PackedVector2Array()
## Where enemies may appear, in room pixels.
@export var enemy_spawns: PackedVector2Array = PackedVector2Array()
## Door positions, in room pixels.
@export var doors: PackedVector2Array = PackedVector2Array()
## Where a sandbox room puts its dummies, in room pixels (staffs B7): the training dummy first,
## then the shooting dummy. Empty in every other room.
@export var dummy_spawns: PackedVector2Array = PackedVector2Array()
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

## The wall art's colours that count, at most; a colour on fewer pixels than this share of the
## most common one is left out (a speck of trim).
const SURFACE_SHADES: int = 3
const SURFACE_MIN_SHARE: float = 0.1
## The same for the floor's colours: a floor is mostly one colour, its seams and highlights a few
## pixels in a hundred (the crypt's shadow is 7 %, its light 1.4 %).
const FLOOR_MIN_SHARE: float = 0.01
## The layer of the walls' bodies (as Flow tells the projectile manager).
const WALL_LAYER: int = 1
## The z of a layout's `Floor` sprite: under Feel's floor marks (one above it) and under the
## bodies (0), so a mark lies on the floor and never over anyone.
const FLOOR_Z: int = -2

## `surface_colors()` and `floor_colors()` once worked out (empty until then).
var _surface: PackedColorArray = PackedColorArray()
var _floor: PackedColorArray = PackedColorArray()


## The colours its walls shed, lightest first (light, base, shadow; always three, a colour
## repeated when the art has fewer): `debris_colors` when set, else sampled once from the art of
## its scene. The sample is the colours of the sprites on its wall bodies (static bodies on the
## wall layer), most common first, leaving out the floor's own colour (the `Floor` sprite's most
## common one), so debris lying on the floor always shows. Empty when there is no art to read.
func surface_colors() -> PackedColorArray:
	if not debris_colors.is_empty():
		return _three(debris_colors)
	if _surface.is_empty() and scene != null:
		_surface = _three(sample_surface(scene.instantiate()))
	return _surface


## The colours of its floor, lightest first (light, base, shadow; always three, a colour repeated
## when the art has fewer): `floor_mark_colors` when set, else sampled once from the `Floor`
## sprite of its scene, its most common colours as it shows them (times its modulate). Empty
## when there is no art to read.
func floor_colors() -> PackedColorArray:
	if not floor_mark_colors.is_empty():
		return _three(floor_mark_colors)
	if _floor.is_empty() and scene != null:
		_floor = _three(sample_floor(scene.instantiate()))
	return _floor


## The floor colours of the layout `layout` (its `Floor` sprite's, most common first, SURFACE_SHADES
## at most, none on fewer than FLOOR_MIN_SHARE of the most common's pixels); frees it.
static func sample_floor(layout: Node) -> PackedColorArray:
	var found := PackedColorArray()
	if layout == null:
		return found
	var floor_sprite := layout.get_node_or_null("Floor") as Sprite2D
	var counts: Dictionary = _count_colours(floor_sprite.texture, {}) if floor_sprite != null else {}
	# As it is shown: a tinted floor's marks are tinted the same.
	var tint: Color = floor_sprite.modulate * floor_sprite.self_modulate if floor_sprite != null else Color.WHITE
	layout.free()
	var most: int = 0
	for rgba: int in counts:
		most = maxi(most, int(counts[rgba]))
	while found.size() < SURFACE_SHADES and not counts.is_empty():
		var top: int = _most_common(counts)
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
		var floor_counts: Dictionary = _count_colours(floor_sprite.texture, {})
		floor_main = _most_common(floor_counts)
	var counts: Dictionary = {}
	for node: Node in layout.find_children("*", "StaticBody2D", true, false):
		if ((node as StaticBody2D).collision_layer & WALL_LAYER) == 0:
			continue
		for child: Node in node.get_children():
			if child is Sprite2D:
				_count_colours((child as Sprite2D).texture, counts)
	layout.free()
	counts.erase(floor_main)
	return _top_colours(counts)


## The colours of the art `texture` (only its `region` when one is given: a frame of a sheet),
## by the same rule as a room's walls: its most common ones, lightest first (light, base, shadow;
## always three, a colour repeated when it has fewer). What a body that breaks sheds (Feel's
## motes). Empty when there is no art to read.
static func colours_of_art(texture: Texture2D, region: Rect2i = Rect2i()) -> PackedColorArray:
	return _three(_top_colours(_count_colours(texture, {}, region)))


## The most common colours of `counts` (RGBA32 -> pixels), most common first: at most
## SURFACE_SHADES, none on fewer than SURFACE_MIN_SHARE of the most common one's pixels. Empties
## `counts`' top colours.
static func _top_colours(counts: Dictionary) -> PackedColorArray:
	var found := PackedColorArray()
	var most: int = 0
	for rgba: int in counts:
		most = maxi(most, int(counts[rgba]))
	while found.size() < SURFACE_SHADES and not counts.is_empty():
		var top: int = _most_common(counts)
		if float(counts[top]) < float(most) * SURFACE_MIN_SHARE:
			break
		found.append(Color.hex(top))
		counts.erase(top)
	return found


## `colours` as three shades, lightest first: light, base, shadow.
static func _three(colours: PackedColorArray) -> PackedColorArray:
	var sorted: Array[Color] = []
	for colour in colours:
		sorted.append(colour)
	sorted.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() > b.get_luminance())
	match sorted.size():
		0:
			return PackedColorArray()
		1:
			return PackedColorArray([sorted[0], sorted[0], sorted[0]])
		2:
			return PackedColorArray([sorted[0], sorted[0], sorted[1]])
	return PackedColorArray([sorted[0], sorted[1], sorted[2]])


## Adds the opaque pixels of `texture` (of its `region` only, when one is given) to `counts`
## (RGBA32 -> pixels) and returns it.
static func _count_colours(texture: Texture2D, counts: Dictionary, region: Rect2i = Rect2i()) -> Dictionary:
	if texture == null:
		return counts
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return counts
	if image.is_compressed():
		image.decompress()
	var area := Rect2i(Vector2i.ZERO, image.get_size())
	if region.has_area():
		area = area.intersection(region)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a >= 0.5:
				var rgba: int = Color(pixel.r, pixel.g, pixel.b, 1.0).to_rgba32()
				counts[rgba] = int(counts.get(rgba, 0)) + 1
	return counts


## The pixels of `texture` (within `region` when it has one) that show (alpha at least a half),
## as positions in the region, every `step`-th of them in reading order: what a body's art is made
## of, for it to break into (S3, a death's motes). Empty for no texture.
static func pixels_of_art(texture: Texture2D, region: Rect2i = Rect2i(), step: int = 1) -> PackedVector2Array:
	var found := PackedVector2Array()
	if texture == null:
		return found
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return found
	if image.is_compressed():
		image.decompress()
	var area := Rect2i(Vector2i.ZERO, image.get_size())
	if region.has_area():
		area = area.intersection(region)
	var n: int = 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if image.get_pixel(x, y).a >= 0.5:
				if n % maxi(step, 1) == 0:
					found.append(Vector2(x - area.position.x, y - area.position.y))
				n += 1
	return found


static func _most_common(counts: Dictionary) -> int:
	var best: int = -1
	var most: int = 0
	for rgba: int in counts:
		if int(counts[rgba]) > most:
			most = int(counts[rgba])
			best = rgba
	return best


## The room's size in pixels, from (0, 0): at least 640×360, every spawn and door a tile in, and
## the layout's `Floor` sprite (the whole room, under the walls) when `layout` is given. The room
## Flow makes is this size (its camera's limits).
func size_in(layout: Node = null) -> Vector2:
	var size := Vector2(640.0, 360.0)
	var floor_sprite: Sprite2D = layout.get_node_or_null("Floor") as Sprite2D if layout != null else null
	if floor_sprite != null and floor_sprite.texture != null:
		var extent: Vector2 = floor_sprite.region_rect.size if floor_sprite.region_enabled else floor_sprite.texture.get_size()
		size = size.max(floor_sprite.position + extent)
	for point: Vector2 in player_spawns:
		size = size.max(point + Vector2(32.0, 32.0))
	for point: Vector2 in enemy_spawns:
		size = size.max(point + Vector2(32.0, 32.0))
	for point: Vector2 in doors:
		size = size.max(point + Vector2(32.0, 32.0))
	return size
