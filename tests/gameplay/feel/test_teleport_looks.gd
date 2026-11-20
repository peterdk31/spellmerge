extends "res://tests/support/suite.gd"
## Where a wizard teleported from the Y map left (the owner, 2026-11-19; gameplay/feel/teleport_looks.gd):
## a column of its light stands there and narrows away a look a frame (Smooth: at least 3 looks,
## each narrower, whole pixels), then is gone; each seat its own.

const EventsScript := preload("res://core/events/events.gd")
const TeleportLooksScript := preload("res://gameplay/feel/teleport_looks.gd")


func test_a_column_narrows_away_where_the_wizard_left() -> void:
	var bus := own(EventsScript.new()) as EventsScript
	var looks := own(TeleportLooksScript.new()) as TeleportLooksScript
	root.add_child(looks)
	looks.bind(bus)
	check(not looks.is_moving(), "nothing to draw yet")
	bus.wizard_teleported.emit(1, Vector2(100.4, 200.6), Vector2(900, 900))
	check_equal(looks.look_of(1), 0, "the widest look first, where it left")
	check_equal(looks.look_of(0), -1, "another seat draws nothing")
	var seen: Array[int] = [looks.look_of(1)]
	while looks.is_moving():
		looks.advance()
		seen.append(looks.look_of(1))
	check_equal(seen, [0, 1, 2, 3, 4, -1] as Array[int], "a look a frame, then gone")
	check(TeleportLooksScript.COLUMNS.size() >= 3, "at least 3 looks (Smooth)")
	for at in TeleportLooksScript.COLUMNS.size() - 1:
		check(TeleportLooksScript.COLUMNS[at + 1].x <= TeleportLooksScript.COLUMNS[at].x, "each look narrower or as narrow")
	var stepped: int = 0
	bus.wizard_teleported.emit(0, Vector2.ZERO, Vector2.ONE)
	looks.step(1.0 / TeleportLooksScript.FPS + 0.001)
	stepped = looks.look_of(0)
	check_equal(stepped, 1, "stepped at its frame rate")
