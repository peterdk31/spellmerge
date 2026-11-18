extends Node
## The Audio service (autoload `Audio`; docs/milestones/sound.md, section 5): every way the game plays
## a sound, and the only code that makes or drives an `AudioStreamPlayer`. View only: no state, no
## tick, no hash; nothing in the simulation reaches it (tests/core/test_sim_rules.gd names any line
## that does). It knows how to play (voices, caps, held sounds and their fades, music layers, the room's
## bed, buses, volumes, the duck, variants, panning) and nothing of bodies, spells, cues, phases or
## rooms: what plays and when is its callers' (Feel's, gameplay/feel).
##
## **Two lanes.** The world's sounds (one-shots `play`, held sounds `hold`, the music `play_track`,
## the room's bed and accents `play_bed`, `play_accent`) are on players under `World`, a child that
## stands still with the tree (the pause menu, a boss's intro) and goes on after. The **over** lane
## never pauses: `play_over` (a boss intro's cues, on SFX) and the UI's sounds (`ui_sound_requested`,
## on UI). A world voice is an `AudioStreamPlayer2D`, heard from where it happens (`at`; INF: the
## middle of the picture), panned by PAN and quieter off the picture up to HEARD pixels; an over voice
## is a plain `AudioStreamPlayer`. `clear_world` stops the world's one-shots and held sounds at once
## (a new room: what held them is gone).
##
## **Buses** (`default_bus_layout.tres`, named in project.godot): Master > `Music` > `MusicDuck`,
## `SFX`, `Ambience` and `UI`; BUS_* are their names, so no other script writes one. The music is on
## `MusicDuck`, whose volume is the duck's alone (`duck`), under `Music`, whose volume is the
## setting's. **Volumes** (`AudioVolumes`, core/settings): it hears `music_volume_changed`,
## `sound_volume_changed`, `ambience_volume_changed` and `ui_volume_changed` and eases its bus to the
## setting's share (`buses.gd`). **The duck:** `duck(decibels, seconds)`, the most asked for wins,
## a ramp both ways. **UI sounds:** UI_VOICES voices, at most one play per id a frame. **Variants:** a
## sound may be an `AudioStreamRandomizer` (`<id>.tres`), which picks a variant and jitters it on every
## play by itself; a voice is held for its longest variant (`AudioLength.of`).
##
## Sounds are asked of `registry` by id (`get_sound`; a missing one is silent). Only `audible` starts
## a player (`hears_audio()`: not on the audio driver with no device, every headless run, where a loop
## still playing as the run quits is left with the engine's audio thread). Every player is made once
## in `_ready`: nothing is allocated per play. It steps itself once a frame (`_process`), the world
## only while it is not paused.
##
## Reached by Feel and the sound room, which are handed it as they are handed the registry (tests use
## their own); the HUD never calls it, it sends `ui_sound_requested`.
##
##     audio.play(&"hit", where)
##     var handle: int = audio.hold(&"broom_burning", body, body.global_position, INF)
##     audio.release(handle)

const VoicesScript := preload("res://core/audio/voices.gd")
const HeldScript := preload("res://core/audio/held.gd")
const MusicScript := preload("res://core/audio/music.gd")
const AmbienceScript := preload("res://core/audio/ambience.gd")
const BusesScript := preload("res://core/audio/buses.gd")
const EventsScript := preload("res://core/events/events.gd")

## The buses (default_bus_layout.tres).
const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_MUSIC_DUCK: StringName = &"MusicDuck"
const BUS_SFX: StringName = &"SFX"
const BUS_AMBIENCE: StringName = &"Ambience"
const BUS_UI: StringName = &"UI"
## The world's one-shot voices, and how many may play one sound id at once.
const VOICES: int = 8
const PER_SOUND: int = 3
## The over lane's voices, and the UI's.
const OVER_VOICES: int = 4
const UI_VOICES: int = 4
## Pixels from the middle of the picture a world sound is heard to, how steeply it falls off, and how
## far it pans (each world voice's `panning_strength`; the project's default of 0.5 stays under it):
## a sound at the screen's edge is mostly, never wholly, on one side. The owner tunes PAN by ear.
const HEARD: float = 1600.0
const ATTENUATION: float = 0.7
const PAN: float = 1.0
## Godot's audio driver with no device (headless runs').
const DUMMY_AUDIO_DRIVER: String = "Dummy"

## The services. Only tests set these, before adding the node; otherwise the autoloads are used.
var registry: Node = null
var events: EventsScript = null
## Whether its players are started (`hears_audio()`, read in `_ready`; a test may set it after).
var audible: bool = true:
	set(value):
		audible = value
		for part: Node in [voices, held, music, ambience, over, ui]:
			if part != null:
				part.set(&"audible", value)

## Its parts (read by tests and the sound room; play through the functions below).
var voices: VoicesScript = null
var held: HeldScript = null
var music: MusicScript = null
var ambience: AmbienceScript = null
var over: VoicesScript = null
var ui: VoicesScript = null
var buses: BusesScript = null

var _world: Node = null
## The ids the UI played this frame (at most one play an id a frame), the first `_ui_count`.
var _ui_played: Array[StringName] = []
var _ui_count: int = 0


func _ready() -> void:
	if _world != null:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	if registry == null:
		registry = get_node_or_null("/root/Registry")
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	var hears: bool = hears_audio()
	_world = Node.new()
	_world.name = "World"
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_world)
	voices = _voices(VOICES, PER_SOUND, true, BUS_SFX, "Voices", _world)
	held = HeldScript.new()
	held.name = "Held"
	held.heard = HEARD
	held.attenuation = ATTENUATION
	held.pan = PAN
	_world.add_child(held)
	music = MusicScript.new()
	music.name = "Music"
	music.bus = BUS_MUSIC_DUCK
	music.registry = registry
	_world.add_child(music)
	ambience = AmbienceScript.new()
	ambience.name = "Ambience"
	ambience.bus = BUS_AMBIENCE
	ambience.heard = HEARD
	ambience.attenuation = ATTENUATION
	ambience.pan = PAN
	ambience.registry = registry
	_world.add_child(ambience)
	var lane := Node.new()
	lane.name = "Over"
	lane.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(lane)
	over = _voices(OVER_VOICES, OVER_VOICES, false, BUS_SFX, "OverVoices", lane)
	ui = _voices(UI_VOICES, UI_VOICES, false, BUS_UI, "UiVoices", lane)
	_ui_played.resize(UI_VOICES)
	buses = BusesScript.new([BUS_MUSIC, BUS_SFX, BUS_AMBIENCE, BUS_UI] as Array[StringName], BUS_MUSIC_DUCK)
	audible = hears
	if events != null:
		events.music_volume_changed.connect(_on_volume.bind(BUS_MUSIC))
		events.sound_volume_changed.connect(_on_volume.bind(BUS_SFX))
		events.ambience_volume_changed.connect(_on_volume.bind(BUS_AMBIENCE))
		events.ui_volume_changed.connect(_on_volume.bind(BUS_UI))
		events.ui_sound_requested.connect(play_ui)


func _voices(count: int, per_sound: int, positional: bool, bus: StringName, label: String, parent: Node) -> VoicesScript:
	var made := VoicesScript.new()
	made.name = label
	made.count = count
	made.per_sound = per_sound
	made.positional = positional
	made.bus = bus
	made.heard = HEARD
	made.attenuation = ATTENUATION
	made.pan = PAN
	parent.add_child(made)
	return made


func _process(delta: float) -> void:
	step(delta)


## `delta` real seconds on: the over lane, the buses and the duck always; the world while it is not
## paused (tests step it by hand).
func step(delta: float) -> void:
	_ui_count = 0
	over.step(delta)
	ui.step(delta)
	buses.step(delta)
	if _world.can_process():
		step_world(delta)


## The world's players `delta` real seconds on: voices, held sounds, the music and the room's bed.
func step_world(delta: float) -> void:
	voices.step(delta)
	held.step(delta)
	music.step(delta)
	ambience.step(delta)


## Whether this machine can hear the players: not on Godot's audio driver with no device
## (`DUMMY_AUDIO_DRIVER`, every headless run).
static func hears_audio() -> bool:
	return AudioServer.get_driver_name() != DUMMY_AUDIO_DRIVER


## The sound `id` (null: none, or no registry).
func sound(id: StringName) -> AudioStream:
	if registry == null or id == &"":
		return null
	return registry.call(&"get_sound", id) as AudioStream


## How long the sound `id` plays (its longest variant; 0 for none).
func length_of(id: StringName) -> float:
	return AudioLength.of(sound(id))


# --- The world ------------------------------------------------------------------------------------

## Plays the sound `id` at `at` (INF: the middle of the picture), `volume` decibels on top of its
## own, on `bus`; the voice used, or -1 for none (no such sound).
func play(id: StringName, at: Vector2 = Vector2.INF, volume: float = 0.0, bus: StringName = BUS_SFX) -> int:
	var stream: AudioStream = sound(id)
	if stream == null:
		return -1
	return voices.play(id, stream, at if at.is_finite() else _middle(), volume, bus)


## Stops the world's one-shot on `voice`.
func stop(voice: int) -> void:
	voices.stop(voice)


## Holds the sound `id` for `seconds` (INF: until let go), following `follow` (null: it stays at
## `at`; INF there: the middle of the picture), `volume` decibels on top of its own, on `bus`; `take`
## is an earlier handle it takes the place of (0: none), going on with no restart when the sound is
## the same. A handle for `release`, or 0 for none (no such sound, no seconds).
func hold(id: StringName, follow: Node2D, at: Vector2, seconds: float, volume: float = 0.0, bus: StringName = BUS_SFX, take: int = 0) -> int:
	return held.hold(sound(id), follow, at if at.is_finite() else _middle(), seconds, volume, bus, take)


## Lets go of the held sound `handle` (it fades out), or of all of them.
func release(handle: int) -> void:
	held.release(handle)


func release_all() -> void:
	held.release_all()


## Whether the held sound `handle` is held and not let go; whether it still has its slot (held or
## fading out); where it is now (INF: none).
func is_held(handle: int) -> bool:
	return held.is_held(handle)


func has_held(handle: int) -> bool:
	return held.has(handle)


func held_at(handle: int) -> Vector2:
	return held.held_at(handle)


## Plays `track` (null: silence) at `intensity` (`music.gd`).
func play_track(track: MusicTrack, intensity: int) -> void:
	music.registry = registry
	music.play(track, intensity)


## The room's bed is `ambience`'s (null: silence; `ambience.gd`).
func play_bed(bed: Ambience) -> void:
	ambience.registry = registry
	ambience.play_bed(bed)


## Plays the sound `id` as an accent of the bed, at `at`, `volume` decibels, at `pitch` its pitch
## scale; the voice used, or -1 for none.
func play_accent(id: StringName, at: Vector2, volume: float, pitch: float) -> int:
	return ambience.play_accent(sound(id), at, volume, pitch)


## The world's one-shots and held sounds stop at once (a new room, a run's end).
func clear_world() -> void:
	voices.clear()
	held.clear()


# --- The over lane --------------------------------------------------------------------------------

## Plays the sound `id` on the over lane (heard while the tree is paused: a boss intro's cues),
## `volume` decibels on top of its own, on `bus`; the voice used, or -1 for none.
func play_over(id: StringName, volume: float = 0.0, bus: StringName = BUS_SFX) -> int:
	var stream: AudioStream = sound(id)
	if stream == null:
		return -1
	return over.play(id, stream, Vector2.ZERO, volume, bus)


## Stops every sound of the over lane (a boss intro closed).
func stop_over() -> void:
	over.clear()


## Plays the UI's sound `id` (`ui_sound_requested`): at most one play of an id a frame; the voice
## used, or -1 for none.
func play_ui(id: StringName) -> int:
	for i in _ui_count:
		if _ui_played[i] == id:
			return -1
	var stream: AudioStream = sound(id)
	if stream == null:
		return -1
	if _ui_count < UI_VOICES:
		_ui_played[_ui_count] = id
		_ui_count += 1
	return ui.play(id, stream, Vector2.ZERO, 0.0, BUS_UI)


# --- The buses ------------------------------------------------------------------------------------

## Lowers the music by `decibels` (below 0) for `seconds` (see the top).
func duck(decibels: float, seconds: float) -> void:
	buses.duck(decibels, seconds)


## The volume setting of `bus` (BUS_MUSIC, BUS_SFX, BUS_AMBIENCE or BUS_UI): `share` of its loudness,
## eased to. The events of the settings come here.
func set_volume(bus: StringName, share: float) -> void:
	buses.set_volume(bus, share)


func _on_volume(percent: int, bus: StringName) -> void:
	set_volume(bus, AudioVolumes.share_of(percent))


## The middle of the picture (where a sound of no place is heard from).
func _middle() -> Vector2:
	var camera: Camera2D = get_viewport().get_camera_2d() if is_inside_tree() else null
	return camera.get_screen_center_position() if camera != null else Vector2.ZERO
