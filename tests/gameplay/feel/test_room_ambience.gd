extends "res://tests/support/suite.gd"
## Atmosphere D (docs/milestones/atmosphere.md): a room's sound under its music, heard only
## (`Ambience`, core/base). Feel's room sound (`gameplay/feel/room_ambience.gd`) picks the room's
## ambience and times its accents; Audio plays the bed and the accents (core/audio `ambience.gd`,
## docs/milestones/sound.md, section 5). The data and its problems, the game's rooms and their
## files, silence with none, the fade in and out across a room change, the bus, the accents' gaps and
## spreads, and a frame making no object. A registry of the test's own answers the test's sound ids
## with a looping silent stream and knows the test's own rooms; each room sound plays on an Audio of
## the test's own.
const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const RoomAmbienceScript := preload("res://gameplay/feel/room_ambience.gd")
const AudioScript := preload("res://core/audio/audio.gd")
const BedScript := preload("res://core/audio/ambience.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")

const FRAME: float = 1.0 / 60.0
const CRYPT_ROOMS: Array[StringName] = [&"arena_01", &"arena_02", &"arena_03", &"arena_04", &"boss_broom"]


## The game's registry, with a silent looping sound for every id in `known` and the test's own
## rooms (`extra`) over its content.
class SoundRegistry:
	extends RegistryScript
	var base: RegistryScript = null
	var stream: AudioStreamWAV = null
	var known: Dictionary = {}
	var extra: Dictionary = {}

	func _init() -> void:
		stream = AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_8_BITS
		stream.mix_rate = 8000
		var data := PackedByteArray()
		data.resize(800)
		stream.data = data
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = 800

	func get_sound(id: StringName) -> AudioStream:
		return stream if known.has(id) else null

	func get_resource(folder: StringName, id: StringName) -> Resource:
		var mine: Resource = (extra.get(folder, {}) as Dictionary).get(id) as Resource
		return mine if mine != null else base.get_resource(folder, id)

	func get_all(folder: StringName) -> Array[Resource]:
		return base.get_all(folder)

	func get_ids(folder: StringName) -> Array[StringName]:
		return base.get_ids(folder)


var fx: Fixture
var reg: SoundRegistry


func before_each() -> void:
	fx = null
	reg = SoundRegistry.new()
	reg.base = RegistryScript.new()
	reg.base.scan()
	own(reg.base)
	own(reg)


func after_each() -> void:
	if fx != null:
		fx.free_all()


func _player() -> RoomAmbienceScript:
	var audio: AudioScript = own(AudioScript.new()) as AudioScript
	audio.registry = reg
	root.add_child(audio)
	var player: RoomAmbienceScript = own(RoomAmbienceScript.new()) as RoomAmbienceScript
	player.registry = reg
	player.audio = audio
	root.add_child(player)
	player.rng.seed = 7
	return player


## The bed Audio plays for `player`.
func _bed(player: RoomAmbienceScript) -> BedScript:
	return player.audio.ambience


## `player` and its Audio's world `delta` seconds on (Audio steps itself in the game).
func _tick(player: RoomAmbienceScript, delta: float, middle: Vector2 = Vector2.INF) -> void:
	player.step(delta, middle)
	player.audio.step_world(delta)


## Feel and its Audio `delta` seconds on.
func _fstep(feel: FeelScript, delta: float) -> void:
	feel.step(delta)
	fx.audio.step_world(delta)


func _layer(sound: StringName, volume: float = 0.0) -> AmbienceLayer:
	var layer := AmbienceLayer.new()
	layer.sound = sound
	layer.volume = volume
	reg.known[sound] = true
	return layer


func _accent(sounds: Array[StringName], gap_min: float, gap_max: float) -> AmbienceAccent:
	var accent := AmbienceAccent.new()
	accent.sounds = sounds
	accent.gap_min = gap_min
	accent.gap_max = gap_max
	for id in sounds:
		reg.known[id] = true
	return accent


func _ambience(layers: Array[AmbienceLayer], accents: Array[AmbienceAccent] = [], fade: float = 2.0) -> Ambience:
	var ambience := Ambience.new()
	ambience.layers = layers
	ambience.accents = accents
	ambience.fade = fade
	ambience.volume = -8.0
	check(ambience.problems("test").is_empty(), "the test's ambience is sound: %s" % [ambience.problems("test")])
	return ambience


## A world with Feel on the test's registry.
func _world() -> FeelScript:
	fx = Fixture.new(root, 1)
	var feel: FeelScript = fx.with_feel() as FeelScript
	feel.registry = reg
	fx.audio.registry = reg
	return feel


func _enter(id: StringName, ambience: Ambience) -> void:
	var room := RoomBase.new()
	room.id = id
	room.ambience = ambience
	var rooms: Dictionary = reg.extra.get(&"rooms", {})
	rooms[id] = room
	reg.extra[&"rooms"] = rooms
	fx.bus.room_entered.emit(id)


# --- The data -------------------------------------------------------------------------------------

func test_an_ambience_is_checked_with_its_room() -> void:
	check_equal(Ambience.new().problems("x").size(), 1, "an ambience needs a layer or an accent")
	var many := Ambience.new()
	for i in Ambience.LAYERS_MOST + 1:
		many.layers.append(_layer(&"a"))
	many.layers.append(AmbienceLayer.new())
	check_equal(many.problems("x").size(), 2, "at most LAYERS_MOST layers, none naming no sound")
	var bad := AmbienceAccent.new()
	bad.sounds = [&"a", &""] as Array[StringName]
	bad.gap_min = 9.0
	bad.gap_max = 3.0
	bad.pitch_spread = 0.9
	var silent := AmbienceAccent.new()
	var accents := Ambience.new()
	accents.accents = [bad, silent] as Array[AmbienceAccent]
	var found: String = "\n".join(accents.problems("x"))
	check(found.contains("empty sound"), "an accent's empty sound")
	check(found.contains("gaps"), "an accent's gaps the most first")
	check(found.contains("pitch"), "an accent's pitch spread")
	check(found.contains("accent 1 names no sound"), "an accent naming no sound")
	var room := RoomBase.new()
	room.id = &"x"
	room.ambience = accents
	check("\n".join(room.template_problems([])).contains("ambience"), "a room's ambience is checked with it")
	room.ambience = null
	check(room.template_problems([]).is_empty(), "no ambience (the default) is fine: silent")


func test_the_crypt_and_the_hub_name_their_ambience_and_its_files_exist() -> void:
	var crypt: Ambience = null
	for id in CRYPT_ROOMS:
		var room: RoomBase = reg.base.get_resource(&"rooms", id) as RoomBase
		check(room != null and room.ambience != null, "%s names an ambience" % id)
		if room == null or room.ambience == null:
			continue
		crypt = room.ambience if crypt == null else crypt
		check(room.ambience == crypt, "%s shares the crypt's" % id)
	var hub: RoomBase = reg.base.get_resource(&"rooms", &"hub") as RoomBase
	check(hub != null and hub.ambience != null and hub.ambience != crypt, "the hub names its own")
	for ambience: Ambience in [crypt, hub.ambience if hub != null else null]:
		if ambience == null:
			continue
		check(ambience.problems("game").is_empty(), "the game's ambience is sound: %s" % [ambience.problems("game")])
		check(ambience.volume < 0.0, "quiet under the music")
		for layer in ambience.layers:
			var bed := reg.base.get_sound(layer.sound) as AudioStreamOggVorbis
			check(bed != null, "the loop %s has its file" % layer.sound)
			if bed != null:
				check(bed.loop, "%s is imported to loop" % layer.sound)
				check(bed.get_length() >= 8.0 and bed.get_length() <= 16.5, "%s is a modest loop" % layer.sound)
		for accent in ambience.accents:
			for id in accent.sounds:
				var sound := reg.base.get_sound(id) as AudioStreamOggVorbis
				check(sound != null and not sound.loop, "the accent %s has its file, played once" % id)


# --- Playing --------------------------------------------------------------------------------------

func test_no_ambience_is_silent() -> void:
	var player: RoomAmbienceScript = _player()
	player.use(null)
	for i in 600:
		_tick(player, FRAME)
	for i in Ambience.LAYERS_MOST:
		check(_bed(player).stream_of(i) == null, "no bed")
	check_equal(player.accents_played, 0, "no accent")
	var feel: FeelScript = _world()
	_enter(&"test_bare", null)
	for i in 120:
		_fstep(feel, FRAME)
	check(feel.ambience().ambience() == null and _bed(feel.ambience()).stream_of(0) == null, "a room naming none is silent in Feel")
	check_equal(feel.ambience().accents_played, 0, "and has no accent")


func test_the_bed_fades_in_and_out_with_the_room_and_plays_on_through_the_same() -> void:
	var feel: FeelScript = _world()
	var crypt: Ambience = _ambience([_layer(&"t_air"), _layer(&"t_deep", -3.0)] as Array[AmbienceLayer])
	var hub: Ambience = _ambience([_layer(&"t_wind")] as Array[AmbienceLayer], [] as Array[AmbienceAccent], 1.0)
	_enter(&"test_crypt", crypt)
	var player: RoomAmbienceScript = feel.ambience()
	check(player.ambience() == crypt, "the room's ambience")
	check(_bed(player).stream_of(0) != null and _bed(player).stream_of(1) != null, "its layers playing")
	check_equal(_bed(player).level(), 0.0, "from silence")
	var last: float = 0.0
	var largest: float = 0.0
	for i in 90:
		_fstep(feel, FRAME)
		largest = maxf(largest, _bed(player).level() - last)
		check(_bed(player).level() >= last, "only ever comes in")
		last = _bed(player).level()
	check(largest <= FRAME / crypt.fade + 0.0001, "a frame's share of its fade at most: no jump")
	check(_bed(player).level() > 0.7 and _bed(player).level() < 0.8, "1.5 s of its 2 s fade")
	for i in 60:
		_fstep(feel, FRAME)
	check(is_equal_approx(_bed(player).level(), 1.0), "in after its fade")
	check(is_equal_approx(_bed(player).volume_of(0), -8.0) and is_equal_approx(_bed(player).volume_of(1), -11.0), "each layer at the ambience's volume and its own")
	_enter(&"test_crypt_2", crypt)
	check(is_equal_approx(_bed(player).level(), 1.0) and _bed(player).fading_level() == 0.0, "the same ambience in the next room plays on")
	_enter(&"test_hub", hub)
	check(player.ambience() == hub and _bed(player).level() == 0.0, "a new room's comes in from silence")
	check(is_equal_approx(_bed(player).fading_level(), 1.0), "while the last goes out from where it was")
	_fstep(feel, 1.0)
	check(is_equal_approx(_bed(player).fading_level(), 0.5), "over its own fade")
	check(is_equal_approx(_bed(player).level(), 1.0), "the new one in over its own")
	_fstep(feel, 1.0)
	check_equal(_bed(player).fading_level(), 0.0, "the last is gone")
	_enter(&"test_bare", null)
	check(player.ambience() == null and is_equal_approx(_bed(player).fading_level(), 1.0), "a room with none: the last fades out, no cut")


func test_every_player_is_on_the_ambience_bus() -> void:
	var feel: FeelScript = _world()
	var player: RoomAmbienceScript = feel.ambience()
	check(player.audio == fx.audio, "Feel hands its room sound its Audio")
	check(AudioServer.get_bus_index(AudioScript.BUS_AMBIENCE) >= 0, "the bus exists (default_bus_layout.tres)")
	var players: int = 0
	for node in _bed(player).players():
		if node is AudioStreamPlayer:
			check_equal((node as AudioStreamPlayer).bus, AudioScript.BUS_AMBIENCE, "a bed's player on the bus")
			players += 1
		elif node is AudioStreamPlayer2D:
			check_equal((node as AudioStreamPlayer2D).bus, AudioScript.BUS_AMBIENCE, "an accent's voice on the bus")
			players += 1
	check_equal(players, Ambience.LAYERS_MOST * 2 + BedScript.ACCENT_VOICES, "every player")
	check_equal(fx.audio.audible, AudioScript.hears_audio(), "Audio knows whether this machine hears")
	check_equal(_bed(player).audible, fx.audio.audible, "the bed the same")
	check_equal(fx.audio.music.audible, fx.audio.audible, "and its music")


func test_accents_come_within_their_gaps_and_spreads() -> void:
	var player: RoomAmbienceScript = _player()
	var drips: AmbienceAccent = _accent([&"t_drip", &"t_drip_2"] as Array[StringName], 4.0, 9.0)
	drips.volume = -4.0
	drips.volume_spread = 3.0
	drips.pitch_spread = 0.1
	drips.wide = 200.0
	var rumble: AmbienceAccent = _accent([&"t_rumble"] as Array[StringName], 30.0, 60.0)
	var ambience: Ambience = _ambience([_layer(&"t_air")] as Array[AmbienceLayer], [drips, rumble] as Array[AmbienceAccent], 0.0)
	player.use(ambience)
	check(player.accent_in(0) >= 4.0 and player.accent_in(0) <= 9.0, "the first drip within its gaps of the room coming")
	check(player.accent_in(1) >= 30.0 and player.accent_in(1) <= 60.0, "the first rumble within its gaps")
	check(is_inf(player.accent_in(2)), "no third accent")
	var middle := Vector2(500.0, 300.0)
	var clock: float = 0.0
	var last_drip: float = 0.0
	var drips_heard: int = 0
	var rumbles_heard: int = 0
	var seen: Dictionary = {}
	var gap_least: float = INF
	var gap_most: float = 0.0
	var played: int = 0
	for frame in int(600.0 / FRAME):
		_tick(player, FRAME, middle)
		clock += FRAME
		if player.accents_played == played:
			continue
		played = player.accents_played
		seen[player.last_accent] = true
		if player.last_accent == &"t_rumble":
			rumbles_heard += 1
			continue
		drips_heard += 1
		var gap: float = clock - last_drip
		last_drip = clock
		gap_least = minf(gap_least, gap)
		gap_most = maxf(gap_most, gap)
		var voice: AudioStreamPlayer2D = _bed(player).accent_voice()
		if voice != null:
			check(voice.volume_db >= -8.0 - 4.0 - 3.0 - 0.001 and voice.volume_db <= -8.0 - 4.0 + 3.0 + 0.001, "a drip's volume within its spread")
			check(voice.pitch_scale >= 0.9 - 0.0001 and voice.pitch_scale <= 1.1 + 0.0001, "its pitch within its spread")
			check(absf(voice.global_position.x - middle.x) <= 200.0 + 0.01 and is_equal_approx(voice.global_position.y, middle.y), "from within its wide of the middle")
	check(gap_least >= 4.0 - 0.0001, "never sooner than gap_min (%s)" % gap_least)
	check(gap_most <= 9.0 + FRAME + 0.0001, "never later than gap_max, within a frame (%s)" % gap_most)
	check(drips_heard >= int(600.0 / 9.0) - 1 and drips_heard <= int(600.0 / 4.0) + 1, "as many drips as ten minutes' gaps allow (%d)" % drips_heard)
	check(rumbles_heard >= 9 and rumbles_heard <= 20, "and rumbles (%d)" % rumbles_heard)
	check(seen.has(&"t_drip") and seen.has(&"t_drip_2"), "its sounds picked at random")


func test_an_accent_follows_the_fade_and_none_comes_without_its_file() -> void:
	var player: RoomAmbienceScript = _player()
	var ghost: AmbienceAccent = _accent([&"t_ghost"] as Array[StringName], 1.0, 1.0)
	reg.known.erase(&"t_ghost")
	player.use(_ambience([] as Array[AmbienceLayer], [ghost] as Array[AmbienceAccent]))
	for i in int(5.0 / FRAME):
		_tick(player, FRAME)
	check_equal(player.accents_played, 0, "an accent whose file does not exist is silent")
	check(player.accent_in(0) <= 1.0, "and still comes round again")
	var soft: AmbienceAccent = _accent([&"t_drip"] as Array[StringName], 0.5, 0.5)
	player.use(_ambience([] as Array[AmbienceLayer], [soft] as Array[AmbienceAccent], 2.0))
	for i in int(0.52 / FRAME):
		_tick(player, FRAME)
	check_equal(player.accents_played, 1, "heard as its room fades in")
	var voice: AudioStreamPlayer2D = _bed(player).accent_voice()
	check(voice != null and voice.volume_db < -8.0 - 10.0, "as soft as the fade has come (a quarter in: -12 dB)")


func test_a_frame_makes_no_object() -> void:
	var player: RoomAmbienceScript = _player()
	var drips: AmbienceAccent = _accent([&"t_drip"] as Array[StringName], 30.0, 30.0)
	player.use(_ambience([_layer(&"t_air"), _layer(&"t_deep")] as Array[AmbienceLayer], [drips] as Array[AmbienceAccent]))
	_tick(player, FRAME)
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for frame in 300:
		player.step(FRAME, Vector2(10.0, 10.0))
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "300 frames of a fade make no object")


func test_leaving_the_tree_lets_go_of_every_stream() -> void:
	var player: RoomAmbienceScript = _player()
	var drips: AmbienceAccent = _accent([&"t_drip"] as Array[StringName], 0.5, 0.5)
	player.use(_ambience([_layer(&"t_air")] as Array[AmbienceLayer], [drips] as Array[AmbienceAccent], 0.0))
	for i in int(1.0 / FRAME):
		_tick(player, FRAME)
	check(_bed(player).stream_of(0) != null and player.accents_played > 0, "playing a bed and an accent")
	root.remove_child(player.audio)
	for node in _bed(player).players():
		var bed := node as AudioStreamPlayer
		var voice := node as AudioStreamPlayer2D
		check((bed == null or bed.stream == null) and (voice == null or voice.stream == null), "no stream held once out of the tree (none left with the audio server at exit)")
	root.add_child(player.audio)


func test_with_no_device_nothing_is_started() -> void:
	var player: RoomAmbienceScript = _player()
	player.audio.audible = false
	var drips: AmbienceAccent = _accent([&"t_drip"] as Array[StringName], 0.5, 0.5)
	player.use(_ambience([_layer(&"t_air")] as Array[AmbienceLayer], [drips] as Array[AmbienceAccent], 0.0))
	for i in int(1.0 / FRAME):
		_tick(player, FRAME)
	check(_bed(player).stream_of(0) != null and player.accents_played > 0, "its streams and accents are worked out")
	for node in _bed(player).players():
		var bed := node as AudioStreamPlayer
		var voice := node as AudioStreamPlayer2D
		check((bed == null or not bed.playing) and (voice == null or not voice.playing), "but no player is started (none left playing as a headless run quits)")


## A stream of `samples` silent 8 kHz samples, looping or not.
func _wav(samples: int, loops: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 8000
	var data := PackedByteArray()
	data.resize(samples)
	wav.data = data
	if loops:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples
	return wav


func test_audible_it_plays_restarts_a_layer_run_out_and_stops_clean() -> void:
	var player: RoomAmbienceScript = _player()
	player.audio.audible = true
	reg.stream = _wav(800, false)
	var drips: AmbienceAccent = _accent([&"t_drip"] as Array[StringName], 0.5, 0.5)
	player.use(_ambience([_layer(&"t_air")] as Array[AmbienceLayer], [drips] as Array[AmbienceAccent]))
	var bed: AudioStreamPlayer = _bed(player).bed_player(0)
	check(bed.playing, "the bed plays as its room comes")
	bed.stop()
	_tick(player, FRAME)
	check(bed.playing, "a layer not imported to loop is started again when it runs out")
	for i in int(0.6 / FRAME):
		_tick(player, FRAME)
	check(_bed(player).accent_voice() != null and _bed(player).accent_voice().playing, "an accent plays")
	player.stop()
	for node in _bed(player).players():
		var a := node as AudioStreamPlayer
		var b := node as AudioStreamPlayer2D
		check((a == null or (not a.playing and a.stream == null)) and (b == null or (not b.playing and b.stream == null)), "stop leaves nothing playing")


func test_it_stands_still_with_the_tree() -> void:
	var player: RoomAmbienceScript = _player()
	player.audio.audible = true
	reg.stream = _wav(800, true)
	player.use(_ambience([_layer(&"t_air")] as Array[AmbienceLayer]))
	var bed: AudioStreamPlayer = _bed(player).bed_player(0)
	check(bed.playing and not bed.stream_paused, "playing")
	paused = true
	var stood: bool = bed.stream_paused and not bed.playing
	paused = false
	check(stood, "the tree paused (the pause menu, a boss's intro): its bed stands still")
	check(bed.playing and not bed.stream_paused, "and goes on after")
	player.stop()


func test_back_to_the_menu_the_ambience_and_the_music_fade_out() -> void:
	var feel: FeelScript = _world()
	var crypt: Ambience = _ambience([_layer(&"t_air")] as Array[AmbienceLayer])
	var track := MusicTrack.new()
	track.layers = [&"t_tune"] as Array[StringName]
	reg.known[&"t_tune"] = true
	var room := RoomBase.new()
	room.id = &"test_crypt"
	room.ambience = crypt
	room.music = track
	reg.extra[&"rooms"] = {room.id: room}
	fx.bus.room_entered.emit(room.id)
	for i in int(3.0 / FRAME):
		_fstep(feel, FRAME)
	var player: RoomAmbienceScript = feel.ambience()
	check(is_equal_approx(_bed(player).level(), 1.0) and fx.audio.music.track() == track, "the crypt's bed and music in")
	fx.bus.main_menu_requested.emit(0)
	check(player.ambience() == null, "the menu: no ambience")
	check(is_equal_approx(_bed(player).fading_level(), 1.0), "the crypt's goes out from where it was, no cut")
	var last: float = _bed(player).fading_level()
	for i in int(3.0 / FRAME):
		_fstep(feel, FRAME)
		check(last - _bed(player).fading_level() <= FRAME / crypt.fade + 0.0001, "a frame's share at a time")
		last = _bed(player).fading_level()
	check_equal(_bed(player).fading_level(), 0.0, "silent under the menu")
	check(fx.audio.music.track() == null and fx.audio.music.fading_level() == 0.0, "the room's music faded out too")


## The level of both sets summed, frame by frame for `seconds`: the most it dropped in a frame.
func _largest_drop(player: RoomAmbienceScript, seconds: float) -> float:
	var largest: float = 0.0
	var last: float = _bed(player).level() + _bed(player).fading_level()
	for i in int(seconds / FRAME):
		_tick(player, FRAME)
		var now: float = _bed(player).level() + _bed(player).fading_level()
		largest = maxf(largest, last - now)
		last = now
	return largest


func test_a_change_inside_a_fade_never_cuts_the_louder() -> void:
	var player: RoomAmbienceScript = _player()
	var a: Ambience = _ambience([_layer(&"t_a")] as Array[AmbienceLayer])
	var b: Ambience = _ambience([_layer(&"t_b")] as Array[AmbienceLayer])
	var c: Ambience = _ambience([_layer(&"t_c")] as Array[AmbienceLayer])
	player.use(a)
	_largest_drop(player, 3.0)
	player.use(b)
	_largest_drop(player, 0.8)
	var b_in: float = _bed(player).level()
	var a_out: float = _bed(player).fading_level()
	player.use(a)
	check(player.ambience() == a and _bed(player).fading_ambience() == b, "A, B, A: the sets swap")
	check(is_equal_approx(_bed(player).level(), a_out) and is_equal_approx(_bed(player).fading_level(), b_in), "each going on from where it was")
	check(_bed(player).stream_of(0) == reg.get_sound(&"t_a"), "A's bed playing on")
	var share: float = FRAME / a.fade + 0.0001
	check(_largest_drop(player, 3.0) <= share, "no frame's summed level drops more than a frame's share")
	player.use(null)
	_largest_drop(player, 0.6)
	var a_left: float = _bed(player).fading_level()
	player.use(b)
	check(_bed(player).fading_ambience() == a and is_equal_approx(_bed(player).fading_level(), a_left), "A, none, B: A goes on going out")
	check(_largest_drop(player, 0.2) <= share, "nothing cut")
	_largest_drop(player, 0.6)
	var louder: Ambience = b if _bed(player).level() >= _bed(player).fading_level() else a
	var louder_level: float = maxf(_bed(player).level(), _bed(player).fading_level())
	player.use(c)
	check(player.ambience() == c and _bed(player).fading_ambience() == louder, "A, B, C: the louder goes on going out")
	check(is_equal_approx(_bed(player).fading_level(), louder_level), "from where it was; only the quieter is let go")
