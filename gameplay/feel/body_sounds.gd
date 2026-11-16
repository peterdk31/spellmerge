extends RefCounted
## What the bodies in play sound of their own (boss plan OB15), read from their state every POLL
## seconds and drawn only: each body's phase (a phase seen to start plays its look's `cue` from the
## body, one first seen in a phase plays none: a snapshot, a late join; its look's `sound`, the
## latest look up to it, is held while it lasts, the last phase's let go) and the music: the first
## living body in actor order whose data has `music`, at its phase's intensity (1, then each phase's
## `intensity` or one more), else the room's (`room_music`, set by Feel as a room is entered). Feel
## owns one and steps it once a frame; it plays a cue through Feel (`play_cue`).

const ActorsScript := preload("res://core/actors/actors.gd")
const SoundsScript := preload("res://gameplay/feel/sounds.gd")
const MusicScript := preload("res://gameplay/feel/music.gd")

## How often the bodies are looked at (s).
const POLL: float = 0.1

## The held sounds and the music played to, and how a cue is played (`Feel.play_cue`'s arguments:
## the cue's id, the actor, where, and the body it follows).
var sounds: SoundsScript = null
var music: MusicScript = null
var play_cue: Callable = Callable()
## The room in play's music (`RoomBase.music`; null: none).
var room_music: MusicTrack = null

var _wait: float = 0.0
## The phase each actor id's body was last seen in (`Phases.current`), and that body (its instance
## id).
var _seen: PackedInt32Array = PackedInt32Array()
var _body: PackedInt64Array = PackedInt64Array()
var _open: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	_seen.resize(ActorsScript.ACTORS)
	_seen.fill(-1)
	_body.resize(ActorsScript.ACTORS)
	_open.resize(ActorsScript.ACTORS)


## A new room (`room_music` its music): looked at at once, every body seen afresh (what held its
## sound was stopped with the last room).
func room_entered(track: MusicTrack) -> void:
	room_music = track
	_wait = 0.0
	_body.fill(0)


## `delta` real seconds on: the bodies of `table` looked at when due, then the music steps.
func step(delta: float, table: ActorsScript, registry: Node) -> void:
	if music == null:
		return
	_wait -= delta
	if _wait <= 0.0:
		_wait = POLL
		var track: MusicTrack = room_music
		var intensity: int = 1
		var found: bool = false
		var open: int = table.open_ids(_open) if table != null else 0
		for n in open:
			var id: int = _open[n]
			var body: Actor = table.node_of(id) as Actor
			if body == null or not is_instance_valid(body) or body.data == null:
				continue
			if body.phases != null:
				_look_at_phase(id, body, registry)
			if not found and body.data.music != null and not body.is_dying():
				found = true
				track = body.data.music
				intensity = intensity_of(body)
		music.registry = registry
		music.play(track, intensity)
	music.step(delta)


## The music's intensity for `body`: 1 before its first phase, then each phase's `intensity`, or one
## more than the phase before when it names none.
static func intensity_of(body: Actor) -> int:
	var intensity: int = 1
	if body.phases == null:
		return intensity
	for at in mini(body.phases.current + 1, body.phases.list.size()):
		var entry: EnemyPhase = body.phases.list[at]
		intensity = entry.intensity if entry != null and entry.intensity > 0 else intensity + 1
	return intensity


## The look `body` wears in phase `phase`: the latest phase up to it that names one (null: its own).
static func phase_look(body: Actor, phase: int) -> PhaseLook:
	for at in range(mini(phase, body.phases.list.size() - 1), -1, -1):
		var entry: EnemyPhase = body.phases.list[at]
		if entry != null and entry.look != null:
			return entry.look
	return null


func _look_at_phase(id: int, body: Actor, registry: Node) -> void:
	var phase: int = body.phases.current
	var first: bool = _body[id] != body.get_instance_id()
	if not first and _seen[id] == phase:
		return
	var was: int = _seen[id]
	_body[id] = body.get_instance_id()
	_seen[id] = phase
	var look: PhaseLook = phase_look(body, phase)
	if not first and phase > was and phase >= 0 and look != null and body.phases.list[phase].look == look and look.cue != &"" and play_cue.is_valid():
		play_cue.call(look.cue, id, body.global_position, body)
	if sounds == null:
		return
	var sound: StringName = look.sound if look != null else &""
	if sound != &"" and sounds.held_of(id, SoundsScript.Until.PHASE) == sound:
		return
	sounds.release(id, SoundsScript.Until.PHASE)
	if sound != &"":
		sounds.registry = registry
		sounds.hold(sound, SoundsScript.Until.PHASE, id, phase, body, body.global_position, INF)
