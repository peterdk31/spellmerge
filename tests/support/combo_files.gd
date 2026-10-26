extends RefCounted
## The combo catalogue: one JSON file per combo in `content/spells/combos/`, named like the
## combo's `id` (staffs A2, docs/milestones/M2-staffs.md, "Working in parallel"). A new card's
## combos are new files, so two card PRs never edit the same list.
##
##     const ComboFiles := preload("res://tests/support/combo_files.gd")
##     var combos: Array = ComboFiles.read_all()

const FOLDER: String = "res://content/spells/combos"


## Every combo row, in file-name order. A file that is not a JSON object is skipped and its
## name is added to `problems`, so the combo test can fail with it.
static func read_all(folder: String = FOLDER, problems: PackedStringArray = PackedStringArray()) -> Array:
	var rows: Array = []
	var names: PackedStringArray = DirAccess.get_files_at(folder)
	names.sort()
	for file_name: String in names:
		if file_name.get_extension() != "json":
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(file_name)))
		if parsed is Dictionary:
			rows.append(parsed)
		else:
			problems.append(file_name)
	return rows


## The file names (without `.json`) of the catalogue, in order, for the check that each file is
## named like its combo.
static func file_ids(folder: String = FOLDER) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	var names: PackedStringArray = DirAccess.get_files_at(folder)
	names.sort()
	for file_name: String in names:
		if file_name.get_extension() == "json":
			ids.append(file_name.get_basename())
	return ids
