extends "res://tests/support/suite.gd"
## A laid room's floor baked into one texture (gameplay/feel/ground/floor_bake.gd; the owner's choice
## of 2026-11-21, after #900: "a room in view is ~1 call for its floor instead of ~7"): the bake's
## viewport holds copies of the floor, its rock face, its glow (added, by the bake's material) and
## its shades, in that order, each where it lies on the floor; once a frame was drawn after it was in
## the tree the floor shows the bake and the layers are hidden and let go, so the floor stack is one
## item drawn; Feel's ground part bakes every layout `room_built` hands over; with no renderer
## nothing is baked; a layout it cannot draw whole is left as it is; no room's shade lies over art
## drawn before it (which the bake would put under it). Pixels: the suite runs headless, which
## draws no viewport, so the bake's pixels (its blend, the glow's add, the order) are checked only by
## tests/screenshots/shot_baked_floors.gd, which holds the bake against the layers in one frame.
const BakeScript := preload("res://gameplay/feel/ground/floor_bake.gd")
const LayoutScript := preload("res://gameplay/feel/ground/ground_layout.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## A crypt room with a floor, a rock face, a glow and shades.
const ROOM: StringName = &"arena_03"


func _room() -> RoomBase:
	return (root.get_node("/root/Registry") as RegistryScript).get_resource(&"rooms", ROOM) as RoomBase


func _bake(picture_scale: int = 1) -> BakeScript:
	var bake := BakeScript.new()
	bake.enabled = true
	bake.picture_scale = picture_scale
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
	var items: Array[CanvasItem] = [ground, ground.get_node("Glow"), ground.find_child("Underside", true, false), ground.get_node_or_null(NodePath(BakeScript.SHOWN))]
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


## At the picture's scale (the shipped 1280 x 720 picture: 2, ART0): the viewport is that many
## times the floor's size and the layers are drawn into it that much bigger; shown, the floor stands
## where it stood (its world rect the same), its texture marked at that detail; unshown, as it was.
func test_the_bake_is_drawn_at_the_picture_s_scale_and_stands_where_the_floor_stood() -> void:
	var layout: Node = own(_room().build())
	var ground := layout.get_node("Floor") as Sprite2D
	var world_rect: Rect2 = ground.transform * ground.get_rect()
	var offset: Vector2 = ground.offset
	var scale_before: Vector2 = ground.scale
	var bake: BakeScript = _bake(2)
	bake.keep_layers = true
	var viewport: SubViewport = bake.bake(layout)
	check(viewport != null, "baked")
	if viewport == null:
		return
	check_equal(viewport.size, Vector2i(ground.texture.get_size() * 2.0), "twice the floor's size each way")
	var base := Transform2D(0.0, Vector2(2.0, 2.0), 0.0, -ground.get_rect().position * 2.0)
	check((viewport.get_child(0) as Sprite2D).transform.is_equal_approx(base), "the floor drawn twice as big from the viewport's corner")
	check((viewport.get_child(2) as Sprite2D).transform.is_equal_approx(base * _in(ground, layout).affine_inverse() * _in(ground.get_node("Glow"), layout)), "the glow twice as big where it lies")
	var children: Array[Transform2D] = []
	for child: Node in ground.get_children():
		if child is Node2D:
			children.append((child as Node2D).transform)
	bake.show_bake(viewport)
	var shown := ground.get_node_or_null(NodePath(BakeScript.SHOWN)) as Sprite2D
	check(shown != null and shown.get_index() == 0, "the bake on a sprite of its own, the floor's first child")
	if shown == null:
		return
	check_equal(ArtDetail.of(shown.texture), 2, "the bake's texture is marked at the picture's detail")
	check((ground.transform * shown.transform * shown.get_rect()).is_equal_approx(world_rect), "the baked floor stands where the floor stood")
	check(ground.offset.is_equal_approx(offset) and ground.scale.is_equal_approx(scale_before), "the floor's own offset and scale untouched (its children are the room's: holes, mote lines)")
	var at: int = 0
	for child: Node in ground.get_children():
		if child is Node2D and child != shown:
			check((child as Node2D).transform.is_equal_approx(children[at]), "%s where it was" % child.name)
			at += 1
	check(BakeScript.unshow(layout), "unshown")
	check(ground.get_node_or_null(NodePath(BakeScript.SHOWN)) == null or ground.get_node(NodePath(BakeScript.SHOWN)).is_queued_for_deletion(), "its sprite gone")
	check((ground.transform * ground.get_rect()).is_equal_approx(world_rect), "the floor's art where it stood")


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
	var shown := ground.get_node_or_null(NodePath(BakeScript.SHOWN)) as Sprite2D
	check(shown != null and shown.texture == viewport.get_texture() and shown.material == BakeScript.shown_material() and ground.texture == null, "a sprite under the floor draws the bake, premultiplied; the floor nothing more")
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


## The pixels of `layout`'s shades that lie over a shown sprite drawn before them on screen (a wall's
## art, `Walls` before `Shade`, at z 0): baked under the floor's, they would no longer darken it.
func _shade_over_art(layout: Node) -> PackedStringArray:
	var found := PackedStringArray()
	var holder: Node = layout.get_node_or_null("Shade")
	if holder == null:
		return found
	var before: Array[Sprite2D] = []
	for node: Node in layout.find_children("*", "Sprite2D", true, false):
		var sprite := node as Sprite2D
		if sprite.texture == null or layout.get_node("Floor").is_ancestor_of(sprite) or sprite == layout.get_node("Floor"):
			continue
		if _index_path(sprite, layout) < _index_path(holder, layout) and _shown(sprite, layout) and not (sprite.z_as_relative == false and sprite.z_index < -2):
			before.append(sprite)
	var images: Dictionary = {}
	for shade: Polygon2D in BakeScript.shades(layout):
		var xf: Transform2D = _in(shade, layout)
		var points: PackedVector2Array = xf * shade.polygon
		var box := Rect2(points[0], Vector2.ZERO)
		for p: Vector2 in points:
			box = box.expand(p)
		for sprite: Sprite2D in before:
			var to_sprite: Transform2D = _in(sprite, layout).affine_inverse()
			var rect: Rect2 = sprite.get_rect()
			if not (_in(sprite, layout) * rect).intersects(box):
				continue
			if not images.has(sprite.texture):
				var image: Image = sprite.texture.get_image()
				image.convert(Image.FORMAT_RGBA8)
				images[sprite.texture] = image
			var image: Image = images[sprite.texture]
			for y in range(floori(box.position.y), ceili(box.end.y)):
				for x in range(floori(box.position.x), ceili(box.end.x)):
					var at := Vector2(x + 0.5, y + 0.5)
					if not Geometry2D.is_point_in_polygon(at, points):
						continue
					var local: Vector2 = to_sprite * at - rect.position
					var texel := Vector2i(floori(local.x), floori(local.y))
					if texel.x < 0 or texel.y < 0 or texel.x >= image.get_width() or texel.y >= image.get_height():
						continue
					if image.get_pixelv(texel).a > 0.0:
						found.append("%s over %s at %s" % [shade.name, sprite.name, at])
	return found


## `node`'s place in the tree's drawing order under `layout` (its indices from the top).
func _index_path(node: Node, layout: Node) -> Array:
	var path: Array = []
	var at: Node = node
	while at != layout:
		path.push_front(at.get_index())
		at = at.get_parent()
	return path


func test_no_room_s_shade_lies_over_art_drawn_before_it() -> void:
	var registry := root.get_node("/root/Registry") as RegistryScript
	var rooms: int = 0
	for item: Resource in registry.get_all(&"rooms"):
		var room := item as RoomBase
		if room == null or room.scene == null:
			continue
		var layout: Node = own(room.build())
		if BakeScript.shades(layout).is_empty():
			continue
		rooms += 1
		var over: PackedStringArray = _shade_over_art(layout)
		check(over.is_empty(), "%s: a shade over a wall's art, which the bake would put under it (%d px; %s)" % [room.id, over.size(), ", ".join(over.slice(0, 3))])
	check(rooms >= 5, "rooms with shades checked (%d)" % rooms)


func test_a_layout_the_bake_cannot_draw_whole_is_left_as_it_is() -> void:
	var layout: Node = own(_room().build())
	check(BakeScript.bakeable(layout), "the crypt room bakes")
	var odd := Node2D.new()
	layout.get_node("Shade").add_child(odd)
	check(not BakeScript.bakeable(layout) and _bake().bake(layout) == null, "a shade holder with something but plain polygons: not baked")
	odd.free()
	(layout.get_node("Floor") as Sprite2D).material = CanvasItemMaterial.new()
	check(_bake().bake(layout) == null, "a floor with a material of its own: not baked")


func test_the_shader_draws_premultiplied_and_adds_the_glow() -> void:
	var code: String = BakeScript.SHADER.code
	check(code.contains("render_mode blend_premul_alpha"), "drawn premultiplied")
	check(BakeScript.glow_material().get_shader_parameter(&"glow") == true and BakeScript.shown_material().get_shader_parameter(&"glow") != true, "the glow's material adds, the floor's shows")
