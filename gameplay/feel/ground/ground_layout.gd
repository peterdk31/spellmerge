extends Node
## The ground drawn when a room is laid out (connected biomes CB4, docs/milestones/connected-biomes.md,
## decision 6): Feel's part that hears each `room_built` (Flow, whenever it lays a room out) and, for a
## room whose `RoomBase.ground_shape` names its shape, draws its ground again from that shape as the
## room is placed (mirrored or not: the layout's `GroundShape.MIRROR_META`) and puts it on the
## layout's `Floor` before it is shown (`GroundShape.apply`). A room with no shape named (the hub)
## keeps its baked art. View only: it changes no node the simulation reads (the walls' and holes'
## bodies stay the layout's).
##
## No load stall: the native module draws a crypt room in a few tens of milliseconds on the module's
## threads (`GroundKernel.draw`); `last_usec` holds how long the last room took, drawing and
## textures together (tests/gameplay/feel/test_ground_layout.gd reports it). Without the module an
## unmirrored room keeps its baked art, which is what would be drawn, rather than stall for seconds.

const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ShapeScript := preload("res://gameplay/feel/ground/ground_shape.gd")
const NativeScript := preload("res://core/native/native.gd")
const MirroredArtScript := preload("res://gameplay/feel/ground/mirrored_art.gd")

const ROOM_FOLDER: StringName = &"rooms"
const FLOOR: StringName = &"Floor"

## The bus and the registry (Feel's; null in a test that lays a layout itself).
var events: EventsScript = null
var registry: RegistryScript = null
## Whether the native module draws when it is loaded (off: the GDScript, for tests).
var native: bool = true
## How many rooms' grounds were drawn, and how long the last took (drawing and textures), in µs.
var drawn: int = 0
var last_usec: int = 0


func _ready() -> void:
	if events != null and not events.room_built.is_connected(_on_room_built):
		events.room_built.connect(_on_room_built)


## Every piece of a biome too (connected biomes CB3), each drawn on its own layout; a mirrored
## piece's other art is put where its mirror image stands first (`mirrored_art.gd`), so it lies
## over its mirrored walls and floor.
func _on_room_built(room_id: StringName, _room: int, layout_root: Node) -> void:
	MirroredArtScript.place(layout_root)
	var room: RoomBase = registry.get_resource(ROOM_FOLDER, room_id) as RoomBase if registry != null else null
	if room != null:
		lay(room, layout_root)


## Draw `room`'s ground onto `layout_root`, its layout as built (nothing when the room names no shape
## or the layout has no `Floor` sprite). True when it was drawn.
func lay(room: RoomBase, layout_root: Node) -> bool:
	if room.ground_shape == null or layout_root == null or registry == null:
		return false
	var ground := layout_root.get_node_or_null(NodePath(FLOOR)) as Sprite2D
	if ground == null or not (room.ground_shape.data is Dictionary):
		return false
	var began: int = Time.get_ticks_usec()
	var mirror: Vector2i = layout_root.get_meta(ShapeScript.MIRROR_META, Vector2i.ZERO)
	# Without the native module the GDScript would take seconds; an unmirrored room's baked art is what
	# it would draw, so it stays (a mirrored one is drawn all the same: it has no other art).
	if mirror == Vector2i.ZERO and not (native and NativeScript.loaded()):
		return false
	var spec: Dictionary = ShapeScript.spec(room.ground_shape.data, room.scene, registry, mirror)
	if spec.is_empty():
		return false
	ShapeScript.apply(ground, ShapeScript.draw(spec, native), spec)
	last_usec = Time.get_ticks_usec() - began
	drawn += 1
	return true
