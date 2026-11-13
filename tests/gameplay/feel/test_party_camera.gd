extends "res://tests/support/suite.gd"
## Whose wizards Feel's party camera holds (gameplay/feel/party_camera.gd; owner, 2026-11-13):
## the ones of this machine's seats, each seat's own body and the actor it drives, and everyone's
## when no seat here has a body. How it zooms and eases with a whole party is checked in the game
## (tests/gameplay/coop/test_coop.gd).
##
## godot --headless --path . --script res://tests/gameplay/feel/test_party_camera.gd

const PartyCameraScript := preload("res://gameplay/feel/party_camera.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

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
