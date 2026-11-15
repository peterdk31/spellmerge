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

## The rooms found by their scene's path (null for a scene no room names), and the cover kinds found
## under each content root, until `forget`.
static var _rooms: Dictionary[String, RoomBase] = {}
static var _kinds: Dictionary[String, Array] = {}


## Floats a tuft takes in `tufts`: its kind's index in the layout, its foot (x, y), its frame and
## 1 or -1 (mirrored).
const TUFT_STRIDE: int = 5


## The cover kinds there are, as the game's registry finds them (under `content_root`: a test's),
## those that can be drawn (`usable`), as the game takes them; read once until `forget`.
static func kinds(content_root: String = RegistryScript.DEFAULT_CONTENT_ROOT) -> Array[CoverKind]:
	if not _kinds.has(content_root):
		var found: Array[CoverKind] = []
		for item: Resource in RegistryScript.scan_folder(COVER_FOLDER, content_root):
			if item is CoverKind and usable(item as CoverKind):
				found.append(item as CoverKind)
		_kinds[content_root] = found
	var kept: Array[CoverKind] = []
	kept.assign(_kinds[content_root])
	return kept


## True for a kind the game lays (Feel's look; the cover area, GC5): one with no problems
## (`CoverKind.problems`, its own data checked), so a broken kind is in no room's cover, the
## editor's included.
static func usable(kind: CoverKind) -> bool:
	return kind != null and kind.problems().is_empty()


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
	return _rooms[scene_path]


## Look for the rooms and the kinds again (a room's `.tres` or a cover kind made or changed).
static func forget() -> void:
	_rooms.clear()
	_kinds.clear()


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


## The z the editor draws cover at: the game's (`RoomBase.FLOOR_Z + 1`, the floor marks'), so the
## editor shows it under every prop, stand-in and wall as the game does.
const Z: int = RoomBase.FLOOR_Z + 1


## Draw `item`'s own drawing at `Z`, set on the server alone so no scene saves it.
static func lay_under(item: CanvasItem) -> void:
	RenderingServer.canvas_item_set_z_index(item.get_canvas_item(), Z)


## True when `scene_root`'s scene holds a preview of its cover (a `RoomPreview` that draws it), which
## then draws every field's tufts.
static func previewed(scene_root: Node) -> bool:
	for found in scene_root.find_children("*", "RoomPreview", true, false):
		if (found as RoomPreview).draws_cover():
			return true
	return false


## The cover of `scene_root`, a room's scene as edited, with the kinds there are (under
## `content_root`).
static func layout_of(scene_root: Node, content_root: String = RegistryScript.DEFAULT_CONTENT_ROOT) -> CoverLayout:
	return CoverLayout.of(scene_root, room_of(scene_root.scene_file_path), kinds(content_root))


## The tufts of `layout`'s cells whose middles lie in `within` (room pixels; an empty rectangle:
## every cell), each kind's first state, kind by kind in the layout's order, each kind's in the order
## they are drawn (`CoverTufts.draw_key`): the rows Feel lays (`gameplay/feel/cover.gd`), in its
## order. TUFT_STRIDE floats each; a kind with no sheet, and a tuft its state draws no frame for, has
## none.
static func tufts(layout: CoverLayout, within: Rect2 = Rect2()) -> PackedFloat32Array:
	var found := PackedFloat32Array()
	var every: bool = not within.has_area()
	for index in layout.kinds.size():
		var kind: CoverKind = layout.kinds[index]
		if kind.sheet == null or kind.states.is_empty() or kind.states[0] == null:
			continue
		var frames: PackedInt32Array = kind.states[0].frames
		var kind_key: int = CoverLayout.name_hash(kind.id)
		var listed := PackedFloat32Array()
		var keys := PackedInt64Array()
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
				keys.append(CoverTufts.draw_key(foot, keys.size()))
				listed.append_array(PackedFloat32Array([float(index), foot.x, foot.y, float(shown), -1.0 if CoverTufts.mirrored(rolled) else 1.0]))
		keys.sort()
		for key in keys:
			var at: int = CoverTufts.slot_of(key) * TUFT_STRIDE
			found.append_array(listed.slice(at, at + TUFT_STRIDE))
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
