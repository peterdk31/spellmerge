extends Node
## Held sounds (core/audio, docs/milestones/sound.md, section 5): a sound that loops while its moment
## lasts, on one of SLOTS slots made once in `_ready`; nothing is allocated while playing. Moved from
## Feel's sounds (boss plan OB15) with no change in what is heard.
##
## `hold` gives a handle (a number never given twice). The sound loops from the `Node2D` it follows
## (or where it started, with none) until it is let go (`release`, `release_all`), its seconds run
## out or the node it follows leaves the tree; then it fades out over FADE and its slot is free.
## What a held sound is for (a wind-up, a carrier, a phase) is its caller's: Audio knows nothing of
## bodies or spells. `take` hands an earlier handle's slot over to the new hold, which goes on playing
## without a restart when its stream is the same (a held sound taken over by the same moment again).
## One more than SLOTS takes the place of the one with the least time left.
##
## Its voices are `AudioStreamPlayer2D`s, placed as Audio's world voices are (`ears`: heard from the
## view that shows them while the screen is split). One where nobody hears (`ears.hears`, connected
## biomes CB12: a fire in a room none of this machine's wizards are in) keeps its slot and its loop
## but is silent, going down or up over FADE as it stops or starts being heard. Only `audible`
## starts a voice (Audio's).

const EarsScript := preload("res://core/audio/ears.gd")

## Held sounds at once.
const SLOTS: int = 16
## Seconds a held sound fades out over once it is let go.
const FADE: float = 0.12
## The least share of a voice's loudness set (-80 dB: silent, never minus infinity).
const SILENT: float = 0.0001

var heard: float = 1600.0
var attenuation: float = 0.7
var pan: float = 1.0
## Whether its voices are started (Audio's `audible`).
var audible: bool = true
## Where its sounds are heard from and which are heard (Audio's; its own with none).
var ears: EarsScript = EarsScript.new()

## The held sounds under way: the first `held_count` of each list.
var held_count: int = 0
var _voices: Array[AudioStreamPlayer2D] = []
var _handle: PackedInt64Array = PackedInt64Array()
var _follow: Array[Node2D] = []
var _followed: PackedByteArray = PackedByteArray()
var _left: PackedFloat32Array = PackedFloat32Array()
## Seconds of its fade left (-1: not fading), and its volume in decibels.
var _fade: PackedFloat32Array = PackedFloat32Array()
var _volume: PackedFloat32Array = PackedFloat32Array()
## How much of it is heard (0 to 1: 0 where nobody hears it).
var _gain: PackedFloat32Array = PackedFloat32Array()
## Where each is in the world (before `ears` places it).
var _at: PackedVector2Array = PackedVector2Array()
var _last_handle: int = 0


func _ready() -> void:
	_handle.resize(SLOTS)
	_followed.resize(SLOTS)
	_left.resize(SLOTS)
	_fade.resize(SLOTS)
	_volume.resize(SLOTS)
	_gain.resize(SLOTS)
	_at.resize(SLOTS)
	for i in SLOTS:
		var voice := AudioStreamPlayer2D.new()
		voice.max_distance = heard
		voice.attenuation = attenuation
		voice.panning_strength = pan
		add_child(voice)
		_voices.append(voice)
		_follow.append(null)


## Leaving the tree (the game quitting): every voice lets go of its stream.
func _exit_tree() -> void:
	clear()


## Holds `stream` for `seconds` (INF: until let go), following `follow` (null: it stays at `at`),
## `volume` decibels on top of its own, on `bus`; `take` is an earlier handle whose slot it takes
## over (0: none). The handle, or 0 for none (no stream, no seconds).
func hold(stream: AudioStream, follow: Node2D, at: Vector2, seconds: float, volume: float, bus: StringName, take: int = 0) -> int:
	if stream == null or seconds <= 0.0:
		return 0
	var slot: int = _slot_of(take) if take != 0 else -1
	if slot < 0:
		if held_count < SLOTS:
			slot = held_count
			held_count += 1
		else:
			slot = 0
			for i in held_count:
				if _left[i] < _left[slot]:
					slot = i
	var voice: AudioStreamPlayer2D = _voices[slot]
	var again: bool = voice.stream != stream or not voice.playing
	_last_handle += 1
	_handle[slot] = _last_handle
	var followed: bool = follow != null and is_instance_valid(follow)
	_follow[slot] = follow if followed else null
	_followed[slot] = 1 if followed else 0
	_left[slot] = seconds
	_fade[slot] = -1.0
	_volume[slot] = volume
	var where: Vector2 = follow.global_position if followed else at
	_at[slot] = where
	if again:
		_gain[slot] = 1.0 if ears.hears(where) else 0.0
	voice.volume_db = volume + linear_to_db(maxf(_gain[slot], SILENT))
	voice.bus = bus
	voice.global_position = ears.place(where)
	if again:
		voice.stream = stream
		if audible:
			voice.play()
	return _last_handle


## Lets go of the held sound `handle`: it fades out.
func release(handle: int) -> void:
	var slot: int = _slot_of(handle)
	if slot >= 0 and _fade[slot] < 0.0:
		_fade[slot] = FADE


## Lets go of every held sound: each fades out.
func release_all() -> void:
	for i in held_count:
		if _fade[i] < 0.0:
			_fade[i] = FADE


## Whether `handle` is held and not yet let go.
func is_held(handle: int) -> bool:
	var slot: int = _slot_of(handle)
	return slot >= 0 and _fade[slot] < 0.0


## Whether `handle` still has its slot (held, or fading out after it was let go).
func has(handle: int) -> bool:
	return _slot_of(handle) >= 0


## Where the held sound `handle` is now in the world (INF for none).
func held_at(handle: int) -> Vector2:
	var slot: int = _slot_of(handle)
	return _at[slot] if slot >= 0 else Vector2.INF


## How much of the held sound `handle` is heard now (0 to 1; 0 for none).
func gain_of(handle: int) -> float:
	var slot: int = _slot_of(handle)
	return _gain[slot] if slot >= 0 else 0.0


## The voice of the held sound `handle` (null for none; for tests).
func voice_of(handle: int) -> AudioStreamPlayer2D:
	var slot: int = _slot_of(handle)
	return _voices[slot] if slot >= 0 else null


## Once a frame, `delta` real seconds on: each held sound follows its node, ends when its seconds or
## its node did, fades out and loops while it lasts.
func step(delta: float) -> void:
	var i: int = 0
	while i < held_count:
		var voice: AudioStreamPlayer2D = _voices[i]
		if _fade[i] >= 0.0:
			_fade[i] -= delta
			if _fade[i] <= 0.0:
				_remove(i)
				continue
			voice.volume_db = _volume[i] + linear_to_db(maxf(_gain[i] * _fade[i] / FADE, SILENT))
			i += 1
			continue
		_left[i] -= delta
		# A freed node is let go of here, never read as a node (`_valid`).
		var follow: Node2D = _valid(i)
		var gone: bool = _followed[i] == 1 and (follow == null or not follow.is_inside_tree())
		if gone or _left[i] <= 0.0:
			_fade[i] = FADE
			i += 1
			continue
		if _followed[i] == 1:
			_at[i] = follow.global_position
		voice.global_position = ears.place(_at[i])
		var gain: float = move_toward(_gain[i], 1.0 if ears.hears(_at[i]) else 0.0, delta / FADE)
		if gain != _gain[i]:
			_gain[i] = gain
			voice.volume_db = _volume[i] + linear_to_db(maxf(gain, SILENT))
		if audible and not voice.playing:
			voice.play()
		i += 1


## Every held sound stops at once (a new room: what held them is gone).
func clear() -> void:
	while held_count > 0:
		_remove(held_count - 1)


## The node held sound `i` follows, or null for none or one that was freed (which it lets go of).
func _valid(i: int) -> Node2D:
	# Not valid: none, or freed.
	if not is_instance_valid(_follow[i]):
		_follow[i] = null
		return null
	return _follow[i]


func _slot_of(handle: int) -> int:
	if handle == 0:
		return -1
	for i in held_count:
		if _handle[i] == handle:
			return i
	return -1


## Held sound `i` goes; the last one takes its place.
func _remove(i: int) -> void:
	var last: int = held_count - 1
	var gone: AudioStreamPlayer2D = _voices[i]
	gone.stop()
	gone.stream = null
	if i != last:
		_voices[i] = _voices[last]
		_voices[last] = gone
		_handle[i] = _handle[last]
		# The last one's node may have been freed since it was last stepped (a body that died this
		# frame): a freed node cannot be put into the list, so it moves as none, and its sound ends
		# at its next step as any whose node is gone.
		_follow[i] = _valid(last)
		_followed[i] = _followed[last]
		_left[i] = _left[last]
		_fade[i] = _fade[last]
		_volume[i] = _volume[last]
		_gain[i] = _gain[last]
		_at[i] = _at[last]
	_follow[last] = null
	_handle[last] = 0
	held_count = last
