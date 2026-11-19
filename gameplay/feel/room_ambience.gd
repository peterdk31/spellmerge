extends Node
## Feel's room sound (docs/milestones/atmosphere.md, D; docs/milestones/sound.md, section 5): which
## `Ambience` plays (the room in play's, `RoomBase.ambience`) and when its accents come, heard only
## (nothing in the game reads it). It hears the room itself (`room_entered`, the room read from the
## registry, as the cover does) and leaving for the main menu (`main_menu_requested`: no room follows,
## so it fades to silence); Feel only makes it and steps it once a frame by real time. Audio plays it:
## the bed (`Audio.play_bed`: its layers, the fades in and out across a room change, the changes
## inside a fade) and each accent (`Audio.play_accent`), all on Audio's `Ambience` bus, whose volume
## is the "Ambience volume" setting.
##
## **Accents:** each of its ambience's accents is heard after a gap of `gap_min` to `gap_max`
## seconds (the first as long after its room came), one of its sounds at random, from up to its
## `wide` px left or right of the middle of the picture, its volume and pitch strayed within their
## spreads, as loud as the bed's fade is (Audio's `ambience.level()`). The dice are its own (`rng`)
## and the clock is its own: view only, never the game's. An accent whose sound has no file is silent
## and still comes round again.
##
## Its timing stands still with the tree as Audio's world does (the pause menu, a boss's intro): it is
## Feel's child and steps with Feel.

const EventsScript := preload("res://core/events/events.gd")
const AudioScript := preload("res://core/audio/audio.gd")

## Where the rooms are in the registry.
const ROOM_FOLDER: StringName = &"rooms"

## The bus it hears rooms on (Feel's; null in a test that hands it ambiences itself), set before it
## enters the tree, the registry the rooms are asked of, and the Audio service it plays on.
var events: EventsScript = null
var registry: Node = null
var audio: AudioScript = null
## Its own dice (view only; a test seeds it).
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Accents played, and the last one's sound id (for tests).
var accents_played: int = 0
var last_accent: StringName = &""

## Feel's real seconds since it was made, and when each accent is next heard.
var _clock: float = 0.0
var _next_at: PackedFloat64Array = PackedFloat64Array()
var _ambience: Ambience = null


func _ready() -> void:
	rng.randomize()
	_next_at.resize(Ambience.ACCENTS_MOST)
	_next_at.fill(INF)
	if events != null and not events.room_entered.is_connected(_on_room_entered):
		events.room_entered.connect(_on_room_entered)
		events.main_menu_requested.connect(_on_main_menu_requested)


## The world's room in play: a biome's first room's for now (connected biomes CB3; each room's own
## sound is CB12's).
func _on_room_entered(room_id: StringName, number: int) -> void:
	if number != EventsScript.FIRST_ROOM:
		return
	var room: RoomBase = registry.call(&"get_resource", ROOM_FOLDER, room_id) as RoomBase if registry != null else null
	use(room.ambience if room != null else null)


## Back to the main menu: no room follows, so the ambience fades out under the menu.
func _on_main_menu_requested(_player: int) -> void:
	use(null)


## The room in play's ambience is `ambience` (null: silence): Audio's bed takes it (a new one comes
## in, the same one plays on), and its accents are timed afresh from now.
func use(ambience: Ambience) -> void:
	if ambience == _ambience:
		return
	_ambience = ambience
	if audio != null:
		audio.play_bed(ambience)
	_schedule()


## Once a frame, `delta` real seconds on, `middle` the middle of the picture (INF: none, the
## origin): each accent due is heard.
func step(delta: float, middle: Vector2 = Vector2.INF) -> void:
	_clock += delta
	if _ambience == null:
		return
	for i in mini(_ambience.accents.size(), Ambience.ACCENTS_MOST):
		if _clock >= _next_at[i]:
			_play_accent(_ambience.accents[i], middle)
			_next_at[i] = _clock + _gap(_ambience.accents[i])


## Silence at once (tests; in play the next room's ambience, or none, takes over by fading).
func stop() -> void:
	_ambience = null
	_next_at.fill(INF)
	if audio != null:
		audio.stop_bed()


## The ambience it chose (null: none).
func ambience() -> Ambience:
	return _ambience


## Seconds until accent `accent` of the ambience playing is next heard (INF: never).
func accent_in(accent: int) -> float:
	return _next_at[accent] - _clock if accent >= 0 and accent < Ambience.ACCENTS_MOST else INF


func _schedule() -> void:
	_next_at.fill(INF)
	if _ambience == null:
		return
	for i in mini(_ambience.accents.size(), Ambience.ACCENTS_MOST):
		_next_at[i] = _clock + _gap(_ambience.accents[i])


func _play_accent(accent: AmbienceAccent, middle: Vector2) -> void:
	if accent == null or accent.sounds.is_empty():
		return
	var id: StringName = accent.sounds[rng.randi_range(0, accent.sounds.size() - 1)]
	if audio == null or audio.sound(id) == null:
		return
	var volume: float = _ambience.volume + accent.volume + rng.randf_range(-accent.volume_spread, accent.volume_spread) + linear_to_db(audio.ambience.level())
	var pitch: float = 1.0 + rng.randf_range(-accent.pitch_spread, accent.pitch_spread)
	var from: Vector2 = middle if middle.is_finite() else Vector2.ZERO
	audio.play_accent(id, from + Vector2(rng.randf_range(-accent.wide, accent.wide), 0.0), volume, pitch)
	accents_played += 1
	last_accent = id


func _gap(accent: AmbienceAccent) -> float:
	if accent == null:
		return INF
	return rng.randf_range(maxf(accent.gap_min, Ambience.GAP_LEAST), maxf(accent.gap_max, accent.gap_min))
