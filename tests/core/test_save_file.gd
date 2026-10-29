extends "res://tests/support/suite.gd"
## `core/save` (`SaveFile`): flags and settings are written at once, and two saves on the same
## path do not wipe out each other's writes (the pause menu and Flow each hold one).
##
## godot --headless --path . --script res://tests/core/test_save_file.gd

const SAVE_PATH: String = "user://test_save_file.cfg"


func before_each() -> void:
	DirAccess.remove_absolute(SAVE_PATH)


func after_each() -> void:
	DirAccess.remove_absolute(SAVE_PATH)


func test_a_setting_and_a_flag_are_kept() -> void:
	var save: SaveFile = SaveFile.new(SAVE_PATH)
	check(save.is_new(), "a new save")
	check(save.set_setting(&"screen_shake", false), "the setting is written")
	check(save.is_new(), "a setting does not make a save old")
	check(save.set_flag(&"intro_seen"), "the flag is written")
	var again: SaveFile = SaveFile.new(SAVE_PATH)
	check(again.has_flag(&"intro_seen"), "the flag is read back")
	check_equal(again.get_setting(&"screen_shake", true), false, "and the setting")


func test_two_saves_on_one_path_keep_each_others_writes() -> void:
	var first: SaveFile = SaveFile.new(SAVE_PATH)
	var second: SaveFile = SaveFile.new(SAVE_PATH)
	second.set_setting(&"screen_shake", false)
	first.set_flag(&"intro_seen")
	var third: SaveFile = SaveFile.new(SAVE_PATH)
	check(third.has_flag(&"intro_seen"), "the flag survives the other save's setting")
	check_equal(third.get_setting(&"screen_shake", true), false, "the setting survives the flag")
	second.set_setting(&"other", 3)
	check(SaveFile.new(SAVE_PATH).has_flag(&"intro_seen"), "a later setting keeps the flag")
