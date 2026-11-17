extends "res://tests/support/suite.gd"
## Every room template's pillars (content/rooms: every room a run's map can pick that has pillars)
## are drawn as 2.5D columns: a base on the collision footprint, a top above it that is drawn over
## characters standing behind, and a shadow on the floor. Only what matters to play: the collision
## stays the base footprint, and the top never hides a wizard in front.

const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const FOOTPRINT: Vector2 = Vector2(32, 32)

## The templates with pillars, and each one's layout.
var rooms: Array[RoomBase] = []
var layouts: Array[Node] = []


func before_each() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	rooms.clear()
	layouts.clear()
	for room in RoomScan.templates(registry):
		var layout: Node = own(room.scene.instantiate()) as Node
		if not _footprints(layout).is_empty():
			rooms.append(room)
			layouts.append(layout)


func _footprints(layout: Node) -> Array[Rect2]:
	var found: Array[Rect2] = []
	var walls: Node = layout.get_node_or_null("Walls")
	if walls == null:
		# A floating room (crypt rework CR3): its pillars are props, not wall tiles.
		return found
	for child in walls.get_children():
		if String(child.name).begins_with("Pillar") and child is CollisionShape2D:
			found.append(Rect2((child as CollisionShape2D).position - FOOTPRINT * 0.5, FOOTPRINT))
	return found


func _rects(layout: Node, group: String) -> Array[Rect2]:
	var found: Array[Rect2] = []
	for child in layout.get_node(group).get_children():
		if child is Sprite2D:
			found.append(RoomScan.sprite_rect(child as Sprite2D))
	return found


func test_rooms_with_pillars_are_found() -> void:
	check(rooms.size() >= 1, "some templates have pillars (%d)" % rooms.size())


func test_a_pillar_blocks_one_tile() -> void:
	for at in rooms.size():
		for child in layouts[at].get_node("Walls").get_children():
			if String(child.name).begins_with("Pillar") and child is CollisionShape2D:
				var box: RectangleShape2D = (child as CollisionShape2D).shape as RectangleShape2D
				check(box != null and box.size == FOOTPRINT, "%s: %s blocks one tile" % [rooms[at].id, child.name])


func test_every_pillar_has_a_base_on_its_footprint() -> void:
	for at in rooms.size():
		var bases: Array[Rect2] = _rects(layouts[at], "Pillars")
		var footprints: Array[Rect2] = _footprints(layouts[at])
		for rect in footprints:
			check(bases.has(rect), "%s: a base is drawn on the footprint %s" % [rooms[at].id, rect])
		check_equal(bases.size(), footprints.size(), "%s: one base per pillar" % rooms[at].id)


func test_every_pillar_has_a_top_straight_above_its_base() -> void:
	for at in rooms.size():
		var tops: Array[Rect2] = _rects(layouts[at], "PillarTops")
		var footprints: Array[Rect2] = _footprints(layouts[at])
		for rect in footprints:
			check(tops.has(Rect2(rect.position - Vector2(0, FOOTPRINT.y), FOOTPRINT)), "%s: a top is drawn right above %s" % [rooms[at].id, rect])
		check_equal(tops.size(), footprints.size(), "%s: one top per pillar" % rooms[at].id)


func test_the_tops_are_drawn_over_characters_and_the_bases_are_not() -> void:
	# Wizards and enemies are added after the room at z_index 0: a raised top draws over
	# them (they walk behind it); the base stays at 0 and in the room's tree order, under them.
	for at in rooms.size():
		check((layouts[at].get_node("PillarTops") as Node2D).z_index > 0, "%s: the tops are above characters" % rooms[at].id)
		check_equal((layouts[at].get_node("Pillars") as Node2D).z_index, 0, "%s: the bases are below characters" % rooms[at].id)


func test_the_tops_let_a_character_behind_them_show_through() -> void:
	for at in rooms.size():
		var alpha: float = (layouts[at].get_node("PillarTops") as Node2D).modulate.a
		check(alpha > 0.3 and alpha < 1.0, "%s: translucent, so a wizard behind a pillar is still seen" % rooms[at].id)


func test_the_collision_is_only_the_base_footprint() -> void:
	for at in rooms.size():
		for rect in _footprints(layouts[at]):
			var top: Rect2 = Rect2(rect.position - Vector2(0, FOOTPRINT.y), FOOTPRINT)
			for wall in RoomScan.wall_rects(layouts[at]):
				check(not wall.intersects(top), "%s: nothing blocks under the top drawn above %s (it is only drawn)" % [rooms[at].id, rect])


func test_every_pillar_has_a_shadow_on_the_floor() -> void:
	for at in rooms.size():
		var shadows: int = 0
		for child in layouts[at].get_node("Shade").get_children():
			if String(child.name).begins_with("Pillar") and child is Polygon2D:
				shadows += 1
		check_equal(shadows, _footprints(layouts[at]).size(), "%s: one shadow per pillar" % rooms[at].id)


func test_the_shadow_is_drawn_under_the_pillar_bases() -> void:
	for at in rooms.size():
		var layout: Node = layouts[at]
		check(layout.get_node("Shade").get_index() < layout.get_node("Pillars").get_index(), "%s: shadows sit under the base that casts them" % rooms[at].id)
