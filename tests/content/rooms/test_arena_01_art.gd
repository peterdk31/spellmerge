extends "res://tests/support/suite.gd"
## The crypt room's look (content/rooms/crypt/arena_01), only what matters to play: the floor
## covers the room, each wall sprite draws over a collision shape, and decoration never blocks
## anything. Which tile, torch or decal goes where is free to change.

const RoomData := preload("res://content/rooms/crypt/arena_01.tres")
const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const ROOM_SIZE: Vector2 = Vector2(640, 384)

var room_root: Node


func before_each() -> void:
	room_root = own((RoomData as RoomBase).scene.instantiate()) as Node


func test_floor_covers_the_whole_room() -> void:
	var floor_sprite: Sprite2D = room_root.get_node("Floor") as Sprite2D
	check(floor_sprite != null, "the room has a Floor sprite")
	if floor_sprite != null:
		check_equal(RoomScan.sprite_rect(floor_sprite), Rect2(Vector2.ZERO, ROOM_SIZE), "the floor rect")


func test_every_wall_sprite_draws_over_a_collision_shape() -> void:
	var rects: Array[Rect2] = RoomScan.wall_rects(room_root)
	for child in room_root.get_node("Walls").get_children():
		if child is Sprite2D:
			check(rects.has(RoomScan.sprite_rect(child as Sprite2D)), "wall sprite %s matches a collision shape" % child.name)


func test_every_collision_shape_has_a_wall_sprite() -> void:
	var drawn: Array[Rect2] = []
	for child in room_root.get_node("Walls").get_children():
		if child is Sprite2D:
			drawn.append(RoomScan.sprite_rect(child as Sprite2D))
	for rect in RoomScan.wall_rects(room_root):
		check(drawn.has(rect), "the wall %s is drawn" % rect)


func test_decoration_has_no_collision() -> void:
	for child in room_root.get_children():
		if child.name != "Walls":
			check_equal(_collision_nodes_below(child), 0, "collision objects under %s" % child.name)


func test_decoration_stays_inside_the_room() -> void:
	for child in room_root.get_children():
		if child.name != "Walls":
			_check_sprites_inside(child)


func _check_sprites_inside(node: Node) -> void:
	var sprite: Sprite2D = node as Sprite2D
	if sprite != null:
		check(Rect2(Vector2.ZERO, ROOM_SIZE).encloses(RoomScan.sprite_rect(sprite)), "%s is inside the room" % sprite.name)
	for child in node.get_children():
		_check_sprites_inside(child)


func _collision_nodes_below(node: Node) -> int:
	var count: int = 1 if node is CollisionObject2D or node is CollisionShape2D else 0
	for child in node.get_children():
		count += _collision_nodes_below(child)
	return count
