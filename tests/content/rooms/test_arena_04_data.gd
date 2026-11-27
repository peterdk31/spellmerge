extends "res://tests/support/suite.gd"
## The crossing's data (content/rooms/crypt/arena_04, crypt rework CR6, docs/milestones/crypt-rework.md):
## a floating room drawn from its shape, its ring of four pillars `crypt_pillar` props and its two
## sockets; its landmark the ring round the middle, where the floor fell in: a round pit inside the ring
## in the edge style `crypt_pit`, small enough to dash over, ringed by floor and clear of every spawn and
## pillar, its two cracks running out between the pillars; the shaft falling into the pit; four
## sarcophagi (each a low wall of the room's own `Walls`, drawn by a sprite of its box's size) with lit
## candles beside them.

const RoomData := preload("res://content/rooms/crypt/arena_04.tres")
const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const Sarcophagus := preload("res://art/tilesets/crypt/sarcophagus@2x.svg")

## How far every spawn stands from the pit: a body's width and more.
const SPAWN_CLEAR: float = 32.0
## How far the pit stays from a pillar's ground: a wizard's body (24 px) walks between them.
const PILLAR_CLEAR: float = 24.0
## The pit's most extent across, in its 8 px hole cells: small enough to dash over ("The rooms": about
## 56×44 px drawn).
const PIT_ACROSS: float = 64.0
## How far out from the pit's middle a crack's heading is checked to pass between the pillars.
const CRACK_HEAD: float = 96.0

var room_root: Node


func before_each() -> void:
	room_root = own((RoomData as RoomBase).scene.instantiate()) as Node


func test_resource_has_an_id_a_scene_and_spawns() -> void:
	var room: RoomBase = RoomData
	check_equal(room.id, &"arena_04", "the id")
	check_equal(room.places().player_spawns.size(), 4, "player spawns")
	check(room.places().enemy_spawns.size() >= 4, "at least four enemy spawns")


func test_it_is_a_floating_room_drawn_from_its_shape() -> void:
	check_equal(RoomScan.floating_room_problems(RoomData as RoomBase, room_root, 4), PackedStringArray(), "a floating room with its ring of four pillars")


## The ring: the four pillar props stand round the middle of the room, and the pit lies inside it,
## within the box their feet span; every pillar's ground stays `PILLAR_CLEAR` off every hole, so a
## wizard walks round the pit inside the ring.
func test_its_landmark_is_the_ring_round_the_fallen_floor() -> void:
	var feet: PackedVector2Array = _pillar_feet()
	check_equal(feet.size(), 4, "a ring of four pillars")
	if feet.is_empty():
		return
	var ring: Rect2 = _ring(feet)
	var middle: Vector2 = (RoomData as RoomBase).places().size * 0.5
	check(ring.grow(-8.0).has_point(middle), "the ring stands round the room's middle: %s" % ring)
	var holes: Array[Rect2] = RoomPlaces.hole_rects(room_root)
	var pit: Rect2 = _pit(holes)
	check(pit.has_area(), "the floor has fallen in")
	check(ring.encloses(pit), "the pit lies inside the ring: %s in %s" % [pit, ring])
	var places: RoomPlaces = (RoomData as RoomBase).places()
	for i in places.of_kind(PropBase):
		var prop: PropBase = places.placed[i] as PropBase
		if prop.id != &"crypt_pillar":
			continue
		var ground: Rect2 = Rect2(places.placed_at[i] + prop.footprint_offset - prop.footprint_size * 0.5, prop.footprint_size)
		for hole in holes:
			check(not hole.grow(PILLAR_CLEAR).intersects(ground), "the pillar's ground %s stands clear of the hole %s" % [ground, hole])


## The pit: holes in the ground's own `Holes` body, small enough to dash over, every spawn and exit
## well clear of it, and ringed by floor (no wall touches a hole, so its lip, its cold glow and its rim
## are the pit's own); its two cracks run out from it, between the pillars, drawn into the floor. A
## prop's ground on open floor is test_template_layout.gd's; the way round it test_template_layout.gd's
## flood and test_ai_pit_rooms.gd's chases.
func test_its_middle_has_fallen_into_a_pit_small_enough_to_dash_over() -> void:
	var ground: Node = room_root.get_node("Floor")
	check(ground.get_node_or_null("Holes") != null, "its holes are the ground's own")
	var holes: Array[Rect2] = RoomPlaces.hole_rects(room_root)
	var pit: Rect2 = _pit(holes)
	check(pit.size.x <= PIT_ACROSS and pit.size.y <= PIT_ACROSS, "small enough to dash over: %s" % pit.size)
	var places: RoomPlaces = (RoomData as RoomBase).places()
	var spawns: PackedVector2Array = places.player_spawns + places.enemy_spawns + RoomScan.markers(room_root, "Doors")
	for i in places.of_kind(PropBase):
		if (places.placed[i] as PropBase).id == &"crypt_gate":
			spawns.append(places.placed_at[i])
	for hole in holes:
		for point in spawns:
			check(not hole.grow(SPAWN_CLEAR).has_point(point), "%s stands clear of the hole %s" % [point, hole])
	var walls: Array[Rect2] = RoomPlaces.wall_rects(room_root)
	for hole in holes:
		for wall in walls:
			check(not hole.grow(8.0).intersects(wall.grow(-0.5)), "the hole %s has floor between it and the wall %s" % [hole, wall])
	var glow: Sprite2D = ground.get_node_or_null("Glow") as Sprite2D
	check(glow != null and glow.texture.get_image().get_used_rect().has_area(), "the pit's still cold glow is drawn")
	# The cracks as the shape gives them (tools/ground_shape.py draws them, stopping short of every
	# pillar, spawn and decal, tools/test_ground_shape.py): two from the pit, each heading out through
	# a gap of the ring, its first `CRACK_HEAD` px from the pit's middle passing no pillar's foot nearer
	# than the shape's keep-clear round.
	var shape: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/rooms/crypt/arena_04.shape.json"))
	var centre: Vector2 = Vector2((shape["pits"][0]["centre"] as Array)[0], (shape["pits"][0]["centre"] as Array)[1])
	var round: float = float(shape["keep_clear_round"])
	var cracks: int = 0
	for crack: Dictionary in shape.get("cracks", []):
		if not crack.has("pit"):
			continue
		cracks += 1
		var way: Vector2 = Vector2.RIGHT.rotated(float(crack["angle"]) * TAU)
		for foot in _pillar_feet():
			var along: float = clampf((foot - centre).dot(way), 0.0, CRACK_HEAD)
			check(foot.distance_to(centre + way * along) >= round, "the crack at %.2f turns runs out between the pillars, clear of %s" % [float(crack["angle"]), foot])
	check_equal(cracks, 2, "two cracks run out of the pit")


## `Enemy1` stood where the pit is: it moved out of the ring ("The rooms"), and no enemy starts in it.
func test_no_enemy_starts_in_the_ring() -> void:
	var ring: Rect2 = _ring(_pillar_feet())
	for point in (RoomData as RoomBase).places().enemy_spawns:
		check(not ring.has_point(point), "the enemy spawn %s stands outside the ring %s" % [point, ring])


## The shaft of light falls into the pit, lighting the floor round it.
func test_the_shaft_falls_into_the_pit() -> void:
	var beam: Node2D = room_root.get_node_or_null("Decor/Beam") as Node2D
	check(beam != null, "the shaft of light")
	if beam == null:
		return
	var pit: Rect2 = _pit(RoomPlaces.hole_rects(room_root))
	check(pit.has_point(beam.position), "it falls into the pit: %s in %s" % [beam.position, pit])
	check(beam.get_node("Light").is_in_group(&"light_spot"), "it lights the floor")


## The four sarcophagi: each a low wall of the room's own `Walls`, drawn by a sprite of the sarcophagus
## art of its box's size, with a lit candle cluster at each end (on the floor, never over it).
func test_its_four_sarcophagi_have_candles_beside_them() -> void:
	var walls: Array[Rect2] = RoomScan.wall_rects(room_root)
	var boxes: Array[Rect2] = []
	for child in room_root.get_node("Walls").get_children():
		var sprite: Sprite2D = child as Sprite2D
		if sprite == null or sprite.texture != Sarcophagus:
			continue
		var box: Rect2 = RoomScan.sprite_rect(sprite)
		check(walls.has(box), "%s is a wall of its sprite's size: %s" % [child.name, box])
		boxes.append(box)
	check_equal(boxes.size(), 4, "four sarcophagi")
	for box in boxes:
		var ends: Dictionary[bool, int] = {true: 0, false: 0}
		for child in room_root.get_node("Decor").get_children():
			var light: Node2D = child.get_node_or_null("Light") as Node2D
			if not String(child.name).begins_with("Candles") or light == null:
				continue
			var at: Vector2 = (child as Node2D).position + light.position
			if box.grow(40.0).has_point(at):
				check(not box.has_point(at), "%s stands beside the sarcophagus %s, not on it" % [child.name, box])
				check(light.is_in_group(&"light_spot"), "%s lights the floor" % child.name)
				ends[at.x < box.get_center().x] += 1
		check(ends[true] >= 1 and ends[false] >= 1, "candles burn at each end of the sarcophagus %s (%s)" % [box, ends])


## The box round every hole: the pit and the wide part of its cracks.
func _pit(holes: Array[Rect2]) -> Rect2:
	if holes.is_empty():
		return Rect2()
	var box: Rect2 = holes[0]
	for hole in holes:
		box = box.merge(hole)
	return box


## The feet of the room's `crypt_pillar` props: the ring.
func _pillar_feet() -> PackedVector2Array:
	var places: RoomPlaces = (RoomData as RoomBase).places()
	var feet: PackedVector2Array = PackedVector2Array()
	for i in places.of_kind(PropBase):
		if (places.placed[i] as PropBase).id == &"crypt_pillar":
			feet.append(places.placed_at[i])
	return feet


## The box the ring's feet span.
func _ring(feet: PackedVector2Array) -> Rect2:
	if feet.is_empty():
		return Rect2()
	var ring: Rect2 = Rect2(feet[0], Vector2.ZERO)
	for at in feet:
		ring = ring.expand(at)
	return ring
