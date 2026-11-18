extends "res://tests/support/suite.gd"
## A bridge's mouth in the room grid (connected biomes CB2, docs/milestones/connected-biomes.md,
## "Cells"; `RoomGrid.MOUTH_CELL`): shots stop at it, on the GDScript's hit pass and the native
## kernel's alike, so an AI's line of fire is not clear through it; sight sees through it; a wizard's walk goes through it and any other body's stops
## there, by who drives the body, never its team; what stands or runs up stops at it; a cut opens a
## room's lip and the dark between pieces is a wall. Real actors for the walks (the actor fixture).
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

const DT: float = 1.0 / 60.0
const ROOM: Rect2 = Rect2(0.0, 0.0, 320.0, 200.0)
## The mouth: one cell deep, across the whole room, at x 160 to 168.
const MOUTH: Rect2 = Rect2(160.0, 0.0, 8.0, 200.0)


func _manager() -> ManagerScript:
	var mgr: ManagerScript = own(ManagerScript.new()) as ManagerScript
	mgr.events = own(EventsScript.new()) as EventsScript
	mgr.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	mgr.set_bounds(ROOM)
	mgr.grid().add_mouth(MOUTH)
	return mgr


func test_a_mouth_is_its_own_mark_and_stays_apart_from_the_stones_count() -> void:
	var mgr: ManagerScript = _manager()
	var grid: RoomGrid = mgr.grid()
	check(grid.has_mouths() and grid.has_walls(), "a mouth lies in the wall grid")
	check(grid.is_mouth(Vector2(164.0, 100.0)) and not grid.is_mouth(Vector2(150.0, 100.0)), "on its cells only")
	check_equal(grid.cell_at(Vector2(164.0, 100.0)), RoomGrid.MOUTH_CELL, "its mark alone")
	check_equal(RoomGrid.SOLID_MOST & RoomGrid.MOUTH_CELL, 0, "the stones' count never reaches the mouth's bit")
	check_equal(RoomGrid.SOLID_MOST & RoomGrid.ROOM_CELL, 0, "nor a wall's")
	# A Wall card's stones piled on a mouth cell: counted up to SOLID_MOST, the mouth kept.
	var cells := PackedInt32Array()
	for i in RoomGrid.SOLID_MOST + 5:
		cells = grid.lay_solid(Vector2(164.0, 100.0), Vector2(164.0, 100.0), 2.0, cells)
	check_equal(grid.cell_at(Vector2(164.0, 100.0)), RoomGrid.MOUTH_CELL | RoomGrid.SOLID_MOST, "the count stops below the mark")
	grid.rebuild_derived()
	check_equal(grid.cell_at(Vector2(164.0, 100.0)), RoomGrid.MOUTH_CELL, "a rebuild takes the stones out and keeps the mouth")


func test_a_shot_stops_at_a_mouth_on_either_side() -> void:
	for native: bool in [false, true]:
		var mgr: ManagerScript = _manager()
		mgr.native = native
		var shot: int = mgr.spawn(0, Vector2(50.0, 100.0), Vector2(240.0, 0.0), 3.0)
		var below: int = mgr.spawn(0, Vector2(200.0, 100.0), Vector2(240.0, 0.0), 3.0)
		for _i in 30:
			mgr.step(DT)
		check(not mgr.is_alive(shot), "native %s: a shot that reaches a mouth ends there" % native)
		check(mgr.is_alive(below), "native %s: a shot past it flies on" % native)
		check_equal(mgr.wall_hits, 1, "native %s: as at a wall" % native)


func test_sight_sees_through_a_mouth_and_a_line_of_fire_does_not() -> void:
	var mgr: ManagerScript = _manager()
	var grid: RoomGrid = mgr.grid()
	check(grid.wall_hit(Vector2(100.0, 100.0), Vector2(250.0, 100.0)) >= 0.0, "a shot's way meets the mouth")
	check(not grid.line_clear(Vector2(100.0, 100.0), Vector2(250.0, 100.0)), "so an AI's line of fire is not clear through it")
	check(grid.sight_clear(Vector2(100.0, 100.0), Vector2(250.0, 100.0)), "sight goes through it")
	grid.add_wall(Rect2(200.0, 80.0, 8.0, 40.0))
	check(not grid.sight_clear(Vector2(100.0, 100.0), Vector2(250.0, 100.0)), "a wall beyond it still blocks sight")
	check(grid.sight_clear(Vector2(100.0, 40.0), Vector2(250.0, 40.0)), "past the wall it sees on")
	var plain: RoomGrid = RoomGrid.new()
	plain.size_to(ROOM)
	plain.add_wall(Rect2(200.0, 80.0, 8.0, 40.0))
	check_equal(plain.sight_clear(Vector2(100.0, 100.0), Vector2(250.0, 100.0)), plain.line_clear(Vector2(100.0, 100.0), Vector2(250.0, 100.0)), "with no mouths sight is the line of fire")


func test_what_stands_or_runs_up_stops_at_a_mouth() -> void:
	var grid: RoomGrid = _manager().grid()
	check(grid.circle_blocked(Vector2(164.0, 100.0), 4.0), "nothing stands on a mouth")
	check(not grid.circle_blocked(Vector2(140.0, 100.0), 4.0), "beside it, it does")
	check(absf(grid.clear_run(Vector2(100.0, 100.0), Vector2.RIGHT, 200.0) - 60.0) < 0.01, "a run-up stops at it")


func test_a_slide_goes_through_a_mouth_only_past_mouths() -> void:
	for native: bool in [false, true]:
		WallSlide.use_native(native)
		var grid: RoomGrid = _manager().grid()
		check_equal(grid.slide_body(Vector2(100.0, 100.0), Vector2(100.0, 0.0), 6.0), Vector2(154.0, 100.0), "native %s: a body that minds it stops at it" % WallSlide.native_on())
		check_equal(grid.slide_body(Vector2(100.0, 100.0), Vector2(100.0, 0.0), 6.0, false, true), Vector2(200.0, 100.0), "native %s: a wizard's walk goes through" % WallSlide.native_on())
		check_equal(grid.slide_body(Vector2(100.0, 100.0), Vector2(100.0, 0.0), 6.0, true, false), Vector2(154.0, 100.0), "native %s: a crossing move of a free body stops too" % WallSlide.native_on())
	WallSlide.use_native(true)


func test_a_cut_opens_a_lip_and_the_dark_between_pieces_is_a_wall() -> void:
	var mgr: ManagerScript = _manager()
	var grid: RoomGrid = mgr.grid()
	grid.add_wall(Rect2(40.0, 0.0, 16.0, 200.0))
	grid.add_hole(Rect2(80.0, 0.0, 16.0, 200.0))
	grid.cut(Rect2(32.0, 64.0, 144.0, 64.0))
	check(grid.line_clear(Vector2(30.0, 96.0), Vector2(150.0, 96.0)), "the wall is cut through")
	check(not grid.is_hole(Vector2(88.0, 96.0)) and grid.is_hole(Vector2(88.0, 20.0)), "the hole only where it was cut")
	check(not grid.is_mouth(Vector2(164.0, 96.0)) and grid.is_mouth(Vector2(164.0, 20.0)), "and the mouth")
	check(not grid.line_clear(Vector2(30.0, 20.0), Vector2(70.0, 20.0)), "the wall beside the cut stands")
	grid.wall_outside([Rect2(0.0, 0.0, 200.0, 200.0)] as Array[Rect2])
	check(not grid.line_clear(Vector2(150.0, 96.0), Vector2(250.0, 96.0)), "the dark past the pieces is a wall")
	check_equal(grid.cell_at(Vector2(250.0, 96.0)), RoomGrid.ROOM_CELL, "a room wall's mark")


## By who drives the body (decision "Who passes a mouth"): a seat's controller walks through, a free
## body's (no seat) stops, whatever its team.
func test_a_wizard_crosses_a_mouth_and_a_free_enemy_does_not() -> void:
	var world := Fixture.new(root)
	world.projectiles.set_bounds(ROOM)
	world.projectiles.grid().add_mouth(MOUTH)
	var wizard_mind := Fixture.Scripted.new()
	wizard_mind.team = ActorsScript.TEAM_WIZARDS
	wizard_mind.seat = 0
	var wizard: Actor = world.actor(Vector2(100.0, 60.0), [&"mover"], wizard_mind)
	var enemy_mind := Fixture.Scripted.new()
	enemy_mind.team = ActorsScript.TEAM_WIZARDS
	var free: Actor = world.actor(Vector2(100.0, 140.0), [&"mover"], enemy_mind)
	check(wizard.passes_mouths() and not free.passes_mouths(), "the seat's body passes, the free one does not")
	wizard_mind.move = Vector2.RIGHT
	enemy_mind.move = Vector2.RIGHT
	for _i in 40:
		for body: Actor in [wizard, free]:
			body.tick_step(Fixture.STEP)
	check(wizard.global_position.x > MOUTH.end.x + 20.0, "the wizard walked through the mouth: %s" % wizard.global_position)
	check(absf(free.global_position.x - (MOUTH.position.x - free.wall_radius())) < 0.01, "the free body stopped at it, its team a wizard's: %s" % free.global_position)
	world.free_all()
