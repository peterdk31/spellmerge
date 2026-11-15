@tool
class_name CoverField
extends RoomZone
## A field of ground cover placed by hand in a room's scene (ground cover GC2,
## docs/milestones/ground-cover.md, rule 1): a zone with data, a cover kind and a density over its
## rectangle, moved and sized by its handles. Fields lie over the biome's own fill, in the tree's
## order, each deciding its own cells: a field of no kind clears them. Read by `RoomPlaces` (its data
## beside its rectangle, `zone_data`) and `CoverLayout.of`, and taken out before play as every zone
## is (`RoomPlaces.strip`). It needs no name (`zone_name`): its data says what it is. In the editor
## it draws the tufts of its rectangle as the game will (`CoverSketch`, ground cover GC3), at the
## game's z: the room's cover worked out whole (the fill, the walls, the fields after it), so moving
## it, sizing it, changing its kind or density, or moving a wall or another field moves the grass
## (it looks again twice a second). With a `CoverPreview` in the scene, the preview draws them.

## The cover kind it puts here (a `CoverKind.id`: &"grass"); empty: it clears the cover here.
@export var kind: StringName = &"":
	set(value):
		kind = value
		queue_redraw()
## The share of its cells that get the kind (0-1); the rest get none.
@export_range(0.0, 1.0, 0.01) var density: float = 1.0:
	set(value):
		density = value
		queue_redraw()


## What it puts here (a new `CoverPatch` of its kind and density).
func data() -> Resource:
	return CoverPatch.make(kind, density)


## Where the cover kinds are found (the game's content; a test's own), whether it draws its tufts
## outside the editor too (a test's; in play it is taken out before it could), and how many its last
## drawing drew.
var content_root: String = CoverSketch.RegistryScript.DEFAULT_CONTENT_ROOT
var draws_in_play: bool = false
var drawn: int = 0
## What its last drawing was drawn from (its cells and its corner: a change draws again), and the
## seconds since the editor last looked.
var _last: PackedByteArray = PackedByteArray()
var _last_at: Vector2 = Vector2.INF
var _since: float = 0.0

## Seconds between two looks at the room in the editor.
const LOOK_EVERY: float = 0.5


func _ready() -> void:
	CoverSketch.lay_under(self)
	set_process(Engine.is_editor_hint())
	if Engine.is_editor_hint() and not item_rect_changed.is_connected(queue_redraw):
		item_rect_changed.connect(queue_redraw)


## In the editor, every LOOK_EVERY seconds: draw again when the room's cover or its own place in the
## room changed (a wall, a spawn, another field or a node above it moved).
func _process(delta: float) -> void:
	_since += delta
	if _since < LOOK_EVERY:
		return
	_since = 0.0
	if _changed():
		queue_redraw()


## Its name in its corner, and in the editor its tufts (left to the room's preview when there is
## one, so the two never disagree).
func _draw() -> void:
	super()
	drawn = 0
	if Engine.is_editor_hint() or draws_in_play:
		_draw_tufts()


## Draw the tufts of its rectangle, from the cover of the scene it is in (the edited scene's in the
## editor, else its own root's).
func _draw_tufts() -> void:
	var scene_root: Node = CoverSketch.scene_root(self)
	if scene_root == null or CoverSketch.previewed(scene_root):
		return
	var layout: CoverLayout = CoverSketch.layout_of(scene_root, content_root)
	var at: Vector2 = room_position(scene_root)
	_last = layout.cells
	_last_at = at
	drawn = CoverSketch.draw(self, layout, at, Rect2(at, size))


## True when what it would draw is not what it drew last.
func _changed() -> bool:
	var scene_root: Node = CoverSketch.scene_root(self)
	if scene_root == null or CoverSketch.previewed(scene_root):
		return drawn > 0
	return room_position(scene_root) != _last_at or CoverSketch.layout_of(scene_root, content_root).cells != _last


## Its corner in the room's pixels, as `RoomPlaces` reads it: the positions of the 2D nodes above
## it, up to `scene_root`, and its own offset.
func room_position(scene_root: Node) -> Vector2:
	var at := Vector2(offset_left, offset_top)
	var node: Node = get_parent()
	while node != null and node != scene_root:
		if node is Node2D:
			at += (node as Node2D).position
		node = node.get_parent()
	return at
