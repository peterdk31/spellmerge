extends "res://tests/support/suite.gd"
## The ossuary court's data (content/rooms/crypt/arena_03, crypt rework CR5, docs/milestones/
## crypt-rework.md): a floating room drawn from its shape, its four pillars `crypt_pillar` props and its
## exits gates; its landmark the four low walls built of bones (each a wall of the room's own `Walls`,
## drawn by a sprite of its box's size), bones piled at their feet and candles low beside them; the
## court in the middle lit by a shaft; no pit; and its side ways beside `Pillar1` and `Pillar2` still
## the crypt's narrowest, the slab's edge pinned to the 32 px line there (rule 2).

const RoomData := preload("res://content/rooms/crypt/arena_03.tres")
const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const BoneWall := preload("res://art/tilesets/crypt/ossuary_wall.svg")
const BonePile := preload("res://art/tilesets/crypt/bone_pile.svg")

## The slab's edge line on the sides (the frame's inset) and the old way's width beside a side pillar.
const EDGE: float = 32.0
const WAY: float = 32.0

var room_root: Node


func before_each() -> void:
	room_root = own((RoomData as RoomBase).scene.instantiate()) as Node


func test_resource_has_an_id_a_scene_and_spawns() -> void:
	var room: RoomBase = RoomData
	check_equal(room.id, &"arena_03", "the id")
	check_equal(room.places().player_spawns.size(), 4, "player spawns")
	check(room.places().enemy_spawns.size() >= 4, "at least four enemy spawns")


func test_it_is_a_floating_room_drawn_from_its_shape() -> void:
	check_equal(RoomScan.floating_room_problems(RoomData as RoomBase, room_root, 4), PackedStringArray(), "a floating room with its four pillars")


## The four low walls built of bones: each a wall of the room's own `Walls`, drawn by a sprite of the
## bone wall's art of its box's size; a pile of bones lies at the foot of each, clear of every wall.
func test_its_landmark_is_its_low_walls_of_bones() -> void:
	var walls: Array[Rect2] = RoomScan.wall_rects(room_root)
	var boxes: Array[Rect2] = []
	for child in room_root.get_node("Walls").get_children():
		var sprite: Sprite2D = child as Sprite2D
		if sprite == null or sprite.texture != BoneWall:
			continue
		var box: Rect2 = RoomScan.sprite_rect(sprite)
		check(walls.has(box), "%s is a wall of its sprite's size: %s" % [child.name, box])
		boxes.append(box)
	check_equal(boxes.size(), 4, "four low walls of bones")
	var piles: Array[Rect2] = []
	for child in room_root.get_node("Decor").get_children():
		if child is Sprite2D and (child as Sprite2D).texture == BonePile:
			piles.append(RoomScan.sprite_rect(child as Sprite2D))
	for box in boxes:
		var at_foot: bool = false
		for pile in piles:
			at_foot = at_foot or pile.intersects(box.grow(8.0))
		check(at_foot, "bones are piled at the foot of the wall %s" % box)
	for pile in piles:
		for wall in walls:
			check(not pile.intersects(wall.grow(-0.5)), "the pile %s lies clear of the wall %s" % [pile, wall])


## The court between the rows of low walls is lit by a shaft of light, and lit candles stand low
## beside the walls of bones (the room's torches, "The rooms": a floating room has no wall to hang one on).
func test_the_court_is_lit_by_a_shaft_and_candles_beside_its_walls() -> void:
	var beam: Node2D = room_root.get_node_or_null("Decor/Beam") as Node2D
	check(beam != null, "the shaft of light")
	if beam != null:
		check(Rect2(288, 160, 64, 128).has_point(beam.position), "it falls on the court: %s" % beam.position)
		check(beam.get_node("Light").is_in_group(&"light_spot"), "it lights the floor")
	var low_walls: Array[Rect2] = []
	for child in room_root.get_node("Walls").get_children():
		if child is Sprite2D and (child as Sprite2D).texture == BoneWall:
			low_walls.append(RoomScan.sprite_rect(child as Sprite2D))
	var beside: int = 0
	for child in room_root.get_node("Decor").get_children():
		var light: Node2D = child.get_node_or_null("Light") as Node2D
		if not String(child.name).begins_with("Candles") or light == null:
			continue
		check(light.is_in_group(&"light_spot"), "%s lights the floor" % child.name)
		var at: Vector2 = (child as Node2D).position + light.position
		for box in low_walls:
			if box.grow(40.0).has_point(at) and not box.has_point(at):
				beside += 1
				break
	check(beside >= 4, "candles stand beside the walls of bones (%d)" % beside)


## The ossuary court has no pit: its low walls make the room ("The rooms").
func test_it_has_no_pit() -> void:
	check(RoomPlaces.hole_rects(room_root).is_empty(), "no holes")


## Rule 2: between `Pillar1` and the slab's west edge, and `Pillar2` and its east edge, the way is
## the old 32 px (from the edge line to the old pillar box): open floor all of it, and the slab's
## invisible wall right at the line, pinned, so it is no narrower and no wider.
func test_its_side_ways_stay_the_narrowest() -> void:
	var width: float = (RoomData as RoomBase).places().size.x
	var walls: Array[Rect2] = RoomScan.wall_rects(room_root)
	for pair in [["Pillar1", true], ["Pillar2", false]]:
		var pillar: Node2D = room_root.get_node_or_null("Props/%s" % pair[0]) as Node2D
		check(pillar != null, "%s stands" % pair[0])
		if pillar == null:
			continue
		var west: bool = pair[1]
		var line: float = EDGE if west else width - EDGE
		check_equal(absf(pillar.position.x - line), WAY + 16.0, "%s stands its old way from the edge" % pair[0])
		var y0: float = pillar.position.y - 32.0
		var way: Rect2 = Rect2(line if west else line - WAY, y0, WAY, 40.0)
		var edge: Rect2 = Rect2(line - 8.0 if west else line, y0, 8.0, 40.0)
		var open: bool = true
		var held: float = 0.0
		for wall in walls:
			open = open and not way.intersects(wall.grow(-0.5))
			held += wall.intersection(edge).get_area()
		check(open, "the way beside %s is open floor: %s" % [pair[0], way])
		check(held >= edge.get_area() - 0.5, "the slab's edge is pinned at the 32 px line beside %s" % pair[0])
