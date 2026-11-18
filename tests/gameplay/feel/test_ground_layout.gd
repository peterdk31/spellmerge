extends "res://tests/support/suite.gd"
## The ground drawn when a room is laid out (connected biomes CB4, gameplay/feel/ground/ground_layout.gd):
## Feel's part hears `room_built` and draws a room's ground again from its shape onto the layout's
## `Floor` before it is shown (its floor, glow and rock face as drawn textures, its rims made again),
## mirrored when the layout says so; the hub, which names no shape, keeps its baked art; and it is
## quick: it says how long each crypt room took (`GROUND LAYOUT` lines), and, with the native module,
## a room is drawn within `MOST_MS` (no load stall), and on one thread (the web's) too, which it
## reports; without the module an unmirrored room keeps its baked art rather than stall.
# unit-test-alone
const LayoutScript := preload("res://gameplay/feel/ground/ground_layout.gd")
const ShapeScript := preload("res://gameplay/feel/ground/ground_shape.gd")
const EventsScript := preload("res://core/events/events.gd")
const NativeScript := preload("res://core/native/native.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const ROOMS: StringName = &"rooms"
## The most a crypt room's ground may take to draw at layout with the native module, in ms: a few
## frames at most, on a slow machine (it takes a few tens of ms on four cores).
const MOST_MS: float = 150.0


func _registry() -> RegistryScript:
	return root.get_node("/root/Registry") as RegistryScript


func _part() -> LayoutScript:
	var part: LayoutScript = LayoutScript.new()
	part.registry = _registry()
	return own(part) as LayoutScript


func _crypt_rooms() -> Array[RoomBase]:
	var found: Array[RoomBase] = []
	for item: Resource in _registry().get_all(ROOMS):
		var room := item as RoomBase
		if room != null and room.ground_shape != null:
			found.append(room)
	return found


func _native_or_say() -> bool:
	if NativeScript.loaded():
		return true
	check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded")
	return false


func test_a_laid_room_gets_its_ground_drawn_quickly() -> void:
	if not _native_or_say():
		return
	var part: LayoutScript = _part()
	var rooms: Array[RoomBase] = _crypt_rooms()
	check(not rooms.is_empty(), "the crypt's rooms name their shapes")
	for room: RoomBase in rooms:
		var layout: Node = room.build()
		var ground := layout.get_node("Floor") as Sprite2D
		var baked: Texture2D = ground.texture
		var lines_before: int = _lines(ground)
		check(part.lay(room, layout), "%s: its ground is drawn as it is laid" % room.id)
		check(ground.texture is ImageTexture and ground.texture != baked, "%s: its floor is the drawn one" % room.id)
		check(ground.texture.get_size() == baked.get_size(), "%s: drawn at the baked art's size" % room.id)
		check((ground.get_node("Glow") as Sprite2D).texture is ImageTexture, "%s: its glow is drawn" % room.id)
		var under := ground.find_child("Underside", true, false) as Sprite2D
		check(under != null and under.texture is ImageTexture, "%s: its rock face is drawn" % room.id)
		check_equal(_lines(ground), lines_before, "%s: its rims and drips are made again, as many" % room.id)
		var first_ms: float = part.last_usec / 1000.0
		part.lay(room, layout)
		var again_ms: float = part.last_usec / 1000.0
		# On one thread, as the web build draws (it has no threads): the drawing alone.
		var spec: Dictionary = ShapeScript.spec(room.ground_shape.data, room.scene, _registry())
		spec["threads"] = 1
		var began: int = Time.get_ticks_usec()
		ShapeScript.draw(spec, true)
		var one_ms: float = (Time.get_ticks_usec() - began) / 1000.0
		print("GROUND LAYOUT %s %dx%d: %.1f ms, again %.1f ms; on one thread %.1f ms" % [room.id, int(baked.get_width()), int(baked.get_height()),
			first_ms, again_ms, one_ms])
		check(maxf(first_ms, again_ms) <= MOST_MS, "%s: drawn in %.1f ms, within %.0f (no load stall)" % [room.id, maxf(first_ms, again_ms), MOST_MS])
		layout.free()


func test_it_is_heard_on_room_built() -> void:
	if not _native_or_say():
		return
	var events: EventsScript = own(EventsScript.new()) as EventsScript
	var part: LayoutScript = _part()
	part.events = events
	part._ready()
	var room: RoomBase = _crypt_rooms()[0]
	var layout: Node = room.build()
	events.room_built.emit(room.id, 0, layout)
	check(part.drawn == 1, "a room laid out is drawn")
	check((layout.get_node("Floor") as Sprite2D).texture is ImageTexture, "its floor is the drawn one")
	layout.free()


func test_the_hub_keeps_its_baked_art() -> void:
	var hub: RoomBase = _registry().get_resource(ROOMS, &"hub")
	var layout: Node = hub.build()
	var baked: Texture2D = (layout.get_node("Floor") as Sprite2D).texture
	check(not _part().lay(hub, layout), "the hub names no shape, so nothing is drawn")
	check((layout.get_node("Floor") as Sprite2D).texture == baked, "its floor is the baked art")
	layout.free()


func test_a_mirrored_layout_is_drawn_mirrored() -> void:
	if not _native_or_say():
		return
	var room: RoomBase = _crypt_rooms()[0]
	var part: LayoutScript = _part()
	var plain: Node = room.build()
	part.lay(room, plain)
	var mirrored: Node = room.build()
	mirrored.set_meta(ShapeScript.MIRROR_META, Vector2i(1, 0))
	part.lay(room, mirrored)
	var a: Image = ((plain.get_node("Floor") as Sprite2D).texture as ImageTexture).get_image()
	var b: Image = ((mirrored.get_node("Floor") as Sprite2D).texture as ImageTexture).get_image()
	var same_alpha: bool = true
	for y in range(0, a.get_height(), 3):
		for x in range(0, a.get_width(), 3):
			same_alpha = same_alpha and a.get_pixel(x, y).a8 == b.get_pixel(a.get_width() - 1 - x, y).a8
	check(same_alpha, "the floor of a room mirrored left to right stands where the plain one's mirror does")
	plain.free()
	mirrored.free()


func test_without_the_module_an_unmirrored_room_keeps_its_baked_art() -> void:
	# The GDScript takes seconds; the baked art is what it would draw.
	var room: RoomBase = _crypt_rooms()[0]
	var part: LayoutScript = _part()
	part.native = false
	var layout: Node = room.build()
	var baked: Texture2D = (layout.get_node("Floor") as Sprite2D).texture
	check(not part.lay(room, layout), "nothing is drawn")
	check((layout.get_node("Floor") as Sprite2D).texture == baked, "its floor is the baked art")
	layout.free()


func _lines(ground: Node) -> int:
	var count: int = 0
	for child: Node in ground.get_children():
		if child is Line2D and child.is_in_group(MoteSource.GROUP):
			count += 1
	return count
