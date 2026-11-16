extends Node2D
## Feel's sounds (boss plan OB15, docs/milestones/boss-old-broom.md, "Sound"): every sound the game
## plays but its music (`music.gd`), drawn only like the rest of Feel, never fed back into the game.
## Feel owns one and steps it once a frame; it lives under Feel (world space), never in the scene.
##
## **One-shots** (`play`): a sound id from the registry (nothing on `null`: silent until an `.ogg`
## exists), on one of VOICES voices, where it happens in the room (`AudioStreamPlayer2D`: panned and
## quieter from the middle of the picture, heard up to HEARD pixels away, so a telegraph off screen
## is still heard). At most PER_SOUND voices play one id at once: one more starts again on the
## oldest of them rather than cutting short another sound (with a cue's `every`, how a sound that
## comes by the hundred stays a few).
##
## **Held sounds** (`hold`): a sound that lasts while its moment lasts (a cue's `held` part;
## `CueBase`): it loops from the body it follows (or where it started, with none) until it is let go
## (`end_carrier`, `release`), a wind-up it lasts for is over (`Spells.is_winding`, read here as
## the telegraph lanes read it), its seconds run out or its body is gone; then it fades out over
## FADE. One held sound a caster and id: a new one takes the old one's place.
##
## Nothing is allocated while playing: the voices are made once.

## One-shot voices, and how many may play one sound id at once.
const VOICES: int = 8
const PER_SOUND: int = 3
## Held sounds at once; one more takes the place of the one with the least time left.
const HELD_MOST: int = 16
## Pixels from the middle of the picture a sound is heard to, and how steeply it falls off.
const HEARD: float = 1600.0
const ATTENUATION: float = 0.7
## Seconds a held sound fades out over once it is let go.
const FADE: float = 0.12
## The least seconds a one-shot counts as playing (a sound of no length still holds its voice for
## this long, so the per-sound limit holds within a frame).
const MIN_SECONDS: float = 0.05

## What ends a held sound besides its seconds and its body (`hold`'s `until`).
enum Until {
	## Its seconds only.
	SECONDS,
	## The wind-up of its caster's staff `key` (`Spells.is_winding`).
	WIND,
	## Its carrier, the spell tagged `key`, ending (`end_carrier`).
	CARRIER,
	## Being let go (`release`): a phase's sound, `key` the phase.
	PHASE,
}

## The registry the sounds are asked of (`get_sound`), and the spell runtime a wind-up is read from.
var registry: Node = null
var spells: Node = null

var _voices: Array[AudioStreamPlayer2D] = []
var _voice_id: Array[StringName] = []
## Feel's clock until each voice counts as done, and when it started (the oldest goes first).
var _voice_until: PackedFloat64Array = PackedFloat64Array()
var _voice_from: PackedFloat64Array = PackedFloat64Array()
var _next_voice: int = 0
## One-shots started, and the last one's id, for tests.
var started: int = 0
var last: StringName = &""
var _clock: float = 0.0

## The held sounds under way: the first `held_count` of each list.
var held_count: int = 0
var _held: Array[AudioStreamPlayer2D] = []
var _h_id: Array[StringName] = []
var _h_until: PackedInt32Array = PackedInt32Array()
var _h_caster: PackedInt32Array = PackedInt32Array()
var _h_key: PackedInt64Array = PackedInt64Array()
var _h_follow: Array[Node2D] = []
var _h_followed: PackedByteArray = PackedByteArray()
var _h_left: PackedFloat32Array = PackedFloat32Array()
## Seconds of its fade left (-1: not fading), and its volume in decibels.
var _h_fade: PackedFloat32Array = PackedFloat32Array()
var _h_volume: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	top_level = true
	for i in VOICES:
		_voices.append(_voice())
		_voice_id.append(&"")
	_voice_until.resize(VOICES)
	_voice_from.resize(VOICES)
	_voice_until.fill(-INF)
	_h_until.resize(HELD_MOST)
	_h_caster.resize(HELD_MOST)
	_h_key.resize(HELD_MOST)
	_h_followed.resize(HELD_MOST)
	_h_left.resize(HELD_MOST)
	_h_fade.resize(HELD_MOST)
	_h_volume.resize(HELD_MOST)
	for i in HELD_MOST:
		_held.append(_voice())
		_h_id.append(&"")
		_h_follow.append(null)


func _voice() -> AudioStreamPlayer2D:
	var voice := AudioStreamPlayer2D.new()
	voice.max_distance = HEARD
	voice.attenuation = ATTENUATION
	add_child(voice)
	return voice


## Plays the sound `id` at `at` (INF: the middle of the picture), `volume` decibels on top of its
## own; the voice used, or -1 for none (no registry, no such sound).
func play(id: StringName, at: Vector2 = Vector2.INF, volume: float = 0.0) -> int:
	var sound: AudioStream = _sound(id)
	if sound == null:
		return -1
	var used: int = _voice_for(id)
	var voice: AudioStreamPlayer2D = _voices[used]
	voice.stream = sound
	voice.volume_db = volume
	voice.global_position = at if at.is_finite() else _middle()
	voice.play()
	_voice_id[used] = id
	_voice_from[used] = _clock
	_voice_until[used] = _clock + maxf(sound.get_length(), MIN_SECONDS)
	started += 1
	last = id
	return used


## Stops the one-shot on `voice` (a killing blow's sound giving way to the death's).
func stop(voice: int) -> void:
	if voice >= 0 and voice < VOICES:
		_voices[voice].stop()
		_voice_until[voice] = -INF


## How many voices play the sound `id` now (for tests and the per-sound limit).
func voices_of(id: StringName) -> int:
	var count: int = 0
	for i in VOICES:
		if _voice_id[i] == id and _clock < _voice_until[i]:
			count += 1
	return count


## The voices that hold a stream (for tests).
func voices_with_stream() -> int:
	var count: int = 0
	for voice in _voices:
		if voice.stream != null:
			count += 1
	return count


## Holds the sound `id` for `caster` (an actor id, or -1) until `until` with its `key` says it ends,
## or `seconds`, following `follow` (null: it stays at `at`), `volume` decibels on top of its own.
## The held slot, or -1 for none (no such sound). The same caster's held `id` is taken over.
func hold(id: StringName, until: int, caster: int, key: int, follow: Node2D, at: Vector2, seconds: float, volume: float = 0.0) -> int:
	var sound: AudioStream = _sound(id)
	if sound == null or seconds <= 0.0:
		return -1
	var slot: int = -1
	for i in held_count:
		if _h_caster[i] == caster and _h_id[i] == id:
			slot = i
			break
	if slot < 0:
		if held_count < HELD_MOST:
			slot = held_count
			held_count += 1
		else:
			slot = 0
			for i in held_count:
				if _h_left[i] < _h_left[slot]:
					slot = i
	var voice: AudioStreamPlayer2D = _held[slot]
	var again: bool = voice.stream != sound or not voice.playing
	_h_id[slot] = id
	_h_until[slot] = until
	_h_caster[slot] = caster
	_h_key[slot] = key
	var followed: bool = follow != null and is_instance_valid(follow)
	_h_follow[slot] = follow if followed else null
	_h_followed[slot] = 1 if followed else 0
	_h_left[slot] = seconds
	_h_fade[slot] = -1.0
	_h_volume[slot] = volume
	voice.volume_db = volume
	voice.global_position = follow.global_position if followed else (at if at.is_finite() else _middle())
	if again:
		voice.stream = sound
		voice.play()
	return slot


## The carrier tagged `tag` that `caster` showed ended (`carrier_ended`): its held sounds fade.
func end_carrier(caster: int, tag: int) -> void:
	for i in held_count:
		if _h_until[i] == Until.CARRIER and _h_caster[i] == caster and _h_key[i] == tag:
			_let_go(i)


## Lets go of `caster`'s held sounds of the kind `until` (a phase's, as the next starts).
func release(caster: int, until: int) -> void:
	for i in held_count:
		if _h_until[i] == until and _h_caster[i] == caster:
			_let_go(i)


## The sound `caster` holds of the kind `until` and not yet let go (&"" for none).
func held_of(caster: int, until: int) -> StringName:
	for i in held_count:
		if _h_until[i] == until and _h_caster[i] == caster and _h_fade[i] < 0.0:
			return _h_id[i]
	return &""


## Whether `caster` holds the sound `id`, not yet let go (for tests).
func is_held(caster: int, id: StringName) -> bool:
	for i in held_count:
		if _h_caster[i] == caster and _h_id[i] == id and _h_fade[i] < 0.0:
			return true
	return false


## Where the held sound `id` of `caster` is now (INF for none; for tests).
func held_at(caster: int, id: StringName) -> Vector2:
	for i in held_count:
		if _h_caster[i] == caster and _h_id[i] == id:
			return _held[i].global_position
	return Vector2.INF


## Once a frame, `delta` real seconds on: each held sound follows its body, ends when its moment
## did, fades out and loops while it lasts.
func step(delta: float) -> void:
	_clock += delta
	var i: int = 0
	while i < held_count:
		var voice: AudioStreamPlayer2D = _held[i]
		if _h_fade[i] >= 0.0:
			_h_fade[i] -= delta
			if _h_fade[i] <= 0.0:
				_remove(i)
				continue
			voice.volume_db = _h_volume[i] + linear_to_db(_h_fade[i] / FADE)
			i += 1
			continue
		_h_left[i] -= delta
		var follow: Node2D = _h_follow[i]
		var gone: bool = _h_followed[i] == 1 and (follow == null or not is_instance_valid(follow) or not follow.is_inside_tree())
		if gone or _h_left[i] <= 0.0 or (_h_until[i] == Until.WIND and not _winding(i)):
			_let_go(i)
			i += 1
			continue
		if _h_followed[i] == 1:
			voice.global_position = follow.global_position
		if not voice.playing:
			voice.play()
		i += 1


## Every sound stops at once (a new room: what held them is gone).
func clear() -> void:
	for voice in _voices:
		voice.stop()
		voice.stream = null
	_voice_until.fill(-INF)
	while held_count > 0:
		_remove(held_count - 1)


## The voice a new one-shot of `id` takes: past PER_SOUND of it playing, the oldest of them; else the
## next in turn.
func _voice_for(id: StringName) -> int:
	var same: int = 0
	var oldest: int = -1
	for i in VOICES:
		if _voice_id[i] == id and _clock < _voice_until[i]:
			same += 1
			if oldest < 0 or _voice_from[i] < _voice_from[oldest]:
				oldest = i
	if same >= PER_SOUND:
		return oldest
	var used: int = _next_voice
	_next_voice = (_next_voice + 1) % VOICES
	return used


func _sound(id: StringName) -> AudioStream:
	if registry == null or id == &"":
		return null
	return registry.call(&"get_sound", id) as AudioStream


func _winding(i: int) -> bool:
	return spells != null and bool(spells.call(&"is_winding", _h_caster[i], int(_h_key[i])))


## The middle of the picture (where a sound of no place is heard from).
func _middle() -> Vector2:
	var camera: Camera2D = get_viewport().get_camera_2d() if is_inside_tree() else null
	return camera.get_screen_center_position() if camera != null else Vector2.ZERO


func _let_go(i: int) -> void:
	if _h_fade[i] < 0.0:
		_h_fade[i] = FADE


## Held sound `i` goes; the last one takes its place.
func _remove(i: int) -> void:
	var last: int = held_count - 1
	var gone: AudioStreamPlayer2D = _held[i]
	gone.stop()
	gone.stream = null
	if i != last:
		_held[i] = _held[last]
		_held[last] = gone
		_h_id[i] = _h_id[last]
		_h_until[i] = _h_until[last]
		_h_caster[i] = _h_caster[last]
		_h_key[i] = _h_key[last]
		_h_follow[i] = _h_follow[last]
		_h_followed[i] = _h_followed[last]
		_h_left[i] = _h_left[last]
		_h_fade[i] = _h_fade[last]
		_h_volume[i] = _h_volume[last]
	_h_follow[last] = null
	_h_id[last] = &""
	held_count = last
