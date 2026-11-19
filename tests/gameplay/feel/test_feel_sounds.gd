extends "res://tests/support/suite.gd"
## Boss plan OB15 and docs/milestones/sound.md, section 5: what Feel decides of its sounds (what
## each held sound is for and when it ends, `held_sounds.gd`; a staff's moments, a death's sound, a
## boss's entrance, a phase's held sound and the music it picks, a cast's carrier sound and infusion hints, a
## cue's duck), heard only. How they play is core/audio's (tests/core/audio). Sound files do not
## exist yet, so a registry of the test's own answers every sound id it knows with a silent stream,
## and knows the test's own cues and rooms; nothing here names a boss of the game.
const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const HeldSoundsScript := preload("res://gameplay/feel/held_sounds.gd")
const AudioScript := preload("res://core/audio/audio.gd")
const MusicScript := preload("res://core/audio/music.gd")
const VoicesScript := preload("res://core/audio/voices.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const CastSoundsScript := preload("res://gameplay/feel/cast_sounds.gd")
const CueSizeScript := preload("res://gameplay/feel/cue_size.gd")
const ActorsScript := preload("res://core/actors/actors.gd")


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


## A world with Feel on the test's registry.
func _world(players: int = 1) -> FeelScript:
	fx = Fixture.new(root, players)
	var feel: FeelScript = fx.with_feel() as FeelScript
	feel.registry = reg
	fx.audio.registry = reg
	return feel


## Feel and its Audio `delta` real seconds on (Audio steps itself in the game).
func _step(feel: FeelScript, delta: float) -> void:
	feel.step(delta)
	fx.audio.step_world(delta)


## The world's one-shot voices (`started`, `last`).
func _voices() -> VoicesScript:
	return fx.audio.voices


# --- The sounds -----------------------------------------------------------------------------

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
	var sounds: HeldSoundsScript = feel.held_sounds()
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
	var sounds: HeldSoundsScript = feel.held_sounds()
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
	_step(feel, 0.05)
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
	var tag: int = _tag_of(body, &"dash")
	var before: int = _voices().started
	fx.bus.caster_move_finished.emit(body.id, &"dash", Vector2(50, 0), tag, false)
	check_equal(_voices().started, before, "a dash that ends in the open crunches nothing")
	fx.bus.caster_move_finished.emit(body.id, &"dash", Vector2(50, 0), tag, true)
	check_equal(_voices().last, &"crunch", "one a wall stopped plays its staff's wall cue")
	fx.bus.cast_left.emit(body.id, 1)
	check_equal(_voices().last, &"thump", "a cast leaving plays its staff's cast cue")
	before = _voices().started
	fx.bus.cast_left.emit(body.id, 0)
	check_equal(_voices().started, before, "a staff with none plays nothing")


func test_a_body_dies_with_its_own_sound() -> void:
	var feel: FeelScript = _world()
	_know([&"enemy_death", &"splinter"])
	var data: EnemyBase = Fixture.staffed([[&"bolt"]])
	data.death_sound = &"splinter"
	var body: Actor = fx.imp(Vector2.ZERO, data)
	fx.bus.enemy_died.emit(fx.players[0].id, body, body.global_position, -1)
	check_equal(_voices().last, &"splinter", "its death sounds as its data says, in place of the cue's")
	var plain: Actor = fx.imp(Vector2(40, 0), Fixture.staffed([[&"bolt"]]))
	fx.bus.enemy_died.emit(fx.players[0].id, plain, plain.global_position, -1)
	check_equal(_voices().last, &"enemy_death", "another's with the cue's own")


func test_a_boss_enters_with_its_intro_and_a_stray_with_none() -> void:
	var feel: FeelScript = _world()
	_know([&"boss_intro"])
	var started: int = _voices().started
	fx.imp(Vector2(40, 0), Fixture.staffed([[&"bolt"]]))
	check_equal(_voices().started, started, "a stray enters with no sound")
	var data: EnemyBase = Fixture.staffed([[&"bolt"]])
	data.id = &"test_boss"
	data.boss = true
	fx.imp(Vector2.ZERO, data)
	check_equal(_voices().last, &"boss_intro", "a boss enters with the `boss_intro` cue, under its banner (boss plan OB16)")
	check_equal(_voices().started, started + 1, "once")


func test_a_boss_with_an_intro_enters_with_its_cue_only_when_no_intro_plays() -> void:
	# docs/milestones/boss-intro.md, rule 8: the overlay's own sounds are its entrance.
	var feel: FeelScript = _world()
	_know([&"boss_intro"])
	var data: EnemyBase = Fixture.staffed([[&"bolt"]])
	data.id = &"test_boss"
	data.boss = true
	data.boss_intro = BossIntro.new()
	var started: int = _voices().started
	var boss: Actor = fx.imp(Vector2.ZERO, data)
	fx.bus.boss_intro_opened.emit(boss.id, "", "", data.boss_intro, 0, true)
	feel.step(1.0 / 60.0)
	check_equal(_voices().started, started, "its intro opened: no entrance cue under the overlay")
	fx.bus.boss_intro_closed.emit(boss.id)
	feel.step(1.0 / 60.0)
	check_equal(_voices().started, started, "nor as it closes")
	var stray: Actor = fx.imp(Vector2(60, 0), data)
	check_equal(_voices().started, started, "a boss with an intro waits for the frame's end")
	feel.step(1.0 / 60.0)
	check_equal(_voices().last, &"boss_intro", "none opened for it (the rule off): the entrance cue")
	check_equal(_voices().started, started + 1, "once")
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
	fx.bus.room_entered.emit(room.id, 0)


func _poll(feel: FeelScript) -> void:
	_step(feel, FeelScript.MUSIC_POLL + 0.01)


func test_a_phase_holds_its_sound_and_plays_its_cue_as_it_starts() -> void:
	var feel: FeelScript = _world()
	var body: Actor = _boss()
	var sounds: HeldSoundsScript = feel.held_sounds()
	_poll(feel)
	check(not sounds.is_held(body.id, &"burning"), "nothing held before its phase")
	var started: int = _voices().started
	body.phases.begin(0)
	_poll(feel)
	check(sounds.is_held(body.id, &"burning"), "its phase's sound is held")
	check_equal(_voices().last, &"ignite", "and its look's cue played as it started")
	check_equal(_voices().started, started + 1, "once")
	_poll(feel)
	check_equal(_voices().started, started + 1, "not again while the phase lasts")
	body.phases.begin(1)
	_poll(feel)
	check(sounds.is_held(body.id, &"burning"), "a phase with no look of its own keeps the last one's sound")
	var id: int = body.id
	body.free()
	_step(feel, 0.01)
	check(not sounds.is_held(id, &"burning"), "the body gone, it ends")


func test_a_body_first_seen_in_its_phase_burns_with_no_cue() -> void:
	var feel: FeelScript = _world()
	var body: Actor = _boss()
	body.phases.begin(0)
	var started: int = _voices().started
	_poll(feel)
	check(feel.held_sounds().is_held(body.id, &"burning"), "a body seen already in its phase holds its sound (a snapshot, a late join)")
	check_equal(_voices().started, started, "but its start was not seen: no cue")


func test_the_music_is_the_rooms_until_an_enemy_with_music_lives() -> void:
	var feel: FeelScript = _world()
	_know([&"crypt_air"])
	var room_track := MusicTrack.new()
	room_track.layers = [&"crypt_air"] as Array[StringName]
	_room(room_track)
	_poll(feel)
	var music: MusicScript = fx.audio.music
	check(music.track() == room_track, "the room's music")
	check(music.stream_of(0) != null, "its layer playing")
	for i in 40:
		_step(feel, 0.05)
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
		_step(feel, 0.05)
	check(is_equal_approx(music.level_of(1), 1.0), "faded in over the track's fade")
	body.phases.begin(1)
	_poll(feel)
	check_equal(music.intensity(), 4, "a phase's own intensity")
	check(music.is_heard(2), "past the last layer: all of them")
	body.free()
	_poll(feel)
	check(music.track() == room_track, "it died: the room's music again")


# --- What each held sound is for (held_sounds.gd) -------------------------------------------------

## Feel's held sounds on an Audio of their own (no world): `spells` answers whether a staff winds up.
func _held() -> HeldSoundsScript:
	var audio: AudioScript = own(AudioScript.new()) as AudioScript
	audio.registry = reg
	root.add_child(audio)
	var held := HeldSoundsScript.new()
	held.audio = audio
	return held


func test_a_held_sound_ends_by_its_kind_and_is_one_a_caster_and_id() -> void:
	var held: HeldSoundsScript = _held()
	_know([&"swish", &"roar", &"scrape", &"hum"])
	var winding: Winding = own(Winding.new()) as Winding
	held.spells = winding
	held.hold(&"swish", HeldSoundsScript.Until.CARRIER, 3, 77, null, Vector2.ZERO, 4.0)
	held.end_carrier(3, 76)
	check(held.is_held(3, &"swish"), "another carrier's end lets nothing go")
	held.end_carrier(4, 77)
	check(held.is_held(3, &"swish"), "nor another caster's")
	held.end_carrier(3, 77)
	check(not held.is_held(3, &"swish"), "its own carrier's end lets it go")
	held.hold(&"roar", HeldSoundsScript.Until.PHASE, 4, 1, null, Vector2.ZERO, INF)
	var first: int = held.audio.held.held_count
	held.hold(&"roar", HeldSoundsScript.Until.PHASE, 4, 2, null, Vector2.ZERO, INF)
	check_equal(held.audio.held.held_count, first, "the same caster's same sound is taken over, not doubled")
	held.hold(&"swish", HeldSoundsScript.Until.CARRIER, 4, 9, null, Vector2.ZERO, 3.0)
	check_equal(held.held_of(4, HeldSoundsScript.Until.PHASE), &"roar", "its phase's sound")
	held.release(4, HeldSoundsScript.Until.PHASE)
	check(not held.is_held(4, &"roar") and held.is_held(4, &"swish"), "letting go of a phase's lets go of that kind only")
	held.hold(&"scrape", HeldSoundsScript.Until.WIND, 2, 0, null, Vector2.ZERO, 10.0)
	held.step()
	check(held.is_held(2, &"scrape"), "held while its staff winds up")
	winding.on = false
	held.step()
	check(not held.is_held(2, &"scrape"), "the wind-up it lasts for is over")
	check_equal(held.hold(&"nothing", HeldSoundsScript.Until.SECONDS, 4, 0, null, Vector2.ZERO, 1.0), 0, "a sound with no file holds nothing")
	held.audio.clear_world()
	held.step()
	check_equal(held.count, 0, "Audio's world cleared: every entry dropped")


func test_more_held_sounds_than_slots_stay_within_them() -> void:
	var held: HeldSoundsScript = _held()
	for i in HeldSoundsScript.SLOTS + 4:
		_know([StringName("loop_%d" % i)])
		held.hold(StringName("loop_%d" % i), HeldSoundsScript.Until.SECONDS, i, 0, null, Vector2.ZERO, 1.0 + float(i))
	check(held.count <= HeldSoundsScript.SLOTS, "at most SLOTS entries (%d)" % held.count)
	check_equal(held.audio.held.held_count, HeldSoundsScript.SLOTS, "and Audio's slots full")
	check(held.is_held(HeldSoundsScript.SLOTS + 3, StringName("loop_%d" % (HeldSoundsScript.SLOTS + 3))), "the newest is held")


# --- The cast sound and a cue's duck --------------------------------------------------------------

## The voice that last started `id` (-1: none).
func _voice_of(id: StringName) -> int:
	var ids: Array = fx.audio.voices.get(&"_voice_id")
	var from: PackedFloat64Array = fx.audio.voices.get(&"_from")
	var found: int = -1
	for i in fx.audio.voices.count:
		if ids[i] == id and (found < 0 or from[i] >= from[found]):
			found = i
	return found


## An enemy whose one staff casts `cards` at once (no wind-up), so a cast leaves as it is pressed.
func _quick_enemy(cards: Array) -> Actor:
	var data: EnemyBase = Fixture.staffed([cards])
	data.staffs[0].staff.wind_up = 0.0
	return fx.imp(Vector2(40, 0), data)


func test_a_cast_sounds_its_carrier_with_its_infusions_hints_over_it() -> void:
	_world()
	_know([&"bolt_cast", &"fire_hint", &"frost_hint", &"cast"])
	var wizard: Actor = fx.wizard(1, Vector2.ZERO, null, null, [[&"fire", &"frost", &"bolt"], [], [], []])
	var before: int = _voices().started
	fx.bus.staff_cast.emit(1, 0, Vector2(30, 10), Vector2.RIGHT)
	check_equal(_voices().started, before, "`staff_cast` alone sounds nothing: the cast leaving does")
	fx.spells.call(&"cast_staff", wizard.id, 0, Vector2(30, 10), Vector2.RIGHT, 1000.0)
	check_equal(_voices().started, before + 3, "the bolt's own sound and its two infusions' hints")
	check_equal(_voices().voices_of(&"bolt_cast"), 1, "the bolt's own cast sound")
	check_equal(_voices().voices_of(&"fire_hint"), 1, "fire's hint over it")
	check_equal(_voices().voices_of(&"frost_hint"), 1, "and frost's")
	check_equal(_voices().voices_of(&"cast"), 0, "not the shared cast")
	var bolt: AudioStreamPlayer2D = _voices().player(_voice_of(&"bolt_cast")) as AudioStreamPlayer2D
	var hint: AudioStreamPlayer2D = _voices().player(_voice_of(&"fire_hint")) as AudioStreamPlayer2D
	check_equal(bolt.volume_db, 0.0, "a wizard's cast at its own level")
	check_equal(hint.volume_db, CastSoundsScript.HINT_VOLUME, "a hint under it")


func test_an_enemys_cast_sounds_quieter_and_a_props_not_at_all() -> void:
	_world()
	_know([&"bolt_cast"])
	var body: Actor = _quick_enemy([&"bolt"])
	fx.spells.call(&"cast_staff", body.id, 0, body.global_position, Vector2.RIGHT, 1000.0)
	check_equal(_voices().voices_of(&"bolt_cast"), 1, "an enemy's cast sounds its carrier")
	var voice: AudioStreamPlayer2D = _voices().player(_voice_of(&"bolt_cast")) as AudioStreamPlayer2D
	check_equal(voice.volume_db, FeelScript.ENEMY_CAST_VOLUME, "quieter than a wizard's")
	# A prop (the world's: an actor with no controller) casting a bolt plays no carrier sound.
	var prop: int = fx.actors.open(ActorsScript.TEAM_WORLD, 0)
	var staff := StaffBase.new()
	staff.slots = 1
	fx.spells.call(&"open_caster", prop)
	fx.spells.call(&"install_staff", prop, 0, fx.spells.call(&"compile_staff", [&"bolt"] as Array[StringName], staff))
	var before: int = _voices().started
	var paid: float = fx.spells.call(&"cast_staff", prop, 0, Vector2(80, 0), Vector2.RIGHT, 1000.0)
	check(paid >= 0.0, "the prop's bolt left (%s)" % paid)
	check_equal(_voices().started, before, "a prop's cast is its states' moments: no carrier sound")


func test_a_staffs_cue_with_no_sound_of_its_own_plays_over_the_casts_sounds() -> void:
	_world()
	_know([&"bolt_cast"])
	_cue(&"test_jet", [] as Array[Dictionary])
	var data: EnemyBase = Fixture.staffed([[&"bolt"]])
	data.staffs[0].staff.wind_up = 0.0
	data.staffs[0].staff.cast_cue = &"test_jet"
	var body: Actor = fx.imp(Vector2(40, 0), data)
	fx.spells.call(&"cast_staff", body.id, 0, body.global_position, Vector2.RIGHT, 1000.0)
	check_equal(_voices().voices_of(&"bolt_cast"), 1, "a look of its own (a spitter's jet) does not silence the cast (review finding)")


func test_a_pours_hints_wait_until_the_last_have_rung_out() -> void:
	var sounds: CastSoundsScript = CastSoundsScript.new()
	sounds.registry = reg
	sounds.audio = AudioScript.new()
	sounds.audio.registry = reg
	root.add_child(sounds.audio)
	_know([&"spray_cast", &"fire_hint"])
	var arena_cast := CompiledCast.new()
	arena_cast.carrier_cards = [&"spray"] as Array[StringName]
	arena_cast.infusion_cards = [&"fire"] as Array[StringName]
	check_equal(sounds.play(arena_cast, Vector2.ZERO, 0.0, 3, 10.0), 2, "the first pour: the spray and its hint")
	check_equal(sounds.play(arena_cast, Vector2.ZERO, 0.0, 3, 10.15), 1, "the next pour of the same staff: the spray alone (review finding: the hints held every voice)")
	check_equal(sounds.play(arena_cast, Vector2.ZERO, 0.0, 4, 10.15), 2, "another staff's cast has its own")
	check_equal(sounds.play(arena_cast, Vector2.ZERO, 0.0, 3, 10.0 + CastSoundsScript.HINT_EVERY), 2, "once rung out, its hint again")
	check_equal(sounds.play(arena_cast, Vector2.ZERO, 0.0, 3, 0.0), 2, "a clock that started again holds nothing back")
	sounds.audio.free()


func test_a_carrier_card_with_no_sound_of_its_own_sounds_the_shared_cast() -> void:
	_world()
	var sounds: CastSoundsScript = CastSoundsScript.new()
	sounds.registry = reg
	check_equal(sounds.carrier_sound(&"bolt"), &"bolt_cast", "a carrier's own")
	var plain := CarrierCard.new()
	plain.id = &"test_plain"
	reg.extra[&"spells"] = {&"test_plain": plain}
	sounds.registry = reg
	check_equal(sounds.carrier_sound(&"test_plain"), CastSoundsScript.FALLBACK, "one that names none: the shared cast")
	check_equal(sounds.carrier_sound(&""), CastSoundsScript.FALLBACK, "a cast of no carrier card: the shared cast")
	check_equal(sounds.hint_sound(&"fire"), &"fire_hint", "an infusion's hint")
	check_equal(sounds.hint_sound(&"bigger"), &"", "a modifier has none")


func test_a_cast_of_three_alike_sounds_once() -> void:
	_world()
	_know([&"bolt_cast", &"fire_hint"])
	var wizard: Actor = fx.wizard(1, Vector2.ZERO, null, null, [[&"triple", &"fire", &"bolt"], [], [], []])
	var before: int = _voices().started
	fx.spells.call(&"cast_staff", wizard.id, 0, Vector2.ZERO, Vector2.RIGHT, 1000.0)
	check_equal(_voices().started, before + 2, "three fire bolts are one bolt's sound and one hint")


func test_a_cue_played_bigger_than_it_is_made_sounds_deeper_and_louder() -> void:
	var feel: FeelScript = _world()
	_know([&"boom"])
	var boom: CueBase = _cue(&"test_boom", [] as Array[Dictionary], &"boom")
	boom.size_ref = 40.0
	feel.play_cue(&"test_boom", -1, Vector2.ZERO, Vector2.ZERO, 40.0)
	var voice: AudioStreamPlayer2D = _voices().player(_voice_of(&"boom")) as AudioStreamPlayer2D
	check_equal(voice.pitch_scale, 1.0, "at its own size, as made")
	check_equal(voice.volume_db, 0.0, "at its own level")
	fx.audio.clear_world()
	feel.play_cue(&"test_boom", -1, Vector2.ZERO, Vector2.ZERO, 80.0)
	voice = _voices().player(_voice_of(&"boom")) as AudioStreamPlayer2D
	check(voice.pitch_scale < 0.9, "twice as big: deeper (%s)" % voice.pitch_scale)
	check(is_equal_approx(voice.volume_db, CueSizeScript.DB_PER_DOUBLING), "and a doubling louder (%s dB)" % voice.volume_db)
	fx.audio.clear_world()
	feel.play_cue(&"test_boom", -1, Vector2.ZERO, Vector2.ZERO, 20.0)
	voice = _voices().player(_voice_of(&"boom")) as AudioStreamPlayer2D
	check(voice.pitch_scale > 1.1 and voice.volume_db < 0.0, "half as big: higher and softer")
	fx.audio.clear_world()
	boom.size_ref = 0.0
	feel.play_cue(&"test_boom", -1, Vector2.ZERO, Vector2.ZERO, 80.0)
	voice = _voices().player(_voice_of(&"boom")) as AudioStreamPlayer2D
	check(voice.pitch_scale == 1.0 and voice.volume_db == 0.0, "a cue with no size of its own plays as made at any size")


func test_a_cue_with_a_duck_lowers_the_music_while_its_sound_plays() -> void:
	var feel: FeelScript = _world()
	fx.audio.buses.reset()
	_know([&"quiet"])
	_know_long(&"slam")
	var slam: CueBase = _cue(&"test_slam", [] as Array[Dictionary], &"slam")
	slam.duck = -6.0
	_cue(&"test_quiet", [] as Array[Dictionary], &"quiet")
	feel.play_cue(&"test_quiet", -1, Vector2.ZERO)
	fx.audio.step(0.1)
	check_equal(fx.audio.buses.ducked(), 0.0, "a cue with no duck leaves the music be")
	feel.play_cue(&"test_slam", -1, Vector2.ZERO)
	fx.audio.step(0.05)
	check(is_equal_approx(fx.audio.buses.ducked(), -6.0), "its duck comes in over 0.05 s (%s)" % fx.audio.buses.ducked())
	fx.audio.step(0.5)
	check(is_equal_approx(fx.audio.buses.ducked(), -6.0), "held while its second-long sound plays")
	for i in 50:
		fx.audio.step(0.02)
	check_equal(fx.audio.buses.ducked(), 0.0, "and lets up once its sound is over")
	var bad := CueBase.new()
	bad.id = &"bad"
	bad.duck = 3.0
	check("\n".join(bad.problems()).contains("duck"), "a duck above 0 is a problem")
	fx.audio.buses.reset()

