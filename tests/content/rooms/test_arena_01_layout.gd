extends "res://tests/support/suite.gd"
## The crypt room's layout (content/rooms/crypt/arena_01), about where things are and what can
## be reached, never about how the room looks: spawns lie inside the room and clear of walls,
## the doors sit in the border, and every spawn can be reached from the first player spawn.

const RoomData := preload("res://content/rooms/crypt/arena_01.tres")
const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const ROOM_SIZE: Vector2 = Vector2(640, 384)
## Clearance a spawn needs around it (a wizard is about 12 px wide).
const SPAWN_RADIUS: float = 12.0
const TILE: float = 32.0
const STEPS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var walls: Array[Rect2] = []


func before_each() -> void:
	var root: Node = own((RoomData as RoomBase).scene.instantiate()) as Node
	walls = RoomScan.wall_rects(root)


func test_the_room_has_walls() -> void:
	check(walls.size() >= 4, "the room has at least its four border walls")


func test_spawns_are_inside_the_room() -> void:
	var room: RoomBase = RoomData
	for point in room.player_spawns + room.enemy_spawns:
		check(Rect2(Vector2.ZERO, ROOM_SIZE).has_point(point), "spawn %s is inside the room" % point)


func test_spawns_are_clear_of_walls() -> void:
	var room: RoomBase = RoomData
	for point in room.player_spawns + room.enemy_spawns:
		var body: Rect2 = Rect2(point - Vector2.ONE * SPAWN_RADIUS, Vector2.ONE * SPAWN_RADIUS * 2.0)
		for wall in walls:
			check(not wall.intersects(body), "spawn %s is clear of the wall %s" % [point, wall])


func test_player_spawns_do_not_overlap() -> void:
	var spawns: PackedVector2Array = (RoomData as RoomBase).player_spawns
	for i in range(spawns.size()):
		for j in range(i + 1, spawns.size()):
			check(spawns[i].distance_to(spawns[j]) >= SPAWN_RADIUS * 2.0, "player spawns %d and %d overlap" % [i, j])


func test_doors_lie_on_the_border() -> void:
	for door in (RoomData as RoomBase).doors:
		var on_border: bool = door.x < TILE or door.y < TILE or door.x > ROOM_SIZE.x - TILE or door.y > ROOM_SIZE.y - TILE
		check(on_border, "door %s lies on the border" % door)


## Flood fill on the 32 px grid from the first player spawn.
func test_every_spawn_can_be_reached() -> void:
	var room: RoomBase = RoomData
	var seen: Dictionary = _flood(_cell(room.player_spawns[0]))
	for point in room.player_spawns + room.enemy_spawns:
		check(seen.has(_cell(point)), "spawn %s can be reached from the first player spawn" % point)


func _flood(start: Vector2i) -> Dictionary:
	var cols: int = int(ROOM_SIZE.x / TILE)
	var rows: int = int(ROOM_SIZE.y / TILE)
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
	return seen


func _cell(point: Vector2) -> Vector2i:
	return Vector2i(int(point.x / TILE), int(point.y / TILE))
