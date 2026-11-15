extends "res://tests/support/suite.gd"
## Every room template's layout (content/rooms: arena_01 and every room a run's map can pick, found
## by folder), about where things are and what can be reached, never about how a room looks: spawns
## lie inside the room and clear of walls, the doors sit in the border, and every spawn can be
## reached from the first player spawn.

const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
## Clearance a spawn needs around it (a wizard is about 12 px wide).
const SPAWN_RADIUS: float = 12.0
const TILE: float = 32.0
const STEPS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var templates: Array[RoomBase] = []
## Each template's layout (one instance), wall rectangles and extent, by id.
var layouts: Dictionary[StringName, Node] = {}
var walls_of: Dictionary[StringName, Array] = {}
var bounds_of: Dictionary[StringName, Rect2] = {}


func before_each() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	templates = RoomScan.templates(registry)
	layouts.clear()
	walls_of.clear()
	bounds_of.clear()
	for room in templates:
		var layout: Node = own(room.scene.instantiate()) as Node
		layouts[room.id] = layout
		walls_of[room.id] = RoomScan.wall_rects(layout)
		bounds_of[room.id] = RoomScan.wall_bounds(layout)


func _walls(room: RoomBase) -> Array[Rect2]:
	var found: Array[Rect2] = []
	found.assign(walls_of[room.id])
	return found


func _bounds(room: RoomBase) -> Rect2:
	return bounds_of[room.id]


func _spawns(room: RoomBase) -> PackedVector2Array:
	return room.places().player_spawns + room.places().enemy_spawns


func test_the_templates_are_found() -> void:
	check(templates.size() >= 4, "arena_01 and the crypt's other fight rooms are found (%d)" % templates.size())


func test_scenes_have_no_scripts() -> void:
	for room in templates:
		check_equal(RoomScan.scripts_below(layouts[room.id]), 0, "%s: scripts in the scene" % room.id)


func test_spawn_groups_hold_only_markers() -> void:
	for room in templates:
		for group: String in ["PlayerSpawns", "EnemySpawns", "Doors"]:
			check(RoomScan.only_markers(layouts[room.id], group), "%s: %s holds only Marker2D nodes" % [room.id, group])


func test_every_room_has_walls() -> void:
	for room in templates:
		check(_walls(room).size() >= 4, "%s has at least its four border walls" % room.id)


func test_spawns_are_inside_the_room() -> void:
	for room in templates:
		var inside: Rect2 = _bounds(room)
		for point in _spawns(room):
			check(inside.has_point(point), "%s: spawn %s is inside the room" % [room.id, point])


func test_spawns_are_clear_of_walls() -> void:
	for room in templates:
		var walls: Array[Rect2] = _walls(room)
		for point in _spawns(room):
			var body: Rect2 = Rect2(point - Vector2.ONE * SPAWN_RADIUS, Vector2.ONE * SPAWN_RADIUS * 2.0)
			for wall in walls:
				check(not wall.intersects(body), "%s: spawn %s is clear of the wall %s" % [room.id, point, wall])


func test_spawns_do_not_overlap() -> void:
	for room in templates:
		var spawns: PackedVector2Array = _spawns(room)
		for i in range(spawns.size()):
			for j in range(i + 1, spawns.size()):
				check(spawns[i].distance_to(spawns[j]) >= SPAWN_RADIUS * 2.0, "%s: spawns %s and %s overlap" % [room.id, spawns[i], spawns[j]])


func test_doors_lie_on_the_border() -> void:
	for room in templates:
		var size: Vector2 = _bounds(room).end
		check(room.places().doors.size() >= 1, "%s has a door" % room.id)
		for door in room.places().doors:
			var on_border: bool = door.x < TILE or door.y < TILE or door.x > size.x - TILE or door.y > size.y - TILE
			check(on_border, "%s: door %s lies on the border" % [room.id, door])


## Flood fill on the 32 px grid from the first player spawn.
func test_every_spawn_can_be_reached() -> void:
	for room in templates:
		var seen: Dictionary = _flood(room, _cell(room.places().player_spawns[0]))
		for point in _spawns(room):
			check(seen.has(_cell(point)), "%s: spawn %s can be reached from the first player spawn" % [room.id, point])


## No floor cell is shut off from the party: a pocket nobody can walk into is a place an enemy
## could be pushed into and never reached.
func test_every_floor_cell_can_be_reached() -> void:
	for room in templates:
		var walls: Array[Rect2] = _walls(room)
		var seen: Dictionary = _flood(room, _cell(room.places().player_spawns[0]))
		var grid: Vector2i = _grid(room)
		for y in grid.y:
			for x in grid.x:
				var cell := Vector2i(x, y)
				if not _blocked(walls, cell):
					check(seen.has(cell), "%s: the floor cell %s can be reached" % [room.id, cell])


func _flood(room: RoomBase, start: Vector2i) -> Dictionary:
	var walls: Array[Rect2] = _walls(room)
	var grid: Vector2i = _grid(room)
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step in STEPS:
			var next: Vector2i = cell + step
			if next.x < 0 or next.y < 0 or next.x >= grid.x or next.y >= grid.y or seen.has(next):
				continue
			if not _blocked(walls, next):
				seen[next] = true
				queue.append(next)
	return seen


func _blocked(walls: Array[Rect2], cell: Vector2i) -> bool:
	var centre: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5)) * TILE
	for wall in walls:
		if wall.has_point(centre):
			return true
	return false


func _grid(room: RoomBase) -> Vector2i:
	var size: Vector2 = _bounds(room).end
	return Vector2i(int(size.x / TILE), int(size.y / TILE))


func _cell(point: Vector2) -> Vector2i:
	return Vector2i(int(point.x / TILE), int(point.y / TILE))
