extends "res://tests/support/suite.gd"
## Every room template's look (content/rooms: every room a run's map can pick, found by folder),
## only what matters to play: the floor covers the room, each wall sprite draws over a collision
## shape and each shape is drawn, and decoration never blocks anything. Which tile, torch or decal
## goes where is free to change.

const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

var templates: Array[RoomBase] = []
## Each template's layout, one instance, by id.
var layouts: Dictionary[StringName, Node] = {}


func before_each() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	templates = RoomScan.templates(registry)
	layouts.clear()
	for room in templates:
		layouts[room.id] = own(room.scene.instantiate()) as Node


func _layout(room: RoomBase) -> Node:
	return layouts[room.id]


func test_the_templates_are_found() -> void:
	check(templates.size() >= 1, "the templates are found (%d)" % templates.size())


func test_floor_covers_the_whole_room() -> void:
	for room in templates:
		var layout: Node = _layout(room)
		var floor_sprite: Sprite2D = layout.get_node_or_null("Floor") as Sprite2D
		check(floor_sprite != null, "%s has a Floor sprite" % room.id)
		if floor_sprite != null:
			check_equal(RoomScan.sprite_rect(floor_sprite), RoomScan.wall_bounds(layout), "%s: the floor covers the room inside and under its walls" % room.id)


func test_every_wall_sprite_draws_over_a_collision_shape() -> void:
	for room in templates:
		var layout: Node = _layout(room)
		var rects: Array[Rect2] = RoomScan.wall_rects(layout)
		for child in layout.get_node("Walls").get_children():
			if child is Sprite2D:
				check(rects.has(RoomScan.sprite_rect(child as Sprite2D)), "%s: wall sprite %s matches a collision shape" % [room.id, child.name])


func test_every_collision_shape_has_a_wall_sprite() -> void:
	for room in templates:
		var layout: Node = _layout(room)
		var drawn: Array[Rect2] = []
		for child in layout.get_node("Walls").get_children():
			if child is Sprite2D:
				drawn.append(RoomScan.sprite_rect(child as Sprite2D))
		# A pillar is drawn in two parts outside `Walls` (see test_template_pillars.gd); its base sits on the shape.
		var pillars: Node = layout.get_node_or_null("Pillars")
		if pillars != null:
			for child in pillars.get_children():
				if child is Sprite2D:
					drawn.append(RoomScan.sprite_rect(child as Sprite2D))
		for rect in RoomScan.wall_rects(layout):
			check(drawn.has(rect), "%s: the wall %s is drawn" % [room.id, rect])


func test_decoration_has_no_collision() -> void:
	for room in templates:
		for child in _layout(room).get_children():
			if child.name != "Walls":
				check_equal(_collision_nodes_below(child), 0, "%s: collision objects under %s" % [room.id, child.name])


func test_decoration_stays_inside_the_room() -> void:
	for room in templates:
		var layout: Node = _layout(room)
		var bounds: Rect2 = RoomScan.wall_bounds(layout)
		for child in layout.get_children():
			if child.name != "Walls":
				_check_sprites_inside(room, child, bounds)


## A rubble or skull lies on the floor, never over a wall or a pillar's base, which draw under it.
## A torch hangs on the wall and a door is in it: those are its own instances or named so.
func test_floor_decoration_lies_clear_of_walls() -> void:
	for room in templates:
		var layout: Node = _layout(room)
		var walls: Array[Rect2] = RoomScan.wall_rects(layout)
		for child in layout.get_node("Decor").get_children():
			var sprite: Sprite2D = child as Sprite2D
			if sprite == null or String(sprite.name).ends_with("Door"):
				continue
			var at: Rect2 = RoomScan.sprite_rect(sprite)
			for wall in walls:
				check(not wall.intersects(at), "%s: %s at %s lies clear of the wall %s" % [room.id, sprite.name, at, wall])


func _check_sprites_inside(room: RoomBase, node: Node, bounds: Rect2) -> void:
	var sprite: Sprite2D = node as Sprite2D
	if sprite != null:
		check(bounds.encloses(RoomScan.sprite_rect(sprite)), "%s: %s is inside the room" % [room.id, sprite.name])
	for child in node.get_children():
		_check_sprites_inside(room, child, bounds)


func _collision_nodes_below(node: Node) -> int:
	var count: int = 1 if node is CollisionObject2D or node is CollisionShape2D else 0
	for child in node.get_children():
		count += _collision_nodes_below(child)
	return count
