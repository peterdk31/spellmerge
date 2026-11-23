extends "res://tests/support/suite.gd"
## The foe markers while the screen splits, merges and regroups (gameplay/feel/foe_markers.gd): the
## real party camera, split camera and markers stepped frame by frame as Feel steps them, wizards
## and foes in one big sealed room. Every frame, every wanted marker stands inside its own view's
## cell (only one shrinking out may be left behind, for its last looks), and no view has more
## wanted markers than there are foes.
const MarkersScript := preload("res://gameplay/feel/foe_markers.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")
const SplitCameraScript := preload("res://gameplay/feel/split_camera.gd")
const PartyCameraScript := preload("res://gameplay/feel/party_camera.gd")

const SCREEN := Vector2(640.0, 360.0)
const FRAME: float = 1.0 / 60.0
## The foes, all far out of every picture.
const FOES: Array[Vector2] = [Vector2(3000.0, 300.0), Vector2(-3000.0, -300.0), Vector2(500.0, 3000.0)]
## The drawn frames a marker's looks take to shrink out, and a few to spare.
const GOING_FRAMES: int = 12

var _table: ActorsScript
var _markers: MarkersScript
var _grid: RoomGrid
var _camera: Camera2D
var _party: PartyCameraScript
var _split: SplitCameraScript
var _one: ScreenViewsScript
var _seats: int = 0
## What the frames stepped so far saw: the most wanted markers in one view, the frames a wanted
## marker stood outside its own view's cell, the longest a marker was shrinking out outside its
## view's cell (frames on end), and the most markers at once.
var _most_a_view: int = 0
var _outside: int = 0
var _left_behind: int = 0
var _left_behind_now: int = 0
var _most: int = 0


func before_each() -> void:
	_table = own(ActorsScript.new()) as ActorsScript
	root.add_child(_table)
	_markers = own(MarkersScript.new()) as MarkersScript
	root.add_child(_markers)
	_grid = RoomGrid.new()
	_grid.size_to(Rect2(-8192.0, -8192.0, 16384.0, 16384.0))
	_grid.set_sealed(_grid.add_place(Rect2(-6000.0, -6000.0, 12000.0, 12000.0)), true)
	var holder := own(SubViewport.new()) as SubViewport
	holder.size = Vector2i(SCREEN)
	holder.disable_3d = true
	root.add_child(holder)
	_camera = Camera2D.new()
	holder.add_child(_camera)
	_camera.make_current()
	_party = PartyCameraScript.new()
	_party.follow(_camera)
	_split = SplitCameraScript.new()
	_one = ScreenViewsScript.new()
	_seats = 0
	_most_a_view = 0
	_outside = 0
	_left_behind = 0
	_left_behind_now = 0
	_most = 0
	for at in FOES:
		var foe := own(Node2D.new()) as Node2D
		root.add_child(foe)
		foe.position = at
		_table.set_node(_table.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY), foe)


func _wizard(at: Vector2, seat: int) -> Node2D:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.position = at
	var id: int = _table.open(ActorsScript.TEAM_WIZARDS, seat, seat)
	_table.set_node(id, node)
	_table.set_home(id, seat)
	_seats |= 1 << seat
	return node


## This machine's views as Feel takes them (`Feel._views_shown`): the split's while it draws, else
## the party camera's one picture.
func _views() -> ScreenViewsScript:
	if _split.views.count > 0:
		return _split.views
	var picture: Rect2 = _party.visible_rect()
	var zoom: float = _camera.zoom.x
	_one.set_single(picture.size * zoom, Transform2D(0.0, Vector2(zoom, zoom), 0.0, -picture.position * zoom), _seats)
	return _one


## A drawn frame as Feel steps it, then what it shows counted.
func _frame() -> void:
	_party.look(_table, _seats)
	_party.step(FRAME)
	_split.step(FRAME, _table, _seats, _camera, SCREEN)
	var views: ScreenViewsScript = _views()
	_markers.step(FRAME, _table, _grid, _seats, views)
	var wanted := PackedInt32Array()
	wanted.resize(ScreenViewsScript.VIEWS_MOST)
	var behind: bool = false
	for at in _markers.count:
		var view: int = views.view_of_id(_markers.view_id_of(at))
		var inside: bool = view >= 0 and views.cell_holds(view, _markers.position_of(at), 0.5)
		if _markers.is_going(at):
			behind = behind or not inside
			continue
		if not inside:
			_outside += 1
		if view >= 0:
			wanted[view] += 1
			_most_a_view = maxi(_most_a_view, wanted[view])
	_left_behind_now = _left_behind_now + 1 if behind else 0
	_left_behind = maxi(_left_behind, _left_behind_now)
	_most = maxi(_most, _markers.count)


func _frames(count: int) -> void:
	for i in count:
		_frame()


## The wanted markers now, and whether every view has one for every foe.
func _whole_markers() -> int:
	var whole: int = 0
	for at in _markers.count:
		if not _markers.is_going(at) and _markers.stage_of(at) == MarkersScript.STAGES:
			whole += 1
	return whole


func _check_frames(what: String) -> void:
	check_equal(_outside, 0, "%s: no wanted marker ever stood outside its own view's cell" % what)
	check(_most_a_view <= FOES.size(), "%s: never more wanted markers in a view than foes (%d)" % [what, _most_a_view])
	check(_left_behind <= GOING_FRAMES, "%s: one left behind shrinking out is gone within its looks (%d frames)" % [what, _left_behind])


## Two seats in one fight walk apart at a wizard's pace until the screen splits, and on.
func test_a_split_keeps_every_marker_in_its_own_cell() -> void:
	_wizard(Vector2(0.0, 0.0), 0)
	var walker: Node2D = _wizard(Vector2(1000.0, 0.0), 1)
	_frames(120)
	check_equal(_split.views.count, 0, "together: one picture")
	check_equal(_whole_markers(), FOES.size(), "a marker a foe")
	var split_at: int = -1
	for i in 2000:
		if split_at < 0:
			walker.position.x += 90.0 * FRAME
		_frame()
		if split_at < 0 and _split.views.count > 1:
			split_at = i
		if split_at >= 0 and i - split_at >= 120:
			break
	check(split_at >= 0 and _split.views.count == 2, "split in two")
	check_equal(_whole_markers(), FOES.size() * 2, "settled: each view a marker a foe")
	check(_most <= FOES.size() * 2 + FOES.size(), "never more markers than both views' and those handing over (%d)" % _most)
	_check_frames("a split")


## Split, then together at once (a portal): the merge.
func test_a_merge_keeps_every_marker_in_its_own_cell() -> void:
	_wizard(Vector2(0.0, 0.0), 0)
	var other: Node2D = _wizard(Vector2(2400.0, 0.0), 1)
	_frames(240)
	check_equal(_split.views.count, 2, "apart: split in two")
	check_equal(_whole_markers(), FOES.size() * 2, "each view a marker a foe")
	_outside = 0
	_most = 0
	other.position = Vector2(100.0, 0.0)
	_frames(180)
	check_equal(_split.views.count, 0, "merged: one picture")
	check_equal(_whole_markers(), FOES.size(), "a marker a foe")
	check_equal(_markers.count, FOES.size(), "and no other")
	check(_most <= FOES.size() * 2 + FOES.size(), "never more markers than both views' and those handing over (%d)" % _most)
	_check_frames("a merge")


## Three seats: seat 0 leaves seat 2's view, walks to seat 1 and joins its view.
func test_a_regroup_keeps_every_marker_in_its_own_cell() -> void:
	var walker: Node2D = _wizard(Vector2(-1500.0, 0.0), 0)
	_wizard(Vector2(1500.0, 0.0), 1)
	_wizard(Vector2(-1450.0, 0.0), 2)
	_frames(240)
	check_equal(_split.views.count, 2, "two views: seats 0 and 2, and seat 1")
	check_equal(_whole_markers(), FOES.size() * 2, "each view a marker a foe")
	_most = 0
	var most_views: int = 0
	for i in 900:
		if walker.position.x < 1450.0:
			walker.position.x += 360.0 * FRAME
		_frame()
		most_views = maxi(most_views, _split.views.count)
		check(_markers.count <= FOES.size() * (_split.views.count + 1), "frame %d: %d markers with %d views" % [i, _markers.count, _split.views.count])
		if _markers.count > FOES.size() * (_split.views.count + 1):
			break
	check_equal(most_views, 3, "seat 0 had a view of its own on the way")
	check_equal(_split.views.count, 2, "two views again: seat 2, and seats 0 and 1")
	check_equal(_whole_markers(), FOES.size() * 2, "each view a marker a foe")
	check_equal(_markers.count, FOES.size() * 2, "and no other")
	_check_frames("a regroup")
