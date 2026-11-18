extends "res://tests/support/suite.gd"
## A cue's size (`CueBase.size_ref`, gameplay/feel/cue_size.gd; the owner, 2026-11-18: a blast
## sounds and looks as big as it is): how many times its own size it plays at, and what grows by it.
const CueSizeScript := preload("res://gameplay/feel/cue_size.gd")
const CueContextScript := preload("res://gameplay/feel/cue_context.gd")


func test_a_cue_grows_by_how_many_times_its_own_size_it_is() -> void:
	check_equal(CueSizeScript.factor(40.0, 40.0), 1.0, "at its own size, as made")
	check_equal(CueSizeScript.factor(40.0, 80.0), 2.0, "twice as big")
	check_equal(CueSizeScript.factor(0.0, 80.0), 1.0, "no size of its own: as made at any size")
	check_equal(CueSizeScript.factor(40.0, 0.0), 1.0, "played with no size: as made")
	check_equal(CueSizeScript.factor(40.0, 4000.0), CueSizeScript.MOST, "never more than MOST")
	check_equal(CueSizeScript.factor(40.0, 1.0), CueSizeScript.LEAST, "never less than LEAST")


func test_what_grows_with_it() -> void:
	check_equal(CueSizeScript.counts(1.0), 1.0, "as made at 1")
	check(CueSizeScript.counts(2.0) > CueSizeScript.seconds(2.0) and CueSizeScript.seconds(2.0) > 1.0, "more motes, lasting a little longer")
	check(CueSizeScript.shake(2.0) > 1.0 and CueSizeScript.shake(0.5) < 1.0, "a bigger shake and kick, a smaller smaller")
	check(CueSizeScript.pitch(2.0) < 1.0 and CueSizeScript.pitch(0.5) > 1.0, "a bigger one deeper")
	check_equal(CueSizeScript.volume(1.0), 0.0, "as loud as made at 1")
	check(is_equal_approx(CueSizeScript.volume(2.0), CueSizeScript.DB_PER_DOUBLING), "a doubling louder")
	check(CueSizeScript.volume(3.0) <= CueSizeScript.MOST_DB, "never past MOST_DB")


func test_a_contexts_counts_are_its_power_and_its_growth() -> void:
	var context: CueContextScript = CueContextScript.new()
	context.power = 1.5
	context.grow = 2.0
	check(is_equal_approx(context.count_times(), 1.5 * CueSizeScript.counts(2.0)), "power times the growth")
	var other: CueContextScript = CueContextScript.new()
	other.copy_from(context)
	check_equal(other.grow, 2.0, "a copy keeps its growth")
