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
## - its zones: every `RoomZone`, a name and a rectangle.
##
## **Places are whole translations:** a position is the sum of the positions up the tree, never
## through a rotation, skew or scale (those go through the engine's trigonometry, which differs
## between platforms: the game's places must be the same on every machine); a node on the way that
## has one is one of `problems()`. Placements and zones are the editor's: `strip` takes them out of
## the room the game shows, where the game stands the real bodies.

const PLAYER_SPAWNS: StringName = &"PlayerSpawns"
const ENEMY_SPAWNS: StringName = &"EnemySpawns"
const DOORS: StringName = &"Doors"
const JOINER_SPAWNS: StringName = &"JoinerSpawns"

## Where the players start (by seat), enemies may appear, the doors are, and a seat joining the
## room under way appears (by seat; empty: the player spawn farthest from danger).
var player_spawns: PackedVector2Array = PackedVector2Array()
var enemy_spawns: PackedVector2Array = PackedVector2Array()
var doors: PackedVector2Array = PackedVector2Array()
var joiner_spawns: PackedVector2Array = PackedVector2Array()
## What stands in it: each placement's data and where, in the tree's order.
var placed: Array[Resource] = []
var placed_at: PackedVector2Array = PackedVector2Array()
## Its zones: a name and a rectangle each, in the tree's order.
var zone_names: Array[StringName] = []
var zone_rects: Array[Rect2] = []
## Its size in pixels from (0, 0) (`size_of`).
var size: Vector2 = Vector2.ZERO
var _problems: PackedStringArray = PackedStringArray()


## The places of `layout`, a room's layout (an instance, in the tree or not; left as it is).
static func read(layout: Node) -> RoomPlaces:
	var places := RoomPlaces.new()
	if layout == null:
		places.size = Vector2(640.0, 360.0)
		return places
	places._walk(layout, Vector2.ZERO, "")
	places.size = places._size_of(layout)
	return places


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


## The first zone named `name` (an empty rectangle when it has none).
func zone(name: StringName) -> Rect2:
	var i: int = zone_names.find(name)
	return zone_rects[i] if i >= 0 else Rect2()


## What is wrong with its layout, one line each (empty when nothing is): a placement with nothing
## picked, a zone with no name, a rotated, skewed or scaled node on the way to a place.
func problems() -> PackedStringArray:
	return _problems


## Take every placement and zone out of `layout`, a room the game is about to show (not yet in the
## tree), wherever they are: they are freed at once.
static func strip(layout: Node) -> void:
	for child in layout.get_children():
		if child is RoomPlacement or child is RoomZone:
			layout.remove_child(child)
			child.free()
		else:
			strip(child)


## The places under `node`, whose own place is `at` (`path` names it in a problem).
func _walk(node: Node, at: Vector2, path: String) -> void:
	for child in node.get_children():
		var here: Vector2 = at
		var named: String = "%s/%s" % [path, child.name] if path != "" else String(child.name)
		if child is Node2D:
			var moved := child as Node2D
			if moved.rotation != 0.0 or moved.skew != 0.0 or moved.scale != Vector2.ONE:
				_problems.append("%s is rotated, skewed or scaled: places are whole translations; undo it." % named)
			here = at + moved.position
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
			if zone_node.zone_name == &"":
				_problems.append("%s is a zone with no name." % named)
			elif zone_node.rotation != 0.0 or zone_node.scale != Vector2.ONE:
				_problems.append("%s is rotated or scaled: places are whole translations; undo it." % named)
			else:
				zone_names.append(zone_node.zone_name)
				zone_rects.append(Rect2(at + Vector2(zone_node.offset_left, zone_node.offset_top), Vector2(zone_node.offset_right - zone_node.offset_left, zone_node.offset_bottom - zone_node.offset_top)))
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
		_walk(child, here, named)


## The room's size in pixels, from (0, 0): at least 640×360, every spawn and door a tile in, its
## `Floor` sprite (the whole room, under the walls, in a crypt) and its walls' rectangles (a room
## whose floor is not one rectangle: the hub's island, the void round it all wall). The room Flow
## makes is this size (its camera's limits).
func _size_of(layout: Node) -> Vector2:
	var most := Vector2(640.0, 360.0)
	var floor_sprite := layout.get_node_or_null("Floor") as Sprite2D
	if floor_sprite != null and floor_sprite.texture != null:
		var extent: Vector2 = floor_sprite.region_rect.size if floor_sprite.region_enabled else floor_sprite.texture.get_size()
		most = most.max(floor_sprite.position + extent)
	for node: Node in layout.find_children("*", "StaticBody2D", true, false):
		var body := node as StaticBody2D
		if (body.collision_layer & RoomBase.WALL_LAYER) == 0:
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
			for corner: Vector2 in [half, -half, Vector2(half.x, -half.y), Vector2(-half.x, half.y)]:
				most = most.max(xf * corner)
	for points: PackedVector2Array in [player_spawns, enemy_spawns, doors]:
		for point: Vector2 in points:
			most = most.max(point + Vector2(32.0, 32.0))
	return most
