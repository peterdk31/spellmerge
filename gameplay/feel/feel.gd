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
## - a white hit flash and a squash on the hit enemy's or wizard's `Sprite` node
##   (a fixed set of reactions; a sprite that is gone is skipped).
## - a white puff where an enemy dies.
## - a sound from `core/registry` by id; nothing plays on `null`.
##
## On `spell_cast` it shows a muzzle flash at the staff tip and kicks the camera a
## little against the aim. Neither touches the cast itself.
##
## Nothing is allocated while playing: emitters and sound players are made once.
## The emitters live under this autoload (top level, so in world space), never
## under the scene: Flow frees the world on every Play and restart.

const EventsScript := preload("res://core/events/events.gd")
const PoolScript := preload("res://core/pools/pool.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const FLASH_SHADER: Shader = preload("res://gameplay/feel/hit_flash.gdshader")

## Most hit particles alive at once, across all players (one limit for the "hit" effect).
const PARTICLE_LIMIT: int = 48
## Particles in one burst. The pool holds PARTICLE_LIMIT / BURST_PARTICLES bursts.
const BURST_PARTICLES: int = 8
const BURST_SLOTS: int = PARTICLE_LIMIT / BURST_PARTICLES
## Sounds that can play at once.
const SOUND_VOICES: int = 8
## Sprites reacting to a hit at once; a hit past this only skips its flash.
const REACT_SLOTS: int = 16
## Flash sprites: one muzzle flash per player (slots 0-3), then the death puffs.
const MUZZLE_SLOTS: int = 4
const FLASH_SLOTS: int = 8
## The biggest camera kick in pixels, however fast the casting.
const MAX_KICK_PIXELS: float = 4.0

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
			_kick = Vector2.ZERO
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
## Hit reactions: the sprite, the scale it had, and seconds left (parallel arrays).
## Instance ids, not references: a sprite may be freed while it waits, and an
## array cannot hold a freed object.
var _react_sprites: PackedInt64Array = PackedInt64Array()
var _react_scale: PackedVector2Array = PackedVector2Array()
var _react_left: PackedFloat32Array = PackedFloat32Array()
var _flash_material: ShaderMaterial = null
## Muzzle flashes and death puffs: sprites made once, with seconds left, seconds
## they started with and their size (parallel arrays of FLASH_SLOTS).
var _flashes: Array[Sprite2D] = []
var _flash_left: PackedFloat32Array = PackedFloat32Array()
var _flash_total: PackedFloat32Array = PackedFloat32Array()
var _flash_size: PackedFloat32Array = PackedFloat32Array()
var _next_puff: int = MUZZLE_SLOTS
## Camera kick of casts (pixels), added to the shake.
var _kick: Vector2 = Vector2.ZERO
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
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = FLASH_SHADER
	for i in FLASH_SLOTS:
		var flash := Sprite2D.new()
		flash.texture = _texture
		flash.top_level = true
		flash.visible = false
		flash.z_index = 20
		flash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(flash)
		_flashes.append(flash)
	_flash_left.resize(FLASH_SLOTS)
	_flash_total.resize(FLASH_SLOTS)
	_flash_size.resize(FLASH_SLOTS)
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
	events.spell_cast.connect(_on_spell_cast)
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
	if _trauma > 0.0 or _kick != Vector2.ZERO:
		_trauma = maxf(_trauma - preset.shake_decay * real_delta, 0.0)
		var strength: float = _trauma * _trauma * preset.max_shake_pixels
		shake_offset = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * strength
		if _trauma == 0.0:
			shake_offset = Vector2.ZERO
		_kick = _kick.move_toward(Vector2.ZERO, preset.cast_kick_decay * real_delta)
		shake_offset += _kick
		_apply_camera()
	_step_reactions(real_delta)
	_step_flashes(real_delta)
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


## Flash and squash the hit sprites for `real_delta` seconds, and put back those done.
func _step_reactions(real_delta: float) -> void:
	var at: int = _react_sprites.size() - 1
	while at >= 0:
		_react_left[at] -= real_delta
		var sprite := instance_from_id(_react_sprites[at]) as Sprite2D
		var alive: bool = sprite != null
		if _react_left[at] <= 0.0 or not alive:
			if alive:
				sprite.material = null
				sprite.scale = _react_scale[at]
			var last: int = _react_sprites.size() - 1
			_react_sprites[at] = _react_sprites[last]
			_react_scale[at] = _react_scale[last]
			_react_left[at] = _react_left[last]
			_react_sprites.resize(last)
			_react_scale.resize(last)
			_react_left.resize(last)
		else:
			var squash: float = preset.hit_squash * _react_left[at] / maxf(preset.flash_seconds, 0.001)
			sprite.scale = _react_scale[at] * Vector2(1.0 + squash, 1.0 - squash)
		at -= 1


## Fade and grow the muzzle flashes and death puffs.
func _step_flashes(real_delta: float) -> void:
	for i in FLASH_SLOTS:
		if _flash_left[i] <= 0.0:
			continue
		_flash_left[i] -= real_delta
		var flash: Sprite2D = _flashes[i]
		if _flash_left[i] <= 0.0:
			flash.visible = false
			continue
		var t: float = _flash_left[i] / _flash_total[i]
		flash.modulate.a = t
		flash.scale = Vector2.ONE * (_flash_size[i] * (1.5 - 0.5 * t))


## Show flash `slot` at `position` for `seconds`, `size` times the art's size.
func _show_flash(slot: int, position: Vector2, seconds: float, size: float) -> void:
	if seconds <= 0.0:
		return
	var flash: Sprite2D = _flashes[slot]
	flash.global_position = position
	flash.modulate = Color.WHITE
	flash.scale = Vector2.ONE * size
	flash.visible = true
	_flash_left[slot] = seconds
	_flash_total[slot] = seconds
	_flash_size[slot] = size


## Start the flash and squash of the hit node's `Sprite` child, if it has one.
func _react(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	var sprite := target.get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	var at: int = _react_sprites.find(sprite.get_instance_id())
	if at >= 0:
		_react_left[at] = preset.flash_seconds
	elif _react_sprites.size() < REACT_SLOTS:
		_react_sprites.append(sprite.get_instance_id())
		_react_scale.append(sprite.scale)
		_react_left.append(preset.flash_seconds)
	else:
		return
	sprite.material = _flash_material


## Sprites flashing right now (for tests).
func reacting_sprites() -> int:
	return _react_sprites.size()


## Muzzle flashes and death puffs showing right now (for tests).
func live_flashes() -> int:
	var count: int = 0
	for i in FLASH_SLOTS:
		if _flash_left[i] > 0.0:
			count += 1
	return count


## Current camera kick in pixels (for tests).
func kick() -> Vector2:
	return _kick


## Live hit particles right now: never more than PARTICLE_LIMIT.
func live_particles() -> int:
	return _active.size() * BURST_PARTICLES


## Current shake strength, 0 to 1.
func trauma() -> float:
	return _trauma


func _on_damage_dealt(_player: int, target: Node, _amount: int, position: Vector2) -> void:
	_react(target)
	_juice(position, preset.hit_stop_seconds, false, preset.hit_shake, preset.hit_sound)


func _on_enemy_died(_player: int, _enemy: Node, position: Vector2) -> void:
	_show_flash(_next_puff, position, preset.death_puff_seconds, preset.death_puff_size)
	_next_puff = MUZZLE_SLOTS + (_next_puff - MUZZLE_SLOTS + 1) % (FLASH_SLOTS - MUZZLE_SLOTS)
	_juice(position, preset.death_stop_seconds, true, preset.death_shake, preset.death_sound)


func _on_spell_cast(player: int, _spell_id: StringName, origin: Vector2, direction: Vector2) -> void:
	_show_flash(clampi(player, 0, MUZZLE_SLOTS - 1), origin, preset.muzzle_flash_seconds, preset.muzzle_flash_size)
	if shake_enabled and direction != Vector2.ZERO:
		_refresh_camera()
		_kick = (_kick - direction.normalized() * preset.cast_kick_pixels).limit_length(MAX_KICK_PIXELS)


func _on_player_downed(_player: int) -> void:
	# The event names no position, so a downed wizard gets stop, shake and sound only.
	_juice(Vector2.INF, preset.death_stop_seconds, true, preset.downed_shake, preset.downed_sound)


## `strong` is a death or a downed wizard: it ignores the rest after a hit-stop and
## gets the bigger burst.
func _juice(position: Vector2, stop: float, strong: bool, shake: float, sound: StringName) -> void:
	# A plain hit only starts a stop when none runs and the rest is over (or a stream
	# of hits would extend it for ever); a strong one may lengthen a shorter stop.
	if stop > stop_left and (strong or (stop_left <= 0.0 and rest_left <= 0.0)):
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
