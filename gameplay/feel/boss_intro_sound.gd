extends Node
## The boss intro's own two sounds (docs/milestones/boss-intro.md, rule 8): Feel's, beside its
## other sounds, on a node of its own that plays while the tree is paused (`process_mode` ALWAYS),
## since the world's sounds and the music stand still with the tree for the whole intro, as under
## the pause menu.
##
## It hears `boss_intro_opened` (fresh only: a restored intro is already past its moments) and plays,
## by the HUD's frame (real time, as the overlay's timeline), the intro's `dark_cue` at
## `BossIntro.DARK_AT` and its reveal cue (`reveal_cue_or_shared`: its own, else the shared
## `boss_intro`) at `BossIntro.REVEAL_AT`, each the sound its cue names (`CueBase.sound`; the cue's
## other parts are the world's, which stands still). `boss_intro_closed` stops both. Nothing here names
## a boss: all of it is the intro's data (rule 9). Its own players, made once; it allocates nothing
## while playing.
##
##     var sound := BossIntroSound.new()
##     sound.registry = registry
##     add_child(sound)
##     sound.bind(events)

const EventsScript := preload("res://core/events/events.gd")

## The registry the cues and their sounds are asked of (Feel's).
var registry: Node = null
## The cues it played, in order, and the last one (for tests).
var played: Array[StringName] = []
var last: StringName = &""

## The intro playing (null: none) and the seconds since it opened.
var _intro: BossIntro = null
var _time: float = -1.0
var _dark: AudioStreamPlayer = null
var _reveal: AudioStreamPlayer = null


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dark = AudioStreamPlayer.new()
	_dark.name = "Dark"
	add_child(_dark)
	_reveal = AudioStreamPlayer.new()
	_reveal.name = "Reveal"
	add_child(_reveal)


func bind(events: EventsScript) -> void:
	if events != null:
		events.boss_intro_opened.connect(_on_opened)
		events.boss_intro_closed.connect(_on_closed)


func _process(delta: float) -> void:
	step(delta)


## Move it on by `delta` seconds of real time: a cue whose moment came plays once.
func step(delta: float) -> void:
	if _intro == null:
		return
	var before: float = _time
	_time += delta
	if _crossed(before, BossIntro.DARK_AT) and _intro.dark_cue != &"":
		_play(_dark, _intro.dark_cue)
	if _crossed(before, BossIntro.REVEAL_AT):
		_play(_reveal, _intro.reveal_cue_or_shared())
		# Nothing more to play: it waits for the close only to stop what plays.
		_intro = null


## True while a cue of the intro plays (for tests).
func is_playing() -> bool:
	return _dark.playing or _reveal.playing


## Stop at once (the intro closed, a run ended).
func stop() -> void:
	_intro = null
	_time = -1.0
	_dark.stop()
	_reveal.stop()


func _on_opened(_actor: int, _boss_name: String, _lore: String, intro: BossIntro, _page: int, fresh: bool) -> void:
	if not fresh or intro == null:
		return
	stop()
	_intro = intro
	_time = 0.0


func _on_closed(_actor: int) -> void:
	stop()


func _crossed(before: float, moment: float) -> bool:
	return before < moment and _time >= moment


func _play(player: AudioStreamPlayer, cue_id: StringName) -> void:
	played.append(cue_id)
	last = cue_id
	if registry == null:
		return
	var cue: CueBase = registry.call(&"get_resource", &"cues", cue_id) as CueBase
	if cue == null or cue.sound == &"":
		return
	var stream: AudioStream = registry.call(&"get_sound", cue.sound) as AudioStream
	if stream == null:
		return
	player.stream = stream
	player.play()
