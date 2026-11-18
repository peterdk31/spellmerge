extends Node
## The content registry (autoload `Registry`): finds content by folder and id,
## and sounds by id. It scans once at start, so adding content never means
## editing a list.
##
## This is the only script allowed to load from a computed path. Everyone else
## writes `load("res://...")` or `preload(...)` with a literal path.
##
##     var bolt := Registry.get_resource(&"spells", &"bolt") as CarrierCard
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
## Every build sees all of it: there is no demo subset (owner, 2026-11-05).
##
## In a debug build the registry runs the spell validator at start (`validate_spells()`), and the
## runs' (`validate_runs()`), and pushes one warning per problem, so broken spell or run content
## shows up on the first run.
##
## Sounds (docs/milestones/sound.md, section 3) are `.ogg` files and `.tres` files (an
## `AudioStreamRandomizer` of a sound's baked variants: `<id>.tres` naming `variants/1.ogg` ...)
## anywhere under the audio root, and under any `sounds/` folder of a content item (a single item's
## sound lives in its own folder, `content/<...>/sounds/<id>/`); the id is the file name without
## extension. Nothing under a `variants/` folder is an id of its own. The content scan of `.tres`
## files skips `sounds/` folders, so a sound loads only when it is first asked for. An `.ogg` and a
## `.tres` of one id, or two files of one id anywhere, is a warning naming both (the audio root's
## first, then the content's, each in path order: the first is kept), listed by `sound_clashes()`, which a test fails on for the game's files. An
## unknown id returns `null`, never an error.

const DEFAULT_CONTENT_ROOT: String = "res://content"
const DEFAULT_AUDIO_ROOT: String = "res://audio"

## The content root of the last scan, and the duplicate spell ids it found (one line each,
## naming both files), for the validator.
var _content_root: String = DEFAULT_CONTENT_ROOT
var _duplicates: PackedStringArray = PackedStringArray()
## folder -> { id -> Resource }
var _resources: Dictionary = {}
## folder -> sorted Array[StringName] of every id
var _ids: Dictionary = {}
## sound id -> path
var _sound_paths: Dictionary = {}
## sound id -> AudioStream already loaded
var _sounds: Dictionary = {}
## One line for each sound id found twice (`sound_clashes`).
var _sound_clashes: PackedStringArray = PackedStringArray()

## The folder a content item keeps its sounds in, and a sound's folder of baked variants: never ids.
const SOUNDS_FOLDER: String = "sounds"
const VARIANTS_FOLDER: String = "variants"
## What a sound file may be.
const SOUND_EXTENSIONS: PackedStringArray = ["ogg", "tres"]


func _ready() -> void:
	scan()
	if OS.is_debug_build():
		warn_spell_problems()
		warn_story_problems()
		warn_run_problems()


## Reads the content and audio folders again. The roots can be changed so
## tests can scan a fixture folder; `sound_extensions` is for tests as well.
func scan(content_root: String = DEFAULT_CONTENT_ROOT, audio_root: String = DEFAULT_AUDIO_ROOT, sound_extensions: PackedStringArray = SOUND_EXTENSIONS) -> void:
	_content_root = content_root
	_duplicates.clear()
	_resources.clear()
	_ids.clear()
	_sound_paths.clear()
	_sounds.clear()
	_sound_clashes.clear()
	for folder_name: String in _list_dir(content_root, true):
		var folder: StringName = StringName(folder_name)
		var duplicates: Array[String] = []
		var found: Dictionary = _read_folder(content_root.path_join(folder_name), duplicates)
		if folder == &"spells":
			_duplicates.append_array(PackedStringArray(duplicates))
		if not found.is_empty():
			_resources[folder] = found
			var ids: Array[StringName] = []
			for id: StringName in found:
				ids.append(id)
			ids.sort_custom(_name_less)
			_ids[folder] = ids
	var sound_files: PackedStringArray = PackedStringArray()
	_collect_sounds(audio_root, sound_extensions, true, sound_files)
	var content_sounds: PackedStringArray = PackedStringArray()
	_collect_sounds(content_root, sound_extensions, false, content_sounds)
	content_sounds.sort()
	sound_files.sort()
	sound_files.append_array(content_sounds)
	for path: String in sound_files:
		var sound_id: StringName = StringName(path.get_file().get_basename())
		if _sound_paths.has(sound_id):
			push_warning("Registry: duplicate sound '%s' in %s (kept %s)" % [sound_id, path, _sound_paths[sound_id]])
			_sound_clashes.append("'%s' in %s and %s" % [sound_id, _sound_paths[sound_id], path])
			continue
		_sound_paths[sound_id] = path


## Every sound id with a file, in id order (the sound room lists them, tests/sound_room).
func sound_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in _sound_paths:
		ids.append(id)
	ids.sort_custom(_name_less)
	return ids


## Every sound id found twice in the last scan, one line each naming both files (empty: none).
func sound_clashes() -> PackedStringArray:
	return _sound_clashes


## Every sound file below `root`: with `inside` (the audio root, or below a content item's
## `sounds/` folder) each file of one of `extensions`; never one below a `variants/` folder.
static func _collect_sounds(root: String, extensions: PackedStringArray, inside: bool, found: PackedStringArray) -> void:
	if inside:
		for file_name: String in _list_dir(root, false):
			if extensions.has(file_name.get_extension()):
				found.append(root.path_join(file_name))
	for sub: String in _list_dir(root, true):
		if sub == VARIANTS_FOLDER:
			continue
		_collect_sounds(root.path_join(sub), extensions, inside or sub == SOUNDS_FOLDER, found)


## Every resource of the content folder `folder` (`cover`) under `content_root`, in id order, read
## there and then: for the editor, where the `Registry` autoload does not run (ground cover GC2, rule
## 7: the editor's cover preview finds the cover kinds by it), and for tools. The game asks the
## autoload (`get_all`), which read the same files the same way at its start.
static func scan_folder(folder: StringName, content_root: String = DEFAULT_CONTENT_ROOT) -> Array[Resource]:
	var found: Dictionary = _read_folder(content_root.path_join(String(folder)), [] as Array[String])
	var ids: Array[StringName] = []
	for id: StringName in found:
		ids.append(id)
	ids.sort_custom(_name_less)
	var result: Array[Resource] = []
	for id in ids:
		result.append(found[id] as Resource)
	return result


## Every `.tres` with an `id` below `folder_path`, by id (the first in sorted path order wins a
## duplicate, with a warning, and a line in `duplicates`).
static func _read_folder(folder_path: String, duplicates: Array[String]) -> Dictionary:
	var found: Dictionary = {}
	for path: String in _find_files(folder_path, PackedStringArray(["tres"]), SOUNDS_FOLDER):
		var res: Resource = ResourceLoader.load(path)
		if res == null or not ("id" in res):
			continue
		var id: StringName = res.get("id")
		if id == &"":
			continue
		if found.has(id):
			push_warning("Registry: duplicate id '%s' in %s (kept %s)" % [id, path, (found[id] as Resource).resource_path])
			duplicates.append("'%s' in %s, kept %s" % [id, path, (found[id] as Resource).resource_path])
			continue
		found[id] = res
	return found


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


## Runs the spell validator on everything found under `spells`, on the
## reaction table `<content root>/spells/reactions.tres`, which is skipped when there is
## none, and on every staff found under `wizard` (`SpellValidator.check_staff`). Returns the problems as `SpellValidator` describes them; empty when all is well.
func validate_spells() -> Array[Dictionary]:
	var spells: Array[Resource] = []
	var found: Dictionary = _resources.get(&"spells", {})
	for id: StringName in found:
		spells.append(found[id] as Resource)
	var reactions: ReactionTable = null
	var table_path: String = _content_root.path_join("spells/reactions.tres")
	if ResourceLoader.exists(table_path):
		reactions = ResourceLoader.load(table_path) as ReactionTable
	var problems: Array[Dictionary] = SpellValidator.check_all(spells, reactions, SpellValidator.load_manifest(), _duplicates)
	# The staffs (staffs A3) live under `wizard` with the other wizard content.
	for res: Resource in _resources.get(&"wizard", {}).values():
		if res is StaffBase:
			problems.append_array(SpellValidator.check_staff(res as StaffBase))
	return problems


## The problems with the game's words: each spell card's description (`SpellComponent.description`,
## `SpellValidator.check_descriptions`), each enemy's and boss's lore (`EnemyBase.lore`,
## `StoryValidator.check_lore`; a missing one only warns) and what a boss says in its intro
## (`BossIntro.lines`, `StoryValidator.check_speech`).
func validate_story() -> Array[Dictionary]:
	var cards: Array[SpellComponent] = []
	for res: Resource in get_all(&"spells"):
		if res is SpellComponent:
			cards.append(res as SpellComponent)
	var problems: Array[Dictionary] = SpellValidator.check_descriptions(cards)
	for folder: StringName in EnemyBase.FOLDERS:
		for res: Resource in get_all(folder):
			if res is EnemyBase:
				var enemy := res as EnemyBase
				problems.append_array(StoryValidator.check_lore(enemy.resource_path, enemy.lore, enemy.boss))
				if enemy.boss_intro != null:
					problems.append_array(StoryValidator.check_speech(enemy.resource_path, enemy.boss_intro.lines))
	return problems


## What a run can be made of (run generation RG1, `RunContent`): the room kinds (`room_kinds`), the
## rooms and the enemies and bosses (`EnemyBase.FOLDERS`) found in the last scan.
func run_content() -> RunContent:
	var enemies: Array[Resource] = []
	for folder: StringName in EnemyBase.FOLDERS:
		enemies.append_array(get_all(folder))
	return RunContent.gather(get_all(&"room_kinds"), get_all(&"rooms"), enemies)


## What keeps a map of the run `run_id` from being made from the content there is, one line each
## (empty when nothing does): no run of that id under `runs`, or its definition's problems
## (`RunDefinition.problems` on `run_content()`, as the generator checks them). Asked before a run's
## start frees anything (Flow). The rolls of a map can still corner it (only `KindRule.not_after`
## can; gameplay/run/run_generator.gd), which only the run's seed tells.
func run_problems(run_id: StringName) -> PackedStringArray:
	var definition := get_resource(&"runs", run_id) as RunDefinition
	if definition == null:
		return PackedStringArray(["No run '%s' in the registry." % run_id])
	return definition.problems(run_content())


## The problems with the runs (`runs`: each `RunDefinition.problems` on `run_content()`), each room
## kind's (`RoomKind.problems`), each room's as a run's template (`RoomBase.template_problems`) and
## more save flags named by the runs' rule changes than a run's start carries, one line each; empty when every run can be made from the content there is.
func validate_runs() -> PackedStringArray:
	var content: RunContent = run_content()
	var found := PackedStringArray()
	for kind: StringName in content.kind_ids():
		found.append_array(content.kind(kind).problems())
	var known: Array[StringName] = content.kind_ids()
	for room: RoomBase in content.rooms:
		found.append_array(room.template_problems(known))
	var flags: Array[StringName] = []
	for res: Resource in get_all(&"runs"):
		if res is RunDefinition:
			found.append_array((res as RunDefinition).problems(content))
			for flag: StringName in (res as RunDefinition).flags():
				if not flags.has(flag):
					flags.append(flag)
	# A run's start carries the save flags every run's changes name (run generation RG6).
	if flags.size() > RunUnlocks.MAX_FLAGS:
		found.append("The runs' rule changes name %d save flags, more than the %d a run's start carries (RunUnlocks.MAX_FLAGS)." % [flags.size(), RunUnlocks.MAX_FLAGS])
	return found


## Pushes one warning per problem `validate_runs()` finds, and returns how many.
func warn_run_problems() -> int:
	var problems: PackedStringArray = validate_runs()
	for line: String in problems:
		push_warning("Registry: " + line)
	return problems.size()


## The resource with this id in this folder, or `null` when there is none.
func get_resource(folder: StringName, id: StringName) -> Resource:
	var found: Dictionary = _resources.get(folder, {})
	return found.get(id) as Resource


## Register `resource` under its `id` in `folder`, as a scan would have found it there (tests: a
## fixture beside the content, on a registry of their own). False, and nothing changes, when it has
## no id or the folder already holds that id.
func add(folder: StringName, resource: Resource) -> bool:
	var id: StringName = resource.get("id") if resource != null and "id" in resource else &""
	var found: Dictionary = _resources.get(folder, {})
	if id == &"" or found.has(id):
		return false
	found[id] = resource
	_resources[folder] = found
	var ids: Array[StringName] = get_ids(folder)
	ids.append(id)
	ids.sort_custom(_name_less)
	_ids[folder] = ids
	return true


## Take the resource of id `id` out of `folder` (tests: undo an `add` on the game's registry, so a
## fixture is not left for the next suite). False when the folder has no such id.
func remove(folder: StringName, id: StringName) -> bool:
	var found: Dictionary = _resources.get(folder, {})
	if not found.has(id):
		return false
	found.erase(id)
	var ids: Array[StringName] = get_ids(folder)
	ids.erase(id)
	_ids[folder] = ids
	return true


## Every id in the folder, sorted. Empty for an unknown folder.
func get_ids(folder: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_ids.get(folder, []))
	return result


## Every resource in the folder, in id order.
func get_all(folder: StringName) -> Array[Resource]:
	var result: Array[Resource] = []
	for id: StringName in get_ids(folder):
		result.append((_resources[folder] as Dictionary)[id] as Resource)
	return result


## Folders that hold at least one resource, sorted.
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



## Names in one directory, sorted. Exported games list imported files with a
## `.remap` or `.import` suffix; it is removed, so the same name works in the
## editor and in an export.
static func _list_dir(path: String, directories: bool) -> PackedStringArray:
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
## A folder named `skip` (a content item's `sounds/`) is not looked in.
static func _find_files(root: String, extensions: PackedStringArray, skip: String = "") -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	_collect_files(root, extensions, found, skip)
	found.sort()
	return found


static func _collect_files(root: String, extensions: PackedStringArray, found: PackedStringArray, skip: String = "") -> void:
	for file_name: String in _list_dir(root, false):
		if extensions.has(file_name.get_extension()):
			found.append(root.path_join(file_name))
	for sub: String in _list_dir(root, true):
		if skip != "" and sub == skip:
			continue
		_collect_files(root.path_join(sub), extensions, found, skip)
