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
## One rule a thing, by what it is:
##
## - a sprite (`Sprite2D`): its drawn box is mirrored, so a wall's sprite covers its wall's mirrored
##   box exactly (the grid's cells);
## - an instanced decal (candles, a torch, the shaft): moved as one, its own nodes with it, by the box
##   of the sprites it lays on the floor (candles' wax: not its light, a glow or a shaft, which falls
##   on anything), so that box lies over the floor its mirror image frees; with none (the shaft), by
##   its place, its feet, as a prop's feet are mirrored (`RoomPlaces.placed_in`);
## - a shade (`Polygon2D`): it moves with the wall it lies on (the template's wall its box overlaps
##   most; none: its own box is mirrored), so it keeps falling to the lower right of it;
## - any other node with children (`Walls`, `Decor`, `Shade`): a holder, each child its own thing;
##   with none, its place is mirrored.
##
## Left where they are: the `Floor` (drawn again mirrored), the collision (the template's, which every
## reader mirrors itself), and the editor's placements, zones, sockets, previews and markers (read
## mirrored by `RoomPlaces`, then stripped). View only: it moves no node the simulation reads.

const FLOOR: StringName = &"Floor"
## Set on a layout whose art was put (`place`): a layout is put once, however often it is heard.
const PLACED_META: StringName = &"art_mirrored"


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
	_put(piece, piece, Transform2D.IDENTITY, PieceShape.of(piece), mirror)
	return true


## Each thing under `node` (in the layout `root`; its transform from the layout is `above`) moved to
## its mirror image.
static func _put(root: Node, node: Node, above: Transform2D, shape: PieceShape, mirror: int) -> void:
	for child: Node in node.get_children():
		var item := child as Node2D
		if item == null or _left(item, node == root):
			continue
		var xf: Transform2D = above * item.transform
		var box: Rect2
		if item.scene_file_path != "":
			box = _decal_box(item, xf)
		elif item is Sprite2D:
			box = xf * (item as Sprite2D).get_rect()
		elif item is Polygon2D:
			box = _shaded_wall(item as Polygon2D, xf, shape)
		elif item.get_child_count() > 0:
			_put(root, item, xf, shape, mirror)
			continue
		else:
			box = Rect2(xf.origin, Vector2.ZERO)
		var moved: Rect2 = shape.flip_rect(box, mirror)
		item.position += above.basis_xform_inv(moved.position - box.position)


## True for a node `place` leaves where it is (the class doc); `at_root`: a child of the layout's root.
static func _left(item: Node2D, at_root: bool) -> bool:
	if at_root and StringName(item.name) == FLOOR:
		return true
	return item is CollisionShape2D or item is CollisionPolygon2D or item is Marker2D \
		or item is RoomPlacement or item is RoomSocket or item is RoomPreview


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


## The box a shade moves by: the template's wall its own box overlaps most, else its own box.
static func _shaded_wall(shade: Polygon2D, xf: Transform2D, shape: PieceShape) -> Rect2:
	var points: PackedVector2Array = shade.polygon
	if points.is_empty():
		return Rect2(xf.origin, Vector2.ZERO)
	var own := Rect2(xf * (points[0] + shade.offset), Vector2.ZERO)
	for point: Vector2 in points:
		own = own.expand(xf * (point + shade.offset))
	var best := Rect2()
	var most: float = 0.0
	for wall: Rect2 in shape.walls:
		var area: float = wall.intersection(own).get_area()
		if area > most:
			most = area
			best = wall
	return best if most > 0.0 else own
