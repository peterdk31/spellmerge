extends Control
## The sound room (docs/milestones/sound.md, section 7; AU4): every sound id the game names, read from
## its data (`sound_names.gd`), beside every id that has a file (`Registry.sound_ids`), each a row
## played through the game's own Audio service (core/audio): a check of the real path, not a second
## synth. Run it with a window:
##
##     godot --path . res://tests/sound_room/sound_room.tscn
##
## **Rows.** An id named with no file is red (missing), and so is a file that nothing names (unnamed).
## A row plays its sound as the game would, on its bus: a one-shot through `Audio.play` (each press a
## new variant: a randomizer picks one), a menu's sound through `Audio.play_ui` (the UI bus), a held sound through `Audio.hold` until pressed again, a
## room's bed layer by playing its whole bed (`Audio.play_bed`, its layers at their levels) until
## pressed again, an accent through `Audio.play_accent` at its bed's and its own level, and a music
## layer by playing its track up to that layer. The fixtures (`fixtures/`, baked by `tools/sound_fixtures.py`: AU2's three
## samples, a held loop and a two-layer track, `room_track.tres`) are rows of their own, so the room
## is heard working before any game sound exists.
##
## **The side.** A slider a bus (Music, SFX, Ambience, UI) for its volume (`Audio.set_volume`, as the
## settings' events do; nothing is saved), a duck button (`Audio.duck`, the music lowered by DUCK_DB
## for DUCK_SECONDS), Stop all (`Audio.silence`), and every music track (the data's and the
## fixtures') with a slider for its intensity (0: silence; `Audio.play_track`, Audio's own
## `music.gd`).
##
## Tests hand it `audio`, `registry` and `fixtures` before adding it; otherwise it makes an Audio of
## its own on the game's registry and the fixtures' (`room_sounds.gd`), and leaves the autoload be.

const AudioScript := preload("res://core/audio/audio.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const PRESET: FeelPresetScript = preload("res://gameplay/feel/presets/punchy.tres")
const SoundNames := preload("res://tests/sound_room/sound_names.gd")
const RoomSounds := preload("res://tests/sound_room/room_sounds.gd")
const FIXTURE_TRACK: MusicTrack = preload("res://tests/sound_room/room_track.tres")

## The fixtures' folder (an audio root of its own) and a content root with nothing in it.
const FIXTURES: String = "res://tests/sound_room/fixtures"
const NO_CONTENT: String = "res://tests/sound_room/no_content"
## How far and how long the duck button lowers the music.
const DUCK_DB: float = -12.0
const DUCK_SECONDS: float = 1.5
## The buses with a volume slider.
const VOLUME_BUSES: Array[StringName] = [AudioScript.BUS_MUSIC, AudioScript.BUS_SFX, AudioScript.BUS_AMBIENCE, AudioScript.BUS_UI]
const RED: Color = Color(1.0, 0.35, 0.35)
const FIXTURE_TINT: Color = Color(0.6, 0.85, 1.0)

## What a row is: named with a file, named with none, a file nothing names, or a fixture.
enum State { HEARD, MISSING, UNNAMED, FIXTURE }


## One id's row.
class Row:
	var id: StringName = &""
	var kind: SoundNames.Kind = SoundNames.Kind.ONE_SHOT
	var state: State = State.HEARD
	var where: String = ""
	## A held sound's handle while it loops (0: none).
	var handle: int = 0
	var button: Button = null


## The services. Only tests set these, before adding the node.
var audio: AudioScript = null
var registry: Node = null
var fixtures: Node = null

## The rows (named ids in id order, then unnamed files, then the fixtures), by id too.
var rows: Array[Row] = []
var row_of: Dictionary[StringName, Row] = {}
## Every music track (the data's, then the fixtures'), its owner, and its intensity now (0: off).
var tracks: Array[MusicTrack] = []
var track_owners: PackedStringArray = PackedStringArray()
var track_intensity: PackedInt32Array = PackedInt32Array()

var _names: SoundNames = null
var _made_fixtures: bool = false
var _sliders: Array[HSlider] = []


func _ready() -> void:
	if registry == null:
		registry = get_node_or_null("/root/Registry")
	if fixtures == null:
		fixtures = RegistryScript.new()
		fixtures.call(&"scan", NO_CONTENT, FIXTURES)
		_made_fixtures = true
	if audio == null:
		var sounds := RoomSounds.new()
		sounds.name = "RoomSounds"
		sounds.sources = [fixtures, registry] as Array[Node]
		add_child(sounds)
		audio = AudioScript.new()
		audio.name = "RoomAudio"
		audio.registry = sounds
		add_child(audio)
	_names = SoundNames.new()
	_names.read(registry, SoundNames.feel_names(PRESET, FeelScript.CAST_SOUND), UiSounds.IDS)
	_list()
	_build()
	print("SOUND ROOM: %d named, %d missing, %d unnamed, %d fixtures" % [_names.kinds.size(), count_of(State.MISSING), count_of(State.UNNAMED), count_of(State.FIXTURE)])


## Freed with the room (not on leaving the tree, so a room moved elsewhere keeps its fixtures).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _made_fixtures and is_instance_valid(fixtures):
		fixtures.free()


## How many rows are in `state`.
func count_of(state: State) -> int:
	var n: int = 0
	for row: Row in rows:
		if row.state == state:
			n += 1
	return n


# --- Playing --------------------------------------------------------------------------------------

## Plays the row `id` as the game would (see the top); a held row's second press lets it go.
func press(id: StringName) -> void:
	var row: Row = row_of.get(id) as Row
	if row == null or row.state == State.MISSING:
		return
	match row.kind:
		SoundNames.Kind.ONE_SHOT:
			audio.play(id)
		SoundNames.Kind.UI:
			audio.play_ui(id)
		SoundNames.Kind.ACCENT:
			audio.play_accent(id, Vector2.ZERO, SoundNames.accent_volume(_names.bed_of(id), id), 1.0)
		SoundNames.Kind.BED:
			var bed: Ambience = _names.bed_of(id)
			audio.play_bed(null if audio.ambience.ambience() == bed else bed)
			for each: Row in rows:
				_label(each)
		SoundNames.Kind.HELD:
			if row.handle != 0 and audio.is_held(row.handle):
				audio.release(row.handle)
				row.handle = 0
			else:
				row.handle = audio.hold(id, null, Vector2.INF, INF, 0.0, AudioScript.BUS_SFX)
			_label(row)
		SoundNames.Kind.MUSIC:
			for i in tracks.size():
				var at: int = tracks[i].layers.find(id)
				if at >= 0:
					set_intensity(i, at + 1)
					return


## Plays track `index` at `intensity` (0: silence), as the game's music does.
func set_intensity(index: int, intensity: int) -> void:
	if index < 0 or index >= tracks.size():
		return
	for i in track_intensity.size():
		if i != index:
			track_intensity[i] = 0
	track_intensity[index] = intensity
	audio.play_track(tracks[index] if intensity > 0 else null, intensity)
	for i in _sliders.size():
		_sliders[i].set_value_no_signal(track_intensity[i])


## Lowers the music by DUCK_DB for DUCK_SECONDS (a cue's `duck`).
func duck() -> void:
	audio.duck(DUCK_DB, DUCK_SECONDS)


## Sets `bus`'s volume to `percent` (as the settings' events do).
func set_bus_volume(bus: StringName, percent: int) -> void:
	audio.set_volume(bus, AudioVolumes.share_of(percent))


## Every sound stops, and every held row and track is off.
func stop_all() -> void:
	audio.silence()
	for row: Row in rows:
		row.handle = 0
		_label(row)
	track_intensity.fill(0)
	for slider: HSlider in _sliders:
		slider.set_value_no_signal(0)


# --- The list -------------------------------------------------------------------------------------

func _list() -> void:
	rows.clear()
	row_of.clear()
	var filed: Array[StringName] = registry.call(&"sound_ids")
	for id: StringName in _names.ids():
		_add(id, _names.kinds[id], State.HEARD if filed.has(id) else State.MISSING, ", ".join(_names.where[id]))
	for id: StringName in filed:
		if not _names.kinds.has(id):
			_add(id, _kind_of(registry, id), State.UNNAMED, "no data names it")
	var fixture_ids: Array[StringName] = fixtures.call(&"sound_ids")
	for id: StringName in fixture_ids:
		var kind: SoundNames.Kind = SoundNames.Kind.MUSIC if FIXTURE_TRACK.layers.has(id) else _kind_of(fixtures, id)
		_add(id, kind, State.FIXTURE, "fixture")
	tracks.assign(_names.tracks)
	track_owners = _names.track_owners.duplicate()
	tracks.append(FIXTURE_TRACK)
	track_owners.append("fixture track")
	track_intensity.resize(tracks.size())
	track_intensity.fill(0)


func _add(id: StringName, kind: SoundNames.Kind, state: State, where: String) -> void:
	if row_of.has(id):
		return
	var row := Row.new()
	row.id = id
	row.kind = kind
	row.state = state
	row.where = where
	rows.append(row)
	row_of[id] = row


## How a file nothing names is played: held when it loops.
static func _kind_of(source: Node, id: StringName) -> SoundNames.Kind:
	var stream: AudioStream = source.call(&"get_sound", id) as AudioStream
	var loops: bool = false
	if stream is AudioStreamOggVorbis:
		loops = (stream as AudioStreamOggVorbis).loop
	elif stream is AudioStreamWAV:
		loops = (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	return SoundNames.Kind.HELD if loops else SoundNames.Kind.ONE_SHOT


# --- The view -------------------------------------------------------------------------------------

const KIND_NAMES: PackedStringArray = ["one-shot", "held", "music", "bed", "accent", "ui"]
const FONT_SIZE: int = 8


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var look := Theme.new()
	look.default_font_size = FONT_SIZE
	theme = look
	var back := ColorRect.new()
	back.color = Color(0.08, 0.08, 0.1)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var split := HBoxContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(split)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)
	var header := Label.new()
	header.text = "Sound room: %d named, %d missing (red), %d files nothing names (red), %d fixtures (blue)" % [_names.kinds.size(), count_of(State.MISSING), count_of(State.UNNAMED), count_of(State.FIXTURE)]
	left.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for row: Row in rows:
		list.add_child(_row_view(row))
	split.add_child(_side())


func _row_view(row: Row) -> Control:
	var line := HBoxContainer.new()
	var button := Button.new()
	button.custom_minimum_size = Vector2(36, 0)
	button.disabled = row.state == State.MISSING
	button.pressed.connect(press.bind(row.id))
	row.button = button
	_label(row)
	line.add_child(button)
	var label := Label.new()
	label.text = "%s  [%s]  %s" % [row.id, KIND_NAMES[row.kind], row.where]
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if row.state == State.MISSING or row.state == State.UNNAMED:
		label.modulate = RED
	elif row.state == State.FIXTURE:
		label.modulate = FIXTURE_TINT
	line.add_child(label)
	return line


func _label(row: Row) -> void:
	if row.button == null:
		return
	match row.kind:
		SoundNames.Kind.HELD:
			row.button.text = "Stop" if row.handle != 0 else "Loop"
		SoundNames.Kind.BED:
			var bed: Ambience = _names.bed_of(row.id)
			row.button.text = "Stop" if bed != null and audio.ambience.ambience() == bed else "Loop"
		_:
			row.button.text = "Play"


func _side() -> Control:
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(180, 0)
	for bus: StringName in VOLUME_BUSES:
		var label := Label.new()
		label.text = "%s volume" % bus
		side.add_child(label)
		var slider := HSlider.new()
		slider.min_value = AmbienceVolume.MIN
		slider.max_value = AmbienceVolume.MAX
		slider.step = AmbienceVolume.STEP
		slider.value = AmbienceVolume.MAX
		slider.value_changed.connect(func(value: float) -> void: set_bus_volume(bus, int(value)))
		side.add_child(slider)
	var duck_button := Button.new()
	duck_button.text = "Duck the music (%d dB, %.1f s)" % [int(DUCK_DB), DUCK_SECONDS]
	duck_button.pressed.connect(duck)
	side.add_child(duck_button)
	var stop_button := Button.new()
	stop_button.text = "Stop all"
	stop_button.pressed.connect(stop_all)
	side.add_child(stop_button)
	for i in tracks.size():
		var label := Label.new()
		label.text = "Music of %s (%d layers): intensity" % [track_owners[i], tracks[i].layers.size()]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		side.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = tracks[i].layers.size()
		slider.step = 1
		slider.tick_count = tracks[i].layers.size() + 1
		slider.ticks_on_borders = true
		slider.value_changed.connect(func(value: float) -> void: set_intensity(i, int(value)))
		side.add_child(slider)
		_sliders.append(slider)
	return side
