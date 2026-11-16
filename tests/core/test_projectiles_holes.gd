extends "res://tests/support/suite.gd"
## The projectile manager's holes (hub rework HR-H1, docs/milestones/hub-rework.md, "Holes" 1 and
## 2): a third grid over the wall cells, laid from rectangles (`set_holes`) or a room's hole bodies
## (`add_hole_body`), cleared with the walls (`set_bounds`, `clear_walls`, `set_walls`). A walk slides
## against the ground and the holes merged (`slide_body`), a crossing move against the ground alone;
## shots, rays, the walls' checks and a body's room to stand (`circle_blocked`) never see a hole; a
## wall over a hole wins (`is_hole`). The manager is stepped by hand.
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const DT: float = 1.0 / 60.0
## A crack four cells wide across the room, from x 200 to 232.
const CRACK: Rect2 = Rect2(200.0, 0.0, 32.0, 360.0)

var bus: EventsScript
var mgr: ManagerScript


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.events = bus
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	root.add_child(mgr)


func _crack() -> void:
	mgr.set_holes([CRACK] as Array[Rect2])


func test_a_hole_is_where_its_rectangle_is() -> void:
	check(not mgr.has_holes(), "a room starts with none")
	_crack()
	check(mgr.has_holes(), "the crack is laid")
	check(mgr.is_hole(Vector2(201.0, 100.0)) and mgr.is_hole(Vector2(231.0, 100.0)), "its cells are holes")
	check(not mgr.is_hole(Vector2(199.0, 100.0)) and not mgr.is_hole(Vector2(233.0, 100.0)), "the ground beside it is not")
	check(mgr.is_hole(Vector2(-20.0, 100.0)), "outside the grid is a hole in a room with holes (HR-H2, question 9)")
	var none := own(ManagerScript.new()) as ManagerScript
	none.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	check(not none.is_hole(Vector2(-20.0, 100.0)), "and none in a room with none")


## Outside the room is the void in a room with holes (HR-H2, question 9): the bounds' margin round
## the room becomes holes; a room with none is left as it is.
func test_outside_the_room_is_a_hole() -> void:
	var grid := own(ManagerScript.new()) as ManagerScript
	grid.set_bounds(Rect2(-32.0, -32.0, 704.0, 424.0))
	grid.set_holes_outside(Rect2(0.0, 0.0, 640.0, 360.0))
	check(not grid.is_hole(Vector2(-10.0, 100.0)), "no holes: the margin is left open")
	grid.set_holes([Rect2(200.0, 0.0, 32.0, 360.0)] as Array[Rect2])
	grid.set_holes_outside(Rect2(0.0, 0.0, 640.0, 360.0))
	check(grid.is_hole(Vector2(-10.0, 100.0)) and grid.is_hole(Vector2(650.0, 370.0)), "the margin is the void")
	check(not grid.is_hole(Vector2(4.0, 100.0)), "the room's own edge cell is ground")
	check(not grid.walk_clear(Vector2(20.0, 100.0), Vector2(-20.0, 100.0)), "a walk off the room meets the void")


## Where a body stands on the ground (HR-H2): the place itself when clear, else the nearest cell
## clear of walls, props' ground and holes; `circle_blocked` with holes on sees a hole.
func test_the_nearest_ground() -> void:
	var grid := own(ManagerScript.new()) as ManagerScript
	grid.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	grid.set_holes([Rect2(200.0, 0.0, 32.0, 360.0)] as Array[Rect2])
	check(grid.circle_blocked(Vector2(216.0, 100.0), 6.0, true), "a circle over the crack is blocked with holes on")
	check(not grid.circle_blocked(Vector2(216.0, 100.0), 6.0), "and not without")
	check_equal(grid.nearest_ground(Vector2(150.0, 100.0), 6.0), Vector2(150.0, 100.0), "clear ground is itself")
	var left: Vector2 = grid.nearest_ground(Vector2(203.0, 100.0), 6.0)
	check(not grid.circle_blocked(left, 6.0, true) and left.x < 200.0, "beside the lip it came from: %s" % left)
	var right: Vector2 = grid.nearest_ground(Vector2(229.0, 100.0), 6.0)
	check(not grid.circle_blocked(right, 6.0, true) and right.x > 232.0, "the other lip from the other side: %s" % right)
	check_equal(grid.nearest_ground(Vector2(203.0, 100.0), 6.0), left, "the same every time")


## The floor marks' mask (HR-H2): with holes asked for, a hole is masked as a wall is.
func test_the_wall_image_masks_holes_when_asked() -> void:
	var grid := own(ManagerScript.new()) as ManagerScript
	grid.set_bounds(Rect2(0.0, 0.0, 64.0, 64.0))
	grid.set_holes([Rect2(16.0, 16.0, 8.0, 8.0)] as Array[Rect2])
	check_equal(grid.wall_image().get_pixel(2, 2).r, 0.0, "walls alone: the hole is open")
	check(grid.wall_image(true).get_pixel(2, 2).r > 0.9, "with holes: masked")


func test_a_walk_stops_at_the_lip_and_a_crossing_goes_over() -> void:
	_crack()
	var at := Vector2(150.0, 100.0)
	var walked: Vector2 = mgr.slide_body(at, Vector2(120.0, 0.0), 6.0)
	check(absf(walked.x - 194.0) < 0.01 and walked.y == 100.0, "a walk stops with its circle at the lip: %s" % walked)
	check_equal(mgr.slide_body(at, Vector2(120.0, 0.0), 6.0, true), Vector2(270.0, 100.0), "a crossing move goes over it")
	check_equal(mgr.slide_body(at, Vector2(0.0, 120.0), 6.0), Vector2(150.0, 220.0), "a walk beside it is free")


func test_walls_still_stop_a_crossing_and_a_wall_over_a_hole_wins() -> void:
	mgr.set_walls([Rect2(208.0, 80.0, 16.0, 40.0)] as Array[Rect2])
	_crack()
	check(not mgr.is_hole(Vector2(212.0, 100.0)), "the wall's cells are a wall, not a hole")
	check(mgr.is_hole(Vector2(212.0, 200.0)), "the crack goes on past the wall")
	var crossed: Vector2 = mgr.slide_body(Vector2(150.0, 100.0), Vector2(120.0, 0.0), 6.0, true)
	check(absf(crossed.x - 202.0) < 0.01, "a crossing move stops at the wall in the crack: %s" % crossed)


func test_a_wall_cards_stones_over_a_hole_are_a_wall_while_they_stand() -> void:
	_crack()
	var slot: int = mgr.spawn(0, Vector2(216.0, 100.0), Vector2.ZERO, 1.0, 5.0, ManagerScript.LAYER_ENEMY, 1 << 30, 1, ManagerScript.MOTION_STILL)
	check(mgr.set_solid(slot, Vector2.DOWN, 5, 9.0), "the still shot becomes solid")
	check(not mgr.is_hole(Vector2(216.0, 100.0)), "the stones over the crack are a wall")
	var crossed: Vector2 = mgr.slide_body(Vector2(150.0, 100.0), Vector2(120.0, 0.0), 6.0, true)
	check(crossed.x < 216.0 - 5.0, "a dash stops at the stones: %s" % crossed)
	for i in 70:
		mgr.step(DT)
	check(mgr.is_hole(Vector2(216.0, 100.0)), "once they are gone the hole is back")
	check_equal(mgr.slide_body(Vector2(150.0, 100.0), Vector2(120.0, 0.0), 6.0, true), Vector2(270.0, 100.0), "and a dash crosses it")


func test_holes_are_cleared_with_the_walls_and_the_bounds() -> void:
	_crack()
	mgr.clear_walls()
	check(not mgr.has_holes() and not mgr.is_hole(Vector2(216.0, 100.0)), "clear_walls takes the holes out")
	check_equal(mgr.slide_body(Vector2(150.0, 100.0), Vector2(120.0, 0.0), 6.0), Vector2(270.0, 100.0), "a walk crosses where the crack was")
	_crack()
	mgr.set_walls([Rect2(0.0, 0.0, 8.0, 8.0)] as Array[Rect2])
	check(not mgr.has_holes(), "set_walls replaces the holes too (they are laid after it)")
	_crack()
	mgr.set_bounds(Rect2(0.0, 0.0, 800.0, 400.0))
	check(not mgr.has_holes() and not mgr.is_hole(Vector2(216.0, 100.0)), "new bounds start with none")
	check_equal(mgr.slide_body(Vector2(150.0, 100.0), Vector2(120.0, 0.0), 6.0), Vector2(270.0, 100.0), "and walk on the ground alone")


func test_a_footprint_and_a_hole_share_the_walking_grid() -> void:
	# A prop's ground laid over the crack and taken away again leaves the crack whole, and the ground
	# laid where there is no hole goes with it.
	_crack()
	mgr.set_footprint(3, Vector2(216.0, 100.0), Vector2(48.0, 16.0), 0.0)
	mgr.set_footprint(3, Vector2.ZERO, Vector2.ZERO, 0.0)
	var walked: Vector2 = mgr.slide_body(Vector2(150.0, 100.0), Vector2(120.0, 0.0), 6.0)
	check(absf(walked.x - 194.0) < 0.01, "the crack still stops a walk: %s" % walked)
	check_equal(mgr.slide_body(Vector2(150.0, 100.0), Vector2(120.0, 0.0), 6.0, true), Vector2(270.0, 100.0), "and the ground beside it is gone")
	# Ground kept while the holes are cleared still stops a walk.
	mgr.set_footprint(4, Vector2(300.0, 100.0), Vector2(16.0, 16.0), 0.0)
	mgr.set_holes([] as Array[Rect2])
	var stopped: Vector2 = mgr.slide_body(Vector2(250.0, 100.0), Vector2(100.0, 0.0), 6.0)
	check(absf(stopped.x - 282.0) < 0.01, "the prop's ground stops a walk with no holes left: %s" % stopped)


func test_a_footprint_laid_before_new_bounds_is_walked_round_in_them() -> void:
	_crack()
	mgr.set_footprint(4, Vector2(300.0, 100.0), Vector2(16.0, 16.0), 0.0)
	mgr.set_bounds(Rect2(0.0, 0.0, 800.0, 400.0))
	var stopped: Vector2 = mgr.slide_body(Vector2(250.0, 100.0), Vector2(100.0, 0.0), 6.0)
	check(absf(stopped.x - 282.0) < 0.01, "the ground is laid again in the new grid: %s" % stopped)


func test_shots_sight_and_standing_never_see_a_hole() -> void:
	_crack()
	check(mgr.line_clear(Vector2(150.0, 100.0), Vector2(300.0, 100.0)), "a line of sight crosses it")
	check_equal(mgr.clip_to_walls(Vector2(150.0, 100.0), Vector2(300.0, 100.0)), Vector2(300.0, 100.0), "a ray is not cut by it")
	check(mgr.ground_clear(Vector2(150.0, 100.0), Vector2(300.0, 100.0)), "it is not a prop's ground")
	check_equal(mgr.clear_run(Vector2(150.0, 100.0), Vector2.RIGHT, 150.0), 150.0, "a run-up crosses it (a dash does)")
	check(not mgr.circle_blocked(Vector2(216.0, 100.0), 6.0), "a teleport's back-off does not mind it")
	var shot: int = mgr.spawn(1, Vector2(150.0, 100.0), Vector2(300.0, 0.0), 2.0)
	for i in 20:
		mgr.step(DT)
	check(mgr.is_alive(shot), "a shot flies over it")
	check(mgr.get_position_of(shot).x > 232.0, "to the far side: %s" % mgr.get_position_of(shot))


func test_walk_clear_sees_holes_and_ground() -> void:
	check(mgr.walk_clear(Vector2(150.0, 100.0), Vector2(300.0, 100.0)), "an empty room is clear")
	_crack()
	check(not mgr.walk_clear(Vector2(150.0, 100.0), Vector2(300.0, 100.0)), "a walk across the crack is not")
	check(mgr.walk_clear(Vector2(150.0, 100.0), Vector2(150.0, 300.0)), "a walk beside it is")
	mgr.set_footprint(3, Vector2(150.0, 200.0), Vector2(16.0, 16.0), 0.0)
	check(not mgr.walk_clear(Vector2(150.0, 100.0), Vector2(150.0, 300.0)), "a prop's ground stands in it too")
	mgr.set_walls([Rect2(100.0, 50.0, 8.0, 8.0)] as Array[Rect2])
	check(mgr.walk_clear(Vector2(50.0, 54.0), Vector2(190.0, 54.0)), "walls are the line's own check (`line_clear`), not this one")


func test_a_room_bodys_shapes_are_laid_as_holes() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = RoomBase.HOLE_LAYER
	body.position = Vector2(200.0, 0.0)
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(32.0, 360.0)
	shape.shape = box
	shape.position = Vector2(16.0, 180.0)
	body.add_child(shape)
	root.add_child(body)
	mgr.add_hole_body(body)
	check(mgr.is_hole(Vector2(201.0, 100.0)) and mgr.is_hole(Vector2(231.0, 300.0)), "its rectangle is a hole")
	check(not mgr.is_hole(Vector2(199.0, 100.0)) and not mgr.is_hole(Vector2(233.0, 100.0)), "and only it")
	body.free()


func test_touches_hole_is_a_circles_overlap() -> void:
	check(not mgr.touches_hole(Vector2(195.0, 100.0), 6.0), "no holes, no touch")
	_crack()
	check(mgr.touches_hole(Vector2(195.0, 100.0), 6.0), "a circle reaching 1 px over the lip")
	check(not mgr.touches_hole(Vector2(194.0, 100.0), 6.0), "one only touching the lip is not over it")
	check(not mgr.touches_hole(Vector2(150.0, 100.0), 6.0), "one far off")
	mgr.set_walls([Rect2(200.0, 80.0, 8.0, 40.0)] as Array[Rect2])
	mgr.set_holes([CRACK] as Array[Rect2])
	check(not mgr.touches_hole(Vector2(195.0, 100.0), 6.0), "a wall over the lip's cells wins")
