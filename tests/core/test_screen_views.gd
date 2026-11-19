extends "res://tests/support/suite.gd"
## What each part of the screen shows while it is split (core/display/screen_views.gd; connected
## biomes CB6): the cell a screen point is in, the view showing a world point, the view holding a
## seat, the box of the world shown, and the views published on a viewport only while split.
const ScreenViewsScript := preload("res://core/display/screen_views.gd")
const VoronoiCellsScript := preload("res://gameplay/feel/voronoi_cells.gd")

const SCREEN := Vector2(640.0, 360.0)


## Two views, left and right halves, at zoom 1: the left shows the world round (0, 0), the right
## the world round (1000, 0), seats 0 and 1 (and 2 in the right one).
static func _two() -> ScreenViewsScript:
	var views := ScreenViewsScript.new()
	views.screen = SCREEN
	views.count = 2
	views.set_view(0, 0b001, Transform2D(0.0, Vector2.ONE, 0.0, Vector2(160.0, 180.0)), Vector2(160.0, 180.0))
	views.set_view(1, 0b110, Transform2D(0.0, Vector2.ONE, 0.0, Vector2(480.0, 180.0) - Vector2(1000.0, 0.0)), Vector2(480.0, 180.0))
	VoronoiCellsScript.new().fill(views)
	return views


func test_one_picture_is_one_view_of_the_whole_screen() -> void:
	var views := ScreenViewsScript.new()
	views.set_single(SCREEN, Transform2D(0.0, Vector2(0.5, 0.5), 0.0, Vector2(10.0, 20.0)), 0b0011)
	check_equal(views.count, 1, "one view")
	check(not views.is_split(), "not split")
	check_equal(views.corners(0), 4, "its cell is the screen")
	check_equal(views.view_at(Vector2(639.0, 359.0)), 0, "every point of the screen is in it")
	check_equal(views.view_at(Vector2(700.0, 10.0)), -1, "a point off the screen is in none")
	check_equal(views.view_of_seat(1), 0, "it holds its seats")
	check_equal(views.anchor[0], SCREEN * 0.5, "its anchor is the screen's middle")


func test_a_split_cuts_the_screen_along_the_bisector() -> void:
	var views: ScreenViewsScript = _two()
	check(views.is_split(), "split")
	check_equal(views.view_at(Vector2(319.0, 100.0)), 0, "left of the middle: the left view")
	check_equal(views.view_at(Vector2(321.0, 300.0)), 1, "right of it: the right view")
	check_equal(views.view_of_seat(2), 1, "seat 2 is in the right view")
	check_equal(views.view_showing(Vector2(20.0, 30.0)), 0, "a world point by the left view's wizards is shown in it")
	check_equal(views.view_showing(Vector2(1010.0, -40.0)), 1, "one by the right view's in it")
	check_equal(views.view_showing(Vector2(500.0, 0.0)), -1, "a point between them, in the other's half of the screen, in none")
	check_equal(views.view_showing(Vector2(170.0, 0.0), 20.0), 0, "a margin reaches past a cell's edge")
	check_equal(views.view_showing(Vector2(150.0, 0.0), -20.0), -1, "a negative margin keeps that far inside")


func test_the_world_shown_is_the_box_round_every_cell() -> void:
	var box: Rect2 = _two().world_box()
	check(box.has_point(Vector2(-150.0, -170.0)) and box.has_point(Vector2(1150.0, 170.0)), "it reaches from the left view's corner to the right view's (%s)" % box)
	check(is_equal_approx(box.size.y, 360.0), "one screen high at zoom 1")


func test_views_are_published_on_a_viewport_only_while_split() -> void:
	var holder := own(SubViewport.new()) as SubViewport
	root.add_child(holder)
	check(ScreenViewsScript.on(holder) == null, "nothing published: one picture")
	var views: ScreenViewsScript = _two()
	ScreenViewsScript.publish(holder, views)
	check(ScreenViewsScript.on(holder) == views, "published")
	ScreenViewsScript.withdraw(holder)
	check(ScreenViewsScript.on(holder) == null, "withdrawn")
