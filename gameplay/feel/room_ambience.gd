extends Node
## Feel's room sound (docs/milestones/atmosphere.md, D): plays the `Ambience` of the room in play
## (`RoomBase.ambience`) quietly under the music, heard only (nothing in the game reads it). It hears
## the room itself (`room_entered`, the room read from the registry, as the cover does) and leaving
## for the main menu (`main_menu_requested`: no room follows, so it fades to silence); Feel only
## makes it and steps it once a frame by real time.
##
## **The bed:** every layer starts together and loops (a file not imported to loop is started again
## when it runs out). It comes in over its ambience's `fade` from silence as its room comes, and a
## new room's ambience comes in while the last one goes out from where it was on a second set of
## players, so a room change never cuts it; the same ambience in the next room plays on. Each fade
## is even in loudness's share (as the music's), never a jump: Smooth for sound. **Changes inside a
## fade:** back to the ambience still going out (A, B, A), the two sets swap and each goes on from
## where it was; a third (A, B, C) needs a set, so the quieter of the two is let go and the louder
## goes on going out.
##
## **Accents:** each of its ambience's accents is heard after a gap of `gap_min` to `gap_max`
## seconds (the first as long after its room came), one of its sounds at random, from up to its
## `wide` px left or right of the middle of the picture, its volume and pitch strayed within their
## spreads, as loud as the bed's fade is. They play on ACCENT_VOICES voices of their own (a new one
## takes the next in turn, the one that started first); one already ringing when the room changes
## rings out. The dice are its own (`rng`) and the clock is its own: view only, never the game's.
##
## **Where it is heard:** every player on this script's BUS, the bus the music and every sound of
## Feel play on, so a volume set on it reaches the ambience too. Its players are Feel's children and
## stand still with the tree as the music does (the pause menu, a boss's intro), and go on where
## they were after.
##
## **The "Ambience volume" setting** (`set_volume`, Feel hands it from `ambience_volume_changed`;
## `AmbienceVolume` in core/settings): a share of the room's own loudness, times every bed's and
## accent's amplitude (in decibels `linear_to_db` of it). A new share is eased to at most
## VOLUME_RATE a second, so a step of the slider is never a jump; at 0 every bed's player stops
## and no accent is heard (they are still picked and placed), and the beds start again as it
## comes back up. Set while the pause menu stops the tree, it is heard after it, easing in.
##
## **Only `audible` starts a player:** Feel hands it its own (`Feel.hears_audio`: false on the audio
## driver with no device, every headless run, so nothing is left playing as a headless run quits).
## Not audible it works out all of the above (streams, levels, accents picked and placed) and starts
## nothing.
##
## Nothing is allocated while playing: the players are made once.

const SoundsScript := preload("res://gameplay/feel/sounds.gd")
const EventsScript := preload("res://core/events/events.gd")

## The bus every player of it plays on (the music's and the sounds': the game has one).
const BUS: StringName = &"Master"
## The voices the accents play on (heard as Feel's sounds are: from its `wide` px aside an accent
## is panned and hardly quieter).
const ACCENT_VOICES: int = 4
## Where the rooms are in the registry.
const ROOM_FOLDER: StringName = &"rooms"
## How fast the share heard follows the "Ambience volume" setting (a second; 1 is all of it).
const VOLUME_RATE: float = 4.0

## The bus it hears rooms on (Feel's; null in a test that hands it ambiences itself), set before it
## enters the tree, and the registry the rooms and sounds are asked of.
var events: EventsScript = null
var registry: Node = null
## Whether its players are started (Feel's `audible`).
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
## How far in the ambience playing has come (0-1), and how far the one going out still is, its
## fade's seconds and which it is (null: none going out).
var _level: float = 0.0
var _then_level: float = 0.0
var _then_fade: float = 0.0
var _then_ambience: Ambience = null
var _voices: Array[AudioStreamPlayer2D] = []
var _next_voice: int = 0
## Feel's real seconds since it was made, and when each accent is next heard.
var _clock: float = 0.0
var _next_at: PackedFloat64Array = PackedFloat64Array()
var _ambience: Ambience = null
## The "Ambience volume" setting's share (`set_volume`), and the share heard now, easing to it.
var _volume: float = 1.0
var _heard: float = 1.0


func _ready() -> void:
	rng.randomize()
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
	if events != null and not events.room_entered.is_connected(_on_room_entered):
		events.room_entered.connect(_on_room_entered)
		events.main_menu_requested.connect(_on_main_menu_requested)


## Leaving the tree (Feel going with the game): every player stops and lets go of its stream.
func _exit_tree() -> void:
	stop()


func _bed_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = BUS
	player.volume_db = linear_to_db(0.0)
	add_child(player)
	return player


func _on_room_entered(room_id: StringName) -> void:
	var room: RoomBase = registry.call(&"get_resource", ROOM_FOLDER, room_id) as RoomBase if registry != null else null
	use(room.ambience if room != null else null)


## Back to the main menu: no room follows, so the ambience fades out under the menu.
func _on_main_menu_requested(_player: int) -> void:
	use(null)


## The room in play's ambience is `ambience` (null: silence): a new one comes in over its fade and
## the last goes out over its own; the same one plays on; the one going out comes back from where
## it was.
func use(ambience: Ambience) -> void:
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
	_next_at.fill(INF)
	if ambience == null:
		_apply()
		return
	var layers: int = mini(ambience.layers.size(), Ambience.LAYERS_MOST)
	for i in layers:
		var layer: AmbienceLayer = ambience.layers[i]
		var player: AudioStreamPlayer = _now[i]
		player.stream = _sound(layer.sound if layer != null else &"")
		_now_db[i] = ambience.volume + (layer.volume if layer != null else 0.0)
		if audible and player.stream != null and _heard > 0.0:
			player.play()
	_schedule()
	if ambience.fade <= 0.0:
		_level = 1.0
	_apply()


## Once a frame, `delta` real seconds on, `middle` the middle of the picture (INF: none, the
## origin): the bed fades, the last ambience goes out, and each accent due is heard.
func step(delta: float, middle: Vector2 = Vector2.INF) -> void:
	_clock += delta
	_ease_volume(delta)
	if _then_level > 0.0:
		_then_level = maxf(_then_level - (delta / _then_fade if _then_fade > 0.0 else 1.0), 0.0)
		if _then_level == 0.0:
			_let_go(_then)
			_then_ambience = null
	if _ambience != null:
		_level = minf(_level + (delta / _ambience.fade if _ambience.fade > 0.0 else 1.0), 1.0)
		for player in _now:
			if audible and player.stream != null and not player.playing and _heard > 0.0:
				player.play()
		for i in mini(_ambience.accents.size(), Ambience.ACCENTS_MOST):
			if _clock >= _next_at[i]:
				_play_accent(_ambience.accents[i], middle)
				_next_at[i] = _clock + _gap(_ambience.accents[i])
	_apply()


## Silence at once (tests, leaving the tree; in play the next room's ambience, or none, takes over
## by fading).
func stop() -> void:
	_let_go(_now)
	_let_go(_then)
	_ambience = null
	_then_ambience = null
	_level = 0.0
	_then_level = 0.0
	_next_at.fill(INF)
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


## Seconds until accent `accent` of the ambience playing is next heard (INF: never).
func accent_in(accent: int) -> float:
	return _next_at[accent] - _clock if accent >= 0 and accent < Ambience.ACCENTS_MOST else INF


## The voice the last accent played on (null: none yet; for tests).
func accent_voice() -> AudioStreamPlayer2D:
	return _voices[(_next_voice + ACCENT_VOICES - 1) % ACCENT_VOICES] if accents_played > 0 else null


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
	_schedule()
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


func _schedule() -> void:
	_next_at.fill(INF)
	for i in mini(_ambience.accents.size(), Ambience.ACCENTS_MOST):
		_next_at[i] = _clock + _gap(_ambience.accents[i])


## The ambience's volumes times each set's fade and the share heard, set on the bed's players.
func _apply() -> void:
	for i in Ambience.LAYERS_MOST:
		_now[i].volume_db = _now_db[i] + linear_to_db(_level * _heard)
		_then[i].volume_db = _then_db[i] + linear_to_db(_then_level * _heard)


## The "Ambience volume" setting: `share` of the room's own loudness (0 to 1; `AmbienceVolume.
## share_of`), eased to by `step` (see the top). Returns the share taken.
func set_volume(share: float) -> float:
	_volume = clampf(share, 0.0, 1.0)
	return _volume


## The share the setting asks for, and the share heard now (for tests).
func volume() -> float:
	return _volume


func heard() -> float:
	return _heard


## The share heard eased toward the setting's, `delta` seconds on; once silent every bed's player
## stops, and every accent's voice (each bed keeps its stream, so the beds start again as the share
## comes back).
func _ease_volume(delta: float) -> void:
	if _heard == _volume:
		return
	_heard = move_toward(_heard, _volume, VOLUME_RATE * delta)
	if _heard <= 0.0:
		for player in _now:
			player.stop()
		for player in _then:
			player.stop()
		for voice in _voices:
			voice.stop()


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
	voice.volume_db += linear_to_db(_heard)
	if audible and _heard > 0.0:
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
