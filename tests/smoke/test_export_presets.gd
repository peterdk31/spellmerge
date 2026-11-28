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


## The web build is threaded (the owner's decision of 2026-11-28): the threaded templates, and the
## cross-origin isolation a browser asks before it gives a page shared memory, from Godot's service
## worker where the host sets no headers (GitHub Pages).
const WEB_SHELL: String = "res://ci/build/web_shell.html"


func test_the_web_build_is_threaded_and_cross_origin_isolated() -> void:
	var web: String = _section_of("Web") + ".options"
	check(config.get_value(web, "variant/thread_support", false) == true, "the Web preset exports the threaded templates")
	check(config.get_value(web, "progressive_web_app/enabled", false) == true, "the Web preset has Godot's service worker")
	check(config.get_value(web, "progressive_web_app/ensure_cross_origin_isolation_headers", false) == true, "and it adds the cross-origin isolation headers")
	# The owner's shell (ci/build/web_shell.html, the owner's answer of 2026-11-28) reloads a first
	# visit once the worker is ready: Godot's own page reloads before it is active.
	check_equal(config.get_value(web, "html/custom_html_shell", ""), WEB_SHELL, "the Web preset's page is the owner's shell")


## A browser's threads are workers made before the game starts (`threads/emscripten_pool_size`); the
## engine's pool takes `threads/godot_pool_size` of them and its audio and loading threads a few
## more, and the native module's loops at most WEB_MAX_WIDTH - 1 (native/src/jobs.h). A thread asked
## for past the pool would never start while the main thread waits for it, so the pool holds them all.
const ENGINE_OTHER_THREADS: int = 2
const JOBS_HEADER: String = "res://native/src/jobs.h"


func test_the_web_pool_holds_the_native_modules_threads() -> void:
	var web: String = _section_of("Web") + ".options"
	var header: String = FileAccess.get_file_as_string(JOBS_HEADER)
	var found: RegExMatch = RegEx.create_from_string("constexpr int WEB_MAX_WIDTH = (\\d+);").search(header)
	check(found != null, "jobs.h names WEB_MAX_WIDTH")
	if found == null:
		return
	var native_workers: int = int(found.get_string(1)) - 1
	var pool: int = config.get_value(web, "threads/emscripten_pool_size", 0)
	var engine: int = config.get_value(web, "threads/godot_pool_size", 0)
	check(engine >= 1, "the engine's pool is set (%d)" % engine)
	check(pool >= engine + ENGINE_OTHER_THREADS + native_workers, "the pool of %d holds the engine's %d, %d more of its own and the module's %d" % [pool, engine, ENGINE_OTHER_THREADS, native_workers])
