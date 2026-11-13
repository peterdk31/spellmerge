extends "res://tests/support/suite.gd"
## The markers at the picture's edge for teammates out of it (gameplay/feel/teammate_markers.gd;
## owner, 2026-11-13): one for each wizard played on another machine that is out of this machine's
## picture, on the edge towards it, in its hat colour, and told apart when it is down.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_teammate_markers.gd

const MarkersScript := preload("res://gameplay/feel/teammate_markers.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

## This machine's picture: one screen from the world's corner.
const PICTURE: Rect2 = Rect2(0.0, 0.0, 640.0, 360.0)

var _table: ActorsScript
var _markers: MarkersScript


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
	_markers.step(_table, 0b0001, PICTURE, 1.0, 0.0)
	check_equal(_markers.count, 1, "one teammate is out of the picture")
	if _markers.count != 1:
		return
	check_equal(_markers.seat_of(0), 1, "seat 1's")
	check_equal(_markers.position_of(0), Vector2(640.0 - MarkersScript.INSET, 180.0), "at the right edge, level with it")
	check_equal(_markers.way_of(0), Vector2.RIGHT, "pointing its way")
	check(not _markers.is_down(0), "standing")
	check(PICTURE.has_point(_markers.position_of(0)), "inside the picture")


## The HUD's panels are in the screen's corners: a marker there would be hidden under one.
func test_a_marker_towards_a_corner_sits_clear_of_the_corner() -> void:
	_wizard(Vector2(320.0, 180.0), 0)
	_wizard(Vector2(5000.0, -3000.0), 2)
	_markers.step(_table, 0b0001, PICTURE, 1.0, 0.0)
	check_equal(_markers.count, 1, "a marker")
	if _markers.count == 1:
		check_equal(_markers.position_of(0), Vector2(640.0 - MarkersScript.CORNER.x, MarkersScript.CORNER.y), "at the inner corner of the top right corner's part")
		check(_markers.way_of(0).x > 0.0 and _markers.way_of(0).y < 0.0, "still pointing up and right, at its wizard")


func test_nobody_in_the_picture_and_none_of_this_machines_gets_one() -> void:
	_wizard(Vector2(100.0, 100.0), 0)
	_wizard(Vector2(500.0, 300.0), 1)
	_wizard(Vector2(3000.0, 100.0), 2)
	_markers.step(_table, 0b0101, PICTURE, 1.0, 0.0)
	check_equal(_markers.count, 0, "seat 1 is in the picture, and seats 0 and 2 are this machine's")
	_markers.step(_table, 0, PICTURE, 1.0, 0.0)
	check_equal(_markers.count, 0, "with no seat here the camera holds everyone: no markers")


func test_a_zoomed_out_picture_keeps_the_marker_as_far_from_its_edge_on_screen() -> void:
	_wizard(Vector2(640.0, 360.0), 0)
	_wizard(Vector2(9000.0, 360.0), 3)
	var wide := Rect2(0.0, 0.0, 1280.0, 720.0)
	_markers.step(_table, 0b0001, wide, 0.5, 0.0)
	check_equal(_markers.count, 1, "a marker")
	if _markers.count == 1:
		check_equal(_markers.position_of(0), Vector2(1280.0 - MarkersScript.INSET * 2.0, 360.0), "twice as far in the world at half the zoom")


func test_a_downed_teammates_marker_says_so_and_a_marker_goes_when_it_is_back() -> void:
	_wizard(Vector2(320.0, 180.0), 0)
	var friend: Node2D = _wizard(Vector2(320.0, 2000.0), 1, true)
	root.add_child(friend)
	_markers.step(_table, 0b0001, PICTURE, 1.0, 0.0)
	check(_markers.count == 1 and _markers.is_down(0), "the downed teammate's marker is a downed one")
	friend.global_position = Vector2(300.0, 200.0)
	_markers.step(_table, 0b0001, PICTURE, 1.0, 0.0)
	check_equal(_markers.count, 0, "in the picture again: no marker")
