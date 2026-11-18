extends "res://tests/support/suite.gd"
## core/audio (docs/milestones/sound.md, section 5): the buses (`default_bus_layout.tres`), the four
## volume settings heard on their events and eased on their buses (the "Ambience volume" cases moved
## from Feel's room sound), the duck (the most asked for wins, a ramp both ways), the UI's voices (one
## play an id a frame) and the over lane playing while the tree is paused. An Audio of the test's own
## on a bus and a registry of the test's own; every bus is put back after each test.
const AudioScript := preload("res://core/audio/audio.gd")
const BusesScript := preload("res://core/audio/buses.gd")
const EventsScript := preload("res://core/events/events.gd")
const SoundBook := preload("res://tests/core/audio/sound_book.gd")

const FRAME: float = 1.0 / 60.0

var book: SoundBook
var bus: EventsScript
var audio: AudioScript


func before_each() -> void:
	book = own(SoundBook.new()) as SoundBook
	bus = own(EventsScript.new()) as EventsScript
	audio = AudioScript.new()
	audio.registry = book
	audio.events = bus
	root.add_child(audio)


func after_each() -> void:
	audio.buses.reset()
	audio.clear_world()
	audio.stop_over()
	audio.ui.clear()
	audio.free()


func _db_of(name: StringName) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(name))


# --- The buses ------------------------------------------------------------------------------------

func test_a_new_audio_starts_every_bus_full_and_puts_them_back_as_it_goes() -> void:
	bus.music_volume_changed.emit(0)
	audio.duck(-12.0, 5.0)
	for frame in 30:
		audio.step(FRAME)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioScript.BUS_MUSIC)), "the music muted")
	var other: AudioScript = AudioScript.new()
	other.registry = book
	root.add_child(other)
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioScript.BUS_MUSIC)), "a new Audio starts the music bus full")
	check(is_equal_approx(_db_of(AudioScript.BUS_MUSIC_DUCK), 0.0), "and no duck")
	bus.sound_volume_changed.emit(0)
	for frame in 30:
		audio.step(FRAME)
	other.free()
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioScript.BUS_SFX)), "an Audio leaving puts the buses back")


func test_the_layout_has_every_bus_and_the_duck_under_the_music() -> void:
	for name: StringName in [AudioScript.BUS_MUSIC, AudioScript.BUS_MUSIC_DUCK, AudioScript.BUS_SFX, AudioScript.BUS_AMBIENCE, AudioScript.BUS_UI]:
		check(AudioServer.get_bus_index(name) > 0, "the bus %s exists" % name)
	check_equal(AudioServer.get_bus_send(AudioServer.get_bus_index(AudioScript.BUS_MUSIC_DUCK)), AudioScript.BUS_MUSIC, "MusicDuck sends to Music")
	for name: StringName in [AudioScript.BUS_MUSIC, AudioScript.BUS_SFX, AudioScript.BUS_AMBIENCE, AudioScript.BUS_UI]:
		check_equal(AudioServer.get_bus_send(AudioServer.get_bus_index(name)), AudioScript.BUS_MASTER, "%s sends to Master" % name)
	check_equal(ProjectSettings.get_setting("audio/buses/default_bus_layout"), "res://default_bus_layout.tres", "named in project.godot")


func test_each_setting_is_heard_on_its_event_and_eased_on_its_bus() -> void:
	var events: Dictionary = {
		AudioScript.BUS_MUSIC: bus.music_volume_changed, AudioScript.BUS_SFX: bus.sound_volume_changed,
		AudioScript.BUS_AMBIENCE: bus.ambience_volume_changed, AudioScript.BUS_UI: bus.ui_volume_changed,
	}
	for name: StringName in events:
		(events[name] as Signal).emit(50)
		var half: float = AudioVolumes.share_of(50)
		check(is_equal_approx(audio.buses.volume(name), half), "%s: 50%% asked on the curve" % name)
		var biggest: float = 0.0
		var last: float = audio.buses.heard(name)
		for frame in 60:
			audio.step(FRAME)
			biggest = maxf(biggest, absf(audio.buses.heard(name) - last))
			last = audio.buses.heard(name)
		check(biggest <= BusesScript.VOLUME_RATE * FRAME + 0.0001, "%s eased a frame's share at a time, the biggest %s" % [name, biggest])
		check(is_equal_approx(_db_of(name), linear_to_db(half)), "%s: the bus at the curve's level, got %s" % [name, _db_of(name)])
	check(is_equal_approx(_db_of(AudioScript.BUS_MUSIC_DUCK), 0.0), "the duck's bus is not the music setting's")


func test_a_volume_at_zero_mutes_its_bus_and_comes_back() -> void:
	bus.ambience_volume_changed.emit(0)
	for frame in 60:
		audio.step(FRAME)
	var at: int = AudioServer.get_bus_index(AudioScript.BUS_AMBIENCE)
	check(AudioServer.is_bus_mute(at), "0%: the bus is muted, nothing on it is mixed")
	check_equal(audio.buses.heard(AudioScript.BUS_AMBIENCE), 0.0, "silent")
	bus.ambience_volume_changed.emit(100)
	audio.step(FRAME)
	check(not AudioServer.is_bus_mute(at), "coming back up it plays again")
	check(audio.buses.heard(AudioScript.BUS_AMBIENCE) > 0.0 and audio.buses.heard(AudioScript.BUS_AMBIENCE) < 0.1, "eased, not a jump")


func test_the_volume_curve_is_even_in_db_from_minus_40_to_0() -> void:
	check_equal(AudioVolumes.share_of(0), 0.0, "0% silent")
	check(is_equal_approx(linear_to_db(AudioVolumes.share_of(10)), AmbienceVolume.QUIETEST_DB), "10%%: %s dB" % AmbienceVolume.QUIETEST_DB)
	check(is_equal_approx(AudioVolumes.share_of(100), 1.0), "100%: the bus's own level")
	var step: float = linear_to_db(AudioVolumes.share_of(20)) - linear_to_db(AudioVolumes.share_of(10))
	for percent in range(20, 101, 10):
		var rise: float = linear_to_db(AudioVolumes.share_of(percent)) - linear_to_db(AudioVolumes.share_of(percent - 10))
		check(absf(rise - step) < 0.01, "%d%%: an even %s dB louder, got %s" % [percent, step, rise])
	check_equal(AudioVolumes.AMBIENCE_KEY, &"ambience_volume", "the ambience setting keeps its saved key")


# --- The duck -------------------------------------------------------------------------------------

func test_the_duck_comes_in_over_its_ramp_and_the_most_asked_for_wins() -> void:
	audio.duck(-3.0, 1.0)
	audio.duck(-9.0, 0.4)
	audio.step(BusesScript.DUCK_IN / 2.0)
	check(is_equal_approx(audio.buses.ducked(), -4.5), "half way down the ramp to the deepest, got %s" % audio.buses.ducked())
	audio.step(BusesScript.DUCK_IN / 2.0)
	check(is_equal_approx(audio.buses.ducked(), -9.0), "the most asked for, over DUCK_IN")
	check(is_equal_approx(_db_of(AudioScript.BUS_MUSIC_DUCK), -9.0), "on the MusicDuck bus")
	check(is_equal_approx(_db_of(AudioScript.BUS_MUSIC), 0.0), "the Music bus (the setting's) untouched")
	var last: float = audio.buses.ducked()
	var biggest: float = 0.0
	for frame in int(0.7 / FRAME):
		audio.step(FRAME)
		biggest = maxf(biggest, absf(audio.buses.ducked() - last))
		last = audio.buses.ducked()
	check(is_equal_approx(audio.buses.ducked(), -3.0), "the deeper's seconds out: back up to the one still under way, got %s" % audio.buses.ducked())
	check(biggest <= 6.0 / BusesScript.DUCK_OUT * FRAME + 0.0001, "letting up is a ramp, never a step (biggest %s dB a frame)" % biggest)
	for frame in int(1.0 / FRAME):
		audio.step(FRAME)
	check_equal(audio.buses.ducked(), 0.0, "every duck over: none")
	audio.duck(3.0, 1.0)
	audio.duck(-6.0, 0.0)
	audio.step(FRAME)
	check_equal(audio.buses.ducked(), 0.0, "a duck up, or of no seconds, asks nothing")


# --- The over lane and the UI ---------------------------------------------------------------------

func test_the_over_lane_plays_while_the_tree_is_paused() -> void:
	book.know([&"sting", &"step"])
	audio.audible = true
	paused = true
	var over: int = audio.play_over(&"sting")
	var world: int = audio.play(&"step")
	var lane: AudioStreamPlayer = audio.over.player(over) as AudioStreamPlayer
	var voice: AudioStreamPlayer2D = audio.voices.player(world) as AudioStreamPlayer2D
	var over_on: bool = lane.playing and not lane.stream_paused and lane.can_process()
	var world_still: bool = not voice.can_process()
	paused = false
	audio.audible = AudioScript.hears_audio()
	check(over_on, "the over lane's voice plays on with the tree paused (a boss intro)")
	check(world_still, "a world voice stands still with it")
	check_equal(lane.bus, AudioScript.BUS_SFX, "on SFX")
	check(audio.play_over(&"nothing") < 0, "a sound with no file plays nothing")


func test_the_ui_plays_one_of_an_id_a_frame_on_its_bus() -> void:
	book.know([&"move", &"choose"])
	bus.ui_sound_requested.emit(&"move")
	bus.ui_sound_requested.emit(&"move")
	bus.ui_sound_requested.emit(&"choose")
	check_equal(audio.ui.started, 2, "one move and one choose this frame")
	check_equal(audio.ui.voices_of(&"move"), 1, "the second move of the frame was dropped")
	audio.step(FRAME)
	bus.ui_sound_requested.emit(&"move")
	check_equal(audio.ui.started, 3, "the next frame's move plays")
	audio.step(FRAME)
	var played: int = 0
	for i in AudioScript.UI_VOICES + 3:
		book.know([StringName("ui_%d" % i)])
		if audio.play_ui(StringName("ui_%d" % i)) >= 0:
			played += 1
	check_equal(played, AudioScript.UI_VOICES, "at most UI_VOICES plays a frame")
	check(audio.play_ui(&"ui_0") < 0, "and still one of an id")
	check_equal((audio.ui.player(0) as AudioStreamPlayer).bus, AudioScript.BUS_UI, "on the UI bus")
	check(audio.ui.get_parent().process_mode == Node.PROCESS_MODE_ALWAYS, "on the over lane: heard over the pause menu")
	bus.ui_sound_requested.emit(&"no_such")
	check(audio.play_ui(&"no_such") < 0, "an id with no file plays nothing")
