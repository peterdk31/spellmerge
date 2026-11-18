extends RefCounted
## Feel's held sounds (boss plan OB15; docs/milestones/sound.md, section 5): what each held sound is
## for, and when it ends. Audio plays them (`Audio.hold`, its handles, the fade, following a body);
## Feel decides: a cue's `held` part (`CueBase`) is held for its caster until its moment ends, and a
## phase's sound (`body_sounds.gd`) while the phase lasts.
##
## A held sound is a caster's (an actor id, or -1) and has its `Until`: its seconds only; the wind-up
## of its caster's staff `key` (`Spells.is_winding`, read each frame, as the telegraph lanes read it);
## its carrier, the spell tagged `key`, ending (`end_carrier`); or being let go (`release`: a phase's,
## `key` the phase). One held sound a caster and id: a new one takes the old one's place, and goes on
## with no restart (Audio's `take`). Its seconds, its body leaving and its fade are Audio's.
##
## At most `AudioScript.HeldScript.SLOTS` entries, as many as Audio's slots: an entry lasts while its
## handle has its slot (held or fading), so nothing is allocated while playing.

const AudioScript := preload("res://core/audio/audio.gd")

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

const SLOTS: int = AudioScript.HeldScript.SLOTS

## The Audio service they play on, and the spell runtime a wind-up is read from.
var audio: AudioScript = null
var spells: Node = null

## The entries, the first `count` of each list.
var count: int = 0
var _id: Array[StringName] = []
var _until: PackedInt32Array = PackedInt32Array()
var _caster: PackedInt32Array = PackedInt32Array()
var _key: PackedInt64Array = PackedInt64Array()
var _handle: PackedInt64Array = PackedInt64Array()


func _init() -> void:
	_id.resize(SLOTS)
	_until.resize(SLOTS)
	_caster.resize(SLOTS)
	_key.resize(SLOTS)
	_handle.resize(SLOTS)


## Holds the sound `id` for `caster` until `until` with its `key` says it ends, or `seconds`,
## following `follow` (null: it stays at `at`), `volume` decibels on top of its own. The handle, or 0
## for none (no such sound). The same caster's held `id` is taken over.
func hold(id: StringName, until: int, caster: int, key: int, follow: Node2D, at: Vector2, seconds: float, volume: float = 0.0) -> int:
	if audio == null:
		return 0
	_purge()
	var at_entry: int = -1
	for i in count:
		if _caster[i] == caster and _id[i] == id:
			at_entry = i
			break
	var handle: int = audio.hold(id, follow, at, seconds, volume, AudioScript.BUS_SFX, _handle[at_entry] if at_entry >= 0 else 0)
	if handle == 0:
		return 0
	if at_entry < 0:
		# Audio may have let one of ours go for this one (all its slots full).
		_purge()
		if count >= SLOTS:
			return handle
		at_entry = count
		count += 1
	_id[at_entry] = id
	_until[at_entry] = until
	_caster[at_entry] = caster
	_key[at_entry] = key
	_handle[at_entry] = handle
	return handle


## The carrier tagged `tag` that `caster` showed ended (`carrier_ended`): its held sounds fade.
func end_carrier(caster: int, tag: int) -> void:
	for i in count:
		if _until[i] == Until.CARRIER and _caster[i] == caster and _key[i] == tag:
			audio.release(_handle[i])


## Lets go of `caster`'s held sounds of the kind `until` (a phase's, as the next starts).
func release(caster: int, until: int) -> void:
	for i in count:
		if _until[i] == until and _caster[i] == caster:
			audio.release(_handle[i])


## The sound `caster` holds of the kind `until` and not yet let go (&"" for none).
func held_of(caster: int, until: int) -> StringName:
	for i in count:
		if _until[i] == until and _caster[i] == caster and audio.is_held(_handle[i]):
			return _id[i]
	return &""


## Whether `caster` holds the sound `id`, not yet let go.
func is_held(caster: int, id: StringName) -> bool:
	for i in count:
		if _caster[i] == caster and _id[i] == id and audio.is_held(_handle[i]):
			return true
	return false


## Where the held sound `id` of `caster` is now (INF for none; for tests).
func held_at(caster: int, id: StringName) -> Vector2:
	for i in count:
		if _caster[i] == caster and _id[i] == id:
			return audio.held_at(_handle[i])
	return Vector2.INF


## Once a frame: a wind-up's sound whose wind-up is over is let go, and an entry whose sound is gone
## is dropped.
func step() -> void:
	if audio == null:
		return
	_purge()
	for i in count:
		if _until[i] == Until.WIND and audio.is_held(_handle[i]) and not _winding(i):
			audio.release(_handle[i])


## Every entry dropped (a new room: Audio's world was cleared).
func clear() -> void:
	count = 0


func _winding(i: int) -> bool:
	return spells != null and bool(spells.call(&"is_winding", _caster[i], int(_key[i])))


## Drops every entry whose sound no longer has its slot in Audio; the last takes its place.
func _purge() -> void:
	var i: int = 0
	while i < count:
		if audio.has_held(_handle[i]):
			i += 1
			continue
		var last: int = count - 1
		_id[i] = _id[last]
		_until[i] = _until[last]
		_caster[i] = _caster[last]
		_key[i] = _key[last]
		_handle[i] = _handle[last]
		_id[last] = &""
		count = last
