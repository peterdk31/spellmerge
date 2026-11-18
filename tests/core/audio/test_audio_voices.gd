extends "res://tests/support/suite.gd"
## core/audio (docs/milestones/sound.md, section 5): the world's one-shot voices and the held sounds,
## moved from Feel's sounds (boss plan OB15) with the cases that tested them there, and a sound's
## length with its variants (`AudioLength`). An Audio of the test's own on a registry of the test's
## own (`sound_book.gd`).
const AudioScript := preload("res://core/audio/audio.gd")
const HeldScript := preload("res://core/audio/held.gd")
const VoicesScript := preload("res://core/audio/voices.gd")
const SoundBook := preload("res://tests/core/audio/sound_book.gd")

var book: SoundBook
var audio: AudioScript


func before_each() -> void:
	book = own(SoundBook.new()) as SoundBook
	audio = AudioScript.new()
	audio.registry = book
	root.add_child(audio)


func after_each() -> void:
	audio.clear_world()
	audio.free()


# --- One-shots ------------------------------------------------------------------------------------

func test_a_sound_plays_where_it_happens_and_a_missing_one_is_silent() -> void:
	book.know([&"knock"])
	check_equal(audio.play(&"nothing", Vector2(5, 5)), -1, "a sound with no file plays nothing")
	var voice: int = audio.play(&"knock", Vector2(120, -40))
	check(voice >= 0, "a known sound plays")
	var player: AudioStreamPlayer2D = audio.voices.player(voice) as AudioStreamPlayer2D
	check(player.global_position.is_equal_approx(Vector2(120, -40)), "from where it happens in the room")
	check(player.max_distance >= 1000.0, "heard well off the picture (a telegraph)")
	check_equal(player.bus, AudioScript.BUS_SFX, "on the SFX bus")
	check_equal(player.panning_strength, AudioScript.PAN, "panned by PAN")


func test_one_sound_has_at_most_its_voices_and_the_oldest_starts_again() -> void:
	book.know([&"knock", &"bell"])
	var first: int = audio.play(&"knock")
	for i in AudioScript.PER_SOUND + 3:
		audio.play(&"knock")
	check_equal(audio.voices.voices_of(&"knock"), AudioScript.PER_SOUND, "one sound plays on PER_SOUND voices at most")
	check(audio.play(&"bell") >= 0 and audio.voices.voices_of(&"bell") == 1, "another sound still has its voice")
	check_equal(audio.voices.voices_of(&"knock"), AudioScript.PER_SOUND, "it took no voice of the knock's")
	audio.step_world(0.2)
	check_equal(audio.voices.voices_of(&"knock"), 0, "once over they hold no voice")
	check(first >= 0, "the first played")


func test_a_long_sound_is_not_cut_short_while_a_voice_is_done() -> void:
	book.know_as(&"splinter", book.long)
	book.know_as(&"tick", SoundBook.wav(80, false))
	audio.play(&"splinter")
	for round in 3:
		for i in AudioScript.PER_SOUND:
			audio.play(&"tick", Vector2(float(i), 0.0))
		audio.step_world(VoicesScript.MIN_SECONDS * 2.0)
	check_equal(audio.voices.voices_of(&"splinter"), 1, "a second-long sound plays on while short ones come and go")
	for i in AudioScript.VOICES + 1:
		book.know([StringName("other_%d" % i)])
		audio.play(StringName("other_%d" % i))
	check_equal(audio.voices.voices_of(&"splinter"), 0, "with every voice busy the one that started first gives way")


func test_a_randomizer_is_as_long_as_its_longest_variant() -> void:
	var variants := AudioStreamRandomizer.new()
	variants.add_stream(-1, SoundBook.wav(800, false))
	variants.add_stream(-1, book.long)
	variants.add_stream(-1, SoundBook.wav(4000, false))
	check_equal(variants.get_length(), 0.0, "Godot 4.7 gives a randomizer no length of its own")
	check(is_equal_approx(AudioLength.of(variants), 1.0), "its longest variant's: 1 s")
	check(is_equal_approx(AudioLength.of(book.long), 1.0), "a plain stream's own")
	check_equal(AudioLength.of(null), 0.0, "none: 0")
	book.know_as(&"cast", variants)
	audio.play(&"cast")
	audio.step_world(0.9)
	check_equal(audio.voices.voices_of(&"cast"), 1, "a voice is held for the longest variant")
	audio.step_world(0.2)
	check_equal(audio.voices.voices_of(&"cast"), 0, "and then let go")
	check(is_equal_approx(audio.length_of(&"cast"), 1.0), "Audio's length of an id")


# --- Held sounds ----------------------------------------------------------------------------------

func test_a_held_sound_follows_its_body_until_let_go() -> void:
	book.know([&"swish"])
	var body: Node2D = own(Node2D.new()) as Node2D
	root.add_child(body)
	body.position = Vector2(10, 0)
	var handle: int = audio.hold(&"swish", body, Vector2.INF, 4.0)
	check(handle != 0, "held")
	body.position = Vector2(60, 20)
	audio.step_world(0.05)
	check(audio.held_at(handle).is_equal_approx(Vector2(60, 20)), "it goes with its body")
	audio.release(handle + 1)
	check(audio.is_held(handle), "letting go of another handle lets nothing go")
	audio.release(handle)
	check(not audio.is_held(handle), "its own handle lets it go")
	check(audio.has_held(handle) and audio.held.held_count == 1, "it fades out first")
	audio.step_world(HeldScript.FADE + 0.01)
	check_equal(audio.held.held_count, 0, "then it is gone")
	check(not audio.has_held(handle), "and its handle with it")


func test_a_held_sound_ends_with_its_seconds_or_its_body() -> void:
	book.know([&"hum", &"roar"])
	var hum: int = audio.hold(&"hum", null, Vector2(4, 4), 0.5)
	check(audio.held_at(hum).is_equal_approx(Vector2(4, 4)), "with no body it stays where it started")
	var body: Node2D = own(Node2D.new()) as Node2D
	root.add_child(body)
	var roar: int = audio.hold(&"roar", body, Vector2.ZERO, INF)
	audio.step_world(0.25)
	check(audio.is_held(hum) and audio.is_held(roar), "both held a while")
	audio.step_world(0.3)
	check(not audio.is_held(hum), "its seconds ran out")
	check(audio.is_held(roar), "one of INF lasts on")
	root.remove_child(body)
	audio.step_world(0.01)
	check(not audio.is_held(roar), "until its body is gone")


func test_a_held_sound_whose_body_was_freed_moves_slots_without_an_error() -> void:
	# The boss recording failed now and then (2026-11-18): a held sound ended while the last one's
	# body had just been freed, and moving that freed node into the gone one's slot was an engine
	# error (the test runner fails a test whose log has one).
	book.know([&"hum", &"roar"])
	var hum: int = audio.hold(&"hum", null, Vector2(4, 4), INF)
	var body := Node2D.new()
	root.add_child(body)
	var roar: int = audio.hold(&"roar", body, Vector2.ZERO, INF)
	audio.release(hum)
	body.free()
	# The first fades out and goes; the last, its body freed and not yet stepped, takes its slot.
	audio.step_world(HeldScript.FADE + 0.01)
	check(not audio.has_held(hum), "the first is gone")
	check(audio.has_held(roar) and not audio.is_held(roar), "the one whose body was freed fades out")
	audio.step_world(HeldScript.FADE + 0.01)
	check_equal(audio.held.held_count, 0, "then it is gone too")


func test_a_held_sound_taken_over_goes_on_and_the_slots_are_capped() -> void:
	book.know([&"roar"])
	var first: int = audio.hold(&"roar", null, Vector2.ZERO, INF)
	var voice: AudioStreamPlayer2D = audio.held.voice_of(first)
	var second: int = audio.hold(&"roar", null, Vector2.ZERO, INF, 0.0, AudioScript.BUS_SFX, first)
	check(second != first and second != 0, "a new handle")
	check_equal(audio.held.held_count, 1, "taken over, not doubled")
	check(audio.held.voice_of(second) == voice, "on the same voice")
	check(not audio.has_held(first), "the old handle is gone")
	check_equal(audio.hold(&"nothing", null, Vector2.ZERO, 1.0), 0, "a sound with no file holds nothing")
	check_equal(audio.hold(&"roar", null, Vector2.ZERO, 0.0), 0, "nor one of no seconds")
	for i in HeldScript.SLOTS + 4:
		book.know([StringName("loop_%d" % i)])
		audio.hold(StringName("loop_%d" % i), null, Vector2.ZERO, 1.0 + float(i))
	check_equal(audio.held.held_count, HeldScript.SLOTS, "at most SLOTS held at once")
	audio.release_all()
	check(not audio.is_held(second), "all let go")
	audio.clear_world()
	check_equal(audio.held.held_count, 0, "clearing the world stops them all")


func test_a_play_allocates_nothing() -> void:
	book.know([&"knock", &"hum"])
	audio.play(&"knock")
	audio.hold(&"hum", null, Vector2.ZERO, 0.5)
	audio.step_world(0.01)
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for i in 200:
		audio.play(&"knock", Vector2(float(i), 0.0))
		audio.hold(&"hum", null, Vector2.ZERO, 0.5)
		audio.step_world(1.0 / 60.0)
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "200 frames of plays make no object")
