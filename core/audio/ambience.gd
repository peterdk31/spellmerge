extends Node
## Audio's room sound (core/audio, docs/milestones/sound.md, section 5; moved from Feel's room
## ambience, atmosphere D, with no change in what is heard): the bed of an `Ambience` (its looping
## layers) and the voices its accents play on. Which ambience plays, and when an accent comes, are its
## caller's (`Audio.play_bed`, `Audio.play_accent`: Feel's room sound, which hears the rooms).
##
## **The bed:** every layer starts together and loops (a file not imported to loop is started again
## when it runs out). It comes in over its ambience's `fade` from silence, and a new ambience comes in
## while the last one goes out from where it was on a second set of players, so a change never cuts
## it; the same ambience asked again plays on. Each fade is even in loudness's share, never a jump:
## Smooth for sound. **Changes inside a fade:** back to the ambience still going out (A, B, A), the
## two sets swap and each goes on from where it was; a third (A, B, C) needs a set, so the quieter of
## the two is let go and the louder goes on going out.
##
## **Accents** play on ACCENT_VOICES placed voices of their own (a new one takes the next in turn,
## the one that started first); one ringing when the ambience changes rings out.
##
## Every player is on `bus` (Audio's `Ambience`), whose volume is the "Ambience volume" setting
## (Audio's buses). Only `audible` starts a player (Audio's). Nothing is allocated while playing.

## The voices the accents play on.
const ACCENT_VOICES: int = 4

## The bus every player is on, and how its placed voices are heard (Audio's), set before `_ready`.
var bus: StringName = &"Master"
var heard: float = 1600.0
var attenuation: float = 0.7
var pan: float = 1.0
## The registry the layers' sounds are asked of (`get_sound`).
var registry: Node = null
## Whether its players are started (Audio's `audible`).
var audible: bool = true

## The bed's players of the ambience playing and of the one going out, a layer each.
var _now: Array[AudioStreamPlayer] = []
var _then: Array[AudioStreamPlayer] = []
## Each layer's loudness at full (decibels), for the ambience playing and the one going out.
var _now_db: PackedFloat32Array = PackedFloat32Array()
var _then_db: PackedFloat32Array = PackedFloat32Array()
## How far in the ambience playing has come (0-1), and how far the one going out still is, its
## fade's seconds and which it is (null: none going out).
var _level: float = 0.0
var _then_level: float = 0.0
var _then_fade: float = 0.0
var _then_ambience: Ambience = null
var _ambience: Ambience = null
var _voices: Array[AudioStreamPlayer2D] = []
var _next_voice: int = 0
var _accents: int = 0


func _ready() -> void:
	for i in Ambience.LAYERS_MOST:
		_now.append(_bed_player())
		_then.append(_bed_player())
	_now_db.resize(Ambience.LAYERS_MOST)
	_then_db.resize(Ambience.LAYERS_MOST)
	for i in ACCENT_VOICES:
		var voice := AudioStreamPlayer2D.new()
		voice.bus = bus
		voice.max_distance = heard
		voice.attenuation = attenuation
		voice.panning_strength = pan
		add_child(voice)
		_voices.append(voice)


## Leaving the tree (the game quitting): every player stops and lets go of its stream.
func _exit_tree() -> void:
	stop()


func _bed_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	player.volume_db = linear_to_db(0.0)
	add_child(player)
	return player


## The bed is `ambience`'s (null: silence): a new one comes in over its fade and the last goes out
## over its own; the same one plays on; the one going out comes back from where it was.
func play_bed(ambience: Ambience) -> void:
	if ambience == _ambience:
		return
	if ambience != null and ambience == _then_ambience:
		_swap_back()
		return
	if _level >= _then_level:
		# The ambience playing is the louder: it goes out from where it was, the one going out before
		# it is let go.
		_let_go(_then)
		_swap_sets()
		_then_level = _level
		_then_fade = _ambience.fade if _ambience != null else 0.0
		_then_ambience = _ambience
	else:
		# The one going out is the louder: it goes on going out, the one coming in is let go.
		_let_go(_now)
	_ambience = ambience
	_level = 0.0
	if ambience == null:
		_apply()
		return
	var layers: int = mini(ambience.layers.size(), Ambience.LAYERS_MOST)
	for i in layers:
		var layer: AmbienceLayer = ambience.layers[i]
		var player: AudioStreamPlayer = _now[i]
		player.stream = _sound(layer.sound if layer != null else &"")
		_now_db[i] = ambience.volume + (layer.volume if layer != null else 0.0)
		if audible and player.stream != null:
			player.play()
	if ambience.fade <= 0.0:
		_level = 1.0
	_apply()


## Plays `stream` as an accent at `at`, `volume` decibels and `pitch` its pitch scale, on the next
## voice in turn; the voice used.
func play_accent(stream: AudioStream, at: Vector2, volume: float, pitch: float) -> int:
	if stream == null:
		return -1
	var used: int = _next_voice
	var voice: AudioStreamPlayer2D = _voices[used]
	_next_voice = (_next_voice + 1) % ACCENT_VOICES
	voice.stream = stream
	voice.volume_db = volume
	voice.pitch_scale = pitch
	voice.global_position = at
	if audible:
		voice.play()
	_accents += 1
	return used


## Once a frame, `delta` real seconds on: the bed fades, the last ambience goes out, and a layer run
## out starts again.
func step(delta: float) -> void:
	if _then_level > 0.0:
		_then_level = maxf(_then_level - (delta / _then_fade if _then_fade > 0.0 else 1.0), 0.0)
		if _then_level == 0.0:
			_let_go(_then)
			_then_ambience = null
	if _ambience != null:
		_level = minf(_level + (delta / _ambience.fade if _ambience.fade > 0.0 else 1.0), 1.0)
		for player in _now:
			if audible and player.stream != null and not player.playing:
				player.play()
	_apply()


## Silence at once (tests, leaving the tree; in play the next ambience, or none, takes over by
## fading).
func stop() -> void:
	_let_go(_now)
	_let_go(_then)
	_ambience = null
	_then_ambience = null
	_level = 0.0
	_then_level = 0.0
	for voice in _voices:
		voice.stop()
		voice.stream = null


## The ambience playing (null: none), and the one going out.
func ambience() -> Ambience:
	return _ambience


func fading_ambience() -> Ambience:
	return _then_ambience


## How far in the ambience playing has come (0-1), and how loud the one going out still is.
func level() -> float:
	return _level


func fading_level() -> float:
	return _then_level


## The sound layer `layer` of the ambience playing plays (null: none), and its loudness now in
## decibels (for tests).
func stream_of(layer: int) -> AudioStream:
	return _now[layer].stream if layer >= 0 and layer < Ambience.LAYERS_MOST else null


func volume_of(layer: int) -> float:
	return _now[layer].volume_db if layer >= 0 and layer < Ambience.LAYERS_MOST else linear_to_db(0.0)


## The bed's player of layer `layer` of the ambience playing (for tests).
func bed_player(layer: int) -> AudioStreamPlayer:
	return _now[layer] if layer >= 0 and layer < Ambience.LAYERS_MOST else null


## The voice the last accent played on (null: none yet; for tests).
func accent_voice() -> AudioStreamPlayer2D:
	return _voices[(_next_voice + ACCENT_VOICES - 1) % ACCENT_VOICES] if _accents > 0 else null


## Every player it has (for tests: the bus).
func players() -> Array[Node]:
	return get_children()


## Back to the ambience going out: the two sets swap, each going on from where it was.
func _swap_back() -> void:
	_swap_sets()
	var coming: float = _then_level
	_then_level = _level
	_level = coming
	var going: Ambience = _ambience
	_ambience = _then_ambience
	_then_ambience = going
	_then_fade = going.fade if going != null else 0.0
	_apply()


func _swap_sets() -> void:
	var swap: Array[AudioStreamPlayer] = _then
	_then = _now
	_now = swap
	var swap_db: PackedFloat32Array = _then_db
	_then_db = _now_db
	_now_db = swap_db


func _let_go(players: Array[AudioStreamPlayer]) -> void:
	for player in players:
		player.stop()
		player.stream = null
		player.volume_db = linear_to_db(0.0)


## The ambience's volumes times each set's fade, set on the bed's players.
func _apply() -> void:
	for i in Ambience.LAYERS_MOST:
		_now[i].volume_db = _now_db[i] + linear_to_db(_level)
		_then[i].volume_db = _then_db[i] + linear_to_db(_then_level)


func _sound(id: StringName) -> AudioStream:
	if registry == null or id == &"":
		return null
	return registry.call(&"get_sound", id) as AudioStream
