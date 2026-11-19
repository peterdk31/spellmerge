extends "res://tests/support/suite.gd"
## Tests for the unit tests' host (tests/support/run.gd): a user:// that Godot did not put under the
## data folder asked for (a relative `XDG_DATA_HOME`, passed over for ~/.local/share) is known to be
## shared, so the host fails the run before any suite (the owner, 2026-11-19: an error, not a warning) (regression, 2026-11-19: test_intro's save and
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
