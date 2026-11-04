extends "res://tests/support/suite.gd"
## The stepped settings' one helper (`SettingStops`, core/settings; docs/milestones/
## spell-spectacle-2.md, S1): the stop nearest a value, the lower one on a tie, for the "Particles",
## "Particle amount" and "Max shots" settings alike.
##
## godot --headless --path . --script res://tests/core/test_setting_stops.gd


func test_the_nearest_stop_and_the_lower_on_a_tie() -> void:
	var stops: Array[int] = [0, 10, 20]
	check_equal(SettingStops.nearest(stops, -5.0), 0, "below the first")
	check_equal(SettingStops.nearest(stops, 4.0), 0, "nearer the first")
	check_equal(SettingStops.nearest(stops, 5.0), 0, "a tie: the lower")
	check_equal(SettingStops.nearest(stops, 6.0), 1, "nearer the second")
	check_equal(SettingStops.nearest(stops, 99.0), 2, "past the last")
	check_equal(SettingStops.nearest([], 3.0), 0, "no stops")


func test_every_stepped_setting_snaps_through_it() -> void:
	check_equal(MoteCap.snap(9000), 8192, "Particles")
	check_equal(MoteCap.word_of(20000), "Medium", "and its word")
	check_equal(MoteDensity.snap(0.7), 0.5, "Particle amount")
	check_equal(MoteDensity.word_of(1.6), "Double", "and its word")
	check_equal(ShotCap.snap(1200), 1000, "Max shots")
	for i in MoteCap.STOPS.size():
		check_equal(MoteCap.index_of(MoteCap.STOPS[i]), i, "each stop is its own")
	for i in ShotCap.STOPS.size():
		check_equal(ShotCap.index_of(ShotCap.STOPS[i]), i, "each shot cap is its own")
	for i in MoteDensity.STOPS.size():
		check_equal(MoteDensity.index_of(MoteDensity.STOPS[i]), i, "each share is its own")
