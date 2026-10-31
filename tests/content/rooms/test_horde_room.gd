extends "res://tests/support/suite.gd"
## The horde arena (content/rooms/horde, docs/milestones/horde.md H2): one walled room of
## 1280×720 (the floor), open, with the four player spawns near the middle and a few fallback
## enemy spawns by the walls (the director picks its own points). The data matches the scene's
## markers, no spawn is in a wall, the walls close the room on the wall layer, and no scripts.

const RoomData := preload("res://content/rooms/horde/horde.tres")
const RoomScan := preload("res://tests/content/rooms/room_scan.gd")

const SIZE: Vector2 = Vector2(1280.0, 720.0)
## Half the size of a body, in pixels.
const BODY_RADIUS: float = 12.0

var room_root: Node


func before_each() -> void:
	room_root = own((RoomData as RoomBase).scene.instantiate()) as Node


func test_resource_has_the_horde_id_a_scene_and_four_player_spawns() -> void:
	var room: RoomBase = RoomData
	check_equal(room.id, &"horde", "the id")
	check(room.scene != null, "the room has a scene")
	check_equal(room.player_spawns.size(), 4, "player spawns")
	check(room.dummy_spawns.is_empty(), "no dummies")


func test_in_web_builds() -> void:
	# The Horde button is in every build, the web ones too, and web builds only see demo content.
	check((RoomData as RoomBase).demo, "the horde room is demo content")


func test_the_floor_is_the_whole_arena() -> void:
	var floor_sprite := room_root.get_node("Floor") as Sprite2D
	check_equal(RoomScan.sprite_rect(floor_sprite), Rect2(Vector2.ZERO, SIZE), "the floor covers 1280×720")


func test_spawns_match_the_markers() -> void:
	var room: RoomBase = RoomData
	check_equal(RoomScan.markers(room_root, "PlayerSpawns"), room.player_spawns, "player spawns")
	check_equal(RoomScan.markers(room_root, "EnemySpawns"), room.enemy_spawns, "enemy spawns")
	check_equal(RoomScan.markers(room_root, "Doors"), room.doors, "doors")


func test_scene_has_no_scripts() -> void:
	check_equal(RoomScan.scripts_below(room_root), 0, "scripts in the scene")


func test_the_walls_close_the_room() -> void:
	var walls := room_root.get_node("Walls") as StaticBody2D
	check(walls.collision_layer & 1 != 0, "the walls are on the wall layer")
	var rects: Array[Rect2] = RoomScan.wall_rects(room_root)
	var bounds := Rect2()
	for rect: Rect2 in rects:
		bounds = rect if bounds.size == Vector2.ZERO else bounds.merge(rect)
	check_equal(bounds, Rect2(Vector2.ZERO, SIZE), "the walls run round the whole arena")
	# Points just inside each edge are in a wall; the middle is not.
	for edge: Vector2 in [Vector2(640.0, 4.0), Vector2(640.0, 716.0), Vector2(4.0, 360.0), Vector2(1276.0, 360.0)]:
		var inside: bool = false
		for rect: Rect2 in rects:
			inside = inside or rect.has_point(edge)
		check(inside, "the edge at %s is walled" % edge)


func test_players_start_near_the_middle() -> void:
	for point: Vector2 in (RoomData as RoomBase).player_spawns:
		check(point.distance_to(SIZE * 0.5) < 96.0, "player spawn %s is near the middle" % point)


func test_spawns_are_clear_of_walls() -> void:
	var walls: Array[Rect2] = RoomScan.wall_rects(room_root)
	var room: RoomBase = RoomData
	for point: Vector2 in room.player_spawns + room.enemy_spawns:
		var body := Rect2(point - Vector2.ONE * BODY_RADIUS, Vector2.ONE * BODY_RADIUS * 2.0)
		check(Rect2(Vector2.ZERO, SIZE).encloses(body), "spawn %s is in the room" % point)
		for wall: Rect2 in walls:
			check(not wall.intersects(body), "spawn %s is clear of the wall %s" % [point, wall])
