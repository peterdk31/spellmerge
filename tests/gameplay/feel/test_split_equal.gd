extends "res://tests/support/suite.gd"
## The equal split screen (the owner, 2026-11-19; gameplay/feel/equal_panes.gd and split_camera.gd's
## `equal`): the panes for two, three and four seats (halves, quarters, the fourth quarter a blank
## with three), each seat's on its corner panel's side; one picture while everyone fits and the
## panes once they part, no jump either way (the views start as the one picture, the anchors walk,
## the blank grows in from its corner and is gone before the merge ends); close foes kept inside
## the pane; the mode changed while split. With 2 to 4 seats in the rooms of a biome (the hand-made
## twelve-room row, tests/support/biome_maps.gd), as test_split_camera.gd does.
const SplitCameraScript := preload("res://gameplay/feel/split_camera.gd")
const EqualPanesScript := preload("res://gameplay/feel/equal_panes.gd")
const PartyCameraScript := preload("res://gameplay/feel/party_camera.gd")
const CloseFoesScript := preload("res://gameplay/feel/close_foes.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")

const SCREEN := Vector2(640.0, 360.0)
const FRAME: float = 1.0 / 60.0
## The rooms the seats stand in, far apart (west to east of the row).
const PLACES: Array[int] = [0, 4, 8, 11]

var _table: ActorsScript
var _holder: SubViewport
var _camera: Camera2D
var _party: PartyCameraScript
var _split: SplitCameraScript
var _bodies: Array[Node2D] = []
var _rooms: PackedVector2Array = PackedVector2Array()


func before_each() -> void:
	_table = own(ActorsScript.new()) as ActorsScript
	root.add_child(_table)
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
	_split.set_equal(true)
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
	_camera.limit_left = int(bounds.position.x) - 400
	_camera.limit_top = int(bounds.position.y) - 400
	_camera.limit_right = int(bounds.end.x) + 400
	_camera.limit_bottom = int(bounds.end.y) + 400
	return out


func _wizard(seat: int, at: Vector2) -> Node2D:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.global_position = at
	var id: int = _table.open(ActorsScript.TEAM_WIZARDS, seat, seat)
	_table.set_node(id, node)
	_table.set_home(id, seat)
	_bodies.append(node)
	return node


func _foe(at: Vector2) -> Node2D:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.global_position = at
	var id: int = _table.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	_table.set_node(id, node)
	_bodies.append(node)
	return node


func _frame(foes: CloseFoesScript = null) -> void:
	if foes != null:
		foes.find(_table, null)
	_party.look(_table, 0, foes)
	_party.step(FRAME)
	_split.step(FRAME, _table, 0, _camera, SCREEN, foes)


func _frames(count: int, foes: CloseFoesScript = null) -> void:
	for i in count:
		_frame(foes)


func _free_bodies() -> void:
	for body in _bodies:
		if is_instance_valid(body):
			body.free()
	_bodies.clear()


func _ready_rooms() -> bool:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return false
	return true


static func _mask(seats: Array[int]) -> int:
	var mask: int = 0
	for seat in seats:
		mask |= 1 << seat
	return mask


static func _area(views: ScreenViewsScript, view: int) -> float:
	var twice: float = 0.0
	var n: int = views.corners(view)
	for i in n:
		twice += views.corner(view, i).cross(views.corner(view, (i + 1) % n))
	return absf(twice) * 0.5


## How far two pictures are apart on screen (pixels), at the screen's corners.
static func _gap(a: Transform2D, b: Transform2D) -> float:
	var most: float = 0.0
	for corner: Vector2 in [Vector2.ZERO, Vector2(SCREEN.x, 0.0), SCREEN, Vector2(0.0, SCREEN.y)]:
		most = maxf(most, (a.affine_inverse() * corner).distance_to(b.affine_inverse() * corner) * a.x.x)
	return most


## Every seat's view's cell is its pane: the pane's area, holding the pane's middle and points just
## inside each of its corners, and its wizard drawn inside it.
func _check_panes(seats: Array[int], what: String) -> void:
	var present: int = _mask(seats)
	var views: ScreenViewsScript = _split.views
	check_equal(views.count, seats.size(), "%s: a view a seat" % what)
	for seat in seats:
		var view: int = views.view_of_seat(seat)
		if view < 0:
			check(false, "%s: seat %d has a view" % [what, seat])
			continue
		check_equal(views.seats[view], 1 << seat, "%s: seat %d's view is its alone" % [what, seat])
		var pane: Rect2 = EqualPanesScript.pane_of(seat, present, SCREEN)
		check(absf(_area(views, view) - pane.get_area()) < 2.0, "%s: seat %d's cell is its pane's size (%.1f, the pane %.1f)" % [what, seat, _area(views, view), pane.get_area()])
		for inside: Vector2 in [pane.get_center(), pane.position + Vector2(2.0, 2.0), pane.end - Vector2(2.0, 2.0), Vector2(pane.end.x - 2.0, pane.position.y + 2.0), Vector2(pane.position.x + 2.0, pane.end.y - 2.0)]:
			check_equal(views.view_at(inside), view, "%s: seat %d's pane point %s is its view's" % [what, seat, inside])
		var body := _table.node_of(_table.home_of_seat(seat)) as Node2D
		var drawn: Vector2 = views.to_screen[view] * body.global_position
		check(pane.grow(0.5).has_point(drawn), "%s: seat %d is drawn in its pane (%s in %s)" % [what, seat, drawn, pane])
		check(drawn.distance_to(pane.get_center()) < 2.0, "%s: seat %d is drawn at its pane's middle (%s)" % [what, seat, drawn])


# --- The panes ---------------------------------------------------------------------------------


func test_two_seats_are_halves_on_their_panels_sides() -> void:
	var both: int = _mask([0, 1])
	check_equal(EqualPanesScript.pane_of(0, both, SCREEN), Rect2(0.0, 0.0, 320.0, 360.0), "P1 and P2: P1 the left half")
	check_equal(EqualPanesScript.pane_of(1, both, SCREEN), Rect2(320.0, 0.0, 320.0, 360.0), "P2 the right half")
	var crossed: int = _mask([1, 2])
	check_equal(EqualPanesScript.pane_of(2, crossed, SCREEN), Rect2(0.0, 0.0, 320.0, 360.0), "P2 and P3: P3 (bottom left panel) the left half")
	check_equal(EqualPanesScript.pane_of(1, crossed, SCREEN), Rect2(320.0, 0.0, 320.0, 360.0), "P2 the right half")
	var stacked: int = _mask([0, 2])
	check_equal(EqualPanesScript.pane_of(0, stacked, SCREEN), Rect2(0.0, 0.0, 640.0, 180.0), "P1 and P3 (both panels on the left): P1 the top half")
	check_equal(EqualPanesScript.pane_of(2, stacked, SCREEN), Rect2(0.0, 180.0, 640.0, 180.0), "P3 the bottom half")
	check_equal(EqualPanesScript.blank_seat(both), -1, "two seats: no blank")


func test_three_and_four_seats_are_quarters_with_a_blank_for_three() -> void:
	var quarters: Array[Rect2] = [Rect2(0.0, 0.0, 320.0, 180.0), Rect2(320.0, 0.0, 320.0, 180.0), Rect2(0.0, 180.0, 320.0, 180.0), Rect2(320.0, 180.0, 320.0, 180.0)]
	var all: int = _mask([0, 1, 2, 3])
	for seat in 4:
		check_equal(EqualPanesScript.pane_of(seat, all, SCREEN), quarters[seat], "four seats: seat %d its corner's quarter" % seat)
	check_equal(EqualPanesScript.blank_seat(all), -1, "four seats: no blank")
	var three: int = _mask([0, 1, 3])
	for seat: int in [0, 1, 3]:
		check_equal(EqualPanesScript.pane_of(seat, three, SCREEN), quarters[seat], "three seats: seat %d its corner's quarter" % seat)
	check_equal(EqualPanesScript.blank_seat(three), 2, "three seats: the missing seat's quarter is the blank")
	check_equal(EqualPanesScript.blank_site(three, SCREEN), quarters[2].get_center(), "at its middle")
	var rest: Vector2 = EqualPanesScript.blank_rest(2, SCREEN)
	check(rest.distance_to(Vector2(0.0, 360.0)) > SCREEN.length(), "the blank rests past its corner, farther than any anchor on the screen could be (%s)" % rest)
	check_equal(EqualPanesScript.pane_of(0, _mask([0]), SCREEN), Rect2(Vector2.ZERO, SCREEN), "one seat: the whole screen")


# --- In play -----------------------------------------------------------------------------------


func test_the_views_settle_on_the_panes_for_two_three_and_four_seats() -> void:
	if not _ready_rooms():
		return
	var cases: Array = [[0, 1], [0, 1, 2], [0, 1, 2, 3], [0, 2], [1, 2, 3]]
	for seats: Array in cases:
		var typed: Array[int] = []
		typed.assign(seats)
		before_each()
		for seat: int in typed:
			_wizard(seat, _rooms[PLACES[seat]])
		_frames(180)
		check(_split.split, "%s apart: split" % [seats])
		_check_panes(typed, "%s" % [seats])
		for view in _split.views.count:
			check_equal(_split.stage_of(view), SplitCameraScript.DIVIDER_WIDTH, "%s: the dividers have grown in" % [seats])
		var blank: int = EqualPanesScript.blank_seat(_mask(typed))
		check_equal(_split.blank_count(), 1 if blank >= 0 else 0, "%s: a blank only with three" % [seats])
		if blank >= 0:
			var quarter := Rect2(Vector2(320.0 * float(blank % 2), 180.0 * float(blank >> 1)), Vector2(320.0, 180.0))
			check(_split.blank_anchor(0).distance_to(quarter.get_center()) < 0.5, "%s: the blank stands on its quarter's middle" % [seats])
			check_equal(_split.views.view_at(quarter.get_center()), -1, "%s: no view draws the blank quarter" % [seats])
			var total: float = 0.0
			for view in _split.views.count:
				total += _area(_split.views, view)
			check(absf(total - SCREEN.x * SCREEN.y * 0.75) < 2.0, "%s: the cells cover the three quarters (%.1f)" % [seats, total])
		_free_bodies()


func test_together_one_picture_apart_the_panes_and_back_without_a_jump() -> void:
	if not _ready_rooms():
		return
	_wizard(0, _rooms[3])
	var walker: Node2D = _wizard(1, _rooms[3] + Vector2(40.0, 0.0))
	_frames(60)
	check_equal(_split.views.count, 0, "together: one picture")
	var frames: int = 0
	while _split.views.count == 0 and frames < 2000:
		walker.global_position += Vector2(6.0, 0.0)
		_frame()
		frames += 1
	check_equal(_split.views.count, 2, "walked apart: a pane each")
	var drawn: Transform2D = _holder.get_canvas_transform()
	for view in 2:
		check(_gap(_split.views.to_screen[view], drawn) < 0.01, "view %d starts as the one picture" % view)
		check_equal(_split.stage_of(view), 1, "its divider starts a pixel wide")
	var before: PackedVector2Array = PackedVector2Array([_split.views.anchor[0], _split.views.anchor[1]])
	for step in 240:
		walker.global_position += Vector2(2.0, 0.0)
		_frame()
		for view in _split.views.count:
			var moved: float = _split.views.anchor[view].distance_to(before[view])
			check(moved <= SplitCameraScript.PANE_ANCHOR_STEP + 0.01, "an anchor walks, never jumps (%.2f px)" % moved)
			if moved > SplitCameraScript.PANE_ANCHOR_STEP + 0.01:
				return
			before[view] = _split.views.anchor[view]
	_frames(120)
	_check_panes([0, 1] as Array[int], "parted")
	# Back together: the panes ease onto the one picture and go.
	var stages := PackedInt32Array([_split.stage_of(0), _split.stage_of(1)])
	frames = 0
	while _split.views.count > 0 and frames < 4000:
		walker.global_position += (_rooms[3] + Vector2(40.0, 0.0) - walker.global_position).limit_length(6.0)
		_frame()
		frames += 1
		for view in _split.views.count:
			check(absi(_split.stage_of(view) - stages[mini(view, 1)]) <= 1, "a divider changes a pixel a frame at most")
			stages[mini(view, 1)] = _split.stage_of(view)
	check_equal(_split.views.count, 0, "together again: one picture")
	check(not _split.split, "not split")


func test_with_three_the_blank_grows_in_from_its_corner_and_is_gone_before_the_merge_ends() -> void:
	if not _ready_rooms():
		return
	_wizard(0, _rooms[5])
	_wizard(1, _rooms[5] + Vector2(30.0, 0.0))
	var walker: Node2D = _wizard(2, _rooms[5] + Vector2(0.0, 30.0))
	_frames(60)
	check_equal(_split.views.count, 0, "together: one picture")
	var target: Vector2 = _rooms[11]
	var frames: int = 0
	while _split.views.count == 0 and frames < 2000:
		walker.global_position += (target - walker.global_position).limit_length(8.0)
		_frame()
		frames += 1
	check_equal(_split.views.count, 3, "apart: a pane each")
	var quarter_middle := Vector2(480.0, 270.0)
	# The first frames: the blank is past the screen, then comes in over at least three frames.
	var shown_frames: int = 0
	var gone: bool = true
	var last_gap: float = INF
	for step in 60:
		walker.global_position += (target - walker.global_position).limit_length(8.0)
		_frame()
		if _split.blank_count() == 0:
			continue
		var gap: float = _split.blank_anchor(0).distance_to(quarter_middle)
		check(gap <= last_gap + 0.001, "the blank only comes nearer")
		last_gap = gap
		if step == 0:
			check(_split.views.view_at(Vector2(639.5, 359.5)) >= 0, "at first no point of the screen is the blank's, its corner included")
		if gap > 0.5:
			shown_frames += 1
		gone = false
	check(not gone, "the blank came in")
	check(shown_frames >= 3, "over at least three frames (%d)" % shown_frames)
	_frames(120)
	check(_split.blank_anchor(0).distance_to(quarter_middle) < 0.5, "settled on its quarter")
	# Walk back: the blank moves out before the panes are gone.
	frames = 0
	var out_frames: int = 0
	var last_out: float = 0.0
	var corner_step: float = 0.0
	while _split.views.count > 0 and frames < 4000:
		walker.global_position += (_rooms[5] + Vector2(0.0, 30.0) - walker.global_position).limit_length(8.0)
		_frame()
		frames += 1
		if _split.views.count > 0 and _split.blank_count() > 0:
			var out: float = _split.blank_anchor(0).distance_to(quarter_middle)
			check(out >= last_out - 0.001, "moving out, the blank only goes farther")
			if out - last_out > 0.001:
				out_frames += 1
				corner_step = maxf(corner_step, out - last_out)
			last_out = out
	# Regression: it once jumped to its rest at once, its quarter taken by the panes in one frame.
	check(out_frames >= 3, "the blank moved out over at least three frames (%d)" % out_frames)
	var whole_way: float = EqualPanesScript.blank_rest(3, SCREEN).distance_to(quarter_middle)
	check(corner_step < whole_way * 0.5, "never most of the way in one frame (%.1f of %.1f px)" % [corner_step, whole_way])
	check_equal(_split.views.count, 0, "together again: one picture")
	check_equal(_split.blank_count(), 0, "and no blank")


func test_a_pane_frames_its_close_foes_inside_itself() -> void:
	if not _ready_rooms():
		return
	_wizard(0, _rooms[0])
	_wizard(1, _rooms[8])
	var foe: Node2D = _foe(_rooms[0] + Vector2(200.0, 0.0))
	var foes := CloseFoesScript.new()
	_frames(240, foes)
	var views: ScreenViewsScript = _split.views
	check_equal(views.count, 2, "split")
	var near: int = views.view_of_seat(0)
	var zoom: float = views.to_screen[near].x.x
	check(zoom < SplitCameraScript.SPLIT_ZOOM - 0.05, "seat 0's pane zoomed out for its foe (%f)" % zoom)
	check(zoom >= PartyCameraScript.MIN_ZOOM - 0.001, "no further than the widest zoom")
	var pane: Rect2 = EqualPanesScript.pane_of(0, _mask([0, 1]), SCREEN)
	var drawn: Vector2 = views.to_screen[near] * foe.global_position
	check(pane.grow(-SplitCameraScript.FOE_MARGIN + 1.0).has_point(drawn), "the foe is drawn inside its wizard's pane (%s)" % drawn)
	check(absf(views.to_screen[views.view_of_seat(1)].x.x - SplitCameraScript.SPLIT_ZOOM) < 0.01, "the other pane at the split's zoom")


func test_the_mode_changed_while_split_eases_over() -> void:
	if not _ready_rooms():
		return
	_split.set_equal(false)
	_wizard(0, _rooms[1])
	_wizard(1, _rooms[1] + Vector2(50.0, 0.0))
	_wizard(2, _rooms[10])
	_frames(150)
	check_equal(_split.views.count, 2, "dynamic: the pair shares a view")
	_split.set_equal(true)
	var before: PackedVector2Array = PackedVector2Array()
	for view in _split.views.count:
		before.append(_split.views.anchor[view])
	_frame()
	for view in mini(before.size(), _split.views.count):
		check(_split.views.anchor[view].distance_to(before[view]) <= SplitCameraScript.PANE_ANCHOR_STEP + 0.01, "an anchor walks to its pane, never jumps")
	_frames(240)
	_check_panes([0, 1, 2] as Array[int], "equal from dynamic")
	_split.set_equal(false)
	_frames(300)
	check_equal(_split.views.count, 2, "dynamic again: the pair shares a view")
	check_equal(_split.blank_count(), 0, "and no blank")
