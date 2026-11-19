extends "res://tests/support/suite.gd"
## Tests for the thin meter line (`hud/widgets/meter_line.gd`; owner, 2026-11-19): the first value
## drawn at once, a change eased by whole pixels over at least 3 frames to exactly its target, a
## sliver still a pixel, and `reset` drawing the next value at once again.

const MeterScript := preload("res://hud/widgets/meter_line.gd")

const WIDTH: float = 60.0


func _line() -> MeterScript:
	var line := MeterScript.new()
	line.size = Vector2(WIDTH, 3.0)
	root.add_child(own(line))
	return line


func test_the_first_value_is_drawn_at_once() -> void:
	var line: MeterScript = _line()
	line.set_value(50.0, 100.0)
	check_equal(line.target_pixels(), 30, "half of 60 px")
	check_equal(line.shown_pixels(), 30, "drawn at once: a line that appears starts where it is")


func test_a_change_eases_by_whole_pixels_over_at_least_three_frames() -> void:
	var line: MeterScript = _line()
	line.set_value(100.0, 100.0)
	line.set_value(10.0, 100.0)
	check_equal(line.target_pixels(), 6, "a tenth of 60 px")
	var seen: Array[int] = []
	for _frame in 30:
		line.step()
		seen.append(line.shown_pixels())
		if line.shown_pixels() == line.target_pixels():
			break
	check(seen.size() >= 3, "it took at least 3 frames, saw %s" % [seen])
	for i in range(1, seen.size()):
		check(seen[i] < seen[i - 1], "each frame it moves on down: %s" % [seen])
	check_equal(seen[seen.size() - 1], 6, "and ends on its target")
	line.set_value(100.0, 100.0)
	line.step()
	check(line.shown_pixels() > 6 and line.shown_pixels() < 60, "a refill eases up too, got %d" % line.shown_pixels())


func test_a_sliver_is_still_a_pixel_and_none_is_empty() -> void:
	var line: MeterScript = _line()
	line.set_value(0.1, 100.0)
	check_equal(line.target_pixels(), 1, "a sliver left shows")
	line.reset()
	line.set_value(0.0, 100.0)
	check_equal(line.shown_pixels(), 0, "none is empty, drawn at once after a reset")
	line.reset()
	line.set_value(5.0, 0.0)
	check_equal(line.shown_pixels(), 0, "no pool is an empty line")
