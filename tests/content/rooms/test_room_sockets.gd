extends "res://tests/support/suite.gd"
## Templates as a biome lays them (connected biomes CB2, docs/milestones/connected-biomes.md, "Every
## template is read by tests in all four mirrorings"): every room template the registry finds with
## sockets, and every walkway, keeps the 32 px rule, has its sockets on the lip and every socket
## reaching every other (`PieceShape.problems`) in all four mirrorings; a walkway has two sockets on
## its edge; a socket is read from its scene and taken out with the placements; mirroring moves
## sockets, walls and holes in whole cells and turns the sockets' facings.
const RegistryScript := preload("res://core/registry/registry.gd")

var _registry: RegistryScript = null


func before_each() -> void:
	super.before_each()
	_registry = own(RegistryScript.new()) as RegistryScript
	_registry.scan()


func _templates() -> Array[RoomBase]:
	var found: Array[RoomBase] = []
	for item: Resource in _registry.get_all(&"rooms"):
		var room := item as RoomBase
		if room != null and (room.walkway or not room.places().socket_at.is_empty()):
			found.append(room)
	return found


func test_every_template_with_sockets_keeps_the_rules_in_all_four_mirrorings() -> void:
	var rooms: Array[RoomBase] = _templates()
	check(rooms.size() >= 4, "the crypt's three socketed rooms and its bridge are found: %d" % rooms.size())
	for room: RoomBase in rooms:
		var shape: PieceShape = PieceShape.of_room(room)
		check(shape != null, "%s has a shape" % room.id)
		if shape == null:
			continue
		for mirror: int in PieceShape.MIRRORINGS:
			check_equal(shape.mirrored(mirror).problems(), PackedStringArray(), "%s mirrored %d keeps the rules" % [room.id, mirror])


func test_a_walkway_has_two_sockets_on_its_ends_and_hosts_no_room_kind() -> void:
	var found: int = 0
	for room: RoomBase in _templates():
		if not room.walkway:
			continue
		found += 1
		var shape: PieceShape = PieceShape.of_room(room)
		check_equal(shape.sockets(), 2, "%s has a socket at each end" % room.id)
		check(room.kinds.is_empty(), "%s hosts no room kind: it is no room of a run's map" % room.id)
		check(shape.cut_rect(0) == Rect2(), "%s is not cut where it is joined" % room.id)
		check_equal(shape.mouth_rect(0).size, Vector2(PieceShape.MOUTH_DEPTH, RoomSocket.MOUTH), "its mouth is a cell deep and a mouth wide")
	check(found >= 1, "the crypt's bridge is a walkway")


func test_a_room_off_the_grid_or_with_a_socket_off_its_lip_breaks_the_rules() -> void:
	var shape := PieceShape.new()
	shape.id = &"test"
	shape.size = Vector2(320.0, 200.0)
	check(not shape.problems().is_empty(), "a size off the 32 px grid is named")
	shape.size = Vector2(320.0, 192.0)
	# A slab: walls round its edge, 32 px deep.
	shape.walls = [Rect2(0.0, 0.0, 320.0, 32.0), Rect2(0.0, 160.0, 320.0, 32.0), Rect2(0.0, 0.0, 32.0, 192.0), Rect2(288.0, 0.0, 32.0, 192.0)] as Array[Rect2]
	shape.socket_at = PackedVector2Array([Vector2(288.0, 96.0)])
	shape.socket_facing = PackedInt32Array([RoomSocket.Facing.EAST])
	check_equal(shape.problems(), PackedStringArray(), "a socket on the lip, facing out: sound")
	shape.socket_at[0] = Vector2(290.0, 96.0)
	check(" off the 32 px grid" in "".join(shape.problems()), "off the grid is named")
	shape.socket_at[0] = Vector2(256.0, 96.0)
	check("open floor for" in "".join(shape.problems()), "a socket inside the slab, not on its lip, is named")
	shape.socket_at[0] = Vector2(320.0, 96.0)
	check("landing" in "".join(shape.problems()), "a socket with the lip's wall on its landing is named")
	shape.socket_at = PackedVector2Array([Vector2(288.0, 96.0), Vector2(32.0, 96.0)])
	shape.socket_facing = PackedInt32Array([RoomSocket.Facing.EAST, RoomSocket.Facing.WEST])
	shape.walls.append(Rect2(160.0, 0.0, 32.0, 192.0))
	check("cannot be walked to" in "".join(shape.problems()), "a socket cut off from the others is named")


func test_mirroring_moves_sockets_walls_and_holes_in_whole_cells() -> void:
	var shape := PieceShape.new()
	shape.size = Vector2(640.0, 384.0)
	shape.walls = [Rect2(608.0, 64.0, 32.0, 96.0)] as Array[Rect2]
	shape.holes = [Rect2(64.0, 320.0, 64.0, 32.0)] as Array[Rect2]
	shape.socket_at = PackedVector2Array([Vector2(608.0, 192.0), Vector2(320.0, 32.0)])
	shape.socket_facing = PackedInt32Array([RoomSocket.Facing.EAST, RoomSocket.Facing.NORTH])
	var across: PieceShape = shape.mirrored(PieceShape.MIRROR_X)
	check_equal(across.walls[0], Rect2(0.0, 64.0, 32.0, 96.0), "a wall mirrored across")
	check_equal(across.holes[0], Rect2(512.0, 320.0, 64.0, 32.0), "a hole mirrored across")
	check_equal(across.socket_at[0], Vector2(32.0, 192.0), "a socket mirrored across")
	check_equal(across.socket_facing[0], RoomSocket.Facing.WEST, "east turns west")
	check_equal(across.socket_facing[1], RoomSocket.Facing.NORTH, "north stays north across")
	var both: PieceShape = shape.mirrored(PieceShape.MIRROR_X | PieceShape.MIRROR_Y)
	check_equal(both.walls[0], Rect2(0.0, 224.0, 32.0, 96.0), "both ways")
	check_equal(both.socket_facing[1], RoomSocket.Facing.SOUTH, "north turns south up and down")
	check_equal(both.mirrored(PieceShape.MIRROR_X | PieceShape.MIRROR_Y).walls[0], shape.walls[0], "mirrored twice is itself")
	check_equal(both.mirror, PieceShape.MIRROR_X | PieceShape.MIRROR_Y, "it knows its mirroring")
	check_equal(shape.cut_rect(0), Rect2(592.0, 160.0, 48.0, 64.0), "a room's cut runs from its landing to its edge, a mouth wide")
	check_equal(shape.mouth_rect(0), Rect2(608.0, 160.0, 8.0, 64.0), "its mouth one cell out from the socket")


func test_a_socket_is_read_from_its_scene_and_taken_out_before_play() -> void:
	var room := _registry.get_resource(&"rooms", &"arena_02") as RoomBase
	var places: RoomPlaces = room.places()
	check_equal(places.socket_at.size(), 2, "the nave's two sockets are read")
	check_equal(places.problems(), PackedStringArray(), "its places are sound")
	var layout: Node = own(room.build())
	RoomPlaces.strip(layout)
	check(layout.find_children("*", "RoomSocket", true, false).is_empty(), "no socket is left in the room the game shows")


## The editor's preview (`SocketPreview`, tools/) reads the scene it is in as a biome would and finds
## its sockets sound; a socket moved off the grid is drawn as broken.
func test_the_socket_preview_reads_its_scene() -> void:
	for id: StringName in [&"arena_02", &"crypt_bridge"]:
		var layout: Node = (_registry.get_resource(&"rooms", id) as RoomBase).build()
		root.add_child(layout)
		var preview := layout.get_node("SocketPreview") as SocketPreview
		check(preview != null and preview.shape != null, "%s has a socket preview that looked" % id)
		if preview == null or preview.shape == null:
			layout.free()
			continue
		check_equal(preview.shape.sockets(), 2, "%s: both sockets read" % id)
		check_equal(preview.broken, PackedInt32Array(), "%s: none broken" % id)
		check_equal(preview.shape.walkway, id == &"crypt_bridge", "%s: a walkway only for the bridge" % id)
		(layout.get_node("Sockets").get_child(0) as Node2D).position += Vector2(8.0, 0.0)
		preview.mirror = PieceShape.MIRROR_Y
		check_equal(preview.broken, PackedInt32Array([0]), "%s: a socket moved off the grid is broken" % id)
		layout.free()
