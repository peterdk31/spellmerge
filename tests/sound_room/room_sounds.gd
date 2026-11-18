extends Node
## The sound room's registry for its Audio (docs/milestones/sound.md, section 7): a sound is asked of
## each of `sources` in turn (the fixtures' registry, then the game's), and the first that has it
## answers. Only `get_sound` is asked of it, as of any registry Audio is handed.

var sources: Array[Node] = []


func get_sound(id: StringName) -> AudioStream:
	for source: Node in sources:
		var found: AudioStream = source.call(&"get_sound", id) as AudioStream
		if found != null:
			return found
	return null
