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
## - an effect (see "Effects" below): sparks sprayed on along the hit, or a puff all
##   round for a hit with no way. A kill turns its killing blow's spray into a bigger
##   puff, so it costs one slot, not two.
## - a white hit flash and a squash on the hit enemy's or wizard's `Sprite` node
##   (a fixed set of reactions; a sprite that is gone is skipped).
## - a white-hot ring where an enemy dies, and a death animation: a copy of the dead
##   enemy's `Sprite` turns white-hot and falls apart pixel by pixel (the enemy itself is
##   freed at once).
## - a sound from `core/registry` by id; nothing plays on `null`.
##
## `projectile_impact` (from `core/projectiles`) says where a shot struck and which way it
## flew. On a character the hit becomes a spray along that way, in ember for an enemy and
## in the wizard's own colours for a wizard, a little bigger with more damage. On a wall or
## pillar it knocks stone chips back. Where a shot lands it shows an effect in the shot's own
## ramp and cards (see "Effects" below).
##
## On `spell_cast` it shows a cast flash at the staff tip in the player's colours (and a ring
## for a carrier whose cast look has one), and kicks the camera a little against the aim.
##
## Effects (the glow look, 2026-10-27; the owner: "I only want the new style going forward"):
## every flare, spray, puff, ring, chip, arc and status is drawn by the shots' own shader
## (`shot_core.gdshader`, kinds KIND_BURST to KIND_STATUS) in one MultiMesh of `effect_slots`
## (a setting: Settings, "Effect slots", through `effect_slots_changed`),
## each with the core colour and look of the shot it comes from (`impact_core`, `impact_look` of
## the projectile manager), so a frost bolt lands in frost flecks and a lightning one in sparks,
## all glowing. A new effect takes the oldest slot when they are all busy. On
## `wizard_cast` (which carries the wizard node) the caster's `Sprite` gets thin and
## tall for a moment. None of this touches the cast itself.
##
## Nothing is allocated while playing: the effect batch and sound players are made once.
## They live under this autoload (top level, so in world space), never under the scene:
## Flow frees the world on every Play and restart.

const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
## The look of a hit kind with no entry at all: nothing changes. Shared, never written.
const NO_LOOK: Dictionary = {}
const FeelPresetScript :=preload("res://gameplay/feel/presets/feel_preset.gd")
const FLASH_SHADER: Shader = preload("res://gameplay/feel/hit_flash.gdshader")
## Draws the beam and the nova ring like a shot: bone body tinted by the player, core by the element.
const CORE_SHADER: Shader = preload("res://core/projectiles/shot_core.gdshader")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
## Bone light: the white-hot of a plain thing (a death's ring).
const BONE_LIGHT: Color = Color("#f4f1ea")
## Beams and nova rings on screen per player: one cast makes at most 24 shots (the spell limit),
## so a split fan is drawn whole; past that the player's oldest slot is taken over.
const FORMS_PER_PLAYER: int = 24
## Four players' beam sprites and the enemies' (one share for every enemy caster, staffs F7).
const FORM_SLOTS: int = FORMS_PER_PLAYER * 5
## The share of the beam sprites every enemy's beam takes turns in.
const ENEMY_FORMS: int = 4
## Beams and rings draw above the room, under the shots (50) and the flashes (20).
const FORM_Z: int = 18
## Live beams drawn at once (core/spells keeps at most as many), and the most points of each
## one's line: a homing beam bends from target to target, so it is drawn along its path's points.
const LIVE_BEAMS: int = 64
const LIVE_BEAM_POINTS: int = 80
## The beam texture's height: a line this wide shows it at its own size.
const BEAM_TEXTURE_HEIGHT: float = 32.0

## Sounds that can play at once.
const SOUND_VOICES: int = 8
## Sprites reacting to a hit at once; a hit past this only skips its flash.
const REACT_SLOTS: int = 16
## Reaction names (labels) rising at once.
const REACTION_SLOTS: int = 4
## Characters that show a status at once (an effect that follows each), and how often the
## statuses are read in seconds.
const STATUS_SLOTS: int = 16
const STATUS_POLL: float = 0.1
## How far a reaction's name rises while it shows, in pixels.
const REACTION_RISE: float = 10.0
## The same reaction makes its sound and shake at most this often, and its name is not shown
## again while the first still rises within `REACTION_LABEL_NEAR` pixels.
const REACTION_REPEAT: float = 0.3
const REACTION_LABEL_NEAR: float = 40.0
## The damage a hit spray is sized for (the fire bolt's); more is a bigger spray, less a smaller one.
const SPRAY_REF_DAMAGE: int = 5
const SPRAY_MIN_SIZE: float = 0.7
const SPRAY_MAX_SIZE: float = 1.6
## Death animations at once; past that the oldest slot is taken over. They draw above the
## room and the wizards, under the shots and effects.
const GHOST_SLOTS: int = 8
const GHOST_Z: int = 21
## The effects drawn with the shot shader (see "Effects" above): the kinds it knows (K_* in
## shot_core.gdshader), their seconds and their draw layer (with the shots, above the room and
## the wizards). How many can show at once is a setting (`EffectSlots` in core/settings).
const KIND_BURST: int = 4
const KIND_RING_OUT: int = 5
const KIND_RING_IN: int = 6
const KIND_RUNE_BURST: int = 7
const KIND_CAST: int = 8
const KIND_DASH: int = 9
const KIND_SPRAY: int = 11
const KIND_PUFF: int = 12
const KIND_CHIPS: int = 13
const KIND_ARC: int = 14
const KIND_STATUS: int = 15
## The look bit that makes an effect take its colour exactly (a reaction's own colour) instead
## of the palette material it is nearest (kind 24 in the shader).
const EXACT: int = 1 << 23
const SPRAY_SECONDS: float = 0.3
const PUFF_SECONDS: float = 0.4
const CHIPS_SECONDS: float = 0.5
## A status effect lasts until its status ends (Feel ends it).
const FOREVER: float = 1.0e9
const BURST_SECONDS: float = 0.3
const RING_SECONDS: float = 0.22
## How big a rain's marker ring is (its zoom: GRID x zoom pixels across).
const RAIN_MARK_ZOOM: int = 2
const RUNE_BURST_SECONDS: float = 0.45
const CAST_SECONDS: float = 0.14
## A dash's dust where it left (its way is the caster's trail, drawn by the projectile manager
## where the wizard really went; its landing is a ring, `_on_caster_move_finished`).
const DASH_SECONDS: float = 0.6
## A shot whose life runs out goes off in a small pop (the mockup's): a flare this big.
const POP_ZOOM: int = 1
const POP_SECONDS: float = 0.2
## A dash effect is drawn along its length (at most DASH_LONGEST: the length travels in the zoom's
## place, 4 px a step), DASH_MARGIN longer at each end and DASH_ACROSS across (the shader's).
const DASH_LONGEST: float = 252.0
const DASH_MARGIN: float = 12.0
const DASH_ACROSS: float = 32.0
## A discharge arc is drawn like a dash: its length in the zoom's place, ARC_MARGIN past each end,
## ARC_ACROSS across (the shader's).
const ARC_MARGIN: float = 4.0
const ARC_ACROSS: float = 16.0
## A status effect's zoom (round a character of about 16 px) and how far above its feet it sits.
const STATUS_ZOOM: int = 2
const STATUS_RISE: float = 8.0
## A beam is drawn this wide (its core, rim, flares and glow; `shot_core.gdshader`'s beam mode).
const BEAM_WIDTH: float = 16.0
## How far a beam's quad reaches past each end, so its flares are whole (the shader's beam_lead).
const BEAM_LEAD: float = 8.0
const EFFECT_Z: int = 50
## The effect quad is the shot shader's grid times the zoom (LOOK_GRID in core/projectiles).
const EFFECT_GRID: float = 24.0
const EFFECT_STRIDE: int = 16
## The age code beside an effect's kind: TRACE_FROM + TRACE_SPAN x how far through it is.
const EFFECT_FROM: float = 0.02
const EFFECT_SPAN: float = 0.42
## Muzzle flash colour of each player: the light colour of the player ramps in
## docs/STYLE.md (the same as the reticle in `gameplay/player`).
const PLAYER_COLORS: Array[Color] = [
	Color("7fc0f0"), Color("f59ab8"), Color("8fd46a"), Color("c99af0"),
]
## How long a muzzle flash is compared with its width.
## The biggest camera kick in pixels, however fast the casting.
const MAX_KICK_PIXELS: float = 4.0

## The services. Only tests set these, before adding the node; otherwise the
## autoloads are used.
var events: EventsScript = null
var registry: RegistryScript = null
var projectiles: Node = null
## The combat autoload, asked only `status_left(enemy, id)` to know when a status ends.
var combat: Node = null
## The spell runtime, asked only for its live beams (`beam_*`) to draw them every frame.
var spells: Node = null
## Tests turn this off: no Engine.time_scale changes.
var drive_engine: bool = true
## The stress benchmark turns this off to time a scene without hit particles (the bursts are
## skipped as when the pool is empty; flashes, numbers and sound stay).
var particles_enabled: bool = true

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
## The effect slot, spot and sound voice of the latest plain hit since the last step, so a
## kill at the same spot upgrades them instead of using a second slot and sound.
var _hit_effect: int = -1
var _hit_position: Vector2 = Vector2.INF
var _hit_voice: int = -1
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
## Hit reactions: the sprite, the scale it had, and seconds left (parallel arrays).
## Instance ids, not references: a sprite may be freed while it waits, and an
## array cannot hold a freed object.
var _react_sprites: PackedInt64Array = PackedInt64Array()
var _react_scale: PackedVector2Array = PackedVector2Array()
var _react_written: PackedVector2Array = PackedVector2Array()
var _react_left: PackedFloat32Array = PackedFloat32Array()
## Per reaction: its length in seconds and its squash (a hit squashes wide and low, a
## cast thin and tall, which is negative).
var _react_total: PackedFloat32Array = PackedFloat32Array()
var _react_amount: PackedFloat32Array = PackedFloat32Array()
var _flash_material: ShaderMaterial = null
## The live beams (`Spells.beam_*`), one line each, made once.
var _live_beams: Array[Line2D] = []
## Scratch for the points of the live beam being drawn.
var _beam_line: PackedVector2Array = PackedVector2Array()
## Beams (sprites made once): seconds left and in all, the owner's body tint and the beam's
## length in pixels.
var _forms: Array[Sprite2D] = []
var _form_left: PackedFloat32Array = PackedFloat32Array()
var _form_total: PackedFloat32Array = PackedFloat32Array()
var _form_body: PackedColorArray = PackedColorArray()
var _form_length: PackedFloat32Array = PackedFloat32Array()
var _next_form: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])
## Each player's last dash (the enemies share the fifth): where it started, its element's colour
## and its look, for the landing.
var _dash_from: PackedVector2Array = PackedVector2Array([Vector2.INF, Vector2.INF, Vector2.INF, Vector2.INF, Vector2.INF])
var _dash_core: PackedColorArray = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
var _dash_look: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])
## Reaction names: one label per reaction flash slot, with where it starts and seconds left.
var _labels: Array[Label] = []
var _label_left: PackedFloat32Array = PackedFloat32Array()
## The seconds a label was given (0: a reaction name's own three times `reaction_seconds`).
var _label_total: PackedFloat32Array = PackedFloat32Array()
var _label_start: PackedVector2Array = PackedVector2Array()
var _next_reaction: int = 0
## Statuses shown, per character (parallel arrays): its instance id, the effect slot that
## shows it (-1 for none), real seconds shown, the status it shows and when to read the
## statuses next.
var _status_enemies: PackedInt64Array = PackedInt64Array()
var _status_effect: PackedInt32Array = PackedInt32Array()
var _status_age: PackedFloat32Array = PackedFloat32Array()
var _status_shown: Array[StringName] = []
var _status_next_poll: PackedFloat32Array = PackedFloat32Array()
## Sound ids by reaction id, built the first time a reaction is heard (so it allocates once).
var _reaction_sounds: Dictionary = {}
## Display names by reaction id, built the same way.
var _reaction_names: Dictionary = {}
## Real seconds since feel started, and when each reaction id last gave a sound and a shake.
var _clock: float = 0.0
var _effect_node: MultiMeshInstance2D = null
var _effect_buffer: PackedFloat32Array = PackedFloat32Array()
var _effect_kind: PackedInt32Array = PackedInt32Array()
var _effect_at: PackedVector2Array = PackedVector2Array()
var _effect_dir: PackedVector2Array = PackedVector2Array()
var _effect_core: PackedColorArray = PackedColorArray()
var _effect_player: PackedInt32Array = PackedInt32Array()
var _effect_zoom: PackedInt32Array = PackedInt32Array()
var _effect_look: PackedInt32Array = PackedInt32Array()
var _effect_age: PackedFloat32Array = PackedFloat32Array()
var _effect_seconds: PackedFloat32Array = PackedFloat32Array()
var _effect_length: PackedFloat32Array = PackedFloat32Array()
## The character an effect follows (a status), or null, and how far above it the effect sits.
var _effect_follow: Array[Node2D] = []
var _effect_rise: PackedFloat32Array = PackedFloat32Array()
var _next_effect: int = 0
## How many effects can show at once (`EffectSlots.DEFAULT` until the setting changes it; see
## `set_effect_slots`). Read only.
var effect_slots: int = EffectSlots.DEFAULT
var _reaction_heard: Dictionary = {}
## The reaction id each name label shows.
var _label_id: Array[StringName] = []
## Where, along which way and in whom the latest shot on a character struck, from
## `projectile_impact` (sent just before the damage), so the damage can aim its spray.
var _impact_target: int = 0
## The player whose shot it was: a contact hit (another player value) never takes it.
var _impact_player: int = 0
## The physics frame it was sent in: the damage follows at once, or the record is stale.
var _impact_frame: int = -1
## The latest hit kind (`hit_landed`): the target it was for, the kind, the frame, and whether a
## wizard hit themselves. `damage_dealt` follows at once, or the record is stale.
var _kind_target: int = 0
var _kind: StringName = &"shot"
var _kind_frame: int = -1
var _kind_own: bool = false
var _impact_at: Vector2 = Vector2.ZERO
var _impact_aim: Vector2 = Vector2.ZERO
## Death animations: sprites made once (drawn by the shot shader's dissolve), seconds left
## and seconds they started with (parallel arrays of GHOST_SLOTS).
var _ghosts: Array[Sprite2D] = []
var _ghost_left: PackedFloat32Array = PackedFloat32Array()
var _ghost_total: PackedFloat32Array = PackedFloat32Array()
var _next_ghost: int = 0
## Camera kick of casts (pixels), added to the shake.
var _kick: Vector2 = Vector2.ZERO
var _last_usec: int = 0
## The looks read from the carrier cards, by card id (see `_form_look`).
var _cast_look_cache: Dictionary = {}
var _impact_look_cache: Dictionary = {}


func _ready() -> void:
	_rng.seed = 1
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if registry == null:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if preset == null:
		preset = load("res://gameplay/feel/presets/punchy.tres") as FeelPresetScript
	_last_usec = Time.get_ticks_usec()
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = FLASH_SHADER
	for i in FORM_SLOTS:
		var form := Sprite2D.new()
		var material := ShaderMaterial.new()
		material.shader = CORE_SHADER
		form.material = material
		form.top_level = true
		form.visible = false
		form.z_index = FORM_Z
		form.centered = false
		form.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		form.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		add_child(form)
		_forms.append(form)
	_make_effects()
	_beam_line.resize(LIVE_BEAM_POINTS)
	for i in LIVE_BEAMS:
		var line := Line2D.new()
		var material := ShaderMaterial.new()
		material.shader = CORE_SHADER
		line.material = material
		line.top_level = true
		line.visible = false
		line.z_index = FORM_Z
		line.texture_mode = Line2D.LINE_TEXTURE_TILE
		line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.add_point(Vector2.ZERO)
		line.add_point(Vector2.ZERO)
		add_child(line)
		_live_beams.append(line)
	_form_left.resize(FORM_SLOTS)
	_form_total.resize(FORM_SLOTS)
	_form_body.resize(FORM_SLOTS)
	_form_length.resize(FORM_SLOTS)
	for i in REACTION_SLOTS:
		var label := Label.new()
		label.top_level = true
		label.visible = false
		label.z_index = 22
		label.add_theme_font_size_override("font_size", 8)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 3)
		label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(label)
		_labels.append(label)
		_label_id.append(&"")
	_label_left.resize(REACTION_SLOTS)
	_label_total.resize(REACTION_SLOTS)
	_label_start.resize(REACTION_SLOTS)
	for i in GHOST_SLOTS:
		var ghost := Sprite2D.new()
		ghost.top_level = true
		ghost.visible = false
		ghost.z_index = GHOST_Z
		var dissolve := ShaderMaterial.new()
		dissolve.shader = CORE_SHADER
		# The sprite path of the shot shader, as itself: a white core leaves its colours be.
		dissolve.set_shader_parameter(&"core_override", Color.WHITE)
		dissolve.set_shader_parameter(&"sprite_glow", 0.8)
		ghost.material = dissolve
		ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(ghost)
		_ghosts.append(ghost)
	_ghost_left.resize(GHOST_SLOTS)
	_ghost_total.resize(GHOST_SLOTS)
	for i in SOUND_VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	if events == null:
		push_warning("Feel: the Events autoload is missing, so there is no juice.")
		return
	events.damage_dealt.connect(_on_damage_dealt)
	events.hit_landed.connect(_on_hit_landed)
	events.heal_dealt.connect(_on_heal_dealt)
	events.enemy_died.connect(_on_enemy_died)
	events.player_downed.connect(_on_player_downed)
	events.spell_cast.connect(_on_spell_cast)
	events.wizard_cast.connect(_on_wizard_cast)
	events.projectile_impact.connect(_on_projectile_impact)
	events.form_shown.connect(_on_form_shown)
	events.reaction_triggered.connect(_on_reaction_triggered)
	events.discharge_arc.connect(_on_discharge_arc)
	events.status_applied.connect(_on_status_applied)
	events.effect_slots_changed.connect(_on_effect_slots_changed)
	events.caster_move_finished.connect(_on_caster_move_finished)
	events.projectile_expired.connect(_on_projectile_expired)
	if combat == null:
		combat = get_node_or_null("/root/Combat")
	if projectiles == null:
		projectiles = get_node_or_null("/root/Projectiles")
	if spells == null:
		spells = get_node_or_null("/root/Spells")
	if projectiles != null and "texture" in projectiles and projectiles.texture == null:
		projectiles.texture = preset.bolt_texture


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
func step(real_delta: float) -> void:
	_hit_effect = -1
	_hit_voice = -1
	_clock += real_delta
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
	_step_forms(real_delta)
	_step_effects(real_delta)
	_draw_live_beams()
	_step_labels(real_delta)
	_step_statuses(real_delta)
	_step_ghosts(real_delta)


## Flash and squash the hit sprites for `real_delta` seconds, and put back those done.
func _step_reactions(real_delta: float) -> void:
	var at: int = _react_sprites.size() - 1
	while at >= 0:
		_react_left[at] -= real_delta
		var sprite := instance_from_id(_react_sprites[at]) as Sprite2D
		var alive: bool = sprite != null
		if alive and sprite.scale != _react_written[at]:
			# The sprite's owner changed the scale (a dash look): that is the new base.
			_react_scale[at] = sprite.scale
		if _react_left[at] <= 0.0 or not alive:
			if alive:
				sprite.material = null
				sprite.scale = _react_scale[at]
			var last: int = _react_sprites.size() - 1
			_react_sprites[at] = _react_sprites[last]
			_react_scale[at] = _react_scale[last]
			_react_written[at] = _react_written[last]
			_react_left[at] = _react_left[last]
			_react_total[at] = _react_total[last]
			_react_amount[at] = _react_amount[last]
			_react_sprites.resize(last)
			_react_scale.resize(last)
			_react_written.resize(last)
			_react_left.resize(last)
			_react_total.resize(last)
			_react_amount.resize(last)
		else:
			var squash: float = _react_amount[at] * _react_left[at] / maxf(_react_total[at], 0.001)
			_react_written[at] = _react_scale[at] * Vector2(1.0 + squash, 1.0 - squash)
			sprite.scale = _react_written[at]
		at -= 1


## Dissolve the death animations: white-hot, then pixel by pixel gone.
func _step_ghosts(real_delta: float) -> void:
	for i in GHOST_SLOTS:
		if _ghost_left[i] <= 0.0:
			continue
		_ghost_left[i] -= real_delta
		var ghost: Sprite2D = _ghosts[i]
		if _ghost_left[i] <= 0.0:
			ghost.visible = false
			continue
		var progress: float = 1.0 - _ghost_left[i] / _ghost_total[i]
		(ghost.material as ShaderMaterial).set_shader_parameter(&"dissolve", maxf(progress, 0.01))


## Start a death animation from a copy of the dead node's `Sprite` child, where that
## sprite is. Nothing happens for a node without one.
func _start_ghost(dead: Node) -> void:
	if preset.death_anim_seconds <= 0.0 or dead == null or not is_instance_valid(dead):
		return
	var source := dead.get_node_or_null("Sprite") as Sprite2D
	if source == null or source.texture == null:
		return
	var slot: int = _next_ghost
	_next_ghost = (_next_ghost + 1) % GHOST_SLOTS
	var ghost: Sprite2D = _ghosts[slot]
	ghost.texture = source.texture
	ghost.hframes = source.hframes
	ghost.vframes = source.vframes
	ghost.frame = source.frame
	ghost.region_enabled = source.region_enabled
	ghost.region_rect = source.region_rect
	ghost.offset = source.offset
	ghost.flip_h = source.flip_h
	ghost.flip_v = source.flip_v
	ghost.centered = source.centered
	ghost.global_position = source.global_position
	ghost.global_rotation = source.global_rotation
	ghost.modulate = Color.WHITE
	# At the rest scale: a sprite killed mid-squash would otherwise pop.
	var rest: Vector2 = source.global_scale
	var at: int = _react_sprites.find(source.get_instance_id())
	if at >= 0 and source.scale.x != 0.0 and source.scale.y != 0.0:
		rest = rest / source.scale * _react_scale[at]
	ghost.scale = rest
	(ghost.material as ShaderMaterial).set_shader_parameter(&"dissolve", 0.01)
	ghost.visible = true
	_ghost_left[slot] = preset.death_anim_seconds
	_ghost_total[slot] = preset.death_anim_seconds


## Start the flash and squash of the hit node's `Sprite` child, if it has one.
func _react(target: Node) -> void:
	_start_reaction(target, preset.flash_seconds, preset.hit_squash, true)


## Squash the `Sprite` child of `target` by `amount` (positive: wide and low, negative:
## thin and tall) for `seconds`, with the white flash if `flash`. A hit replaces a
## running cast squash; a cast never replaces a running hit.
func _start_reaction(target: Node, seconds: float, amount: float, flash: bool) -> void:
	if seconds <= 0.0 or target == null or not is_instance_valid(target):
		return
	var sprite := target.get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	var at: int = _react_sprites.find(sprite.get_instance_id())
	if at >= 0:
		if not flash and sprite.material == _flash_material:
			return
		_react_left[at] = seconds
		_react_total[at] = seconds
		_react_amount[at] = amount
	elif _react_sprites.size() < REACT_SLOTS:
		_react_sprites.append(sprite.get_instance_id())
		_react_scale.append(sprite.scale)
		_react_written.append(sprite.scale)
		_react_left.append(seconds)
		_react_total.append(seconds)
		_react_amount.append(amount)
	else:
		return
	sprite.material = _flash_material if flash else null


## Sprites flashing right now (for tests).
func reacting_sprites() -> int:
	return _react_sprites.size()


## Death animations showing right now (for tests).
func live_ghosts() -> int:
	var count: int = 0
	for i in GHOST_SLOTS:
		if _ghost_left[i] > 0.0:
			count += 1
	return count


## The death animation sprite in `slot` (for tests).
func ghost(slot: int) -> Sprite2D:
	return _ghosts[slot]


## Current camera kick in pixels (for tests).
func kick() -> Vector2:
	return _kick


## Current shake strength, 0 to 1.
func trauma() -> float:
	return _trauma


func _on_damage_dealt(player: int, target: Node, amount: int, position: Vector2) -> void:
	_react(target)
	var aim: Vector2 = Vector2.ZERO
	var at: Vector2 = position
	var tint: Color = Color.WHITE
	var size: float = 1.0
	var colours: int = 0
	if target != null and is_instance_valid(target):
		tint = _target_tint(target)
		# A wizard's hit is in their own colours: white, their player's ramp.
		if target.is_in_group(&"players") and target.get("index") is int:
			colours = clampi(target.get("index") as int, 0, PLAYER_COLORS.size() - 1)
			tint = Color.WHITE
		# The shot that did this hit told us where it struck and which way it flew.
		if target.get_instance_id() == _impact_target and player == _impact_player and Engine.get_physics_frames() == _impact_frame:
			aim = _impact_aim
			at = _impact_at
			size = clampf(1.0 + float(amount - SPRAY_REF_DAMAGE) * preset.hit_spray_per_damage, SPRAY_MIN_SIZE, SPRAY_MAX_SIZE)
	_impact_target = 0
	# The kind of the hit came just before (`hit_landed`): its default stop, shake and sound.
	var stop: float = preset.hit_stop_seconds
	var shake: float = preset.hit_shake
	var sound: StringName = preset.hit_sound
	var own: bool = false
	if target != null and target.get_instance_id() == _kind_target and Engine.get_physics_frames() == _kind_frame:
		var look_kind: StringName = _kind if preset.kind_looks.has(_kind) else &"shot"
		var look: Dictionary = preset.kind_looks[look_kind] as Dictionary if preset.kind_looks.has(look_kind) else NO_LOOK
		stop *= look.get("stop", 1.0) as float
		shake *= look.get("shake", 1.0) as float
		sound = look.get("sound", preset.hit_sound) as StringName
		own = _kind_own
	_kind_target = 0
	_juice(position, stop, false, shake, sound, aim, tint, size, at, colours)
	if own:
		# Their own spell: a ring in its own colour on this frame, so it is never taken for an enemy's hit.
		_show_ring(position, preset.self_hit_color, preset.self_hit_seconds, preset.self_hit_size)
		_play(preset.self_hit_sound)


## The kind of the hit that `damage_dealt` announces next, and whether a wizard hit themselves.
func _on_hit_landed(player: int, target: Node, _amount: int, _position: Vector2, kind: StringName) -> void:
	if target == null:
		return
	_kind_target = target.get_instance_id()
	_kind = kind
	_kind_frame = Engine.get_physics_frames()
	_kind_own = kind != &"heal" and kind != &"status" and target.is_in_group(&"players") and target.get("index") == player


## A heal: a soft ring in green on the wizard, with no stop and no shake.
func _on_heal_dealt(_player: int, _target: Node, _amount: int, position: Vector2) -> void:
	_show_ring(position, preset.heal_color, preset.heal_seconds, preset.heal_size)
	_play(preset.heal_sound)


## A ring that flashes out from `position` in exactly `tint`, `size` as wide as the old ring
## art (32 px), for `seconds`.
func _show_ring(position: Vector2, tint: Color, seconds: float, size: float) -> void:
	show_effect(KIND_RING_OUT, position, Vector2.RIGHT, tint, 0, EXACT, clampi(roundi(size * 1.6), 1, 15), seconds)


## A line of text rising from `position` for `seconds`, in a label slot of the reactions.
func _show_note(text: String, position: Vector2, tint: Color, seconds: float) -> void:
	var slot: int = _next_reaction
	_next_reaction = (_next_reaction + 1) % REACTION_SLOTS
	var label: Label = _labels[slot]
	label.text = text
	label.modulate = tint
	_label_start[slot] = position + Vector2(-label.get_minimum_size().x * 0.5, -22.0)
	label.global_position = _label_start[slot]
	label.visible = true
	_label_left[slot] = seconds
	_label_total[slot] = seconds
	_label_id[slot] = &"note"


## An element reaction fired at `position`: a puff and a ring in the reaction's colour, its
## name rising from the spot, a little shake and the sound `reaction_<id>`. The same for every
## player; it changes nothing in the fight.
func _on_reaction_triggered(_player: int, reaction_id: StringName, position: Vector2) -> void:
	var tint: Color = preset.reaction_colors.get(reaction_id, Color.WHITE) as Color
	var power: float = preset.reaction_power.get(reaction_id, 1.0) as float
	var slot: int = _next_reaction
	_next_reaction = (_next_reaction + 1) % REACTION_SLOTS
	# A puff and a ring in the reaction's own colour, bigger for a stronger reaction.
	show_effect(KIND_PUFF, position, Vector2.RIGHT, tint, 0, EXACT, clampi(roundi(preset.reaction_burst_size * power), 1, 15), preset.reaction_seconds * 2.0)
	_show_ring(position, tint, preset.reaction_seconds * 1.6, preset.reaction_ring_size * power * 2.0)
	if not _reaction_names.has(reaction_id):
		_reaction_names[reaction_id] = String(reaction_id).capitalize()
		_reaction_sounds[reaction_id] = StringName(preset.reaction_sound_prefix + String(reaction_id))
	if not _label_showing(reaction_id, position):
		var label: Label = _labels[slot]
		var shown: String = _reaction_names[reaction_id] as String
		if label.text != shown:
			label.text = shown
		label.modulate = tint
		_label_start[slot] = position + Vector2(-label.get_minimum_size().x * 0.5, -18.0)
		label.global_position = _label_start[slot]
		label.visible = true
		_label_left[slot] = preset.reaction_seconds * 3.0
		_label_total[slot] = 0.0
		_label_id[slot] = reaction_id
	if _clock - (_reaction_heard.get(reaction_id, -REACTION_REPEAT) as float) < REACTION_REPEAT:
		return
	_reaction_heard[reaction_id] = _clock
	# The hit-stop is longer than a death's and, like a death's, ignores the rest after a stop.
	var stop: float = preset.reaction_stop_seconds * power
	if stop > stop_left:
		stop_left = stop
		_set_time_scale(preset.hit_stop_scale)
	if shake_enabled:
		_refresh_camera()
		_trauma = minf(_trauma + preset.reaction_shake * power, 1.0)
	_play(_reaction_sounds[reaction_id] as StringName)


## A discharge jumped from `from` to `to`: a jagged line of lightning between them, re-rolled
## as it flickers, that burns out (an effect, KIND_ARC), in the discharge's colour.
func _on_discharge_arc(_player: int, from: Vector2, to: Vector2) -> void:
	if preset.arc_seconds <= 0.0 or from.is_equal_approx(to):
		return
	var tint: Color = preset.reaction_colors.get(&"discharge", Color.WHITE) as Color
	show_effect(KIND_ARC, from, from.direction_to(to), tint, 0, EXACT, 1, preset.arc_seconds, from.distance_to(to))


## Discharge arcs showing right now (for tests).
func live_arcs() -> int:
	return effects_of(KIND_ARC)


## A character got a status: show it until combat says it has ended.
func _on_status_applied(_player: int, target: Node, _status_id: StringName) -> void:
	if target == null or not is_instance_valid(target) or combat == null:
		return
	var id: int = target.get_instance_id()
	var known: int = _status_enemies.find(id)
	if known >= 0:
		# A new status on a shown character (a chill that froze it) changes the look at once.
		_status_shown[known] = _status_of(target)
		_pose_status(known)
		return
	if not target is Node2D or _status_enemies.size() >= STATUS_SLOTS:
		return
	_status_enemies.append(id)
	_status_effect.append(-1)
	_status_age.append(0.0)
	_status_shown.append(_status_of(target))
	_status_next_poll.append(STATUS_POLL)
	_pose_status(_status_enemies.size() - 1)


## Read the statuses now and then; end the effect of a status that ended.
func _step_statuses(real_delta: float) -> void:
	var at: int = _status_enemies.size() - 1
	while at >= 0:
		_status_age[at] += real_delta
		var enemy := instance_from_id(_status_enemies[at]) as Node
		var keep: bool = enemy != null and combat != null
		if keep:
			if _status_age[at] >= _status_next_poll[at]:
				_status_next_poll[at] = _status_age[at] + STATUS_POLL
				var shown: StringName = _status_of(enemy)
				if shown != _status_shown[at]:
					_status_shown[at] = shown
					_end_status_effect(at)
			keep = _status_shown[at] != &""
		if keep:
			_pose_status(at)
		else:
			_end_status_effect(at)
			var last: int = _status_enemies.size() - 1
			_status_enemies[at] = _status_enemies[last]
			_status_effect[at] = _status_effect[last]
			_status_age[at] = _status_age[last]
			_status_shown[at] = _status_shown[last]
			_status_next_poll[at] = _status_next_poll[last]
			_status_enemies.resize(last)
			_status_effect.resize(last)
			_status_age.resize(last)
			_status_shown.resize(last)
			_status_next_poll.resize(last)
		at -= 1


## The status to show on `enemy` (the first of `status_order` it has), or empty for none.
func _status_of(enemy: Node) -> StringName:
	if not is_instance_valid(enemy):
		return &""
	for id in preset.status_order:
		if (combat.call("status_left", enemy, id) as float) > 0.0:
			return id
	return &""


## Keep status `at` shown: an effect that follows its character, its look's particles round it
## and a glow in its colour (`status_looks`: `color`, `look`), started again if a crowd of other
## effects took its slot. Hidden while the character's sprite is.
func _pose_status(at: int) -> void:
	var enemy := instance_from_id(_status_enemies[at]) as Node2D
	var look: Dictionary = preset.status_looks.get(_status_shown[at], {}) as Dictionary
	var sprite: CanvasItem = null
	if enemy != null:
		sprite = enemy.get_node_or_null("Sprite") as CanvasItem
	if enemy == null or look.is_empty() or (sprite != null and not sprite.is_visible_in_tree()):
		_end_status_effect(at)
		return
	var slot: int = _status_effect[at]
	if slot >= 0 and slot < effect_slots and _effect_seconds[slot] > 0.0 and _effect_follow[slot] == enemy:
		return
	var kinds: int = look.get("look", 0) as int
	var bits: int = ProjectileManagerScript.pack_look(PackedInt32Array([kinds])) if kinds > 0 else 0
	var tint: Color = look.get("color", Color.WHITE) as Color
	_status_effect[at] = show_effect(KIND_STATUS, enemy.global_position, Vector2.RIGHT, tint, 0, bits | EXACT, STATUS_ZOOM, FOREVER, 0.0, enemy)


## End the effect that shows status `at`, if it still shows it.
func _end_status_effect(at: int) -> void:
	var slot: int = _status_effect[at]
	var enemy := instance_from_id(_status_enemies[at]) as Node2D
	if slot >= 0 and slot < effect_slots and _effect_kind[slot] == KIND_STATUS and _effect_follow[slot] == enemy:
		_effect_seconds[slot] = 0.0
		_effect_follow[slot] = null
	_status_effect[at] = -1


## The status shown on `enemy` (empty for none), for tests.
func status_shown(enemy: Node) -> StringName:
	var at: int = _status_enemies.find(enemy.get_instance_id())
	if at < 0 or _status_effect[at] < 0:
		return &""
	return _status_shown[at]


## Statuses showing right now (for tests).
func live_statuses() -> int:
	return effects_of(KIND_STATUS)


## Is the name of `reaction_id` already rising near `position`?
func _label_showing(reaction_id: StringName, position: Vector2) -> bool:
	for i in REACTION_SLOTS:
		if _label_left[i] > 0.0 and _label_id[i] == reaction_id \
				and _label_start[i].distance_to(position) < REACTION_LABEL_NEAR:
			return true
	return false


## Raise and fade the reaction names.
func _step_labels(real_delta: float) -> void:
	for i in REACTION_SLOTS:
		if _label_left[i] <= 0.0:
			continue
		_label_left[i] -= real_delta
		var label: Label = _labels[i]
		if _label_left[i] <= 0.0:
			label.visible = false
			continue
		var total: float = _label_total[i] if _label_total[i] > 0.0 else preset.reaction_seconds * 3.0
		var t: float = _label_left[i] / total
		label.global_position = _label_start[i] + Vector2(0.0, -REACTION_RISE * (1.0 - t))
		label.modulate.a = minf(t * 2.0, 1.0)


## Reaction names showing right now (for tests).
func live_labels() -> int:
	var count: int = 0
	for i in REACTION_SLOTS:
		if _label_left[i] > 0.0:
			count += 1
	return count


## A shot struck. On a character, remember how, for the damage event that follows at once;
## on a wall or pillar (`target` is null), show the impact.
func _on_projectile_impact(player: int, target: Node, position: Vector2, direction: Vector2) -> void:
	if target != null:
		_impact_target = target.get_instance_id()
		_impact_player = player
		_impact_frame = Engine.get_physics_frames()
		_impact_at = position
		_impact_aim = direction
		_show_impact(player, position, direction)
		return
	# Stone chips knocked back off the surface.
	if particles_enabled:
		show_effect(KIND_CHIPS, position, -direction, Color.WHITE, 0, 0, clampi(roundi(preset.wall_chip_size), 1, 3), CHIPS_SECONDS)
	_show_impact(player, position, direction)


## A dash landed: a ring in the player's colours where the wizard stopped; lightning arcs from
## where it left, and an infused dash lands in a small flare of its element (the mockup's).
func _on_caster_move_finished(player: int, mode: StringName, position: Vector2, _tag: int) -> void:
	if mode != &"dash" or player < EventsScript.NO_PLAYER or player >= PLAYER_COLORS.size() or not position.is_finite():
		return
	var who: int = player if player >= 0 else ENEMY_FORMS
	var look: int = _dash_look[who]
	show_effect(KIND_RING_OUT, position, Vector2.RIGHT, Color.WHITE, player, 0, 1, RING_SECONDS)
	var from: Vector2 = _dash_from[who]
	if from.is_finite() and (look & (1 << (ProjectileManagerScript.LOOK_SPARKS - 1))) != 0 and from.distance_to(position) > 4.0:
		show_effect(KIND_ARC, from, from.direction_to(position), _dash_core[who], player, look, 1, RING_SECONDS, from.distance_to(position))
	if look != 0:
		show_effect(KIND_BURST, position, from.direction_to(position) if from.is_finite() else Vector2.RIGHT, _dash_core[who], player, look, POP_ZOOM, POP_SECONDS)
	_dash_from[who] = Vector2.INF


## A bolt or orbit shot whose life ran out goes off in a small pop of its own colours where it
## was (the mockup's); one that ended on a wall already showed its impact, and a rune's going off
## is its own burst.
func _on_projectile_expired(player: int, position: Vector2, _tag: int) -> void:
	if projectiles == null or not position.is_finite() or player < EventsScript.NO_PLAYER or player >= PLAYER_COLORS.size():
		return
	if bool(projectiles.get("expired_on_wall")) or not ("impact_form" in projectiles):
		return
	var form: StringName = projectiles.impact_form as StringName
	if form != &"bolt" and form != &"orbit":
		return
	var heading: Vector2 = projectiles.get("impact_heading") as Vector2 if "impact_heading" in projectiles else Vector2.RIGHT
	show_effect(KIND_BURST, position, heading, projectiles.impact_core as Color, player, projectiles.impact_look as int, POP_ZOOM, POP_SECONDS)


## The payoff of a shot: a flare in the shot's colour, shaped by the form of the shot itself
## (the projectile manager's `impact_form` while the impact is sent; a rune goes off, a nova's
## adds a ring). An enemy's shot (NO_PLAYER) lands the same way, in the enemy ramp where a
## player's colour would show (staffs F7: one look for every spell).
func _show_impact(player: int, position: Vector2, direction: Vector2) -> void:
	var form: StringName = &""
	if projectiles != null and "impact_form" in projectiles:
		form = projectiles.impact_form as StringName
	var look: Dictionary = _form_look(form, false)
	var size: float = look.get("size", preset.wall_spark_size) as float
	var core: Color = Color.WHITE
	var bits: int = 0
	if projectiles != null and "impact_core" in projectiles:
		core = projectiles.impact_core as Color
		bits = projectiles.impact_look as int
	if form == &"rune":
		show_effect(KIND_RUNE_BURST, position, Vector2.RIGHT, core, player, bits, 3, RUNE_BURST_SECONDS)
		return
	var zoom: int = clampi(roundi(size * 2.0), 1, 3)
	show_effect(KIND_BURST, position, direction, core, player, bits, zoom, BURST_SECONDS)
	if look.get("ring", false) as bool:
		show_effect(KIND_RING_OUT, position, direction, core, player, 0, 1, RING_SECONDS)


## Make the effect batch (see "Effects" above): one MultiMesh of `effect_slots` quads in world
## space, drawn by the shot shader, and the arrays behind it.
func _make_effects() -> void:
	_effect_node = MultiMeshInstance2D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.visible_instance_count = 0
	# Effects show anywhere in the world; there is no room to fit a box to.
	multimesh.custom_aabb = AABB(Vector3(-100000.0, -100000.0, -1.0), Vector3(200000.0, 200000.0, 2.0))
	_effect_node.multimesh = multimesh
	var material := ShaderMaterial.new()
	material.shader = CORE_SHADER
	_effect_node.material = material
	_effect_node.top_level = true
	_effect_node.z_index = EFFECT_Z
	add_child(_effect_node)
	_size_effects(effect_slots)


## Make room for `slots` effects: the MultiMesh, its buffer and the arrays behind it. The
## effects showing end (a setting changed in a menu: nobody misses a tenth of a second of sparks).
func _size_effects(slots: int) -> void:
	effect_slots = slots
	_effect_node.multimesh.visible_instance_count = 0
	_effect_node.multimesh.instance_count = slots
	_effect_buffer.resize(slots * EFFECT_STRIDE)
	_effect_kind.resize(slots)
	_effect_at.resize(slots)
	_effect_dir.resize(slots)
	_effect_core.resize(slots)
	_effect_player.resize(slots)
	_effect_zoom.resize(slots)
	_effect_look.resize(slots)
	_effect_age.resize(slots)
	_effect_seconds.resize(slots)
	_effect_seconds.fill(0.0)
	_effect_length.resize(slots)
	_effect_follow.resize(slots)
	_effect_follow.fill(null)
	_effect_rise.resize(slots)
	_next_effect = 0
	# The statuses shown lost their effects; the next step shows them again.
	_status_effect.fill(-1)


## The setting: how many effects can show at once, snapped by `EffectSlots.snap`. Returns the
## number taken.
func set_effect_slots(slots: int) -> int:
	var snapped: int = EffectSlots.snap(slots)
	if _effect_node == null:
		effect_slots = snapped
	elif snapped != effect_slots:
		_size_effects(snapped)
	return effect_slots


func _on_effect_slots_changed(slots: int) -> void:
	set_effect_slots(slots)


## Show an effect of `kind` (KIND_BURST to KIND_CAST) at `at`, aimed along `dir`, in the ramp of
## `core` (white: `player`'s colours, the enemy ramp for NO_PLAYER) with the particles of the packed `look`, at `zoom`, for
## `seconds`. A dash or an arc runs `length` pixels from `at` along `dir` (its zoom is then the
## length). An effect given a `follow` node moves with it (a status), and ends when it is gone.
## It takes the next slot, the oldest effect when they are all busy, and returns it (-1 for
## none).
func show_effect(kind: int, at: Vector2, dir: Vector2, core: Color, player: int, look: int, zoom: int, seconds: float, length: float = 0.0, follow: Node2D = null) -> int:
	if _effect_node == null or not at.is_finite() or player < EventsScript.NO_PLAYER or player >= PLAYER_COLORS.size():
		return -1
	var slot: int = _next_effect
	_next_effect = (_next_effect + 1) % effect_slots
	_effect_kind[slot] = kind
	_effect_at[slot] = at.round()
	_effect_dir[slot] = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	_effect_core[slot] = core
	_effect_player[slot] = player
	_effect_zoom[slot] = clampi(zoom, 1, 15)
	_effect_look[slot] = look
	_effect_age[slot] = 0.0
	_effect_seconds[slot] = maxf(seconds, 0.01)
	_effect_length[slot] = 0.0
	_effect_follow[slot] = follow
	_effect_rise[slot] = STATUS_RISE if follow != null else 0.0
	if kind == KIND_DASH or kind == KIND_ARC:
		var steps: int = clampi(roundi(length / 4.0), 1, roundi(DASH_LONGEST / 4.0))
		_effect_zoom[slot] = steps
		_effect_length[slot] = steps * 4.0
	return slot


## Age the effects by `real_delta` and write the live ones into the batch, oldest first.
func _step_effects(real_delta: float) -> void:
	if _effect_node == null:
		return
	(_effect_node.material as ShaderMaterial).set_shader_parameter(&"sim_time", _clock)
	var out: int = 0
	for n in effect_slots:
		var slot: int = (_next_effect + n) % effect_slots
		if _effect_seconds[slot] <= 0.0:
			continue
		_effect_age[slot] += real_delta
		var through: float = _effect_age[slot] / _effect_seconds[slot]
		var follow: Node2D = _effect_follow[slot]
		if follow != null and not is_instance_valid(follow):
			through = 1.0
		if through >= 1.0:
			_effect_seconds[slot] = 0.0
			_effect_follow[slot] = null
			continue
		if follow != null:
			_effect_at[slot] = (follow.global_position + Vector2(0.0, -_effect_rise[slot])).round()
		var i: int = out * EFFECT_STRIDE
		var d: float = EFFECT_GRID * _effect_zoom[slot]
		var along: float = d
		var dir: Vector2 = _effect_dir[slot]
		var at: Vector2 = _effect_at[slot]
		if _effect_length[slot] > 0.0:
			# A dash or an arc: from where it starts along its way, a margin past each end.
			var arc: bool = _effect_kind[slot] == KIND_ARC
			d = ARC_ACROSS if arc else DASH_ACROSS
			along = _effect_length[slot] + 2.0 * (ARC_MARGIN if arc else DASH_MARGIN)
			at += dir * _effect_length[slot] * 0.5
		_effect_buffer[i] = dir.x * along
		_effect_buffer[i + 1] = dir.y * d
		_effect_buffer[i + 2] = 0.0
		_effect_buffer[i + 3] = at.x
		_effect_buffer[i + 4] = dir.y * along
		_effect_buffer[i + 5] = -dir.x * d
		_effect_buffer[i + 6] = 0.0
		_effect_buffer[i + 7] = at.y
		var data: Color = ProjectileManagerScript.look_color(_effect_player[slot], _effect_zoom[slot], _effect_look[slot])
		_effect_buffer[i + 8] = data.r
		_effect_buffer[i + 9] = data.g
		_effect_buffer[i + 10] = data.b
		_effect_buffer[i + 11] = data.a
		var core: Color = _effect_core[slot]
		_effect_buffer[i + 12] = core.r
		_effect_buffer[i + 13] = core.g
		_effect_buffer[i + 14] = core.b
		_effect_buffer[i + 15] = 1.0 - (float(_effect_kind[slot]) + EFFECT_FROM + EFFECT_SPAN * through) / 16.0
		out += 1
	if out > 0:
		_effect_node.multimesh.buffer = _effect_buffer
	_effect_node.multimesh.visible_instance_count = out


## How many effects are showing (for tests and the sheets).
func live_effects() -> int:
	var live: int = 0
	for slot in effect_slots:
		if _effect_seconds[slot] > 0.0:
			live += 1
	return live


## How many live effects are of `kind`, and (with `player` 0-3) of that player.
func effects_of(kind: int, player: int = -1) -> int:
	var found: int = 0
	for slot in effect_slots:
		if _effect_seconds[slot] > 0.0 and _effect_kind[slot] == kind and (player < 0 or _effect_player[slot] == player):
			found += 1
	return found


## The core colour and look of the newest live effect of `kind` (for tests): [core, look].
func effect_dress(kind: int) -> Array:
	for n in effect_slots:
		var slot: int = (_next_effect - 1 - n + effect_slots) % effect_slots
		if _effect_seconds[slot] > 0.0 and _effect_kind[slot] == kind:
			return [_effect_core[slot], _effect_look[slot]]
	return []


## The newest live effect of `kind` (for tests): its place, way, core colour, player, zoom and
## look, or an empty dictionary when none shows.
func effect_info(kind: int) -> Dictionary:
	for n in effect_slots:
		var slot: int = (_next_effect - 1 - n + effect_slots) % effect_slots
		if _effect_seconds[slot] > 0.0 and _effect_kind[slot] == kind:
			return {"at": _effect_at[slot], "dir": _effect_dir[slot], "core": _effect_core[slot], "player": _effect_player[slot],
					"zoom": _effect_zoom[slot], "look": _effect_look[slot], "seconds": _effect_seconds[slot]}
	return {}


## The colour of what was hit: a wizard's own colour, else the enemy ember.
func _target_tint(target: Node) -> Color:
	if target.is_in_group(&"players"):
		var index: Variant = target.get("index")
		if index is int:
			return PLAYER_COLORS[clampi(index as int, 0, PLAYER_COLORS.size() - 1)]
	return preset.enemy_hit_color


## The colour of a shot: its player's colour, the enemy ramp's (Blight ochre) for an enemy's.
func _shot_color(player: int) -> Color:
	if player >= 0 and player < PLAYER_COLORS.size():
		return PLAYER_COLORS[player]
	return ProjectileManagerScript.ENEMY_COLOR


func _on_enemy_died(_player: int, enemy: Node, position: Vector2) -> void:
	_start_ghost(enemy)
	if preset.death_puff_seconds > 0.0:
		_show_ring(position, BONE_LIGHT, preset.death_puff_seconds, preset.death_puff_size)
	_juice(position, preset.death_stop_seconds, true, preset.death_shake, preset.death_sound)


## The look a carrier's card brings (`FormBase.cast_look` or `impact_look`), empty when the card
## has none or there is no registry. Read once per card id, then kept: a cast allocates nothing.
func _form_look(form: StringName, cast: bool) -> Dictionary:
	var cache: Dictionary = _cast_look_cache if cast else _impact_look_cache
	var cached: Variant = cache.get(form)
	if cached != null:
		return cached as Dictionary
	var look: Dictionary = {}
	# No registry yet, or no form id yet: answer plain but keep nothing, so a later card still counts.
	if registry == null or form == &"":
		return look
	var card: Resource = registry.get_resource(&"spells", form)
	if card is FormBase:
		look = ((card as FormBase).cast_look if cast else (card as FormBase).impact_look).duplicate()
	cache[form] = look
	return look


func _on_spell_cast(player: int, spell_id: StringName, origin: Vector2, direction: Vector2) -> void:
	if player < 0 or player >= PLAYER_COLORS.size():
		return
	var slot: int = player
	# Each form has its own flash on the wizard: a bolt a short streak along the aim, a beam a
	# long thin flare, a nova a wide burst, a rune and an orbit gather in (the build-up).
	var look: Dictionary = _form_look(spell_id, true)
	var aim: Vector2 = direction if direction != Vector2.ZERO else Vector2.RIGHT
	show_effect(KIND_CAST, origin, aim, Color.WHITE, slot, 0, 1, CAST_SECONDS)
	if look.get("ring", false) as bool:
		var gather: bool = (look.get("grow", 0.5) as float) < 0.0
		show_effect(KIND_RING_IN if gather else KIND_RING_OUT, origin, aim, Color.WHITE, slot, 0, 1, RING_SECONDS)
	if shake_enabled and direction != Vector2.ZERO:
		_refresh_camera()
		_kick = (_kick - direction.normalized() * preset.cast_kick_pixels).limit_length(MAX_KICK_PIXELS)


## A beam (drawn by the shot shader's beam mode in the element's ramp), a nova's ring, a dash and
## a rain's marker (effects), each with the cast's cards. An enemy's (NO_PLAYER) look the same,
## in the enemy ramp (staffs F7). A rain's marker is a ring closing on the point for as long as
## the rain takes to fall (`length` seconds), so nobody is hit by a rain they could not see.
func _on_form_shown(player: int, form: StringName, origin: Vector2, direction: Vector2, length: float, tint: Color, look: int) -> void:
	if player < EventsScript.NO_PLAYER or player >= PLAYER_COLORS.size() or not origin.is_finite():
		return
	if form == &"rain":
		if length > 0.0:
			show_effect(KIND_RING_IN, origin, Vector2.RIGHT, tint, player, look, RAIN_MARK_ZOOM, length)
		return
	if form == &"nova":
		if preset.nova_seconds > 0.0:
			var zoom: int = clampi(roundi(preset.nova_ring_size / 20.0), 1, 15)
			show_effect(KIND_RING_OUT, origin, Vector2.RIGHT, tint, player, look, zoom, preset.nova_seconds)
		return
	if form == &"dash":
		# Only its dust here: the wizard picks its way (where it walks), so its streaks and cards
		# are its trail, and the ring comes where it lands.
		var who: int = player if player >= 0 else ENEMY_FORMS
		_dash_from[who] = origin
		_dash_core[who] = tint
		_dash_look[who] = look
		if length > 0.0 and direction != Vector2.ZERO:
			show_effect(KIND_DASH, origin, Vector2.RIGHT, tint, player, look, 1, DASH_SECONDS, 4.0)
		return
	if form != &"beam" or length <= 0.0 or direction == Vector2.ZERO:
		return
	var seconds: float = preset.beam_seconds
	if seconds <= 0.0:
		return
	# Each player reuses only their own oldest slots, so nobody's beams push out another's; the
	# enemies share one player's worth, so a crowd of them never takes a player's.
	var who: int = player if player >= 0 else ENEMY_FORMS
	var slot: int = who * FORMS_PER_PLAYER + _next_form[who]
	_next_form[who] = (_next_form[who] + 1) % FORMS_PER_PLAYER
	var sprite: Sprite2D = _forms[slot]
	sprite.global_position = origin
	sprite.texture = preset.beam_texture
	sprite.centered = false
	# BEAM_LEAD past each end, so the flares are whole.
	sprite.offset = Vector2(-BEAM_LEAD, -16.0)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0.0, 0.0, length + 2.0 * BEAM_LEAD, 32.0)
	sprite.rotation = direction.angle()
	sprite.scale = Vector2.ONE
	var material: ShaderMaterial = sprite.material as ShaderMaterial
	material.set_shader_parameter(&"core_override", Color(tint.r, tint.g, tint.b, 1.0))
	material.set_shader_parameter(&"beam_mode", 2)
	material.set_shader_parameter(&"beam_length", length)
	material.set_shader_parameter(&"beam_lead", BEAM_LEAD)
	material.set_shader_parameter(&"beam_start", origin)
	material.set_shader_parameter(&"beam_end", origin + direction.normalized() * length)
	material.set_shader_parameter(&"beam_end_dir", direction.normalized())
	material.set_shader_parameter(&"beam_player", player)
	material.set_shader_parameter(&"beam_look", look)
	material.set_shader_parameter(&"beam_glow", preset.beam_alpha)
	var body: Color = Color.WHITE
	if projectiles != null and projectiles.has_method("tint_of"):
		body = projectiles.call("tint_of", player) as Color
	_form_body[slot] = body
	_form_left[slot] = seconds
	_form_total[slot] = seconds
	sprite.visible = true
	_pose_form(slot, 1.0)


## Fade the beams.
func _step_forms(real_delta: float) -> void:
	for i in FORM_SLOTS:
		if _form_left[i] <= 0.0:
			continue
		_form_left[i] -= real_delta
		if _form_left[i] <= 0.0:
			_forms[i].visible = false
			continue
		_pose_form(i, _form_left[i] / _form_total[i])


## Draw every live beam where it is this frame: along its curve, as far as it got, in its owner's
## tint with its element's colour in the core. It flares on each hit, flickers a little and fades
## over the last quarter of its life. Nothing is allocated.
func _draw_live_beams() -> void:
	var count: int = 0
	if spells != null and spells.has_method("beam_slots"):
		count = mini(int(spells.call("beam_slots")), LIVE_BEAMS)
	for i in LIVE_BEAMS:
		var line: Line2D = _live_beams[i]
		if i >= count or not bool(spells.call("beam_on", i)):
			if line.visible:
				line.visible = false
			continue
		var points: int = mini(int(spells.call("beam_point_count", i)), LIVE_BEAM_POINTS)
		var reach: float = spells.call("beam_reach", i)
		var origin: Vector2 = spells.call("beam_point", i, 0) if points > 0 else Vector2.INF
		if reach <= 0.0 or points < 2 or not origin.is_finite():
			line.visible = false
			continue
		# Its path up to where it got: whole pieces, then the last one cut short.
		var walked: float = 0.0
		var prev: Vector2 = origin
		var used: int = 1
		_beam_line[0] = origin
		for n in range(1, points):
			var point: Vector2 = spells.call("beam_point", i, n)
			var piece: float = prev.distance_to(point)
			if walked + piece >= reach:
				_beam_line[used] = prev.move_toward(point, reach - walked)
				walked = reach
				used += 1
				break
			walked += piece
			_beam_line[used] = point
			used += 1
			prev = point
		# The line only changes its number of points when the path does. It reaches BEAM_LEAD past
		# each end, so the flares there are whole.
		while line.get_point_count() < used:
			line.add_point(Vector2.ZERO)
		while line.get_point_count() > used:
			line.remove_point(line.get_point_count() - 1)
		var start_dir: Vector2 = _beam_line[0].direction_to(_beam_line[1])
		var end_at: Vector2 = _beam_line[used - 1]
		var end_dir: Vector2 = _beam_line[used - 2].direction_to(end_at)
		for n in used:
			var point: Vector2 = _beam_line[n]
			if n == 0:
				point -= start_dir * BEAM_LEAD
			elif n == used - 1:
				point += end_dir * BEAM_LEAD
			line.set_point_position(n, point)
		var since: float = spells.call("beam_since_hit", i)
		var left: float = spells.call("beam_left", i)
		var fade: float = clampf(left * 4.0, 0.0, 1.0)
		var flare: float = 1.0 + preset.beam_flare * maxf(1.0 - since / maxf(preset.beam_seconds * preset.beam_flare_share, 0.001), 0.0)
		var flicker: float = 1.0 - preset.beam_flicker_depth * float(int(since * preset.beam_flicker_rate) % 2)
		# Drawn by the shader's beam mode across a fixed width; flare, flicker and fade swell and
		# dissolve its pixels instead of stretching them.
		line.width = BEAM_WIDTH
		line.texture = preset.beam_texture
		line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
		var player: int = spells.call("beam_player", i)
		var body: Color = Color.WHITE
		if projectiles != null and projectiles.has_method("tint_of"):
			body = projectiles.call("tint_of", player) as Color
		var tint: Color = spells.call("beam_tint", i)
		var material: ShaderMaterial = line.material as ShaderMaterial
		material.set_shader_parameter(&"core_override", Color(tint.r, tint.g, tint.b, 1.0))
		material.set_shader_parameter(&"body_tint", Color(body.r, body.g, body.b, fade * preset.beam_alpha))
		material.set_shader_parameter(&"beam_mode", 1)
		material.set_shader_parameter(&"beam_length", walked)
		material.set_shader_parameter(&"beam_lead", BEAM_LEAD)
		material.set_shader_parameter(&"beam_start", origin)
		material.set_shader_parameter(&"beam_end", end_at)
		material.set_shader_parameter(&"beam_end_dir", end_dir)
		material.set_shader_parameter(&"sim_time", _clock)
		material.set_shader_parameter(&"beam_width", BEAM_WIDTH)
		material.set_shader_parameter(&"beam_player", player)
		material.set_shader_parameter(&"beam_look", int(spells.call("beam_look", i)) if spells.has_method("beam_look") else 0)
		material.set_shader_parameter(&"beam_fade", fade)
		material.set_shader_parameter(&"beam_swell", maxf(fade, 0.35) * flare * flicker)
		material.set_shader_parameter(&"beam_glow", preset.beam_alpha)
		line.visible = true


## Show beam `slot` at `t` (1 just shown, 0 gone): its rim and glow swell for its first moments
## (the payoff), then thin and flicker, and it dissolves into pixels (`beam_swell`, `beam_fade`).
func _pose_form(slot: int, t: float) -> void:
	var sprite: Sprite2D = _forms[slot]
	var body: Color = _form_body[slot]
	var age: float = 1.0 - t
	var material: ShaderMaterial = sprite.material as ShaderMaterial
	material.set_shader_parameter(&"sim_time", _clock)
	material.set_shader_parameter(&"body_tint", Color(body.r, body.g, body.b, t * preset.beam_alpha))
	var flare: float = 1.0 + preset.beam_flare * maxf(1.0 - age / preset.beam_flare_share, 0.0)
	var step: int = int(age * _form_total[slot] * preset.beam_flicker_rate)
	var flicker: float = 1.0 - preset.beam_flicker_depth * float(step % 2)
	material.set_shader_parameter(&"beam_swell", t * flare * flicker)
	material.set_shader_parameter(&"beam_fade", t)


func _on_wizard_cast(_player: int, wizard: Node) -> void:
	# The dash look owns the sprite scale while dodging; a squash would fight it.
	if wizard != null and wizard.has_method("is_dashing") and wizard.call("is_dashing"):
		return
	_start_reaction(wizard, preset.cast_squash_seconds, -preset.cast_squash, false)


func _on_player_downed(player: int) -> void:
	# The event names no position, so a downed wizard gets stop, shake and sound only...
	_juice(Vector2.INF, preset.death_stop_seconds, true, preset.downed_shake, preset.downed_sound)
	# ...and, when their own (or a teammate's) spell did it, a note over them saying so.
	if combat == null or not combat.has_method("downed_note"):
		return
	var note: String = combat.downed_note(player) as String
	var wizard: Node2D = combat.wizard_of(player) as Node2D
	if note.is_empty() or wizard == null:
		return
	_show_note(note, wizard.global_position if wizard.is_inside_tree() else wizard.position, _shot_color(player), preset.downed_note_seconds)


## `strong` is a death or a downed wizard: it ignores the rest after a hit-stop and
## gets the bigger puff.
## A plain hit with an `aim` (the way the shot flew) sprays along it, `size` times as big,
## from `at`, in the ramp of `tint` (white: `player`'s colours); without one it is a puff at
## `position`.
func _juice(position: Vector2, stop: float, strong: bool, shake: float, sound: StringName, aim: Vector2 = Vector2.ZERO, tint: Color = Color.WHITE, size: float = 1.0, at: Vector2 = Vector2.INF, player: int = 0) -> void:
	# A plain hit only starts a stop when none runs and the rest is over (or a stream
	# of hits would extend it for ever); a strong one may lengthen a shorter stop.
	if stop > stop_left and (strong or (stop_left <= 0.0 and rest_left <= 0.0)):
		stop_left = stop
		_set_time_scale(preset.hit_stop_scale)
	if shake_enabled:
		_refresh_camera()
		_trauma = minf(_trauma + shake, 1.0)
	var upgraded: bool = false
	if position != Vector2.INF and particles_enabled:
		if strong:
			upgraded = _burst_death(position)
		else:
			var from: Vector2 = position if at == Vector2.INF else at
			var zoom: int = clampi(roundi(size), 1, 3)
			if aim != Vector2.ZERO:
				_hit_effect = show_effect(KIND_SPRAY, from, aim, tint, player, 0, zoom, SPRAY_SECONDS)
			else:
				_hit_effect = show_effect(KIND_PUFF, from, Vector2.RIGHT, tint, player, 0, zoom, PUFF_SECONDS)
			_hit_position = position
	if upgraded and _hit_voice >= 0:
		_voices[_hit_voice].stop()
	var voice: int = _play(sound)
	if not strong:
		_hit_voice = voice


## A death puff: the killing blow's own spray turned into a bigger puff when it is at this
## spot (one slot, one sound), else a new puff in the enemy colour. Returns true when it
## upgraded the hit's effect (which then needs no second sound).
func _burst_death(position: Vector2) -> bool:
	var zoom: int = clampi(roundi(preset.death_particle_size), 1, 3)
	var slot: int = _hit_effect
	if slot >= 0 and _hit_position == position and _effect_seconds[slot] > 0.0:
		_effect_kind[slot] = KIND_PUFF
		_effect_zoom[slot] = zoom
		_effect_age[slot] = 0.0
		_effect_seconds[slot] = PUFF_SECONDS
		return true
	show_effect(KIND_PUFF, position, Vector2.RIGHT, preset.enemy_hit_color, 0, 0, zoom, PUFF_SECONDS)
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
