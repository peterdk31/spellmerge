extends RefCounted
## The combo catalogue: one JSON file per combo, named like the combo's `id`, in a `combos/`
## folder inside the card it was written for (`content/spells/modifiers/slow/combos/
## slow_fire_fan.json`; staffs A2, docs/milestones/M2-staffs.md, "Working in parallel"). A
## card's combos live and go with its folder, and two card PRs never edit the same list.
##
##     const ComboFiles := preload("res://tests/support/combo_files.gd")
##     var combos: Array = ComboFiles.read_all()

const ROOT: String = "res://content/spells"
const FOLDER_NAME: String = "combos"


## Every combo row, in file-name order. A file that is not a JSON object is skipped and its
## name is added to `problems`, so the combo test can fail with it.
static func read_all(root: String = ROOT, problems: PackedStringArray = PackedStringArray()) -> Array:
	var rows: Array = []
	for path: String in paths(root):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			rows.append(parsed)
		else:
			problems.append(path.get_file())
	return rows


## The file names (without `.json`) of the catalogue, in order, for the check that each file is
## named like its combo.
static func file_ids(root: String = ROOT) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for path: String in paths(root):
		ids.append(path.get_file().get_basename())
	return ids


## Every combo file below `root` (a `.json` in a folder named `combos`, at any depth), sorted by
## file name so the order does not depend on which card holds a combo.
static func paths(root: String = ROOT) -> PackedStringArray:
	var found: Array[String] = []
	_walk(root, found)
	found.sort_custom(func(a: String, b: String) -> bool: return a.get_file() < b.get_file())
	return PackedStringArray(found)


static func _walk(folder: String, found: Array[String]) -> void:
	if folder.get_file() == FOLDER_NAME:
		for file_name: String in DirAccess.get_files_at(folder):
			if file_name.get_extension() == "json":
				found.append(folder.path_join(file_name))
	for child: String in DirAccess.get_directories_at(folder):
		if not child.begins_with("."):
			_walk(folder.path_join(child), found)
