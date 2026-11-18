extends "res://tests/support/suite.gd"
## The markers at the screen's edge for teammates out of every view (gameplay/feel/teammate_markers.gd;
## owner, 2026-11-13; connected biomes CB6, decision 28): one for each wizard played on another
## machine that is in none of this machine's views, on the edge towards it, in its hat colour, and
## told apart when it is down. Places are screen pixels.
const MarkersScript := preload("res://gameplay/feel/teammate_markers.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")
const VoronoiCellsScript := preload("res://gameplay/feel/voronoi_cells.gd")

## This machine's picture: one screen from the world's corner.
const PICTURE: Rect2 = Rect2(0.0, 0.0, 640.0, 360.0)

var _table: ActorsScript
var _markers: MarkersScript


## One picture showing `picture` (world pixels) at `zoom`.
static func _one(picture: Rect2, zoom: float = 1.0) -> ScreenViewsScript:
	var views := ScreenViewsScript.new()
	views.set_single(picture.size * zoom, Transform2D(0.0, Vector2(zoom, zoom), 0.0, -picture.position * zoom), 0b0001)
	return views


func before_each() -> void:
	_table = own(ActorsScript.new()) as ActorsScript
	root.add_child(_table)
	_markers = own(MarkersScript.new()) as MarkersScript
	root.add_child(_markers)


## Seat `seat`'s own wizard at `at` (an Actor with `down`, a plain body without).
func _wizard(at: Vector2, seat: int, down: bool = false) -> Node2D:
	var node: Node2D = Actor.new() if down else Node2D.new()
	own(node)
	if down:
		(node as Actor).set_down(true)
	else:
		root.add_child(node)
	node.position = at
	var id: int = _table.open(ActorsScript.TEAM_WIZARDS, seat, seat)
	_table.set_node(id, node)
	_table.set_home(id, seat)
	return node


func test_a_teammate_out_of_the_picture_gets_a_marker_on_the_edge_towards_it() -> void:
	_wizard(Vector2(320.0, 180.0), 0)
	_wizard(Vector2(2000.0, 180.0), 1)
	_markers.step(_table, 0b0001, _one(PICTURE), 0.0)
	check_equal(_markers.count, 1, "one teammate is out of the picture")
	if _markers.count != 1:
		return
	check_equal(_markers.seat_of(0), 1, "seat 1's")
	check_equal(_markers.position_of(0), Vector2(640.0 - MarkersScript.INSET, 180.0), "at the right edge, level with it")
	check_equal(_markers.way_of(0), Vector2.RIGHT, "pointing its way")
	check(not _markers.is_down(0), "standing")
	check(PICTURE.has_point(_markers.position_of(0)), "inside the picture")


## The HUD's panels take no part (owner, 2026-11-13): a marker towards a corner sits in the corner,
## at the edge, and is drawn over the panels.
func test_a_marker_towards_a_corner_sits_in_the_corner() -> void:
	_wizard(Vector2(320.0, 180.0), 0)
	# Off the top right corner, on the line through the corner of the inset edge.
	var half: Vector2 = PICTURE.size * 0.5 - Vector2.ONE * MarkersScript.INSET
	_wizard(Vector2(320.0, 180.0) + Vector2(half.x, -half.y) * 10.0, 2)
	_markers.step(_table, 0b0001, _one(PICTURE), 0.0)
	check_equal(_markers.count, 1, "a marker")
	if _markers.count == 1:
		var corner := Vector2(640.0 - MarkersScript.INSET, MarkersScript.INSET)
		check(_markers.position_of(0).is_equal_approx(corner), "in the top right corner, not kept clear of it (%s)" % _markers.position_of(0))
		check(_markers.way_of(0).x > 0.0 and _markers.way_of(0).y < 0.0, "pointing up and right, at its wizard")


func test_feel_draws_the_markers_over_the_hud() -> void:
	check(MarkersScript.LAYER > 10, "the markers' layer is over the HUD's (layer 10)")


func test_nobody_in_the_picture_and_none_of_this_machines_gets_one() -> void:
	_wizard(Vector2(100.0, 100.0), 0)
	_wizard(Vector2(500.0, 300.0), 1)
	_wizard(Vector2(3000.0, 100.0), 2)
	_markers.step(_table, 0b0101, _one(PICTURE), 0.0)
	check_equal(_markers.count, 0, "seat 1 is in the picture, and seats 0 and 2 are this machine's")
	_markers.step(_table, 0, _one(PICTURE), 0.0)
	check_equal(_markers.count, 0, "with no seat here the camera holds everyone: no markers")


func test_a_zoomed_out_picture_keeps_the_marker_as_far_from_its_edge_on_screen() -> void:
	_wizard(Vector2(640.0, 360.0), 0)
	_wizard(Vector2(9000.0, 360.0), 3)
	var wide := Rect2(0.0, 0.0, 1280.0, 720.0)
	_markers.step(_table, 0b0001, _one(wide, 0.5), 0.0)
	check_equal(_markers.count, 1, "a marker")
	if _markers.count == 1:
		check_equal(_markers.position_of(0), Vector2(640.0 - MarkersScript.INSET, 180.0), "as far from the screen's edge at half the zoom")


func test_a_downed_teammates_marker_says_so_and_a_marker_goes_when_it_is_back() -> void:
	_wizard(Vector2(320.0, 180.0), 0)
	var friend: Node2D = _wizard(Vector2(320.0, 2000.0), 1, true)
	root.add_child(friend)
	_markers.step(_table, 0b0001, _one(PICTURE), 0.0)
	check(_markers.count == 1 and _markers.is_down(0), "the downed teammate's marker is a downed one")
	friend.global_position = Vector2(300.0, 200.0)
	_markers.step(_table, 0b0001, _one(PICTURE), 0.0)
	check_equal(_markers.count, 0, "in the picture again: no marker")


## Two views side by side (a split), each a half of the screen at zoom 1: the left one shows the
## world round `left` and the right one the world round `right`, their anchors at the halves' middles.
static func _two(left: Vector2, right: Vector2) -> ScreenViewsScript:
	var views := ScreenViewsScript.new()
	views.screen = PICTURE.size
	views.count = 2
	var anchors: Array[Vector2] = [Vector2(160.0, 180.0), Vector2(480.0, 180.0)]
	var worlds: Array[Vector2] = [left, right]
	for view in 2:
		views.set_view(view, 1 << view, Transform2D(0.0, Vector2.ONE, 0.0, anchors[view] - worlds[view]), anchors[view])
	VoronoiCellsScript.new().fill(views)
	return views


## Split (CB6): a teammate any view shows needs no marker; one in none gets it at the screen's
## edge, from the view nearest it.
func test_a_teammate_in_another_view_needs_no_marker_and_one_in_none_gets_one() -> void:
	_wizard(Vector2(0.0, 0.0), 0)
	_wizard(Vector2(5000.0, 0.0), 1)
	var friend: Node2D = _wizard(Vector2(5040.0, 10.0), 2)
	var views: ScreenViewsScript = _two(Vector2(0.0, 0.0), Vector2(5000.0, 0.0))
	_markers.step(_table, 0b0011, views, 0.0)
	check_equal(_markers.count, 0, "seat 2 stands in the right view's cell: no marker")
	friend.global_position = Vector2(5000.0, 2000.0)
	_markers.step(_table, 0b0011, views, 0.0)
	check_equal(_markers.count, 1, "seat 2 in no view: a marker")
	if _markers.count == 1:
		check_equal(_markers.position_of(0), Vector2(480.0, 360.0 - MarkersScript.INSET), "at the bottom edge, below the right view's wizard")
		check_equal(_markers.way_of(0), Vector2.DOWN, "pointing down, its way")
