extends Node
## Feel: juice on every hit. One autoload ("Feel") that only reacts to events:
## `damage_dealt`, `enemy_died` and `player_downed`. It never changes damage,
## health or who wins, and it sends no events.
##
##     Feel.shake_enabled = false     # the setting: no screen shake (kept in memory until core/save exists)
##     Feel.preset = load("res://gameplay/feel/presets/punchy.tres")
##
## On a hit it does four things, all the same for every player:
## - hit-stop: Engine.time_scale drops for a few hundredths of a second (real time).
##   Overlapping stops do not add up: the longest one wins.
## - screen shake: trauma on the current Camera2D, off when `shake_enabled` is false.
## - particles: a burst of CPUParticles2D from a fixed pool. Live particles never
##   exceed PARTICLE_LIMIT; with the pool empty a burst is skipped.
## - a sound from `core/registry` by id; nothing plays on `null`.
##
## Nothing is allocated while playing: emitters and sound players are made once.

const EventsScript := preload("res://core/events/events.gd")
const PoolScript := preload("res://core/pools/pool.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")

## Most hit particles alive at once, across all players (one limit for the "hit" effect).
const PARTICLE_LIMIT: int = 48
## Particles in one burst. The pool holds PARTICLE_LIMIT / BURST_PARTICLES bursts.
const BURST_PARTICLES: int = 8
const BURST_SLOTS: int = PARTICLE_LIMIT / BURST_PARTICLES
## Sounds that can play at once.
const SOUND_VOICES: int = 8

## The services. Only tests set these, before adding the node; otherwise the
## autoloads are used.
var events: EventsScript = null
var registry: RegistryScript = null
var projectiles: Node = null
## Tests turn this off: no Engine.time_scale changes.
var drive_engine: bool = true

var preset: FeelPresetScript = null
var shake_enabled: bool = true:
	set(value):
		shake_enabled = value
		if not value:
			_trauma = 0.0
			_reset_camera()
## Seconds of hit-stop left, in real time.
var stop_left: float = 0.0
## Current offset applied to the camera.
var shake_offset: Vector2 = Vector2.ZERO

## Shake strength, 0 to 1.
var _trauma: float = 0.0
var _camera: Camera2D = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _bursts: PoolScript = null
## Bursts in use and their seconds left (parallel arrays, at most BURST_SLOTS long).
var _active: Array[CPUParticles2D] = []
var _active_left: PackedFloat32Array = PackedFloat32Array()
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _texture: Texture2D = null


func _ready() -> void:
	_rng.seed = 1
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if registry == null:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if preset == null:
		preset = load("res://gameplay/feel/presets/punchy.tres") as FeelPresetScript
	_texture = load("res://art/vfx/hit_spark.svg") as Texture2D
	_bursts = PoolScript.new(_make_burst, BURST_SLOTS, Callable(), _hide_burst)
	for i in SOUND_VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	if events == null:
		push_warning("Feel: the Events autoload is missing, so there is no juice.")
		return
	events.damage_dealt.connect(_on_damage_dealt)
	events.enemy_died.connect(_on_enemy_died)
	events.player_downed.connect(_on_player_downed)
	if projectiles == null:
		projectiles = get_node_or_null("/root/Projectiles")
	if projectiles != null and "texture" in projectiles and projectiles.texture == null:
		projectiles.texture = load("res://art/vfx/fire_bolt.svg") as Texture2D


func _process(delta: float) -> void:
	var time_scale: float = Engine.time_scale if drive_engine else 1.0
	step(delta / maxf(time_scale, 0.001))


## Advance by `real_delta` seconds of real time (not slowed by hit-stop).
func step(real_delta: float) -> void:
	if stop_left > 0.0:
		stop_left = maxf(stop_left - real_delta, 0.0)
		if stop_left == 0.0:
			_set_time_scale(1.0)
	if _trauma > 0.0:
		_trauma = maxf(_trauma - preset.shake_decay * real_delta, 0.0)
		var strength: float = _trauma * _trauma * preset.max_shake_pixels
		shake_offset = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * strength
		if _trauma == 0.0:
			shake_offset = Vector2.ZERO
		_apply_camera()
	var at: int = _active.size() - 1
	while at >= 0:
		_active_left[at] -= real_delta
		if _active_left[at] <= 0.0:
			_bursts.release(_active[at])
			var last: int = _active.size() - 1
			_active[at] = _active[last]
			_active_left[at] = _active_left[last]
			_active.resize(last)
			_active_left.resize(last)
		at -= 1


## Live hit particles right now: never more than PARTICLE_LIMIT.
func live_particles() -> int:
	return _active.size() * BURST_PARTICLES


## Current shake strength, 0 to 1.
func trauma() -> float:
	return _trauma


func _on_damage_dealt(_player: int, _target: Node, _amount: int, position: Vector2) -> void:
	_juice(position, preset.hit_stop_seconds, preset.hit_shake, preset.hit_sound)


func _on_enemy_died(_player: int, _enemy: Node, position: Vector2) -> void:
	_juice(position, preset.death_stop_seconds, preset.death_shake, preset.death_sound)


func _on_player_downed(_player: int) -> void:
	# The event names no position, so a downed wizard gets stop, shake and sound only.
	_juice(Vector2.INF, preset.death_stop_seconds, preset.downed_shake, preset.downed_sound)


func _juice(position: Vector2, stop: float, shake: float, sound: StringName) -> void:
	if stop > stop_left:
		stop_left = stop
		_set_time_scale(preset.hit_stop_scale)
	if shake_enabled:
		_trauma = minf(_trauma + shake, 1.0)
	if position != Vector2.INF:
		_burst(position)
	_play(sound)


func _burst(position: Vector2) -> void:
	var burst := _bursts.acquire() as CPUParticles2D
	if burst == null:
		return
	var parent: Node = _world()
	if burst.get_parent() != parent:
		if burst.get_parent() != null:
			burst.get_parent().remove_child(burst)
		parent.add_child(burst)
	burst.global_position = position
	burst.lifetime = preset.particle_lifetime
	burst.initial_velocity_min = preset.particle_speed * 0.5
	burst.initial_velocity_max = preset.particle_speed
	burst.visible = true
	burst.restart()
	burst.emitting = true
	_active.append(burst)
	_active_left.append(preset.particle_lifetime)


func _play(id: StringName) -> void:
	if registry == null or id == &"":
		return
	var sound: AudioStream = registry.get_sound(id)
	if sound == null:
		return
	var voice: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % SOUND_VOICES
	voice.stream = sound
	voice.play()


func _make_burst() -> Object:
	var burst := CPUParticles2D.new()
	burst.amount = BURST_PARTICLES
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.emitting = false
	burst.visible = false
	burst.texture = _texture
	burst.spread = 180.0
	burst.gravity = Vector2.ZERO
	burst.scale_amount_min = 0.3
	burst.scale_amount_max = 0.5
	burst.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return burst


func _hide_burst(item: Object) -> void:
	var burst := item as CPUParticles2D
	burst.emitting = false
	burst.visible = false


## Where bursts go: the current scene (the world), else this node.
func _world() -> Node:
	if is_inside_tree() and get_tree().current_scene != null:
		return get_tree().current_scene
	return self


func _set_time_scale(value: float) -> void:
	if drive_engine:
		Engine.time_scale = value


func _apply_camera() -> void:
	if not is_inside_tree():
		return
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_2d()
	if _camera != null:
		_camera.offset = shake_offset


func _reset_camera() -> void:
	shake_offset = Vector2.ZERO
	_apply_camera()
