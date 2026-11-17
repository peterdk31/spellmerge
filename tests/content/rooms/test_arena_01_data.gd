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


func test_it_is_a_floating_room_drawn_from_its_shape() -> void:
	var room: RoomBase = RoomData
	var ground: Node = room_root.get_node_or_null("Floor")
	check(ground != null and ground.has_meta(&"ground_inputs"), "its floor is the ground drawn from arena_01.shape.json")
	check(ground != null and ground.get_node_or_null("Walls/WallArt") == null, "no wall art: its edge is an invisible wall over the dark")
	var void_art: Sprite2D = room_root.get_node_or_null("Void") as Sprite2D
	check(void_art != null and ground != null and void_art.z_index < (ground as CanvasItem).z_index, "its own Void is drawn behind the slab")
	check_equal(room.ambient, 0.8, "a crypt room's ambient (rule 6)")
	check(room.floor_mark_colors.size() > 0 and room.debris_colors.size() > 0, "it names its floor-mark and debris colours (rule 9)")


func test_its_pillars_are_props_and_its_exits_gates() -> void:
	var places: RoomPlaces = (RoomData as RoomBase).places()
	var ids: Dictionary[StringName, int] = {}
	for prop: Resource in places.placed_of(PropBase):
		var id: StringName = (prop as PropBase).id
		ids[id] = ids.get(id, 0) + 1
	check(ids.get(&"crypt_pillar", 0) >= 4, "its pillars are crypt_pillar props (%d)" % ids.get(&"crypt_pillar", 0))
	check_equal(ids.get(&"crypt_gate", 0), 2, "its two exits are crypt gates")
	check_equal(ids.get(&"room_exit", 0), 0, "no old exit stands in it")


func test_its_landmark_stands_under_the_shaft() -> void:
	var decor: Node = room_root.get_node("Decor")
	var beam: Node2D = decor.get_node_or_null("Beam") as Node2D
	var column: Sprite2D = decor.get_node_or_null("FallenColumn") as Sprite2D
	check(beam != null and column != null, "the shaft of light and the fallen column")
	if beam != null and column != null:
		check(RoomScan.sprite_rect(column).has_point(beam.position), "the shaft falls on the fallen column")
		check(beam.get_node("Light").is_in_group(&"light_spot"), "the shaft lights the floor")
