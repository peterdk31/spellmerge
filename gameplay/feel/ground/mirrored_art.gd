extends RefCounted
## A mirrored piece's own art put where its mirror image stands (the owner's bug of 2026-11-19: "the
## hitbox of decorations does not seem to align with the decorations" in mirrored rooms). A biome lays
## a piece mirrored (connected biomes, decision 6): its walls, holes and places are mirrored by their
## readers (`BiomeWorld`'s grid, `RoomPlaces.placed_in`, `CoverLayout.of_piece`) and its ground is drawn
## again mirrored (`GroundShape`), but the rest of its layout's art is the template's as saved: a
## sarcophagus's or a wall of bones' sprite, its shade, the rubble, skulls, candles and the shaft. So
## `place` moves each of those to its mirror image's place before the piece is shown, never flipping it
## (the light still comes from the upper left): Feel's ground part does it as it hears `room_built`.
##
## Each thing is moved as one, by a box:
##
## - a sprite (`Sprite2D`) by its drawn box, a shade (`Polygon2D`) by its points' box, an instanced
##   decal (candles, a torch, the shaft) by the box of the sprites it lays on the floor (candles' wax:
##   not its light, a glow or a shaft, which falls on anything; none: its place, its feet, as a prop's
##   feet are mirrored, `RoomPlaces.placed_in`), and any other leaf by its place;
## - **but what lies on one of the room's own walls** (a sarcophagus's or a wall of bones' sprite, the
##   shade it casts, a torch on it) moves with that wall (the one covering most of its box, at least half), so it stays
##   on it as drawn (a lid over the wall's top, a shade to its lower right), whatever its own size;
## - a node with children that is no sprite, shade or plain decal (`Walls`, `Decor`, `Shade`, a decal
##   that holds collision or places) is a holder: each child is its own thing.
##
## Left where they are: the `Floor` (drawn again mirrored), the collision (the template's, which every
## reader mirrors itself), and the editor's placements, zones, sockets, previews and spawn and door
## markers (read mirrored by `RoomPlaces`, then stripped; a `light_spot` marker in the art moves). View
## only: it moves no node the simulation reads (`tests/gameplay/feel/test_mirrored_art.gd`).

const FLOOR: StringName = &"Floor"
## Set on a layout whose art was put (`place`): a layout is put once, however often it is heard.
const PLACED_META: StringName = &"art_mirrored"
## How much of a thing's box a wall covers for it to lie on that wall (`_wall_under`).
const ON_WALL: float = 0.5


## Put the art of `layout_root` (a laid piece, `room_built`'s, before it is shown) where its
## mirroring says (`PieceShape.mirror_of`); its template's shape (`PieceShape.of`) is the extent it is
## mirrored within, the grid's. True when anything was moved: false for an unmirrored piece, or one
## put already.
static func place(layout_root: Node) -> bool:
	var piece := layout_root as Node2D
	if piece == null or piece.has_meta(PLACED_META):
		return false
	var mirror: int = PieceShape.mirror_of(piece)
	if mirror == 0:
		return false
	piece.set_meta(PLACED_META, true)
	_put(piece, piece, Transform2D.IDENTITY, PieceShape.of(piece), _own_walls(piece), mirror)
	return true


## The room's own walls (template pixels): its layout's, but its floor's (a floating room's edge).
static func _own_walls(root: Node2D) -> Array[Rect2]:
	var all: Array[Rect2] = RoomPlaces.wall_rects(root)
	var ground := root.get_node_or_null(NodePath(FLOOR)) as Node2D
	if ground == null:
		return all
	var edge: Array[Rect2] = RoomPlaces.wall_rects(ground)
	var own: Array[Rect2] = []
	for rect: Rect2 in all:
		if not edge.has(Rect2(rect.position - ground.position, rect.size)):
			own.append(rect)
	return own


## Each thing under `node` (in the layout `root`; its transform from the layout is `above`) moved to
## its mirror image.
static func _put(root: Node, node: Node, above: Transform2D, shape: PieceShape, walls: Array[Rect2], mirror: int) -> void:
	for child: Node in node.get_children():
		var item := child as Node2D
		if item == null or _left(item, node, node == root):
			continue
		var xf: Transform2D = above * item.transform
		var box: Rect2
		if item.scene_file_path != "" and not _holds_places(item):
			box = _decal_box(item, xf)
		elif item is Sprite2D:
			box = xf * (item as Sprite2D).get_rect()
		elif item is Polygon2D:
			box = _points_box(item as Polygon2D, xf)
		elif item.get_child_count() > 0:
			_put(root, item, xf, shape, walls, mirror)
			continue
		else:
			box = Rect2(xf.origin, Vector2.ZERO)
		box = _wall_under(box, walls)
		var moved: Rect2 = shape.flip_rect(box, mirror)
		item.position += above.affine_inverse().basis_xform(moved.position - box.position)


## True for a node `place` leaves where it is (the class doc): the root's `Floor` (`at_root`), the
## collision's shapes (a body is a holder: its sprites move), the editor's nodes and a spawn's or a door's marker (under `parent`).
static func _left(item: Node2D, parent: Node, at_root: bool) -> bool:
	if at_root and StringName(item.name) == FLOOR:
		return true
	if item is Marker2D:
		return StringName(parent.name) in RoomPlaces.POINT_HOLDERS
	return item is CollisionShape2D or item is CollisionPolygon2D \
		or item is RoomPlacement or item is RoomSocket or item is RoomPreview


## True for an instanced scene holding collision or the editor's places, which it must not move as one
## (their readers mirror them from where the template has them): it is walked as a holder.
static func _holds_places(decal: Node) -> bool:
	for node: Node in decal.find_children("*", "", true, false):
		if node is CollisionObject2D or node is CollisionShape2D or node is CollisionPolygon2D \
				or node is RoomPlacement or node is RoomSocket or node is RoomZone \
				or (node is Marker2D and StringName(node.get_parent().name) in RoomPlaces.POINT_HOLDERS):
			return true
	return false


## The room's own wall `box` lies on (the one it overlaps most, over at least ON_WALL of its own box:
## it moves with it), else `box` itself (the dark behind a slab, which covers every wall, is no thing
## on one).
static func _wall_under(box: Rect2, walls: Array[Rect2]) -> Rect2:
	if not box.has_area():
		return box
	var best := Rect2()
	var most: float = 0.0
	for wall: Rect2 in walls:
		var area: float = wall.intersection(box).get_area()
		if area > most:
			most = area
			best = wall
	return best if most >= box.get_area() * ON_WALL else box


## The box a decal (an instanced scene, `xf` its transform from the layout) moves by: its floor
## sprites' (not its light's), else its place.
static func _decal_box(decal: Node2D, xf: Transform2D) -> Rect2:
	var box := Rect2()
	var found: bool = false
	for node: Node in decal.find_children("*", "Sprite2D", true, false):
		var sprite := node as Sprite2D
		if is_light(sprite):
			continue
		var at: Rect2 = xf * _below(decal, sprite) * sprite.get_rect()
		box = box.merge(at) if found else at
		found = true
	return box if found else Rect2(xf.origin, Vector2.ZERO)


## The transform of `node` from `top`, one of its parents (walked by hand: the layout is not in the
## tree as it is built).
static func _below(top: Node, node: Node) -> Transform2D:
	var xf := Transform2D.IDENTITY
	var up: Node = node
	while up != null and up != top:
		if up is Node2D:
			xf = (up as Node2D).transform * xf
		up = up.get_parent()
	return xf


## True for a sprite that is light (painted light, or drawn additively: a glow, a shaft), which falls
## on anything (tests/content/rooms/test_template_art.gd reads light so).
static func is_light(sprite: Sprite2D) -> bool:
	var material: CanvasItemMaterial = sprite.material as CanvasItemMaterial
	return sprite.is_in_group(&"painted_light") or (material != null and material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD)


## The box round a shade's points (`xf` its transform from the layout); its place when it has none.
static func _points_box(shade: Polygon2D, xf: Transform2D) -> Rect2:
	var points: PackedVector2Array = shade.polygon
	if points.is_empty():
		return Rect2(xf.origin, Vector2.ZERO)
	var own := Rect2(xf * (points[0] + shade.offset), Vector2.ZERO)
	for point: Vector2 in points:
		own = own.expand(xf * (point + shade.offset))
	return own
