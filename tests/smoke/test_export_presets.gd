extends "res://tests/support/suite.gd"
## `Linux Test`, `Web Test` and `Windows Test` (the exports that keep tests/ for the 4-bot run,
## and on Windows for the replay hashes, online-ready N2b) must stay copies of `Linux`, `Web` and
## `Windows`: each pair, and their options, differ only in name, runnable, exclude_filter and
## export_path. A new option added to one must be added to both. The web pair alone also excludes
## addons/* (the WebRTC extension is the desktop builds'). Each test checks one of those rules on
## all three pairs of export_presets.cfg, read afresh before each test.

const PRESETS_PATH: String = "res://export_presets.cfg"
const DIFFERENT: Array[String] = ["name", "runnable", "exclude_filter", "export_path"]
## Each shipped preset and its test copy.
const PAIRS: Dictionary[String, String] = {"Linux": "Linux Test", "Web": "Web Test", "Windows": "Windows Test"}

var config: ConfigFile
var loaded: Error = OK


func before_each() -> void:
	config = ConfigFile.new()
	loaded = config.load(PRESETS_PATH)


func after_each() -> void:
	config = null


func _section_of(preset_name: String) -> String:
	for section in config.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options") \
				and config.get_value(section, "name", "") == preset_name:
			return section
	return ""


## The pairs whose two presets both exist, as shipped section -> test section.
func _pairs() -> Dictionary[String, String]:
	var found: Dictionary[String, String] = {}
	for shipped_name: String in PAIRS:
		var shipped: String = _section_of(shipped_name)
		var test: String = _section_of(PAIRS[shipped_name])
		if shipped != "" and test != "":
			found[shipped] = test
	return found


func _name_of(section: String) -> String:
	return config.get_value(section, "name", "")


## Checks that sections `a` and `b` hold the same value for every key but DIFFERENT.
func _check_same_but_different(a: String, b: String) -> void:
	var keys: Dictionary[String, bool] = {}
	for section: String in [a, b]:
		if config.has_section(section):
			for key in config.get_section_keys(section):
				keys[key] = true
	for key: String in keys:
		if key in DIFFERENT:
			continue
		check(config.get_value(a, key, null) == config.get_value(b, key, null), "%s and %s differ in '%s'" % [a, b, key])


func test_the_presets_file_loads() -> void:
	check_equal(loaded, OK, "export_presets.cfg loads")


func test_every_shipped_preset_has_its_test_copy() -> void:
	for shipped_name: String in PAIRS:
		check(_section_of(shipped_name) != "" and _section_of(PAIRS[shipped_name]) != "", "both the %s and %s presets exist" % [shipped_name, PAIRS[shipped_name]])


func test_a_test_preset_excludes_nothing_but_addons_on_the_web() -> void:
	# A web build leaves the WebRTC extension's folder out (the browser has its own; with it packed
	# the game would try to load a library the web has none of: netcode spike S3). A desktop build
	# must not: it is where its WebRTC comes from.
	var pairs: Dictionary[String, String] = _pairs()
	for shipped: String in pairs:
		var only_web: String = "addons/*" if _name_of(shipped) == "Web" else ""
		check_equal(config.get_value(pairs[shipped], "exclude_filter", "x"), only_web, "%s's exclude_filter" % _name_of(pairs[shipped]))


func test_a_shipped_preset_excludes_the_tests_and_addons_only_on_the_web() -> void:
	var pairs: Dictionary[String, String] = _pairs()
	for shipped: String in pairs:
		var expected: String = "tests/*, content/*/test_*.gd*" + (", addons/*" if _name_of(shipped) == "Web" else "")
		check_equal(config.get_value(shipped, "exclude_filter", ""), expected, "%s excludes tests/*, the cards' tests (and addons/* on the web), and nothing else" % _name_of(shipped))


func test_a_test_preset_is_not_runnable() -> void:
	var pairs: Dictionary[String, String] = _pairs()
	for shipped: String in pairs:
		check(config.get_value(pairs[shipped], "runnable", true) == false, "%s is not runnable" % _name_of(pairs[shipped]))


func test_a_test_preset_exports_to_its_own_path() -> void:
	var pairs: Dictionary[String, String] = _pairs()
	for shipped: String in pairs:
		check(config.get_value(pairs[shipped], "export_path", "") != config.get_value(shipped, "export_path", ""), "%s and its test copy export to different paths" % _name_of(shipped))


func test_a_test_preset_matches_its_shipped_one_in_every_other_setting() -> void:
	var pairs: Dictionary[String, String] = _pairs()
	for shipped: String in pairs:
		_check_same_but_different(shipped, pairs[shipped])


func test_a_test_preset_matches_its_shipped_one_in_every_option() -> void:
	var pairs: Dictionary[String, String] = _pairs()
	for shipped: String in pairs:
		_check_same_but_different(shipped + ".options", pairs[shipped] + ".options")
