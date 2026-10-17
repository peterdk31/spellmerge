extends SceneTree
## Tests for the crypt room (content/rooms/crypt/arena_01): it loads on RoomBase, has no scripts,
## four player spawns, enemy spawns and doors that match the scene's markers, and no spawn lies
## inside a wall or outside the room.
##
## godot --headless --path . --script res://tests/content/rooms/test_arena_01.gd

const RoomData := preload("res://content/rooms/crypt/arena_01.tres")
const ROOM_SIZE: Vector2 = Vector2(640, 384)
## Clearance a spawn needs around it (a wizard is about 12 px wide).
const SPAWN_RADIUS: float = 12.0

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
	root.free()


func _scripts_below(node: Node) -> int:
	var count: int = 1 if node.get_script() != null else 0
	for child in node.get_children():
		count += _scripts_below(child)
	return count


func _markers(root: Node, group: String) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for child in root.get_node(group).get_children():
		points.append((child as Marker2D).position)
	return points


func _wall_rects(root: Node) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child in root.get_node("Walls").get_children():
		var shape_node: CollisionShape2D = child as CollisionShape2D
		if shape_node == null:
			continue
		var size: Vector2 = (shape_node.shape as RectangleShape2D).size
		rects.append(Rect2(shape_node.position - size * 0.5, size))
	return rects
