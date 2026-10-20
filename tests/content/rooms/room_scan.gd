extends RefCounted
## Helpers for tests of a room scene (content/rooms/**): read the markers and the wall
## collision rectangles out of the instantiated scene.


## The positions of the Marker2D children of `group` (for example "PlayerSpawns").
static func markers(root: Node, group: String) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var parent: Node = root.get_node_or_null(group)
	if parent == null:
		return points
	for child in parent.get_children():
		if child is Marker2D:
			points.append((child as Marker2D).position)
	return points


## True when every child of `group` is a Marker2D (and the group exists).
static func only_markers(root: Node, group: String) -> bool:
	var parent: Node = root.get_node_or_null(group)
	if parent == null:
		return false
	for child in parent.get_children():
		if not child is Marker2D:
			return false
	return true


## The rectangles of the RectangleShape2D collision shapes under `Walls`.
static func wall_rects(root: Node) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child in root.get_node("Walls").get_children():
		var shape_node: CollisionShape2D = child as CollisionShape2D
		if shape_node == null:
			continue
		var rectangle: RectangleShape2D = shape_node.shape as RectangleShape2D
		if rectangle != null:
			rects.append(Rect2(shape_node.position - rectangle.size * 0.5, rectangle.size))
	return rects


## The area a Sprite2D covers: its region, or the whole texture.
static func sprite_rect(sprite: Sprite2D) -> Rect2:
	var size: Vector2 = sprite.region_rect.size if sprite.region_enabled else sprite.texture.get_size()
	return Rect2(sprite.position, size)


static func scripts_below(node: Node) -> int:
	var count: int = 1 if node.get_script() != null else 0
	for child in node.get_children():
		count += scripts_below(child)
	return count
