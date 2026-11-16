class_name RoomPlaces
extends RefCounted
## What is where in a room (props W8a/W8c, docs/milestones/props.md), read from the instance of its
## layout the game shows (`RoomBase.build()`, `read`): a room is edited by hand in the Godot editor,
## or put together from pieces (M3), and what is in it is what the game reads.
##
## Found at any depth, in the tree's order, so a piece of scene carries its own:
##
## - spawns and doors: `Marker2D`s under a node named `PlayerSpawns` (by seat), `EnemySpawns`,
##   `Doors` or `JoinerSpawns` (by seat);
## - what stands in it: every `RoomPlacement` (a prop's `PropStandIn`, an enemy's `EnemyStandIn`,
##   tools/), its data (`placed()`) and its position, the feet of what stands there;
## - its zones: every `RoomZone`, a name, a rectangle and its data (`RoomZone.data()`: a cover
##   field's `CoverPatch`, ground cover GC2; null for a plain zone).
##
## **Places are whole translations:** a position is the sum of the positions up the tree, never
## through a rotation, skew or scale (those go through the engine's trigonometry, which differs
## between platforms: the game's places must be the same on every machine); a place under a node
## that has one is one of `problems()` (art elsewhere may be mirrored or turned freely). Placements and zones are the editor's: `strip` takes them out of
## the room the game shows, where the game stands the real bodies; so is an editor's preview
## (`RoomPreview`: the whole room's cover, ground cover GC3), which places nothing and is passed over.

const PLAYER_SPAWNS: StringName = &"PlayerSpawns"
const ENEMY_SPAWNS: StringName = &"EnemySpawns"
const DOORS: StringName = &"Doors"
const JOINER_SPAWNS: StringName = &"JoinerSpawns"
const POINT_HOLDERS: Array[StringName] = [PLAYER_SPAWNS, ENEMY_SPAWNS, DOORS, JOINER_SPAWNS]

## Where the players start (by seat), enemies may appear, the doors are, and a seat joining the
## room under way appears (by seat; empty: the player spawn farthest from danger).
var player_spawns: PackedVector2Array = PackedVector2Array()
var enemy_spawns: PackedVector2Array = PackedVector2Array()
var doors: PackedVector2Array = PackedVector2Array()
var joiner_spawns: PackedVector2Array = PackedVector2Array()
## What stands in it: each placement's data and where, in the tree's order.
var placed: Array[Resource] = []
var placed_at: PackedVector2Array = PackedVector2Array()
## Its zones: a name, a rectangle and its data each, in the tree's order (a zone with data may
## have no name: &""; a plain zone's data is null).
var zone_names: Array[StringName] = []
var zone_rects: Array[Rect2] = []
var zone_data: Array[Resource] = []
## Its size in pixels from (0, 0) (`size_of`).
var size: Vector2 = Vector2.ZERO
var _problems: PackedStringArray = PackedStringArray()


## The places of `layout`, a room's layout (an instance, in the tree or not; left as it is).
static func read(layout: Node) -> RoomPlaces:
	var places := RoomPlaces.new()
	if layout == null:
		places.size = Vector2(640.0, 360.0)
		return places
	places._walk(layout, Vector2.ZERO, "", "")
	places.size = places._size_of(layout)
	places._check_corner(layout)
	return places


## The indices into the zones of those whose data is of class `kind` (`CoverPatch`), in order.
func zones_of(kind: Script) -> PackedInt32Array:
	var found := PackedInt32Array()
	for i in zone_data.size():
		if zone_data[i] != null and is_instance_of(zone_data[i], kind):
			found.append(i)
	return found


## The indices into `placed` of the data of class `kind` (`PropBase`, `EnemyBase`), in order.
func of_kind(kind: Script) -> PackedInt32Array:
	var found := PackedInt32Array()
	for i in placed.size():
		if is_instance_of(placed[i], kind):
			found.append(i)
	return found


## The placed data of class `kind`, in order.
func placed_of(kind: Script) -> Array[Resource]:
	var found: Array[Resource] = []
	for i in of_kind(kind):
		found.append(placed[i])
	return found


## Where the placed data of class `kind` stand, in order.
func placed_at_of(kind: Script) -> PackedVector2Array:
	var found := PackedVector2Array()
	for i in of_kind(kind):
		found.append(placed_at[i])
	return found


## The first zone named `name` (an empty rectangle when it has none, or for no name).
func zone(name: StringName) -> Rect2:
	var i: int = zone_names.find(name) if name != &"" else -1
	return zone_rects[i] if i >= 0 else Rect2()


## What is wrong with its layout, one line each (empty when nothing is): a placement with nothing
## picked, a zone with no name and no data, a place under a rotated, skewed or scaled node.
func problems() -> PackedStringArray:
	return _problems


## Take every placement, zone and preview (`RoomPreview`) out of `layout`, a room the game is about
## to show (not yet in the tree), wherever they are: they are freed at once.
static func strip(layout: Node) -> void:
	for child in layout.get_children():
		if child is RoomPlacement or child is RoomZone or child is RoomPreview:
			layout.remove_child(child)
			child.free()
		else:
			strip(child)


## The places under `node`, whose own place is `at` (`path` names it in a problem; `bent` names a
## rotated, skewed or scaled node above it, "" for none: only a place under one is a problem, so
## art may be mirrored or turned freely).
func _walk(node: Node, at: Vector2, path: String, bent: String) -> void:
	for child in node.get_children():
		if child is RoomPreview:
			continue
		var here: Vector2 = at
		var below: String = bent
		var named: String = "%s/%s" % [path, child.name] if path != "" else String(child.name)
		if child is Node2D:
			var moved := child as Node2D
			if below == "" and (moved.rotation != 0.0 or moved.skew != 0.0 or moved.scale != Vector2.ONE):
				below = named
			here = at + moved.position
		if below != "" and (child is RoomPlacement or child is RoomZone or (child is Marker2D and StringName(node.name) in POINT_HOLDERS)):
			_problems.append("%s lies under %s, which is rotated, skewed or scaled: places are whole translations; undo it." % [named, below])
		if child is RoomPlacement:
			var data: Resource = (child as RoomPlacement).placed()
			if data == null:
				_problems.append("%s places nothing: pick what stands there in the Inspector." % named)
			else:
				placed.append(data)
				placed_at.append(here)
			continue
		if child is RoomZone:
			var zone_node := child as RoomZone
			var held: Resource = zone_node.data()
			if zone_node.zone_name == &"" and held == null:
				_problems.append("%s is a zone with no name." % named)
			else:
				zone_names.append(zone_node.zone_name)
				zone_rects.append(Rect2(at + Vector2(zone_node.offset_left, zone_node.offset_top), Vector2(zone_node.offset_right - zone_node.offset_left, zone_node.offset_bottom - zone_node.offset_top)))
				zone_data.append(held)
			continue
		if child is Marker2D:
			match StringName(node.name):
				PLAYER_SPAWNS:
					player_spawns.append(here)
				ENEMY_SPAWNS:
					enemy_spawns.append(here)
				DOORS:
					doors.append(here)
				JOINER_SPAWNS:
					joiner_spawns.append(here)
		_walk(child, here, named, below)


## The rectangles of `layout`'s walls (a room's layout, in the tree or not), in room pixels, in the
## tree's order: each rectangle shape of a static body on the wall layer (`RoomBase.WALL_LAYER`), as
## the box round its corners (a wall is never turned: places are whole translations). The room's size
## (`size`) and its cover (`CoverLayout.of`, ground cover GC2) are read from them.
static func wall_rects(layout: Node) -> Array[Rect2]:
	return _layer_rects(layout, false)


## The rectangles of `layout`'s holes (hub rework HR-H1), as `wall_rects` reads walls: each rectangle
## shape of a static body whose layer is exactly the hole layer (`RoomBase.HOLE_LAYER`; a body also on
## the wall layer is a wall). Where one overlaps a wall, the wall wins (the projectile manager's
## grids, `ProjectileManager.is_hole`). The room's size (`size`) counts them.
static func hole_rects(layout: Node) -> Array[Rect2]:
	return _layer_rects(layout, true)


## The rectangles of `layout`'s walls (`holes` false) or holes (true); see `wall_rects`.
static func _layer_rects(layout: Node, holes: bool) -> Array[Rect2]:
	var found: Array[Rect2] = []
	if layout == null:
		return found
	for node: Node in layout.find_children("*", "StaticBody2D", true, false):
		var body := node as StaticBody2D
		if holes != (body.collision_layer == RoomBase.HOLE_LAYER) or (not holes and (body.collision_layer & RoomBase.WALL_LAYER) == 0):
			continue
		for child: Node in body.get_children():
			var shape := child as CollisionShape2D
			var box := shape.shape as RectangleShape2D if shape != null else null
			if box == null:
				continue
			# The layout may not be in the tree yet: its transform is walked by hand.
			var xf: Transform2D = shape.transform
			var up: Node = body
			while up != null and up != layout:
				if up is Node2D:
					xf = (up as Node2D).transform * xf
				up = up.get_parent()
			var half: Vector2 = box.size * 0.5
			var first: Vector2 = xf * half
			var wall := Rect2(first, Vector2.ZERO)
			for corner: Vector2 in [-half, Vector2(half.x, -half.y), Vector2(-half.x, half.y)]:
				wall = wall.expand(xf * corner)
			found.append(wall)
	return found


## The room starts at (0, 0) (docs/DECISIONS.md, 2026-11-12, "the world draws its bodies by their
## feet"): Flow's world draws its children by their place, the layout as one piece at its own, so
## the layout's root stays at (0, 0) and nothing stands above or left of it, or a body there would
## be drawn under the floor.
func _check_corner(layout: Node) -> void:
	var root := layout as Node2D
	if root != null and root.position != Vector2.ZERO:
		_problems.append("the room's root %s is at %s: put it back at (0, 0), and move what is in it instead." % [root.name, root.position])
	var points := PackedVector2Array()
	for list: PackedVector2Array in [player_spawns, enemy_spawns, doors, joiner_spawns, placed_at]:
		points.append_array(list)
	for at in points:
		if at.x < 0.0 or at.y < 0.0:
			_problems.append("a spawn, door or placement at %s lies above or left of the room's corner (0, 0): move it into the room." % at)


## The room's size in pixels, from (0, 0): at least 640×360, every spawn and door a tile in, its
## `Floor` sprite (the whole room, under the walls, in a crypt) and its walls' and holes' rectangles
## (a room whose floor is not one rectangle: the hub's island, the void round it). The room Flow
## makes is this size (its camera's limits).
func _size_of(layout: Node) -> Vector2:
	var most := Vector2(640.0, 360.0)
	var floor_sprite := layout.get_node_or_null("Floor") as Sprite2D
	if floor_sprite != null and floor_sprite.texture != null:
		var extent: Vector2 = floor_sprite.region_rect.size if floor_sprite.region_enabled else floor_sprite.texture.get_size()
		most = most.max(floor_sprite.position + extent)
	for wall: Rect2 in wall_rects(layout):
		most = most.max(wall.end)
	for hole: Rect2 in hole_rects(layout):
		most = most.max(hole.end)
	for points: PackedVector2Array in [player_spawns, enemy_spawns, doors]:
		for point: Vector2 in points:
			most = most.max(point + Vector2(32.0, 32.0))
	return most
