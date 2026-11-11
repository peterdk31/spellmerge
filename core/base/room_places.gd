class_name RoomPlaces
extends RefCounted
## What is where in a room (props W8a, docs/milestones/props.md, "W8a: a room is its scene"), read
## from its scene, the one place a position is written: a room is edited by hand in the Godot
## editor, and what is moved there is what the game reads. `RoomBase.places()` reads it once.
##
## Nothing in a room's scene runs (rooms carry no scripts), so a placed thing is a plain node, its
## data in metadata, under a node named for what it holds (children in order):
##
## - `PlayerSpawns` (by seat), `EnemySpawns`, `Doors`, `JoinerSpawns` (by seat): `Marker2D`s.
## - `Props`: each a prop's stand-in (`content/props/<id>/<id>_stand_in.tscn`: a `Sprite2D` drawing
##   its first picture where the game draws it), `metadata/prop` its `PropBase`; its position is
##   the prop's feet.
## - `Dummies`: an enemy standing in the room the same way (`metadata/enemy`, an `EnemyBase`): the
##   training and shooting dummies.
## - `Zones`: `ReferenceRect`s (drawn in the editor only) with `metadata/zone` a name. Core knows a
##   zone only by its name; what one means is the game's (the hub's `start_stone`, Flow).
##
## Positions are room pixels, through every parent up to the scene's root. Stand-ins and zones are
## the editor's: `strip` takes them out of a room the game shows, where Flow stands the real bodies.

const PLAYER_SPAWNS: StringName = &"PlayerSpawns"
const ENEMY_SPAWNS: StringName = &"EnemySpawns"
const DOORS: StringName = &"Doors"
const JOINER_SPAWNS: StringName = &"JoinerSpawns"
const PROPS: StringName = &"Props"
const DUMMIES: StringName = &"Dummies"
const ZONES: StringName = &"Zones"
## The nodes only the editor shows (`strip`).
const EDITOR_ONLY: Array[StringName] = [PROPS, DUMMIES, ZONES]
## The metadata a stand-in's data and a zone's name are under.
const PROP_META: StringName = &"prop"
const ENEMY_META: StringName = &"enemy"
const ZONE_META: StringName = &"zone"

## Where the players start (by seat), enemies may appear, the doors are, and a seat joining the
## room under way appears (by seat; empty: the player spawn farthest from danger).
var player_spawns: PackedVector2Array = PackedVector2Array()
var enemy_spawns: PackedVector2Array = PackedVector2Array()
var doors: PackedVector2Array = PackedVector2Array()
var joiner_spawns: PackedVector2Array = PackedVector2Array()
## The props it stands and where (their feet), one place a prop, in the scene's order.
var props: Array[PropBase] = []
var prop_places: PackedVector2Array = PackedVector2Array()
## The enemies standing in it (dummies) and where, in the scene's order.
var dummies: Array[EnemyBase] = []
var dummy_places: PackedVector2Array = PackedVector2Array()
## Its zones: a name and a rectangle each, in the scene's order.
var zone_names: Array[StringName] = []
var zone_rects: Array[Rect2] = []
var _problems: PackedStringArray = PackedStringArray()


## The places of the room scene `layout` (an instance, in the tree or not; left as it is).
static func read(layout: Node) -> RoomPlaces:
	var places := RoomPlaces.new()
	if layout == null:
		return places
	places.player_spawns = _points(layout, PLAYER_SPAWNS)
	places.enemy_spawns = _points(layout, ENEMY_SPAWNS)
	places.doors = _points(layout, DOORS)
	places.joiner_spawns = _points(layout, JOINER_SPAWNS)
	for node in _children(layout, PROPS):
		var data := _meta(node, PROP_META) as PropBase
		if data == null or not node is Node2D:
			places._problems.append("%s/%s has no prop (metadata/%s, a PropBase): drag a prop's stand-in in." % [PROPS, node.name, PROP_META])
			continue
		places.props.append(data)
		places.prop_places.append(at(node as Node2D, layout))
	for node in _children(layout, DUMMIES):
		var enemy := _meta(node, ENEMY_META) as EnemyBase
		if enemy == null or not node is Node2D:
			places._problems.append("%s/%s has no enemy (metadata/%s, an EnemyBase): drag an enemy's stand-in in." % [DUMMIES, node.name, ENEMY_META])
			continue
		places.dummies.append(enemy)
		places.dummy_places.append(at(node as Node2D, layout))
	for node in _children(layout, ZONES):
		var name: StringName = StringName(str(_meta(node, ZONE_META))) if node.has_meta(ZONE_META) else &""
		var rect := node as Control
		if name == &"" or rect == null:
			places._problems.append("%s/%s is no zone: a ReferenceRect with metadata/%s, its name." % [ZONES, node.name, ZONE_META])
			continue
		places.zone_names.append(name)
		places.zone_rects.append(rect_of(rect, layout))
	return places


## The first zone named `name` (an empty rectangle when it has none).
func zone(name: StringName) -> Rect2:
	var i: int = zone_names.find(name)
	return zone_rects[i] if i >= 0 else Rect2()


## What is wrong with its scene, one line each (empty when nothing is): a stand-in with no data, a
## zone with no name.
func problems() -> PackedStringArray:
	return _problems


## Take the editor's nodes (stand-ins, zones) out of `layout`, a room scene the game is about to
## show (not yet in the tree): they are freed at once.
static func strip(layout: Node) -> void:
	for holder: StringName in EDITOR_ONLY:
		var node: Node = layout.get_node_or_null(NodePath(String(holder)))
		if node != null:
			layout.remove_child(node)
			node.free()


## Where `node` stands in room pixels: its position through every parent up to `layout`.
static func at(node: Node2D, layout: Node) -> Vector2:
	return _to_room(node.get_parent(), layout) * node.position


## The rectangle a zone covers in room pixels (its offsets: a zone's anchors are left at 0).
static func rect_of(rect: Control, layout: Node) -> Rect2:
	var xf: Transform2D = _to_room(rect.get_parent(), layout)
	var corner := Vector2(rect.offset_left, rect.offset_top)
	var far := Vector2(rect.offset_right, rect.offset_bottom)
	return Rect2(xf * corner, Vector2.ZERO).expand(xf * far)


## The transform from `node`'s space to `layout`'s (identity at the layout itself).
static func _to_room(node: Node, layout: Node) -> Transform2D:
	var xf := Transform2D.IDENTITY
	var up: Node = node
	while up != null and up != layout:
		if up is Node2D:
			xf = (up as Node2D).transform * xf
		up = up.get_parent()
	return xf


## `node`'s metadata `key`, or null when it has none.
static func _meta(node: Node, key: StringName) -> Variant:
	return node.get_meta(key) if node.has_meta(key) else null


static func _children(layout: Node, holder: StringName) -> Array[Node]:
	var node: Node = layout.get_node_or_null(NodePath(String(holder)))
	return node.get_children() if node != null else [] as Array[Node]


static func _points(layout: Node, holder: StringName) -> PackedVector2Array:
	var points := PackedVector2Array()
	for node in _children(layout, holder):
		if node is Node2D:
			points.append(at(node as Node2D, layout))
	return points
