extends "res://tests/support/suite.gd"
## Boss plan OB15: held sounds, sounds where they happen, the voices a sound may have, and music
## with intensity, all drawn only (gameplay/feel: `sounds.gd`, `music.gd`). Sound files do not exist
## yet, so a registry of the test's own answers every sound id it knows with a silent stream, and
## knows the test's own cues and rooms; nothing here names a boss of the game.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_feel_sounds.gd

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SoundsScript := preload("res://gameplay/feel/sounds.gd")
const MusicScript := preload("res://gameplay/feel/music.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")


## The game's registry, with a silent sound for every id in `known` and the test's own cues and
## rooms (`extra`, folder -> id -> resource) over its content.
class SoundRegistry:
	extends RegistryScript
	var base: RegistryScript = null
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	var long: AudioStreamWAV = null
	var known: Dictionary = {}
	var extra: Dictionary = {}

	func get_sound(id: StringName) -> AudioStream:
		if not known.has(id):
			return null
		return long if int(known[id]) == 2 else stream

	func get_resource(folder: StringName, id: StringName) -> Resource:
		var mine: Resource = (extra.get(folder, {}) as Dictionary).get(id) as Resource
		return mine if mine != null else base.get_resource(folder, id)

	func get_all(folder: StringName) -> Array[Resource]:
		return base.get_all(folder)

	func get_ids(folder: StringName) -> Array[StringName]:
		return base.get_ids(folder)


## A spell runtime that only answers whether a staff winds up.
class Winding:
	extends Node
	var on: bool = true

	func is_winding(_caster: int, _staff: int) -> bool:
		return on


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
		if fx.feel != null and is_instance_valid(fx.feel):
			(fx.feel as FeelScript).sounds().clear()
			(fx.feel as FeelScript).music().stop()
		fx.free_all()


func _know(ids: Array) -> void:
	for id: Variant in ids:
		reg.known[StringName(str(id))] = true


## A sound `id` a second long (one that would be cut short).
func _know_long(id: StringName) -> void:
	if reg.long == null:
		reg.long = AudioStreamWAV.new()
		reg.long.format = AudioStreamWAV.FORMAT_8_BITS
		reg.long.mix_rate = 8000
		var data := PackedByteArray()
		data.resize(8000)
		reg.long.data = data
	reg.known[id] = 2


func _cue(id: StringName, parts: Array[Dictionary], sound: StringName = &"") -> CueBase:
	var cue := CueBase.new()
	cue.id = id
	cue.parts = parts
	cue.sound = sound
	var cues: Dictionary = reg.extra.get(&"cues", {})
	cues[id] = cue
	reg.extra[&"cues"] = cues
	check(cue.problems().is_empty(), "the test cue %s is sound: %s" % [id, cue.problems()])
	return cue


func _sounds() -> SoundsScript:
	var sounds: SoundsScript = own(SoundsScript.new()) as SoundsScript
	sounds.registry = reg
	root.add_child(sounds)
	return sounds


## A world with Feel on the test's registry.
func _world(players: int = 1) -> FeelScript:
	fx = Fixture.new(root, players)
	var feel: FeelScript = fx.with_feel() as FeelScript
	feel.registry = reg
	return feel


# --- The sounds -----------------------------------------------------------------------------

func test_a_sound_plays_where_it_happens_and_a_missing_one_is_silent() -> void:
	var sounds: SoundsScript = _sounds()
	_know([&"knock"])
	check_equal(sounds.play(&"nothing", Vector2(5, 5)), -1, "a sound with no file plays nothing")
	var voice: int = sounds.play(&"knock", Vector2(120, -40))
	check(voice >= 0, "a known sound plays")
	check(sounds.get_child(voice).global_position.is_equal_approx(Vector2(120, -40)), "from where it happens in the room")
	check((sounds.get_child(voice) as AudioStreamPlayer2D).max_distance >= 1000.0, "heard well off the picture (a telegraph)")


func test_one_sound_has_at_most_its_voices_and_the_oldest_starts_again() -> void:
	var sounds: SoundsScript = _sounds()
	_know([&"knock", &"bell"])
	var first: int = sounds.play(&"knock")
	for i in SoundsScript.PER_SOUND + 3:
		sounds.play(&"knock")
	check_equal(sounds.voices_of(&"knock"), SoundsScript.PER_SOUND, "one sound plays on PER_SOUND voices at most")
	check(sounds.play(&"bell") >= 0 and sounds.voices_of(&"bell") == 1, "another sound still has its voice")
	check_equal(sounds.voices_of(&"knock"), SoundsScript.PER_SOUND, "it took no voice of the knock's")
	sounds.step(SoundsScript.MIN_SECONDS * 2.0)
	check_equal(sounds.voices_of(&"knock"), 0, "once over they hold no voice")
	check(first >= 0, "the first played")


func test_a_long_sound_is_not_cut_short_while_a_voice_is_done() -> void:
	var sounds: SoundsScript = _sounds()
	_know_long(&"splinter")
	_know([&"tick"])
	sounds.play(&"splinter")
	for round in 3:
		for i in SoundsScript.PER_SOUND:
			sounds.play(&"tick", Vector2(float(i), 0.0))
		sounds.step(SoundsScript.MIN_SECONDS * 2.0)
	check_equal(sounds.voices_of(&"splinter"), 1, "a second-long sound plays on while short ones come and go")
	for i in SoundsScript.VOICES + 1:
		_know([StringName("other_%d" % i)])
		sounds.play(StringName("other_%d" % i))
	check_equal(sounds.voices_of(&"splinter"), 0, "with every voice busy the one that started first gives way")


func test_a_held_sound_follows_its_body_until_its_carrier_ends() -> void:
	var sounds: SoundsScript = _sounds()
	_know([&"swish"])
	var body: Node2D = own(Node2D.new()) as Node2D
	root.add_child(body)
	body.position = Vector2(10, 0)
	check(sounds.hold(&"swish", SoundsScript.Until.CARRIER, 3, 77, body, Vector2.INF, 4.0) >= 0, "held")
	body.position = Vector2(60, 20)
	sounds.step(0.05)
	check(sounds.held_at(3, &"swish").is_equal_approx(Vector2(60, 20)), "it goes with its body")
	sounds.end_carrier(3, 76)
	check(sounds.is_held(3, &"swish"), "another carrier's end lets nothing go")
	sounds.end_carrier(3, 77)
	check(not sounds.is_held(3, &"swish"), "its own carrier's end lets it go")
	check_equal(sounds.held_count, 1, "it fades out first")
	sounds.step(SoundsScript.FADE + 0.01)
	check_equal(sounds.held_count, 0, "then it is gone")


func test_a_held_sound_ends_with_its_seconds_its_body_or_its_wind_up() -> void:
	var sounds: SoundsScript = _sounds()
	_know([&"hum", &"scrape", &"roar"])
	sounds.hold(&"hum", SoundsScript.Until.SECONDS, 1, 0, null, Vector2(4, 4), 0.5)
	check(sounds.held_at(1, &"hum").is_equal_approx(Vector2(4, 4)), "with no body it stays where it started")
	var winding: Winding = own(Winding.new()) as Winding
	sounds.spells = winding
	sounds.hold(&"scrape", SoundsScript.Until.WIND, 2, 0, null, Vector2.ZERO, 10.0)
	var body: Node2D = own(Node2D.new()) as Node2D
	root.add_child(body)
	sounds.hold(&"roar", SoundsScript.Until.PHASE, 5, 1, body, Vector2.ZERO, INF)
	sounds.step(0.25)
	check(sounds.is_held(1, &"hum") and sounds.is_held(2, &"scrape") and sounds.is_held(5, &"roar"), "all held a while")
	sounds.step(0.3)
	check(not sounds.is_held(1, &"hum"), "its seconds ran out")
	winding.on = false
	sounds.step(0.01)
	check(not sounds.is_held(2, &"scrape"), "the wind-up it lasts for is over")
	check(sounds.is_held(5, &"roar"), "a phase's lasts on")
	root.remove_child(body)
	sounds.step(0.01)
	check(not sounds.is_held(5, &"roar"), "until its body is gone")


func test_a_held_sound_is_taken_over_and_let_go_by_kind() -> void:
	var sounds: SoundsScript = _sounds()
	_know([&"roar", &"swish"])
	sounds.hold(&"roar", SoundsScript.Until.PHASE, 4, 1, null, Vector2.ZERO, INF)
	sounds.hold(&"roar", SoundsScript.Until.PHASE, 4, 2, null, Vector2.ZERO, INF)
	check_equal(sounds.held_count, 1, "the same caster's same sound is taken over, not doubled")
	sounds.hold(&"swish", SoundsScript.Until.CARRIER, 4, 9, null, Vector2.ZERO, 3.0)
	check_equal(sounds.held_of(4, SoundsScript.Until.PHASE), &"roar", "its phase's sound")
	sounds.release(4, SoundsScript.Until.PHASE)
	check(not sounds.is_held(4, &"roar") and sounds.is_held(4, &"swish"), "letting go of a phase's lets go of that kind only")
	check(sounds.hold(&"nothing", SoundsScript.Until.SECONDS, 4, 0, null, Vector2.ZERO, 1.0) < 0, "a sound with no file holds nothing")
	for i in SoundsScript.HELD_SLOTS + 4:
		_know([StringName("loop_%d" % i)])
		sounds.hold(StringName("loop_%d" % i), SoundsScript.Until.SECONDS, i, 0, null, Vector2.ZERO, 1.0 + float(i))
	check_equal(sounds.held_count, SoundsScript.HELD_SLOTS, "at most HELD_SLOTS held at once")
	sounds.clear()
	check_equal(sounds.held_count, 0, "a new room stops them all")


# --- Cues and staffs' moments ----------------------------------------------------------------

func test_a_cues_held_part_is_checked() -> void:
	var cue := CueBase.new()
	cue.id = &"bad"
	cue.parts = [{"part": &"held"}, {"part": &"held", "sound": &"x", "seconds": 0.0}, {"part": &"held", "sound": &"x", "volume": 99.0}, {"part": &"held", "sound": &"x", "wobble": 1}] as Array[Dictionary]
	var lines: String = "\n".join(cue.problems())
	check(lines.contains("names no sound"), "a held part needs a sound")
	check(lines.contains("seconds"), "and seconds over 0")
	check(lines.contains("volume"), "and a volume in range")
	check(lines.contains("unknown key 'wobble'"), "and only its keys")


## An enemy whose dash staff winds up with a held scrape and a lane, swishes while it dashes and
## crunches where a wall stops it; its second staff thumps as it leaves.
func _moments_body() -> Actor:
	_know([&"scrape", &"swish", &"crunch", &"thump"])
	_cue(&"test_scrape", [{"part": &"lane"}, {"part": &"held", "sound": &"scrape", "seconds": 3.0}] as Array[Dictionary])
	_cue(&"test_swish", [{"part": &"held", "sound": &"swish"}] as Array[Dictionary])
	_cue(&"test_crunch", [] as Array[Dictionary], &"crunch")
	_cue(&"test_thump", [] as Array[Dictionary], &"thump")
	var data: EnemyBase = Fixture.staffed([[&"on_wall", &"dash", &"pulse"], [&"swing"]])
	var dash: StaffBase = data.staffs[0].staff
	dash.wind_cue = &"test_scrape"
	dash.move_cue = &"test_swish"
	dash.wall_cue = &"test_crunch"
	data.staffs[1].staff.cast_cue = &"test_thump"
	data.staffs[1].staff.wind_up = 0.0
	var body: Actor = fx.imp(Vector2.ZERO, data)
	Fixture.ai(body).profile = Fixture.exact()
	return body


func test_a_wind_up_holds_its_scrape_until_the_cast_leaves() -> void:
	var feel: FeelScript = _world()
	var body: Actor = _moments_body()
	fx.players[0].position = Vector2(120.0, 0.0)
	var sounds: SoundsScript = feel.sounds()
	var held: bool = false
	for i in 12:
		fx.run(body, 1)
		if body.caster.is_winding(0):
			held = sounds.is_held(body.id, &"scrape")
			break
	check(body.caster.is_winding(0), "it winds its dash up")
	check(held, "its scrape is held while it winds up")
	while body.caster.is_winding(0):
		fx.run(body, 1)
	fx.run(body, 1)
	check(not sounds.is_held(body.id, &"scrape"), "the cast left: the scrape is let go")


func test_a_staffs_dash_swishes_until_it_lands() -> void:
	var feel: FeelScript = _world()
	var body: Actor = _moments_body()
	var sounds: SoundsScript = feel.sounds()
	var tag: int = _tag_of(body, &"dash")
	var pulse: int = _tag_of(body, &"pulse")
	check(tag != 0 and pulse != 0, "its staff's dash and its on-wall pulse")
	fx.spells.set(&"cue_tag", tag)
	fx.bus.carrier_shown.emit(body.id, &"dash", body.global_position, Vector2.RIGHT, 80.0, Color.WHITE, 0)
	check(sounds.is_held(body.id, &"swish"), "its staff's move cue holds the swish as the dash sets off")
	fx.spells.set(&"cue_tag", SpellTag.make(fx.players[0].id, 0, 0, 0))
	fx.bus.carrier_shown.emit(fx.players[0].id, &"dash", Vector2.ZERO, Vector2.RIGHT, 80.0, Color.WHITE, 0)
	check(not sounds.is_held(fx.players[0].id, &"swish"), "a dash of another staff is the card's alone")
	fx.spells.set(&"cue_tag", tag)
	body.position = Vector2(40.0, 0.0)
	feel.step(0.05)
	check(sounds.held_at(body.id, &"swish").is_equal_approx(body.global_position), "it goes with the body")
	fx.bus.carrier_ended.emit(body.id, &"dash", body.global_position, Vector2.RIGHT, 8.0, Color.WHITE, 0)
	check(not sounds.is_held(body.id, &"swish"), "it lands: the swish is let go")
	# Then its `on wall` pulse shows itself: a carrier of the same staff that sends no end.
	fx.spells.set(&"cue_tag", pulse)
	fx.bus.carrier_shown.emit(body.id, &"pulse", body.global_position, Vector2.RIGHT, 0.0, Color.WHITE, 0)
	fx.spells.set(&"cue_tag", 0)
	check(not sounds.is_held(body.id, &"swish"), "the pulse it sets off at the wall does not swish again")


## The tag of the spell of `body`'s first staff whose carrier card is `card` (0: none).
func _tag_of(body: Actor, card: StringName) -> int:
	for node in 8:
		var tag: int = int(fx.spells.call(&"current_tag", body.id, 0, node))
		var spell: CompiledSpell = fx.spells.call(&"profile", tag) as CompiledSpell
		if spell != null and spell.carrier_card_id == card:
			return tag
	return 0


func test_a_wall_crunches_and_a_cast_thumps() -> void:
	var feel: FeelScript = _world()
	var body: Actor = _moments_body()
	var sounds: SoundsScript = feel.sounds()
	var tag: int = _tag_of(body, &"dash")
	var before: int = sounds.started
	fx.bus.caster_move_finished.emit(body.id, &"dash", Vector2(50, 0), tag, false)
	check_equal(sounds.started, before, "a dash that ends in the open crunches nothing")
	fx.bus.caster_move_finished.emit(body.id, &"dash", Vector2(50, 0), tag, true)
	check_equal(sounds.last, &"crunch", "one a wall stopped plays its staff's wall cue")
	fx.bus.cast_left.emit(body.id, 1)
	check_equal(sounds.last, &"thump", "a cast leaving plays its staff's cast cue")
	before = sounds.started
	fx.bus.cast_left.emit(body.id, 0)
	check_equal(sounds.started, before, "a staff with none plays nothing")


func test_a_body_dies_with_its_own_sound() -> void:
	var feel: FeelScript = _world()
	_know([&"enemy_death", &"splinter"])
	var data: EnemyBase = Fixture.staffed([[&"bolt"]])
	data.death_sound = &"splinter"
	var body: Actor = fx.imp(Vector2.ZERO, data)
	fx.bus.enemy_died.emit(fx.players[0].id, body, body.global_position, -1)
	check_equal(feel.sounds().last, &"splinter", "its death sounds as its data says, in place of the cue's")
	var plain: Actor = fx.imp(Vector2(40, 0), Fixture.staffed([[&"bolt"]]))
	fx.bus.enemy_died.emit(fx.players[0].id, plain, plain.global_position, -1)
	check_equal(feel.sounds().last, &"enemy_death", "another's with the cue's own")


func test_a_boss_enters_with_its_intro_and_a_stray_with_none() -> void:
	var feel: FeelScript = _world()
	_know([&"boss_intro"])
	var started: int = feel.sounds().started
	fx.imp(Vector2(40, 0), Fixture.staffed([[&"bolt"]]))
	check_equal(feel.sounds().started, started, "a stray enters with no sound")
	var data: EnemyBase = Fixture.staffed([[&"bolt"]])
	data.id = &"test_boss"
	data.boss = true
	fx.imp(Vector2.ZERO, data)
	check_equal(feel.sounds().last, &"boss_intro", "a boss enters with the `boss_intro` cue, under its banner (boss plan OB16)")
	check_equal(feel.sounds().started, started + 1, "once")


func test_a_boss_with_an_intro_enters_with_its_cue_only_when_no_intro_plays() -> void:
	# docs/milestones/boss-intro.md, rule 8: the overlay's own sounds are its entrance.
	var feel: FeelScript = _world()
	_know([&"boss_intro"])
	var data: EnemyBase = Fixture.staffed([[&"bolt"]])
	data.id = &"test_boss"
	data.boss = true
	data.boss_intro = BossIntro.new()
	var started: int = feel.sounds().started
	var boss: Actor = fx.imp(Vector2.ZERO, data)
	fx.bus.boss_intro_opened.emit(boss.id, "", "", data.boss_intro, 0, true)
	feel.step(1.0 / 60.0)
	check_equal(feel.sounds().started, started, "its intro opened: no entrance cue under the overlay")
	fx.bus.boss_intro_closed.emit(boss.id)
	feel.step(1.0 / 60.0)
	check_equal(feel.sounds().started, started, "nor as it closes")
	var stray: Actor = fx.imp(Vector2(60, 0), data)
	check_equal(feel.sounds().started, started, "a boss with an intro waits for the frame's end")
	feel.step(1.0 / 60.0)
	check_equal(feel.sounds().last, &"boss_intro", "none opened for it (the rule off, a sandbox spawn): the entrance cue")
	check_equal(feel.sounds().started, started + 1, "once")
	check(stray != null, "the second boss stands")


# --- Phases and music ------------------------------------------------------------------------

## A boss of the test's own: its music (two stacked layers), a phase that burns (a held sound, an
## ignition cue, the music one step up), and a last one at intensity 4 that looks the same.
func _boss() -> Actor:
	_know([&"calm", &"drums", &"choir", &"burning", &"ignite"])
	_cue(&"test_ignite", [] as Array[Dictionary], &"ignite")
	var data: EnemyBase = Fixture.staffed([[&"bolt"]])
	data.id = &"test_boss"
	data.boss = true
	data.music = MusicTrack.new()
	data.music.layers = [&"calm", &"drums", &"choir"] as Array[StringName]
	var burning := EnemyPhase.new()
	burning.health_below = 0.5
	burning.transition = 0.0
	burning.look = PhaseLook.new()
	burning.look.sound = &"burning"
	burning.look.cue = &"test_ignite"
	var last := EnemyPhase.new()
	last.after_seconds = 1000.0
	last.transition = 0.0
	last.intensity = 4
	data.phases = [burning, last] as Array[EnemyPhase]
	return fx.imp(Vector2.ZERO, data)


func _room(music: MusicTrack) -> void:
	var room := RoomBase.new()
	room.id = &"test_room"
	room.music = music
	var rooms: Dictionary = reg.extra.get(&"rooms", {})
	rooms[room.id] = room
	reg.extra[&"rooms"] = rooms
	fx.bus.room_entered.emit(room.id)


func _poll(feel: FeelScript) -> void:
	feel.step(FeelScript.MUSIC_POLL + 0.01)


func test_a_phase_holds_its_sound_and_plays_its_cue_as_it_starts() -> void:
	var feel: FeelScript = _world()
	var body: Actor = _boss()
	var sounds: SoundsScript = feel.sounds()
	_poll(feel)
	check(not sounds.is_held(body.id, &"burning"), "nothing held before its phase")
	var started: int = sounds.started
	body.phases.begin(0)
	_poll(feel)
	check(sounds.is_held(body.id, &"burning"), "its phase's sound is held")
	check_equal(sounds.last, &"ignite", "and its look's cue played as it started")
	check_equal(sounds.started, started + 1, "once")
	_poll(feel)
	check_equal(sounds.started, started + 1, "not again while the phase lasts")
	body.phases.begin(1)
	_poll(feel)
	check(sounds.is_held(body.id, &"burning"), "a phase with no look of its own keeps the last one's sound")
	var id: int = body.id
	body.free()
	feel.step(0.01)
	check(not sounds.is_held(id, &"burning"), "the body gone, it ends")


func test_a_body_first_seen_in_its_phase_burns_with_no_cue() -> void:
	var feel: FeelScript = _world()
	var body: Actor = _boss()
	body.phases.begin(0)
	var started: int = feel.sounds().started
	_poll(feel)
	check(feel.sounds().is_held(body.id, &"burning"), "a body seen already in its phase holds its sound (a snapshot, a late join)")
	check_equal(feel.sounds().started, started, "but its start was not seen: no cue")


func test_the_music_is_the_rooms_until_an_enemy_with_music_lives() -> void:
	var feel: FeelScript = _world()
	_know([&"crypt_air"])
	var room_track := MusicTrack.new()
	room_track.layers = [&"crypt_air"] as Array[StringName]
	_room(room_track)
	_poll(feel)
	var music: MusicScript = feel.music()
	check(music.track() == room_track, "the room's music")
	check(music.stream_of(0) != null, "its layer playing")
	for i in 40:
		feel.step(0.05)
	var body: Actor = _boss()
	_poll(feel)
	check(music.track() == body.data.music, "a living enemy's music overrides the room's")
	check_equal(music.intensity(), 1, "at its first intensity")
	check(music.fading_level() > 0.0, "the room's fades out")
	check(music.is_heard(0) and not music.is_heard(1), "one layer heard")
	body.phases.begin(0)
	_poll(feel)
	check_equal(music.intensity(), 2, "its phase raises it one step")
	check(music.is_heard(0) and music.is_heard(1) and not music.is_heard(2), "stacked: two layers together")
	for i in 40:
		feel.step(0.05)
	check(is_equal_approx(music.level_of(1), 1.0), "faded in over the track's fade")
	body.phases.begin(1)
	_poll(feel)
	check_equal(music.intensity(), 4, "a phase's own intensity")
	check(music.is_heard(2), "past the last layer: all of them")
	body.free()
	_poll(feel)
	check(music.track() == room_track, "it died: the room's music again")


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
	_know([&"a", &"b"])
	var music: MusicScript = own(MusicScript.new()) as MusicScript
	music.registry = reg
	root.add_child(music)
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
