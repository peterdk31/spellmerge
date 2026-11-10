extends "res://tests/support/suite.gd"
## The hub room (content/rooms/hub, docs/milestones/online-lobby.md, L1): a large island floating
## in the void, the void round it all wall, the teleporter stone in the middle, three dummies
## together off to one side and the multiplayer altar. The data matches the scene; no scripts; the
## stone's lit look starts hidden, in the group Feel shows; nothing starts on the stone or in a wall.

const RoomData := preload("res://content/rooms/hub/hub.tres")
const RoomScan := preload("res://tests/content/rooms/room_scan.gd")

## Half the size of a body (a wizard, a dummy), in pixels.
const BODY_RADIUS: float = 12.0

var room_root: Node


func before_each() -> void:
	room_root = own((RoomData as RoomBase).scene.instantiate()) as Node


func _room() -> RoomBase:
	return RoomData as RoomBase


## A body standing at `point`.
func _body(point: Vector2) -> Rect2:
	return Rect2(point - Vector2.ONE * BODY_RADIUS, Vector2.ONE * BODY_RADIUS * 2.0)


func test_resource_is_the_hub_where_hits_take_nothing() -> void:
	var room: RoomBase = _room()
	check_equal(room.id, &"hub", "the id")
	check(room.scene != null, "the room has a scene")
	check_equal(room.player_spawns.size(), 4, "player spawns")
	check_equal(room.dummy_spawns.size(), 3, "three dummies")
	check(room.enemy_spawns.is_empty(), "no enemy spawns: no wave there")
	check(room.invincible, "hits take nothing in the hub")
	check(room.start_stone.has_area(), "it has a teleporter stone")
	for i in room.dummy_spawns.size():
		check_equal(room.dummy_id(i), &"training_dummy", "dummy %d is a training dummy" % i)


func test_the_other_rooms_have_no_stone_and_hurt() -> void:
	for path: String in ["res://content/rooms/crypt/arena_01.tres", "res://content/rooms/crypt/sandbox.tres"]:
		var room: RoomBase = load(path) as RoomBase
		check(not room.start_stone.has_area(), "%s has no stone" % room.id)
		check(not room.altar.has_area(), "%s has no altar" % room.id)
		check(not room.invincible, "%s hurts" % room.id)


func test_spawns_match_the_markers() -> void:
	check_equal(RoomScan.markers(room_root, "PlayerSpawns"), _room().player_spawns, "player spawns")
	check_equal(RoomScan.markers(room_root, "DummySpawns"), _room().dummy_spawns, "dummy spawns")


func test_scene_has_no_scripts() -> void:
	check_equal(RoomScan.scripts_below(room_root), 0, "scripts in the scene")


func test_the_stone_art_is_where_the_stone_is() -> void:
	var stone := room_root.get_node("Stone") as Sprite2D
	var lit := room_root.get_node("StoneLit") as Sprite2D
	check_equal(RoomScan.sprite_rect(stone), _room().start_stone, "the stone's art covers the stone")
	check_equal(RoomScan.sprite_rect(lit), _room().start_stone, "its lit look lies on it")
	check(lit.is_in_group(RoomBase.STONE_LIT), "its lit look is in the group Feel shows when it lights")
	check(not lit.visible, "its lit look starts hidden")
	var in_group: int = 0
	for node: Node in room_root.find_children("*", "", true, false):
		if node.is_in_group(RoomBase.STONE_LIT):
			in_group += 1
	check_equal(in_group, 1, "only the lit look is in that group")


func test_the_room_is_large_and_the_void_round_the_island_is_wall() -> void:
	var size: Vector2 = _room().size_in(room_root)
	check(size.x >= 1280.0 and size.y >= 800.0, "a large room: %s" % size)
	var walls: Array[Rect2] = RoomScan.wall_rects(room_root)
	var floor_rects: Array[Rect2] = []
	for node: Node in room_root.get_children():
		if node is Sprite2D and String(node.name).begins_with("Floor"):
			floor_rects.append(RoomScan.sprite_rect(node as Sprite2D))
	check(floor_rects.size() >= 2, "the island is made of floor pieces")
	check_equal((room_root.get_node("Floor") as Sprite2D).z_index, RoomBase.FLOOR_Z, "its floor under the marks")
	# Every 8-pixel cell of the room is floor or wall, never both, never neither: no way off the island.
	var cell: float = 8.0
	var y: float = cell * 0.5
	var bad: int = 0
	while y < size.y:
		var x: float = cell * 0.5
		while x < size.x:
			var point := Vector2(x, y)
			var on_floor: bool = floor_rects.any(func(r: Rect2) -> bool: return r.has_point(point))
			var in_wall: bool = walls.any(func(r: Rect2) -> bool: return r.has_point(point))
			if on_floor == in_wall:
				bad += 1
			x += cell
		y += cell
	check_equal(bad, 0, "cells that are both floor and wall, or neither")


func test_a_rooms_size_follows_nested_walls() -> void:
	# A wall body under a moved node: its rectangle counts where it really is.
	var layout := own(Node2D.new()) as Node2D
	var group := Node2D.new()
	group.position = Vector2(700.0, 500.0)
	layout.add_child(group)
	var body := StaticBody2D.new()
	body.collision_layer = RoomBase.WALL_LAYER
	body.position = Vector2(100.0, 50.0)
	group.add_child(body)
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(64.0, 32.0)
	shape.shape = box
	shape.position = Vector2(32.0, 16.0)
	body.add_child(shape)
	check_equal(RoomBase.new().size_in(layout), Vector2(864.0, 582.0), "the wall's far corner, through every parent")


func test_nothing_starts_in_a_wall_or_on_the_stone() -> void:
	var walls: Array[Rect2] = RoomScan.wall_rects(room_root)
	var stone: Rect2 = _room().start_stone
	for point: Vector2 in _room().player_spawns:
		check(not stone.intersects(_body(point)), "player spawn %s is off the stone, so a joiner puts it out" % point)
		for wall: Rect2 in walls:
			check(not wall.intersects(_body(point)), "player spawn %s is clear of the wall %s" % [point, wall])
	for point: Vector2 in _room().dummy_spawns:
		check(not stone.intersects(_body(point)), "dummy %s is off the stone" % point)
		for wall: Rect2 in walls:
			check(not wall.intersects(_body(point)), "dummy %s is clear of the wall %s" % [point, wall])
	for wall: Rect2 in walls:
		check(not wall.intersects(stone.grow(BODY_RADIUS)), "the stone has room round it (wall %s)" % wall)


## The island's edge gives off motes (`MoteRim`; the owner's pick, "A, mixed elements"): one hidden
## rim node, a sound look whose kind exists, in the elements' palette ramps, its points clockwise
## round the floor so every stretch has floor on its right and void (wall) on its left.
func test_the_rim_of_motes_runs_round_the_island() -> void:
	var rims: Array[Node] = []
	for node: Node in room_root.find_children("*", "", true, false):
		if node.is_in_group(MoteRim.GROUP):
			rims.append(node)
	check_equal(rims.size(), 1, "one rim")
	if rims.is_empty():
		return
	var line := rims[0] as Line2D
	check(line != null and not line.visible and line.closed, "a hidden, closed Line2D")
	var look: MoteRim = MoteRim.of(line)
	check(look != null and look.problems().is_empty(), "a sound MoteRim")
	if look == null:
		return
	check(ResourceLoader.exists("res://content/motes/%s.tres" % look.kind), "its kind %s is a mote kind" % look.kind)
	check_equal(look.ramps.size(), 5, "five ramps: fire, spark, arc, ice, void")
	var walls: Array[Rect2] = RoomScan.wall_rects(room_root)
	var bad: int = 0
	var points: PackedVector2Array = line.points
	for i in points.size():
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		var mid: Vector2 = (a + b) * 0.5
		var way: Vector2 = (b - a).normalized()
		var left := Vector2(way.y, -way.x)
		var outside: Vector2 = mid + left * 4.0
		var inside: Vector2 = mid - left * 4.0
		if not walls.any(func(r: Rect2) -> bool: return r.has_point(outside)) or walls.any(func(r: Rect2) -> bool: return r.has_point(inside)):
			bad += 1
	check_equal(bad, 0, "stretches without void on their left and floor on their right")


func test_the_dummies_stand_together_away_from_the_stone() -> void:
	var spawns: PackedVector2Array = _room().dummy_spawns
	var centre: Vector2 = _room().start_stone.get_center()
	for i in spawns.size():
		check(spawns[i].distance_to(centre) > 200.0, "dummy %s is off to one side" % spawns[i])
		for j in range(i + 1, spawns.size()):
			var gap: float = spawns[i].distance_to(spawns[j])
			check(gap >= BODY_RADIUS * 4.0 and gap <= 160.0, "dummies %s and %s stand together, apart" % [spawns[i], spawns[j]])


func test_the_altar_stands_on_the_island() -> void:
	var altar := room_root.get_node("Altar") as Sprite2D
	var area: Rect2 = RoomScan.sprite_rect(altar)
	check(not area.intersects(_room().start_stone), "the altar is not the stone")
	check_equal(area, _room().altar, "the altar's art covers the altar (where A opens the room)")
	for wall: Rect2 in RoomScan.wall_rects(room_root):
		check(not wall.intersects(area), "the altar is clear of the wall %s" % wall)
