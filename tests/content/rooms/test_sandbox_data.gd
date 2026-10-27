extends "res://tests/support/suite.gd"
## The sandbox room (content/rooms/crypt/sandbox, staffs B7): two shooting lanes split by a
## wall (owner, 2026-10-26), the training dummy at the far end of the left lane and the
## shooting dummy at the far end of the right one, a group of four more training dummies round
## the first in the left lane (owner, 2026-10-27: to try homing and pierce on), the divider stopping short of the bottom so
## wizards walk between the lanes. The data matches the scene's markers; no scripts.

const RoomData := preload("res://content/rooms/crypt/sandbox.tres")
const RoomScan := preload("res://tests/content/rooms/room_scan.gd")

## Half the size of a dummy's body, in pixels.
const DUMMY_RADIUS: float = 12.0

var room_root: Node


func before_each() -> void:
	room_root = own((RoomData as RoomBase).scene.instantiate()) as Node


func test_resource_has_an_id_a_scene_and_six_dummy_spawns() -> void:
	var room: RoomBase = RoomData
	check_equal(room.id, &"sandbox", "the id")
	check(room.scene != null, "the room has a scene")
	check_equal(room.player_spawns.size(), 4, "player spawns")
	check(room.enemy_spawns.size() >= 4, "at least four enemy spawns, for the imp wave")
	check_equal(room.dummy_spawns.size(), 6, "dummy spawns: the training dummy, the shooting dummy and a group of four")


func test_in_web_builds() -> void:
	# `/preview/` is a web build, and web builds only see demo content (core/registry).
	check((RoomData as RoomBase).demo, "the sandbox is demo content, so the preview site has it")


func test_spawns_match_the_markers() -> void:
	var room: RoomBase = RoomData
	check_equal(RoomScan.markers(room_root, "PlayerSpawns"), room.player_spawns, "player spawns")
	check_equal(RoomScan.markers(room_root, "EnemySpawns"), room.enemy_spawns, "enemy spawns")
	check_equal(RoomScan.markers(room_root, "Doors"), room.doors, "doors")
	check_equal(RoomScan.markers(room_root, "DummySpawns"), room.dummy_spawns, "dummy spawns")


func test_scene_has_no_scripts() -> void:
	check_equal(RoomScan.scripts_below(room_root), 0, "scripts in the scene")


## The divider: the wall that is neither a border nor reaches the bottom wall.
func _divider(walls: Array[Rect2]) -> Rect2:
	for wall: Rect2 in walls:
		if wall.position.x > 64.0 and wall.end.x < 576.0 and wall.size.y > 64.0:
			return wall
	return Rect2()


func test_a_wall_splits_the_dummies_into_two_lanes() -> void:
	var divider: Rect2 = _divider(RoomScan.wall_rects(room_root))
	check(divider.size != Vector2.ZERO, "the room has a divider wall")
	var spawns: PackedVector2Array = (RoomData as RoomBase).dummy_spawns
	check(spawns[0].x < divider.position.x, "the training dummy is in the left lane")
	check(spawns[1].x > divider.end.x, "the shooting dummy is in the right lane")
	check(spawns[0].y < divider.end.y and spawns[1].y < divider.end.y, "both dummies stand beside the divider")
	for i in range(2, spawns.size()):
		check(spawns[i].x < divider.position.x and spawns[i].y < divider.end.y, "the group's dummy %s is in the left lane, beside the divider" % spawns[i])
	check(divider.end.y < 320.0, "the divider stops short of the bottom, so wizards cross between the lanes")


func test_two_players_start_in_each_lane() -> void:
	var divider: Rect2 = _divider(RoomScan.wall_rects(room_root))
	var left: int = 0
	for point: Vector2 in (RoomData as RoomBase).player_spawns:
		if point.x < divider.position.x:
			left += 1
	check_equal(left, 2, "players starting in the left lane")


func test_dummies_stand_apart() -> void:
	var spawns: PackedVector2Array = (RoomData as RoomBase).dummy_spawns
	for i in spawns.size():
		for j in range(i + 1, spawns.size()):
			check(spawns[i].distance_to(spawns[j]) >= DUMMY_RADIUS * 4.0, "dummies %s and %s do not touch" % [spawns[i], spawns[j]])


func test_dummy_spawns_are_clear_of_walls() -> void:
	var walls: Array[Rect2] = RoomScan.wall_rects(room_root)
	check(walls.size() >= 4, "the walls are found")
	for point: Vector2 in (RoomData as RoomBase).dummy_spawns:
		var body := Rect2(point - Vector2.ONE * DUMMY_RADIUS, Vector2.ONE * DUMMY_RADIUS * 2.0)
		for wall: Rect2 in walls:
			check(not wall.intersects(body), "dummy spawn %s is clear of the wall %s" % [point, wall])
