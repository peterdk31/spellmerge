extends "res://tests/support/suite.gd"
## The seed sweep's arguments and result line (tests/smoke/four_bot_sweep.gd; the sweep itself plays
## whole runs and is run by hand, never in a build).

const SweepScript := preload("res://tests/smoke/four_bot_sweep.gd")


func test_a_range_plays_every_seed_in_it() -> void:
	check_equal(SweepScript.seeds_of(PackedStringArray(["--seeds=3-6"])), PackedInt64Array([3, 4, 5, 6]), "--seeds=3-6")
	check_equal(SweepScript.seeds_of(PackedStringArray(["--seeds=6-3"])), PackedInt64Array([3, 4, 5, 6]), "--seeds=6-3")


func test_a_list_plays_its_seeds() -> void:
	check_equal(SweepScript.seeds_of(PackedStringArray(["--seeds=11,2,40"])), PackedInt64Array([11, 2, 40]), "--seeds=11,2,40")


func test_no_argument_plays_the_default_range() -> void:
	var seeds: PackedInt64Array = SweepScript.seeds_of(PackedStringArray())
	check_equal(seeds.size(), SweepScript.DEFAULT_LAST - SweepScript.DEFAULT_FIRST + 1, "how many")
	check_equal(seeds[0], SweepScript.DEFAULT_FIRST, "the first")


func test_seed_zero_and_words_are_left_out() -> void:
	check_equal(SweepScript.seeds_of(PackedStringArray(["--seeds=0,x,5"])), PackedInt64Array([5]), "0 (a random one) and a word")
	check_equal(SweepScript.seeds_of(PackedStringArray(["--seeds=0-2"])), PackedInt64Array([1, 2]), "a range from 0")


func test_the_result_line_gives_the_rate_and_the_lost_seeds() -> void:
	check_equal(SweepScript.result_line(40, PackedStringArray(["9", "21"])), "SWEEP RESULT: 2 of 40 seeds lost (5.0%): 9, 21", "two lost")
	check_equal(SweepScript.result_line(3, PackedStringArray()), "SWEEP RESULT: 0 of 3 seeds lost (0.0%)", "none lost")
