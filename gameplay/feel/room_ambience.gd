extends Node
## Feel's room sound (docs/milestones/atmosphere.md, D): plays the `Ambience` of the room in play
## (`RoomBase.ambience`) quietly under the music, heard only (nothing in the game reads it). Feel
## says which (`use`, as a room is entered) and steps it once a frame by real time.
##
## **The bed:** every layer starts together and loops (a file not imported to loop is started again
## when it runs out). It comes in over its ambience's `fade` from silence as its room comes, and a
## new room's ambience comes in while the last one goes out from where it was on a second set of
## players, so a room change never cuts it; the same ambience in the next room plays on. Each fade
## is even in loudness's share (as the music's), never a jump: Smooth for sound.
##
## **Accents:** each of its ambience's accents is heard after a gap of `gap_min` to `gap_max`
## seconds (the first as long after its room came), one of its sounds at random, from up to its
## `wide` px left or right of the middle of the picture, its volume and pitch strayed within their
## spreads, as loud as the bed's fade is. They play on ACCENT_VOICES voices of their own (a new one
## takes the next in turn, the one that started first); one already ringing when the room changes
## rings out. The dice are its own (`rng`) and the clock is its own: view only, never the game's.
##
## **Where it is heard:** on BUS, the bus the music and every sound of Feel play on, so a volume set
## on it reaches the ambience too. Its players are Feel's children and stand still with the tree
## as the music does (the pause menu, a boss's intro), and go on where they were after.
##
## **No device, no playback:** on the audio driver with no device (`DUMMY_DRIVER`: every headless
## run, the tests among them) it does all of the above (streams, levels, accents picked and placed)
## but starts no player (`audible`), since nothing is there to hear it, and a loop still playing as a
## headless run quits is left behind by the engine's audio thread under load (a leak the test
## runner fails on).
##
## Nothing is allocated while playing: the players are made once.

const SoundsScript := preload("res://gameplay/feel/sounds.gd")

## The bus every player of it plays on (the music's and the sounds': the game has one).
const BUS: StringName = &"Master"
## The audio driver that has no device (Godot's headless runs').
const DUMMY_DRIVER: String = "Dummy"
## The voices the accents play on (heard as Feel's sounds are: from its `wide` px aside an accent
## is panned and hardly quieter).
const ACCENT_VOICES: int = 4

## The registry the sounds are asked of (`get_sound`).
var registry: Node = null
## Whether its players are started (false on DUMMY_DRIVER: nothing to hear; set in `_ready`).
var audible: bool = true
## Its own dice (view only; a test seeds it).
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Accents played, and the last one's sound id (for tests).
var accents_played: int = 0
var last_accent: StringName = &""

## The bed's players of the ambience playing and of the one going out, a layer each.
var _now: Array[AudioStreamPlayer] = []
var _then: Array[AudioStreamPlayer] = []
## Each layer's loudness at full (decibels), for the ambience playing and the one going out.
var _now_db: PackedFloat32Array = PackedFloat32Array()
var _then_db: PackedFloat32Array = PackedFloat32Array()
## How far in the ambience playing has come (0-1), and how far the one going out still is, and its
## fade's seconds.
var _level: float = 0.0
var _then_level: float = 0.0
var _then_fade: float = 0.0
var _voices: Array[AudioStreamPlayer2D] = []
var _next_voice: int = 0
## Feel's real seconds since it was made, and when each accent is next heard.
var _clock: float = 0.0
var _next_at: PackedFloat64Array = PackedFloat64Array()
var _ambience: Ambience = null


func _ready() -> void:
	rng.randomize()
	audible = AudioServer.get_driver_name() != DUMMY_DRIVER
	for i in Ambience.LAYERS_MOST:
		_now.append(_bed_player())
		_then.append(_bed_player())
	_now_db.resize(Ambience.LAYERS_MOST)
	_then_db.resize(Ambience.LAYERS_MOST)
	_next_at.resize(Ambience.ACCENTS_MOST)
	_next_at.fill(INF)
	for i in ACCENT_VOICES:
		var voice := AudioStreamPlayer2D.new()
		voice.bus = BUS
		voice.max_distance = SoundsScript.HEARD
		voice.attenuation = SoundsScript.ATTENUATION
		add_child(voice)
		_voices.append(voice)


## Leaving the tree (Feel freed with its world): every player stops and lets go of its stream, so
## no playback is left with the audio server.
func _exit_tree() -> void:
	stop()


func _bed_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = BUS
	player.volume_db = linear_to_db(0.0)
	add_child(player)
	return player


## The room in play's ambience is `ambience` (null: silence): a new one comes in over its fade and
## the last goes out over its own; the same one plays on.
func use(ambience: Ambience) -> void:
	if ambience == _ambience:
		return
	# The ambience playing goes out as a whole from where it was; one still going out stops.
	for player in _then:
		player.stop()
		player.stream = null
	var swap: Array[AudioStreamPlayer] = _then
	_then = _now
	_now = swap
	var swap_db: PackedFloat32Array = _then_db
	_then_db = _now_db
	_now_db = swap_db
	_then_level = _level
	_then_fade = _ambience.fade if _ambience != null else 0.0
	_ambience = ambience
	_level = 0.0
	_next_at.fill(INF)
	if ambience == null:
		return
	var layers: int = mini(ambience.layers.size(), Ambience.LAYERS_MOST)
	for i in layers:
		var layer: AmbienceLayer = ambience.layers[i]
		var player: AudioStreamPlayer = _now[i]
		player.stream = _sound(layer.sound if layer != null else &"")
		_now_db[i] = ambience.volume + (layer.volume if layer != null else 0.0)
		player.volume_db = linear_to_db(0.0)
		if audible and player.stream != null:
			player.play()
	for i in mini(ambience.accents.size(), Ambience.ACCENTS_MOST):
		_next_at[i] = _clock + _gap(ambience.accents[i])
	if ambience.fade <= 0.0:
		_level = 1.0
	_apply()


## Once a frame, `delta` real seconds on, `middle` the middle of the picture (INF: none, the
## origin): the bed fades, the last ambience goes out, and each accent due is heard.
func step(delta: float, middle: Vector2 = Vector2.INF) -> void:
	_clock += delta
	if _then_level > 0.0:
		_then_level = maxf(_then_level - (delta / _then_fade if _then_fade > 0.0 else 1.0), 0.0)
		if _then_level == 0.0:
			for player in _then:
				player.stop()
				player.stream = null
	if _ambience != null:
		_level = minf(_level + (delta / _ambience.fade if _ambience.fade > 0.0 else 1.0), 1.0)
		for player in _now:
			if audible and player.stream != null and not player.playing:
				player.play()
		for i in mini(_ambience.accents.size(), Ambience.ACCENTS_MOST):
			if _clock >= _next_at[i]:
				_play_accent(_ambience.accents[i], middle)
				_next_at[i] = _clock + _gap(_ambience.accents[i])
	_apply()


## Silence at once (tests; in play the next room's ambience, or none, takes over by fading).
func stop() -> void:
	use(null)
	_then_level = 0.0
	for player in _then:
		player.stop()
		player.stream = null
	for voice in _voices:
		voice.stop()
		voice.stream = null


## The ambience playing (null: none).
func ambience() -> Ambience:
	return _ambience


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


## Seconds until accent `accent` of the ambience playing is next heard (INF: never).
func accent_in(accent: int) -> float:
	return _next_at[accent] - _clock if accent >= 0 and accent < Ambience.ACCENTS_MOST else INF


## The voice the last accent played on (null: none yet; for tests).
func accent_voice() -> AudioStreamPlayer2D:
	return _voices[(_next_voice + ACCENT_VOICES - 1) % ACCENT_VOICES] if accents_played > 0 else null


## Every player it has (for tests: the bus).
func players() -> Array[Node]:
	return get_children()


## The ambience's volumes times each set's fade, set on the bed's players.
func _apply() -> void:
	for i in Ambience.LAYERS_MOST:
		_now[i].volume_db = _now_db[i] + linear_to_db(_level)
		_then[i].volume_db = _then_db[i] + linear_to_db(_then_level)


func _play_accent(accent: AmbienceAccent, middle: Vector2) -> void:
	if accent == null or accent.sounds.is_empty():
		return
	var id: StringName = accent.sounds[rng.randi_range(0, accent.sounds.size() - 1)]
	var sound: AudioStream = _sound(id)
	if sound == null:
		return
	var voice: AudioStreamPlayer2D = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % ACCENT_VOICES
	voice.stream = sound
	voice.volume_db = _ambience.volume + accent.volume + rng.randf_range(-accent.volume_spread, accent.volume_spread) + linear_to_db(_level)
	voice.pitch_scale = 1.0 + rng.randf_range(-accent.pitch_spread, accent.pitch_spread)
	var from: Vector2 = middle if middle.is_finite() else Vector2.ZERO
	voice.global_position = from + Vector2(rng.randf_range(-accent.wide, accent.wide), 0.0)
	if audible:
		voice.play()
	accents_played += 1
	last_accent = id


func _gap(accent: AmbienceAccent) -> float:
	if accent == null:
		return INF
	return rng.randf_range(maxf(accent.gap_min, Ambience.GAP_LEAST), maxf(accent.gap_max, accent.gap_min))


func _sound(id: StringName) -> AudioStream:
	if registry == null or id == &"":
		return null
	return registry.call(&"get_sound", id) as AudioStream
