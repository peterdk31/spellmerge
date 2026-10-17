extends Node
## The content registry (autoload `Registry`): finds content by folder and id,
## and sounds by id. It scans once at start, so adding content never means
## editing a list.
##
## This is the only script allowed to load from a computed path. Everyone else
## writes `load("res://...")` or `preload(...)` with a literal path.
##
##     var bolt := Registry.get_resource(&"spells", &"bolt") as SpellBase
##     var sound: AudioStream = Registry.get_sound(&"fire_cast")
##     if sound != null:
##         ...  # plays nothing on null, so a missing sound is silent
##
## A "folder" is a direct child of the content root (`spells`, `enemies`,
## `rooms`, ...). Every `.tres` below it, at any depth, that has an `id` is
## registered under that id; a `.tres` without one (a sub-resource of an item)
## is skipped. The first file found wins a duplicate id (folders are read in
## sorted order) and a warning names both.
##
## The `demo` flag: when `demo_only` is true (the web demo build, the feature
## tag `demo`), resources whose `demo` is false are hidden from every question.
## Resources with no `demo` property are always visible.
##
## Sounds are `.ogg` files anywhere under the audio root; the id is the file
## name without extension. An unknown id returns `null`, never an error.

const DEFAULT_CONTENT_ROOT: String = "res://content"
const DEFAULT_AUDIO_ROOT: String = "res://audio"
const FEATURE_DEMO: String = "demo"

## Only demo content is visible when true. Starts true in a build with the
## `demo` feature tag. Changing it takes effect at once, no rescan needed.
var demo_only: bool = false

## folder -> { id -> Resource }
var _resources: Dictionary = {}
## folder -> sorted Array[StringName] of every id (demo or not)
var _ids: Dictionary = {}
## sound id -> path
var _sound_paths: Dictionary = {}
## sound id -> AudioStream already loaded
var _sounds: Dictionary = {}


func _ready() -> void:
	demo_only = OS.has_feature(FEATURE_DEMO)
	scan()


## Reads the content and audio folders again. The roots can be changed so
## tests can scan a fixture folder; `sound_extensions` is for tests as well.
func scan(content_root: String = DEFAULT_CONTENT_ROOT, audio_root: String = DEFAULT_AUDIO_ROOT, sound_extensions: PackedStringArray = PackedStringArray(["ogg"])) -> void:
	_resources.clear()
	_ids.clear()
	_sound_paths.clear()
	_sounds.clear()
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
				continue
			found[id] = res
		if not found.is_empty():
			_resources[folder] = found
			var ids: Array[StringName] = []
			for id: StringName in found:
				ids.append(id)
			ids.sort()
			_ids[folder] = ids
	for path: String in _find_files(audio_root, sound_extensions):
		var sound_id: StringName = StringName(path.get_file().get_basename())
		if _sound_paths.has(sound_id):
			push_warning("Registry: duplicate sound '%s' in %s (kept %s)" % [sound_id, path, _sound_paths[sound_id]])
			continue
		_sound_paths[sound_id] = path


## The resource with this id in this folder, or `null` when there is none (or
## it is hidden by `demo_only`).
func get_resource(folder: StringName, id: StringName) -> Resource:
	var found: Dictionary = _resources.get(folder, {})
	var res: Resource = found.get(id)
	if res == null or not _visible(res):
		return null
	return res


func has_resource(folder: StringName, id: StringName) -> bool:
	return get_resource(folder, id) != null


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
	result.sort()
	return result


## The sound with this id, or `null` when there is none: no such file, or it
## does not load as a sound. Callers play nothing on `null`.
func get_sound(id: StringName) -> AudioStream:
	if _sounds.has(id):
		return _sounds[id] as AudioStream
	var path: String = _sound_paths.get(id, "")
	if path == "":
		return null
	var stream: AudioStream = ResourceLoader.load(path) as AudioStream
	if stream != null:
		_sounds[id] = stream
	return stream


func has_sound(id: StringName) -> bool:
	return _sound_paths.has(id)


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


## Every file with one of the extensions below `root`, in sorted order.
func _find_files(root: String, extensions: PackedStringArray) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for file_name: String in _list_dir(root, false):
		if extensions.has(file_name.get_extension()):
			found.append(root.path_join(file_name))
	for sub: String in _list_dir(root, true):
		found.append_array(_find_files(root.path_join(sub), extensions))
	return found
