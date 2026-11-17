extends "res://tests/support/suite.gd"
## The broom's hall (content/rooms/crypt/boss_broom, crypt rework CR7, docs/milestones/
## crypt-rework.md, "The rooms"): its test lives in the boss's folder, as the hall is the boss's
## (boss plan decision 28: deleting the boss deletes both). A floating room drawn from its shape, its
## four pillars `crypt_pillar` props and no gate (cleared, the run is won); no pit (a boss never
## falls); its landmark the swept ring: its ground's areas `dust` over the whole hall, then `swept`
## (clean stone with the strokes of a broom) round its middle, the pillars standing in the ring and
## everything pushed out of it (the dust heaps, the rubble and the skulls lie in the drifts round it);
## the crypt's shaft of light on its middle; and lit by candles where its ten wall torches hung.

const HallData := preload("res://content/rooms/crypt/boss_broom/boss_broom.tres")
## Its shape (tools/ground_shape.py draws its ground from it) and the swept ring's material.
const Shape := preload("res://content/rooms/crypt/boss_broom/boss_broom.shape.json")
const Swept := preload("res://content/grounds/swept/ground.json")
const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const Beam := preload("res://content/rooms/decor/beam.tscn")
const Candles := preload("res://content/rooms/crypt/decals/candles.tscn")
const Torch := preload("res://content/rooms/crypt/decals/torch.tscn")
const Rubble := preload("res://art/tilesets/crypt/rubble.svg")
const Skull := preload("res://art/tilesets/crypt/skull.svg")

## How near the room's middle the ring's centre and the shaft stand.
const MIDDLE: float = 24.0
## The candle clusters lighting the hall, one where each of its ten wall torches hung.
const CANDLES: int = 10

var halls: Array[RoomBase] = []
## Every cover kind of the game (content/cover), for the ring's cover.
var kinds: Array[CoverKind] = []


func before_each() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	kinds.clear()
	for item: Resource in registry.get_all(&"cover"):
		if item is CoverKind:
			kinds.append(item as CoverKind)
	halls.clear()
	halls.append(HallData as RoomBase)


func test_it_is_a_crypt_boss_room_drawn_from_its_shape() -> void:
	var room: RoomBase = HallData
	check_equal(room.id, &"boss_broom", "the id")
	check(room.biome == &"crypt" and room.hosts(&"boss"), "the crypt's boss room")
	check(Shape is JSON and (Shape as JSON).data is Dictionary, "drawn from its shape")


func test_a_hall_is_a_floating_room_with_no_gate_and_no_pit() -> void:
	for room in halls:
		var root: Node = own(room.scene.instantiate()) as Node
		check_equal(RoomScan.floating_room_problems(room, root, 4, 0), PackedStringArray(), "%s: a floating room with its four pillars, leading nowhere" % room.id)
		check(RoomPlaces.hole_rects(root).is_empty(), "%s: no pit, a boss never falls" % room.id)


## The ring: the shape's areas end with `dust` over the whole hall (every corner of the room inside
## it), then `swept` round the room's middle, inside the dust; the swept material draws a broom's
## strokes; every pillar stands in the ring, and every dust heap, rubble and skull lies outside it, and
## no cover grows in it (the crypt's cobwebs fill the hall, and its own fields clear the ring).
func test_its_landmark_is_the_swept_ring() -> void:
	for room in halls:
		var root: Node = own(room.scene.instantiate()) as Node
		var shape: Dictionary = (Shape as JSON).data
		var areas: Array = shape.get("areas", [])
		check(areas.size() >= 2, "%s: dust, then the swept ring" % room.id)
		if areas.size() < 2:
			continue
		var dust: Dictionary = areas[areas.size() - 2]
		var ring: Dictionary = areas[areas.size() - 1]
		check_equal(dust.get("ground"), "dust", "%s: dust over the hall" % room.id)
		check_equal(ring.get("ground"), "swept", "%s: then the swept ring" % room.id)
		var size: Vector2 = room.places().size
		for corner: Vector2 in [Vector2.ZERO, Vector2(size.x, 0.0), Vector2(0.0, size.y), size]:
			check(_reach(dust, corner) < 1.0 - _rough(dust), "%s: the dust lies over the whole hall, %s too" % [room.id, corner])
		check(_centre(ring).distance_to(size * 0.5) <= MIDDLE, "%s: the ring is swept round the middle" % room.id)
		var radii: Vector2 = _radii(ring) * (1.0 + _rough(ring))
		var centre: Vector2 = _centre(ring)
		for corner: Vector2 in [centre - radii, centre + radii, centre + Vector2(radii.x, -radii.y), centre + Vector2(-radii.x, radii.y)]:
			check(_reach(dust, corner) < 1.0 - _rough(dust), "%s: the ring lies inside the dust" % room.id)
		var swept: Dictionary = (Swept as JSON).data
		check(swept.has("strokes"), "the swept stone keeps a broom's strokes")
		var places: RoomPlaces = room.places()
		var heaps: int = 0
		for i in places.of_kind(PropBase):
			var prop: PropBase = places.placed[i] as PropBase
			var at: Vector2 = places.placed_at[i]
			if prop.id == &"crypt_pillar":
				check(_reach(ring, at) < 1.0 - _rough(ring), "%s: the pillar at %s stands in the ring" % [room.id, at])
			elif prop.id == &"dust_heap":
				heaps += 1
				check(_reach(ring, at) > 1.0 + _rough(ring), "%s: the dust heap at %s lies in the drift round the ring" % [room.id, at])
		check(heaps >= 1, "%s: dust heaps stand in its drifts" % room.id)
		for child in root.get_node("Decor").get_children():
			var sprite: Sprite2D = child as Sprite2D
			if sprite == null or not (sprite.texture == Rubble or sprite.texture == Skull):
				continue
			var middle: Vector2 = RoomScan.sprite_rect(sprite).get_center()
			check(_reach(ring, middle) > 1.0 + _rough(ring), "%s: %s at %s is swept out of the ring" % [room.id, child.name, middle])
		var cover: CoverLayout = CoverLayout.of(own(room.build()), room, kinds)
		for cell in cover.cells.size():
			var at: Vector2 = cover.cell_rect(cell).get_center()
			if cover.cells[cell] != 0 and _reach(ring, at) < 1.0 - _rough(ring):
				check(false, "%s: the ring is swept, yet %s grows at %s" % [room.id, cover.kind_at(cell).id, at])


## The crypt's shaft of light (the shared beam) falls on the middle of the ring, lighting the floor.
func test_the_shaft_falls_on_its_middle() -> void:
	for room in halls:
		var root: Node = own(room.scene.instantiate()) as Node
		var beam: Node2D = root.get_node_or_null("Decor/Beam") as Node2D
		check(beam != null, "%s: a shaft of light" % room.id)
		if beam == null:
			continue
		check(beam.position.distance_to(room.places().size * 0.5) <= MIDDLE, "%s: on its middle: %s" % [room.id, beam.position])
		check_equal(beam.scene_file_path, Beam.resource_path, "%s: the crypt's shaft of light" % room.id)
		check(beam.get_node("Light").is_in_group(&"light_spot"), "%s: it lights the floor" % room.id)


## Lit as a floating room is: by candle clusters standing on the slab (no wall to hang a torch on),
## each lighting the floor.
func test_it_is_lit_by_candles() -> void:
	for room in halls:
		var root: Node = own(room.scene.instantiate()) as Node
		var candles: int = 0
		for child in root.get_node("Decor").get_children():
			if child.scene_file_path == Candles.resource_path:
				candles += 1
				check((child.get_node("Light") as Node).is_in_group(&"light_spot"), "%s: %s lights the floor" % [room.id, child.name])
			check(child.scene_file_path != Torch.resource_path, "%s: no wall torch, %s" % [room.id, child.name])
		check(candles >= CANDLES, "%s: lit by candles (%d)" % [room.id, candles])


func _centre(area: Dictionary) -> Vector2:
	return Vector2(float(area["centre"][0]), float(area["centre"][1]))


func _radii(area: Dictionary) -> Vector2:
	return Vector2(float(area["radii"][0]), float(area["radii"][1]))


## How far out on an area's oval `point` lies: under 1 inside its plain oval, over 1 outside.
func _reach(area: Dictionary, point: Vector2) -> float:
	var d: Vector2 = (point - _centre(area)) / _radii(area)
	return d.length()


## The most an area's outline strays off its plain oval, as a share of its radius: its waves and its
## rough together (tools/ground_shape.py, `outline_points`).
func _rough(area: Dictionary) -> float:
	var most: float = 0.0
	for wave: Array in area.get("waves", []):
		most += absf(float(wave[1]))
	for rough: Array in area.get("rough", []):
		most += absf(float(rough[1]))
	return most
