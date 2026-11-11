extends "res://tests/support/suite.gd"
## The crypt room's data (content/rooms/crypt/arena_01): the resource is a RoomBase, the scene
## has no scripts, and its spawns and doors are its scene's markers (props W8a: `RoomPlaces`).

const RoomData := preload("res://content/rooms/crypt/arena_01.tres")
const RoomScan := preload("res://tests/content/rooms/room_scan.gd")

var room_root: Node


func before_each() -> void:
	room_root = own((RoomData as RoomBase).scene.instantiate()) as Node


func test_resource_has_an_id_a_scene_and_spawns() -> void:
	var room: RoomBase = RoomData
	check_equal(room.id, &"arena_01", "the id")
	check(room.scene != null, "the room has a scene")
	check_equal(room.places().player_spawns.size(), 4, "player spawns")
	check(room.places().enemy_spawns.size() >= 4, "at least four enemy spawns")
	check(room.places().doors.size() >= 1, "at least one door")


func test_scene_has_no_scripts() -> void:
	check_equal(RoomScan.scripts_below(room_root), 0, "scripts in the scene")


func test_spawn_groups_hold_only_markers() -> void:
	for group in ["PlayerSpawns", "EnemySpawns", "Doors"]:
		check(RoomScan.only_markers(room_root, group), "%s holds only Marker2D nodes" % group)
