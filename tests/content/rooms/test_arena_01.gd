extends SceneTree
## Tests for the crypt room (content/rooms/crypt/arena_01): it loads on RoomBase, has no scripts,
## four player spawns, enemy spawns and doors that match the scene's markers, and no spawn lies
## inside a wall or outside the room, the wall and floor sprites line up with the collision shapes,
## the doors sit in the border, and every spawn can be reached from the first player spawn.
##
## godot --headless --path . --script res://tests/content/rooms/test_arena_01.gd

const RoomData := preload("res://content/rooms/crypt/arena_01.tres")
const ROOM_SIZE: Vector2 = Vector2(640, 384)
## Clearance a spawn needs around it (a wizard is about 12 px wide).
const SPAWN_RADIUS: float = 12.0
const TILE: float = 32.0
const STEPS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var _failures: Array[String] = []


func _initialize() -> void:
	_test_resource()
	_test_scene()
	if _failures.is_empty():
		print("TEST OK: content/rooms/crypt/arena_01 (spawns, doors, walls)")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_resource() -> void:
	var room: RoomBase = RoomData
	_check(room.id == &"arena_01", "id is arena_01")
	_check(room.scene != null, "the room has a scene")
	_check(room.player_spawns.size() == 4, "four player spawns")
	_check(room.enemy_spawns.size() >= 4, "at least four enemy spawns")
	_check(room.doors.size() >= 1, "at least one door")


func _test_scene() -> void:
	var room: RoomBase = RoomData
	var root: Node = room.scene.instantiate()
	_check(root.get_script() == null, "the root has no script")
	_check(_scripts_below(root) == 0, "no node has a script")
	_check(_markers(root, "PlayerSpawns") == room.player_spawns, "player spawns match the markers")
	_check(_markers(root, "EnemySpawns") == room.enemy_spawns, "enemy spawns match the markers")
	_check(_markers(root, "Doors") == room.doors, "doors match the markers")
	var walls: Array[Rect2] = _wall_rects(root)
	_check(walls.size() >= 4, "the room has walls")
	var inner: Rect2 = Rect2(Vector2.ZERO, ROOM_SIZE)
	var spawns: PackedVector2Array = room.player_spawns + room.enemy_spawns
	for point in spawns:
		_check(inner.has_point(point), "spawn %s is inside the room" % point)
		var body: Rect2 = Rect2(point - Vector2.ONE * SPAWN_RADIUS, Vector2.ONE * SPAWN_RADIUS * 2.0)
		for wall in walls:
			_check(not wall.intersects(body), "spawn %s is clear of the wall %s" % [point, wall])
	for i in range(room.player_spawns.size()):
		for j in range(i + 1, room.player_spawns.size()):
			_check(room.player_spawns[i].distance_to(room.player_spawns[j]) >= SPAWN_RADIUS * 2.0, "player spawns %d and %d do not overlap" % [i, j])
	_test_art(root, walls)
	_test_doors(room)
	_test_reachable(room, walls)
	root.free()


## The floor covers the room and every wall sprite has a collision shape of the same rect.
func _test_art(root: Node, walls: Array[Rect2]) -> void:
	var floor_sprite: Sprite2D = root.get_node("Floor") as Sprite2D
	_check(floor_sprite != null and _sprite_rect(floor_sprite) == Rect2(Vector2.ZERO, ROOM_SIZE), "the floor covers the whole room")
	var sprites: int = 0
	for child in root.get_node("Walls").get_children():
		var sprite: Sprite2D = child as Sprite2D
		if sprite == null:
			continue
		sprites += 1
		_check(walls.has(_sprite_rect(sprite)), "wall sprite %s matches a collision shape" % sprite.name)
	_check(sprites == walls.size(), "one wall sprite per collision shape (%d sprites, %d shapes)" % [sprites, walls.size()])


## Doors are in the border ring (the outer tile of the room).
func _test_doors(room: RoomBase) -> void:
	for door in room.doors:
		var on_border: bool = door.x < TILE or door.y < TILE or door.x > ROOM_SIZE.x - TILE or door.y > ROOM_SIZE.y - TILE
		_check(on_border, "door %s lies on the border" % door)


## Flood fill on the 32 px grid: no spawn is walled off from the first player spawn.
func _test_reachable(room: RoomBase, walls: Array[Rect2]) -> void:
	var cols: int = int(ROOM_SIZE.x / TILE)
	var rows: int = int(ROOM_SIZE.y / TILE)
	var start: Vector2i = _cell(room.player_spawns[0])
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step in STEPS:
			var next: Vector2i = cell + step
			if next.x < 0 or next.y < 0 or next.x >= cols or next.y >= rows or seen.has(next):
				continue
			var centre: Vector2 = (Vector2(next) + Vector2(0.5, 0.5)) * TILE
			var blocked: bool = false
			for wall in walls:
				blocked = blocked or wall.has_point(centre)
			if not blocked:
				seen[next] = true
				queue.append(next)
	for point in room.player_spawns + room.enemy_spawns:
		_check(seen.has(_cell(point)), "spawn %s can be reached from the first player spawn" % point)


func _cell(point: Vector2) -> Vector2i:
	return Vector2i(int(point.x / TILE), int(point.y / TILE))


func _sprite_rect(sprite: Sprite2D) -> Rect2:
	var size: Vector2 = sprite.region_rect.size if sprite.region_enabled else sprite.texture.get_size()
	return Rect2(sprite.position, size)


func _scripts_below(node: Node) -> int:
	var count: int = 1 if node.get_script() != null else 0
	for child in node.get_children():
		count += _scripts_below(child)
	return count


func _markers(root: Node, group: String) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for child in root.get_node(group).get_children():
		var marker: Marker2D = child as Marker2D
		_check(marker != null, "%s/%s is a Marker2D" % [group, child.name])
		if marker != null:
			points.append(marker.position)
	return points


func _wall_rects(root: Node) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child in root.get_node("Walls").get_children():
		var shape_node: CollisionShape2D = child as CollisionShape2D
		if shape_node == null:
			continue
		var rectangle: RectangleShape2D = shape_node.shape as RectangleShape2D
		_check(rectangle != null, "wall %s uses a RectangleShape2D" % shape_node.name)
		if rectangle == null:
			continue
		var size: Vector2 = rectangle.size
		rects.append(Rect2(shape_node.position - size * 0.5, size))
	return rects
