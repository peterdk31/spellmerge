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
## a boss: all of it is the intro's data (rule 9). It keeps the timing only, and has no player of its
## own: the cues play on Audio's over lane (`Audio.play_over`, docs/milestones/sound.md, section 5),
## which keeps playing while the tree is paused. It allocates nothing while playing.
##
##     var sound := BossIntroSound.new()
##     sound.registry = registry
##     sound.audio = audio
##     add_child(sound)
##     sound.bind(events)

const EventsScript := preload("res://core/events/events.gd")
const AudioScript := preload("res://core/audio/audio.gd")

## The registry the cues are asked of (Feel's), and the Audio service they play on.
var registry: Node = null
var audio: AudioScript = null
## The cues the intro playing played, in order (two at most; a fresh open starts it again), and the
## last one (for tests).
var played: Array[StringName] = []
var last: StringName = &""

## The intro playing (null: none) and the seconds since it opened.
var _intro: BossIntro = null
var _time: float = -1.0
## The over lane's voices its two cues play on (-1: none).
var _dark: int = -1
var _reveal: int = -1


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


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
		_dark = _play(_intro.dark_cue)
	if _crossed(before, BossIntro.REVEAL_AT):
		_reveal = _play(_intro.reveal_cue_or_shared())
		# Nothing more to play: it waits for the close only to stop what plays.
		_intro = null


## The over lane's voice the dark cue and the reveal cue last played on (-1: none; for tests).
func dark_voice() -> int:
	return _dark


func reveal_voice() -> int:
	return _reveal


## Stop at once (the intro closed, a run ended).
func stop() -> void:
	_intro = null
	_time = -1.0
	if audio != null:
		if _dark >= 0:
			audio.over.stop(_dark)
		if _reveal >= 0:
			audio.over.stop(_reveal)
	_dark = -1
	_reveal = -1


func _on_opened(_actor: int, _boss_name: String, _lore: String, intro: BossIntro, _page: int, fresh: bool) -> void:
	if not fresh or intro == null:
		return
	stop()
	played.clear()
	_intro = intro
	_time = 0.0


func _on_closed(_actor: int) -> void:
	stop()


func _crossed(before: float, moment: float) -> bool:
	return before < moment and _time >= moment


func _play(cue_id: StringName) -> int:
	played.append(cue_id)
	last = cue_id
	if registry == null or audio == null:
		return -1
	var cue: CueBase = registry.call(&"get_resource", &"cues", cue_id) as CueBase
	if cue == null or cue.sound == &"":
		return -1
	return audio.play_over(cue.sound)
