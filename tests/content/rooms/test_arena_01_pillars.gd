extends "res://tests/support/suite.gd"
## The crypt room's pillars (content/rooms/crypt/arena_01) are drawn as 2.5D columns: a base
## on the collision footprint, a top above it that is drawn over characters standing behind,
## and a shadow on the floor. Only what matters to play: the collision stays the base
## footprint, and the top never hides a wizard in front.

const RoomData := preload("res://content/rooms/crypt/arena_01.tres")
const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const FOOTPRINT: Vector2 = Vector2(32, 32)

var room_root: Node
var footprints: Array[Rect2] = []


func before_each() -> void:
	room_root = own((RoomData as RoomBase).scene.instantiate()) as Node
	footprints.clear()
	for child in room_root.get_node("Walls").get_children():
		if String(child.name).begins_with("Pillar") and child is CollisionShape2D:
			var shape_node: CollisionShape2D = child as CollisionShape2D
			footprints.append(Rect2(shape_node.position - FOOTPRINT * 0.5, FOOTPRINT))


func _rects(group: String) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child in room_root.get_node(group).get_children():
		if child is Sprite2D:
			rects.append(RoomScan.sprite_rect(child as Sprite2D))
	return rects


func test_the_room_has_pillars_with_a_footprint_each() -> void:
	check(footprints.size() >= 1, "the room has pillars")
	for rect in footprints:
		check_equal(rect.size, FOOTPRINT, "a pillar blocks one tile")


func test_every_pillar_has_a_base_on_its_footprint() -> void:
	var bases: Array[Rect2] = _rects("Pillars")
	for rect in footprints:
		check(bases.has(rect), "a base is drawn on the footprint %s" % rect)
	check_equal(bases.size(), footprints.size(), "one base per pillar")


func test_every_pillar_has_a_top_straight_above_its_base() -> void:
	var tops: Array[Rect2] = _rects("PillarTops")
	for rect in footprints:
		check(tops.has(Rect2(rect.position - Vector2(0, FOOTPRINT.y), FOOTPRINT)), "a top is drawn right above %s" % rect)
	check_equal(tops.size(), footprints.size(), "one top per pillar")


func test_the_tops_are_drawn_over_characters_and_the_bases_are_not() -> void:
	# Wizards and enemies are added after the room at z_index 0: a raised top draws over
	# them (they walk behind it); the base stays at 0 and in the room's tree order, under them.
	check((room_root.get_node("PillarTops") as Node2D).z_index > 0, "the tops are above characters")
	check_equal((room_root.get_node("Pillars") as Node2D).z_index, 0, "the bases are below characters")


func test_the_tops_let_a_character_behind_them_show_through() -> void:
	var alpha: float = (room_root.get_node("PillarTops") as Node2D).modulate.a
	check(alpha > 0.3 and alpha < 1.0, "translucent, so a wizard behind a pillar is still seen")


func test_the_collision_is_only_the_base_footprint() -> void:
	for rect in footprints:
		var top: Rect2 = Rect2(rect.position - Vector2(0, FOOTPRINT.y), FOOTPRINT)
		for wall in RoomScan.wall_rects(room_root):
			check(not wall.intersects(top), "nothing blocks under the top drawn above %s (it is only drawn)" % rect)


func test_every_pillar_has_a_shadow_on_the_floor() -> void:
	var shadows: int = 0
	for child in room_root.get_node("Shade").get_children():
		if String(child.name).begins_with("Pillar") and child is Polygon2D:
			shadows += 1
	check_equal(shadows, footprints.size(), "one shadow per pillar")


func test_the_shadow_is_drawn_under_the_pillar_bases() -> void:
	check(room_root.get_node("Shade").get_index() < room_root.get_node("Pillars").get_index(), "shadows sit under the base that casts them")
