extends "res://tests/support/suite.gd"
## The equal split screen (the owner, 2026-11-19 and 2026-11-20; gameplay/feel/equal_panes.gd and
## split_camera.gd's `equal`): wizards close together share a pane (grouped by distance, with the
## join's hysteresis), and the groups' panes are one view, the left and right halves (always, P1
## and P3 too) or the quarters (the fourth a blank with three groups); each seat's HUD spot inside
## its own pane (`corners`); one picture while everyone fits and the
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


## Every group's view's cell is its pane (`groups`: the seats of each view): the pane's area, holding
## the pane's middle and points just inside each of its corners, its wizards drawn inside it, a
## lone wizard at its middle; each seat's HUD spot inside its own pane, no two on one spot.
func _check_panes(groups: Array, what: String) -> void:
	var views: ScreenViewsScript = _split.views
	check_equal(views.count, groups.size(), "%s: a view a group" % what)
	var spots: int = 0
	for group: Array in groups:
		var typed: Array[int] = []
		typed.assign(group)
		var first: int = typed.min()
		var view: int = views.view_of_seat(first)
		if view < 0:
			check(false, "%s: seat %d has a view" % [what, first])
			continue
		check_equal(views.seats[view], _mask(typed), "%s: seats %s share a view, theirs alone" % [what, typed])
		var pane: Rect2 = _split.panes().pane(first, SCREEN)
		check(absf(_area(views, view) - pane.get_area()) < 2.0, "%s: %s's cell is its pane's size (%.1f, the pane %.1f)" % [what, typed, _area(views, view), pane.get_area()])
		for inside: Vector2 in [pane.get_center(), pane.position + Vector2(2.0, 2.0), pane.end - Vector2(2.0, 2.0), Vector2(pane.end.x - 2.0, pane.position.y + 2.0), Vector2(pane.position.x + 2.0, pane.end.y - 2.0)]:
			check_equal(views.view_at(inside), view, "%s: %s's pane point %s is its view's" % [what, typed, inside])
		for seat in typed:
			var body := _table.node_of(_table.home_of_seat(seat)) as Node2D
			var drawn: Vector2 = views.to_screen[view] * body.global_position
			check(pane.grow(0.5).has_point(drawn), "%s: seat %d is drawn in its pane (%s in %s)" % [what, seat, drawn, pane])
			if typed.size() == 1:
				check(drawn.distance_to(pane.get_center()) < 2.0, "%s: seat %d is drawn at its pane's middle (%s)" % [what, seat, drawn])
			var spot: int = _split.corners[seat]
			check(pane.grow(0.5).encloses(EqualPanesScript.quarter_rect(spot >> 1, SCREEN)), "%s: seat %d's HUD quarter (spot %d) is inside its pane" % [what, seat, spot])
			check(spots & (1 << spot) == 0, "%s: seat %d's HUD spot %d is no other's" % [what, seat, spot])
			spots |= 1 << spot


# --- The panes ---------------------------------------------------------------------------------


## Panes for groups (`EqualPanes.lay`, by group's lowest seat: its seats).
static func _laid(groups: Array) -> EqualPanesScript:
	var by_first := PackedInt32Array([0, 0, 0, 0])
	for group: Array in groups:
		var mask: int = 0
		var first: int = 4
		for seat: int in group:
			mask |= 1 << seat
			first = mini(first, seat)
		by_first[first] = mask
	var panes := EqualPanesScript.new()
	panes.lay(by_first)
	return panes


const LEFT := Rect2(0.0, 0.0, 320.0, 360.0)
const RIGHT := Rect2(320.0, 0.0, 320.0, 360.0)
const QUARTERS: Array[Rect2] = [Rect2(0.0, 0.0, 320.0, 180.0), Rect2(320.0, 0.0, 320.0, 180.0), Rect2(0.0, 180.0, 320.0, 180.0), Rect2(320.0, 180.0, 320.0, 180.0)]


func test_two_panes_are_always_left_and_right_with_the_panels_moved_into_them() -> void:
	var both: EqualPanesScript = _laid([[0], [1]])
	check_equal(both.pane(0, SCREEN), LEFT, "P1 and P2: P1 the left half")
	check_equal(both.pane(1, SCREEN), RIGHT, "P2 the right half")
	check_equal(both.corner, PackedInt32Array([0, 2, 4, 6]), "both panels where they were")
	var crossed: EqualPanesScript = _laid([[1], [2]])
	check_equal(crossed.pane(2, SCREEN), LEFT, "P2 and P3: P3 (bottom left panel) the left half")
	check_equal(crossed.pane(1, SCREEN), RIGHT, "P2 the right half")
	# The owner, 2026-11-20: P1 and P3 are left and right too, P3's panel moved to the right.
	var stacked: EqualPanesScript = _laid([[0], [2]])
	check_equal(stacked.pane(0, SCREEN), LEFT, "P1 and P3: P1 the left half")
	check_equal(stacked.pane(2, SCREEN), RIGHT, "P3 the right half, not the bottom")
	check_equal(stacked.corner[0], 0, "P1's panel stays top left")
	check_equal(stacked.corner[2], 6, "P3's panel moves to the bottom right (quarter 3, its outer side)")
	var right_side: EqualPanesScript = _laid([[1], [3]])
	check_equal(right_side.pane(1, SCREEN), LEFT, "P2 and P4: P2 the left half")
	check_equal(right_side.corner[1], 0, "P2's panel moves to the top left")
	check_equal(right_side.corner[3], 6, "P4's stays bottom right")
	check_equal(both.blank_quarter, -1, "two panes: no blank")
	# Four players in two pairs: the halves, each seat a spot in its own half.
	var pairs: EqualPanesScript = _laid([[0, 1], [2, 3]])
	check_equal(pairs.pane(0, SCREEN), LEFT, "P1 and P2 together, P3 and P4 together: P1's pair left")
	for seat in 4:
		var pane: Rect2 = pairs.pane(0 if seat < 2 else 2, SCREEN)
		check(pane.encloses(EqualPanesScript.quarter_rect(pairs.corner[seat] >> 1, SCREEN)), "pairs: seat %d's spot (%d) in its half" % [seat, pairs.corner[seat]])
	# The owner, 2026-11-20: each panel keeps its corner's row in its pair's half (no crossing).
	check_equal(pairs.corner, PackedInt32Array([0, 1, 7, 6]), "pairs: P2's panel at the top left quarter's inner side, P3's at the bottom right's")
	var trio: EqualPanesScript = _laid([[0, 1, 2], [3]])
	var spots: int = 0
	for seat in 3:
		check(LEFT.encloses(EqualPanesScript.quarter_rect(trio.corner[seat] >> 1, SCREEN)), "a trio left: seat %d's spot in the left half" % seat)
		check(spots & (1 << trio.corner[seat]) == 0, "a trio: no two panels on one spot")
		spots |= 1 << trio.corner[seat]


func test_three_and_four_panes_are_quarters_with_a_blank_for_three() -> void:
	var all: EqualPanesScript = _laid([[0], [1], [2], [3]])
	for seat in 4:
		check_equal(all.pane(seat, SCREEN), QUARTERS[seat], "four groups: seat %d its corner's quarter" % seat)
	check_equal(all.blank_quarter, -1, "four groups: no blank")
	check_equal(all.corner, PackedInt32Array([0, 2, 4, 6]), "every panel where it was")
	var three: EqualPanesScript = _laid([[0], [1], [3]])
	for seat: int in [0, 1, 3]:
		check_equal(three.pane(seat, SCREEN), QUARTERS[seat], "three seats: seat %d its corner's quarter" % seat)
	check_equal(three.blank_quarter, 2, "three seats: the missing seat's quarter is the blank")
	check_equal(three.blank_site(SCREEN), QUARTERS[2].get_center(), "at its middle")
	# Four players, a pair and two alone (the owner, 2026-11-20): the pair a half, the two alone a
	# quarter each of the other half, no void; the pair's bottom quarter its twin.
	var pair: EqualPanesScript = _laid([[0, 1], [2], [3]])
	check_equal(pair.pane(0, SCREEN), LEFT, "the pair P1 and P2: the left half")
	check_equal(pair.pane(2, SCREEN), QUARTERS[1], "P3 the top right quarter")
	check_equal(pair.pane(3, SCREEN), QUARTERS[3], "P4 its own")
	check_equal(pair.blank_quarter, -1, "no void")
	check_equal(pair.twin_group, 0, "the pair has a twin")
	check_equal(pair.twin_quarter, 2, "its half's bottom quarter")
	check_equal(pair.site(0, SCREEN), LEFT.get_center(), "and drawn at its half's middle")
	check_equal(pair.corner, PackedInt32Array([0, 1, 2, 6]), "P2's panel at the top left quarter's inner side, P3's in its quarter")
	var three_alone: EqualPanesScript = _laid([[0], [1], [2]])
	check_equal(three_alone.twin_group, -1, "three players in three groups: no twin")
	check_equal(three_alone.blank_quarter, 3, "but the void")
	var rest: Vector2 = EqualPanesScript.blank_rest(2, SCREEN)
	check(rest.distance_to(Vector2(0.0, 360.0)) > SCREEN.length(), "the blank rests past its corner, farther than any anchor on the screen could be (%s)" % rest)
	var one: EqualPanesScript = _laid([[0, 1, 2]])
	check_equal(one.pane(0, SCREEN), Rect2(Vector2.ZERO, SCREEN), "one group: the whole screen")
	check_equal(one.corner, PackedInt32Array([0, 2, 4, 6]), "and every panel where it was")


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
		var alone: Array = []
		for seat: int in typed:
			alone.append([seat])
		_check_panes(alone, "%s" % [seats])
		for view in _split.views.count:
			check_equal(_split.stage_of(view), SplitCameraScript.DIVIDER_WIDTH, "%s: the dividers have grown in" % [seats])
		var blank: int = 6 - typed[0] - typed[1] - typed[2] if typed.size() == 3 else -1
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
	_check_panes([[0], [1]], "parted")
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
	var west: Node2D = _wizard(1, _rooms[5] + Vector2(30.0, 0.0))
	var walker: Node2D = _wizard(2, _rooms[5] + Vector2(0.0, 30.0))
	_frames(60)
	check_equal(_split.views.count, 0, "together: one picture")
	var target: Vector2 = _rooms[11]
	var frames: int = 0
	# Two walk off, each its own way, so there are three groups (two close would share a pane).
	while _split.views.count < 3 and frames < 2000:
		walker.global_position += (target - walker.global_position).limit_length(8.0)
		west.global_position += (_rooms[0] - west.global_position).limit_length(8.0)
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
		west.global_position += (_rooms[0] - west.global_position).limit_length(8.0)
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
		west.global_position += (_rooms[5] + Vector2(30.0, 0.0) - west.global_position).limit_length(8.0)
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
	var pane: Rect2 = _split.panes().pane(0, SCREEN)
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
	_check_panes([[0, 1], [2]], "equal from dynamic: the pair shares a half")
	_split.set_equal(false)
	_frames(300)
	check_equal(_split.views.count, 2, "dynamic again: the pair shares a view")
	check_equal(_split.blank_count(), 0, "and no blank")


# --- Grouped panes (the owner, 2026-11-20) -----------------------------------------------------


func test_three_players_two_close_share_a_half_and_part_past_the_leave_reach() -> void:
	if not _ready_rooms():
		return
	_wizard(0, _rooms[0])
	var near: Node2D = _wizard(1, _rooms[0] + Vector2(SplitCameraScript.JOIN_REACH - 40.0, 0.0))
	_wizard(2, _rooms[11])
	_frames(240)
	check(_split.split, "the third far: split")
	_check_panes([[0, 1], [2]], "two close, one far")
	check_equal(_split.blank_count(), 0, "two panes: no blank")
	# The halves that move fewest panels: P3 left (its own corner), the pair right, P1's panel to
	# the top right quarter's inner side (it keeps its row).
	check_equal(_split.panes().pane(2, SCREEN), LEFT, "P3 the left half")
	check_equal(_split.panes().pane(0, SCREEN), RIGHT, "the pair the right half")
	check_equal(_split.corners, PackedInt32Array([3, 2, 4, 6]), "P1's panel moves into the right half, on its row")
	# Between the join and the leave reach they stay together: no flicker at the join distance.
	var between: float = (SplitCameraScript.JOIN_REACH + SplitCameraScript.LEAVE_REACH) * 0.5
	near.global_position = _rooms[0] + Vector2(between, 0.0)
	for step in 120:
		_frame()
		check_equal(_split.views.view_of_seat(0), _split.views.view_of_seat(1), "within the leave reach they share a pane (frame %d)" % step)
		if _split.views.view_of_seat(0) != _split.views.view_of_seat(1):
			return
	# Past it they part: three groups, three quarters and the blank.
	near.global_position = _rooms[0] + Vector2(SplitCameraScript.LEAVE_REACH + 60.0, 0.0)
	_frames(300)
	_check_panes([[0], [1], [2]], "all three apart")
	check_equal(_split.panes().blank_quarter, 3, "the blank the missing P4's quarter")
	check_equal(_split.corners, PackedInt32Array([0, 2, 4, 6]), "every panel back on its own corner")
	# Back within the leave reach (but past the join reach) they stay apart, then join within it.
	near.global_position = _rooms[0] + Vector2(between, 0.0)
	_frames(30)
	check(_split.views.view_of_seat(0) != _split.views.view_of_seat(1), "apart, they join only within the join reach")
	near.global_position = _rooms[0] + Vector2(SplitCameraScript.JOIN_REACH - 40.0, 0.0)
	_frames(300)
	_check_panes([[0, 1], [2]], "close again")


func test_four_players_in_pairs_are_halves_and_a_pair_and_two_alone_are_quarters() -> void:
	if not _ready_rooms():
		return
	_wizard(0, _rooms[0])
	_wizard(1, _rooms[0] + Vector2(60.0, 0.0))
	_wizard(2, _rooms[11])
	var walker: Node2D = _wizard(3, _rooms[11] + Vector2(60.0, 0.0))
	_frames(240)
	_check_panes([[0, 1], [2, 3]], "two pairs")
	check_equal(_split.panes().pane(0, SCREEN), LEFT, "P1's pair the left half")
	# P4 walks off to the middle: three groups, P3 and P4 apart.
	walker.global_position = _rooms[6]
	_frames(300)
	_check_panes([[0, 1], [2], [3]], "a pair and two alone")
	check_equal(_split.panes().pane(0, SCREEN), LEFT, "the pair the left half")
	var owner: int = _split.views.view_of_seat(0)
	check_equal(_split.blank_owner_view(), owner, "the blank is the pair's twin, showing its picture")
	check_equal(_split.blank_divider(owner), 0, "no line between the pair and its twin")
	check(_split.blank_anchor(0).distance_to(QUARTERS[2].get_center()) < 0.5, "the twin on the bottom left quarter")
	check(_split.views.anchor[owner].distance_to(QUARTERS[0].get_center()) < 0.5, "the pair cut as the top left quarter")
	check_equal(_split.views.view_at(QUARTERS[2].get_center()), owner, "readers see the bottom left as the pair's")
	# Back to two pairs: the twin moves out, never jumping; the anchors walk.
	var before := PackedVector2Array()
	for view in _split.views.count:
		before.append(_split.views.anchor[view])
	var last_twin: float = 0.0
	walker.global_position = _rooms[11] + Vector2(60.0, 0.0)
	for frame in 300:
		_frame()
		if _split.blank_count() > 0:
			var out: float = _split.blank_anchor(0).distance_to(QUARTERS[2].get_center())
			check(out >= last_twin - 0.001, "the twin only moves out")
			last_twin = out
		for view in mini(before.size(), _split.views.count):
			if _split.views.seats[view] & 1 != 0:
				var moved: float = _split.views.anchor[view].distance_to(before[view])
				check(moved <= SplitCameraScript.PANE_ANCHOR_STEP + 0.01, "the pair's anchor walks (%.1f)" % moved)
				before[view] = _split.views.anchor[view]
	_check_panes([[0, 1], [2, 3]], "two pairs again")
	check_equal(_split.blank_count(), 0, "no twin")
	_split.set_equal(false)
	_frames(10)
	check_equal(_split.corners, PackedInt32Array([0, 2, 4, 6]), "dynamic: every panel on its own corner")


func test_p1_and_p3_are_left_and_right_in_play_and_p3s_panel_moves_right() -> void:
	if not _ready_rooms():
		return
	_wizard(0, _rooms[0])
	_wizard(2, _rooms[11])
	var seen: int = _split.corners_version
	var changed: int = 0
	for frame in 240:
		_frame()
		if _split.corners_version != seen:
			changed += 1
			seen = _split.corners_version
	_check_panes([[0], [2]], "P1 and P3")
	check_equal(_split.panes().pane(2, SCREEN), RIGHT, "P3 the right half")
	check_equal(_split.corners[2], 6, "P3's HUD at the bottom right")
	check_equal(changed, 1, "the corners changed once, as the screen split")
	_free_bodies()
	_frames(5)
	check_equal(_split.corners[2], 4, "no wizards: P3's HUD back on its own corner")
	check(_split.corners_version != seen, "counted as a change")
	# Regression: a reset (a new room) put the corners home without counting it, so the HUD was
	# never told and P3's panel stayed on the right.
	_wizard(0, _rooms[0])
	_wizard(2, _rooms[11])
	_frames(240)
	check_equal(_split.corners[2], 6, "split again: P3's HUD at the bottom right")
	seen = _split.corners_version
	_split.reset()
	check_equal(_split.corners[2], 4, "a reset: P3's HUD home")
	check(_split.corners_version != seen, "and the change is counted, for the HUD to hear")


## Regression (review): a moved panel landed on the corner panel of a seat played on another machine
## (it has a body, so a panel, but no pane here).
func test_a_moved_panel_keeps_off_the_corner_of_a_seat_played_elsewhere() -> void:
	var stacked := PackedInt32Array([1 << 0, 0, 1 << 2, 0])
	var panes := EqualPanesScript.new()
	panes.lay(stacked, 1 << 3)
	check_equal(panes.corner[2], 7, "P1 and P3 here, P4 elsewhere: P3's panel at the bottom right quarter's inner side, not on P4's")
	panes.lay(stacked)
	check_equal(panes.corner[2], 6, "P4 nowhere: the bottom right corner")
	if not _ready_rooms():
		return
	_wizard(0, _rooms[0])
	_wizard(2, _rooms[11])
	_wizard(3, _rooms[6])
	for frame in 240:
		_party.look(_table, 0b0101)
		_party.step(FRAME)
		_split.step(FRAME, _table, 0b0101, _camera, SCREEN)
	check_equal(_split.views.count, 2, "only this machine's seats split it")
	check_equal(_split.corners[2], 7, "in play too: P3's panel keeps off P4's corner")


## Regression (review): the twin is kept by its view's slot, so when its pair's lowest seat changes
## (a third joins the pair: two halves) the twin keeps the pair's picture while it moves out.
func test_the_twin_keeps_its_pairs_picture_while_it_moves_out_after_a_regroup() -> void:
	if not _ready_rooms():
		return
	var lone: Node2D = _wizard(0, _rooms[0])
	_wizard(1, _rooms[11])
	_wizard(2, _rooms[11] + Vector2(60.0, 0.0))
	_wizard(3, _rooms[6])
	_frames(300)
	var owner: int = _split.blank_owner_view()
	check(owner >= 0, "the pair P2 and P3 has a twin")
	lone.global_position = _rooms[11] + Vector2(30.0, 40.0)
	var frames_out: int = 0
	for frame in 300:
		_frame()
		if _split.blank_count() == 0:
			break
		frames_out += 1
		check(_split.blank_owner_view() >= 0, "while it moves out the twin shows its pair's picture (frame %d)" % frame)
		if _split.blank_owner_view() < 0:
			return
	check(frames_out >= 3, "it moved out over frames (%d)" % frames_out)
