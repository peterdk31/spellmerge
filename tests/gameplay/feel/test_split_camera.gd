extends "res://tests/support/suite.gd"
## The Voronoi split's views (connected biomes CB6, gameplay/feel/split_camera.gd; decision 27):
## one picture while everyone fits; past that a view a group of wizards, the cells covering the
## screen, each holding its own wizards; a split starts as the picture it splits from and a merge
## ends on it, so nothing jumps but the divider, which grows and shrinks a pixel a drawn frame.
## With 1 to 4 seats in the rooms of a biome (the hand-made twelve-room row, tests/support/biome_maps.gd),
## the world's camera driven by the party camera as in the game.
const SplitCameraScript := preload("res://gameplay/feel/split_camera.gd")
const PartyCameraScript := preload("res://gameplay/feel/party_camera.gd")
const CloseFoesScript := preload("res://gameplay/feel/close_foes.gd")
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
	var most: float = 0.0
	for step in 60:
		_frame()
		for view in _split.views.count:
			var moved: float = _gap(_split.views.to_screen[view], before[view])
			if step < 2:
				check(moved < 1.0, "view %d sets off gently (%.2f px in frame %d)" % [view, moved, step])
			most = maxf(most, moved)
			before[view] = _split.views.to_screen[view]
	check(most < 32.0, "the views ease apart without a jump (at most %.2f px a frame)" % most)
	print("SPLIT: the views moved at most %.2f px a frame easing apart" % most)
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


## A copy of the views as laid out now.
func _snapshot() -> ScreenViewsScript:
	var copy := ScreenViewsScript.new()
	var views: ScreenViewsScript = _split.views
	copy.screen = views.screen
	copy.count = views.count
	for view in views.count:
		copy.set_view(view, views.seats[view], views.to_screen[view], views.anchor[view])
		for at in views.corners(view):
			copy.set_corner(view, at, views.corner(view, at))
		copy.set_corners(view, views.corners(view))
	return copy


## The world point drawn at screen point `p` (the world camera's with no view).
func _world_at(views: ScreenViewsScript, p: Vector2) -> Vector2:
	if views.count == 0:
		return _root_transform().affine_inverse() * p
	var view: int = views.view_at(p)
	return views.to_screen[maxi(view, 0)].affine_inverse() * p


## No part of the screen shows a far other part of the world from one frame to the next: a pixel in
## the same view as before shows what it showed moved at most `most` screen pixels (the views' own
## easing); a pixel that changed view lies within LINE_MOVE of its new cell's edge (a divider moving
## on, a few pixels a frame, never a region of the screen changing picture at once).
const LINE_MOVE: float = 6.0


func _check_no_jump(before: ScreenViewsScript, before_root: Transform2D, after: ScreenViewsScript, most: float, what: String) -> bool:
	for y in range(3, int(SCREEN.y), 12):
		for x in range(3, int(SCREEN.x), 12):
			var p := Vector2(x, y) + Vector2(0.5, 0.5)
			var was_view: int = before.view_at(p) if before.count > 0 else -1
			var now_view: int = after.view_at(p) if after.count > 0 else -1
			var was_seats: int = before.seats[was_view] if was_view >= 0 else -1
			var now_seats: int = after.seats[now_view] if now_view >= 0 else -1
			var was: Vector2 = before.to_screen[was_view].affine_inverse() * p if was_view >= 0 else before_root.affine_inverse() * p
			var now: Vector2 = _world_at(after, p)
			var zoom: float = after.to_screen[now_view].x.x if now_view >= 0 else _root_transform().x.x
			var moved: float = was.distance_to(now) * zoom
			if moved <= most:
				continue
			if now_view >= 0 and was_view >= 0 and was_seats != now_seats and not after.cell_holds(now_view, p, -LINE_MOVE):
				continue
			check(false, "%s: the screen point %s jumped %.1f px (view %d to %d)" % [what, p, moved, was_view, now_view])
			return false
	return true


func test_a_wizard_leaving_a_shared_view_splits_off_it_without_a_jump() -> void:
	_wizard(0, _rooms[1])
	var walker: Node2D = _wizard(1, _rooms[1] + Vector2(40.0, 0.0))
	_wizard(2, _rooms[9])
	_frames(150)
	check_equal(_split.views.count, 2, "the pair shares a view, the third its own")
	var shared: int = _split.views.view_of_seat(0)
	var frames: int = 0
	while _split.views.count == 2 and frames < 600:
		var before: ScreenViewsScript = _snapshot()
		var before_root: Transform2D = _root_transform()
		walker.global_position += Vector2(0.0, 5.0)
		_frame()
		frames += 1
		if _split.views.count == 3:
			var left: Transform2D = before.to_screen[shared]
			var new_view: int = _split.views.view_of_seat(1)
			check(_gap(_split.views.to_screen[new_view], left) < 0.01, "the new view starts as the view its wizard left (%.3f px off)" % _gap(_split.views.to_screen[new_view], left))
			_check_no_jump(before, before_root, _snapshot(), 40.0, "the split-off frame")
	check_equal(_split.views.count, 3, "walked off: a view of its own")
	for i in 60:
		var before: ScreenViewsScript = _snapshot()
		var before_root: Transform2D = _root_transform()
		walker.global_position += Vector2(0.0, 5.0)
		_frame()
		if not _check_no_jump(before, before_root, _snapshot(), 40.0, "easing apart"):
			break


func test_three_views_where_one_merges_into_another_without_a_jump() -> void:
	_wizard(0, _rooms[0])
	var walker: Node2D = _wizard(1, _rooms[5])
	_wizard(2, _rooms[11])
	_frames(150)
	check_equal(_split.views.count, 3, "three views")
	var frames: int = 0
	var target: Vector2 = _rooms[0] + Vector2(40.0, 0.0)
	while frames < 3000 and (_split.views.count > 2 or walker.global_position.distance_to(target) > 1.0):
		var before: ScreenViewsScript = _snapshot()
		var before_root: Transform2D = _root_transform()
		walker.global_position += (target - walker.global_position).limit_length(8.0)
		_frame()
		frames += 1
		# A frame where the walker's view goes, or the cells shift: what each pixel shows moves no
		# more than the views' easing does.
		if not _check_no_jump(before, before_root, _snapshot(), 40.0, "merging (frame %d)" % frames):
			break
	check_equal(_split.views.count, 2, "merged: two views")
	check_equal(_split.views.view_of_seat(0), _split.views.view_of_seat(1), "seats 0 and 1 share one")


# --- Close foes (the owner, 2026-11-19) ------------------------------------------------------------

## An enemy at `at`.
func _foe(at: Vector2) -> Node2D:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.global_position = at
	var id: int = _table.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	_table.set_node(id, node)
	_bodies.append(node)
	return node


## A view zooms out for the foes close to its own wizards, no further than the widest zoom, eased;
## the cells still cover the screen and hold their wizards; the other view stays at the split's zoom.
func test_a_view_zooms_out_for_its_close_foes_and_its_cell_still_holds_its_wizard() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	_wizard(0, _rooms[0])
	_wizard(1, _rooms[8])
	var foe: Node2D = _foe(_rooms[0] + Vector2(0.0, CloseFoesScript.REACH - 30.0))
	var foes := CloseFoesScript.new()
	var zooms: Array[float] = []
	for i in 120:
		foes.find(_table, null)
		_party.look(_table, 0, foes)
		_party.step(FRAME)
		_split.step(FRAME, _table, 0, _camera, SCREEN, foes)
		var near: int = _split.views.view_of_seat(0)
		if near >= 0:
			zooms.append(_split.views.to_screen[near].x.x)
	var views: ScreenViewsScript = _split.views
	check_equal(views.count, 2, "split")
	var near: int = views.view_of_seat(0)
	var far: int = views.view_of_seat(1)
	var zoom: float = views.to_screen[near].x.x
	check(zoom < SplitCameraScript.SPLIT_ZOOM - 0.05, "seat 0's view zoomed out for its foe (%f)" % zoom)
	check(zoom >= PartyCameraScript.MIN_ZOOM - 0.001, "no further than the widest zoom")
	check(absf(views.to_screen[far].x.x - SplitCameraScript.SPLIT_ZOOM) < 0.01, "seat 1's view, with no foe near, at the split's zoom")
	var drawn: Vector2 = views.to_screen[near] * foe.global_position
	check(views.cell_holds(near, drawn, 0.5), "the foe is drawn in its wizard's cell (%s)" % drawn)
	_check_cover(views, "with a close foe")
	_check_own_cells(views, "with a close foe")
	for i in range(1, zooms.size()):
		check(absf(zooms[i] - zooms[i - 1]) < 0.05, "the zoom eases, no jump (%f to %f)" % [zooms[i - 1], zooms[i]])
		if absf(zooms[i] - zooms[i - 1]) >= 0.05:
			break
	# A foe far beyond the cell: the zoom stops at the widest.
	var far_grid := RoomGrid.new()
	far_grid.size_to(Rect2(_rooms[0] - Vector2(4096.0, 4096.0), Vector2(8192.0, 8192.0)))
	far_grid.set_sealed(far_grid.add_place(Rect2(_rooms[0] - Vector2(2048.0, 2048.0), Vector2(4096.0, 4096.0))), true)
	foe.global_position = _rooms[0] + Vector2(0.0, 1800.0)
	for i in 240:
		foes.find(_table, far_grid)
		_party.look(_table, 0, foes)
		_party.step(FRAME)
		_split.step(FRAME, _table, 0, _camera, SCREEN, foes)
	near = _split.views.view_of_seat(0)
	var limits := Rect2(_camera.limit_left, _camera.limit_top, _camera.limit_right - _camera.limit_left, _camera.limit_bottom - _camera.limit_top)
	var widest: float = maxf(PartyCameraScript.MIN_ZOOM, maxf(SCREEN.x / limits.size.x, SCREEN.y / limits.size.y))
	check(near >= 0 and absf(_split.views.to_screen[near].x.x - widest) < 0.01, "a far foe in a sealed fight: the view stops at the widest zoom the limits allow, %f (%f)" % [widest, _split.views.to_screen[near].x.x if near >= 0 else -1.0])
	check(_split.split, "a foe never merges or splits the views: still split")
	_check_own_cells(_split.views, "with a far foe")
	# Narrow limits (a biome one screen tall): the view zooms out no wider than they allow.
	_split.step(FRAME, _table, 0, _camera, SCREEN, foes)
	var group: int = 0
	check(is_equal_approx(_split.zoom_for_foes(group, SCREEN, Rect2(limits.position, Vector2(limits.size.x, SCREEN.y / 0.8))), 0.8), "limits 1/0.8 screens tall: no wider than 0.8")
