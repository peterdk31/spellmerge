extends SceneTree
## `Linux Test` (the export that keeps tests/ for the 4-bot run) must stay a copy of
## `Linux`: the two presets, and their options, differ only in name, runnable,
## exclude_filter and export_path. A new option added to one must be added to both.
##
## godot --headless --path . --script res://tests/smoke/test_export_presets.gd

const PRESETS_PATH: String = "res://export_presets.cfg"
const DIFFERENT: Array[String] = ["name", "runnable", "exclude_filter", "export_path"]

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	_test_linux_test_matches_linux()
	if _failures.is_empty():
		print("TEST OK: tests/smoke/export_presets")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _section_of(config: ConfigFile, preset_name: String) -> String:
	for section in config.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options") \
				and config.get_value(section, "name", "") == preset_name:
			return section
	return ""


func _test_linux_test_matches_linux() -> void:
	var config := ConfigFile.new()
	_check(config.load(PRESETS_PATH) == OK, "export_presets.cfg loads")
	var linux: String = _section_of(config, "Linux")
	var test: String = _section_of(config, "Linux Test")
	_check(linux != "" and test != "", "both the Linux and Linux Test presets exist")
	if linux == "" or test == "":
		return
	_check(config.get_value(test, "exclude_filter", "x") == "", "Linux Test excludes nothing")
	_check(config.get_value(linux, "exclude_filter", "") == "tests/*", "Linux still excludes tests/*")
	_check(config.get_value(test, "runnable", true) == false, "Linux Test is not runnable")
	_check(config.get_value(test, "export_path", "") != config.get_value(linux, "export_path", ""), "the two presets export to different paths")
	_compare(config, linux, test)
	_compare(config, linux + ".options", test + ".options")


func _compare(config: ConfigFile, a: String, b: String) -> void:
	var keys: Dictionary = {}
	for section in [a, b]:
		if config.has_section(section):
			for key in config.get_section_keys(section):
				keys[key] = true
	for key in keys:
		if key in DIFFERENT:
			continue
		_check(config.get_value(a, key, null) == config.get_value(b, key, null), "%s and %s differ in '%s'" % [a, b, key])
