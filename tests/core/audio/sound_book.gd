extends Node
## A registry of a test's own for core/audio: every id in `known` is a silent stream (an 8 kHz WAV:
## `short` a tenth of a second, looping; `long` a second, once), made by the test itself, so no sound
## file is needed. Only `get_sound` is asked of it.

var known: Dictionary = {}
var short: AudioStreamWAV = wav(800, true)
var long: AudioStreamWAV = wav(8000, false)


## A silent stream of `samples` 8 kHz samples, looping or not.
static func wav(samples: int, loops: bool) -> AudioStreamWAV:
	var made := AudioStreamWAV.new()
	made.format = AudioStreamWAV.FORMAT_8_BITS
	made.mix_rate = 8000
	var data := PackedByteArray()
	data.resize(samples)
	made.data = data
	if loops:
		made.loop_mode = AudioStreamWAV.LOOP_FORWARD
		made.loop_end = samples
	return made


## Knows each of `ids` as the short stream.
func know(ids: Array) -> void:
	for id: Variant in ids:
		known[StringName(str(id))] = short


## Knows `id` as `stream`.
func know_as(id: StringName, stream: AudioStream) -> void:
	known[id] = stream


func get_sound(id: StringName) -> AudioStream:
	return known.get(id) as AudioStream
