extends "res://tests/support/suite.gd"
## The wall-clock helper of the tests that time the machine (tests/support/wall_clock.gd): the
## fastest of several runs, and a run's cost as a multiple of a reference run beside it. Its own
## work is CPU work, never a wait on the clock: a wait that is cut off overshoots on a busy machine,
## and this file runs in the parallel suite like any other.
const WallClock := preload("res://tests/support/wall_clock.gd")


## The GDScript reference `times` times over.
static func _references(times: int) -> void:
	for i in times:
		WallClock.gdscript_reference()


func test_the_fastest_run_counts() -> void:
	var sizes: Array[int] = [12, 1, 12]
	var next: Array[int] = [0]
	var one: int = WallClock.fastest_usec(func() -> void: _references(1), 3)
	var best: int = WallClock.fastest_usec(func() -> void:
		_references(sizes[next[0]])
		next[0] += 1, 3)
	check_equal(next[0], 3, "run three times")
	check(best < one * 6, "the fastest of the three, the small one (%d us; one reference %d us)" % [best, one])


func test_work_twice_the_reference_is_about_two_references() -> void:
	for reference: Callable in [WallClock.gdscript_reference, WallClock.native_reference]:
		var twice := func() -> void:
			reference.call()
			reference.call()
		var timed: WallClock.Timed = WallClock.against(twice, reference, 3)
		# On a busy machine the multiple reads low (`against`): 1.5 for two, once, under the loaded suite.
		check(timed.multiple > 1.2 and timed.multiple < 3.0, "the reference run twice costs about two (%.2f; %d us against %d)" % [timed.multiple, timed.work_usec, timed.reference_usec])
		check(timed.work_usec > timed.reference_usec, "the work's time and the reference's are kept")


func test_the_reference_runs_as_long_as_the_work() -> void:
	# A reference that counts its runs, against work of ten of it: it is run again and again for about
	# as long as the work took, so a busy machine slows the two alike.
	var runs: Array[int] = [0]
	var counted := func() -> void:
		runs[0] += 1
		WallClock.gdscript_reference()
	var timed: WallClock.Timed = WallClock.against(func() -> void: _references(10), counted, 2)
	check(runs[0] >= 2 * 5, "run for about as long as the work, each round (%d runs in 2 rounds)" % runs[0])
	check(timed.multiple > 5.0 and timed.multiple < 20.0, "so the work costs about ten references (%.2f)" % timed.multiple)
