extends "res://tests/support/suite.gd"
## core/audio (docs/milestones/sound.md, section 5): the music (`music.gd`, moved from Feel, boss plan
## OB15, unchanged in behaviour), with the cases that tested it there: a track's layers by intensity,
## fades, and a change inside a fade. Its players are on the MusicDuck bus. An Audio of the test's own
## on a registry of the test's own (`sound_book.gd`).
const AudioScript := preload("res://core/audio/audio.gd")
const MusicScript := preload("res://core/audio/music.gd")
const SoundBook := preload("res://tests/core/audio/sound_book.gd")

var book: SoundBook
var audio: AudioScript


func before_each() -> void:
	book = own(SoundBook.new()) as SoundBook
	audio = AudioScript.new()
	audio.registry = book
	root.add_child(audio)


func after_each() -> void:
	audio.music.stop()
	audio.free()


func test_the_music_plays_on_the_duck_bus_through_play_track() -> void:
	book.know([&"a"])
	var track := MusicTrack.new()
	track.layers = [&"a"] as Array[StringName]
	audio.play_track(track, 1)
	check(audio.music.track() == track and audio.music.stream_of(0) == book.short, "Audio plays the track")
	for node in audio.music.get_children():
		check_equal((node as AudioStreamPlayer).bus, AudioScript.BUS_MUSIC_DUCK, "every music player on MusicDuck")


func test_a_track_of_entries_plays_one_at_a_time() -> void:
	var track := MusicTrack.new()
	track.layers = [&"a", &"b", &"c"] as Array[StringName]
	track.stacked = false
	var heard := PackedByteArray()
	track.audible(2, heard)
	check_equal(heard, PackedByteArray([0, 1, 0]), "entries: intensity 2 is the second alone")
	track.stacked = true
	track.audible(2, heard)
	check_equal(heard, PackedByteArray([1, 1, 0]), "stacked: the first two")
	track.audible(9, heard)
	check_equal(heard, PackedByteArray([1, 1, 1]), "past the last, all")
	check(MusicTrack.new().problems("x").size() == 1, "a track needs a layer")
	var long := MusicTrack.new()
	long.layers = [&"a", &"", &"c", &"d", &"e"] as Array[StringName]
	check_equal(long.problems("x").size(), 2, "at most LAYERS_MOST, none empty")
	var data := EnemyBase.new()
	data.id = &"x"
	data.music = MusicTrack.new()
	check("\n".join(data.problems()).contains("music"), "an enemy's music is checked with its data")


func test_music_changes_fade_and_silence_stops() -> void:
	book.know([&"a", &"b"])
	var music: MusicScript = audio.music
	var one := MusicTrack.new()
	one.layers = [&"a"] as Array[StringName]
	one.fade = 1.0
	music.play(one, 1)
	music.step(0.5)
	check(is_equal_approx(music.level_of(0), 0.5), "a layer fades in over the fade")
	var two := MusicTrack.new()
	two.layers = [&"b"] as Array[StringName]
	music.play(two, 1)
	check(is_equal_approx(music.fading_level(), 0.5), "the last track fades out from where it was")
	music.step(1.0)
	check_equal(music.fading_level(), 0.0, "and is gone after its fade")
	var stacked := MusicTrack.new()
	stacked.layers = [&"a", &"b"] as Array[StringName]
	music.play(stacked, 1)
	for i in 40:
		music.step(0.05)
	music.play(one, 1)
	check(music.fading_level_of(0) > 0.9, "a stacked track's heard layer fades out from full")
	check_equal(music.fading_level_of(1), 0.0, "and its silent layer stays silent as it goes")
	music.stop()
	check(music.track() == null and music.stream_of(0) == null, "silence")


func test_a_track_change_inside_a_fade_never_cuts_the_louder() -> void:
	book.know([&"a", &"b", &"c"])
	var music: MusicScript = audio.music
	var tracks: Array[MusicTrack] = []
	for id: StringName in [&"a", &"b", &"c"]:
		var track := MusicTrack.new()
		track.layers = [id] as Array[StringName]
		track.fade = 1.0
		tracks.append(track)
	music.play(tracks[0], 1)
	music.step(1.0)
	music.play(tracks[1], 1)
	music.step(0.3)
	var b_in: float = music.level_of(0)
	var a_out: float = music.fading_level()
	music.play(tracks[0], 1)
	check(music.track() == tracks[0] and music.fading_track() == tracks[1], "A, B, A: the sets swap")
	check(is_equal_approx(music.level_of(0), a_out) and is_equal_approx(music.fading_level(), b_in), "each going on from where it was")
	var last: float = music.level_of(0) + music.fading_level()
	var largest: float = 0.0
	for i in 60:
		music.step(1.0 / 60.0)
		var now: float = music.level_of(0) + music.fading_level()
		largest = maxf(largest, last - now)
		last = now
	check(largest <= 1.0 / 60.0 + 0.0001, "no frame's summed level drops more than a frame's share")
	music.play(tracks[1], 1)
	music.step(0.6)
	var louder_level: float = maxf(music.level_of(0), music.fading_level())
	var louder: MusicTrack = tracks[1] if music.level_of(0) >= music.fading_level() else tracks[0]
	music.play(tracks[2], 1)
	check(music.track() == tracks[2] and music.fading_track() == louder, "A, B, C: the louder goes on fading out")
	check(is_equal_approx(music.fading_level(), louder_level), "from where it was")
	music.stop()
