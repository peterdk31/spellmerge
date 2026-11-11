extends "res://tests/support/suite.gd"
## The ground of bodies that cannot move (props W4, docs/milestones/props.md):
## `set_footprint(actor, centre, size, radius)` lays a box (or a circle) into a grid of its own over
## the wall grid's cells, the cells whose centres lie in it. Bodies that walk slide along it and
## cannot land on it (`slide_body`, `circle_blocked`); nothing else sees it: shots, rays, lines of
## sight and clipped segments pass over it, so a shot hits the body standing there as any other
## (a piercing one goes on). It is laid again in a new grid (`set_bounds`) and left alone by the
## walls (`set_walls`, `clear_walls`); overlapping ones are counted, and laying the same again
## changes nothing. The manager is stepped by hand.
##
## godot --headless --path . --script res://tests/core/test_projectiles_footprint.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const DT: float = 1.0 / 60.0
## The prop: actor 7, a 16 px box of ground centred at CENTRE.
const PROP: int = 7
const CENTRE: Vector2 = Vector2(200.0, 100.0)
const SIZE: Vector2 = Vector2(16.0, 16.0)
## A line across the box.
const ACROSS_FROM: Vector2 = Vector2(150.0, 100.0)
const ACROSS_TO: Vector2 = Vector2(250.0, 100.0)

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
	mgr.set_footprint(actor, centre, SIZE, 0.0)


func _lift(actor: int = PROP) -> void:
	mgr.set_footprint(actor, Vector2.ZERO, Vector2.ZERO, 0.0)


## A body of radius 6 walking from left of the box to right of it: where it ends.
func _walk() -> Vector2:
	return mgr.slide_body(Vector2(170.0, 100.0), Vector2(60.0, 0.0), 6.0)


func _blocks() -> bool:
	return _walk().x < 230.0


func test_it_blocks_bodies_that_walk_and_nothing_else() -> void:
	_lay()
	check_equal(mgr.footprint_of(PROP), Rect2(CENTRE - SIZE * 0.5, SIZE), "its box is kept")
	var stopped: Vector2 = _walk()
	check(stopped.x < 192.0 - 6.0 + 0.01 and stopped.x > 170.0, "a body walking at it stops short: %s" % stopped)
	check(mgr.circle_blocked(CENTRE, 2.0), "and cannot land on it")
	check(mgr.line_clear(ACROSS_FROM, ACROSS_TO), "a line of sight passes over it")
	check_equal(mgr.clip_to_walls(ACROSS_FROM, ACROSS_TO), ACROSS_TO, "a segment is not cut by it")
	check(mgr.ray(1, ACROSS_FROM, Vector2.RIGHT, 100.0) > 99.0, "nor a ray")
	_lift()
	check_equal(mgr.footprint_of(PROP), Rect2(), "lifted")
	check_equal(_walk(), Vector2(230.0, 100.0), "and the way is open")


func test_a_box_lays_the_cells_whose_centres_lie_in_it() -> void:
	# Cells of 8 px from the bounds' corner: x from 195 to 211 holds the centres 196 and 204.
	_lay(PROP, Vector2(203.0, 100.0))
	check(mgr.circle_blocked(Vector2(193.0, 100.0), 0.0), "the cell from 192 is laid (its centre 196 is in 195-211)")
	check(mgr.circle_blocked(Vector2(207.0, 100.0), 0.0), "and the one from 200")
	check(not mgr.circle_blocked(Vector2(210.0, 100.0), 0.0), "not the one from 208 (its centre 212 is past it)")


func test_a_circle_lays_the_cells_whose_centres_lie_in_it() -> void:
	mgr.set_footprint(PROP, Vector2(200.0, 100.0), Vector2.ZERO, 6.0)
	check(mgr.circle_blocked(Vector2(197.0, 97.0), 0.0) and mgr.circle_blocked(Vector2(203.0, 103.0), 0.0), "the four cells round its centre")
	check(not mgr.circle_blocked(Vector2(209.0, 100.0), 0.0), "not the next (its centre 212 is 12 px off)")
	check_equal(mgr.footprint_of(PROP), Rect2(194.0, 94.0, 12.0, 12.0), "its box is the circle's")


func test_it_is_laid_again_in_a_new_grid_and_the_walls_leave_it() -> void:
	_lay()
	mgr.set_walls([Rect2(0.0, 0.0, 640.0, 8.0)] as Array[Rect2])
	check(_blocks(), "new walls leave the ground")
	mgr.clear_walls()
	check(_blocks(), "and so does clearing them")
	mgr.set_bounds(Rect2(-100.0, -100.0, 840.0, 560.0))
	check(_blocks(), "new bounds: laid again in the new grid")
	_lift()
	check(not _blocks(), "and lifted from it")


func test_overlapping_ones_are_counted_and_laying_again_changes_nothing() -> void:
	_lay(1)
	_lay(2, CENTRE + Vector2(4.0, 0.0))
	_lift(1)
	check(_blocks(), "the other still blocks")
	_lift(2)
	check(not _blocks(), "both lifted")
	# A body made again from a snapshot lays what the snapshot's grid already holds.
	_lay()
	_lay()
	_lift()
	check(not _blocks(), "laid twice, one lift takes it all out")
	# More on one cell than a count holds: each takes out only what it counted.
	for actor in 260:
		_lay(actor)
	for actor in 260:
		_lift(actor)
	check(not _blocks(), "a crowded cell is open again when they are all gone")


func test_a_piercing_shot_hits_the_body_over_it_and_goes_on() -> void:
	_lay()
	for at: Vector2 in [CENTRE, Vector2(300.0, 100.0)]:
		var node := Node2D.new()
		node.name = "prop" if at == CENTRE else "behind"
		root.add_child(node)
		own(node)
		node.global_position = at
		mgr.add_target(node, 10.0, ManagerScript.LAYER_ENEMY, PROP if at == CENTRE else 2)
	var shot: int = mgr.spawn(1, Vector2(120.0, 100.0), Vector2(600.0, 0.0), 2.0, 2.0, ManagerScript.LAYER_ENEMY, 5)
	check(shot >= 0, "the shot was made")
	for i in 30:
		mgr.step(DT)
	check_equal(_hits, [[1, "prop"], [1, "behind"]], "it hit the prop and went on to the body behind")
	check_equal(mgr.wall_hits, 0, "it met no wall")
