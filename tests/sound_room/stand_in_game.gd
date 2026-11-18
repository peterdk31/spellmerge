extends Node
## A game of a sound room test's own: the registry calls the room asks (`get_folders`, `get_all`,
## `sound_ids`, `get_sound`) over resources and sounds the test puts in (`put`, `file`). A filed
## sound is a silent stream (`tests/core/audio/sound_book.gd`), looping when asked.

const SoundBook := preload("res://tests/core/audio/sound_book.gd")

var folders: Dictionary[StringName, Array] = {}
var sounds: Dictionary[StringName, AudioStream] = {}


## Puts `resource` in the folder `folder`.
func put(folder: StringName, resource: Resource) -> void:
	if not folders.has(folder):
		folders[folder] = []
	folders[folder].append(resource)


## Gives `id` a file: a short silent stream, looping or not.
func file(id: StringName, loops: bool = false) -> void:
	sounds[id] = SoundBook.wav(800, loops)


func get_folders() -> Array[StringName]:
	var found: Array[StringName] = []
	found.assign(folders.keys())
	return found


func get_all(folder: StringName) -> Array[Resource]:
	var found: Array[Resource] = []
	found.assign(folders.get(folder, []))
	return found


func sound_ids() -> Array[StringName]:
	var found: Array[StringName] = []
	found.assign(sounds.keys())
	found.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return found


func get_sound(id: StringName) -> AudioStream:
	return sounds.get(id) as AudioStream
