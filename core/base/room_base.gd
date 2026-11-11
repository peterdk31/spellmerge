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
## Where a room stands dummies, in room pixels (staffs B7: the sandbox; the hub). Empty in every
## other room.
@export var dummy_spawns: PackedVector2Array = PackedVector2Array()
## Which dummy (an enemy id, content/enemies) stands at each of `dummy_spawns`, in order; the last
## one stands at every spawn past the list (`dummy_id`).
@export var dummy_ids: Array[StringName] = []
## The props the room stands (props W8, content/props: the hub's teleporter stone and altar), by
## id, each at the place of the same index in `prop_spawns` (its feet), in room pixels. Empty (the
## default): none. The scene marks the places too (`PropSpawns`), and a test holds them together.
@export var prop_ids: Array[StringName] = []
@export var prop_spawns: PackedVector2Array = PackedVector2Array()
## The prop yard, in room pixels (props W8: the hub's): a place where every prop the registry knows
## stands (`PropBase.in_yard`), in rows by id, each in its first state, to try spells on. Empty (the
## default): none.
@export var prop_yard: Rect2 = Rect2()
## Seconds after a yard prop leaves its first state (lit, broken) or goes before a fresh one stands
## in its place, so testing never runs out of barrels.
@export_range(0.0, 120.0, 0.5) var prop_yard_return: float = 10.0
## The teleporter stone that starts a run, in room pixels (the hub; docs/milestones/
## online-lobby.md, L1): it is lit while every wizard in the room stands in it, and then any seat's
## A starts the run. Empty (the default) in every other room. What shows it is a prop standing in
## it (`prop_ids`: the hub's `hub_stone`), which enters its state `lit` as it lights and `unlit` as
## it goes out (props W8), so its look and its cue are the prop's.
@export var start_stone: Rect2 = Rect2()
## The multiplayer altar, in room pixels (the hub; docs/milestones/online-lobby.md, L2): a seat
## whose wizard stands in it may open the room to other machines with A (`altar_changed`, the HUD's
## `online_open_requested`). Empty (the default) in every other room.
@export var altar: Rect2 = Rect2()
## Where the wizard of a seat that joins while the room is under way appears, by seat, in room pixels
## (the hub: beside the altar, where a joining machine's wizards arrive; online lobby decision 4).
## Empty (the default): at the player spawn farthest from the enemies and the other wizards.
@export var joiner_spawns: PackedVector2Array = PackedVector2Array()
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

## The states of a prop standing on the `start_stone` (props W8): lit while every wizard stands
## on the stone, unlit otherwise.
const STONE_LIT: StringName = &"lit"
const STONE_UNLIT: StringName = &"unlit"
## Pixels between two props in the yard, across and between rows (room to aim at one).
const YARD_GAP: float = 32.0
## The share of the most common colour a floor's colour needs to count (a wall's is the art rule's,
## `ArtPixels.MIN_SHARE`): a floor is mostly one colour, its seams and highlights a few pixels in a
## hundred (the crypt's shadow is 7 %, its light 1.4 %).
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
		return ArtPixels.three(debris_colors)
	if _surface.is_empty() and scene != null:
		_surface = ArtPixels.three(sample_surface(scene.instantiate()))
	return _surface


## The colours of its floor, lightest first (light, base, shadow; always three, a colour repeated
## when the art has fewer): `floor_mark_colors` when set, else sampled once from the `Floor`
## sprite of its scene, its most common colours as it shows them (times its modulate). Empty
## when there is no art to read.
func floor_colors() -> PackedColorArray:
	if not floor_mark_colors.is_empty():
		return ArtPixels.three(floor_mark_colors)
	if _floor.is_empty() and scene != null:
		_floor = ArtPixels.three(sample_floor(scene.instantiate()))
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


## The dummy that stands at the `spawn`-th of `dummy_spawns`: `dummy_ids` in order, then its last
## one; `&""` when it names none.
func dummy_id(spawn: int) -> StringName:
	if dummy_ids.is_empty() or spawn < 0:
		return &""
	return dummy_ids[mini(spawn, dummy_ids.size() - 1)]


## Where each of `props` stands in the `prop_yard` (its feet, whole pixels), in order: rows filled
## left to right, YARD_GAP apart (by `PropBase.extent`), each row centred, its props' feet on one
## line; a prop that does not fit (the yard is full) at Vector2.INF. Empty with no yard.
func yard_places(props: Array[PropBase]) -> PackedVector2Array:
	var places := PackedVector2Array()
	if not prop_yard.has_area():
		return places
	places.resize(props.size())
	places.fill(Vector2.INF)
	var top: float = prop_yard.position.y
	var at: int = 0
	while at < props.size():
		# A row: as many as fit across.
		var row_end: int = at
		var width: float = 0.0
		var above: float = 0.0
		var below: float = 0.0
		while row_end < props.size():
			var box: Rect2 = props[row_end].extent() if props[row_end] != null else Rect2()
			var wider: float = width + (YARD_GAP if row_end > at else 0.0) + box.size.x
			if row_end > at and wider > prop_yard.size.x:
				break
			width = wider
			above = maxf(above, -box.position.y)
			below = maxf(below, box.end.y)
			row_end += 1
		if top + above + below > prop_yard.end.y or width > prop_yard.size.x:
			break
		var x: float = prop_yard.position.x + floorf((prop_yard.size.x - width) * 0.5)
		var feet_y: float = ceilf(top + above)
		for i in range(at, row_end):
			var box: Rect2 = props[i].extent() if props[i] != null else Rect2()
			if props[i] != null:
				places[i] = Vector2(floorf(x - box.position.x), feet_y)
			x += box.size.x + YARD_GAP
		top = feet_y + below + YARD_GAP
		at = row_end
	return places


## The room's size in pixels, from (0, 0): at least 640×360, every spawn and door a tile in, and,
## when `layout` is given, its `Floor` sprite (the whole room, under the walls, in a crypt) and its
## walls' rectangles (a room whose floor is not one rectangle: the hub's island, the void round it
## all wall). The room Flow makes is this size (its camera's limits).
func size_in(layout: Node = null) -> Vector2:
	var size := Vector2(640.0, 360.0)
	var floor_sprite: Sprite2D = layout.get_node_or_null("Floor") as Sprite2D if layout != null else null
	if floor_sprite != null and floor_sprite.texture != null:
		var extent: Vector2 = floor_sprite.region_rect.size if floor_sprite.region_enabled else floor_sprite.texture.get_size()
		size = size.max(floor_sprite.position + extent)
	if layout != null:
		for node: Node in layout.find_children("*", "StaticBody2D", true, false):
			var body := node as StaticBody2D
			if (body.collision_layer & WALL_LAYER) == 0:
				continue
			for child: Node in body.get_children():
				var shape := child as CollisionShape2D
				var box := shape.shape as RectangleShape2D if shape != null else null
				if box == null:
					continue
				# The layout is not in the tree yet: its transform is walked by hand.
				var xf: Transform2D = shape.transform
				var up: Node = body
				while up != null and up != layout:
					if up is Node2D:
						xf = (up as Node2D).transform * xf
					up = up.get_parent()
				var half: Vector2 = box.size * 0.5
				for corner: Vector2 in [half, -half, Vector2(half.x, -half.y), Vector2(-half.x, half.y)]:
					size = size.max(xf * corner)
	for point: Vector2 in player_spawns:
		size = size.max(point + Vector2(32.0, 32.0))
	for point: Vector2 in enemy_spawns:
		size = size.max(point + Vector2(32.0, 32.0))
	for point: Vector2 in doors:
		size = size.max(point + Vector2(32.0, 32.0))
	return size
