extends "res://tests/support/suite.gd"
## Whose wizards Feel's party camera holds (gameplay/feel/party_camera.gd; owner, 2026-11-13):
## the ones of this machine's seats, each seat's own body and the actor it drives, and everyone's
## when no seat here has a body. How it zooms and eases with a whole party is checked in the game
## (tests/gameplay/coop/test_coop.gd).
const PartyCameraScript := preload("res://gameplay/feel/party_camera.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const CloseFoesScript := preload("res://gameplay/feel/close_foes.gd")

var _table: ActorsScript
var _party: PartyCameraScript
var _camera: Camera2D


func before_each() -> void:
	_table = own(ActorsScript.new()) as ActorsScript
	root.add_child(_table)
	_camera = own(Camera2D.new()) as Camera2D
	root.add_child(_camera)
	_party = PartyCameraScript.new()
	_party.follow(_camera)


## A body at `at`: seat `seat`'s own wizard, or with -1 an actor no seat drives.
func _body(at: Vector2, seat: int = -1) -> int:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.global_position = at
	var id: int = _table.open(ActorsScript.TEAM_WIZARDS if seat >= 0 else ActorsScript.TEAM_ENEMIES, maxi(seat, 0), seat)
	_table.set_node(id, node)
	if seat >= 0:
		_table.set_home(id, seat)
	return id


func test_it_holds_only_this_machines_seats() -> void:
	_body(Vector2(100.0, 100.0), 0)
	_body(Vector2(2000.0, 900.0), 1)
	_party.look(_table, 0b0001)
	check_equal(_party.target_position, Vector2(100.0, 100.0), "seat 0 plays here: the camera is on its wizard")
	check_equal(_party.target_zoom, PartyCameraScript.MAX_ZOOM, "and no zoom out for the wizard played elsewhere")
	_party.look(_table, 0b0010)
	check_equal(_party.target_position, Vector2(2000.0, 900.0), "seat 1 plays here: on its wizard")


func test_two_seats_on_one_machine_share_the_picture() -> void:
	_body(Vector2(100.0, 100.0), 0)
	_body(Vector2(900.0, 100.0), 1)
	_body(Vector2(5000.0, 5000.0), 2)
	_party.look(_table, 0b0011)
	check_equal(_party.target_position, Vector2(500.0, 100.0), "between the two played here")
	check(_party.target_zoom < PartyCameraScript.MAX_ZOOM, "zoomed out to hold both (%f)" % _party.target_zoom)
	check(_party.visible_rect().has_area(), "a picture")
	_party.snap()
	check(_party.visible_rect().has_point(Vector2(100.0, 100.0)) and _party.visible_rect().has_point(Vector2(900.0, 100.0)), "both are in it")
	check(not _party.visible_rect().has_point(Vector2(5000.0, 5000.0)), "the third machine's wizard need not be")


func test_with_no_seat_here_it_holds_everyone() -> void:
	_body(Vector2(100.0, 100.0), 0)
	_body(Vector2(500.0, 300.0), 1)
	_party.look(_table, 0)
	check_equal(_party.target_position, Vector2(300.0, 200.0), "nobody plays here (a recording): everyone is held")
	_party.look(_table, 0b1000)
	check_equal(_party.target_position, Vector2(300.0, 200.0), "this machine's seat has no wizard yet: everyone is held")


func test_it_holds_the_actor_a_seat_here_drives_too() -> void:
	var home: int = _body(Vector2(100.0, 100.0), 0)
	var puppet: int = _body(Vector2(300.0, 100.0))
	_body(Vector2(900.0, 900.0), 1)
	_table.set_driver(puppet, ActorsScript.TEAM_WIZARDS, 0)
	check_equal([_table.home_of_seat(0), _table.actor_of_seat(0)], [home, puppet], "the seat drives another actor than its own body")
	_party.look(_table, 0b0001)
	check_equal(_party.target_position, Vector2(200.0, 100.0), "its own body and the actor it drives are both held")


func test_a_seat_joining_here_is_eased_to_and_never_out_of_the_picture() -> void:
	_body(Vector2(100.0, 100.0), 0)
	_body(Vector2(700.0, 100.0), 1)
	_party.look(_table, 0b0001)
	check_equal(_camera.position, Vector2(100.0, 100.0), "the first view is jumped to")
	_party.look(_table, 0b0011)
	_party.step(0.016)
	check(_camera.position.x > 100.0 and _camera.position.x < 400.0, "the camera eases towards both (%f)" % _camera.position.x)
	check(_party.visible_rect().has_point(Vector2(700.0, 100.0)) and _party.visible_rect().has_point(Vector2(100.0, 100.0)), "and both are in the picture meanwhile")


func test_a_new_room_is_jumped_to() -> void:
	var id: int = _body(Vector2(100.0, 100.0), 0)
	_party.look(_table, 0)
	(_table.node_of(id) as Node2D).global_position = Vector2(800.0, 500.0)
	_party.room_entered()
	_party.look(_table, 0)
	check_equal(_camera.position, Vector2(800.0, 500.0), "no easing across a new room")


# --- Close foes (the owner, 2026-11-19) ------------------------------------------------------------

## A foe within reach of a wizard is framed with it; one far off is not.
func test_a_close_foe_is_framed_with_the_wizard() -> void:
	_body(Vector2(100.0, 100.0), 0)
	_body(Vector2(100.0, 100.0 + CloseFoesScript.REACH - 10.0))
	_body(Vector2(100.0 + CloseFoesScript.REACH * 3.0, 100.0))
	var foes := CloseFoesScript.new()
	foes.find(_table, null)
	check_equal(foes.count, 1, "only the foe within reach is close")
	_party.look(_table, 0b0001)
	var alone: float = _party.target_zoom
	_party.look(_table, 0b0001, foes)
	check(_party.target_zoom < alone, "zoomed out for the foe (%f < %f)" % [_party.target_zoom, alone])
	_party.snap()
	var picture: Rect2 = _party.visible_rect()
	check(picture.has_point(Vector2(100.0, 100.0)) and picture.has_point(Vector2(100.0, 100.0 + CloseFoesScript.REACH - 10.0)), "the wizard and the foe are both in the picture")


## In a sealed fight every foe of the room is framed, but never past the widest zoom, and the
## wizards always stay in the picture.
func test_a_sealed_rooms_foes_are_framed_down_to_the_widest_zoom_and_the_wizards_stay_in() -> void:
	var grid := RoomGrid.new()
	grid.size_to(Rect2(-4096.0, -4096.0, 8192.0, 8192.0))
	var room: int = grid.add_place(Rect2(-2048.0, -2048.0, 4096.0, 4096.0))
	grid.set_sealed(room, true)
	_body(Vector2(0.0, 0.0), 0)
	_body(Vector2(1800.0, 0.0))
	var foes := CloseFoesScript.new()
	foes.find(_table, grid)
	check_equal(foes.count, 1, "a sealed room's foe is close however far")
	grid.set_sealed(room, false)
	foes.find(_table, grid)
	check_equal(foes.count, 0, "unsealed, past reach, it is not")
	grid.set_sealed(room, true)
	foes.find(_table, grid)
	_party.look(_table, 0b0001, foes)
	check_equal(_party.target_zoom, PartyCameraScript.MIN_ZOOM, "zoomed out no further than the widest")
	_party.snap()
	check(_party.visible_rect().grow(-PartyCameraScript.CAMERA_MARGIN + 1.0).has_point(Vector2.ZERO), "the wizard stays in, its margin kept")


## A foe in another place (behind a wall, in the next room) is not framed.
func test_a_foe_in_another_room_is_not_framed() -> void:
	var grid := RoomGrid.new()
	grid.size_to(Rect2(-1024.0, -1024.0, 2048.0, 2048.0))
	grid.add_place(Rect2(-512.0, -256.0, 512.0, 512.0))
	grid.add_place(Rect2(32.0, -256.0, 512.0, 512.0))
	_body(Vector2(-40.0, 0.0), 0)
	_body(Vector2(80.0, 0.0))
	var foes := CloseFoesScript.new()
	foes.find(_table, grid)
	check_equal(foes.count, 0, "the foe beyond the wall is not close")


## A foe coming close eases the picture out, never in one jump (docs/STYLE.md, "Smooth").
func test_a_foe_coming_close_eases_the_zoom() -> void:
	_body(Vector2(100.0, 100.0), 0)
	var foes := CloseFoesScript.new()
	foes.find(_table, null)
	_party.look(_table, 0b0001, foes)
	_party.snap()
	var before: float = _camera.zoom.x
	_body(Vector2(100.0, 100.0 + CloseFoesScript.REACH - 4.0))
	foes.find(_table, null)
	_party.look(_table, 0b0001, foes)
	var goal: float = _party.target_zoom
	check(goal < before, "it heads out (%f < %f)" % [goal, before])
	_party.step(1.0 / 60.0)
	var first: float = _camera.zoom.x
	check(first < before and first > goal, "the first frame moves only part of the way (%f between %f and %f)" % [first, before, goal])
	check(before - first < (before - goal) * 0.25, "a small step, not a jump")


## The foes' part of the box is cut down to fit, keeping the wizards' box whole.
func test_fit_around_keeps_the_inner_box() -> void:
	var inner := Rect2(0.0, 0.0, 100.0, 50.0)
	var framed := Rect2(-300.0, 0.0, 500.0, 50.0)
	var cut: Rect2 = PartyCameraScript.fit_around(inner, framed, Vector2(300.0, 1000.0))
	check(cut.encloses(inner), "the wizards' box kept whole")
	check(is_equal_approx(cut.size.x, 300.0), "cut to the most it may be: %s" % cut)
	check(is_equal_approx(cut.position.x, -150.0) and is_equal_approx(cut.end.x, 150.0), "each side in proportion: %s" % cut)
	check_equal(PartyCameraScript.fit_around(inner, framed, Vector2(50.0, 50.0)), inner, "no room: the wizards' box alone")
