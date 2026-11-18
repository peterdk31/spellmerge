extends "res://tests/support/suite.gd"
## The sound room (docs/milestones/sound.md, section 7; AU4): it lists every id the data names (a
## stand-in game's, and the real game's), red when it has no file and when a file is named by
## nothing, and plays, loops, ducks and steps the fixtures' intensity through Audio on the right buses.
## The room makes its own Audio (silent in a headless run: its players' streams and buses are what is
## checked) on the fixtures in tests/sound_room/fixtures/.
const SoundRoomScript := preload("res://tests/sound_room/sound_room.gd")
const SoundNames := preload("res://tests/sound_room/sound_names.gd")
const StandInGame := preload("res://tests/sound_room/stand_in_game.gd")
const AudioScript := preload("res://core/audio/audio.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")

const FRAME: float = 1.0 / 60.0

var room: SoundRoomScript


func after_each() -> void:
	if room != null and is_instance_valid(room):
		room.audio.buses.reset()
		room.audio.silence()
		room.free()
	room = null


func _open(game: Node = null) -> SoundRoomScript:
	room = SoundRoomScript.new()
	room.registry = game if game != null else root.get_node("Registry")
	root.add_child(room)
	return room


## A stand-in game naming one sound of every kind, with files for some and one file nothing names.
func _game() -> StandInGame:
	var game := own(StandInGame.new()) as StandInGame
	var cue := CueBase.new()
	cue.id = &"slam"
	cue.sound = &"slam_hit"
	cue.parts = [{"part": "held", "sound": "slam_scrape", "seconds": 1.0}] as Array[Dictionary]
	game.put(&"cues", cue)
	var enemy := EnemyBase.new()
	enemy.id = &"brute"
	enemy.death_sound = &"brute_death"
	var phase := EnemyPhase.new()
	phase.look = PhaseLook.new()
	phase.look.sound = &"brute_burning"
	enemy.phases = [phase] as Array[EnemyPhase]
	enemy.music = MusicTrack.new()
	enemy.music.layers = [&"brute_calm", &"brute_drums"] as Array[StringName]
	game.put(&"enemies", enemy)
	var bed := Ambience.new()
	var layer := AmbienceLayer.new()
	layer.sound = &"cave_air"
	bed.layers = [layer] as Array[AmbienceLayer]
	var accent := AmbienceAccent.new()
	accent.sounds = [&"cave_drip"] as Array[StringName]
	bed.accents = [accent] as Array[AmbienceAccent]
	for room_id: StringName in [&"cave", &"cave_deep"]:
		var place := RoomBase.new()
		place.id = room_id
		place.ambience = bed
		game.put(&"rooms", place)
	game.file(&"slam_hit")
	game.file(&"slam_scrape", true)
	game.file(&"cave_air", true)
	game.file(&"cave_drip")
	game.file(&"brute_calm", true)
	game.file(&"stray_noise")
	return game


# --- The list -------------------------------------------------------------------------------------

func test_every_id_the_data_names_is_a_row_of_its_kind() -> void:
	_open(_game())
	var want: Dictionary = {
		&"slam_hit": SoundNames.Kind.ONE_SHOT, &"slam_scrape": SoundNames.Kind.HELD,
		&"brute_death": SoundNames.Kind.ONE_SHOT, &"brute_burning": SoundNames.Kind.HELD,
		&"brute_calm": SoundNames.Kind.MUSIC, &"brute_drums": SoundNames.Kind.MUSIC,
		&"cave_air": SoundNames.Kind.BED, &"cave_drip": SoundNames.Kind.ACCENT,
		FeelScript.CAST_SOUND: SoundNames.Kind.ONE_SHOT, SoundRoomScript.PRESET.hit_sound: SoundNames.Kind.ONE_SHOT,
	}
	for id: StringName in want:
		var row: SoundRoomScript.Row = room.row_of.get(id) as SoundRoomScript.Row
		check(row != null, "%s is a row" % id)
		if row != null:
			check_equal(row.kind, want[id], "%s's kind" % id)


func test_a_named_id_with_no_file_is_missing_and_cannot_be_played() -> void:
	_open(_game())
	var row: SoundRoomScript.Row = room.row_of[&"brute_death"]
	check_equal(row.state, SoundRoomScript.State.MISSING, "named, no file: missing (red)")
	check(row.button.disabled, "its button is off")
	check_equal(room.row_of[&"slam_hit"].state, SoundRoomScript.State.HEARD, "named with a file: heard")


func test_a_file_nothing_names_is_unnamed() -> void:
	_open(_game())
	check_equal(room.row_of[&"stray_noise"].state, SoundRoomScript.State.UNNAMED, "a file nothing names (red)")


func test_a_bed_shared_by_two_rooms_names_both() -> void:
	_open(_game())
	var where: String = room.row_of[&"cave_air"].where
	check(where.contains("room cave,") or where.ends_with("room cave"), "the first room: %s" % where)
	check(where.contains("room cave_deep"), "and the second: %s" % where)


func test_every_hit_kinds_sound_of_feels_preset_is_a_row() -> void:
	_open(_game())
	var kinds_found: int = 0
	for kind: Variant in SoundRoomScript.PRESET.kind_looks:
		var id := StringName((SoundRoomScript.PRESET.kind_looks[kind] as Dictionary).get("sound", ""))
		if id != &"":
			kinds_found += 1
			check(room.row_of.has(id), "%s's hit sound %s is a row" % [kind, id])
	check(kinds_found >= 2, "the preset names its hit kinds' sounds")


func test_the_games_own_data_is_listed() -> void:
	_open()
	var game: Node = root.get_node("Registry")
	var filed: Array[StringName] = game.call(&"sound_ids")
	for id: StringName in [FeelScript.CAST_SOUND, &"hit", &"broom_burning", &"broom_scrape", &"broom_splinter", &"boss_broom", &"boss_broom_fire", &"amb_crypt_air"]:
		var row: SoundRoomScript.Row = room.row_of.get(id) as SoundRoomScript.Row
		check(row != null and row.state != SoundRoomScript.State.FIXTURE, "the game's %s is a row" % id)
		if row != null:
			check_equal(row.state == SoundRoomScript.State.MISSING, not filed.has(id), "%s is red only without a file" % id)
	check(room.tracks.size() >= 2, "the boss's music and the fixtures' track are tracks")


func test_the_fixtures_are_rows_of_their_own() -> void:
	_open(_game())
	for id: StringName in [&"room_whoosh", &"room_fire_hit", &"room_glass_ping", &"room_hum", &"room_track_calm", &"room_track_pulse"]:
		var row: SoundRoomScript.Row = room.row_of.get(id) as SoundRoomScript.Row
		check(row != null and row.state == SoundRoomScript.State.FIXTURE, "%s is a fixture row" % id)
	check_equal(room.row_of[&"room_hum"].kind, SoundNames.Kind.HELD, "the looping fixture is held")
	check_equal(room.row_of[&"room_track_calm"].kind, SoundNames.Kind.MUSIC, "the track's layers are music")
	check(room.audio.sound(&"room_whoosh") is AudioStreamRandomizer, "a baked one-shot is its variants")


# --- Playing --------------------------------------------------------------------------------------

func test_a_one_shot_plays_a_voice_on_sfx() -> void:
	_open(_game())
	room.press(&"room_whoosh")
	check_equal(room.audio.voices.voices_of(&"room_whoosh"), 1, "one voice plays it")
	check_equal(room.audio.voices.last, &"room_whoosh", "the last played")
	var played: int = -1
	for i in AudioScript.VOICES:
		var voice := room.audio.voices.player(i) as AudioStreamPlayer2D
		if voice.stream == room.audio.sound(&"room_whoosh"):
			played = i
			check_equal(voice.bus, AudioScript.BUS_SFX, "on SFX")
	check(played >= 0, "a voice has its stream")


## Every one-shot the game names and has a file of (the combat set since AU5) plays in the room as
## the game plays it: its variants, each there, held for its longest, on SFX, and let go after.
func test_every_filed_game_one_shot_plays_its_variants_on_sfx() -> void:
	_open()
	var played: int = 0
	for row: SoundRoomScript.Row in room.rows:
		if row.state != SoundRoomScript.State.HEARD or row.kind != SoundNames.Kind.ONE_SHOT:
			continue
		var stream: AudioStream = room.audio.sound(row.id)
		check(stream != null, "%s loads" % row.id)
		check(stream is AudioStreamRandomizer, "%s is its baked variants" % row.id)
		var variants := stream as AudioStreamRandomizer
		if variants != null:
			check(variants.streams_count >= 2, "%s has its variants" % row.id)
			for i in variants.streams_count:
				check(variants.get_stream(i) is AudioStreamOggVorbis, "%s's variant %d is there" % [row.id, i + 1])
		var seconds: float = room.audio.length_of(row.id)
		check(seconds > 0.05 and seconds < 3.0, "%s is held for its length: %s s" % [row.id, seconds])
		room.press(row.id)
		check_equal(room.audio.voices.voices_of(row.id), 1, "%s plays a voice" % row.id)
		var on_sfx: int = 0
		for i in AudioScript.VOICES:
			var voice := room.audio.voices.player(i) as AudioStreamPlayer2D
			if voice.stream == stream and voice.bus == AudioScript.BUS_SFX:
				on_sfx += 1
		check_equal(on_sfx, 1, "%s plays on SFX" % row.id)
		for i in ceili(seconds / FRAME) + 2:
			room.audio.step(FRAME)
		check_equal(room.audio.voices.voices_of(row.id), 0, "%s's voice is let go after its length" % row.id)
		played += 1
	check(played >= 24, "the combat set's one-shots all play: %d" % played)


func test_an_accent_plays_on_the_ambience_bus() -> void:
	_open(_game())
	room.press(&"cave_drip")
	var voice: AudioStreamPlayer2D = room.audio.ambience.accent_voice()
	check(voice != null and voice.stream == room.audio.sound(&"cave_drip"), "on the bed's accent voices")
	if voice != null:
		check_equal(voice.bus, AudioScript.BUS_AMBIENCE, "on Ambience")


func test_a_held_sound_loops_until_pressed_again() -> void:
	_open(_game())
	room.press(&"room_hum")
	var row: SoundRoomScript.Row = room.row_of[&"room_hum"]
	check(row.handle != 0 and room.audio.is_held(row.handle), "it is held")
	check_equal(room.audio.held.voice_of(row.handle).bus, AudioScript.BUS_SFX, "on SFX")
	check_equal(row.button.text, "Stop", "its button stops it")
	var handle: int = row.handle
	for i in 60:
		room.audio.step(FRAME)
	check(room.audio.is_held(handle), "still held a second on")
	room.press(&"room_hum")
	check(not room.audio.is_held(handle), "let go")
	check_equal(row.button.text, "Loop", "its button loops it again")


func test_a_bed_layer_plays_its_whole_bed_on_the_ambience_bus_until_pressed_again() -> void:
	var game := _game()
	_open(game)
	room.press(&"cave_air")
	var bed: Ambience = (game.folders[&"rooms"][0] as RoomBase).ambience
	check(room.audio.ambience.ambience() == bed, "its bed plays, as a room's does")
	check(room.audio.ambience.stream_of(0) == room.audio.sound(&"cave_air"), "its layer's sound")
	check_equal(room.audio.ambience.bed_player(0).bus, AudioScript.BUS_AMBIENCE, "on Ambience")
	check_equal(room.row_of[&"cave_air"].button.text, "Stop", "its button stops it")
	room.press(&"cave_air")
	check(room.audio.ambience.ambience() == null, "pressed again, the bed goes")


func test_the_fixture_track_steps_through_its_intensity() -> void:
	_open(_game())
	var at: int = room.tracks.find(SoundRoomScript.FIXTURE_TRACK)
	check(at >= 0, "the fixture track is listed")
	room.set_intensity(at, 1)
	var music: Node = room.audio.music
	check(music.call(&"track") == SoundRoomScript.FIXTURE_TRACK, "it plays")
	check(music.call(&"stream_of", 0) == room.audio.sound(&"room_track_calm"), "its first layer's sound")
	check(music.call(&"is_heard", 0) and not music.call(&"is_heard", 1), "intensity 1: the calm layer alone")
	for node: Node in music.get_children():
		check_equal((node as AudioStreamPlayer).bus, AudioScript.BUS_MUSIC_DUCK, "every music player on MusicDuck")
	room.set_intensity(at, 2)
	check(music.call(&"is_heard", 0) and music.call(&"is_heard", 1), "intensity 2: both layers")
	for i in 120:
		room.audio.step(FRAME)
	check(is_equal_approx(music.call(&"level_of", 1), 1.0), "the second layer faded in")
	room.set_intensity(at, 0)
	check(music.call(&"track") == null, "intensity 0: silence")


func test_a_music_row_plays_its_track_up_to_its_layer() -> void:
	_open(_game())
	room.press(&"room_track_pulse")
	var at: int = room.tracks.find(SoundRoomScript.FIXTURE_TRACK)
	check_equal(room.track_intensity[at], 2, "the pulse is the second layer")
	check(room.audio.music.call(&"track") == SoundRoomScript.FIXTURE_TRACK, "its track plays")


func test_the_duck_lowers_the_music_and_lets_it_back() -> void:
	_open(_game())
	room.duck()
	for i in 10:
		room.audio.step(FRAME)
	var duck_bus: int = AudioServer.get_bus_index(AudioScript.BUS_MUSIC_DUCK)
	check(AudioServer.get_bus_volume_db(duck_bus) < -1.0, "the MusicDuck bus is lowered: %s dB" % AudioServer.get_bus_volume_db(duck_bus))
	for i in 180:
		room.audio.step(FRAME)
	check(is_equal_approx(AudioServer.get_bus_volume_db(duck_bus), 0.0), "and back up once its seconds are out")


func test_a_bus_slider_sets_its_volume() -> void:
	_open(_game())
	room.set_bus_volume(AudioScript.BUS_SFX, 50)
	check(is_equal_approx(room.audio.buses.volume(AudioScript.BUS_SFX), AudioVolumes.share_of(50)), "SFX at the setting's half")
	check(is_equal_approx(room.audio.buses.volume(AudioScript.BUS_MUSIC), 1.0), "the others as they were")


func test_stop_all_lets_go_of_every_held_row_and_track() -> void:
	_open(_game())
	room.press(&"room_hum")
	room.set_intensity(room.tracks.find(SoundRoomScript.FIXTURE_TRACK), 2)
	room.stop_all()
	check_equal(room.row_of[&"room_hum"].handle, 0, "no row held")
	check(room.audio.music.call(&"track") == null, "no music")
