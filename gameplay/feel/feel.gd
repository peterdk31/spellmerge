extends Node
## Feel: juice on every hit. One autoload ("Feel") that only reacts to events:
## `damage_dealt`, `enemy_died` and `player_downed`. It never changes damage,
## health or who wins, and it sends no events.
##
##     Feel.shake_enabled = false     # the setting: no screen shake (the pause menu's "Screen shake" switch, saved by core/save)
##     Feel.preset = load("res://gameplay/feel/presets/punchy.tres")
##
## On a hit it does four things, all the same for every player:
## - hit-stop, a local stop (freezes in co-op): the attacker, the target and the shot of a hit
##   hold still for a few hundredths of a second while the rest of the game runs on. After a
##   plain hit's stop a body rests, and plain hits do not hold it again (a crowded fight must
##   not feel like lag); kills hold at once. Only a downed player and a boss kill drop
##   Engine.time_scale (real time); overlapping stops do not add up: the longest one wins.
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
## A deflected shot (`shot_deflected`) flashes big and white where it turned, in its new caster's
## colours; a swing's block (`shot_blocked` while the projectile manager's `impact_form` is
## `swing`) is a parry: a big four-point star in Spark gold and a local stop on the parrying actor
## (melee I5).
##
## Every hit body is read by its actor (`Actor.id`): its ramp (`Actors.ramp_of`) colours the hit
## (a hat ramp in its light shade, `ProjectileManager.ramp_light`; the enemy ramp in ember), and a
## hit whose caster is the hit actor itself is a self-hit.
##
## Effects (the glow look, 2026-10-27; the owner: "I only want the new style going forward"):
## every flare, spray, puff, ring, chip, arc and status is drawn by the shots' own shaders
## (core/projectiles: `shot_effect.gdshader` for the flares, kinds KIND_BURST to KIND_CHIPS;
## `shot_arc.gdshader` for KIND_ARC; `shot_status.gdshader` for KIND_STATUS), one MultiMesh each,
## sharing `effect_slots` (a setting: Settings, "Effect slots", through `effect_slots_changed`),
## each with the core colour and look of the shot it comes from (`impact_core`, `impact_look` of
## the projectile manager), so a frost bolt lands in frost flecks and a lightning one in sparks,
## all glowing. A new effect takes the oldest slot when they are all busy. How a caster's body
## moves when it casts is its carrier card's `staff_pose`, drawn by its look (ActorLook), not here.
## None of this touches the cast itself.
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
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
## The shot shaders Feel draws with (core/README.md, "The shot shaders"): beams; the effects'
## batches (flares, arcs, statuses); the sprite path of the death and afterimage copies.
const BEAM_SHADER: Shader = preload("res://core/projectiles/shot_beam.gdshader")
const EFFECT_SHADER: Shader = preload("res://core/projectiles/shot_effect.gdshader")
const ARC_SHADER: Shader = preload("res://core/projectiles/shot_arc.gdshader")
const STATUS_SHADER: Shader = preload("res://core/projectiles/shot_status.gdshader")
const BLAST_SHADER: Shader = preload("res://core/projectiles/shot_blast.gdshader")
const SPRITE_SHADER: Shader = preload("res://core/projectiles/shot_sprite.gdshader")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SwingTrailsScript := preload("res://gameplay/feel/swing_trails.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
## Beams and nova rings on screen per player: one cast makes at most 24 shots (the spell limit),
## so a split fan is drawn whole; past that the player's oldest slot is taken over.
const FORMS_PER_PLAYER: int = 24
## Four players' beam sprites and the enemies' (one share for every enemy caster, staffs F7).
const FORM_SLOTS: int = FORMS_PER_PLAYER * 5
## The share of the beam sprites every enemy's beam takes turns in.
const ENEMY_FORMS: int = 4
## Beams and rings draw above the room, under the shots (50) and the flashes (20).
const FORM_Z: int = 18
## Marks on the floor (a quake) draw just under the beams and rings, under the enemies (40).
const FLOOR_Z: int = FORM_Z - 1
## Live beams made at once (more are made when core/spells has more: no beam limit, owner
## 2026-10-29), and the most points of each one's drawn path (BEAM_POINTS in `shot_beam.gdshader`):
## a homing beam bends from target to target and a bouncing one turns at walls, so it is drawn
## along its path's points; a path with more keeps its ends and its sharpest turns and drops the
## points of its gentlest curves for its look (`_thin_beam`; its hits and turns are the runtime's,
## whole).
const LIVE_BEAM_POINTS: int = 80
const LIVE_BEAMS: int = 64
## How wide a beam that is shown whole (a short beam) is drawn: its core, rim, flares and glow.
const BEAM_TEXTURE_HEIGHT: float = 32.0
## The quad kinds of a beam's mesh (`beam_mesh`; Q_* in `shot_beam.gdshader`, PARTICLES ARE
## GEOMETRY there): the light round each piece of its path, a splash spark's light, its card
## particles, the splash sparks, each piece's pixels.
const BEAM_Q_PIECE_LIGHT: int = 0
const BEAM_Q_SPLASH_LIGHT: int = 1
const BEAM_Q_PARTICLE: int = 2
const BEAM_Q_SPLASH: int = 3
const BEAM_Q_PIECE: int = 4
## The mesh's quads in drawing order, as (kind, slots, 1 when the slots run backwards): the
## lights first, then the particles (the newest on top), the splash (the first on top), the
## beam's own pixels last. 12 particles (MAX_PARTICLES in the shot shaders), 6 splash sparks.
const BEAM_QUADS: Array[Vector3i] = [
	Vector3i(BEAM_Q_PIECE_LIGHT, LIVE_BEAM_POINTS - 1, 0),
	Vector3i(BEAM_Q_SPLASH_LIGHT, 6, 0),
	Vector3i(BEAM_Q_PARTICLE, 12, 0),
	Vector3i(BEAM_Q_SPLASH, 6, 1),
	Vector3i(BEAM_Q_PIECE, LIVE_BEAM_POINTS - 1, 0),
]

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
## The effects drawn with the shot shaders (see "Effects" above): the kinds they know (K_* in
## core/projectiles/shot_palette.gdshaderinc), their seconds and their draw layer (with the shots, above the room and
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
## The ground struck (a part of the cues `quake` and `slam`): cracks cooling from white-hot,
## rubble and dust, drawn by the flares' shader in a batch of its own under the bodies (`FLOOR_Z`). Below KIND_BURST, where
## the shots' kinds are, which never come to that shader.
const KIND_QUAKE: int = 3
## The look bit that makes an effect take its colour exactly (a reaction's own colour) instead
## of the palette material it is nearest (kind 24 in the shader).
const EXACT: int = 1 << 23
## The look bit that turns a puff into a staff's poof (kind 22 in the shader; living staffs H4):
## bone clouds swelling and shrinking along the staff, a few sparks in the player's colour.
const POOF: int = 1 << 21
## The poof: its seconds (the swap is at 35% of them, StaffLook's), its zoom (a quad of
## EFFECT_GRID x 2 px, the staff's length) and its middle, this far from the hand along the aim.
const POOF_SECONDS: float = 0.18
const POOF_ZOOM: int = 2
const POOF_ALONG: float = 4.0
const SPRAY_SECONDS: float = 0.3
const PUFF_SECONDS: float = 0.4
const CHIPS_SECONDS: float = 0.5
## A quake's seconds (its cracks cool and crumble away at the end), and its reach per zoom in
## pixels (QUAKE_REACH in the shader): its zoom is the reach struck times QUAKE_PAST over that.
const QUAKE_SECONDS: float = 1.4
const QUAKE_REACH: float = 8.0
const QUAKE_PAST: float = 1.5
## An explosion's parts (the cues `blast` and `fireball`), drawn by `shot_blast.gdshader` (its B_*: these less
## KIND_SHELL) in a batch of their own, the scorch in another under the bodies (`FLOOR_Z`): the
## ragged shell (blast's), the rising fireball (an exploding barrel's), the fragments and rubble
## flung past the radius, the scorch. Their seconds (the shader's; keep them equal), and the
## square each is drawn in: BLAST_SPAN radii each way.
const KIND_SHELL: int = 16
const KIND_FIREBALL: int = 17
const KIND_DEBRIS: int = 18
const KIND_SCORCH: int = 19
const SHELL_SECONDS: float = 0.5
const FIREBALL_SECONDS: float = 1.2
const DEBRIS_SECONDS: float = 1.6
const SCORCH_SECONDS: float = 2.6
const BLAST_SPAN: float = 2.2
## What a cue's part can name (`CueBase.EFFECTS`): its effect kind, the pixels a step of its zoom
## is (for a part's `reach`: a ring's radius, a flare's half width, a quake's reach, an
## explosion's radius) and its seconds when the part gives none.
const CUE_EFFECTS: Dictionary = {
	&"burst": [KIND_BURST, 12.0, BURST_SECONDS],
	&"ring_out": [KIND_RING_OUT, 10.0, RING_SECONDS],
	&"ring_in": [KIND_RING_IN, 10.0, RING_SECONDS],
	&"rune_burst": [KIND_RUNE_BURST, 12.0, RUNE_BURST_SECONDS],
	&"cast": [KIND_CAST, 12.0, CAST_SECONDS],
	&"spray": [KIND_SPRAY, 12.0, SPRAY_SECONDS],
	&"puff": [KIND_PUFF, 12.0, PUFF_SECONDS],
	&"chips": [KIND_CHIPS, 12.0, CHIPS_SECONDS],
	&"quake": [KIND_QUAKE, QUAKE_REACH, QUAKE_SECONDS],
	&"shell": [KIND_SHELL, 2.0, SHELL_SECONDS],
	&"fireball": [KIND_FIREBALL, 2.0, FIREBALL_SECONDS],
	&"debris": [KIND_DEBRIS, 2.0, DEBRIS_SECONDS],
	&"scorch": [KIND_SCORCH, 2.0, SCORCH_SECONDS],
}
## A status effect lasts until its status ends (Feel ends it).
const FOREVER: float = 1.0e9
const BURST_SECONDS: float = 0.3
const RING_SECONDS: float = 0.22
## The moments `form_shown` names that are a cue each (`content/cues`), played with its `length`
## as the cue's size: a nova's ring leaving the caster, and the telegraph of a rain (a ring closing
## on where it falls for the `length` seconds until then, so nobody is hit by one they could not
## see coming). A slam's impact (`slam`) plays the cue its card's impact look names; its wind-up
## shows only on the staff (the rising, glowing staff: a ring there distracted from the strike).
const FORM_CUES: Dictionary = {&"nova": &"nova", &"rain": &"telegraph"}
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
const ARC_MARGIN: float = 12.0
const ARC_ACROSS: float = 56.0
## A zap no longer than this is an arc's spark into the air (SpellLimits.ARC_SPARK_LONGEST): it
## burns out sooner.
const SPARK_LONGEST: float = 22.0
## A status effect's zoom (round a character of about 16 px) and how far above its feet it sits.
const STATUS_ZOOM: int = 2
const STATUS_RISE: float = 8.0
## A beam is drawn this wide (its core, rim, flares and glow; `shot_beam.gdshader`'s mode 1).
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
## The quad kinds of an effect's mesh (`effect_mesh`; Q_* in `shot_effect.gdshader`, PARTICLES ARE
## GEOMETRY there): its light, its card particles, its sparks, a poof's clouds and its flash.
const EFFECT_Q_LIGHT: int = 0
const EFFECT_Q_PARTICLE: int = 1
const EFFECT_Q_SPARK: int = 2
const EFFECT_Q_CLOUD: int = 3
const EFFECT_Q_SHAPE: int = 4
## The mesh's quads in drawing order, as (kind, slots, 1 when the slots run backwards): the light
## first, then the particles (the newest on top), the sparks and clouds (the first on top), the
## flash last. 12 particles (MAX_PARTICLES in the shot shaders), 16 sparks (a rune's), 4 clouds.
## The blast mesh's quads (`blast_mesh`; Q_* in `shot_blast.gdshader`): its light, then
## BLAST_PIECES pieces (chunks, lobes, puffs, embers), each part using what it needs.
const BLAST_Q_LIGHT: int = 0
const BLAST_Q_PIECE: int = 1
const BLAST_PIECES: int = 24
const BLAST_QUADS: Array[Vector3i] = [
	Vector3i(BLAST_Q_LIGHT, 1, 0),
	Vector3i(BLAST_Q_PIECE, BLAST_PIECES, 0),
]
const EFFECT_QUADS: Array[Vector3i] = [
	Vector3i(EFFECT_Q_LIGHT, 1, 0),
	Vector3i(EFFECT_Q_PARTICLE, 12, 0),
	Vector3i(EFFECT_Q_SPARK, 16, 1),
	Vector3i(EFFECT_Q_CLOUD, 4, 1),
	Vector3i(EFFECT_Q_SHAPE, 1, 0),
]
## How long a muzzle flash is compared with its width.
## The biggest camera kick in pixels, however fast the casting.
const MAX_KICK_PIXELS: float = 4.0
## A possession's ring on the possessed actor (`possess_started`, `possess_ended`): its zoom and
## seconds, and the sound when it starts.
const POSSESS_ZOOM: int = 2
const POSSESS_SECONDS: float = 0.35
const POSSESS_SOUND: StringName = &"possess"

## The services. Only tests set these, before adding the node; otherwise the
## autoloads are used.
var events: EventsScript = null
var registry: RegistryScript = null
var projectiles: Node = null
## The combat autoload, asked only `status_left(enemy, id)` to know when a status ends.
var combat: Node = null
## The spell runtime, asked only for its live beams (`beam_*`) to draw them every frame.
var spells: Node = null
## The actor table, which says the ramp, seat and budget of a caster (actors G3b). Only tests set
## it; otherwise the "Actors" autoload.
var actors: ActorsScript = null
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
## Seconds of the game-wide stop left, in real time (`Engine.time_scale`): only for a downed
## player and a boss kill. Every other hit holds only its own bodies (see `_hold_bodies`).
var stop_left: float = 0.0
## Seconds left after a game-wide stop, in real time.
var rest_left: float = 0.0
## The time (`_clock`) before which a plain hit does not hold this actor again, by actor id, so a
## stream of hits on one body cannot keep it held for ever.
var _rest_until: PackedFloat32Array = PackedFloat32Array()
## The body (instance id) each rest belongs to, so a reused actor id starts with no rest.
var _rest_body: PackedInt64Array = PackedInt64Array()
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
## The live beams (`Spells.carrier(&"beam")`), one beam mesh each (`beam_mesh`), made once, and each one's
## path as the shader takes it (x, y and how far along the beam; `beam_path`).
var _live_beams: Array[MeshInstance2D] = []
## The swings' trails (`swing_trails.gd`, melee I4), drawn from `Spells`' live swings every frame.
var _swing_trails: SwingTrailsScript = null
var _live_paths: Array[PackedVector3Array] = []
## Scratch of `_thin_beam`: the points of a long path (read once, drawn from here), which of them
## are drawn, how sharply it turns at each, and those turns sorted.
var _thin_points: PackedVector2Array = PackedVector2Array()
var _thin_keep: PackedByteArray = PackedByteArray()
var _thin_turn: PackedFloat32Array = PackedFloat32Array()
var _thin_sorted: PackedFloat32Array = PackedFloat32Array()
## Beams shown whole (beam meshes made once) and their paths of two points: seconds left and in
## all, the owner's body tint and the beam's length in pixels.
var _forms: Array[MeshInstance2D] = []
var _form_paths: Array[PackedVector3Array] = []
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
## The effects' batches, one per shader (see "Effects" above): the flares, the arcs, the
## statuses, and the marks on the floor (the flares' shader, lower); each has room for every slot.
var _effect_node: MultiMeshInstance2D = null
var _effect_buffer: PackedFloat32Array = PackedFloat32Array()
static var _effect_mesh: ArrayMesh = null
static var _beam_mesh: ArrayMesh = null
static var _swing_mesh: ArrayMesh = null
var _arc_node: MultiMeshInstance2D = null
var _arc_buffer: PackedFloat32Array = PackedFloat32Array()
var _status_node: MultiMeshInstance2D = null
var _status_buffer: PackedFloat32Array = PackedFloat32Array()
var _floor_node: MultiMeshInstance2D = null
var _floor_buffer: PackedFloat32Array = PackedFloat32Array()
## An explosion's parts, and its scorch under the bodies (`shot_blast.gdshader`).
var _blast_node: MultiMeshInstance2D = null
var _blast_buffer: PackedFloat32Array = PackedFloat32Array()
var _blast_floor_node: MultiMeshInstance2D = null
var _blast_floor_buffer: PackedFloat32Array = PackedFloat32Array()
static var _blast_mesh: ArrayMesh = null
var _effect_kind: PackedInt32Array = PackedInt32Array()
var _effect_at: PackedVector2Array = PackedVector2Array()
var _effect_dir: PackedVector2Array = PackedVector2Array()
var _effect_core: PackedColorArray = PackedColorArray()
## Each effect's ramp (`Actors.ramp_of` of its caster; 0-3 a hat ramp, anything else the enemy ramp).
var _effect_ramp: PackedInt32Array = PackedInt32Array()
var _effect_zoom: PackedInt32Array = PackedInt32Array()
var _effect_look: PackedInt32Array = PackedInt32Array()
var _effect_age: PackedFloat32Array = PackedFloat32Array()
var _effect_seconds: PackedFloat32Array = PackedFloat32Array()
var _effect_length: PackedFloat32Array = PackedFloat32Array()
## The character an effect follows (a status), or null, and how far above it the effect sits.
var _effect_follow: Array[Node2D] = []
## Where a followed effect sits from its node (a status rises above it, a poof sits on the staff).
var _effect_offset: PackedVector2Array = PackedVector2Array()
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
## The actor whose shot it was: a contact hit (another caster value) never takes it.
var _impact_caster: int = 0
## The physics frame it was sent in: the damage follows at once, or the record is stale.
var _impact_frame: int = -1
## The latest hit kind (`hit_landed`): the target it was for, the kind, the frame, and whether a
## wizard hit themselves. `damage_dealt` follows at once, or the record is stale.
var _kind_target: int = 0
var _kind: StringName = &"shot"
var _kind_frame: int = -1
var _kind_own: bool = false
## The shot whose hit `hit_landed` announced (its `shot`, -1 for none): the one a hit's stop holds.
var _kind_shot: int = -1
var _impact_at: Vector2 = Vector2.ZERO
var _impact_aim: Vector2 = Vector2.ZERO
## Death animations: sprites made once (drawn by `shot_sprite.gdshader`'s dissolve), seconds left
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
## The cues read from `content/cues`, by id (see `cue_of`).
var _cue_cache: Dictionary = {}


func _ready() -> void:
	_rng.seed = 1
	_rest_until.resize(ActorsScript.ACTORS)
	_rest_body.resize(ActorsScript.ACTORS)
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if registry == null:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if preset == null:
		preset = load("res://gameplay/feel/presets/punchy.tres") as FeelPresetScript
	_last_usec = Time.get_ticks_usec()
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = FLASH_SHADER
	ShaderWarmupScript.want(FLASH_SHADER, ShaderWarmupScript.RECT)
	for i in FORM_SLOTS:
		_forms.append(_make_beam())
		_form_paths.append(_make_beam_path())
	_make_effects()
	for i in LIVE_BEAMS:
		_live_beams.append(_make_beam())
		_live_paths.append(_make_beam_path())
	_swing_trails = SwingTrailsScript.new(swing_mesh())
	add_child(_swing_trails)
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
		dissolve.shader = SPRITE_SHADER
		# The shots' sprite shader, as itself: a white core leaves its colours be.
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
	events.staff_shown.connect(_on_staff_shown)
	events.possess_started.connect(_on_possess_started)
	events.possess_ended.connect(_on_possess_ended)
	events.projectile_impact.connect(_on_projectile_impact)
	events.form_shown.connect(_on_form_shown)
	events.cue_shown.connect(_on_cue_shown)
	events.reaction_triggered.connect(_on_reaction_triggered)
	events.discharge_arc.connect(_on_discharge_arc)
	events.status_applied.connect(_on_status_applied)
	events.effect_slots_changed.connect(_on_effect_slots_changed)
	events.screen_shake_changed.connect(_on_screen_shake_changed)
	events.caster_move_finished.connect(_on_caster_move_finished)
	events.projectile_expired.connect(_on_projectile_expired)
	events.shot_deflected.connect(_on_shot_deflected)
	events.shot_blocked.connect(_on_shot_blocked)
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
	if _swing_trails != null:
		_swing_trails.step(spells.call("carrier", &"swing") if spells != null and spells.has_method("carrier") else null, _clock, _swing_ramp, preset.beam_alpha)
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


## Start the white flash and the squash (wide and low) of the hit node's `Sprite` child, if it
## has one, for `flash_seconds`; a hit on a sprite still reacting starts it again.
func _react(target: Node) -> void:
	var seconds: float = preset.flash_seconds
	var amount: float = preset.hit_squash
	if seconds <= 0.0 or target == null or not is_instance_valid(target):
		return
	var sprite := target.get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	var at: int = _react_sprites.find(sprite.get_instance_id())
	if at >= 0:
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
	sprite.material = _flash_material


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


func _on_damage_dealt(caster: int, target: Node, amount: float, position: Vector2) -> void:
	_react(target)
	var aim: Vector2 = Vector2.ZERO
	var at: Vector2 = position
	var tint: Color = Color.WHITE
	var size: float = 1.0
	var colours: int = 0
	if target != null and is_instance_valid(target):
		# An actor of a hat ramp is hit in its own colours: white, its ramp; the rest in ember.
		var ramp: int = _hat_ramp_of(target)
		if ramp >= 0:
			colours = ramp
		else:
			tint = preset.enemy_hit_color
		# The shot that did this hit told us where it struck and which way it flew.
		if target.get_instance_id() == _impact_target and caster == _impact_caster and Engine.get_physics_frames() == _impact_frame:
			aim = _impact_aim
			at = _impact_at
			size = clampf(1.0 + float(amount - SPRAY_REF_DAMAGE) * preset.hit_spray_per_damage, SPRAY_MIN_SIZE, SPRAY_MAX_SIZE)
	_impact_target = 0
	# The kind of the hit came just before (`hit_landed`): its default stop, shake and sound.
	var stop: float = preset.hit_stop_seconds
	# A hit of part of a point (an atom's speck) shakes as much as its share, so a stream of them
	# is not a quake.
	var shake: float = preset.hit_shake * minf(amount, 1.0)
	var sound: StringName = preset.hit_sound
	var own: bool = false
	var shot: int = -1
	if target != null and target.get_instance_id() == _kind_target and Engine.get_physics_frames() == _kind_frame:
		shot = _kind_shot
		var look_kind: StringName = _kind if preset.kind_looks.has(_kind) else &"shot"
		var look: Dictionary = preset.kind_looks[look_kind] as Dictionary if preset.kind_looks.has(look_kind) else NO_LOOK
		stop *= look.get("stop", 1.0) as float
		shake *= look.get("shake", 1.0) as float
		sound = look.get("sound", preset.hit_sound) as StringName
		own = _kind_own
	_kind_target = 0
	_hold_bodies(caster, _actor_of(target), stop, false, shot)
	_juice(position, shake, sound, aim, tint, size, at, colours)
	if own:
		# Their own spell: the cue `self_hit` (a ring in its own colour) on this frame, so it is
		# never taken for an enemy's hit.
		play_cue(&"self_hit", caster, position)


## The kind of the hit that `damage_dealt` announces next, and whether an actor hit itself.
func _on_hit_landed(caster: int, target: Node, _amount: float, _position: Vector2, kind: StringName, shot: int) -> void:
	if target == null:
		return
	_kind_target = target.get_instance_id()
	_kind = kind
	_kind_shot = shot
	_kind_frame = Engine.get_physics_frames()
	_kind_own = kind != &"heal" and kind != &"status" and caster != ActorsScript.NONE and _actor_of(target) == caster


## A heal: the cue `heal` (a soft ring in green on the wizard, with no stop and no shake). Its
## ring is in its own colour, whoever healed.
func _on_heal_dealt(_player: int, _target: Node, _amount: float, position: Vector2) -> void:
	play_cue(&"heal", ActorsScript.NONE, position)


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
func _on_reaction_triggered(caster: int, reaction_id: StringName, position: Vector2, shot: int) -> void:
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
	# The hit-stop is longer than a death's and, like a death's, ignores the rest after a stop. The
	# reaction's own hit (kind `reaction`) holds its target by the plain rule; a hold only ever
	# lengthens, so whichever of the two comes first, the caster is held for the longer one.
	_hold_bodies(caster, ActorsScript.NONE, preset.reaction_stop_seconds * power, true, shot)
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
func _on_projectile_impact(caster: int, target: Node, position: Vector2, direction: Vector2) -> void:
	var ramp: int = _ramp_of(caster)
	if target != null:
		_impact_target = target.get_instance_id()
		_impact_caster = caster
		_impact_frame = Engine.get_physics_frames()
		_impact_at = position
		_impact_aim = direction
		_show_impact(caster, ramp, position, direction, true)
		return
	# Stone chips knocked back off the surface.
	if particles_enabled:
		show_effect(KIND_CHIPS, position, -direction, Color.WHITE, 0, 0, clampi(roundi(preset.wall_chip_size), 1, 3), CHIPS_SECONDS)
	_show_impact(caster, ramp, position, direction, false)


## A dash landed: a ring in its caster's ramp where the body stopped; lightning arcs from where it
## left, and an infused dash lands in a small flare of its element (the mockup's). One dash is
## kept per budget (a seat's, and one for every actor no seat drives).
func _on_caster_move_finished(caster: int, mode: StringName, position: Vector2, _tag: int) -> void:
	if mode != &"dash" or caster < ActorsScript.NONE or caster >= ActorsScript.ACTORS or not position.is_finite():
		return
	var ramp: int = _ramp_of(caster)
	var who: int = _budget_of(caster)
	var look: int = _dash_look[who]
	show_effect(KIND_RING_OUT, position, Vector2.RIGHT, Color.WHITE, ramp, 0, 1, RING_SECONDS)
	var from: Vector2 = _dash_from[who]
	if from.is_finite() and (look & (1 << (ProjectileManagerScript.LOOK_SPARKS - 1))) != 0 and from.distance_to(position) > 4.0:
		show_effect(KIND_ARC, from, from.direction_to(position), _dash_core[who], ramp, look, 1, RING_SECONDS, from.distance_to(position))
	if look != 0:
		show_effect(KIND_BURST, position, from.direction_to(position) if from.is_finite() else Vector2.RIGHT, _dash_core[who], ramp, look, POP_ZOOM, POP_SECONDS)
	_dash_from[who] = Vector2.INF


## A bolt or orbit shot whose life ran out goes off in a small pop of its own colours where it
## was (the mockup's); one that ended on a wall already showed its impact, and a rune's going off
## is its own burst.
func _on_projectile_expired(caster: int, position: Vector2, _tag: int, _shot: int) -> void:
	if projectiles == null or not position.is_finite() or caster < ActorsScript.NONE or caster >= ActorsScript.ACTORS:
		return
	if bool(projectiles.get("expired_on_wall")) or not ("impact_form" in projectiles):
		return
	var form: StringName = projectiles.impact_form as StringName
	if form != &"bolt" and form != &"orbit":
		return
	var heading: Vector2 = projectiles.get("impact_heading") as Vector2 if "impact_heading" in projectiles else Vector2.RIGHT
	show_effect(KIND_BURST, position, heading, projectiles.impact_core as Color, _ramp_of(caster), projectiles.impact_look as int, POP_ZOOM, POP_SECONDS)


## A shot was deflected (melee I5; docs/milestones/M2-staffs.md, "The look"): the cue `deflect`,
## a big white-hot cross in its new caster's (`caster`'s) colours, bigger than a hit's, aimed the
## way it leaves (`shot`, the deflected shot). Its longer tail needs
## nothing here: it flies 1.7x faster, and its tail is a pixel per pixel of travel.
func _on_shot_deflected(caster: int, position: Vector2, _tag: int, shot: int) -> void:
	if not position.is_finite() or caster < ActorsScript.NONE or caster >= ActorsScript.ACTORS:
		return
	var heading: Vector2 = Vector2.RIGHT
	if projectiles != null and shot >= 0:
		heading = projectiles.get_velocity_of(shot) as Vector2
	play_cue(&"deflect", caster, position, heading)


## A shot was blocked. A swing's block is a parry (`shield · swing`; the projectile manager's
## `impact_form` says which carrier blocked): the cue `parry`, a big four-point star in Spark gold
## and a local stop on the parrying actor alone. Other blocks show nothing of their own.
func _on_shot_blocked(caster: int, position: Vector2, _tag: int, _shot: int) -> void:
	if projectiles == null or not ("impact_form" in projectiles) or (projectiles.impact_form as StringName) != &"swing":
		return
	if not position.is_finite():
		return
	play_cue(&"parry", caster, position)


## The payoff of a shot: a flare in the shot's colour, shaped by the form of the shot itself
## (the projectile manager's `impact_form` while the impact is sent; a rune goes off, a nova's
## adds a ring), in its caster's `ramp`: an enemy's lands the same way, in the enemy ramp where a
## hat colour would show (staffs F7: one look for every spell). A carrier whose impact look names
## a `cue` plays it where it ends on no body (`on_body` false), as big as its card's radius.
func _show_impact(caster: int, ramp: int, position: Vector2, direction: Vector2, on_body: bool) -> void:
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
		show_effect(KIND_RUNE_BURST, position, Vector2.RIGHT, core, ramp, bits, 3, RUNE_BURST_SECONDS)
		return
	var zoom: int = clampi(roundi(size * 2.0), 1, 3)
	show_effect(KIND_BURST, position, direction, core, ramp, bits, zoom, BURST_SECONDS)
	if look.get("ring", false) as bool:
		show_effect(KIND_RING_OUT, position, direction, core, ramp, 0, 1, RING_SECONDS)
	if look.has("cue") and not on_body:
		play_cue(StringName(look["cue"]), caster, position, direction, look.get("radius", 0.0) as float, core, bits)


## Play the cue `id` (a `CueBase`, `content/cues/<id>.tres`; `cue_shown` calls this) at `at`, set
## off by `caster` (NONE for none: the enemy ramp; its body is where `away` punches from) along
## `dir`, `size` pixels big (what a part's `reach` is times; the seconds a `lasts_size` part
## lasts), in its ramp with `tint` (as `show_effect`'s `core`) and the cards of the packed `look`,
## on `target` (an actor, for `hold_target`). Draws its parts, then its weight: holds, the game-wide stop, shake and punch
## (both off with the screen shake setting) and its sound. An unknown cue plays nothing.
func play_cue(id: StringName, caster: int, at: Vector2, dir: Vector2 = Vector2.ZERO, size: float = 0.0, tint: Color = Color.WHITE, look: int = 0, target: int = ActorsScript.NONE, shot: int = -1) -> void:
	if not at.is_finite() or caster < ActorsScript.NONE or caster >= ActorsScript.ACTORS:
		return
	var cue: CueBase = cue_of(id)
	if cue == null:
		return
	var ramp: int = _ramp_of(caster)
	var aim: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	for part: Dictionary in cue.parts:
		var row: Array = CUE_EFFECTS.get(StringName(part.get("effect", "")), []) as Array
		if row.is_empty() or (bool(part.get("particles", false)) and not particles_enabled):
			continue
		var seconds: float = float(part.get("seconds", row[2]))
		if bool(part.get("lasts_size", false)):
			if size <= 0.0:
				continue
			seconds = size
		var zoom: int = int(part.get("zoom", 1))
		if part.has("reach"):
			zoom = roundi(size * float(part["reach"]) / float(row[1]))
		var way: Vector2 = aim
		match StringName(part.get("way", "aim")):
			&"back":
				way = -aim
			&"right":
				way = Vector2.RIGHT
			&"up":
				way = Vector2.UP
		if part.has("color"):
			show_effect(int(row[0]), at, way, part["color"] as Color, 0, EXACT, zoom, seconds)
		elif bool(part.get("plain", false)):
			show_effect(int(row[0]), at, way, Color.WHITE, 0, 0, zoom, seconds)
		else:
			show_effect(int(row[0]), at, way, tint, ramp, look, zoom, seconds)
	var table: ActorsScript = _actor_table()
	if table != null:
		var held: bool = cue.hold > 0.0 and _hold_actor(table, caster, cue.hold, true)
		held = (cue.hold_target > 0.0 and _hold_actor(table, target, cue.hold_target, true)) or held
		if cue.hold_shot and held and projectiles != null and shot >= 0:
			projectiles.freeze_shot(shot, maxf(cue.hold, cue.hold_target))
	if cue.stop_game > 0.0:
		_stop_game(cue.stop_game)
	if shake_enabled and (cue.shake > 0.0 or cue.kick > 0.0):
		_refresh_camera()
		_trauma = minf(_trauma + cue.shake, 1.0)
		var way: Vector2 = Vector2.DOWN
		match cue.kick_way:
			&"back":
				way = -aim
			&"aim":
				way = aim
			&"away":
				var body: Node2D = table.node_of(caster) as Node2D if table != null and table.is_open(caster) else null
				if body != null and body.global_position.distance_to(at) > 1.0:
					way = body.global_position.direction_to(at)
		_kick = (_kick + way * cue.kick).limit_length(MAX_KICK_PIXELS)
	_play(cue.sound)


## The cue `id` (`content/cues/<id>.tres`), or null when there is none or no registry yet. Read
## once per id, then kept: a cue allocates nothing.
func cue_of(id: StringName) -> CueBase:
	var cached: Variant = _cue_cache.get(id)
	if cached != null:
		return cached as CueBase
	if registry == null or id == &"":
		return null
	var cue: CueBase = registry.get_resource(&"cues", id) as CueBase
	if cue != null:
		_cue_cache[id] = cue
	return cue


func _on_cue_shown(caster: int, cue: StringName, at: Vector2, direction: Vector2, size: float, tint: Color, look: int) -> void:
	play_cue(cue, caster, at, direction, size, tint, look)


## A beam's node: a beam mesh in world space drawn by the beam shader, hidden until shown.
func _make_beam() -> MeshInstance2D:
	var node := MeshInstance2D.new()
	node.mesh = beam_mesh()
	var material := ShaderMaterial.new()
	material.shader = BEAM_SHADER
	node.material = material
	node.top_level = true
	node.visible = false
	node.z_index = FORM_Z
	add_child(node)
	return node


func _make_beam_path() -> PackedVector3Array:
	var path := PackedVector3Array()
	path.resize(LIVE_BEAM_POINTS)
	return path


## The mesh a beam is drawn as (`shot_beam.gdshader`, PARTICLES ARE GEOMETRY there): small quads
## told in their UV which quad kind (BEAM_Q_*) and slot they are, in BEAM_QUADS' order, as
## `effect_mesh`. The shader places them along the beam's path in the world, so the mesh says
## nothing of where: it is never culled (its box is the whole world). Made once.
static func beam_mesh() -> ArrayMesh:
	if _beam_mesh == null:
		_beam_mesh = _quads_mesh(BEAM_QUADS)
		_beam_mesh.custom_aabb = AABB(Vector3(-100000.0, -100000.0, -1.0), Vector3(200000.0, 200000.0, 2.0))
	return _beam_mesh


## The mesh a swing's trail is drawn as (`SwingTrailsScript.SWING_QUADS`; Q_* in
## `shot_swing.gdshader`), as `beam_mesh`. Made once.
static func swing_mesh() -> ArrayMesh:
	if _swing_mesh == null:
		_swing_mesh = _quads_mesh(SwingTrailsScript.SWING_QUADS)
		_swing_mesh.custom_aabb = AABB(Vector3(-100000.0, -100000.0, -1.0), Vector3(200000.0, 200000.0, 2.0))
	return _swing_mesh


## The swing trails (for tests).
func swing_trails() -> SwingTrailsScript:
	return _swing_trails


## The shader's player for a swing of `actor` (`_beam_ramp` of its ramp).
func _swing_ramp(actor: int) -> int:
	return _beam_ramp(_ramp_of(actor))


## Make the effect batches (see "Effects" above): a MultiMesh of `effect_slots` quads in world
## space for each of the flares, the arcs and the statuses, each drawn by its own shot shader,
## and the arrays behind them.
func _make_effects() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_status_node = _make_effect_batch(STATUS_SHADER, quad)
	_effect_node = _make_effect_batch(EFFECT_SHADER, effect_mesh())
	_arc_node = _make_effect_batch(ARC_SHADER, quad)
	_floor_node = _make_effect_batch(EFFECT_SHADER, effect_mesh())
	_floor_node.z_index = FLOOR_Z
	_blast_node = _make_effect_batch(BLAST_SHADER, blast_mesh())
	_blast_floor_node = _make_effect_batch(BLAST_SHADER, blast_mesh())
	_blast_floor_node.z_index = FLOOR_Z
	_size_effects(effect_slots)


## The mesh an effect is drawn as (`shot_effect.gdshader`, PARTICLES ARE GEOMETRY there): small
## quads, each told in its UV which quad kind (EFFECT_Q_*) and slot it is, in EFFECT_QUADS'
## order. The shader places every quad in the effect's square, or folds it away; a vertex says
## which quad and corner it is in its UV: x the slot + 0.25 or 0.75, y the kind + 0.25 or 0.75.
## Made once.
static func effect_mesh() -> ArrayMesh:
	if _effect_mesh == null:
		_effect_mesh = _quads_mesh(EFFECT_QUADS)
	return _effect_mesh


## The mesh an explosion's part is drawn as (`shot_blast.gdshader`): its light and BLAST_PIECES
## small quads, told their kind and slot in their UV as `effect_mesh`'s. Made once.
static func blast_mesh() -> ArrayMesh:
	if _blast_mesh == null:
		_blast_mesh = _quads_mesh(BLAST_QUADS)
	return _blast_mesh


## A mesh of small quads, (kind, slots, 1 when the slots run backwards) for each entry of `quads`
## in order: a vertex says which quad and corner it is in its UV, x the slot + 0.25 or 0.75, y
## the kind + 0.25 or 0.75 (its position is a unit square round the origin).
static func _quads_mesh(quads: Array[Vector3i]) -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var corners: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for entry: Vector3i in quads:
		for n in entry.y:
			var slot: int = entry.y - 1 - n if entry.z == 1 else n
			var base: int = verts.size()
			for corner: Vector2 in corners:
				verts.append(corner - Vector2(0.5, 0.5))
				uvs.append(Vector2(float(slot) + 0.25 + 0.5 * corner.x, float(entry.x) + 0.25 + 0.5 * corner.y))
				colors.append(Color.WHITE)
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_effect_batch(shader: Shader, mesh: Mesh) -> MultiMeshInstance2D:
	var node := MultiMeshInstance2D.new()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.visible_instance_count = 0
	# Effects show anywhere in the world; there is no room to fit a box to.
	multimesh.custom_aabb = AABB(Vector3(-100000.0, -100000.0, -1.0), Vector3(200000.0, 200000.0, 2.0))
	node.multimesh = multimesh
	var material := ShaderMaterial.new()
	material.shader = shader
	node.material = material
	node.top_level = true
	node.z_index = EFFECT_Z
	add_child(node)
	return node


## Make room for `slots` effects: the MultiMesh, its buffer and the arrays behind it. The
## effects showing end (a setting changed in a menu: nobody misses a tenth of a second of sparks).
func _size_effects(slots: int) -> void:
	effect_slots = slots
	for node: MultiMeshInstance2D in [_effect_node, _arc_node, _status_node, _floor_node, _blast_node, _blast_floor_node]:
		node.multimesh.visible_instance_count = 0
		node.multimesh.instance_count = slots
	_effect_buffer.resize(slots * EFFECT_STRIDE)
	_arc_buffer.resize(slots * EFFECT_STRIDE)
	_floor_buffer.resize(slots * EFFECT_STRIDE)
	_blast_buffer.resize(slots * EFFECT_STRIDE)
	_blast_floor_buffer.resize(slots * EFFECT_STRIDE)
	_status_buffer.resize(slots * EFFECT_STRIDE)
	_effect_kind.resize(slots)
	_effect_at.resize(slots)
	_effect_dir.resize(slots)
	_effect_core.resize(slots)
	_effect_ramp.resize(slots)
	_effect_zoom.resize(slots)
	_effect_look.resize(slots)
	_effect_age.resize(slots)
	_effect_seconds.resize(slots)
	_effect_seconds.fill(0.0)
	_effect_length.resize(slots)
	_effect_follow.resize(slots)
	_effect_follow.fill(null)
	_effect_offset.resize(slots)
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


func _on_screen_shake_changed(enabled: bool) -> void:
	shake_enabled = enabled


## Show an effect of `kind` (KIND_BURST to KIND_CAST) at `at`, aimed along `dir`, in the ramp of
## `core` (white: the colours of `ramp`, a caster's `Actors.ramp_of`: 0-3 a hat ramp, anything else
## from NONE up the enemy ramp) with the particles of the packed `look`, at `zoom`, for
## `seconds`. A dash or an arc runs `length` pixels from `at` along `dir` (its zoom is then the
## length). An effect given a `follow` node moves with it (a status), and ends when it is gone.
## It takes the next slot, the oldest effect when they are all busy, and returns it (-1 for
## none).
func show_effect(kind: int, at: Vector2, dir: Vector2, core: Color, ramp: int, look: int, zoom: int, seconds: float, length: float = 0.0, follow: Node2D = null) -> int:
	if _effect_node == null or not at.is_finite() or ramp < ActorsScript.NONE or ramp > ActorsScript.RAMP_ENEMY:
		return -1
	var slot: int = _next_effect
	_next_effect = (_next_effect + 1) % effect_slots
	_effect_kind[slot] = kind
	_effect_at[slot] = at.round()
	_effect_dir[slot] = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	_effect_core[slot] = core
	_effect_ramp[slot] = ramp
	# An explosion's part takes its radius / 2 as its zoom, up to the most the look holds.
	_effect_zoom[slot] = clampi(zoom, 1, 63 if kind >= KIND_SHELL else 15)
	_effect_look[slot] = look
	_effect_age[slot] = 0.0
	_effect_seconds[slot] = maxf(seconds, 0.01)
	_effect_length[slot] = 0.0
	_effect_follow[slot] = follow
	_effect_offset[slot] = Vector2(0.0, -STATUS_RISE) if follow != null else Vector2.ZERO
	if kind == KIND_DASH or kind == KIND_ARC:
		var steps: int = clampi(roundi(length / 4.0), 1, roundi(DASH_LONGEST / 4.0))
		_effect_zoom[slot] = steps
		_effect_length[slot] = steps * 4.0
	return slot


## Age the effects by `real_delta` and write the live ones into their batches, oldest first.
func _step_effects(real_delta: float) -> void:
	if _effect_node == null:
		return
	(_effect_node.material as ShaderMaterial).set_shader_parameter(&"sim_time", _clock)
	(_arc_node.material as ShaderMaterial).set_shader_parameter(&"sim_time", _clock)
	(_status_node.material as ShaderMaterial).set_shader_parameter(&"sim_time", _clock)
	(_floor_node.material as ShaderMaterial).set_shader_parameter(&"sim_time", _clock)
	(_blast_node.material as ShaderMaterial).set_shader_parameter(&"sim_time", _clock)
	(_blast_floor_node.material as ShaderMaterial).set_shader_parameter(&"sim_time", _clock)
	var out: int = 0
	var arcs: int = 0
	var floors: int = 0
	var blasts: int = 0
	var scorches: int = 0
	var statuses: int = 0
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
			_effect_at[slot] = (follow.global_position + _effect_offset[slot]).round()
		var kind: int = _effect_kind[slot]
		var buffer: PackedFloat32Array = _effect_buffer
		var i: int = out * EFFECT_STRIDE
		if kind == KIND_ARC:
			buffer = _arc_buffer
			i = arcs * EFFECT_STRIDE
			arcs += 1
		elif kind == KIND_STATUS:
			buffer = _status_buffer
			i = statuses * EFFECT_STRIDE
			statuses += 1
		elif kind == KIND_QUAKE:
			buffer = _floor_buffer
			i = floors * EFFECT_STRIDE
			floors += 1
		elif kind == KIND_SCORCH:
			buffer = _blast_floor_buffer
			i = scorches * EFFECT_STRIDE
			scorches += 1
		elif kind >= KIND_SHELL:
			buffer = _blast_buffer
			i = blasts * EFFECT_STRIDE
			blasts += 1
		else:
			out += 1
		var d: float = EFFECT_GRID * _effect_zoom[slot]
		var along: float = d
		var dir: Vector2 = _effect_dir[slot]
		var at: Vector2 = _effect_at[slot]
		if kind >= KIND_SHELL:
			# An explosion's part: BLAST_SPAN radii each way, its radius the zoom x 2.
			d = _effect_zoom[slot] * 4.0 * BLAST_SPAN
			along = d
		if _effect_length[slot] > 0.0:
			# A dash or an arc: from where it starts along its way, a margin past each end.
			var arc: bool = kind == KIND_ARC
			d = ARC_ACROSS if arc else DASH_ACROSS
			along = _effect_length[slot] + 2.0 * (ARC_MARGIN if arc else DASH_MARGIN)
			at += dir * _effect_length[slot] * 0.5
		buffer[i] = dir.x * along
		buffer[i + 1] = dir.y * d
		buffer[i + 2] = 0.0
		buffer[i + 3] = at.x
		buffer[i + 4] = dir.y * along
		buffer[i + 5] = -dir.x * d
		buffer[i + 6] = 0.0
		buffer[i + 7] = at.y
		var data: Color = ProjectileManagerScript.look_color(_effect_ramp[slot], _effect_zoom[slot], _effect_look[slot])
		buffer[i + 8] = data.r
		buffer[i + 9] = data.g
		buffer[i + 10] = data.b
		buffer[i + 11] = data.a
		var core: Color = _effect_core[slot]
		buffer[i + 12] = core.r
		buffer[i + 13] = core.g
		buffer[i + 14] = core.b
		var code: int = kind - KIND_SHELL if kind >= KIND_SHELL else kind
		buffer[i + 15] = 1.0 - (float(code) + EFFECT_FROM + EFFECT_SPAN * through) / 16.0
	if out > 0:
		_effect_node.multimesh.buffer = _effect_buffer
	_effect_node.multimesh.visible_instance_count = out
	if arcs > 0:
		_arc_node.multimesh.buffer = _arc_buffer
	_arc_node.multimesh.visible_instance_count = arcs
	if statuses > 0:
		_status_node.multimesh.buffer = _status_buffer
	_status_node.multimesh.visible_instance_count = statuses
	if floors > 0:
		_floor_node.multimesh.buffer = _floor_buffer
	_floor_node.multimesh.visible_instance_count = floors
	if blasts > 0:
		_blast_node.multimesh.buffer = _blast_buffer
	_blast_node.multimesh.visible_instance_count = blasts
	if scorches > 0:
		_blast_floor_node.multimesh.buffer = _blast_floor_buffer
	_blast_floor_node.multimesh.visible_instance_count = scorches


## How many effects are showing (for tests and the sheets).
func live_effects() -> int:
	var live: int = 0
	for slot in effect_slots:
		if _effect_seconds[slot] > 0.0:
			live += 1
	return live


## How many live effects are of `kind`, and (with a `ramp` 0-4) in that ramp.
func effects_of(kind: int, ramp: int = -1) -> int:
	var found: int = 0
	for slot in effect_slots:
		if _effect_seconds[slot] > 0.0 and _effect_kind[slot] == kind and (ramp < 0 or _effect_ramp[slot] == ramp):
			found += 1
	return found


## The core colour and look of the newest live effect of `kind` (for tests): [core, look].
func effect_dress(kind: int) -> Array:
	for n in effect_slots:
		var slot: int = (_next_effect - 1 - n + effect_slots) % effect_slots
		if _effect_seconds[slot] > 0.0 and _effect_kind[slot] == kind:
			return [_effect_core[slot], _effect_look[slot]]
	return []


## The newest live effect of `kind` (for tests): its place, way, core colour, ramp, zoom and
## look, or an empty dictionary when none shows.
func effect_info(kind: int) -> Dictionary:
	for n in effect_slots:
		var slot: int = (_next_effect - 1 - n + effect_slots) % effect_slots
		if _effect_seconds[slot] > 0.0 and _effect_kind[slot] == kind:
			return {"at": _effect_at[slot], "dir": _effect_dir[slot], "core": _effect_core[slot], "ramp": _effect_ramp[slot],
					"zoom": _effect_zoom[slot], "look": _effect_look[slot], "seconds": _effect_seconds[slot]}
	return {}


## The actor id of a hit body (a kit Actor's `id`), or Actors.NONE for anything else.
static func _actor_of(target: Node) -> int:
	return (target as Actor).id if target is Actor else ActorsScript.NONE


## The hat ramp (0-3) of the actor `target` is, or -1 for an actor of the enemy ramp, no actor or
## an unknown one.
func _hat_ramp_of(target: Node) -> int:
	var id: int = _actor_of(target)
	if id == ActorsScript.NONE:
		return -1
	var ramp: int = _ramp_of(id)
	return ramp if ProjectileManagerScript.is_hat_ramp(ramp) else -1


## The actor table: `actors`, else the "Actors" autoload.
func _actor_table() -> ActorsScript:
	if actors != null:
		return actors if is_instance_valid(actors) else null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"Actors") as ActorsScript if tree != null and tree.root != null else null


## The budget of `caster` (its seat, or SHARED: no actor too), for what Feel keeps per budget.
func _budget_of(caster: int) -> int:
	var table: ActorsScript = _actor_table()
	return table.budget_of(caster) if table != null else ActorsScript.SHARED


## The ramp of `caster`'s spells (NONE for no actor: the enemy ramp).
func _ramp_of(caster: int) -> int:
	var table: ActorsScript = _actor_table()
	return table.ramp_of(caster) if table != null else ActorsScript.NONE


## A death: its ghost, the cue `enemy_death` (a white-hot ring; the killer and the shot hold for
## the kill, the dead body is freed at once) or, for a boss, `boss_death`, which also stops the
## whole game; and a puff. The puff is the killing blow's own spray turned into a bigger one when
## it is at this spot (one slot, and the hit's sound gives way to the death's), else a new puff
## in the enemy colour after the cue's ring.
func _on_enemy_died(killer: int, enemy: Node, position: Vector2, shot: int) -> void:
	_start_ghost(enemy)
	var zoom: int = clampi(roundi(preset.death_particle_size), 1, 3)
	var upgraded: bool = particles_enabled and _upgrade_hit(position, zoom)
	if upgraded and _hit_voice >= 0:
		_voices[_hit_voice].stop()
	play_cue(&"boss_death" if _is_boss(enemy) else &"enemy_death", killer, position, Vector2.ZERO, 0.0, Color.WHITE, 0, ActorsScript.NONE, shot)
	if particles_enabled and not upgraded:
		show_effect(KIND_PUFF, position, Vector2.RIGHT, preset.enemy_hit_color, 0, 0, zoom, PUFF_SECONDS)


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
		# Its cue is as big as the card's radius.
		if look.has("cue"):
			look["radius"] = (card as FormBase).radius
	cache[form] = look
	return look


func _on_spell_cast(player: int, spell_id: StringName, origin: Vector2, direction: Vector2) -> void:
	if player < 0 or player >= ActorsScript.SEATS:
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


## A beam (drawn by `shot_beam.gdshader` in the element's ramp), a dash, and the moments that are
## cues (FORM_CUES, and a slam's impact), each with the cast's cards, in the caster's ramp: an
## enemy's look the same, in the enemy ramp (staffs F7). The beam and the dash keep state of their
## own (a beam's slot while it fades, where a dash left until it lands), so they stay in code.
func _on_form_shown(caster: int, form: StringName, origin: Vector2, direction: Vector2, length: float, tint: Color, look: int) -> void:
	if caster < ActorsScript.NONE or caster >= ActorsScript.ACTORS or not origin.is_finite():
		return
	var cue: StringName = FORM_CUES.get(form, &"") as StringName
	if form == &"slam":
		# A slam's impact is where its carrier ends: the cue its card's impact look names, as big as
		# its ring (`length`).
		cue = StringName(str(_form_look(form, false).get("cue", "")))
	if cue != &"":
		play_cue(cue, caster, origin, direction, length, tint, look)
		return
	var ramp: int = _ramp_of(caster)
	if form == &"zap":
		# An arc's zap or spark: lightning in the shot's colours (its infusion's, else its caster's).
		if length > 0.0 and direction != Vector2.ZERO and preset.arc_seconds > 0.0:
			show_effect(KIND_ARC, origin, direction, tint, ramp, look, 1, preset.arc_seconds * (1.0 if length > SPARK_LONGEST else 0.6), length)
		return
	if form == &"dash":
		# Only its dust here: the wizard picks its way (where it walks), so its streaks and cards
		# are its trail, and the ring comes where it lands.
		var who: int = _budget_of(caster)
		_dash_from[who] = origin
		_dash_core[who] = tint
		_dash_look[who] = look
		if length > 0.0 and direction != Vector2.ZERO:
			show_effect(KIND_DASH, origin, Vector2.RIGHT, tint, ramp, look, 1, DASH_SECONDS, 4.0)
		return
	if form != &"beam" or length <= 0.0 or direction == Vector2.ZERO:
		return
	var seconds: float = preset.beam_seconds
	if seconds <= 0.0:
		return
	# Each seat's caster reuses only its own oldest slots, so nobody's beams push out another's;
	# the actors no seat drives share one seat's worth (by budget), so a crowd never takes a seat's.
	var who: int = _budget_of(caster)
	var slot: int = who * FORMS_PER_PLAYER + _next_form[who]
	_next_form[who] = (_next_form[who] + 1) % FORMS_PER_PLAYER
	var node: MeshInstance2D = _forms[slot]
	var end: Vector2 = origin + direction.normalized() * length
	var path: PackedVector3Array = _form_paths[slot]
	path[0] = Vector3(origin.x, origin.y, 0.0)
	path[1] = Vector3(end.x, end.y, length)
	var material: ShaderMaterial = node.material as ShaderMaterial
	material.set_shader_parameter(&"core_override", Color(tint.r, tint.g, tint.b, 1.0))
	# A path of two points, BEAM_LEAD past each end, so the flares are whole.
	material.set_shader_parameter(&"beam_path", path)
	material.set_shader_parameter(&"beam_points", 2)
	material.set_shader_parameter(&"beam_width", BEAM_TEXTURE_HEIGHT)
	material.set_shader_parameter(&"beam_length", length)
	material.set_shader_parameter(&"beam_lead", BEAM_LEAD)
	material.set_shader_parameter(&"beam_start", origin)
	material.set_shader_parameter(&"beam_end", end)
	material.set_shader_parameter(&"beam_end_dir", direction.normalized())
	material.set_shader_parameter(&"beam_player", _beam_ramp(ramp))
	material.set_shader_parameter(&"beam_look", look)
	material.set_shader_parameter(&"beam_glow", preset.beam_alpha)
	var body: Color = Color.WHITE
	if projectiles != null and projectiles.has_method("tint_of"):
		body = projectiles.call("tint_of", caster) as Color
	_form_body[slot] = body
	_form_left[slot] = seconds
	_form_total[slot] = seconds
	node.visible = true
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
## Marks in `_thin_keep` which of the `all` points of live beam `i` to draw when it has more than
## LIVE_BEAM_POINTS: its two ends and the LIVE_BEAM_POINTS - 2 points where it turns most (a wall
## it bounces off turns it sharply, a target it bends at less, a point of a gentle curve hardly),
## the first of equal ones; the points of its gentlest curves are dropped. Only a path that long
## (many pierce cards on a homing beam, many bounces) comes here; its scratch grows to the
## longest path seen.
func _thin_beam(beams: Object, i: int, all: int) -> void:
	if _thin_keep.size() < all:
		_thin_keep.resize(all)
		_thin_turn.resize(all)
		_thin_points.resize(all)
	_thin_sorted.resize(all - 2)
	for n in all:
		_thin_points[n] = beams.call("beam_point", i, n)
	var prev: Vector2 = _thin_points[0]
	var here: Vector2 = _thin_points[1]
	for n in range(1, all - 1):
		var next: Vector2 = _thin_points[n + 1]
		var into: Vector2 = here - prev
		var out: Vector2 = next - here
		var turn: float = 0.0 if into.is_zero_approx() or out.is_zero_approx() else absf(into.angle_to(out))
		_thin_turn[n] = turn
		_thin_sorted[n - 1] = turn
		prev = here
		here = next
	_thin_sorted.sort()
	var room: int = LIVE_BEAM_POINTS - 2
	var least: float = _thin_sorted[all - 2 - room]
	var above: int = 0
	for n in range(1, all - 1):
		if _thin_turn[n] > least:
			above += 1
	var equal_room: int = room - above
	_thin_keep[0] = 1
	_thin_keep[all - 1] = 1
	for n in range(1, all - 1):
		var keep: bool = _thin_turn[n] > least
		if not keep and _thin_turn[n] == least and equal_room > 0:
			keep = true
			equal_room -= 1
		_thin_keep[n] = 1 if keep else 0


func _draw_live_beams() -> void:
	var count: int = 0
	# The beams' rows (`Spells.carrier(&"beam")`, a `CarrierBeam`).
	var beams: Object = spells.call("carrier", &"beam") if spells != null and spells.has_method("carrier") else null
	if beams != null:
		count = int(beams.call("beam_slots"))
	while _live_beams.size() < count:
		_live_beams.append(_make_beam())
		_live_paths.append(_make_beam_path())
	for i in _live_beams.size():
		var node: MeshInstance2D = _live_beams[i]
		if i >= count or not bool(beams.call("beam_on", i)):
			if node.visible:
				node.visible = false
			continue
		var all: int = int(beams.call("beam_point_count", i))
		var points: int = mini(all, LIVE_BEAM_POINTS)
		# A longer path keeps the points that shape it most (`_thin_beam`).
		var thin: bool = all > LIVE_BEAM_POINTS
		if thin:
			_thin_beam(beams, i, all)
		var reach: float = beams.call("beam_reach", i)
		var origin: Vector2 = beams.call("beam_point", i, 0) if points > 0 else Vector2.INF
		if reach <= 0.0 or points < 2 or not origin.is_finite():
			node.visible = false
			continue
		# Its path up to where it got: whole pieces, then the last one cut short, each point with
		# how far along the beam it is. The shader draws it BEAM_LEAD past each end, so the flares
		# there are whole.
		var path: PackedVector3Array = _live_paths[i]
		var walked: float = 0.0
		var prev: Vector2 = origin
		var used: int = 1
		var end_at: Vector2 = origin
		path[0] = Vector3(origin.x, origin.y, 0.0)
		for n in range(1, all):
			if used == LIVE_BEAM_POINTS:
				break
			if thin and _thin_keep[n] == 0:
				continue
			var point: Vector2 = _thin_points[n] if thin else beams.call("beam_point", i, n)
			var piece: float = prev.distance_to(point)
			if walked + piece >= reach:
				end_at = prev.move_toward(point, reach - walked)
				walked = reach
				path[used] = Vector3(end_at.x, end_at.y, walked)
				used += 1
				break
			walked += piece
			path[used] = Vector3(point.x, point.y, walked)
			end_at = point
			used += 1
			prev = point
		var before: Vector3 = path[used - 2]
		var end_dir: Vector2 = Vector2(before.x, before.y).direction_to(end_at)
		var since: float = beams.call("beam_since_hit", i)
		var left: float = beams.call("beam_left", i)
		var fade: float = clampf(left * 4.0, 0.0, 1.0)
		var flare: float = 1.0 + preset.beam_flare * maxf(1.0 - since / maxf(preset.beam_seconds * preset.beam_flare_share, 0.001), 0.0)
		var flicker: float = 1.0 - preset.beam_flicker_depth * float(int(since * preset.beam_flicker_rate) % 2)
		# Drawn across a fixed width; flare, flicker and fade swell and dissolve its pixels instead
		# of stretching them.
		var caster: int = beams.call("beam_caster", i)
		var body: Color = Color.WHITE
		if projectiles != null and projectiles.has_method("tint_of"):
			body = projectiles.call("tint_of", caster) as Color
		var tint: Color = beams.call("beam_tint", i)
		var material: ShaderMaterial = node.material as ShaderMaterial
		material.set_shader_parameter(&"core_override", Color(tint.r, tint.g, tint.b, 1.0))
		material.set_shader_parameter(&"body_tint", Color(body.r, body.g, body.b, fade * preset.beam_alpha))
		material.set_shader_parameter(&"beam_path", path)
		material.set_shader_parameter(&"beam_points", used)
		material.set_shader_parameter(&"beam_length", walked)
		material.set_shader_parameter(&"beam_lead", BEAM_LEAD)
		material.set_shader_parameter(&"beam_start", origin)
		material.set_shader_parameter(&"beam_end", end_at)
		material.set_shader_parameter(&"beam_end_dir", end_dir)
		material.set_shader_parameter(&"sim_time", _clock)
		# A growing beam is drawn wider as it hits wider (growth, rules R4f).
		var grown: float = float(beams.call("beam_growth", i)) if beams.has_method("beam_growth") else 1.0
		material.set_shader_parameter(&"beam_width", BEAM_WIDTH * grown)
		material.set_shader_parameter(&"beam_player", _beam_ramp(_ramp_of(caster)))
		material.set_shader_parameter(&"beam_look", int(beams.call("beam_look", i)) if beams.has_method("beam_look") else 0)
		material.set_shader_parameter(&"beam_fade", fade)
		material.set_shader_parameter(&"beam_swell", maxf(fade, 0.35) * flare * flicker * grown)
		material.set_shader_parameter(&"beam_glow", preset.beam_alpha)
		node.visible = true


## Show beam `slot` at `t` (1 just shown, 0 gone): its rim and glow swell for its first moments
## (the payoff), then thin and flicker, and it dissolves into pixels (`beam_swell`, `beam_fade`).
func _pose_form(slot: int, t: float) -> void:
	var body: Color = _form_body[slot]
	var age: float = 1.0 - t
	var material: ShaderMaterial = _forms[slot].material as ShaderMaterial
	material.set_shader_parameter(&"sim_time", _clock)
	material.set_shader_parameter(&"body_tint", Color(body.r, body.g, body.b, t * preset.beam_alpha))
	var flare: float = 1.0 + preset.beam_flare * maxf(1.0 - age / preset.beam_flare_share, 0.0)
	var step: int = int(age * _form_total[slot] * preset.beam_flicker_rate)
	var flicker: float = 1.0 - preset.beam_flicker_depth * float(step % 2)
	material.set_shader_parameter(&"beam_swell", t * flare * flicker)
	material.set_shader_parameter(&"beam_fade", t)


## Another staff went on show (the personality swap, living staffs H4): a poof along the staff,
## in the actor's ramp, moving with it.
func _on_staff_shown(caster: int, actor: Node, _staff: int) -> void:
	var body: Actor = actor as Actor
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return
	var offset: Vector2 = body.hand_offset + body.aim * POOF_ALONG
	var slot: int = show_effect(KIND_PUFF, body.global_position + offset, body.aim, Color.WHITE, _ramp_of(caster), POOF, POOF_ZOOM, POOF_SECONDS, 0.0, body)
	if slot >= 0:
		_effect_offset[slot] = offset


## A possession started: a ring closes on the possessed actor in the driver's ramp, with the sound
## `possess`.
func _on_possess_started(caster: int, actor: int) -> void:
	if _show_possession(caster, actor, KIND_RING_IN):
		_play(POSSESS_SOUND)


## A possession ended: a ring in the driver's ramp goes out from the actor let go (if it is there).
func _on_possess_ended(caster: int, actor: int) -> void:
	_show_possession(caster, actor, KIND_RING_OUT)


## A ring of `kind` on the body of `actor` (at its drawn body), in the ramp of `caster`. False
## when the body is gone.
func _show_possession(caster: int, actor: int, kind: int) -> bool:
	var table: ActorsScript = _actor_table()
	var body: Node2D = table.node_of(actor) as Node2D if table != null and actor != ActorsScript.NONE else null
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return false
	var at: Vector2 = body.global_position + ((body as Actor).body_offset if body is Actor else Vector2.ZERO)
	show_effect(kind, at, Vector2.RIGHT, Color.WHITE, _ramp_of(caster), 0, POSSESS_ZOOM, POSSESS_SECONDS)
	return true


func _on_player_downed(player: int) -> void:
	# The event names no position, so a downed wizard's cue draws nothing: the game-wide stop,
	# shake and sound only (its point is never used)...
	play_cue(&"player_downed", ActorsScript.NONE, Vector2.ZERO)
	# ...and, when their own (or a teammate's) spell did it, a note over them saying so: the
	# seat's own body (its home actor, also while the seat drives another), in its light shade.
	if combat == null or not combat.has_method("home_actor_of"):
		return
	var actor: int = combat.home_actor_of(player) as int
	var table: ActorsScript = _actor_table()
	if actor == ActorsScript.NONE or table == null:
		return
	var note: String = combat.downed_note_of(actor) as String
	var wizard: Node2D = table.node_of(actor) as Node2D
	if note.is_empty() or wizard == null:
		return
	_show_note(note, wizard.global_position if wizard.is_inside_tree() else wizard.position, ProjectileManagerScript.ramp_light(table.ramp_of(actor)), preset.downed_note_seconds)


## A hit's shake, looks and sound; its stop is already applied by the caller (`_hold_bodies`).
## A hit with an `aim` (the way the shot flew) sprays along it, `size` times as big, from `at`,
## in the ramp of `tint` (white: `player`'s colours); without one it is a puff at `position`.
func _juice(position: Vector2, shake: float, sound: StringName, aim: Vector2 = Vector2.ZERO, tint: Color = Color.WHITE, size: float = 1.0, at: Vector2 = Vector2.INF, player: int = 0) -> void:
	if shake_enabled:
		_refresh_camera()
		_trauma = minf(_trauma + shake, 1.0)
	if position != Vector2.INF and particles_enabled:
		var from: Vector2 = position if at == Vector2.INF else at
		var zoom: int = clampi(roundi(size), 1, 3)
		if aim != Vector2.ZERO:
			_hit_effect = show_effect(KIND_SPRAY, from, aim, tint, player, 0, zoom, SPRAY_SECONDS)
		else:
			_hit_effect = show_effect(KIND_PUFF, from, Vector2.RIGHT, tint, player, 0, zoom, PUFF_SECONDS)
		_hit_position = position
	_hit_voice = _play(sound)


## Turns the last hit's effect into a puff `zoom` big, as new, when it is still showing at
## `position` (a killing blow's spray becomes the death's puff: one slot). Returns true when it did.
func _upgrade_hit(position: Vector2, zoom: int) -> bool:
	var slot: int = _hit_effect
	if slot < 0 or _hit_position != position or _effect_seconds[slot] <= 0.0:
		return false
	_effect_kind[slot] = KIND_PUFF
	_effect_zoom[slot] = zoom
	_effect_age[slot] = 0.0
	_effect_seconds[slot] = PUFF_SECONDS
	return true


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


## The game-wide stop: `Engine.time_scale` drops for `seconds` of real time, for everyone. Only a
## downed player and a boss kill use it (melee I7, M2-staffs.md "Freezes in co-op"); a longer
## stop replaces a shorter one.
func _stop_game(seconds: float) -> void:
	if seconds > stop_left:
		stop_left = seconds
		_set_time_scale(preset.hit_stop_scale)


## The local stop of a hit or a kill: the attacker `attacker`, the target `target` and the shot
## that hit (`shot`, the event's; -1 for none) hold for `seconds`, and nothing
## else does: another player, another enemy and every other shot run on. A plain hit (not
## `strong`) holds a body only when its rest from the last stop is over, so a crowd of hits does
## not freeze it for ever; a kill or a reaction always holds. Either actor may be NONE.
func _hold_bodies(attacker: int, target: int, seconds: float, strong: bool, shot: int = -1) -> void:
	var table: ActorsScript = _actor_table()
	if table == null or seconds <= 0.0:
		return
	var held: bool = _hold_actor(table, attacker, seconds, strong)
	held = _hold_actor(table, target, seconds, strong) or held
	if held and projectiles != null and shot >= 0:
		projectiles.freeze_shot(shot, seconds)


func _hold_actor(table: ActorsScript, id: int, seconds: float, strong: bool) -> bool:
	if not table.is_open(id):
		return false
	# An id handed to a new body does not inherit the last body's rest.
	var node: Node = table.node_of(id)
	var body: int = node.get_instance_id() if node != null else 0
	if _rest_body[id] != body:
		_rest_body[id] = body
		_rest_until[id] = 0.0
	if not strong and _clock < _rest_until[id]:
		return false
	_rest_until[id] = _clock + seconds + preset.hit_stop_rest
	return table.hold(id, seconds)


## True for the death of a boss: an enemy whose data says `boss`.
static func _is_boss(enemy: Node) -> bool:
	return enemy is Actor and (enemy as Actor).data != null and (enemy as Actor).data.boss


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


## The shader's `beam_player` for `ramp`: the hat ramp 0-3, or -1 for the enemy ramp.
static func _beam_ramp(ramp: int) -> int:
	return ramp if ProjectileManagerScript.is_hat_ramp(ramp) else -1
