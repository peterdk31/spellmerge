extends "res://tests/support/suite.gd"
## A mirrored room's art lies over what bodies and shots hit there (the owner's bug of 2026-11-19: "the
## hitbox of decorations (maybe just in mirrored rooms) does not seem to align with the decorations";
## gameplay/feel/ground/mirrored_art.gd). On the real game: every crypt template, in each of its four
## mirrorings, started by Flow as a one-room biome at a place away from the world's origin, Feel
## hearing it built as in play. In each, every wall's sprite (a sarcophagus, a wall of bones) covers
## wall cells of the grid only, and its shade lies on it; every floor decoration (rubble, a skull, a
## decal's sprites) lies clear of the grid's walls; every prop's footprint (the ground it blocks) lies
## under its drawn body; and the light's blockers are the grid's walls. An unmirrored room's art is
## the template's, moved to its place only.
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const MirroredArtScript := preload("res://gameplay/feel/ground/mirrored_art.gd")

const DT: float = 1.0 / 60.0
## Where each room is laid: on the 32 px grid, away from the origin on both axes.
const PLACE: Vector2 = Vector2(320.0, 224.0)
const CELL: float = RoomGrid.WALL_CELL

var flow: FlowScript
var tick: TickScript
var registry: Node
var projectiles: Node
var feel: Node
var input: Node


func before_each() -> void:
	input = root.get_node("PlayerInput")
	input.call(&"add_virtual_device", 0)
	flow = root.get_node("Flow") as FlowScript
	tick = root.get_node("Tick") as TickScript
	registry = root.get_node("Registry")
	projectiles = root.get_node("Projectiles")
	feel = root.get_node("Feel")
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	flow.set(&"loading_enabled", false)
	flow.set(&"intro_enabled", false)


func after_each() -> void:
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	input.call(&"leave", 0)
	tick.begin_run()


## The crypt's rooms (not its walkways), by id.
func _templates() -> Array[RoomBase]:
	var found: Array[RoomBase] = []
	for item: Resource in registry.call(&"get_all", &"rooms"):
		var room := item as RoomBase
		if room != null and room.biome == &"crypt" and not room.walkway and room.scene != null and not String(room.id).begins_with("pinned_"):
			found.append(room)
	found.sort_custom(func(a: RoomBase, b: RoomBase) -> bool: return String(a.id) < String(b.id))
	return found


## `room` started alone, mirrored by `mirror`, at PLACE; its layout (null when it did not start).
func _start(room: RoomBase, mirror: int) -> Node2D:
	flow.stop_run()
	var map := BiomeMap.new()
	map.biome = room.biome
	map.add_room(room.id, PLACE, mirror, &"start")
	map.work_out_depths()
	if not flow.start_biome(0, map, [RoomFight.new()] as Array[RoomFight]):
		check(false, "%s mirrored %d: the room starts" % [room.id, mirror])
		return null
	tick.run(DT)
	return flow.biome.room_layout(0) as Node2D


func _grid() -> RoomGrid:
	return projectiles.call(&"grid") as RoomGrid


func _is_wall(at: Vector2) -> bool:
	return (_grid().cell_at(at) & RoomGrid.ROOM_CELL) != 0


## The middles of the 8 px cells of the world's grid whose middles lie in `rect` (world pixels).
func _cell_middles(rect: Rect2) -> PackedVector2Array:
	var found := PackedVector2Array()
	var y: float = floorf(rect.position.y / CELL) * CELL + CELL * 0.5
	while y < rect.end.y:
		var x: float = floorf(rect.position.x / CELL) * CELL + CELL * 0.5
		while x < rect.end.x:
			if rect.has_point(Vector2(x, y)):
				found.append(Vector2(x, y))
			x += CELL
		y += CELL
	return found


func _world_rect(item: CanvasItem, local: Rect2) -> Rect2:
	return item.get_global_transform() * local


func test_every_mirrored_rooms_art_lies_over_what_is_hit_there() -> void:
	var rooms: Array[RoomBase] = _templates()
	check(rooms.size() >= 4, "the crypt's rooms are found (%d)" % rooms.size())
	var walls_seen: int = 0
	var props_seen: int = 0
	for room: RoomBase in rooms:
		for mirror: int in PieceShape.MIRRORINGS:
			var layout: Node2D = _start(room, mirror)
			if layout == null:
				continue
			var named: String = "%s mirrored %d" % [room.id, mirror]
			check_equal(layout.has_meta(MirroredArtScript.PLACED_META), mirror != 0, "%s: its art is put as it is mirrored" % named)
			var dark := layout.get_node_or_null("Void") as Sprite2D
			if dark != null:
				check(_world_rect(dark, dark.get_rect()).encloses(flow.biome.room_rect(0)), "%s: the dark behind its slab still covers it" % named)
			walls_seen += _check_walls(layout, named)
			_check_floor_decoration(layout, named)
			props_seen += _check_props(named)
			_check_light_blockers(named)
	check(walls_seen > 0, "some room has a wall drawn by a sprite of its own (%d)" % walls_seen)
	check(props_seen > 0, "some room has props (%d)" % props_seen)


## Every sprite of a wall body covers the grid's walls only (and some), and each shade lies on one.
func _check_walls(layout: Node2D, named: String) -> int:
	var seen: int = 0
	var drawn: Array[Rect2] = []
	for body: Node in layout.find_children("*", "StaticBody2D", true, false):
		if body.get_parent() != layout:
			continue
		for child: Node in body.get_children():
			var sprite := child as Sprite2D
			if sprite == null:
				continue
			var at: Rect2 = _world_rect(sprite, sprite.get_rect())
			drawn.append(at)
			var middles: PackedVector2Array = _cell_middles(at)
			var open: int = 0
			for middle: Vector2 in middles:
				if not _is_wall(middle):
					open += 1
			check(not middles.is_empty() and open == 0, "%s: the wall sprite %s at %s lies over walls only (%d of %d cells open)" % [named, sprite.name, at, open, middles.size()])
			seen += 1
	var shade: Node = layout.get_node_or_null("Shade")
	if shade != null:
		for child: Node in shade.get_children():
			var polygon := child as Polygon2D
			if polygon == null or polygon.polygon.is_empty():
				continue
			var box := Rect2(polygon.polygon[0], Vector2.ZERO)
			for point: Vector2 in polygon.polygon:
				box = box.expand(point)
			box = _world_rect(polygon, box)
			check(drawn.any(func(wall: Rect2) -> bool: return wall.intersection(box).get_area() >= wall.get_area() * 0.5),
				"%s: the shade %s at %s lies on its wall's sprite" % [named, polygon.name, box])
	return seen


## Every floor decoration's sprite (rubble, a skull, a decal's but its light; a torch hangs on a wall
## and a door is in it) lies clear of the grid's walls.
func _check_floor_decoration(layout: Node2D, named: String) -> void:
	var decor: Node = layout.get_node_or_null("Decor")
	if decor == null:
		return
	for child: Node in decor.get_children():
		var name: String = String(child.name)
		if name.ends_with("Door") or name.begins_with("Torch"):
			continue
		var sprites: Array[Node] = [child]
		if child.scene_file_path != "":
			sprites.append_array(child.get_children())
		for each: Node in sprites:
			var sprite := each as Sprite2D
			if sprite == null or MirroredArtScript.is_light(sprite) or not sprite.visible:
				continue
			var at: Rect2 = _world_rect(sprite, sprite.get_rect())
			for middle: Vector2 in _cell_middles(at):
				if _is_wall(middle):
					check(false, "%s: %s's sprite %s at %s lies clear of the walls (a wall at %s)" % [named, name, sprite.name, at, middle])
					break


## Every prop's footprint (the ground it blocks, as the grid has it) lies under its body's drawn art.
func _check_props(named: String) -> int:
	var seen: int = 0
	for body: Node in flow.world.get_children():
		var actor := body as Actor
		if actor == null or actor.prop == null:
			continue
		var ground: Rect2 = _grid().footprint_of(actor.id)
		if not ground.has_area():
			continue
		var sprite := actor.get_node_or_null("Sprite") as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		var art: Rect2 = _world_rect(sprite, sprite.get_rect())
		check(art.grow(0.5).encloses(ground), "%s: %s's footprint %s lies under its art %s" % [named, actor.name, ground, art])
		seen += 1
	return seen


## The light's blockers are the walls as the grid has them: each standing wall's cells are walls.
func _check_light_blockers(named: String) -> void:
	var spectacle: Object = feel.call(&"spectacle") if feel.has_method(&"spectacle") else null
	var blockers: Object = spectacle.get(&"blockers") if spectacle != null else null
	if blockers == null:
		return
	for rect: Rect2 in blockers.get(&"walls") as Array[Rect2]:
		for middle: Vector2 in _cell_middles(rect):
			if not _is_wall(middle):
				check(false, "%s: the light's blocker %s lies over the grid's walls (open at %s)" % [named, rect, middle])
				break


## A mirrored layout is put once: heard again, nothing moves.
func test_a_layout_is_put_once() -> void:
	var room: RoomBase = registry.call(&"get_resource", &"rooms", &"arena_02") as RoomBase
	var layout := room.build() as Node2D
	layout.set_meta(PieceShape.GROUND_MIRROR_META, Vector2i(0, 1))
	var sprite := layout.get_node("Walls/Sarcophagus") as Sprite2D
	var before: Vector2 = sprite.position
	check(MirroredArtScript.place(layout), "a mirrored layout's art is put")
	var put: Vector2 = sprite.position
	check(put != before, "the sarcophagus moved (%s to %s)" % [before, put])
	check(not MirroredArtScript.place(layout), "heard again, it is not put twice")
	check_equal(sprite.position, put, "and stays where it was put")
	layout.free()
