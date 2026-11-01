extends "res://tests/support/suite.gd"
## `AISight` (gameplay/ai/sight.gd, owner 2026-11-01): what an AI sees of walls. A room wall and a
## Wall card's solid shot both block the line; a long line is walked to its end; the detour way
## is free and leads to where the goal is in view; with no projectile manager nothing blocks.
##
## godot --headless --path . --script res://tests/gameplay/ai/test_ai_sight.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

var mgr: ManagerScript


func before_each() -> void:
	var bus := own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.events = bus
	mgr.set_bounds(Rect2(0.0, 0.0, 1280.0, 720.0))
	root.add_child(mgr)


func test_a_room_wall_blocks_the_line() -> void:
	check(AISight.line_clear(mgr, Vector2(100.0, 100.0), Vector2(300.0, 100.0)), "an open room: clear")
	mgr.set_walls([Rect2(192.0, 64.0, 16.0, 80.0)] as Array[Rect2])
	check(not AISight.line_clear(mgr, Vector2(100.0, 100.0), Vector2(300.0, 100.0)), "a wall across the line blocks it")
	check(AISight.line_clear(mgr, Vector2(100.0, 200.0), Vector2(300.0, 200.0)), "a line past its end is clear")


func test_a_wall_cards_solid_shot_blocks_the_line_while_it_lives() -> void:
	var slot: int = mgr.spawn(0, Vector2(200.0, 100.0), Vector2.ZERO, 0.5, 5.0, ManagerScript.LAYER_ENEMY, 1 << 30, 1, ManagerScript.MOTION_STILL)
	check(mgr.set_solid(slot, Vector2.DOWN, 5, 9.0), "a solid shot stands")
	check(not AISight.line_clear(mgr, Vector2(100.0, 100.0), Vector2(300.0, 100.0)), "a spell wall blocks the line, as it stops shots")
	for i in 40:
		mgr.step(1.0 / 60.0)
	check(AISight.line_clear(mgr, Vector2(100.0, 100.0), Vector2(300.0, 100.0)), "gone with its shot")


func test_a_long_line_is_walked_to_its_end() -> void:
	mgr.set_walls([Rect2(1100.0, 0.0, 16.0, 720.0)] as Array[Rect2])
	check(not AISight.line_clear(mgr, Vector2(20.0, 20.0), Vector2(1200.0, 700.0)), "a wall far along a long diagonal still blocks it")
	check(AISight.line_clear(mgr, Vector2(20.0, 20.0), Vector2(1000.0, 700.0)), "and a long clear line is clear, not cut short")


func test_the_detour_is_free_and_leads_into_view() -> void:
	# A wall straight between: the way round goes up or down, and from its end the goal shows.
	mgr.set_walls([Rect2(192.0, 60.0, 16.0, 80.0)] as Array[Rect2])
	var from := Vector2(150.0, 100.0)
	var goal := Vector2(300.0, 100.0)
	var way: Vector2 = AISight.detour(mgr, from, goal, 100.0)
	check(is_equal_approx(way.length(), 1.0), "a unit way: %s" % way)
	check(absf(way.y) > 0.5, "it goes round, not into the wall: %s" % way)
	check(AISight.line_clear(mgr, from, from + way * 100.0), "its first steps are free")
	check(AISight.line_clear(mgr, from + way * 100.0, goal), "and the goal is in view from there")


func test_without_a_manager_nothing_blocks() -> void:
	check(AISight.line_clear(null, Vector2.ZERO, Vector2(500.0, 0.0)), "clear")
	check(AISight.detour(null, Vector2.ZERO, Vector2(10.0, 0.0), 40.0).is_equal_approx(Vector2.RIGHT), "straight at the goal")
