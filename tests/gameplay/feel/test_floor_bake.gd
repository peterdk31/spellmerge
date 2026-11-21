extends "res://tests/support/suite.gd"
## A laid room's floor baked into one texture (gameplay/feel/ground/floor_bake.gd; the owner's choice
## of 2026-11-21, after #900: "a room in view is ~1 call for its floor instead of ~7"): the bake's
## viewport holds copies of the floor, its rock face, its glow (added, by the bake's material) and
## its shades, in that order, each where it lies on the floor; once a frame was drawn after it was in
## the tree the floor shows the bake and the layers are hidden and let go, so the floor stack is one
## item drawn; Feel's ground part bakes every layout `room_built` hands over; with no renderer
## nothing is baked. Pixels: tests/screenshots/shot_baked_floors.gd holds the bake against the layers
## in one frame (a headless run draws no viewport).
const BakeScript := preload("res://gameplay/feel/ground/floor_bake.gd")
const LayoutScript := preload("res://gameplay/feel/ground/ground_layout.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## A crypt room with a floor, a rock face, a glow and shades.
const ROOM: StringName = &"arena_03"


func _room() -> RoomBase:
	return (root.get_node("/root/Registry") as RegistryScript).get_resource(&"rooms", ROOM) as RoomBase


func _bake() -> BakeScript:
	var bake := BakeScript.new()
	bake.enabled = true
	return bake


## `node`'s transform from `layout`.
func _in(node: Node, layout: Node) -> Transform2D:
	var xf := Transform2D.IDENTITY
	var at: Node = node
	while at != layout:
		if at is Node2D:
			xf = (at as Node2D).transform * xf
		at = at.get_parent()
	return xf


## The canvas items of the floor's stack shown: the floor, its rock face and glow, the shades.
func _stack_shown(layout: Node) -> int:
	var shown: int = 0
	var ground := layout.get_node("Floor") as Sprite2D
	var items: Array[CanvasItem] = [ground, ground.get_node("Glow"), ground.find_child("Underside", true, false)]
	for shade: Node in layout.get_node("Shade").get_children():
		items.append(shade as CanvasItem)
	for item: CanvasItem in items:
		if item != null and _shown(item, layout) and (not (item is Sprite2D) or (item as Sprite2D).texture != null):
			shown += 1
	return shown


## True when `item` and every holder up to `layout` are shown.
func _shown(item: Node, layout: Node) -> bool:
	var at: Node = item
	while at != null and at != layout:
		if at is CanvasItem and not (at as CanvasItem).visible:
			return false
		at = at.get_parent()
	return true


func test_the_bake_holds_the_floor_s_layers_in_order_where_they_lie() -> void:
	var layout: Node = own(_room().build())
	var ground := layout.get_node("Floor") as Sprite2D
	var shades: Array[Polygon2D] = BakeScript.shades(layout)
	check(shades.size() >= 2, "the room has shades to bake (%d)" % shades.size())
	var viewport: SubViewport = _bake().bake(layout)
	check(viewport != null and viewport.get_parent() == layout, "a viewport on the layout")
	if viewport == null:
		return
	check_equal(viewport.size, Vector2i(ground.texture.get_size()), "the floor's size")
	check(viewport.transparent_bg and viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "clear, drawn once")
	var copies: Array[Node] = viewport.get_children()
	check_equal(copies.size(), 3 + shades.size(), "the floor, its rock face, its glow and every shade")
	check((copies[0] as Sprite2D).texture == ground.texture, "the floor first")
	check((copies[1] as Sprite2D).texture == (ground.find_child("Underside", true, false) as Sprite2D).texture, "then its rock face")
	var glow := copies[2] as Sprite2D
	check(glow.texture == (ground.get_node("Glow") as Sprite2D).texture and glow.material == BakeScript.glow_material(), "then its glow, added by the bake's material")
	check(glow.transform.is_equal_approx(_in(ground.get_node("Glow"), layout)), "the glow where it lies (its scale too)")
	var to_bake: Transform2D = Transform2D(0.0, -ground.get_rect().position) * _in(ground, layout).affine_inverse()
	for i in shades.size():
		var copy := copies[3 + i] as Polygon2D
		check(copy != null and copy.polygon == shades[i].polygon and copy.color == shades[i].color, "shade %d copied" % i)
		if copy != null:
			check(copy.transform.is_equal_approx(to_bake * _in(shades[i], layout)), "shade %d where it lies on the floor" % i)
	check_equal(_stack_shown(layout), 3 + shades.size(), "until it is drawn the layers show")
	check(_bake().bake(layout) == null, "baked once a layout")


func test_drawn_the_floor_shows_the_bake_and_its_stack_is_one_item() -> void:
	var layout: Node = own(_room().build())
	var bake: BakeScript = _bake()
	var viewport: SubViewport = bake.bake(layout)
	bake.step(10)
	check(not BakeScript.is_baked(layout), "not shown while its layout is out of the tree")
	root.add_child(layout)
	bake.step(10)
	bake.step(10)
	check(not BakeScript.is_baked(layout), "nor before a frame is drawn after it was in the tree")
	bake.step(11)
	check(BakeScript.is_baked(layout), "shown once a frame was drawn")
	check_equal(bake.shown, 1, "counted")
	var ground := layout.get_node("Floor") as Sprite2D
	check(ground.texture == viewport.get_texture() and ground.material == BakeScript.shown_material(), "the floor draws the bake, premultiplied")
	check_equal(_stack_shown(layout), 1, "the floor's whole stack is one item drawn (one draw call)")
	check((ground.get_node("Glow") as Sprite2D).texture == null and (ground.find_child("Underside", true, false) as Sprite2D).texture == null, "the layers' textures let go")
	check_equal(viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED, "never drawn again")
	await process_frame
	check_equal(viewport.get_child_count(), 0, "its copies freed")
	layout.get_parent().remove_child(layout)


func test_feel_s_ground_part_bakes_every_layout_it_hears() -> void:
	var events: EventsScript = own(EventsScript.new()) as EventsScript
	var part: LayoutScript = own(LayoutScript.new()) as LayoutScript
	part.events = events
	part.registry = root.get_node("/root/Registry") as RegistryScript
	part.native = false
	part.bake.enabled = true
	part._ready()
	var room: RoomBase = _room()
	var layout: Node = own(room.build())
	events.room_built.emit(room.id, 0, layout)
	check(layout.has_node(NodePath(BakeScript.BAKE)), "its floor's bake laid")
	var hub: RoomBase = (root.get_node("/root/Registry") as RegistryScript).get_resource(&"rooms", &"hub") as RoomBase
	if hub != null:
		var hub_layout: Node = own(hub.build())
		events.room_built.emit(hub.id, 1, hub_layout)
		check(hub_layout.has_node(NodePath(BakeScript.BAKE)), "the hub's baked art is baked too")


func test_with_no_renderer_nothing_is_baked() -> void:
	var bake := BakeScript.new()
	check_equal(bake.enabled, DisplayServer.get_name() != "headless", "off in a headless run")
	var layout: Node = own(_room().build())
	if not bake.enabled:
		check(bake.bake(layout) == null and not layout.has_node(NodePath(BakeScript.BAKE)), "nothing laid")
