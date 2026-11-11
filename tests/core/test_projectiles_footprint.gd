extends "res://tests/support/suite.gd"
## Footprints (props W4, docs/milestones/props.md): `set_footprint(actor, rect)` lays the cells
## whose centres lie in a body's rectangle into the wall grid, where bodies slide along it and shots
## and rays end on it as on any wall, and laid again when the walls are; a shot that meets it hits
## the body over it first (its hurt circle covers it); the body's own shots, rays and staff leave
## it, and a sweep's line to the body is not hidden by it. Counts on a cell never touch the room's
## mark, however many things lie there. The manager is stepped by hand.
##
## godot --headless --path . --script res://tests/core/test_projectiles_footprint.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const DT: float = 1.0 / 60.0
## The prop: actor 7, a 16 px footprint centred at CENTRE, and a hurt circle round it that covers it.
const PROP: int = 7
const CENTRE: Vector2 = Vector2(200.0, 100.0)
const SIZE: Vector2 = Vector2(16.0, 16.0)
const RADIUS: float = 17.0

var bus: EventsScript
var mgr: ManagerScript
## Every projectile_hit as [caster, target name].
var _hits: Array = []


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.events = bus
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	root.add_child(mgr)
	_hits.clear()
	bus.projectile_hit.connect(func(caster: int, target: Node, _at: Vector2, _tag: int, _shot: int) -> void: _hits.append([caster, String(target.name)]))


func _lay(actor: int = PROP, centre: Vector2 = CENTRE) -> void:
	mgr.set_footprint(actor, Rect2(centre - SIZE * 0.5, SIZE))


## A body over the footprint, a target owned by `actor`.
func _body(name: String, at: Vector2, radius: float, actor: int) -> Node2D:
	var node := Node2D.new()
	node.name = name
	root.add_child(node)
	own(node)
	node.global_position = at
	mgr.add_target(node, radius, ManagerScript.LAYER_ENEMY, actor)
	return node


func test_it_blocks_bodies_lines_and_circles_until_it_is_lifted() -> void:
	_lay()
	check_equal(mgr.footprint_of(PROP), Rect2(CENTRE - SIZE * 0.5, SIZE), "its rectangle is kept")
	check(not mgr.line_clear(Vector2(150.0, 100.0), Vector2(250.0, 100.0)), "a line through it is blocked")
	check(mgr.line_clear(Vector2(150.0, 130.0), Vector2(250.0, 130.0)), "one past it is not")
	check(mgr.circle_blocked(CENTRE, 2.0), "a circle on it is blocked")
	var stopped: Vector2 = mgr.slide_body(Vector2(170.0, 100.0), Vector2(60.0, 0.0), 6.0)
	check(stopped.x < 192.0 - 6.0 + 0.01 and stopped.x > 170.0, "a body walking at it stops short: %s" % stopped)
	mgr.set_footprint(PROP, Rect2())
	check_equal(mgr.footprint_of(PROP), Rect2(), "lifted")
	check(mgr.line_clear(Vector2(150.0, 100.0), Vector2(250.0, 100.0)), "and the way is open")
	check_equal(mgr.slide_body(Vector2(170.0, 100.0), Vector2(60.0, 0.0), 6.0), Vector2(230.0, 100.0), "for bodies too")


func test_it_lays_the_cells_whose_centres_lie_in_it() -> void:
	# Cells of 8 px from the bounds' corner: x from 192 to 208 covers the cells 24 and 25 exactly;
	# moved 3 px, the centres 196 and 204 are still the only ones in it, and 2 cells are laid.
	_lay(PROP, Vector2(203.0, 100.0))
	check(not mgr.line_clear(Vector2(193.0, 80.0), Vector2(193.0, 120.0)), "the cell from 192 is laid (its centre 196 is in 195-211)")
	check(not mgr.line_clear(Vector2(207.0, 80.0), Vector2(207.0, 120.0)), "and the one from 200")
	check(mgr.line_clear(Vector2(210.0, 80.0), Vector2(210.0, 120.0)), "not the one from 208 (its centre 212 is past it)")


func test_laying_it_again_changes_nothing() -> void:
	# A body made again from a snapshot lays what the snapshot's grid already holds (props W4).
	_lay()
	_lay()
	mgr.set_footprint(PROP, Rect2())
	check(mgr.line_clear(Vector2(150.0, 100.0), Vector2(250.0, 100.0)), "one lift takes it all out")


func test_it_is_laid_again_when_the_walls_are() -> void:
	_lay()
	mgr.set_walls([Rect2(0.0, 0.0, 640.0, 8.0)] as Array[Rect2])
	check(not mgr.line_clear(Vector2(150.0, 100.0), Vector2(250.0, 100.0)), "after new walls")
	mgr.set_bounds(Rect2(-100.0, -100.0, 840.0, 560.0))
	check(not mgr.line_clear(Vector2(150.0, 100.0), Vector2(250.0, 100.0)), "after new bounds, in the new grid")
	mgr.set_footprint(PROP, Rect2())
	check(mgr.line_clear(Vector2(150.0, 100.0), Vector2(250.0, 100.0)), "and lifted from it")


func test_footprints_on_one_cell_are_counted_and_never_reach_the_rooms_mark() -> void:
	# Two that overlap: lifting one leaves the other.
	_lay(1)
	_lay(2, CENTRE + Vector2(4.0, 0.0))
	mgr.set_footprint(1, Rect2())
	check(not mgr.line_clear(Vector2(150.0, 100.0), Vector2(250.0, 100.0)), "the other still blocks")
	mgr.set_footprint(2, Rect2())
	check(mgr.line_clear(Vector2(150.0, 100.0), Vector2(250.0, 100.0)), "both lifted")
	# More things on one cell than its count holds, on a room wall: the count stops at its most,
	# and lifting them all leaves the room wall as it was and nothing else.
	mgr.set_walls([Rect2(192.0, 96.0, 8.0, 8.0)] as Array[Rect2])
	for actor in ManagerScript.ROOM_CELL + 10:
		_lay(actor)
	for actor in ManagerScript.ROOM_CELL + 10:
		mgr.set_footprint(actor, Rect2())
	var image: Image = mgr.wall_image()
	check_equal(image.get_pixel(24, 12).r, 1.0, "the room wall is still there")
	check(mgr.line_clear(Vector2(150.0, 100.0), Vector2(191.0, 100.0)), "and nothing more")
	check(mgr.line_clear(Vector2(201.0, 100.0), Vector2(250.0, 100.0)), "on either side")


func test_a_shot_that_meets_it_hits_the_body_over_it_first() -> void:
	_lay()
	_body("prop", CENTRE, RADIUS, PROP)
	# Fast enough to cross the footprint in one step (3,000 px/s: 50 px a step), and piercing: it
	# hits the body, then ends on the footprint as on a wall.
	var shot: int = mgr.spawn(1, Vector2(120.0, 100.0), Vector2(3000.0, 0.0), 2.0, 2.0, ManagerScript.LAYER_ENEMY, 5)
	for i in 6:
		mgr.step(DT)
	check_equal(_hits, [[1, "prop"]], "the body was hit")
	check(not mgr.is_alive(shot), "and the shot ended on its footprint")
	check_equal(mgr.wall_hits, 1, "a wall end")


func test_its_bodys_own_shots_and_rays_leave_it() -> void:
	_lay()
	var prop: Node2D = _body("prop", CENTRE, RADIUS, PROP)
	var far: Node2D = _body("far", Vector2(320.0, 100.0), 8.0, 2)
	var own_shot: int = mgr.spawn(PROP, CENTRE, Vector2(600.0, 0.0), 2.0, 2.0, ManagerScript.LAYER_ENEMY, 0, 0)
	var stranger: int = mgr.spawn(3, CENTRE + Vector2(0.0, 4.0), Vector2(600.0, 0.0), 2.0, 2.0, ManagerScript.LAYER_ENEMY, 0, 0)
	check(own_shot >= 0 and stranger >= 0, "shots born on a footprint are made (only a room wall refuses them)")
	# Each spares the body it is cast from, as the spell runtime has it.
	mgr.exclude(own_shot, prop)
	mgr.exclude(stranger, prop)
	for i in 20:
		mgr.step(DT)
	check(_hits.has([PROP, "far"]), "its own shot flew out and on: %s" % [_hits])
	check(not _hits.has([PROP, "prop"]), "sparing its body")
	check(not mgr.is_alive(stranger), "a shot of another born in it ends at once")
	check(mgr.ray(PROP, CENTRE, Vector2.RIGHT, 60.0, 0, ManagerScript.LAYER_ENEMY, 0, 0.0, prop) > 50.0, "its own ray walks out")
	check(mgr.ray(3, CENTRE, Vector2.RIGHT, 60.0, 0, ManagerScript.LAYER_ENEMY, 0, 0.0, prop) < 1.0, "another's gets nowhere")
	check(mgr.ray(3, Vector2(150.0, 100.0), Vector2.RIGHT, 100.0) < 42.5, "and one from outside stops at it")
	check(is_instance_valid(prop) and is_instance_valid(far), "both bodies stand")


func test_its_bodys_staff_is_not_cut_by_it_and_others_are() -> void:
	_lay()
	var tip: Vector2 = CENTRE + Vector2(20.0, 0.0)
	check_equal(mgr.clip_to_walls(CENTRE, tip, PROP), tip, "its own staff reaches out of it")
	check_equal(mgr.place_caster(PROP, CENTRE, CENTRE, tip), tip, "as the Caster places it each step")
	check_equal(mgr.clip_to_walls(CENTRE, tip, -1), CENTRE, "a segment of nobody's is cut where it starts")
	check(mgr.clip_to_walls(Vector2(150.0, 100.0), CENTRE, 3).x < 193.0, "and another's at its edge")


func test_a_sweep_sees_the_body_over_it() -> void:
	_lay()
	_body("prop", CENTRE, RADIUS, PROP)
	var found: int = mgr.sweep(3, Vector2(170.0, 100.0), Vector2.RIGHT, 1, -PI, PI, 40.0, ManagerScript.ACTOR_LAYERS)
	check_equal(found, 1, "the body is found though its centre lies past its footprint's edge")
	mgr.set_walls([Rect2(180.0, 80.0, 8.0, 40.0)] as Array[Rect2])
	_lay()
	check_equal(mgr.sweep(3, Vector2(170.0, 100.0), Vector2.RIGHT, 1, -PI, PI, 40.0, ManagerScript.ACTOR_LAYERS), 0, "a room wall between still hides it")
