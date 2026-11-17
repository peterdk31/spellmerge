extends "res://tests/support/suite.gd"
## The nave's data (content/rooms/crypt/arena_02, crypt rework CR4, docs/milestones/crypt-rework.md):
## a floating room drawn from its shape, its two colonnades `crypt_pillar` props and its exits gates;
## its landmark the sarcophagus in the middle of the nave (a low wall in its own `Walls`, drawn by a
## sprite of its box's size) ringed by candles; a shaft of light at one end; the floor of its south-west
## aisle fallen in, a pit in the edge style `crypt_pit`, clear of every spawn and placement.

const RoomData := preload("res://content/rooms/crypt/arena_02.tres")
const RoomScan := preload("res://tests/content/rooms/room_scan.gd")

## How far every spawn stands from the pit: a body's width and more.
const SPAWN_CLEAR: float = 32.0

var room_root: Node


func before_each() -> void:
	room_root = own((RoomData as RoomBase).scene.instantiate()) as Node


func test_resource_has_an_id_a_scene_and_spawns() -> void:
	var room: RoomBase = RoomData
	check_equal(room.id, &"arena_02", "the id")
	check_equal(room.places().player_spawns.size(), 4, "player spawns")
	check(room.places().enemy_spawns.size() >= 4, "at least four enemy spawns")


func test_it_is_a_floating_room_drawn_from_its_shape() -> void:
	check_equal(RoomScan.floating_room_problems(RoomData as RoomBase, room_root, 8), PackedStringArray(), "a floating room with its two colonnades")


## The sarcophagus: one low wall of the room's own `Walls`, its sprite its box's size, candles round it
## (each lit), none over it.
func test_its_landmark_is_the_sarcophagus_ringed_by_candles() -> void:
	var walls: Node = room_root.get_node_or_null("Walls")
	var sprite: Sprite2D = walls.get_node_or_null("Sarcophagus") as Sprite2D if walls != null else null
	check(sprite != null, "the sarcophagus is drawn on the room's Walls")
	if sprite == null:
		return
	var box: Rect2 = RoomScan.sprite_rect(sprite)
	check(RoomScan.wall_rects(room_root).has(box), "it is a wall of its sprite's size: %s" % box)
	var round: int = 0
	for child in room_root.get_node("Decor").get_children():
		var light: Node2D = child.get_node_or_null("Light") as Node2D
		if not String(child.name).begins_with("Candles") or light == null:
			continue
		var at: Vector2 = (child as Node2D).position + light.position
		if box.grow(40.0).has_point(at):
			round += 1
			check(not box.has_point(at), "%s stands beside it, not on it" % child.name)
			check(light.is_in_group(&"light_spot"), "%s lights it" % child.name)
	check(round >= 4, "candles ring it (%d)" % round)


## A shaft of light falls at one end of the nave (its outer quarter), lighting the floor.
func test_a_shaft_falls_at_one_end() -> void:
	var beam: Node2D = room_root.get_node_or_null("Decor/Beam") as Node2D
	check(beam != null, "the shaft of light")
	if beam == null:
		return
	var width: float = (RoomData as RoomBase).places().size.x
	check(beam.position.x < width * 0.25 or beam.position.x > width * 0.75, "at one end: x %.0f" % beam.position.x)
	check(beam.get_node("Light").is_in_group(&"light_spot"), "it lights the floor")


## The pit: holes in the ground's own `Holes` body, all in the south-west aisle, every spawn well
## clear of them, and ringed by floor: no wall touches a hole, so its lip, its cold glow and its rim are
## the pit's own and never the slab's edge (a body falls into a pit, never off the edge). A prop's ground
## on open floor is test_template_layout.gd's.
func test_its_south_west_aisle_has_fallen_into_a_pit() -> void:
	var ground: Node = room_root.get_node("Floor")
	var holes: Array[Rect2] = RoomPlaces.hole_rects(room_root)
	check(not holes.is_empty(), "it has a pit")
	check(ground.get_node_or_null("Holes") != null, "its holes are the ground's own")
	var size: Vector2 = (RoomData as RoomBase).places().size
	var places: RoomPlaces = (RoomData as RoomBase).places()
	var spawns: PackedVector2Array = places.player_spawns + places.enemy_spawns
	for hole in holes:
		check(hole.end.x <= size.x * 0.25 and hole.position.y >= size.y * 0.5, "the hole %s lies in the south-west aisle" % hole)
		for point in spawns:
			check(not hole.grow(SPAWN_CLEAR).has_point(point), "the spawn %s stands clear of the hole %s" % [point, hole])
	var walls: Array[Rect2] = RoomPlaces.wall_rects(room_root)
	for hole in holes:
		for wall in walls:
			check(not hole.grow(8.0).intersects(wall.grow(-0.5)), "the hole %s has floor between it and the wall %s" % [hole, wall])
	var glow: Sprite2D = ground.get_node_or_null("Glow") as Sprite2D
	check(glow != null and glow.texture.get_image().get_used_rect().has_area(), "the pit's still cold glow is drawn")
