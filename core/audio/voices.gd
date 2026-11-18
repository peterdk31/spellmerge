extends Node
## A set of one-shot voices (core/audio, docs/milestones/sound.md, section 5): Audio's, made once in
## `_ready`, `count` of them; nothing is allocated while playing. Moved from Feel's sounds (boss plan
## OB15) with no change in what is heard.
##
## `play` puts a sound on a voice: one that is done (looked for from the next in turn), else the one
## that started first; at most `per_sound` voices play one id at once, and one more starts again on
## the oldest of them rather than cutting short another sound. A voice counts as playing for its
## sound's length (`AudioLength.of`: a randomizer's longest variant), at least MIN_SECONDS, by its own
## clock (`step`).
##
## **Placed** voices (`positional`) are `AudioStreamPlayer2D`s, heard from where the sound happens:
## panned by PAN (Audio's) and quieter from the middle of the picture, up to `heard` pixels away.
## The others are plain `AudioStreamPlayer`s, heard the same everywhere (the UI's, a boss intro's).
## Only `audible` starts a voice (Audio's: none on the audio driver with no device).

## The least seconds a one-shot counts as playing (a sound of no length still holds its voice for
## this long, so the per-sound limit holds within a frame).
const MIN_SECONDS: float = 0.05

## How many voices, how many may play one id at once, whether they are placed, their bus, and (placed)
## how far they are heard, how steeply they fall off and how far they pan. Set before `_ready`.
var count: int = 8
var per_sound: int = 3
var positional: bool = true
var bus: StringName = &"Master"
var heard: float = 1600.0
var attenuation: float = 0.7
var pan: float = 1.0
## Whether its voices are started (Audio's `audible`).
var audible: bool = true
## One-shots started, and the last one's id, for tests.
var started: int = 0
var last: StringName = &""

var _placed: Array[AudioStreamPlayer2D] = []
var _flat: Array[AudioStreamPlayer] = []
var _voice_id: Array[StringName] = []
## Its clock until each voice counts as done, and when it started (the oldest goes first).
var _until: PackedFloat64Array = PackedFloat64Array()
var _from: PackedFloat64Array = PackedFloat64Array()
var _next: int = 0
var _clock: float = 0.0


func _ready() -> void:
	for i in count:
		if positional:
			var voice := AudioStreamPlayer2D.new()
			voice.max_distance = heard
			voice.attenuation = attenuation
			voice.panning_strength = pan
			voice.bus = bus
			add_child(voice)
			_placed.append(voice)
		else:
			var flat := AudioStreamPlayer.new()
			flat.bus = bus
			add_child(flat)
			_flat.append(flat)
		_voice_id.append(&"")
	_until.resize(count)
	_from.resize(count)
	_until.fill(-INF)


## Leaving the tree (the game quitting): every voice lets go of its stream.
func _exit_tree() -> void:
	clear()


## Plays `stream` (the sound `id`) at `at` (placed voices only), `volume` decibels on top of its own,
## on `on_bus` (empty: its own bus); the voice used, or -1 for none (no stream).
func play(id: StringName, stream: AudioStream, at: Vector2, volume: float, on_bus: StringName = &"") -> int:
	if stream == null:
		return -1
	var used: int = _voice_for(id)
	var to: StringName = on_bus if on_bus != &"" else bus
	if positional:
		var voice: AudioStreamPlayer2D = _placed[used]
		voice.stream = stream
		voice.volume_db = volume
		voice.bus = to
		voice.global_position = at
		if audible:
			voice.play()
	else:
		var flat: AudioStreamPlayer = _flat[used]
		flat.stream = stream
		flat.volume_db = volume
		flat.bus = to
		if audible:
			flat.play()
	_voice_id[used] = id
	_from[used] = _clock
	_until[used] = _clock + maxf(AudioLength.of(stream), MIN_SECONDS)
	started += 1
	last = id
	return used


## Stops the one-shot on `voice` (a killing blow's sound giving way to the death's).
func stop(voice: int) -> void:
	if voice < 0 or voice >= count:
		return
	if positional:
		_placed[voice].stop()
	else:
		_flat[voice].stop()
	_until[voice] = -INF


## How many voices play the sound `id` now (for tests and the per-sound limit).
func voices_of(id: StringName) -> int:
	var playing: int = 0
	for i in count:
		if _voice_id[i] == id and _clock < _until[i]:
			playing += 1
	return playing


## The voices that hold a stream (for tests).
func voices_with_stream() -> int:
	var holding: int = 0
	for i in count:
		if _stream_of(i) != null:
			holding += 1
	return holding


## The player of voice `voice` (for tests).
func player(voice: int) -> Node:
	if voice < 0 or voice >= count:
		return null
	return _placed[voice] if positional else _flat[voice]


## `delta` real seconds on (its clock: when each voice is done).
func step(delta: float) -> void:
	_clock += delta


## Every voice stops at once and lets go of its stream.
func clear() -> void:
	for voice in _placed:
		voice.stop()
		voice.stream = null
	for flat in _flat:
		flat.stop()
		flat.stream = null
	_until.fill(-INF)


func _stream_of(i: int) -> AudioStream:
	return _placed[i].stream if positional else _flat[i].stream


## The voice a new one-shot of `id` takes: past `per_sound` of it playing, the oldest of them; else
## a voice that is done (looked for from the next in turn), else the one that started first.
func _voice_for(id: StringName) -> int:
	var same: int = 0
	var oldest_same: int = -1
	var oldest: int = 0
	for i in count:
		if _clock < _until[i]:
			if _from[i] < _from[oldest]:
				oldest = i
			if _voice_id[i] == id:
				same += 1
				if oldest_same < 0 or _from[i] < _from[oldest_same]:
					oldest_same = i
	if same >= per_sound:
		return oldest_same
	for n in count:
		var i: int = (_next + n) % count
		if _clock >= _until[i]:
			_next = (i + 1) % count
			return i
	return oldest
