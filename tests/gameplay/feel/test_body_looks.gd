extends "res://tests/support/suite.gd"
## A body shows the hit looks of at most `PER_BODY` hits of one staff a frame (gameplay/feel/
## body_looks.gd; owner, 2026-11-07): each staff counts apart, the next frame counts again, and a
## frame of many bodies keeps every body's count when the table grows.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_body_looks.gd

const BodyLooks := preload("res://gameplay/feel/body_looks.gd")


func _shown(looks: BodyLooks, body: int, group: int, hits: int) -> int:
	var shown: int = 0
	for i in hits:
		if looks.take(body, group):
			shown += 1
	return shown


func test_a_body_shows_a_few_hits_of_a_staff_a_frame() -> void:
	var looks := BodyLooks.new()
	check_equal(_shown(looks, 1001, 0, 1000), BodyLooks.PER_BODY, "of a thousand hits in a frame, %d show" % BodyLooks.PER_BODY)
	check_equal(_shown(looks, 2002, 0, 2), 2, "another body counts its own")


func test_each_staff_counts_apart() -> void:
	var looks := BodyLooks.new()
	_shown(looks, 1001, 0, 50)
	check_equal(_shown(looks, 1001, 5, 1), 1, "a lone cast of another staff on the same body still shows")


func test_the_next_frame_counts_again() -> void:
	var looks := BodyLooks.new()
	_shown(looks, 1001, 0, 50)
	looks.new_frame()
	check_equal(_shown(looks, 1001, 0, 50), BodyLooks.PER_BODY, "a new frame shows the body's looks again")


func test_a_frame_of_many_bodies_keeps_each_count() -> void:
	var looks := BodyLooks.new()
	var bodies: int = BodyLooks.START_SIZE * 2
	for body in bodies:
		_shown(looks, 5000 + body * 977, body % 3, 2)
	var wrong: int = 0
	for body in bodies:
		# Each has shown 2: one more shows, then none.
		if _shown(looks, 5000 + body * 977, body % 3, 5) != BodyLooks.PER_BODY - 2:
			wrong += 1
	check_equal(wrong, 0, "after the table grew, every one of %d bodies kept its count" % bodies)
