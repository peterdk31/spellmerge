extends "res://tests/support/suite.gd"
## Tests for the unit tests' host (tests/support/run.gd): a user:// that Godot did not put under the
## data folder asked for (a relative `XDG_DATA_HOME`, passed over for ~/.local/share) is known to be
## shared, so the host clears nothing in it (regression, 2026-11-19: test_intro's save and
## test_net_play's replays were deleted mid-test by other processes' clearing, only among the others).
const RunScript := preload("res://tests/support/run.gd")


func test_a_user_dir_under_its_data_folder_is_its_own() -> void:
	check(not RunScript.user_dir_shared("/work/build/test-runs/a", "/work/build/test-runs/a/godot/app_userdata/Spellmerge"), "under it: its own")
	check(not RunScript.user_dir_shared("/work/build/test-runs/a/", "/work/build/test-runs/a/godot/app_userdata/Spellmerge"), "a trailing slash too")
	check(not RunScript.user_dir_shared("", "/root/.local/share/godot/app_userdata/Spellmerge"), "none asked: a process run by hand")


func test_a_relative_data_folder_passed_over_is_shared() -> void:
	# What Godot does with XDG_DATA_HOME=build/test-runs/a (seen 2026-11-19): ~/.local/share.
	check(RunScript.user_dir_shared("build/test-runs/a", "/root/.local/share/godot/app_userdata/Spellmerge"), "relative: passed over, shared")
	check(RunScript.user_dir_shared("/work/build/test-runs/a", "/work/build/test-runs/ab/godot/app_userdata/Spellmerge"), "a folder whose name only begins the same is another")


## This very process: the runner (ci/build/unit_tests.sh, tools/ptest.sh) gives it a folder of its
## own; where it did not, the host must have cleared nothing (it says so in the log).
func test_this_host_clears_only_a_user_dir_of_its_own() -> void:
	var shared: bool = RunScript.user_dir_shared(OS.get_environment("XDG_DATA_HOME"), OS.get_user_data_dir())
	var host: Variant = Engine.get_main_loop()
	if host is RunScript:
		check_equal(bool((host as Object).get(&"_shared")), shared, "the host knows whether its user:// is shared")
