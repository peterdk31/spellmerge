extends "res://tests/support/suite.gd"
## Every `.uid` file in the project holds a valid, unique Godot UID: `uid://` followed by letters
## a-y and digits 0-8 (Godot's alphabet has no z and no 9; a file with a 9 makes the editor report
## an invalid UID). The validator's own tests come first, one rejected form each; then the scan
## finds the files it must, and every file found is checked for a valid UID and for one no other
## file has.
##
## godot --headless --path . --script res://tests/support/run.gd -- res://tests/core/test_uids.gd

const ALPHABET: String = "abcdefghijklmnopqrstuvwxy012345678"
## Files that must always be found, so a broken scan cannot pass by finding nothing.
const KNOWN_UID_FILES: Array[String] = [
	"res://core/events/events.gd.uid",
	"res://tests/core/test_uids.gd.uid",
]
# Generated output (build) and third-party code (addons); skipped at the repo root only.
const SKIPPED_FOLDERS: Array[String] = ["build", "addons"]

## The scan, made once per file (the tests only read it).
var _files: Array[String] = []


## An empty string when the UID text is valid, otherwise what is wrong.
static func _problem(text: String) -> String:
	if not text.begins_with("uid://"):
		return "does not start with uid://"
	var body: String = text.substr(6)
	if body.is_empty():
		return "no characters after uid://"
	for i in body.length():
		if not ALPHABET.contains(body[i]):
			return "invalid character '%s' (allowed: a-y and 0-8)" % body[i]
	return ""


static func _find_uid_files(dir_path: String) -> Array[String]:
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


func _uid_files() -> Array[String]:
	if _files.is_empty():
		_files = _find_uid_files("res://")
	return _files


func _uid_of(path: String) -> String:
	return FileAccess.get_file_as_string(path).strip_edges()


func test_the_validator_accepts_a_valid_uid() -> void:
	check(_problem("uid://bsbf87knh6522").is_empty(), "a valid UID was rejected")


func test_the_validator_rejects_a_nine() -> void:
	check(not _problem("uid://b4k9t2w6m8rze").is_empty(), "a 9 was accepted")


func test_the_validator_rejects_a_z() -> void:
	check(not _problem("uid://abz").is_empty(), "a z was accepted")


func test_the_validator_rejects_a_capital_letter() -> void:
	check(not _problem("uid://aB").is_empty(), "a capital letter was accepted")


func test_the_validator_rejects_an_empty_uid() -> void:
	check(not _problem("uid://").is_empty(), "an empty UID was accepted")


func test_the_validator_rejects_a_missing_prefix() -> void:
	check(not _problem("abc").is_empty(), "a missing prefix was accepted")


func test_the_scan_finds_the_known_uid_files() -> void:
	var files: Array[String] = _uid_files()
	for known in KNOWN_UID_FILES:
		check(files.has(known), "the scan did not find %s: it is broken" % known)


func test_every_uid_file_holds_a_valid_uid() -> void:
	for path in _uid_files():
		var text: String = _uid_of(path)
		var problem: String = _problem(text)
		check(problem.is_empty(), "%s: %s (%s)" % [path, problem, text])


func test_no_two_uid_files_share_a_uid() -> void:
	var seen: Dictionary[String, String] = {}
	for path in _uid_files():
		var text: String = _uid_of(path)
		if seen.has(text):
			check(false, "%s and %s share the UID %s" % [path, seen[text], text])
		seen[text] = path
