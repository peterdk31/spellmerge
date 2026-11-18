@tool
class_name SocketPreview
extends RoomPreview
## A room's sockets in the editor (connected biomes CB2, docs/milestones/connected-biomes.md): add one
## to a template's scene (Add Child Node, "SocketPreview"; anywhere, at the scene's corner) and it
## draws every `RoomSocket`'s mouth as a biome will lay it: the mouth's bar across the way it faces
## (`RoomSocket.MOUTH` wide, a wall cell deep, just outside the socket), an arrow out of the slab, the
## landing inside it, and the cut a biome opens to the template's edge, outlined. A socket that breaks
## a rule (`PieceShape.problems`: off the 32 px grid, off the lip, cut off from the others) is drawn in
## red, the others in green, and the template's 32 px grid is drawn faintly under them. It looks at
## the room again every LOOK_EVERY seconds, so moving a socket or a wall shows at once; `mirror` shows
## the template as a biome would place it mirrored (the sockets and the rules only: the art is not
## flipped here).
##
## Whether the template is a walkway (`RoomBase.walkway`) is read from the room's `.tres` that names
## the scene (`CoverSketch.room_of`). The game never shows it: it is a `RoomPreview`, which `RoomPlaces` passes over and takes out of the
## room before play. An editor script (the owner's decision of 2026-11-11), so it lives in tools/.

## Seconds between two looks at the room in the editor.
const LOOK_EVERY: float = 0.5
const GOOD: Color = Color(0.35, 0.86, 0.45, 0.95)
const BAD: Color = Color(0.92, 0.3, 0.22, 0.95)
const CUT: Color = Color(0.95, 0.76, 0.19, 0.6)
const GRID_LINES: Color = Color(1.0, 1.0, 1.0, 0.07)

## Show the sockets as a biome places the template mirrored: 0 none, 1 across, 2 up and down, 3 both.
@export_range(0, 3) var mirror: int = 0:
	set(value):
		mirror = value
		_look()
## Draw the 32 px placement grid under the sockets.
@export var show_grid: bool = true:
	set(value):
		show_grid = value
		queue_redraw()

## The shape drawn last (null before the first look), its problems by socket, and the seconds since
## the editor last looked.
var shape: PieceShape = null
var broken: PackedInt32Array = PackedInt32Array()
var _since: float = 0.0


func _ready() -> void:
	set_process(Engine.is_editor_hint())
	_look()


func _process(delta: float) -> void:
	_since += delta
	if _since < LOOK_EVERY:
		return
	_since = 0.0
	_look()


## Read the room's sockets and walls again and draw them (the editor calls it; a test may too).
func _look() -> void:
	var root: Node = CoverSketch.scene_root(self)
	if root == null:
		return
	var room: RoomBase = CoverSketch.room_of(root.scene_file_path)
	shape = PieceShape.of(root, room.id if room != null else StringName(root.name), room != null and room.walkway).mirrored(mirror)
	broken = PackedInt32Array()
	for line: String in shape.problems():
		for i in shape.sockets():
			if ("socket %d " % i) in line and not broken.has(i):
				broken.append(i)
	queue_redraw()


func _draw() -> void:
	if shape == null:
		return
	if show_grid:
		var x: float = 0.0
		while x <= shape.size.x:
			draw_line(Vector2(x, 0.0), Vector2(x, shape.size.y), GRID_LINES)
			x += PieceShape.GRID
		var y: float = 0.0
		while y <= shape.size.y:
			draw_line(Vector2(0.0, y), Vector2(shape.size.x, y), GRID_LINES)
			y += PieceShape.GRID
	for i in shape.sockets():
		var colour: Color = BAD if broken.has(i) else GOOD
		var cut: Rect2 = shape.cut_rect(i)
		if cut.has_area():
			draw_rect(cut, CUT, false, 1.0)
		draw_rect(shape.strip(i, -PieceShape.LANDING, 0.0), Color(colour, 0.25), true)
		draw_rect(shape.mouth_rect(i), colour, true)
		var at: Vector2 = shape.socket_at[i]
		var way: Vector2 = shape.way_of(i)
		var tip: Vector2 = at + way * 24.0
		draw_line(at, tip, colour, 2.0)
		var side: Vector2 = Vector2(-way.y, way.x) * 5.0
		draw_line(tip, tip - way * 7.0 + side, colour, 2.0)
		draw_line(tip, tip - way * 7.0 - side, colour, 2.0)
