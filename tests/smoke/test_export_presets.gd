extends SceneTree
## `Linux Test`, `Web Test` and `Windows Test` (the exports that keep tests/ for the 4-bot run,
## and on Windows for the replay hashes, online-ready N2b) must stay copies of `Linux`, `Web` and
## `Windows`: each pair, and their options, differ only in name,
## runnable, exclude_filter and export_path. A new option added to one must be added to both.
## The web pair alone also excludes addons/* (the WebRTC extension is the desktop builds').
##
## godot --headless --path . --script res://tests/smoke/test_export_presets.gd

const PRESETS_PATH: String = "res://export_presets.cfg"
const DIFFERENT: Array[String] = ["name", "runnable", "exclude_filter", "export_path"]

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	_test_test_preset_matches("Linux", "Linux Test")
	_test_test_preset_matches("Web", "Web Test")
	_test_test_preset_matches("Windows", "Windows Test")
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


func _test_test_preset_matches(shipped_name: String, test_name: String) -> void:
	var config := ConfigFile.new()
	_check(config.load(PRESETS_PATH) == OK, "export_presets.cfg loads")
	var linux: String = _section_of(config, shipped_name)
	var test: String = _section_of(config, test_name)
	_check(linux != "" and test != "", "both the %s and %s presets exist" % [shipped_name, test_name])
	if linux == "" or test == "":
		return
	# A web build leaves the WebRTC extension's folder out (the browser has its own; with it packed
	# the game would try to load a library the web has none of: netcode spike S3). A desktop build
	# must not: it is where its WebRTC comes from.
	var web: bool = shipped_name == "Web"
	var only_web: String = "addons/*" if web else ""
	var shipped_filter: String = "tests/*, content/*/test_*.gd*" + (", " + only_web if web else "")
	_check(config.get_value(test, "exclude_filter", "x") == only_web, "%s excludes nothing%s" % [test_name, " but addons/*" if web else ""])
	_check(config.get_value(linux, "exclude_filter", "") == shipped_filter, "%s excludes tests/*, the cards' tests%s, and nothing else" % [shipped_name, " and addons/*" if web else ""])
	_check(config.get_value(test, "runnable", true) == false, "%s is not runnable" % test_name)
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
