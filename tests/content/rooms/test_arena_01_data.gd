extends "res://tests/support/suite.gd"
## The crypt room's data (content/rooms/crypt/arena_01): the resource is a RoomBase, the scene
## has no scripts, and its spawns and doors are its scene's markers (props W8a: `RoomPlaces`). The
## antechamber (crypt rework CR3, docs/milestones/crypt-rework.md): a floating room drawn from its
## shape, its pillars and gates props, its landmark the fallen column under a shaft of light.

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


## A floating room drawn from its shape, its own Void behind the slab, its five pillars props and its
## exits gates (`RoomScan.floating_room_problems`).
func test_it_is_a_floating_room_drawn_from_its_shape() -> void:
	check_equal(RoomScan.floating_room_problems(RoomData as RoomBase, room_root, 4), PackedStringArray(), "a floating room")


func test_its_landmark_stands_under_the_shaft() -> void:
	var decor: Node = room_root.get_node("Decor")
	var beam: Node2D = decor.get_node_or_null("Beam") as Node2D
	var column: Sprite2D = decor.get_node_or_null("FallenColumn") as Sprite2D
	check(beam != null and column != null, "the shaft of light and the fallen column")
	if beam != null and column != null:
		check(RoomScan.sprite_rect(column).has_point(beam.position), "the shaft falls on the fallen column")
		check(beam.get_node("Light").is_in_group(&"light_spot"), "the shaft lights the floor")
