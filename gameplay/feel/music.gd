extends Node
## Feel's music (boss plan OB15, docs/milestones/boss-old-broom.md, "Sound"): plays one
## `MusicTrack` at an intensity, drawn only (nothing in the game reads it). Feel says which track
## and intensity (`play`: the room's, or a living enemy's with its phase's intensity) and steps it
## once a frame.
##
## Every layer of the track starts together and keeps playing, silent until its intensity comes, so
## the layers never drift apart; each fades to where its intensity puts it over the track's `fade`.
## A new track starts at once while the last one fades out on a second set of players. A layer whose
## sound does not exist is silent (the game has no music files yet). When the track's first layer
## has run out (a file not imported to loop), every layer starts again together.

## The players of the track playing and of the one fading out, a layer each.
var _now: Array[AudioStreamPlayer] = []
var _then: Array[AudioStreamPlayer] = []
## Each layer's level now (0-1) and whether it is to be heard, for the track playing.
var _level: PackedFloat32Array = PackedFloat32Array()
var _want: PackedByteArray = PackedByteArray()
## The level of the track fading out (0-1), and its fade's seconds.
var _then_level: float = 0.0
var _then_fade: float = 0.0

## The registry the layers' sounds are asked of (`get_sound`).
var registry: Node = null

var _track: MusicTrack = null
var _intensity: int = 0


func _ready() -> void:
	for i in MusicTrack.LAYERS_MOST:
		_now.append(_player())
		_then.append(_player())
	_level.resize(MusicTrack.LAYERS_MOST)
	_want.resize(MusicTrack.LAYERS_MOST)


func _player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.volume_db = linear_to_db(0.0)
	add_child(player)
	return player


## Plays `track` (null: silence) at `intensity` (1: its first layer): a new track starts and the last
## fades out; the same track only moves to the new intensity.
func play(track: MusicTrack, intensity: int) -> void:
	if track == _track:
		if track != null and intensity != _intensity:
			_intensity = intensity
			track.audible(intensity, _want)
		return
	# The track playing fades out as a whole, from the loudest of its layers.
	var loudest: float = 0.0
	for i in MusicTrack.LAYERS_MOST:
		loudest = maxf(loudest, _level[i])
		_then[i].stop()
		_then[i].stream = null
	var swap: Array[AudioStreamPlayer] = _then
	_then = _now
	_now = swap
	_then_level = loudest
	_then_fade = _track.fade if _track != null else 0.0
	_track = track
	_intensity = intensity
	_level.fill(0.0)
	_want.fill(0)
	if track == null:
		return
	track.audible(intensity, _want)
	var layers: int = mini(track.layers.size(), MusicTrack.LAYERS_MOST)
	for i in layers:
		var player: AudioStreamPlayer = _now[i]
		player.stream = registry.call(&"get_sound", track.layers[i]) as AudioStream if registry != null else null
		player.volume_db = linear_to_db(0.0)
	_start_all()


## Once a frame, `delta` real seconds on: each layer fades toward its level, the last track fades
## out, and a track run out starts again.
func step(delta: float) -> void:
	if _then_level > 0.0:
		_then_level = maxf(_then_level - (delta / _then_fade if _then_fade > 0.0 else 1.0), 0.0)
		for player in _then:
			player.volume_db = linear_to_db(_then_level)
			if _then_level == 0.0:
				player.stop()
				player.stream = null
	if _track == null:
		return
	var rate: float = delta / _track.fade if _track.fade > 0.0 else 1.0
	for i in MusicTrack.LAYERS_MOST:
		var target: float = 1.0 if _want[i] == 1 else 0.0
		_level[i] = move_toward(_level[i], target, rate)
		_now[i].volume_db = linear_to_db(_level[i])
	var first: AudioStreamPlayer = _now[0]
	if first.stream != null and not first.playing:
		_start_all()


## Silence at once (the game leaving play).
func stop() -> void:
	play(null, 0)
	_then_level = 0.0
	for player in _then:
		player.stop()
		player.stream = null


## The track playing (null: none) and its intensity.
func track() -> MusicTrack:
	return _track


func intensity() -> int:
	return _intensity


## How loud layer `layer` of the track playing is now (0-1), and whether it is to be heard.
func level_of(layer: int) -> float:
	return _level[layer] if layer >= 0 and layer < MusicTrack.LAYERS_MOST else 0.0


func is_heard(layer: int) -> bool:
	return layer >= 0 and layer < MusicTrack.LAYERS_MOST and _want[layer] == 1


## The sound layer `layer` of the track playing plays (null: none), for tests.
func stream_of(layer: int) -> AudioStream:
	return _now[layer].stream if layer >= 0 and layer < MusicTrack.LAYERS_MOST else null


## The level of the track fading out (0-1).
func fading_level() -> float:
	return _then_level


func _start_all() -> void:
	for player in _now:
		if player.stream != null:
			player.play()
