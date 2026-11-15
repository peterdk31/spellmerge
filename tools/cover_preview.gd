@tool
class_name CoverPreview
extends RoomPreview
## The whole room's ground cover in the editor (ground cover GC3, docs/milestones/ground-cover.md,
## rule 7): add one to a room's scene (Add Child Node, "CoverPreview"; anywhere, at the scene's
## corner) and it draws the cover the game will lay there, from `CoverLayout.of` (the biome's fill and
## the fields, never under a wall or on a door, a spawn or a placement), with the same tufts Feel draws
## (`CoverSketch`, `CoverTufts`), still and at rest. Moving a field, a wall or a spawn moves the grass:
## it looks at the room again every `LOOK_EVERY` seconds and draws again when its cover changed. It
## draws at the game's z (`CoverSketch.Z`), under the props and walls, and with it in the scene the
## fields draw only their outlines. A change to a kind's look alone is seen after `look_again`.
##
## The game never shows it: it is a `RoomPreview`, which `RoomPlaces` passes over and takes out of
## the room before play. An editor script (the owner's decision of 2026-11-11), so it lives in tools/.

## Seconds between two looks at the room in the editor.
const LOOK_EVERY: float = 0.5

## Draw the cover (off: the room as it is, for placing things under it).
@export var show_cover: bool = true:
	set(value):
		show_cover = value
		queue_redraw()
## Look for the room's `.tres` and the cover kinds again (a kind or a room made since).
@export var look_again: bool = false:
	set(value):
		look_again = false
		CoverSketch.forget()
		_last = PackedByteArray()
		queue_redraw()

## Where the cover kinds are found (the game's content; a test's own).
var content_root: String = CoverSketch.RegistryScript.DEFAULT_CONTENT_ROOT
## How many tufts its last drawing drew.
var drawn: int = 0
## The cells drawn last (a change redraws), and the seconds since the last look.
var _last: PackedByteArray = PackedByteArray()
var _since: float = 0.0


func _ready() -> void:
	CoverSketch.lay_under(self)
	set_process(Engine.is_editor_hint())


## It draws the room's cover: the fields leave their tufts to it (`RoomPreview`).
func draws_cover() -> bool:
	return true


func _process(delta: float) -> void:
	_since += delta
	if _since < LOOK_EVERY or not show_cover:
		return
	_since = 0.0
	var root: Node = CoverSketch.scene_root(self)
	if root == null:
		return
	var cells: PackedByteArray = CoverSketch.layout_of(root, content_root).cells
	if cells != _last:
		_last = cells
		queue_redraw()


## The room's cover, its corner at the scene's (whatever this node's own place).
func _draw() -> void:
	drawn = 0
	var root: Node = CoverSketch.scene_root(self)
	if show_cover and root != null:
		drawn = CoverSketch.draw(self, CoverSketch.layout_of(root, content_root), _room_position(root))


## Its own place in the room's pixels (the 2D nodes above it and its own position).
func _room_position(root: Node) -> Vector2:
	var at: Vector2 = position
	var node: Node = get_parent()
	while node != null and node != root:
		if node is Node2D:
			at += (node as Node2D).position
		node = node.get_parent()
	return at

