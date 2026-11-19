extends SceneTree
## The host of the unit test suites (tests/support/suite.gd): runs the suite files its user
## arguments name, one after another in this one process, and quits 1 if any failed.
##
##   godot --headless --path . --script res://tests/support/run.gd -- res://tests/a/test_x.gd res://tests/b/test_y.gd
##
## A Godot start compiles the whole game (the autoloads reach nearly every script: seconds), so the
## runner (ci/build/unit_tests.sh) hands one process several small files. Each file still starts on
## a fresh game, as in a process of its own: before every file but the first, what the last one left
## is cleared (the root's children that are not autoloads, the tree's pause and current scene, the
## input map, the time scale) and every autoload is made again (`FreshGame.restart`). Static members
## (caches) stay, as they do between the tests of one file.
##
## Each file is framed in the log, so the runner can give every file its own log and result:
##   SUITE START: res://tests/a/test_x.gd
##   ... the suite's TEST TIME, TEST OK or TEST FAILED lines, and whatever it printed ...
##   SUITE END: res://tests/a/test_x.gd PASS 1234 ms
## A user argument `--shard=K/N` goes to every suite (tests/support/suite.gd, "shards").
##
## **Its own user://:** the runner gives every process a data folder of its own (`XDG_DATA_HOME`),
## and what a file saved is cleared before the next (`_clear_user_data`). Godot takes only an
## absolute `XDG_DATA_HOME` (as the XDG rules say): a relative one is passed over for
## `~/.local/share`, so every process at once shares one user:// and one process's clearing deletes
## another's files mid-test (a save written, then gone: test_intro's "the save remembers it", and
## test_net_play's replays, failing only among the others; found 2026-11-19). A host whose user://
## is not under its `XDG_DATA_HOME` (`user_dir_shared`) fails the run at once, before any file and
## before clearing anything, so it never deletes what another process is using and the runner's
## mistake is seen (the owner, 2026-11-19: "a shared user:// should be an error, not a warning").

const FreshGame := preload("res://tests/support/fresh_game.gd")
const SuiteScript := preload("res://tests/support/suite.gd")

const START: String = "SUITE START: "
const END: String = "SUITE END: "


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	var files: PackedStringArray = PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.ends_with(".gd"):
			files.append(arg if arg.begins_with("res://") else "res://" + arg)
	if files.is_empty():
		printerr("run.gd: name the suite files to run (-- res://tests/<area>/test_<name>.gd ...)")
		quit(2)
		return
	var autoloads: Array[String] = _autoload_names()
	if user_dir_shared(OS.get_environment("XDG_DATA_HOME"), OS.get_user_data_dir()):
		printerr("ERROR: run.gd: user:// (%s) is not under XDG_DATA_HOME (%s; Godot takes it only when absolute): it is shared with every other process, which delete each other's files. Give each process an absolute data folder of its own; no suite runs." % [OS.get_user_data_dir(), OS.get_environment("XDG_DATA_HOME")])
		quit(2)
		return
	var failed: int = 0
	for at in files.size():
		if at > 0:
			await _fresh_game(autoloads)
		print(START + files[at])
		var started: int = Time.get_ticks_msec()
		var passed: bool = await _run_file(files[at])
		if not passed:
			failed += 1
		print("%s%s %s %d ms" % [END, files[at], "PASS" if passed else "FAIL", Time.get_ticks_msec() - started])
	quit(1 if failed > 0 else 0)


## Runs the suite in `path`; whether every test passed.
func _run_file(path: String) -> bool:
	var script: Script = load(path) as Script
	if script == null or not script.can_instantiate():
		printerr("TEST FAILED: %s did not load (its error is above)" % path)
		return false
	if not _is_suite(script):
		printerr("TEST FAILED: %s is not a suite (it must extend res://tests/support/suite.gd)" % path)
		return false
	var suite: SuiteScript = script.new() as SuiteScript
	var failures: Array[String] = await suite.run_in(self)
	suite.free()
	return failures.is_empty()


static func _is_suite(script: Script) -> bool:
	var base: Script = script
	while base != null:
		if base == SuiteScript:
			return true
		base = base.get_base_script()
	return false


## What a file left is cleared and every autoload made again, so the next file starts as in a
## process of its own.
func _fresh_game(autoloads: Array[String]) -> void:
	paused = false
	current_scene = null
	for child: Node in root.get_children():
		if not autoloads.has(String(child.name)):
			root.remove_child(child)
			child.free()
	Engine.time_scale = 1.0
	InputMap.load_from_project_settings()
	_clear_user_data("user://")
	FreshGame.restart(root)
	# As at a start: the autoloads' deferred calls run before the first test.
	await process_frame


## True when the data folder `xdg_data_home` (the environment's `XDG_DATA_HOME`; empty: none asked)
## was asked for and the user dir `user_dir` (`OS.get_user_data_dir()`) is not in it: Godot passed it
## over (a relative path), and user:// is the one every process shares.
static func user_dir_shared(xdg_data_home: String, user_dir: String) -> bool:
	if xdg_data_home == "":
		return false
	var home: String = xdg_data_home.simplify_path()
	return not (user_dir.simplify_path() + "/").begins_with(home.trim_suffix("/") + "/")


## Every file and folder under `folder` of user:// (what an earlier file saved: settings, replays),
## but Godot's own logs.
static func _clear_user_data(folder: String) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	for name: String in dir.get_directories():
		if folder == "user://" and name == "logs":
			continue
		_clear_user_data(folder.path_join(name))
		dir.remove(name)
	for name: String in dir.get_files():
		dir.remove(name)


static func _autoload_names() -> Array[String]:
	var names: Array[String] = []
	for info: Dictionary in ProjectSettings.get_property_list():
		var key: String = info["name"]
		if key.begins_with("autoload/"):
			names.append(key.trim_prefix("autoload/"))
	return names
