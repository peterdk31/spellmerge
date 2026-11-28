extends "res://tests/support/suite.gd"
## Feel's rooms sort the bodies found to the views whose cells they can walk (perf plan F3,
## gameplay/feel/cover_reach.gd): each view walks only its own, and every view's grid of walked cells
## is the one it was when every view walked every body found (`step_with`'s walk), frame by frame,
## shown or switched off, with bodies on the walk boxes' very edges and the buckets' borders; and a
## frame of it allocates nothing.
const CoverScript := preload("res://gameplay/feel/cover.gd")
const CoverRoomsScript := preload("res://gameplay/feel/cover_rooms.gd")
const CoverReachScript := preload("res://gameplay/feel/cover_reach.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
var fixture_grass: CoverKind = preload("res://tests/core/fixtures/cover_content/cover/test_grass/test_grass.tres")

## Rooms 640×384 laid side by side with a gap, three a row, a field of grass in each.
const ROOMS: int = 7
const FIELD := Rect2(160, 96, 320, 192)


func _grass() -> CoverKind:
	var kind := fixture_grass.duplicate(true) as CoverKind
	kind.biomes = [] as Array[StringName]
	var image := Image.create_empty(16 * 7, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.5, 0.2))
	kind.sheet = ImageTexture.create_from_image(image)
	return kind


## Room `number`'s layout, at its place (a row of three; the second row starts on a bucket's border).
func _layout(kind: CoverKind, number: int) -> CoverLayout:
	var node := own(Node2D.new()) as Node2D
	var field := CoverField.new()
	field.kind = kind.id
	field.density = 1.0
	field.offset_left = FIELD.position.x
	field.offset_top = FIELD.position.y
	field.offset_right = FIELD.end.x
	field.offset_bottom = FIELD.end.y
	node.add_child(field)
	var room := RoomBase.new()
	room.id = &"meadow"
	var laid: CoverLayout = CoverLayout.of(node, room, [kind] as Array[CoverKind])
	laid.origin = Vector2(float((number % 3) * 700), float((number / 3) * 512))
	return laid


func _table(places: PackedVector2Array) -> ActorsScript:
	var table := own(ActorsScript.new()) as ActorsScript
	for at in places:
		var body := own(Node2D.new()) as Node2D
		root.add_child(body)
		body.global_position = at
		var id: int = table.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
		table.set_node(id, body)
	return table


## Places for 32 bodies in frame `frame`: on cover, off it, on the walk boxes' very edges (a body a
## pixel either side of where its footprint may touch a cell), on the buckets' borders.
func _places(views: Array[CoverScript], frame: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	var places := PackedVector2Array()
	for n in CoverScript.BODIES:
		var view: CoverScript = views[(n + frame) % views.size()]
		var low: Vector2 = view.walk_low()
		var high: Vector2 = view.walk_high()
		match (n + frame) % 4:
			0:
				places.append(Vector2(rng.randf_range(low.x, high.x), rng.randf_range(low.y, high.y)))
			1:
				places.append(Vector2(low.x, rng.randf_range(low.y, high.y)) if n % 2 == 0 else Vector2(rng.randf_range(low.x, high.x), high.y))
			2:
				places.append(Vector2(high.x + 0.01, low.y) if n % 2 == 0 else Vector2(low.x - 0.01, high.y))
			_:
				places.append(Vector2(float(rng.randi_range(0, 4)) * CoverReachScript.BUCKET, rng.randf_range(-100.0, 1200.0)))
	return places


func test_each_room_walks_the_cells_every_body_found_walked() -> void:
	var kind: CoverKind = _grass()
	var rooms: CoverRoomsScript = own(CoverRoomsScript.new(0)) as CoverRoomsScript
	root.add_child(rooms)
	var twins: Array[CoverScript] = []
	for number in ROOMS:
		if number > 0:
			rooms._views.append(rooms._view(number))
		rooms.view_of(number).lay(_layout(kind, number))
		var twin: CoverScript = own(CoverScript.new(0)) as CoverScript
		root.add_child(twin)
		twin.lay(_layout(kind, number))
		twins.append(twin)
	var views: Array[CoverScript] = []
	for number in ROOMS:
		views.append(rooms.view_of(number))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var table: ActorsScript = _table(_places(views, 0, rng))
	var ids := PackedInt32Array()
	ids.resize(64)
	var walked: int = 0
	for frame in 12:
		var places: PackedVector2Array = _places(views, frame, rng)
		var open: int = table.open_ids(ids)
		for n in open:
			(table.node_of(ids[n]) as Node2D).global_position = places[n]
		# Some rooms switched off, the same in both.
		for number in ROOMS:
			var shown: bool = (number + frame) % 3 != 0
			views[number].visible = shown
			twins[number].visible = shown
		# A room laid again mid-run, at another place (as a new world lays its pieces): the reach is
		# worked out again (`flats_version`).
		if frame == 6:
			var moved: CoverLayout = _layout(kind, 3)
			moved.origin += Vector2(256.0, 40.0)
			views[3].lay(moved)
			var twin_moved: CoverLayout = _layout(kind, 3)
			twin_moved.origin += Vector2(256.0, 40.0)
			twins[3].lay(twin_moved)
		var now: float = 1.0 + 0.1 * float(frame)
		rooms.step(now, table, Vector2.INF)
		for number in ROOMS:
			check_equal(views[number]._walk_count, -1, "frame %d: room %d let its bodies go" % [frame, number])
		var lead: CoverScript = twins[0]
		lead.step(now, table, Vector2.INF)
		for number in range(1, ROOMS):
			twins[number].step_with(lead.bodies(), lead.body_count(), now, null, Rect2(), -1, Callable(), lead.found_box())
		for number in ROOMS:
			check_equal(views[number]._times.get_data(), twins[number]._times.get_data(), "frame %d: room %d's walked cells as every body walked them" % [frame, number])
			for cell in views[number].layout.cells.size():
				if views[number].walked_at(cell) == now:
					walked += 1
	check(walked > 20, "while bodies walked cells (%d)" % walked)
	# The sorted bodies: every one inside each view's walk box, and no other.
	var reach: CoverReachScript = rooms._reach
	var found: PackedVector2Array = views[0].found_bodies()
	for number in ROOMS:
		var expected: int = 0
		for at in views[0].found_count():
			var body: Vector2 = found[at]
			var low: Vector2 = views[number].walk_low()
			var high: Vector2 = views[number].walk_high()
			if not (body.x < low.x or body.y < low.y or body.x > high.x or body.y > high.y):
				check_equal(reach.bodies[number * CoverScript.BODIES + expected], body, "room %d: the bodies in their order found" % number)
				expected += 1
		check_equal(reach.counts[number], expected, "room %d: every body in its walk box" % number)


func test_a_frame_of_the_sort_allocates_nothing() -> void:
	var kind: CoverKind = _grass()
	var rooms: CoverRoomsScript = own(CoverRoomsScript.new(0)) as CoverRoomsScript
	root.add_child(rooms)
	var views: Array[CoverScript] = []
	for number in ROOMS:
		if number > 0:
			rooms._views.append(rooms._view(number))
		rooms.view_of(number).lay(_layout(kind, number))
		views.append(rooms.view_of(number))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var table: ActorsScript = _table(_places(views, 0, rng))
	for frame in 3:
		rooms.step(1.0 + 0.1 * float(frame), table, Vector2.INF)
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for frame in 100:
		rooms.step(2.0 + 0.1 * float(frame), table, Vector2.INF)
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "100 frames of seven rooms make no object")
