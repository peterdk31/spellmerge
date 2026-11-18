extends "res://tests/support/suite.gd"
## The Voronoi split's views (connected biomes CB6, gameplay/feel/split_camera.gd; decision 27):
## one picture while everyone fits; past that a view a group of wizards, the cells covering the
## screen, each holding its own wizards; a split starts as the picture it splits from and a merge
## ends on it, so nothing jumps but the divider, which grows and shrinks a pixel a drawn frame.
## With 1 to 4 seats in the rooms of a biome (the hand-made twelve-room row, tests/support/biome_maps.gd),
## the world's camera driven by the party camera as in the game.
const SplitCameraScript := preload("res://gameplay/feel/split_camera.gd")
const PartyCameraScript := preload("res://gameplay/feel/party_camera.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")

const SCREEN := Vector2(640.0, 360.0)
## A drawn frame (real seconds).
const FRAME: float = 1.0 / 60.0

var _table: ActorsScript
var _holder: SubViewport
var _camera: Camera2D
var _party: PartyCameraScript
var _split: SplitCameraScript
var _bodies: Array[Node2D] = []
## The middles of the biome's rooms, west to east.
var _rooms: PackedVector2Array = PackedVector2Array()


func before_each() -> void:
	_table = own(ActorsScript.new()) as ActorsScript
	root.add_child(_table)
	# The world's camera in a viewport of its own the screen's size, so its picture is read as drawn.
	_holder = own(SubViewport.new()) as SubViewport
	_holder.size = Vector2i(SCREEN)
	_holder.disable_3d = true
	root.add_child(_holder)
	_camera = Camera2D.new()
	_holder.add_child(_camera)
	_camera.make_current()
	_party = PartyCameraScript.new()
	_party.follow(_camera)
	_split = SplitCameraScript.new()
	_bodies.clear()
	_rooms = _room_middles()


func _room_middles() -> PackedVector2Array:
	var out := PackedVector2Array()
	var registry: Object = root.get_node_or_null(^"Registry")
	if registry == null:
		return out
	var map: BiomeMap = BiomeMaps.twelve_rooms(registry)
	var bounds := Rect2()
	for room in map.rooms():
		var shape: PieceShape = BiomeMaps.shape(registry, map.room_templates[room]).mirrored(map.room_mirrors[room])
		var rect := Rect2(map.room_places[room], shape.size)
		bounds = rect if room == 0 else bounds.merge(rect)
		out.append(rect.get_center())
	# The camera keeps to the biome (CB3 moves the world camera's limits to the biome's bounds).
	_camera.limit_left = int(bounds.position.x)
	_camera.limit_top = int(bounds.position.y) - 400
	_camera.limit_right = int(bounds.end.x)
	_camera.limit_bottom = int(bounds.end.y) + 400
	return out


## Seat `seat`'s wizard at `at`.
func _wizard(seat: int, at: Vector2) -> Node2D:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.global_position = at
	var id: int = _table.open(ActorsScript.TEAM_WIZARDS, seat, seat)
	_table.set_node(id, node)
	_table.set_home(id, seat)
	_bodies.append(node)
	return node


## A drawn frame: the party camera, then the split, as Feel steps them.
func _frame(seats: int = 0) -> void:
	_party.look(_table, seats)
	_party.step(FRAME)
	_split.step(FRAME, _table, seats, _camera, SCREEN)


func _frames(count: int, seats: int = 0) -> void:
	for i in count:
		_frame(seats)


## The world camera's picture as drawn (its transform).
func _root_transform() -> Transform2D:
	return _holder.get_canvas_transform()


## How far two pictures are apart on screen (pixels), at the screen's corners.
static func _gap(a: Transform2D, b: Transform2D) -> float:
	var most: float = 0.0
	for corner: Vector2 in [Vector2.ZERO, Vector2(SCREEN.x, 0.0), SCREEN, Vector2(0.0, SCREEN.y)]:
		most = maxf(most, (a.affine_inverse() * corner).distance_to(b.affine_inverse() * corner) * a.x.x)
	return most


## The cells cover the screen without overlap: their areas add up to the screen's, and every point
## of a grid over it is in at least one cell (two only on a line between them).
func _check_cover(views: ScreenViewsScript, what: String) -> void:
	var total: float = 0.0
	for view in views.count:
		var cell := PackedVector2Array()
		for at in views.corners(view):
			cell.append(views.corner(view, at))
		total += _area(cell)
	check(absf(total - SCREEN.x * SCREEN.y) < 1.0, "%s: the cells' areas add up to the screen's (%.1f)" % [what, total])
	for y in range(5, int(SCREEN.y), 20):
		for x in range(5, int(SCREEN.x), 20):
			var p := Vector2(x, y) + Vector2(0.37, 0.21)
			var held: int = 0
			for view in views.count:
				if views.cell_holds(view, p, 0.0):
					held += 1
			if held != 1:
				check(false, "%s: the point %s is in %d cells" % [what, p, held])
				return


static func _area(polygon: PackedVector2Array) -> float:
	var twice: float = 0.0
	for i in polygon.size():
		twice += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return absf(twice) * 0.5


## Every wizard of view `view` is drawn inside its cell.
func _check_own_cells(views: ScreenViewsScript, what: String) -> void:
	for view in views.count:
		for seat in ActorsScript.SEATS:
			if views.seats[view] & (1 << seat) == 0:
				continue
			var body := _table.node_of(_table.home_of_seat(seat)) as Node2D
			var drawn: Vector2 = views.to_screen[view] * body.global_position
			check(views.cell_holds(view, drawn, 0.5), "%s: seat %d is drawn in its own view's cell (%s)" % [what, seat, drawn])


func test_one_wizard_never_splits() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	_wizard(0, _rooms[0])
	_frames(30)
	check_equal(_split.views.count, 0, "one wizard: one picture, no view")
	_bodies[0].global_position = _rooms[11]
	_frames(30)
	check_equal(_split.views.count, 0, "still one picture after walking to the far room")


func test_wizards_that_fit_share_the_one_picture() -> void:
	_wizard(0, _rooms[0])
	_wizard(1, _rooms[0] + Vector2(200.0, 40.0))
	_frames(30)
	check(not _split.split, "two wizards in one room fit: no split")
	check_equal(_split.views.count, 0, "and no view")


func test_two_to_four_seats_in_separate_rooms_split_into_cells_that_cover_the_screen() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	var places: Array[int] = [0, 4, 8, 11]
	for seats in range(2, 5):
		before_each()
		for seat in seats:
			_wizard(seat, _rooms[places[seat]])
		_frames(120)
		var views: ScreenViewsScript = _split.views
		check(_split.split, "%d seats in separate rooms split" % seats)
		check_equal(views.count, seats, "%d seats in separate rooms: a view each" % seats)
		_check_cover(views, "%d views" % seats)
		_check_own_cells(views, "%d views" % seats)
		for view in views.count:
			check_equal(_split.stage_of(view), SplitCameraScript.DIVIDER_WIDTH, "the divider has grown in")
			check(absf(views.to_screen[view].x.x - SplitCameraScript.SPLIT_ZOOM) < 0.01, "a split view eases to the split's zoom")
		_free_bodies()


func test_two_wizards_together_share_a_view_while_a_third_is_far() -> void:
	_wizard(0, _rooms[0])
	_wizard(1, _rooms[0] + Vector2(60.0, 0.0))
	_wizard(2, _rooms[9])
	_frames(120)
	var views: ScreenViewsScript = _split.views
	check_equal(views.count, 2, "the two together share a view, the third has its own")
	var pair: int = views.view_of_seat(0)
	check(pair >= 0 and pair == views.view_of_seat(1), "seats 0 and 1 are in one view")
	check(views.view_of_seat(2) != pair, "seat 2 in another")
	_check_cover(views, "the pair and one")
	_check_own_cells(views, "the pair and one")


func test_a_split_starts_as_the_picture_it_splits_from() -> void:
	var a: Node2D = _wizard(0, _rooms[3])
	var b: Node2D = _wizard(1, _rooms[3] + Vector2(40.0, 0.0))
	_frames(60)
	check_equal(_split.views.count, 0, "together: one picture")
	# B walks east; the first frame with views, each is the world camera's picture.
	var frames: int = 0
	while _split.views.count == 0 and frames < 2000:
		b.global_position += Vector2(6.0, 0.0)
		_frame()
		frames += 1
	check_equal(_split.views.count, 2, "walked apart: two views")
	var drawn: Transform2D = _root_transform()
	for view in _split.views.count:
		check(_gap(_split.views.to_screen[view], drawn) < 0.01, "view %d starts as the picture drawn (%.4f px off)" % [view, _gap(_split.views.to_screen[view], drawn)])
		check_equal(_split.stage_of(view), 1, "its divider starts a pixel wide")
	# Then the divider grows a pixel a frame, and the views ease apart without a jump.
	var before: Array[Transform2D] = [_split.views.to_screen[0], _split.views.to_screen[1]]
	for step in SplitCameraScript.DIVIDER_WIDTH + 30:
		_frame()
		for view in _split.views.count:
			var moved: float = _gap(_split.views.to_screen[view], before[view])
			check(moved < 40.0, "view %d moves on smoothly (%.2f px in a frame)" % [view, moved])
			before[view] = _split.views.to_screen[view]
	check(a != null, "the wizards stand")


func test_a_merge_ends_on_the_one_picture_and_only_the_divider_shrinks() -> void:
	_wizard(0, _rooms[2])
	var b: Node2D = _wizard(1, _rooms[7])
	_frames(120)
	check_equal(_split.views.count, 2, "apart: two views")
	# B walks back to A; the views ease onto each other and the one picture.
	var stages: PackedInt32Array = PackedInt32Array([_split.stage_of(0), _split.stage_of(1)])
	var last: Array[Transform2D] = [_split.views.to_screen[0], _split.views.to_screen[1]]
	var frames: int = 0
	while _split.views.count > 0 and frames < 4000:
		var to: Vector2 = _rooms[2] + Vector2(48.0, 0.0) - b.global_position
		b.global_position += to.limit_length(6.0)
		_frame()
		frames += 1
		if _split.views.count > 0:
			for view in _split.views.count:
				check(absi(_split.stage_of(view) - stages[mini(view, 1)]) <= 1, "a divider changes a pixel a frame at most")
			for view in _split.views.count:
				stages[mini(view, 1)] = _split.stage_of(view)
				last[mini(view, 1)] = _split.views.to_screen[view]
	check_equal(_split.views.count, 0, "together again: one picture")
	check(not _split.split, "not split")
	var drawn: Transform2D = _root_transform()
	for view in 2:
		check(_gap(last[view], drawn) < SplitCameraScript.SETTLED * 4.0, "the last view's picture was the one drawn now (%.4f px off)" % _gap(last[view], drawn))
	for view in 2:
		check_equal(stages[view], 0, "the divider had shrunk out")


func test_this_machines_seats_only() -> void:
	# Online: seat 1 plays elsewhere, far away; this machine plays seat 0 alone.
	_wizard(0, _rooms[0])
	_wizard(1, _rooms[11])
	_frames(60, 0b0001)
	check_equal(_split.views.count, 0, "a teammate on another machine never splits this screen")
	_wizard(2, _rooms[6])
	_frames(120, 0b0101)
	check_equal(_split.views.count, 2, "two seats here, apart: two views")
	check(_split.views.view_of_seat(1) < 0, "the other machine's seat is in none")


func test_a_view_keeps_its_slot() -> void:
	_wizard(0, _rooms[0])
	_wizard(1, _rooms[5])
	_wizard(2, _rooms[10])
	_frames(90)
	var slots: Array[int] = []
	for seat in 3:
		slots.append(_split.slot_of(_split.views.view_of_seat(seat)))
	_frames(90)
	for seat in 3:
		check_equal(_split.slot_of(_split.views.view_of_seat(seat)), slots[seat], "seat %d's view keeps its slot" % seat)


func test_a_new_room_drops_the_views() -> void:
	_wizard(0, _rooms[0])
	_wizard(1, _rooms[8])
	_frames(60)
	check(_split.views.count > 0, "split")
	_split.reset()
	check_equal(_split.views.count, 0, "a new room: no view")
	check(not _split.split, "and not split until the next frame finds it")


func _free_bodies() -> void:
	for body in _bodies:
		if is_instance_valid(body):
			body.free()
	_bodies.clear()
