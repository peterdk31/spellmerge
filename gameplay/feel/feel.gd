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
##   Overlapping stops do not add up: the longest one wins. After a plain hit's stop
##   there is a short rest in which plain hits do not stop the game again (a
##   crowded fight must not feel like lag); deaths and downed wizards always stop.
## - screen shake: trauma on the current Camera2D, off when `shake_enabled` is false.
## - particles: a burst of CPUParticles2D from a fixed pool. Live particles never
##   exceed PARTICLE_LIMIT. With the pool empty a hit burst is skipped, but a death
##   takes over the burst closest to ending. A kill upgrades the burst its killing
##   blow just made into a bigger one, so it costs one slot, not two.
## - a sound from `core/registry` by id; nothing plays on `null`.
##
## Nothing is allocated while playing: emitters and sound players are made once.
## The emitters live under this autoload (top level, so in world space), never
## under the scene: Flow frees the world on every Play and restart.

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
## Seconds left in which plain hits cannot start a hit-stop, in real time.
var rest_left: float = 0.0
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
## The burst, spot and sound voice of the latest plain hit since the last step, so a
## kill at the same spot upgrades them instead of using a second slot and sound.
var _hit_burst: CPUParticles2D = null
var _hit_position: Vector2 = Vector2.INF
var _hit_voice: int = -1
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _texture: Texture2D = null
var _last_usec: int = 0


func _ready() -> void:
	_rng.seed = 1
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if registry == null:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if preset == null:
		preset = load("res://gameplay/feel/presets/punchy.tres") as FeelPresetScript
	_texture = load("res://art/vfx/hit_spark.svg") as Texture2D
	_last_usec = Time.get_ticks_usec()
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


func _exit_tree() -> void:
	if drive_engine:
		Engine.time_scale = 1.0


func _process(delta: float) -> void:
	var real_delta: float = delta
	if drive_engine:
		# Real time from the clock, so other uses of Engine.time_scale cannot skew it.
		var now: int = Time.get_ticks_usec()
		real_delta = minf(float(now - _last_usec) / 1000000.0, 0.25)
		_last_usec = now
	step(real_delta)


## Advance by `real_delta` seconds of real time (not slowed by hit-stop).
## Particles simulate on scaled time, which is never ahead of real time, so a burst
## is never released while it is still flying.
func step(real_delta: float) -> void:
	_hit_burst = null
	_hit_voice = -1
	rest_left = maxf(rest_left - real_delta, 0.0)
	if stop_left > 0.0:
		stop_left = maxf(stop_left - real_delta, 0.0)
		if stop_left == 0.0:
			rest_left = preset.hit_stop_rest
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
			if is_instance_valid(_active[at]):
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
	_juice(position, preset.hit_stop_seconds, false, preset.hit_shake, preset.hit_sound)


func _on_enemy_died(_player: int, _enemy: Node, position: Vector2) -> void:
	_juice(position, preset.death_stop_seconds, true, preset.death_shake, preset.death_sound)


func _on_player_downed(_player: int) -> void:
	# The event names no position, so a downed wizard gets stop, shake and sound only.
	_juice(Vector2.INF, preset.death_stop_seconds, true, preset.downed_shake, preset.downed_sound)


## `strong` is a death or a downed wizard: it ignores the rest after a hit-stop and
## gets the bigger burst.
func _juice(position: Vector2, stop: float, strong: bool, shake: float, sound: StringName) -> void:
	if stop > stop_left and (strong or rest_left <= 0.0):
		stop_left = stop
		_set_time_scale(preset.hit_stop_scale)
	if shake_enabled:
		_refresh_camera()
		_trauma = minf(_trauma + shake, 1.0)
	var upgraded: bool = false
	if position != Vector2.INF:
		if strong:
			upgraded = _burst_death(position)
		else:
			_hit_burst = _burst(position, 1.0)
			_hit_position = position
	if upgraded and _hit_voice >= 0:
		_voices[_hit_voice].stop()
	var voice: int = _play(sound)
	if not strong:
		_hit_voice = voice


## Start a burst; `size` scales its speed, life and particle size. Returns it, or
## null when the pool is empty.
func _burst(position: Vector2, size: float) -> CPUParticles2D:
	var burst := _bursts.acquire() as CPUParticles2D
	if burst == null:
		return null
	_launch(burst, position, size)
	_active.append(burst)
	_active_left.append(preset.particle_lifetime * size)
	return burst


func _launch(burst: CPUParticles2D, position: Vector2, size: float) -> void:
	burst.global_position = position
	burst.lifetime = preset.particle_lifetime * size
	burst.initial_velocity_min = preset.particle_speed * 0.5 * size
	burst.initial_velocity_max = preset.particle_speed * size
	burst.scale_amount_min = 0.3 * size
	burst.scale_amount_max = 0.5 * size
	burst.visible = true
	burst.restart()
	burst.emitting = true


## A death burst: the killing blow's own burst made bigger when it is at this spot,
## else a new one, else the burst closest to ending taken over. Returns true when
## it upgraded the hit burst (which then needs no second sound).
func _burst_death(position: Vector2) -> bool:
	var size: float = preset.death_particle_size
	if _hit_burst != null and _hit_position == position:
		var at: int = _active.find(_hit_burst)
		if at >= 0:
			_launch(_hit_burst, position, size)
			_active_left[at] = preset.particle_lifetime * size
			return true
	if _burst(position, size) != null:
		return false
	var oldest: int = -1
	for i in _active.size():
		if oldest < 0 or _active_left[i] < _active_left[oldest]:
			oldest = i
	if oldest >= 0:
		_launch(_active[oldest], position, size)
		_active_left[oldest] = preset.particle_lifetime * size
	return false


## Plays a sound; returns the voice used, or -1 for none.
func _play(id: StringName) -> int:
	if registry == null or id == &"":
		return -1
	var sound: AudioStream = registry.get_sound(id)
	if sound == null:
		return -1
	var used: int = _next_voice
	var voice: AudioStreamPlayer = _voices[used]
	_next_voice = (_next_voice + 1) % SOUND_VOICES
	voice.stream = sound
	voice.play()
	return used


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
	burst.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Top level: the burst sits in world space and lives under this autoload, so a
	# scene change cannot free it.
	burst.top_level = true
	add_child(burst)
	return burst


func _hide_burst(item: Object) -> void:
	var burst := item as CPUParticles2D
	burst.emitting = false
	burst.visible = false


func _set_time_scale(value: float) -> void:
	if drive_engine:
		Engine.time_scale = value


## Follow the current camera: when it changed, the old one is put back at rest.
func _refresh_camera() -> void:
	if not is_inside_tree():
		return
	var current: Camera2D = get_viewport().get_camera_2d()
	if current == _camera:
		return
	if _camera != null and is_instance_valid(_camera):
		_camera.offset = Vector2.ZERO
	_camera = current


func _apply_camera() -> void:
	if _camera != null and is_instance_valid(_camera):
		_camera.offset = shake_offset


func _reset_camera() -> void:
	shake_offset = Vector2.ZERO
	_refresh_camera()
	_apply_camera()
