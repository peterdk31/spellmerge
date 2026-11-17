extends RefCounted
## Helpers for tests of a room scene (content/rooms/**): read the markers and the wall
## collision rectangles out of the instantiated scene, and find the rooms a run's map can pick.

const RegistryScript := preload("res://core/registry/registry.gd")
const PinnedRun := preload("res://tests/support/pinned_run.gd")


## Every room template a run's map can pick (a room that hosts a kind, content/rooms/README.md), by
## id, found by folder: a new template is checked the day it lands. `registry` has been scanned. A
## test's pinned copy of a room (tests/support/pinned_run.gd) is not one.
static func templates(registry: RegistryScript) -> Array[RoomBase]:
	var found: Array[RoomBase] = []
	for room: RoomBase in registry.run_content().rooms:
		if not room.kinds.is_empty() and not String(room.id).begins_with(PinnedRun.PREFIX):
			found.append(room)
	found.sort_custom(func(a: RoomBase, b: RoomBase) -> bool: return String(a.id) < String(b.id))
	return found


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


## The rectangles of the room's walls (RectangleShape2D shapes of its wall-layer bodies, at any depth).
static func wall_rects(root: Node) -> Array[Rect2]:
	# The game's own reader: walls at any depth (a room's ground drawn from a shape keeps its walls
	# in the instanced ground scene, hub rework HR2), each where it really is.
	return RoomPlaces.wall_rects(root)


## The room's extent: the box round its wall rectangles (a crypt room's border holds the rest).
static func wall_bounds(root: Node) -> Rect2:
	var rects: Array[Rect2] = wall_rects(root)
	if rects.is_empty():
		return Rect2()
	var box: Rect2 = rects[0]
	for rect in rects:
		box = box.merge(rect)
	return box


## The area a Sprite2D covers: its region, or the whole texture.
static func sprite_rect(sprite: Sprite2D) -> Rect2:
	var size: Vector2 = sprite.region_rect.size if sprite.region_enabled else sprite.texture.get_size()
	return Rect2(sprite.position, size)


## The game scripts in a room's scene: none is allowed. Its placements and zones (`RoomPlacement`,
## `RoomZone`, props W8c) and its previews (`RoomPreview`, ground cover GC3) are not counted: editor
## scripts holding what stands where or showing what the game works out, taken out before play.
static func scripts_below(node: Node) -> int:
	if node is RoomPlacement or node is RoomZone or node is RoomPreview:
		return 0
	var count: int = 1 if node.get_script() != null else 0
	for child in node.get_children():
		count += scripts_below(child)
	return count


## What keeps `room` (its layout instanced as `root`) from being a floating crypt room (crypt rework,
## docs/milestones/crypt-rework.md, the owner's second round), one line each: its floor the ground
## drawn from its shape with no wall art (its edge an invisible wall over the dark), its own `Void`
## behind the slab, a crypt room's `ambient` (rule 6), its floor-mark and debris colours named (rule
## 9), at least `pillars` `crypt_pillar` props, its two exits `crypt_gate` props and no old exit.
static func floating_room_problems(room: RoomBase, root: Node, pillars: int) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var ground: Node = root.get_node_or_null("Floor")
	if ground == null or not ground.has_meta(&"ground_inputs"):
		problems.append("its floor is not a ground drawn from its shape")
	elif ground.get_node_or_null("Walls/WallArt") != null:
		problems.append("its ground draws wall art: a floating room's edge is an invisible wall over the dark")
	var void_art: Sprite2D = root.get_node_or_null("Void") as Sprite2D
	if void_art == null or ground == null or void_art.z_index >= (ground as CanvasItem).z_index:
		problems.append("its own Void is not drawn behind the slab")
	if room.ambient != 0.8:
		problems.append("its ambient is %.2f, not a crypt room's 0.8 (rule 6)" % room.ambient)
	if room.floor_mark_colors.is_empty() or room.debris_colors.is_empty():
		problems.append("it does not name its floor-mark and debris colours (rule 9)")
	var ids: Dictionary[StringName, int] = {}
	for prop: Resource in room.places().placed_of(PropBase):
		var id: StringName = (prop as PropBase).id
		ids[id] = ids.get(id, 0) + 1
	if ids.get(&"crypt_pillar", 0) < pillars:
		problems.append("%d crypt_pillar props, not at least %d" % [ids.get(&"crypt_pillar", 0), pillars])
	if ids.get(&"crypt_gate", 0) != 2:
		problems.append("%d crypt gates, not its two exits" % ids.get(&"crypt_gate", 0))
	if ids.get(&"room_exit", 0) != 0:
		problems.append("an old exit stands in it")
	return problems
