extends Node
## The content registry (autoload `Registry`): finds content by folder and id,
## and sounds by id. It scans once at start, so adding content never means
## editing a list.
##
## This is the only script allowed to load from a computed path. Everyone else
## writes `load("res://...")` or `preload(...)` with a literal path.
##
##     var bolt := Registry.get_resource(&"spells", &"bolt") as FormBase
##     var sound: AudioStream = Registry.get_sound(&"fire_cast")
##     if sound != null:
##         ...  # plays nothing on null, so a missing sound is silent
##
## A "folder" is a direct child of the content root (`spells`, `enemies`,
## `rooms`, ...). Every `.tres` below it, at any depth, that has an `id` is
## registered under that id; a `.tres` without one (a sub-resource of an item)
## is skipped. The first file found wins a duplicate id (files are read in
## sorted path order) and a warning names both.
##
## The `demo` flag: when `demo_only` is true (the web demo build, the feature
## tag `demo`), resources whose `demo` is false are hidden from every question.
## Resources with no `demo` property are always visible.
##
## In a debug build the registry runs the spell validator at start (`validate_spells()`) and
## pushes one warning per problem, so broken spell content shows up on the first run.
##
## Sounds are `.ogg` files anywhere under the audio root; the id is the file
## name without extension. An unknown id returns `null`, never an error.

const DEFAULT_CONTENT_ROOT: String = "res://content"
const DEFAULT_AUDIO_ROOT: String = "res://audio"
const FEATURE_DEMO: String = "demo"

## Only demo content is visible when true. Starts true in a build with the
## `demo` feature tag. Changing it takes effect at once, no rescan needed.
var demo_only: bool = false

## The content root of the last scan, and the duplicate spell ids it found (one line each,
## naming both files), for the validator.
var _content_root: String = DEFAULT_CONTENT_ROOT
var _duplicates: PackedStringArray = PackedStringArray()
## folder -> { id -> Resource }
var _resources: Dictionary = {}
## folder -> sorted Array[StringName] of every id (demo or not)
var _ids: Dictionary = {}
## sound id -> path
var _sound_paths: Dictionary = {}
## sound id -> AudioStream already loaded
var _sounds: Dictionary = {}
## Lore files of the last scan: path -> parsed JSON (null if it did not parse).
var _lore_files: Dictionary = {}
## about -> { id -> text } of the lore files that are valid, for `get_lore()`.
var _lore: Dictionary = {}


func _ready() -> void:
	demo_only = OS.has_feature(FEATURE_DEMO)
	scan()
	if OS.is_debug_build():
		warn_spell_problems()
		warn_story_problems()


## Reads the content and audio folders again. The roots can be changed so
## tests can scan a fixture folder; `sound_extensions` is for tests as well.
func scan(content_root: String = DEFAULT_CONTENT_ROOT, audio_root: String = DEFAULT_AUDIO_ROOT, sound_extensions: PackedStringArray = PackedStringArray(["ogg"])) -> void:
	_content_root = content_root
	_duplicates.clear()
	_resources.clear()
	_ids.clear()
	_sound_paths.clear()
	_sounds.clear()
	_scan_lore(content_root.path_join("story/lore"))
	for folder_name: String in _list_dir(content_root, true):
		var folder: StringName = StringName(folder_name)
		var found: Dictionary = {}
		for path: String in _find_files(content_root.path_join(folder_name), PackedStringArray(["tres"])):
			var res: Resource = ResourceLoader.load(path)
			if res == null or not ("id" in res):
				continue
			var id: StringName = res.get("id")
			if id == &"":
				continue
			if found.has(id):
				push_warning("Registry: duplicate id '%s' in %s (kept %s)" % [id, path, (found[id] as Resource).resource_path])
				if folder == &"spells":
					_duplicates.append("'%s' in %s, kept %s" % [id, path, (found[id] as Resource).resource_path])
				continue
			found[id] = res
		if not found.is_empty():
			_resources[folder] = found
			var ids: Array[StringName] = []
			for id: StringName in found:
				ids.append(id)
			ids.sort_custom(_name_less)
			_ids[folder] = ids
	for path: String in _find_files(audio_root, sound_extensions):
		var sound_id: StringName = StringName(path.get_file().get_basename())
		if _sound_paths.has(sound_id):
			push_warning("Registry: duplicate sound '%s' in %s (kept %s)" % [sound_id, path, _sound_paths[sound_id]])
			continue
		_sound_paths[sound_id] = path


## Pushes one warning per problem `validate_spells()` finds, and returns how many.
func warn_spell_problems() -> int:
	var problems: Array[Dictionary] = validate_spells()
	for problem: Dictionary in problems:
		push_warning("Registry: " + SpellValidator.format(problem))
	return problems.size()


## Pushes one warning per problem `validate_story()` finds, and returns how many.
func warn_story_problems() -> int:
	var problems: Array[Dictionary] = validate_story()
	for problem: Dictionary in problems:
		push_warning("Registry: " + StoryValidator.format(problem))
	return problems.size()


## Runs the spell validator on everything found under `spells` (demo or not) and on the
## reaction table `<content root>/spells/reactions.tres`, which is skipped when there is
## none. Returns the problems as `SpellValidator` describes them; empty when all is well.
func validate_spells() -> Array[Dictionary]:
	var spells: Array[Resource] = []
	var found: Dictionary = _resources.get(&"spells", {})
	for id: StringName in found:
		spells.append(found[id] as Resource)
	var reactions: ReactionTable = null
	var table_path: String = _content_root.path_join("spells/reactions.tres")
	if ResourceLoader.exists(table_path):
		reactions = ResourceLoader.load(table_path) as ReactionTable
	return SpellValidator.check_all(spells, reactions, SpellValidator.load_manifest(), _duplicates)


## Reads every lore `.json` below `root` (`content/story/lore`). A file that fails the story
## validator is kept for `validate_story()` but never given out by `get_lore()`.
func _scan_lore(root: String) -> void:
	_lore_files.clear()
	_lore.clear()
	for path: String in _find_files(root, PackedStringArray(["json"])):
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		var data: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		_lore_files[path] = data
		if not StoryValidator.check_lore(path, data).is_empty():
			continue
		var entry: Dictionary = data
		var about: StringName = StringName(entry["about"])
		var texts: Dictionary = _lore.get(about, {})
		if not texts.has(entry["id"]):
			texts[StringName(entry["id"])] = entry["text"]
		_lore[about] = texts


## The lore text about `about` (`&"component"`) with this id, or "" when there is none.
func get_lore(about: StringName, id: StringName) -> String:
	var texts: Dictionary = _lore.get(about, {})
	return texts.get(id, "")


## Runs the story validator on the component lore files and checks that every spell component
## has one (demo or not). Problems come back as `StoryValidator` describes them.
func validate_story() -> Array[Dictionary]:
	var entries: Dictionary = {}
	for path: String in _lore_files:
		if path.begins_with(_content_root.path_join("story/lore/components/")):
			entries[path] = _lore_files[path]
	var ids: Array[StringName] = []
	for id: StringName in _resources.get(&"spells", {}):
		ids.append(id)
	ids.sort_custom(_name_less)
	return StoryValidator.check_component_lore(entries, ids)


## The resource with this id in this folder, or `null` when there is none (or
## it is hidden by `demo_only`).
func get_resource(folder: StringName, id: StringName) -> Resource:
	var found: Dictionary = _resources.get(folder, {})
	var res: Resource = found.get(id)
	if res == null or not _visible(res):
		return null
	return res


## Every visible id in the folder, sorted. Empty for an unknown folder.
func get_ids(folder: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var all_ids: Array[StringName] = []
	all_ids.assign(_ids.get(folder, []))
	for id: StringName in all_ids:
		if _visible((_resources[folder] as Dictionary)[id] as Resource):
			result.append(id)
	return result


## Every visible resource in the folder, in id order.
func get_all(folder: StringName) -> Array[Resource]:
	var result: Array[Resource] = []
	for id: StringName in get_ids(folder):
		result.append((_resources[folder] as Dictionary)[id] as Resource)
	return result


## Folders that hold at least one resource (visible or not), sorted.
func get_folders() -> Array[StringName]:
	var result: Array[StringName] = []
	for folder: StringName in _resources:
		result.append(folder)
	result.sort_custom(_name_less)
	return result


## StringName's own `<` compares addresses, not letters, so sort by the text.
static func _name_less(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)


## The sound with this id, or `null` when there is none: no such file, or it
## does not load as a sound. Callers play nothing on `null`.
func get_sound(id: StringName) -> AudioStream:
	if _sounds.has(id):
		return _sounds[id] as AudioStream
	var path: String = _sound_paths.get(id, "")
	if path == "":
		return null
	var stream: AudioStream = ResourceLoader.load(path) as AudioStream
	_sounds[id] = stream  # a failed load is remembered too, so it is tried once
	return stream


func _visible(res: Resource) -> bool:
	if not demo_only or not ("demo" in res):
		return true
	return res.get("demo") == true


## Names in one directory, sorted. Exported games list imported files with a
## `.remap` or `.import` suffix; it is removed, so the same name works in the
## editor and in an export.
func _list_dir(path: String, directories: bool) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return names
	var raw: PackedStringArray = dir.get_directories() if directories else dir.get_files()
	for entry: String in raw:
		if entry.begins_with("."):
			continue
		if not directories:
			entry = entry.trim_suffix(".remap").trim_suffix(".import")
		if not names.has(entry):
			names.append(entry)
	names.sort()
	return names


## Every file with one of the extensions below `root`, in full-path sorted order.
func _find_files(root: String, extensions: PackedStringArray) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	_collect_files(root, extensions, found)
	found.sort()
	return found


func _collect_files(root: String, extensions: PackedStringArray, found: PackedStringArray) -> void:
	for file_name: String in _list_dir(root, false):
		if extensions.has(file_name.get_extension()):
			found.append(root.path_join(file_name))
	for sub: String in _list_dir(root, true):
		_collect_files(root.path_join(sub), extensions, found)
