extends "res://tests/support/suite.gd"
## Every room's places (props W8a/W8b/W8c, docs/milestones/props.md): found by folder, so a new room
## is checked too. Its places are sound (`RoomPlaces.problems`: every placement has its data, every
## zone its name, places are whole translations); a prop's stand-in (`PropStandIn`, the editor's)
## draws its look as the game's body does (`PropLook`), state by state, so the editor never lies;
## and the room the game shows has no placement or zone left (`RoomPlaces.strip`).
##
## godot --headless --path . --script res://tests/content/rooms/test_room_places.gd

const RegistryScript := preload("res://core/registry/registry.gd")
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const FlowScript := preload("res://gameplay/flow/flow.gd")

var _registry: RegistryScript
var _world: Fixture


func before_each() -> void:
	_registry = own(RegistryScript.new()) as RegistryScript
	_registry.scan()
	_world = Fixture.new(root)


func after_each() -> void:
	_world.free_all()


func _rooms() -> Array[RoomBase]:
	var found: Array[RoomBase] = []
	for item: Resource in _registry.get_all(&"rooms"):
		if item is RoomBase:
			found.append(item as RoomBase)
	return found


func test_every_rooms_places_are_sound() -> void:
	check(_rooms().size() >= 3, "the rooms are found")
	for room in _rooms():
		check_equal(room.places().problems(), PackedStringArray(), "%s: its places are sound" % room.id)


## What the editor draws for a prop (its stand-in's sprites) is what the game draws (its body's
## look's sprites), in every state: picture, frames, place, depth, shown.
func test_a_props_stand_in_draws_what_the_game_draws() -> void:
	var props: Array[PropBase] = []
	for room in _rooms():
		for data: PropBase in room.places().placed_of(PropBase):
			if not props.has(data):
				props.append(data)
	# And every prop of the game's, placed in a room or not (the yard's stand where Flow puts them).
	for data: Resource in _registry.get_all(&"props"):
		if not props.has(data):
			props.append(data as PropBase)
	for data in props:
		for state in data.states.list:
			var stand_in := own(PropStandIn.new()) as PropStandIn
			stand_in.prop = data
			stand_in.state = state.state_id
			stand_in.show_look()
			var body: Actor = _world.add(PropBody.make(data), Vector2(100, 100))
			if state != data.states.list[0]:
				body.state_triggers.enter(state.state_id)
			var drawn: Array[Sprite2D] = []
			for child in [body.get_node("Sprite")] + body.get_node("PropLook").get_children():
				if child is Sprite2D and not child.is_queued_for_deletion():
					drawn.append(child as Sprite2D)
			var shown: Array[Sprite2D] = stand_in.look_sprites()
			var where: String = "%s, %s" % [data.id, state.state_id]
			check_equal(shown.size(), drawn.size(), "%s: as many pictures" % where)
			for i in mini(shown.size(), drawn.size()):
				check_equal(shown[i].texture, drawn[i].texture, "%s, layer %d: the picture" % [where, i])
				check_equal(shown[i].hframes, drawn[i].hframes, "%s, layer %d: its frames" % [where, i])
				check_equal(shown[i].position + shown[i].offset, drawn[i].position + drawn[i].offset, "%s, layer %d: where" % [where, i])
				check_equal(shown[i].z_index, drawn[i].z_index, "%s, layer %d: its depth" % [where, i])
				check_equal(shown[i].visible, drawn[i].visible, "%s, layer %d: shown" % [where, i])


func test_the_room_the_game_shows_has_no_placements_or_zones() -> void:
	for room in _rooms():
		var layout: Node = own(room.build())
		RoomPlaces.strip(layout)
		check(layout.find_children("*", "RoomPlacement", true, false).is_empty(), "%s: no placement left" % room.id)
		check(layout.find_children("*", "RoomZone", true, false).is_empty(), "%s: no zone left" % room.id)


## A cover field (ground cover GC2) is a zone with data: read with its rectangle and its patch, by
## kind (`zones_of`), with no name and no problem; a plain zone with no name is still one; a plain
## zone's data is null; and the game's room has no field left (`strip`).
func test_a_cover_field_is_read_with_its_data_and_taken_out() -> void:
	var layout := own(Node2D.new()) as Node2D
	var zones := Node2D.new()
	zones.position = Vector2(10, 20)
	layout.add_child(zones)
	var plain := RoomZone.new()
	plain.zone_name = &"prop_yard"
	plain.offset_right = 30
	plain.offset_bottom = 30
	zones.add_child(plain)
	var field := CoverField.new()
	field.kind = &"grass"
	field.density = 0.4
	field.offset_left = 5
	field.offset_top = 6
	field.offset_right = 105
	field.offset_bottom = 56
	zones.add_child(field)
	var places: RoomPlaces = RoomPlaces.read(layout)
	check_equal(places.problems(), PackedStringArray(), "a field needs no name")
	check_equal(places.zone_names.size(), 2, "both zones read")
	check(places.zone_data[0] == null, "a plain zone holds no data")
	check_equal(places.zones_of(CoverPatch), PackedInt32Array([1]), "the field, by its data's kind")
	var patch := places.zone_data[1] as CoverPatch
	check(patch != null and patch.kind == &"grass" and is_equal_approx(patch.density, 0.4), "its kind and density")
	check_equal(places.zone_rects[1], Rect2(15, 26, 100, 50), "its rectangle, through its holder")
	check_equal(places.zone(&""), Rect2(), "no zone is found by no name")
	check_equal(places.zone(&"prop_yard"), Rect2(10, 20, 30, 30), "a named zone still is")
	zones.add_child(RoomZone.new())
	check_equal(RoomPlaces.read(layout).problems().size(), 1, "a plain zone with no name is a problem")
	RoomPlaces.strip(layout)
	check(layout.find_children("*", "RoomZone", true, false).is_empty(), "the fields taken out with the zones")


## Every room's cover, with the game's cover kinds, has no problems (a field naming a kind there is
## none of), and the fill is on unless a room turns it off.
func test_every_rooms_cover_is_sound() -> void:
	var kinds: Array[CoverKind] = []
	for item: Resource in _registry.get_all(&"cover"):
		if item is CoverKind:
			kinds.append(item as CoverKind)
	check(RoomBase.new().cover_fill, "the fill is on by default")
	for room in _rooms():
		var layout: Node = own(room.build())
		check_equal(CoverLayout.of(layout, room, kinds).problems(), PackedStringArray(), "%s: its cover is sound" % room.id)


## A static body in `layout` on `layer` at `at`, with one rectangle `size` across from its corner.
func _body_rect(layout: Node, layer: int, at: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = layer
	body.position = at
	layout.add_child(body)
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = size
	shape.shape = box
	shape.position = size * 0.5
	body.add_child(shape)


func test_a_rooms_holes_are_read_apart_from_its_walls_and_count_in_its_size() -> void:
	# Hub rework HR-H1: a body exactly on the hole layer is a hole; one on the wall layer (even with
	# the hole layer too) is a wall; a hole past every wall makes the room that big.
	var layout := own(Node2D.new()) as Node2D
	_body_rect(layout, RoomBase.WALL_LAYER, Vector2(0.0, 0.0), Vector2(640.0, 16.0))
	_body_rect(layout, RoomBase.HOLE_LAYER, Vector2(200.0, 16.0), Vector2(32.0, 344.0))
	_body_rect(layout, RoomBase.HOLE_LAYER, Vector2(640.0, 0.0), Vector2(160.0, 480.0))
	_body_rect(layout, RoomBase.WALL_LAYER | RoomBase.HOLE_LAYER, Vector2(300.0, 100.0), Vector2(8.0, 8.0))
	check_equal(RoomPlaces.hole_rects(layout), [Rect2(200.0, 16.0, 32.0, 344.0), Rect2(640.0, 0.0, 160.0, 480.0)] as Array[Rect2], "the holes, in the tree's order")
	check_equal(RoomPlaces.wall_rects(layout), [Rect2(0.0, 0.0, 640.0, 16.0), Rect2(300.0, 100.0, 8.0, 8.0)] as Array[Rect2], "the walls, a body on both layers among them")
	check_equal(RoomPlaces.read(layout).size, Vector2(800.0, 480.0), "the room reaches the far hole's corner")


func test_flow_hands_a_rooms_holes_to_the_projectile_manager() -> void:
	var world := Node2D.new()
	_body_rect(world, RoomBase.WALL_LAYER, Vector2(0.0, 0.0), Vector2(64.0, 8.0))
	_body_rect(world, RoomBase.HOLE_LAYER, Vector2(200.0, 0.0), Vector2(32.0, 64.0))
	root.add_child(world)
	var flow := own(FlowScript.new()) as FlowScript
	flow.projectiles = _world.projectiles
	_world.projectiles.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	flow._set_walls(world)
	check(_world.projectiles.is_hole(Vector2(216.0, 32.0)), "the hole body is a hole")
	check(not _world.projectiles.is_hole(Vector2(32.0, 4.0)) and not _world.projectiles.line_clear(Vector2(32.0, 20.0), Vector2(32.0, 0.0)), "the wall body is a wall")
	world.free()
