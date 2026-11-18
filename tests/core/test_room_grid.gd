extends "res://tests/support/suite.gd"
## The room grid (`RoomGrid`, the projectile manager's `grid()`; hit batch B1): its footprints and a
## solid shot's stones are the manager's state, kept by a snapshot and given back by its restore in
## place; its room layers (walls, mouths, holes) are not (connected biomes CB2: laid by whoever lays
## the room, from the room or the biome map), and what is worked out from both is set up again. The
## grid stays the same object through a restore and a run's start.
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


## A grid with walls, a hole, a footprint and a Wall card's stones, as `mgr` lays them.
func _laid_room(mgr: ManagerScript) -> int:
	mgr.set_bounds(ROOM)
	mgr.set_walls([Rect2(0.0, 0.0, 320.0, 8.0), Rect2(150.0, 60.0, 16.0, 40.0)] as Array[Rect2])
	mgr.set_holes([Rect2(240.0, 120.0, 32.0, 32.0)] as Array[Rect2])
	mgr.grid().add_mouth(Rect2(200.0, 16.0, 8.0, 32.0))
	mgr.set_footprint(5, Vector2(80.0, 150.0), Vector2(24.0, 16.0), 0.0)
	# A Wall card's stones: a still shot made solid, laid at its step.
	var stone: int = mgr.spawn(0, Vector2(100.0, 100.0), Vector2.ZERO, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 1, ManagerScript.MOTION_STILL)
	check(mgr.set_solid(stone, Vector2.RIGHT, 3, 8.0), "the stone shot is solid")
	mgr.step(DT)
	check(not mgr.line_clear(Vector2(100.0, 80.0), Vector2(100.0, 120.0)), "its stones stand in the grid")
	return stone


func _manager() -> ManagerScript:
	var mgr: ManagerScript = own(ManagerScript.new()) as ManagerScript
	mgr.events = own(EventsScript.new()) as EventsScript
	mgr.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	return mgr


func test_a_snapshot_keeps_the_room_grid_and_its_restore_gives_it_back_in_place() -> void:
	var mgr: ManagerScript = _manager()
	var stone: int = _laid_room(mgr)
	var grid: RoomGrid = mgr.grid()
	var laid: Dictionary = _members(grid)
	var slid: Vector2 = mgr.slide_body(Vector2(60.0, 150.0), Vector2(40.0, 0.0), 6.0)
	var snapshot := Snapshot.take({"projectiles": mgr})
	# What changes in play changed after the snapshot: the footprint went, the stones moved off.
	mgr.set_footprint(5, Vector2.ZERO, Vector2.ZERO, 0.0)
	check(mgr.move_shot(stone, Vector2(0.0, 40.0), DT), "the stones are moved")
	for _i in 3:
		mgr.step(DT)
	check(mgr.line_clear(Vector2(100.0, 80.0), Vector2(100.0, 120.0)), "the stones moved off")
	check(_members(grid) != laid, "the grid changed")
	var problems: PackedStringArray = snapshot.restore({"projectiles": mgr})
	check_equal(problems, PackedStringArray(), "restored without problems")
	check(mgr.grid() == grid, "the same grid, given back in place")
	check_equal(_members(grid), laid, "every member of the grid as it was")
	check_equal(mgr.slide_body(Vector2(60.0, 150.0), Vector2(40.0, 0.0), 6.0), slid, "a slide ends where it did")
	check(not mgr.line_clear(Vector2(100.0, 80.0), Vector2(100.0, 120.0)), "the stones stand where they did")
	check(mgr.is_hole(Vector2(250.0, 130.0)) and not mgr.line_clear(Vector2(158.0, 50.0), Vector2(158.0, 110.0)), "the hole and the wall are there")
	mgr.begin_run()
	check(mgr.grid() == grid, "a run's start keeps the same grid")
	check(mgr.line_clear(Vector2(158.0, 50.0), Vector2(158.0, 110.0)), "and starts it with no walls")


## The room's layers are not the snapshot's (connected biomes CB2): a restore leaves the walls, holes
## and mouths as whoever lays the room laid them, and the grid's own lists say so.
func test_the_rooms_layers_are_not_in_a_snapshot() -> void:
	var derived: PackedStringArray = StateWalk.listed(RoomGrid, "DERIVED")
	for member: String in ["_wall_cells", "_hole_cells", "_walk_cells", "_ground_cells", "_has_walls", "_has_holes", "_has_mouths", "_bounds"]:
		check(derived.has(member), "%s is DERIVED" % member)
	for member: String in ["_footprint_at", "_footprint_half", "_footprint_round", "_footprints_laid"]:
		check(not derived.has(member), "%s is state" % member)
	var mgr: ManagerScript = _manager()
	_laid_room(mgr)
	var snapshot := Snapshot.take({"projectiles": mgr})
	mgr.clear_walls()
	check_equal(snapshot.restore({"projectiles": mgr}), PackedStringArray(), "restored without problems")
	check(mgr.line_clear(Vector2(158.0, 50.0), Vector2(158.0, 110.0)), "a wall taken out after the snapshot is not laid by it")
	check(not mgr.is_hole(Vector2(250.0, 130.0)) and not mgr.grid().has_mouths(), "nor a hole or a mouth")
	check(not mgr.line_clear(Vector2(100.0, 80.0), Vector2(100.0, 120.0)), "the stones, play's state, are laid back")
	check(mgr.slide_body(Vector2(60.0, 150.0), Vector2(40.0, 0.0), 6.0) != Vector2(100.0, 150.0), "and the footprint")
