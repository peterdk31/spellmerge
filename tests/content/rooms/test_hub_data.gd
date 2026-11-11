extends "res://tests/support/suite.gd"
## The hub room (content/rooms/hub, docs/milestones/online-lobby.md, L1): a large island floating
## in the void, the void round it all wall, the teleporter stone in the middle, three dummies
## together off to one side and the multiplayer altar, both props (props W8: content/props/hub_stone,
## hub_altar), and the prop yard, all placed in its scene (props W8a: `RoomPlaces`). No scripts;
## the stone's art lies on the stone in both its states; nothing starts on the stone or in a wall;
## the yard is open floor.

const RoomData := preload("res://content/rooms/hub/hub.tres")
const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const FlowScript := preload("res://gameplay/flow/flow.gd")

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
	check_equal(room.places().player_spawns.size(), 4, "player spawns")
	check_equal(room.places().placed_at_of(EnemyBase).size(), 3, "three dummies")
	check(room.places().enemy_spawns.is_empty(), "no enemy spawns: no wave there")
	check(room.invincible, "hits take nothing in the hub")
	check(HubRules.area_of(room.places(), HubRules.ROLE_RUN_START).has_area(), "it has a teleporter stone")
	for dummy: EnemyBase in room.places().placed_of(EnemyBase):
		check_equal(dummy.id, &"training_dummy", "a training dummy")
	check_equal(room.places().problems(), PackedStringArray(), "every stand-in and zone has its data")


func test_the_other_rooms_have_no_stone_and_hurt() -> void:
	for path: String in ["res://content/rooms/crypt/arena_01.tres", "res://content/rooms/crypt/sandbox.tres"]:
		var room: RoomBase = load(path) as RoomBase
		check(not HubRules.area_of(room.places(), HubRules.ROLE_RUN_START).has_area(), "%s has no stone" % room.id)
		check(not HubRules.area_of(room.places(), HubRules.ROLE_PARTY_ALTAR).has_area(), "%s has no altar" % room.id)
		check(not room.invincible, "%s hurts" % room.id)


func test_scene_has_no_scripts() -> void:
	check_equal(RoomScan.scripts_below(room_root), 0, "scripts in the scene")


## The prop of `id` the room stands, and where its feet are (null and INF when it has none).
func _prop(id: StringName) -> PropBase:
	for data: PropBase in _room().places().placed_of(PropBase):
		if data.id == id:
			return data
	return null


func _prop_at(id: StringName) -> Vector2:
	var places: RoomPlaces = _room().places()
	for i in places.of_kind(PropBase):
		if (places.placed[i] as PropBase).id == id:
			return places.placed_at[i]
	return Vector2.INF


## Where layer `layer` of a prop whose feet are at `feet` is drawn (its bottom middle on the feet,
## moved by its offset).
func _layer_rect(layer: PropLayer, feet: Vector2) -> Rect2:
	var size := Vector2(layer.frame_size())
	return Rect2(feet + layer.offset - Vector2(size.x * 0.5, size.y), size)


## The stone is a prop (props W8), the one Flow lights (`Flow.STONE_PROP`), stood on where its own
## ground is (W8b), in the states Flow puts it in, its slab's art on its ground in both, on the floor; walked onto (it blocks nothing and takes no hit),
## invincible, never in the yard, and its lit look plays the stone's cue.
func test_the_stone_is_a_prop_on_the_stone() -> void:
	var stone: PropBase = _prop(&"hub_stone")
	check(stone != null, "the room stands the hub's stone")
	if stone == null:
		return
	var feet: Vector2 = _prop_at(&"hub_stone")
	check(HubRules.area_of(_room().places(), HubRules.ROLE_RUN_START).has_point(feet), "it stands on the stone")
	check_equal(stone.states.list[0].state_id, HubRules.UNLIT, "it starts unlit")
	check(stone.states.state_at(HubRules.LIT) >= 0, "it can be lit")
	for state in stone.states.list:
		check(not state.blocks and not state.hittable, "%s: walked onto, never hit" % state.state_id)
		var look: PropStateLook = stone.look_of(state.state_id)
		check(look != null, "%s has a look" % state.state_id)
		if look == null:
			continue
		for layer in look.layers:
			check_equal(_layer_rect(layer, feet), HubRules.area_of(_room().places(), HubRules.ROLE_RUN_START), "%s: its art lies on the stone" % state.state_id)
			check_equal(layer.drawn, PropLayer.Drawn.ON_FLOOR, "%s: on the floor" % state.state_id)
	check(stone.invincible and stone.role == HubRules.ROLE_RUN_START, "invincible, the hub's run_start (so never in the yard)")
	check_equal(stone.look_of(HubRules.LIT).cue, &"stone_lit", "it plays the stone's cue as it lights")
	check_equal(stone.look_of(HubRules.UNLIT).cue, &"", "and none as it goes out")


## The yard (props W8): open floor on the island, clear of the walls, the stone, the altar and
## every spawn, with room round it.
func test_the_prop_yard_is_open_floor() -> void:
	var room: RoomBase = _room()
	var yard: Rect2 = room.places().zone(FlowScript.ZONE_PROP_YARD)
	check(yard.has_area(), "the hub has a prop yard")
	check(yard.size.x >= 256.0 and yard.size.y >= 96.0, "room for a row of props and to try spells: %s" % yard)
	for wall: Rect2 in RoomScan.wall_rects(room_root):
		check(not wall.intersects(yard), "clear of the wall %s" % wall)
	check(not yard.intersects(HubRules.area_of(room.places(), HubRules.ROLE_RUN_START).grow(32.0)), "clear of the stone")
	check(not yard.intersects(HubRules.area_of(room.places(), HubRules.ROLE_PARTY_ALTAR).grow(32.0)), "clear of the altar")
	for spawns: PackedVector2Array in [room.places().player_spawns, room.places().joiner_spawns, room.places().placed_at_of(EnemyBase)]:
		for point: Vector2 in spawns:
			check(not yard.intersects(_body(point).grow(32.0)), "clear of the spawn %s" % point)
	for other: String in ["res://content/rooms/crypt/arena_01.tres", "res://content/rooms/crypt/sandbox.tres"]:
		check(not (load(other) as RoomBase).places().zone(FlowScript.ZONE_PROP_YARD).has_area(), "%s has none" % other)


func test_the_room_is_large_and_the_void_round_the_island_is_wall() -> void:
	var size: Vector2 = RoomPlaces.read(room_root).size
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
	check_equal(RoomPlaces.read(layout).size, Vector2(864.0, 582.0), "the wall's far corner, through every parent")


func test_nothing_starts_in_a_wall_or_on_the_stone() -> void:
	var walls: Array[Rect2] = RoomScan.wall_rects(room_root)
	var stone: Rect2 = HubRules.area_of(_room().places(), HubRules.ROLE_RUN_START)
	for point: Vector2 in _room().places().player_spawns:
		check(not stone.intersects(_body(point)), "player spawn %s is off the stone, so a joiner puts it out" % point)
		for wall: Rect2 in walls:
			check(not wall.intersects(_body(point)), "player spawn %s is clear of the wall %s" % [point, wall])
	for point: Vector2 in _room().places().placed_at_of(EnemyBase):
		check(not stone.intersects(_body(point)), "dummy %s is off the stone" % point)
		for wall: Rect2 in walls:
			check(not wall.intersects(_body(point)), "dummy %s is clear of the wall %s" % [point, wall])
	for wall: Rect2 in walls:
		check(not wall.intersects(stone.grow(BODY_RADIUS)), "the stone has room round it (wall %s)" % wall)


## The island's edge gives off motes (a `MoteSource` line, props W7; the owner's pick, "A, mixed elements"): one hidden
## rim node, a sound look whose kind exists, in the elements' palette ramps, its points clockwise
## round the floor so every stretch has floor on its right and void (wall) on its left.
func test_the_rim_of_motes_runs_round_the_island() -> void:
	var rims: Array[Node] = []
	for node: Node in room_root.find_children("*", "", true, false):
		if node.is_in_group(MoteSource.GROUP):
			rims.append(node)
	check_equal(rims.size(), 1, "one rim")
	if rims.is_empty():
		return
	var line := rims[0] as Line2D
	check(line != null and not line.visible and line.closed, "a hidden, closed Line2D")
	var look: MoteSource = MoteSource.of(line)
	check(look != null and look.problems(false).is_empty(), "a sound MoteSource")
	check(look != null and look.from == MoteSource.From.LINE and look.points.is_empty(), "a line along the node's own points")
	if look == null:
		return
	check(ResourceLoader.exists("res://content/motes/%s.tres" % look.kind), "its kind %s is a mote kind" % look.kind)
	check_equal(look.colours, [&"fire", &"spark", &"arc", &"ice", &"void"] as Array[StringName], "the elements' five materials")
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
	var spawns: PackedVector2Array = _room().places().placed_at_of(EnemyBase)
	var centre: Vector2 = HubRules.area_of(_room().places(), HubRules.ROLE_RUN_START).get_center()
	for i in spawns.size():
		check(spawns[i].distance_to(centre) > 200.0, "dummy %s is off to one side" % spawns[i])
		for j in range(i + 1, spawns.size()):
			var gap: float = spawns[i].distance_to(spawns[j])
			check(gap >= BODY_RADIUS * 4.0 and gap <= 160.0, "dummies %s and %s stand together, apart" % [spawns[i], spawns[j]])


func test_the_altar_stands_on_the_island() -> void:
	var altar: PropBase = _prop(&"hub_altar")
	check(altar != null, "the room stands the hub's altar")
	if altar == null:
		return
	check(altar.invincible and altar.role == HubRules.ROLE_PARTY_ALTAR, "invincible, the hub's party_altar (so never in the yard)")
	for state in altar.states.list:
		check(not state.blocks and not state.hittable, "%s: walked onto, never hit" % state.state_id)
	var area: Rect2 = _layer_rect(altar.look_of(altar.states.list[0].state_id).layers[0], _prop_at(&"hub_altar"))
	check(not area.intersects(HubRules.area_of(_room().places(), HubRules.ROLE_RUN_START)), "the altar is not the stone")
	check_equal(area, HubRules.area_of(_room().places(), HubRules.ROLE_PARTY_ALTAR), "the altar's art covers the altar (where A opens the room)")
	for wall: Rect2 in RoomScan.wall_rects(room_root):
		check(not wall.intersects(area), "the altar is clear of the wall %s" % wall)


## A joining machine's wizards arrive beside the altar (online lobby, decision 4): a spawn for each
## seat, on the island, clear of the walls, the stone, the altar (where A opens the room) and each
## other.
func test_joiners_arrive_beside_the_altar() -> void:
	var room: RoomBase = _room()
	check_equal(room.places().joiner_spawns.size(), 4, "one for each seat")
	var walls: Array[Rect2] = RoomScan.wall_rects(room_root)
	for i in room.places().joiner_spawns.size():
		var point: Vector2 = room.places().joiner_spawns[i]
		check(not HubRules.area_of(room.places(), HubRules.ROLE_PARTY_ALTAR).intersects(_body(point)), "joiner spawn %s is off the altar" % point)
		check(point.distance_to(HubRules.area_of(room.places(), HubRules.ROLE_PARTY_ALTAR).get_center()) < 128.0, "joiner spawn %s is beside it" % point)
		check(not HubRules.area_of(room.places(), HubRules.ROLE_RUN_START).intersects(_body(point)), "joiner spawn %s is off the stone" % point)
		for wall: Rect2 in walls:
			check(not wall.intersects(_body(point)), "joiner spawn %s is clear of the wall %s" % [point, wall])
		for j in range(i + 1, room.places().joiner_spawns.size()):
			check(not _body(point).intersects(_body(room.places().joiner_spawns[j])), "joiner spawns %s and %s do not overlap" % [point, room.places().joiner_spawns[j]])
	for path: String in ["res://content/rooms/crypt/arena_01.tres", "res://content/rooms/crypt/sandbox.tres"]:
		check((load(path) as RoomBase).places().joiner_spawns.is_empty(), "%s has none: a joiner comes in away from danger" % path)
