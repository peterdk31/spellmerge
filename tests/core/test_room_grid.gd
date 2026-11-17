extends "res://tests/support/suite.gd"
## The room grid (`RoomGrid`, the projectile manager's `grid()`; hit batch B1): its walls, holes,
## footprints and a solid shot's stones are the manager's state, kept by a snapshot and given back by
## its restore in place, and the grid stays the same object through a restore and a run's start.
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const DT: float = 1.0 / 60.0
const ROOM: Rect2 = Rect2(0.0, 0.0, 320.0, 200.0)


## Every script member of `grid`, as bytes.
func _members(grid: RoomGrid) -> Dictionary:
	var out: Dictionary = {}
	for prop: Dictionary in grid.get_property_list():
		if (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			out[prop["name"]] = var_to_bytes(grid.get(prop["name"]))
	return out


func test_a_snapshot_keeps_the_room_grid_and_its_restore_gives_it_back_in_place() -> void:
	var mgr: ManagerScript = own(ManagerScript.new()) as ManagerScript
	mgr.events = own(EventsScript.new()) as EventsScript
	mgr.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	mgr.set_bounds(ROOM)
	mgr.set_walls([Rect2(0.0, 0.0, 320.0, 8.0), Rect2(150.0, 60.0, 16.0, 40.0)] as Array[Rect2])
	mgr.set_holes([Rect2(240.0, 120.0, 32.0, 32.0)] as Array[Rect2])
	mgr.set_footprint(5, Vector2(80.0, 150.0), Vector2(24.0, 16.0), 0.0)
	# A Wall card's stones: a still shot made solid, laid at its step.
	var stone: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2.ZERO, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 1, ManagerScript.MOTION_STILL)
	check(mgr.set_solid(stone, Vector2.RIGHT, 3, 8.0), "the stone shot is solid")
	mgr.step(DT)
	check(not mgr.line_clear(Vector2(100.0, 80.0), Vector2(100.0, 120.0)), "its stones stand in the grid")
	var grid: RoomGrid = mgr.grid()
	var laid: Dictionary = _members(grid)
	var slid: Vector2 = mgr.slide_body(Vector2(60.0, 150.0), Vector2(40.0, 0.0), 6.0)
	var snapshot := Snapshot.take({"projectiles": mgr})
	# Everything changed after the snapshot.
	mgr.clear_walls()
	mgr.set_footprint(5, Vector2.ZERO, Vector2.ZERO, 0.0)
	check(_members(grid) != laid, "the grid changed")
	var problems: PackedStringArray = snapshot.restore({"projectiles": mgr})
	check_equal(problems, PackedStringArray(), "restored without problems")
	check(mgr.grid() == grid, "the same grid, given back in place")
	check_equal(_members(grid), laid, "every member of the grid as it was")
	check_equal(mgr.slide_body(Vector2(60.0, 150.0), Vector2(40.0, 0.0), 6.0), slid, "a slide ends where it did")
	check(mgr.is_hole(Vector2(250.0, 130.0)) and not mgr.line_clear(Vector2(158.0, 50.0), Vector2(158.0, 110.0)), "the hole and the wall are back")
	mgr.begin_run()
	check(mgr.grid() == grid, "a run's start keeps the same grid")
	check(mgr.line_clear(Vector2(158.0, 50.0), Vector2(158.0, 110.0)), "and starts it with no walls")
