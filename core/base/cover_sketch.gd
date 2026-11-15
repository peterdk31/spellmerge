@tool
class_name CoverSketch
extends RefCounted
## The editor's drawing of a room's ground cover (ground cover GC3, docs/milestones/ground-cover.md,
## rule 7): a cover field's tufts (`CoverField`) and the whole room's (`CoverPreview`, tools/), the
## same tufts Feel's batches lay (`CoverTufts`), still and at rest (each kind's first state). It finds
## what the game is told without the `Registry` autoload, which does not run in the editor: the cover
## kinds by the registry's static scan, and the room a scene is the layout of by the rooms' `.tres`
## (`RoomBase.scene`), so its rolls are keyed by the room's id as the game's are. A scene no room
## names is drawn as a room of no id and no biome: its fields only, rolled by key 0.

const RegistryScript := preload("res://core/registry/registry.gd")
const COVER_FOLDER: StringName = &"cover"
const ROOM_FOLDER: StringName = &"rooms"

## The rooms found by their scene's path (null for a scene no room names), until `forget`.
static var _rooms: Dictionary = {}


## Floats a tuft takes in `tufts`: its kind's index in the layout, its foot (x, y), its frame and
## 1 or -1 (mirrored).
const TUFT_STRIDE: int = 5


## The cover kinds there are, as the game's registry finds them (under `content_root`: a test's).
static func kinds(content_root: String = RegistryScript.DEFAULT_CONTENT_ROOT) -> Array[CoverKind]:
	var found: Array[CoverKind] = []
	for item: Resource in RegistryScript.scan_folder(COVER_FOLDER, content_root):
		if item is CoverKind:
			found.append(item as CoverKind)
	return found


## The room whose layout is the scene saved at `scene_path` (null for none, or for "").
static func room_of(scene_path: String) -> RoomBase:
	if scene_path == "":
		return null
	if not _rooms.has(scene_path):
		_rooms[scene_path] = null
		for item: Resource in RegistryScript.scan_folder(ROOM_FOLDER):
			var room := item as RoomBase
			if room != null and room.scene != null and room.scene.resource_path == scene_path:
				_rooms[scene_path] = room
	return _rooms[scene_path] as RoomBase


## Look for the rooms again at the next `room_of` (a room's `.tres` made or changed).
static func forget() -> void:
	_rooms.clear()


## The root of the room's scene `node` is in: the edited scene's in the editor, else its owner's, else
## the top of its own tree (null when it is the top).
static func scene_root(node: Node) -> Node:
	if Engine.is_editor_hint() and node.is_inside_tree() and node.get_tree().edited_scene_root != null:
		return node.get_tree().edited_scene_root
	if node.owner != null:
		return node.owner
	var top: Node = node
	while top.get_parent() != null and not (top.get_parent() is Window):
		top = top.get_parent()
	return top if top != node else null


## The cover of `scene_root`, a room's scene as edited, with the kinds there are (under
## `content_root`).
static func layout_of(scene_root: Node, content_root: String = RegistryScript.DEFAULT_CONTENT_ROOT) -> CoverLayout:
	return CoverLayout.of(scene_root, room_of(scene_root.scene_file_path), kinds(content_root))


## The tufts of `layout`'s cells whose middles lie in `within` (room pixels; an empty rectangle:
## every cell), each kind's first state, kind by kind in the layout's order and cell by cell: the
## rows Feel lays (`gameplay/feel/cover.gd`). TUFT_STRIDE floats each; a kind with no sheet, and a
## tuft its state draws no frame for, has none.
static func tufts(layout: CoverLayout, within: Rect2 = Rect2()) -> PackedFloat32Array:
	var found := PackedFloat32Array()
	var every: bool = not within.has_area()
	for index in layout.kinds.size():
		var kind: CoverKind = layout.kinds[index]
		if kind.sheet == null or kind.states.is_empty() or kind.states[0] == null:
			continue
		var frames: PackedInt32Array = kind.states[0].frames
		var kind_key: int = CoverLayout.name_hash(kind.id)
		for cell in layout.cells.size():
			if layout.cells[cell] != index + 1:
				continue
			if not every and not within.has_point(layout.cell_rect(cell).get_center()):
				continue
			for tuft in kind.tufts_per_cell:
				var rolled: int = CoverTufts.roll(layout, kind_key, cell, tuft)
				var shown: int = CoverTufts.frame(rolled, frames)
				if shown < 0:
					continue
				var foot: Vector2 = CoverTufts.foot(layout, cell, tuft, kind.tufts_per_cell, rolled)
				found.append_array(PackedFloat32Array([float(index), foot.x, foot.y, float(shown), -1.0 if CoverTufts.mirrored(rolled) else 1.0]))
	return found


## Draw on `canvas` the tufts of `layout`'s cells whose middles lie in `within` (as `tufts`), a room
## pixel `at` drawn at `at - shift`. Returns how many tufts were drawn.
static func draw(canvas: CanvasItem, layout: CoverLayout, shift: Vector2, within: Rect2 = Rect2()) -> int:
	var found: PackedFloat32Array = tufts(layout, within)
	var count: int = found.size() / TUFT_STRIDE
	for at in count:
		var kind: CoverKind = layout.kinds[int(found[at * TUFT_STRIDE])]
		var size := Vector2(kind.frame_size)
		var foot := Vector2(found[at * TUFT_STRIDE + 1], found[at * TUFT_STRIDE + 2]) - shift
		var shown: float = found[at * TUFT_STRIDE + 3]
		canvas.draw_set_transform(foot, 0.0, Vector2(found[at * TUFT_STRIDE + 4], 1.0))
		canvas.draw_texture_rect_region(kind.sheet, Rect2(Vector2(-size.x * 0.5, -size.y), size), Rect2(Vector2(shown * size.x, 0.0), size))
	canvas.draw_set_transform(Vector2.ZERO)
	return count
