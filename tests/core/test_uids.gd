extends SceneTree
## Every `.uid` file in the project holds a valid, unique Godot UID: `uid://`
## followed by letters a-y and digits 0-8 (Godot's alphabet has no z and no 9;
## a file with a 9 makes the editor report an invalid UID).
##
## godot --headless --path . --script res://tests/core/test_uids.gd

const ALPHABET: String = "abcdefghijklmnopqrstuvwxy012345678"
## Files that must always be found, so a broken scan cannot pass by finding nothing.
const KNOWN_UID_FILES: Array[String] = [
	"res://core/events/events.gd.uid",
	"res://tests/core/test_uids.gd.uid",
]
# Generated output (build) and third-party code (addons); skipped at the repo root only.
const SKIPPED_FOLDERS: Array[String] = ["build", "addons"]

var _failures: Array[String] = []


func _initialize() -> void:
	_test_validator()
	var seen: Dictionary = {}
	var files: Array[String] = _find_uid_files("res://")
	for known in KNOWN_UID_FILES:
		_check(files.has(known), "the scan did not find %s: it is broken" % known)
	for path in files:
		var text: String = FileAccess.get_file_as_string(path).strip_edges()
		var problem: String = _problem(text)
		_check(problem.is_empty(), "%s: %s (%s)" % [path, problem, text])
		if seen.has(text):
			_check(false, "%s and %s share the UID %s" % [path, seen[text], text])
		seen[text] = path
	if _failures.is_empty():
		print("TEST OK: uids (%d files)" % files.size())
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## An empty string when the UID text is valid, otherwise what is wrong.
func _problem(text: String) -> String:
	if not text.begins_with("uid://"):
		return "does not start with uid://"
	var body: String = text.substr(6)
	if body.is_empty():
		return "no characters after uid://"
	for i in body.length():
		if not ALPHABET.contains(body[i]):
			return "invalid character '%s' (allowed: a-y and 0-8)" % body[i]
	return ""


## The check itself must reject what Godot rejects.
func _test_validator() -> void:
	_check(_problem("uid://bsbf87knh6522").is_empty(), "a valid UID was rejected")
	_check(not _problem("uid://b4k9t2w6m8rze").is_empty(), "a 9 was accepted")
	_check(not _problem("uid://abz").is_empty(), "a z was accepted")
	_check(not _problem("uid://aB").is_empty(), "a capital letter was accepted")
	_check(not _problem("uid://").is_empty(), "an empty UID was accepted")
	_check(not _problem("abc").is_empty(), "a missing prefix was accepted")


func _find_uid_files(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return found
	for sub in dir.get_directories():
		if sub.begins_with(".") or (dir_path == "res://" and SKIPPED_FOLDERS.has(sub)):
			continue
		found.append_array(_find_uid_files(dir_path.path_join(sub)))
	for file_name in dir.get_files():
		if file_name.ends_with(".uid"):
			found.append(dir_path.path_join(file_name))
	return found
