extends "res://tests/support/suite.gd"
## Every script the unit tests never run (the screenshot sheets, the clips, the benchmarks and the
## tests' support) still parses: a sheet that fails to parse fails only when the screenshots are
## taken, which no check runs. (Regression: `tests/support/empty_stage.gd` named `PinnedRun`, which its
## base `screenshot.gd` had come to name too, so the props sheet no longer parsed.)
const FOLDERS: Array[String] = ["res://tests/support", "res://tests/screenshots", "res://tests/clips", "res://tests/benchmark"]


func _scripts(folder: String, found: Array[String]) -> void:
	for file_name: String in DirAccess.get_files_at(folder):
		if file_name.ends_with(".gd"):
			found.append(folder.path_join(file_name))
	for sub: String in DirAccess.get_directories_at(folder):
		_scripts(folder.path_join(sub), found)


func test_every_script_beside_the_tests_parses() -> void:
	var found: Array[String] = []
	for folder: String in FOLDERS:
		if DirAccess.dir_exists_absolute(folder):
			_scripts(folder, found)
	check(found.size() > 20, "the scripts are found (%d)" % found.size())
	for path: String in found:
		var script := load(path) as GDScript
		check(script != null and script.can_instantiate(), "%s parses" % path)
