extends Node
## Feel: juice on every hit. One autoload ("Feel") that only reacts to events:
## `damage_dealt`, `enemy_died` and `player_downed`. It never changes damage,
## health or who wins, and it sends no events.
##
##     Feel.shake_enabled = false     # the setting: no screen shake (the pause menu's "Screen shake" switch, saved by core/save)
##     Feel.preset = load("res://gameplay/feel/presets/punchy.tres")
##
## On a hit it does four things, all the same for every player:
## - hit-stop is not Feel's: which bodies a hit, a kill or a cue holds still, and the game-wide stop
##   of a downed player or a boss kill, are the game's rule (Combat's `HitStop`, online-ready N4),
##   counted in ticks, the same with or without Feel. Feel draws what they do.
## - screen shake: trauma on the current Camera2D, off when `shake_enabled` is false.
## - a flash (see "Flashes" below): a spray along the hit (a white-hot cross, and its sparks
##   as motes), or a puff all round for a hit with no way. A kill turns its killing blow's
##   spray into a bigger puff, so it costs one slot, not two.
## - a white hit flash and a squash on the hit enemy's or wizard's `Sprite` node, on every hit
##   sprite however many (one shared flash material; no limit, owner 2026-10-31; a sprite that is
##   gone is skipped).
## - a white-hot ring where an enemy dies, and its body breaks into motes of its own art's
##   colours that fall and settle (S3, `Spectacle.break_body`; the enemy itself is freed at once).
## - a sound from `core/registry` by id; nothing plays on `null`.
##
## Every actor's damage numbers (props W5) are drawn by one child, `damage_number_drawer.gd`: each
## actor's `DamageNumbers` look tells its hits on the bus (`damage_number_shown`), and the
## "Damage numbers" setting (`damage_numbers_changed`) hides them.
##
## `projectile_impact` (from `core/projectiles`) says where a shot struck and which way it
## flew. On a character the hit becomes a spray along that way, in ember for an enemy and
## in the wizard's own colours for a wizard, a little bigger with more damage. On a wall or
## pillar it knocks stone chips back. Where a shot lands it shows a flash in the shot's own
## ramp and cards (see "Flashes" below).
##
## On `spell_cast` it plays the carrier card's `cast_cue` at the staff tip in the player's colours
## (`cast` unless the card names another: a flash, a ring for a ring carrier, and a little kick of
## the camera against the aim); where a shot strikes, its card's `impact_cue` (S6 2).
##
## A deflected shot (`shot_deflected`) flashes big and white where it turned, in its new caster's
## colours; a swing's block (`shot_blocked` while the projectile manager's `impact_carrier_card` is
## `swing`) is a parry: a big four-point star in Spark gold and a local stop on the parrying actor
## (melee I5).
##
## Every hit body is read by its actor (`Actor.id`): its ramp (`Actors.ramp_of`) colours the hit
## (a hat ramp in its light shade, `ProjectileManager.ramp_light`; the enemy ramp in ember), and a
## hit whose caster is the hit actor itself is a self-hit.
##
## Flashes (the glow look, 2026-10-27; the owner: "I only want the new style going forward"):
## every flare, spray, puff, ring, arc and status is drawn by the shots' own shaders (the sparks of
## a spray and a puff, and every chip, are motes since S3)
## (core/projectiles: `shot_flash.gdshader` for the flash kinds it draws from their curves (and
## the cracks on the floor), `shot_blast.gdshader` for an explosion's parts, `shot_arc.gdshader` for
## lightning, `shot_status.gdshader` for KIND_STATUS), one MultiMesh each,
## sharing `effect_slots` (a setting: Settings, "Effect slots", through `effect_slots_changed`),
## each with the core colour and look of the shot it comes from (`impact_core`, `impact_look` of
## the projectile manager), so a frost bolt lands in frost flecks and a lightning one in sparks,
## all glowing. A new flash takes the oldest slot when they are all busy. **Each flash is a kind
## of data** (docs/milestones/flash-kinds.md): a `FlashKind` file in content/flashes, read from the
## registry (`_read_flash_kinds`) into the flash shader's table (`flash_table.gd`), so a new look
## is a new file; a cue's `flash` part names it by id. How a caster's body
## moves when it casts is its carrier card's `staff_pose`, drawn by its look (ActorLook), not here.
## None of this touches the cast itself.
##
## Motes, floor marks and spell light (docs/milestones/spell-spectacle.md) are the spectacle's
## (`spectacle.gd`, a child of Feel; docs/milestones/spell-spectacle-2.md, S1): Feel's handlers
## tell it when (a hit sheds motes, a wall throws chips, a reaction a ring) and it says what, and
## it owns their settings and the room they are in. `motes()`, `marks()`, `light()` and the
## `set_*` of their settings are forwards to it.
##
## A cue (`play_cue`, `CueBase`) is played part by part through a table of part players by part
## type (`add_cue_part`): Feel's own flashes (`flash`) and the spectacle's `motes` and `mark`
## parts, each handed the part and the cue's `CueContext` (one kept per depth, so a cue allocates
## nothing). A new kind of part is a player added to the table and a row in `CueBase.PART_TYPES`.
##
## Nothing is allocated while playing: the flash batch and sound players are made once.
## They live under this autoload (top level, so in world space), never under the scene:
## Flow frees the world on every Play and restart.

const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
## The look of a hit kind with no entry at all: nothing changes. Shared, never written.
const NO_LOOK: Dictionary = {}
const FeelPresetScript :=preload("res://gameplay/feel/presets/feel_preset.gd")
const HIT_FLASH_SHADER: Shader = preload("res://gameplay/feel/hit_flash.gdshader")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const BatchesScript := preload("res://core/projectiles/batches.gd")
## The shot shaders Feel draws with (core/README.md, "The shot shaders"): beams; the flashes'
## batches (flares, arcs, statuses, explosions).
const BEAM_SHADER: Shader = preload("res://core/projectiles/shot_beam.gdshader")
const FLASH_SHADER: Shader = preload("res://core/projectiles/shot_flash.gdshader")
const ARC_SHADER: Shader = preload("res://core/projectiles/shot_arc.gdshader")
const STATUS_SHADER: Shader = preload("res://core/projectiles/shot_status.gdshader")
const BirthsScript := preload("res://gameplay/feel/births.gd")
const BLAST_SHADER: Shader = preload("res://core/projectiles/shot_blast.gdshader")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SwingTrailsScript := preload("res://gameplay/feel/swing_trails.gd")
const PortalLookScript := preload("res://gameplay/feel/portal_look.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const MarksScript := preload("res://gameplay/feel/marks.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const SpectacleScript := preload("res://gameplay/feel/spectacle.gd")
const LanesScript := preload("res://gameplay/feel/lanes.gd")
const CueContextScript := preload("res://gameplay/feel/cue_context.gd")
const CuePlanScript := preload("res://gameplay/feel/cue_plan.gd")
const BodyLooksScript := preload("res://gameplay/feel/body_looks.gd")
const FlashTableScript := preload("res://gameplay/feel/flash_table.gd")
const PartyCameraScript := preload("res://gameplay/feel/party_camera.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const DamageNumberDrawerScript := preload("res://gameplay/feel/damage_number_drawer.gd")
## Beams on screen per player: one cast makes at most 24 shots (the spell limit),
## so a split fan is drawn whole; past that the player's oldest slot is taken over.
const SHOWN_BEAMS_PER_PLAYER: int = 24
## Four players' beam sprites and the enemies' (one share for every enemy caster, staffs F7).
const SHOWN_BEAM_SLOTS: int = SHOWN_BEAMS_PER_PLAYER * 5
## The share of the beam sprites every enemy's beam takes turns in.
const ENEMY_SHOWN_BEAMS: int = 4
## Beams and rings draw above the room, under the shots (50) and the flashes (20).
const SHOWN_BEAM_Z: int = 18
## Where the spectacle draws (`spectacle.gd`): the motes under the beams and every flash and
## telegraph, the floor marks on the floor under every body, spell light just under the motes.
const MOTE_Z: int = SpectacleScript.MOTE_Z
const MARK_Z: int = SpectacleScript.MARK_Z
const LIGHT_Z: int = SpectacleScript.LIGHT_Z
## Flashes on the floor (a quake's cracks, a slam's burst and star: `FlashKind.on_floor`, a cue
## part's `floor`) draw with the floor marks: over the room's floor (`RoomBase.FLOOR_Z`), under
## every body (the wizards and enemies at 0 and up; it was SHOWN_BEAM_Z - 1 and drew over them).
const FLOOR_Z: int = MARK_Z
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
## The quad kinds of a beam's mesh (`beam_mesh`; Q_* in `shot_beam.gdshader`): the light round
## each piece of its path, each piece's pixels.
const BEAM_Q_PIECE_LIGHT: int = 0
const BEAM_Q_PIECE: int = 1
## The mesh's quads in drawing order, as (kind, slots, 1 when the slots run backwards): the
## lights first, the beam's own pixels last.
const BEAM_QUADS: Array[Vector3i] = [
	Vector3i(BEAM_Q_PIECE_LIGHT, LIVE_BEAM_POINTS - 1, 0),
	Vector3i(BEAM_Q_PIECE, LIVE_BEAM_POINTS - 1, 0),
]
## A beam's motes (spell spectacle 2, S6 item 10; the beam shader drew them until then), given off
## as births (`Spectacle.births`, `_beam_motes`): where it lands, BEAM_SPLASH_RATE sparks a second
## (the shader's 6, each about a sixth of a second) thrown back off its end while it is more than
## BEAM_SPLASH_FADE whole; along it, each of its card particles (4, and 2 a card kind, at most
## BEAM_PARTICLES_MOST, as the shader had them) BEAM_PARTICLE_RATE times a second (the shader's 2.5
## to 4), from a random point of it, out to either side.
const BEAM_SPLASH_RATE: float = 36.0
const BEAM_SPLASH_FADE: float = 0.3
const BEAM_PARTICLE_RATE: float = 3.25
const BEAM_PARTICLES_MOST: int = 12

## Sounds that can play at once.
const SOUND_VOICES: int = 8
## The share of the effect slots a frame's hit flashes leave to the rest (casts, kills,
## statuses): `effect_slots` / this (`_flashes_shown`).
const HIT_FLASH_RESERVE: int = 4
## The voices a frame's hit sounds may start (`_hit_sounds`): past them each would only cut short
## one of the same frame before it was heard, and the rest stay free for kills, casts and cues.
const HIT_SOUNDS_PER_FRAME: int = SOUND_VOICES / 2
## Room for sprites reacting to a hit made at first; every hit sprite flashes (owner,
## 2026-10-31: no limit on interactions), and the room doubles when a crowd needs more, up to the
## largest crowd seen, and is kept.
const REACT_START: int = 64
## Reaction names (labels) rising at once.
const REACTION_SLOTS: int = 4
## Characters that show a status at once (a flash that follows each), and how often the
## statuses are read in seconds.
const STATUS_SLOTS: int = 16
const STATUS_POLL: float = 0.1
## How far a reaction's name rises while it shows, in pixels.
const REACTION_RISE: float = 10.0
## A reaction's name is not shown again while the first still rises within `REACTION_LABEL_NEAR`
## pixels; its sound and shake come at most every `CueBase.REACTION_REPEAT` seconds (the game's
## hit-stop counts the same).
## How long a reaction's name rises, in seconds.
const REACTION_NAME_SECONDS: float = 0.75
const REACTION_LABEL_NEAR: float = 40.0
## The damage a hit spray is sized for (the fire bolt's); more is a bigger spray, less a smaller one.
const SPRAY_REF_DAMAGE: int = 5
const SPRAY_MIN_SIZE: float = 0.7
const SPRAY_MAX_SIZE: float = 1.6
## The flash kinds' folder in the registry (content/flashes; `FlashKind`).
const FLASH_FOLDER: StringName = &"flashes"
## Feel's codes for its flashes (`_flash_kind` of a slot): a kind the flash shader draws from the
## table is FLASH_TABLE + its row; the rest are drawn by shaders of their own, each its code there
## (K_* in core/projectiles/shot_palette.gdshaderinc; an explosion's part less KIND_SHELL in
## `shot_blast.gdshader`). A status's glow (`shot_status.gdshader`) is no kind of content.
const KIND_ARC: int = 14
const KIND_STATUS: int = 15
const KIND_SHELL: int = 16
const KIND_FIREBALL: int = 17
const FLASH_TABLE: int = 256
## The code a table flash's row carries beside its age (any of 0-15 does: the shader reads its kind
## from the row's transform; 15 keeps the age finest where the custom data is kept as half floats).
const FLASH_TABLE_CODE: int = 15
## The codes of the kinds drawn by shaders of their own, by their `draw`.
const DRAW_KINDS: Dictionary = {&"shell": KIND_SHELL, &"fireball": KIND_FIREBALL, &"arc": KIND_ARC}
## The look bit that makes a flash take its colour exactly (a reaction's own colour) instead
## of the palette material it is nearest (kind 24 in the shader).
const EXACT: int = 1 << 23
## Another staff on show plays the cue `staff_swap` (S6, item 9) along the new staff, following the
## body.
const STAFF_SWAP: StringName = &"staff_swap"
## An explosion's parts (the flash kinds `shell` and `fireball`), drawn by `shot_blast.gdshader` in
## a batch of their own; their fragments and rubble are motes and their scorch a floor mark (S3, the
## cues' `motes` and `mark` parts). The square each is drawn in: BLAST_SPAN radii each way (the
## shader's; its seconds are the kinds' own, keep them equal).
const BLAST_SPAN: float = 2.2
## What `_carrier_cues_of` answers: the places of a carrier card's cues and radius, and the defaults.
const CUE_CAST: int = 0
const CUE_SHOWN: int = 1
const CUE_IMPACT: int = 2
const CUE_END: int = 3
const CUE_RADIUS: int = 4
const CUE_WIND: int = 5
const NO_CARRIER_CUES: Array = [&"cast", &"", &"impact", &"", 0.0, &"wind"]
## The cue of a shield's block (combat plays it for a barrier's, Feel for a shot's own shield).
const SHIELD_BLOCK_CUE: StringName = &"shield_block"
## The pixels a step of a hit's spray or puff is (its cue's size is its steps times this: the
## `spray` and `puff` kinds' own step).
const HIT_STEP: float = 12.0
## `play_cue`'s body colour when there is none (alpha 0), and its ramp when not given: the caster's.
const NO_BODY := Color(0.0, 0.0, 0.0, 0.0)
const CASTER_RAMP: int = -100
## A status effect lasts until its status ends (Feel ends it).
const FOREVER: float = 1.0e9
## A discharge arc is drawn along its length (in steps of 4 px, as long as it is: `shot_arc.gdshader`
## reads it from its quad), ARC_MARGIN past each end, ARC_ACROSS across (the shader's).
const ARC_MARGIN: float = 12.0
const ARC_ACROSS: float = 56.0
## The cue of a discharge's arc (`discharge_arc`; content/cues).
const DISCHARGE_ARC: StringName = &"discharge_arc"
## A status effect's zoom (round a character of about 16 px) and how far above its feet it sits.
const STATUS_ZOOM: int = 2
## The registry folder the element cards a status is shown as are in (`_status_card`).
const STATUS_CARD_FOLDER: StringName = &"spells"
const STATUS_RISE: float = 8.0
## A beam is drawn this wide (its core, rim, flares and glow; `shot_beam.gdshader`'s mode 1).
const BEAM_WIDTH: float = 16.0
## How far a beam's quad reaches past each end, so its flares are whole (the shader's beam_lead).
const BEAM_LEAD: float = 8.0
## The most infusions a live beam hands its look (the shader's `beam_infusions[8]`); more are left
## out of its drawing only.
const BEAM_INFUSIONS_MOST: int = 8
const FLASH_Z: int = 50
## The flash quad is the shot shader's grid times the zoom (LOOK_GRID in core/projectiles).
const FLASH_GRID: float = 24.0
const FLASH_STRIDE: int = 16
## The age code beside a flash's kind: TRACE_FROM + TRACE_SPAN x how far through it is. A row's
## transform carries two more numbers in its unused floats (full precision, where the custom data
## may be kept as half floats): its table row (a table kind's, else 0) and how much it lights the
## room at its start (0 for a flash that does not: `_flash_light`; spell light reads it).
const FLASH_FROM: float = 0.02
const FLASH_SPAN: float = 0.42
## The quad kinds of a flash's mesh (`flash_mesh`; Q_* in `shot_flash.gdshader`): its light, a
## poof's clouds and its flash. A flash's sparks and card particles are motes, thrown by its
## cue's motes parts (S6, item 3), not quads of its mesh.
const FLASH_Q_LIGHT: int = 0
const FLASH_Q_CLOUD: int = 3
const FLASH_Q_SHAPE: int = 4
## The mesh's quads in drawing order, as (kind, slots, 1 when the slots run backwards): the light
## first, then the clouds (the first on top), the flash last: 4 clouds.
## The blast mesh's quads (`blast_mesh`; Q_* in `shot_blast.gdshader`): its light, then
## BLAST_PIECES pieces (chunks, lobes, puffs, embers), each part using what it needs.
const BLAST_Q_LIGHT: int = 0
const BLAST_Q_PIECE: int = 1
const BLAST_PIECES: int = 22
const BLAST_QUADS: Array[Vector3i] = [
	Vector3i(BLAST_Q_LIGHT, 1, 0),
	Vector3i(BLAST_Q_PIECE, BLAST_PIECES, 0),
]
const FLASH_QUADS: Array[Vector3i] = [
	Vector3i(FLASH_Q_LIGHT, 1, 0),
	Vector3i(FLASH_Q_CLOUD, 4, 1),
	Vector3i(FLASH_Q_SHAPE, 1, 0),
]
## How long a muzzle flash is compared with its width.
## The biggest camera kick in pixels, however fast the casting.
const MAX_KICK_PIXELS: float = 4.0
## The cues of a possession starting and ending, on the possessed body (`possess_started`,
## `possess_ended`; content/cues).
const POSSESS_START: StringName = &"possess_start"
const POSSESS_END: StringName = &"possess_end"

## The services. Only tests set these, before adding the node; otherwise the
## autoloads are used.
var events: EventsScript = null
## The registry and the projectile manager are handed on to the spectacle whenever they change.
var registry: RegistryScript = null:
	set(value):
		registry = value
		_status_cards.clear()
		if _flash_node != null:
			_read_flash_kinds()
		if _spectacle != null:
			_spectacle.registry = value
		if _numbers != null:
			_numbers.registry = value
## The projectile manager (typed, so its `impact_*` facts are read as members: every hit and every
## shot's end reads them; performance, 2026-11-02).
var projectiles: ProjectileManagerScript = null:
	set(value):
		projectiles = value
		if _spectacle != null:
			_spectacle.projectiles = value
## The combat autoload, asked only `status_left(enemy, id)` to know when a status ends.
var combat: Node = null
## The spell runtime, asked only for its live beams (`beam_*`) to draw them every frame.
var spells: Node = null
## The actor table, which says the ramp, seat and budget of a caster (actors G3b). Only tests set
## it; otherwise the "Actors" autoload.
var actors: ActorsScript = null
## The "Actors" autoload once found (`_actor_table`), while it is still there.
var _auto_actors: ActorsScript = null
## Tests turn this off: Feel steps only when the test calls `step` (no real clock in `_process`).
var drive_engine: bool = true
## The stress benchmark turns this off to time a scene without hit particles (the bursts are
## skipped as when the pool is empty; flashes, numbers and sound stay).
var particles_enabled: bool = true:
	set(value):
		particles_enabled = value
		if _spectacle != null:
			_spectacle.particles_enabled = value

var preset: FeelPresetScript = null
var shake_enabled: bool = true:
	set(value):
		shake_enabled = value
		if not value:
			_trauma = 0.0
			_kick = Vector2.ZERO
			_reset_camera()
## The last hit `_on_damage_dealt` gave its flash, hold and sound, by the hit actor's id: the
## physics frame and Feel's step (`_steps`), the body (instance id), the attacker and the kind.
## Another hit with all of them the same (no time has passed for Feel or the game) would only do
## them again: the flash is restarted to the same time, the hold is refused for
## both bodies (each rests from the first), and the same sound would start on the next voice in the
## same frame. So it skips them (a crowd of shots on one body: 2026-11-02, "Sandbox storm").
var _juiced_frame: PackedInt64Array = PackedInt64Array()
var _juiced_step: PackedInt64Array = PackedInt64Array()
## Feel's steps so far (`step`).
var _steps: int = 0
var _juiced_body: PackedInt64Array = PackedInt64Array()
var _juiced_by: PackedInt32Array = PackedInt32Array()
var _juiced_kind: Array[StringName] = []
## Current offset applied to the camera.
var shake_offset: Vector2 = Vector2.ZERO

## Shake strength, 0 to 1.
var _trauma: float = 0.0
var _camera: Camera2D = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## The effect slot, spot and sound voice of the latest plain hit since the last step, so a
## kill at the same spot upgrades them instead of using a second slot and sound.
var _hit_slot: int = -1
var _hit_position: Vector2 = Vector2.INF
var _hit_voice: int = -1
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
## Hit reactions: the sprite, the scale it had, and seconds left (parallel arrays, the first
## `_react_count` in use; they grow to the largest crowd seen and never shrink, so a busy frame
## allocates only the first time). Instance ids, not references: a sprite may be freed while it
## waits, and an array cannot hold a freed object. `_react_actor` is the actor id of each (-1 for a
## body that is no actor), and `_react_of_actor` the reaction of each actor id (checked against its
## sprite), so a hit finds its reaction without searching a thousand.
var _react_count: int = 0
var _react_actor: PackedInt32Array = PackedInt32Array()
var _react_of_actor: PackedInt32Array = PackedInt32Array()
var _react_sprites: PackedInt64Array = PackedInt64Array()
var _react_scale: PackedVector2Array = PackedVector2Array()
var _react_written: PackedVector2Array = PackedVector2Array()
var _react_left: PackedFloat32Array = PackedFloat32Array()
## Per reaction: its length in seconds and its squash (a hit squashes wide and low, a
## cast thin and tall, which is negative).
var _react_total: PackedFloat32Array = PackedFloat32Array()
var _react_amount: PackedFloat32Array = PackedFloat32Array()
var _hit_flash_material: ShaderMaterial = null
## The live beams (`Spells.carrier(&"beam")`), one beam mesh each (`beam_mesh`), made once, and each one's
## path as the shader takes it (x, y and how far along the beam; `beam_path`).
var _live_beams: Array[MeshInstance2D] = []
## Each carrier card's own look as an area of Feel draws it, asked of Spells once and kept
## (`_carrier_look_of`; docs/milestones/card-looks.md): {Carrier.LOOK_BEAM or LOOK_SWING: {card id:
## CardLook}}. Beams' and swing trails' materials take its shader; a beam's light its light. Feel
## reads no card field.
var _carrier_looks: Dictionary = {}
## The swings' trails (`swing_trails.gd`, melee I4), drawn from `Spells`' live swings every frame.
var _swing_trails: SwingTrailsScript = null
## The open portals' gates (`PortalLookScript`), drawn every frame from one typed read of them
## (`CarrierPortal.read_view` into `_portal_view`, refilled each frame).
var _portal_look: PortalLookScript = null
var _portal_view: PortalView = PortalView.new()
## The spectacle (`spectacle.gd`): motes, floor marks, spell light and their settings.
var _spectacle: SpectacleScript = null
## The party's shared camera, eased towards Coop's view (`view_fitted`) as it is drawn.
var party_camera: PartyCameraScript = PartyCameraScript.new()
## The telegraph lanes of casts winding up (`lane` cue parts; docs/milestones/cast-timing.md, T6b).
var _lanes: LanesScript = null
## Every actor's damage numbers (`damage_number_drawer.gd`, props W5).
var _numbers: DamageNumberDrawerScript = null
## Its settings, read through Feel (read only; their `set_*` below).
var mote_cap: int:
	get:
		return _spectacle.mote_cap if _spectacle != null else MoteCap.default_cap()
var mote_density: float:
	get:
		return _spectacle.mote_density if _spectacle != null else MoteDensity.DEFAULT
var floor_marks: bool:
	get:
		return _spectacle.floor_marks if _spectacle != null else FloorMarks.default_on()
var spell_light: bool:
	get:
		return _spectacle.spell_light if _spectacle != null else SpellLightSetting.default_on()
## The players of a cue's parts by part type, each [player, prepare] (`add_cue_part`; a part with no
## `part` is a `flash`), the cues read for playing by id (`CuePlan`, `_plan_of`), the cue contexts
## kept for them (one per depth of a cue played inside a cue's part), and the parts of a type no
## player plays, skipped (`unknown_cue_parts`, warned once per type).
var _cue_parts: Dictionary = {}
var _cue_plans: Dictionary = {}
var _cue_contexts: Array[CueContextScript] = []
var _cue_depth: int = 0
var unknown_cue_parts: int = 0
## The slot of the last flash a cue's part showed (-1 for none): a hit's spray, whose sound a kill
## at its spot silences (`_hit_slot`).
var _cue_flash: int = -1
var _unknown_part_warned: Dictionary = {}
var _live_paths: Array[PackedVector3Array] = []
## Scratch of `_thin_beam`: the points of a long path (read once, drawn from here), which of them
## are drawn, how sharply it turns at each, and those turns sorted.
var _thin_points: PackedVector2Array = PackedVector2Array()
var _thin_keep: PackedByteArray = PackedByteArray()
var _thin_turn: PackedFloat32Array = PackedFloat32Array()
var _thin_sorted: PackedFloat32Array = PackedFloat32Array()
## Beams shown whole (beam meshes made once) and their paths of two points: seconds left and in
## all, the owner's body tint and the beam's length in pixels.
var _shown_beams: Array[MeshInstance2D] = []
var _shown_beam_paths: Array[PackedVector3Array] = []
var _shown_beam_left: PackedFloat32Array = PackedFloat32Array()
var _shown_beam_total: PackedFloat32Array = PackedFloat32Array()
var _shown_beam_body: PackedColorArray = PackedColorArray()
var _shown_beam_length: PackedFloat32Array = PackedFloat32Array()
## Each one's motes: its caster's shader ramp (`_beam_ramp`), its look, its tint and its spell's tag.
var _shown_beam_ramp: PackedInt32Array = PackedInt32Array()
var _shown_beam_look: PackedInt32Array = PackedInt32Array()
var _shown_beam_tint: PackedColorArray = PackedColorArray()
var _shown_beam_tag: PackedInt64Array = PackedInt64Array()
var _next_shown_beam: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])
## Reaction names: one label per reaction flash slot, with where it starts and seconds left.
var _labels: Array[Label] = []
var _label_left: PackedFloat32Array = PackedFloat32Array()
## The seconds a label was given (0: a reaction name's own REACTION_NAME_SECONDS).
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
## How each status is shown (`_status_card`: its element card's `status_look()`), found once; an
## empty Array for none.
var _status_cards: Dictionary = {}
## The cue of each reaction id (`CueBase.reaction_cue`), found the first time it is
## seen (so it allocates once).
var _reaction_cues: Dictionary = {}
## Display names by reaction id, built the same way.
var _reaction_names: Dictionary = {}
## Real seconds since feel started, and when each reaction id last gave a sound and a shake.
var _clock: float = 0.0
## The flashes' batches, one per shader (see "Flashes" above): the flares, the arcs, the
## statuses, and the marks on the floor (the flares' shader, lower); each has room for every slot.
var _flash_node: MultiMeshInstance2D = null
var _flash_buffer: PackedFloat32Array = PackedFloat32Array()
static var _flash_mesh: ArrayMesh = null
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
static var _blast_mesh: ArrayMesh = null
var _flash_kind: PackedInt32Array = PackedInt32Array()
var _flash_at: PackedVector2Array = PackedVector2Array()
var _flash_dir: PackedVector2Array = PackedVector2Array()
var _flash_core: PackedColorArray = PackedColorArray()
## Each flash's ramp (`Actors.ramp_of` of its caster; 0-3 a hat ramp, anything else the enemy ramp).
var _flash_ramp: PackedInt32Array = PackedInt32Array()
var _flash_zoom: PackedInt32Array = PackedInt32Array()
var _flash_look: PackedInt32Array = PackedInt32Array()
var _flash_age: PackedFloat32Array = PackedFloat32Array()
var _flash_seconds: PackedFloat32Array = PackedFloat32Array()
var _flash_length: PackedFloat32Array = PackedFloat32Array()
## The character a flash follows (a status), or null, and how far above it the flash sits.
var _flash_follow: Array[Node2D] = []
## How much each flash lights the room at its start: its kind's `room_light`, 0 for one shown by a
## cue with a `light` part (S6, item 4: that lights instead) or a status.
var _flash_light: PackedFloat32Array = PackedFloat32Array()
## Whether the cue whose parts are playing now lights by its own `light` part (`play_cue`), so the
## flashes it shows are unlit.
var _cue_unlit: bool = false
## Where a followed flash sits from its node (a status rises above it, a poof sits on the staff).
var _flash_offset: PackedVector2Array = PackedVector2Array()
## The actor whose staff tip each flash sits on, turning with its live aim (a wind-up's ring:
## `Spells.aim_origin_of`), or NONE; its `_flash_offset` is then from the tip, along the aim.
var _flash_tip: PackedInt32Array = PackedInt32Array()
## 1 for a flash drawn on the floor under the bodies by its cue part (`floor`; a slam's), as its
## kind's `on_floor` draws the cracks.
var _flash_floor: PackedByteArray = PackedByteArray()
## The actor whose staff tip the flashes of the cue playing now sit on (`_on_cast_winding`), or NONE.
var _cue_tip: int = ActorsScript.NONE
var _next_flash: int = 0
## The flashes shown since the last step drew them (`_show_flash`), and whether the flash being
## shown is a hit's own (its spray or impact, `_hit_flash`). A frame's hit flashes stop at
## `effect_slots` less HIT_FLASH_RESERVE (shot scale H3): past it, each would take the slot of a
## flash of the same frame before it was ever drawn, and the rest stay free for what is not a hit.
var _flashes_shown: int = 0
var _hit_flash: bool = false
## Hit sounds started since the last step (HIT_SOUNDS_PER_FRAME).
var _hit_sounds: int = 0
## The step the camera was last looked for (`_refresh_camera`: once a step, not once a hit).
var _camera_step: int = -1
## The flash kinds (content/flashes, `_read_flash_kinds`), in id order: a table kind's row is its
## place here. Each id's code (`_flash_kind` of a slot), its row for a cue's flash part
## (`CuePlan.flash_of`: code, step, seconds, drawn along a length), and each code's room light; the
## table kinds drawn on the floor (by row).
var _flash_kinds: Array[FlashKind] = []
var _flash_codes: Dictionary = {}
var _flash_rows: Dictionary = {}
var _code_light: Dictionary = {}
var _table_floor: PackedByteArray = PackedByteArray()
## How many flashes can show at once (`EffectSlots.DEFAULT` until the setting changes it; see
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
## The shot's tag, and whether its hit sprays its motes (its staff's share, rolled once at the
## impact, `Spectacle.begin_hit`): the damage's spray follows the same roll.
var _impact_tag: int = 0
var _impact_shown: bool = false
## Whether that hit shows its look (`_body_looks`: a few hits of a staff on a body a frame); its damage
## follows the same answer.
var _impact_looked: bool = true
## The hit looks each body showed this frame, per staff (`body_looks.gd`).
var _body_looks: BodyLooksScript = BodyLooksScript.new()
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
## Camera kick of casts (pixels), added to the shake.
var _kick: Vector2 = Vector2.ZERO
var _last_usec: int = 0
## The cues and radius read from the carrier cards, by card id (see `_carrier_cues_of`).
var _carrier_cues: Dictionary = {}
## The cues read from `content/cues`, by id (see `cue_of`).
var _cue_cache: Dictionary = {}
## The cues that play at most `every` seconds apart (`CueBase.every`): each one's first index in
## `_cue_next_at` by id, and there, by actor (its id + 1: none first), the clock time (`_clock`)
## from which it may play again. Grown once per such cue, then written in place.
var _cue_every_at: Dictionary = {}
var _cue_next_at: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	_rng.seed = 1
	_juiced_frame.resize(ActorsScript.ACTORS)
	_juiced_frame.fill(-1)
	_juiced_step.resize(ActorsScript.ACTORS)
	_juiced_body.resize(ActorsScript.ACTORS)
	_juiced_by.resize(ActorsScript.ACTORS)
	_juiced_kind.resize(ActorsScript.ACTORS)
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if registry == null:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if preset == null:
		preset = load("res://gameplay/feel/presets/punchy.tres") as FeelPresetScript
	_last_usec = Time.get_ticks_usec()
	_hit_flash_material = ShaderMaterial.new()
	_hit_flash_material.shader = HIT_FLASH_SHADER
	ShaderWarmupScript.want(HIT_FLASH_SHADER, ShaderWarmupScript.RECT)
	for i in SHOWN_BEAM_SLOTS:
		_shown_beams.append(_make_beam())
		_shown_beam_paths.append(_make_beam_path())
	_make_flashes()
	for i in LIVE_BEAMS:
		_live_beams.append(_make_beam())
		_live_paths.append(_make_beam_path())
	_swing_trails = SwingTrailsScript.new(swing_mesh())
	add_child(_swing_trails)
	_portal_look = PortalLookScript.new()
	add_child(_portal_look)
	_spectacle = SpectacleScript.new()
	_spectacle.name = "Spectacle"
	_spectacle.events = events
	_spectacle.registry = registry
	_spectacle.particles_enabled = particles_enabled
	add_child(_spectacle)
	# The floor flashes (a slam's burst and star) share the floor marks' z; at one z the later node
	# draws on top, so they come after the spectacle, whose mark layer (made whenever the setting
	# turns on) is inside it: a new strike shows over the marks earlier ones left.
	move_child(_floor_node, _spectacle.get_index())
	_lanes = LanesScript.new()
	_lanes.name = "Lanes"
	# Over the shots and every flash: a telegraph is the brightest thing on screen (docs/STYLE.md).
	_lanes.z_index = SHOWN_BEAM_Z + 2
	add_child(_lanes)
	_numbers = DamageNumberDrawerScript.new()
	_numbers.name = "DamageNumbers"
	_numbers.events = events
	_numbers.registry = registry
	add_child(_numbers)
	add_cue_part(&"flash", _play_flash, _prepare_flash)
	add_cue_part(&"lane", _play_lane)
	var parts: Dictionary = _spectacle.cue_parts()
	for type: StringName in parts:
		var row: Array = parts[type] as Array
		add_cue_part(type, row[0] as Callable, row[1] as Callable if row.size() > 1 else Callable(), row[2] as Callable if row.size() > 2 else Callable())
	_shown_beam_left.resize(SHOWN_BEAM_SLOTS)
	_shown_beam_total.resize(SHOWN_BEAM_SLOTS)
	_shown_beam_body.resize(SHOWN_BEAM_SLOTS)
	_shown_beam_length.resize(SHOWN_BEAM_SLOTS)
	_shown_beam_ramp.resize(SHOWN_BEAM_SLOTS)
	_shown_beam_look.resize(SHOWN_BEAM_SLOTS)
	_shown_beam_tint.resize(SHOWN_BEAM_SLOTS)
	_shown_beam_tag.resize(SHOWN_BEAM_SLOTS)
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
	events.barrier_changed.connect(_on_barrier_changed)
	events.staff_shown.connect(_on_staff_shown)
	events.possess_started.connect(_on_possess_started)
	events.possess_ended.connect(_on_possess_ended)
	events.projectile_impact.connect(_on_projectile_impact)
	events.carrier_shown.connect(_on_carrier_shown)
	events.cast_winding.connect(_on_cast_winding)
	events.carrier_ended.connect(_on_carrier_ended)
	events.cue_shown.connect(_on_cue_shown)
	events.reaction_triggered.connect(_on_reaction_triggered)
	events.discharge_arc.connect(_on_discharge_arc)
	events.status_applied.connect(_on_status_applied)
	events.effect_slots_changed.connect(_on_effect_slots_changed)
	events.screen_shake_changed.connect(_on_screen_shake_changed)
	events.projectile_expired.connect(_on_projectile_expired)
	events.shot_deflected.connect(_on_shot_deflected)
	events.shot_blocked.connect(_on_shot_blocked)
	events.room_entered.connect(_on_room_entered)
	events.view_fitted.connect(_on_view_fitted)
	if combat == null:
		combat = get_node_or_null("/root/Combat")
	if projectiles == null:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectileManagerScript
	if spells == null:
		spells = get_node_or_null("/root/Spells")
	_warm_card_looks()
	if _portal_look != null and spells is SpellRuntime:
		_portal_look.use_shaders((spells as SpellRuntime).look_shaders(Carrier.LOOK_PORTAL))
	if projectiles != null and projectiles.texture == null:
		projectiles.texture = preset.bolt_texture
	_spectacle.attach(projectiles, spells)


func _process(delta: float) -> void:
	var real_delta: float = delta
	if drive_engine:
		# Real time from the clock, so a test's or benchmark's tick rate cannot skew it.
		var now: int = Time.get_ticks_usec()
		real_delta = minf(float(now - _last_usec) / 1000000.0, 0.25)
		_last_usec = now
	step(real_delta)


## Advance by `real_delta` seconds of real time (not slowed by hit-stop).
func step(real_delta: float) -> void:
	_steps += 1
	_body_looks.new_frame()
	_hit_slot = -1
	_hit_voice = -1
	_clock += real_delta
	if _trauma > 0.0 or _kick != Vector2.ZERO:
		_trauma = maxf(_trauma - preset.shake_decay * real_delta, 0.0)
		var strength: float = _trauma * _trauma * preset.max_shake_pixels
		shake_offset = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * strength
		if _trauma == 0.0:
			shake_offset = Vector2.ZERO
		_kick = _kick.move_toward(Vector2.ZERO, preset.cast_kick_decay * real_delta)
		shake_offset += _kick
		_apply_camera()
	party_camera.follow(_live_camera())
	party_camera.step(real_delta)
	_step_reactions(real_delta)
	_step_shown_beams(real_delta)
	_step_flashes(real_delta)
	_flashes_shown = 0
	_hit_sounds = 0
	_draw_live_beams(real_delta)
	if _swing_trails != null:
		_swing_trails.step(spells.call("carrier", &"swing") if spells != null and spells.has_method("carrier") else null, _clock, _swing_ramp, preset.beam_alpha, _spectacle.births if _spectacle.motes_on() else null, _swing_shader_of)
	if _portal_look != null:
		_step_portals()
	_status_motes(real_delta)
	_spectacle.step(_clock, _actor_table())
	if _lanes != null:
		_lanes.spells = spells
		_lanes.step()
	_step_labels(real_delta)
	if _numbers != null:
		_numbers.step(real_delta)
	_step_statuses(real_delta)


## The open portals, read once (`CarrierPortal.read_view`), drawn by the portal look; their motes
## into the spectacle's pool while motes are on.
func _step_portals() -> void:
	var portals: CarrierPortal = CarrierPortal.of(spells as SpellRuntime) if spells is SpellRuntime else null
	if portals != null:
		portals.read_view(_portal_view)
	else:
		_portal_view.portals = 0
		_portal_view.gates = 0
	_portal_look.step(_portal_view, _actor_table(), _spectacle.pool if _spectacle.motes_on() else null, _clock)


## Flash and squash the hit sprites for `real_delta` seconds, and put back those done.
func _step_reactions(real_delta: float) -> void:
	var at: int = _react_count - 1
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
			_drop_reaction(at)
		else:
			var squash: float = _react_amount[at] * _react_left[at] / maxf(_react_total[at], 0.001)
			_react_written[at] = _react_scale[at] * Vector2(1.0 + squash, 1.0 - squash)
			sprite.scale = _react_written[at]
		at -= 1


## The world transform a dead body's art is broken from (S3, `Spectacle.break_body`): its sprite's,
## at its rest scale (a body killed mid-squash would otherwise break squashed).
func _rest_transform(sprite: Sprite2D, dead: Node) -> Transform2D:
	var rest: Vector2 = sprite.global_scale
	var at: int = _find_reaction(sprite.get_instance_id(), _actor_of(dead))
	if at >= 0 and sprite.scale.x != 0.0 and sprite.scale.y != 0.0:
		rest = rest / sprite.scale * _react_scale[at]
	return Transform2D(sprite.global_rotation, rest, 0.0, sprite.global_position)


## The Sprite2D a body shows as: its `Sprite` child; null for none.
func _body_sprite(body: Node) -> Sprite2D:
	if body == null or not is_instance_valid(body):
		return null
	return body.get_node_or_null("Sprite") as Sprite2D


## Start the white flash and the squash (wide and low) of the hit node's `Sprite` child, if it
## has one, for `hit_flash_seconds`; a hit on a sprite still reacting starts it again.
func _react(target: Node) -> void:
	var seconds: float = preset.hit_flash_seconds
	var amount: float = preset.hit_squash
	if seconds <= 0.0 or target == null or not is_instance_valid(target):
		return
	var sprite := target.get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	var id: int = sprite.get_instance_id()
	var actor: int = _actor_of(target)
	var at: int = _find_reaction(id, actor)
	if at < 0:
		if _react_count == _react_sprites.size():
			_grow_reactions(maxi(_react_count * 2, REACT_START))
		at = _react_count
		_react_count += 1
		_react_sprites[at] = id
		_react_actor[at] = actor
		if actor >= 0 and actor < _react_of_actor.size():
			_react_of_actor[actor] = at
		_react_scale[at] = sprite.scale
		_react_written[at] = sprite.scale
	_react_left[at] = seconds
	_react_total[at] = seconds
	_react_amount[at] = amount
	# One material shared by every flashing sprite (its flash is the shader's): nothing per flash.
	sprite.material = _hit_flash_material


## The reaction of the sprite with instance id `sprite` (of the actor `actor`, -1 for none), or -1.
func _find_reaction(sprite: int, actor: int) -> int:
	if actor >= 0 and actor < _react_of_actor.size():
		var at: int = _react_of_actor[actor]
		return at if at >= 0 and at < _react_count and _react_sprites[at] == sprite else -1
	var found: int = _react_sprites.find(sprite)
	return found if found < _react_count else -1


## Reaction `at` ends: the last one takes its place.
func _drop_reaction(at: int) -> void:
	var last: int = _react_count - 1
	var actor: int = _react_actor[at]
	if actor >= 0 and actor < _react_of_actor.size() and _react_of_actor[actor] == at:
		_react_of_actor[actor] = -1
	if at != last:
		_react_sprites[at] = _react_sprites[last]
		_react_actor[at] = _react_actor[last]
		_react_scale[at] = _react_scale[last]
		_react_written[at] = _react_written[last]
		_react_left[at] = _react_left[last]
		_react_total[at] = _react_total[last]
		_react_amount[at] = _react_amount[last]
		var moved: int = _react_actor[at]
		if moved >= 0 and moved < _react_of_actor.size() and _react_of_actor[moved] == last:
			_react_of_actor[moved] = at
	_react_sprites[last] = 0
	_react_count = last


## Room for `size` reactions (they only grow), and the index by actor id once.
func _grow_reactions(size: int) -> void:
	if _react_of_actor.is_empty():
		_react_of_actor.resize(ActorsScript.ACTORS)
		_react_of_actor.fill(-1)
	_react_sprites.resize(size)
	_react_actor.resize(size)
	_react_scale.resize(size)
	_react_written.resize(size)
	_react_left.resize(size)
	_react_total.resize(size)
	_react_amount.resize(size)


## A run starts (`room_entered`): no reaction was heard and no hit was juiced, so the first ones
## shake and sound (view only since N4: the holds are the game's, `HitStop`).
func _on_room_entered(_room_id: StringName) -> void:
	party_camera.room_entered()
	_reaction_heard.clear()
	_juiced_frame.fill(0)
	_juiced_step.fill(0)
	_juiced_body.fill(0)
	_juiced_by.fill(0)
	_juiced_kind.fill(&"")


## The party's view (`view_fitted`, Coop's, on the tick): the party camera heads for it, on the
## world's camera now (a new room's, at its first view).
func _on_view_fitted(view: Rect2, party: Rect2) -> void:
	_camera_step = -1
	_refresh_camera()
	party_camera.follow(_live_camera())
	party_camera.fitted(view, party)


## The camera followed now, or null when it is gone (a freed world's).
func _live_camera() -> Camera2D:
	return _camera if _camera != null and is_instance_valid(_camera) else null


## Sprites flashing right now (for tests).
func reacting_sprites() -> int:
	return _react_count


## Current camera kick in pixels (for tests).
func kick() -> Vector2:
	return _kick


## Current shake strength, 0 to 1.
func trauma() -> float:
	return _trauma


func _on_damage_dealt(caster: int, target: Node, amount: float, position: Vector2) -> void:
	if not _damage_look_shown(target, caster):
		# Past its body's looks this frame for its staff: no spray, squash, shake or sound.
		_impact_target = 0
		_kind_target = 0
		return
	var hit_id: int = _actor_of(target)
	var repeat: bool = _repeat_hit(hit_id, target, caster)
	if not repeat:
		_react(target)
	var aim: Vector2 = Vector2.ZERO
	var at: Vector2 = position
	var tint: Color = Color.WHITE
	var size: float = 1.0
	var colours: int = 0
	# The spray's motes are a hit's: the shot's impact's roll when it did this hit, else one of its own.
	var held: bool = false
	if target != null and is_instance_valid(target):
		# An actor of a hat ramp is hit in its own colours: white, its ramp; the rest in their own
		# colour (`EnemyBase.hit_color`).
		var ramp: int = _hat_ramp_of_id(hit_id)
		if ramp >= 0:
			colours = ramp
		else:
			tint = _hit_color_of(target)
		# The shot that did this hit told us where it struck and which way it flew.
		if target.get_instance_id() == _impact_target and caster == _impact_caster and Engine.get_physics_frames() == _impact_frame:
			aim = _impact_aim
			at = _impact_at
			held = true
			_spectacle.hold_hit(caster, _impact_tag, _impact_shown)
			size = clampf(1.0 + float(amount - SPRAY_REF_DAMAGE) * preset.hit_spray_per_damage, SPRAY_MIN_SIZE, SPRAY_MAX_SIZE)
	_impact_target = 0
	# The kind of the hit came just before (`hit_landed`): its shake and sound (its stop is the
	# game's, `HitStop`).
	# A hit of part of a point (an atom's speck) shakes as much as its share, so a stream of them
	# is not a quake.
	var shake: float = preset.hit_shake * minf(amount, 1.0)
	var sound: StringName = preset.hit_sound
	var own: bool = false
	if target != null and target.get_instance_id() == _kind_target and Engine.get_physics_frames() == _kind_frame:
		# Its kind's look, else a shot's, else none (one read of the table each).
		var looks: Dictionary = preset.kind_looks
		var found: Variant = looks.get(_kind)
		if found == null:
			found = looks.get(&"shot", NO_LOOK)
		var look: Dictionary = found as Dictionary
		shake *= look.get("shake", 1.0) as float
		sound = look.get("sound", preset.hit_sound) as StringName
		own = _kind_own
	_kind_target = 0
	var voice: int = _hit_voice
	if not held:
		_spectacle.begin_hit(caster, 0)
	_juice(position, shake, &"" if repeat else sound, aim, tint, size, at, colours)
	_spectacle.end_hit()
	if repeat:
		# The sound of the hit it repeats is still this hit's (a kill stops it, `_on_enemy_died`).
		_hit_voice = voice
	if own:
		# Their own spell: the cue `self_hit` (a ring in its own colour) on this frame, so it is
		# never taken for an enemy's hit.
		play_cue(&"self_hit", caster, position)


## True when the hit on `target` (the actor `id`) by `caster` repeats the last one this physics
## frame and Feel step that was flashed, held and heard (same body, attacker and kind: `_juiced_*`); else it
## becomes that hit. Only an actor's hits are told apart.
func _repeat_hit(id: int, target: Node, caster: int) -> bool:
	if id < 0 or id >= _juiced_frame.size() or target == null:
		return false
	var frame: int = Engine.get_physics_frames()
	var body: int = target.get_instance_id()
	var kind: StringName = _kind if body == _kind_target and frame == _kind_frame else &""
	if _juiced_frame[id] == frame and _juiced_step[id] == _steps and _juiced_body[id] == body and _juiced_by[id] == caster and _juiced_kind[id] == kind:
		return true
	_juiced_frame[id] = frame
	_juiced_step[id] = _steps
	_juiced_body[id] = body
	_juiced_by[id] = caster
	_juiced_kind[id] = kind
	return false


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


## An element reaction fired at `position`: its cue (`reaction_<id>`, else `reaction`;
## content/cues: a puff, a ring and a ring of the reacting shot's motes in the reaction's own
## colour, a hold, shake and its sound, as strong as its `power`), and its name rising from the spot
## in that colour. The cue's weight (hold, shake, sound) comes at most every `CueBase.REACTION_REPEAT` seconds
## per reaction, its looks every time. The same for every player; it changes nothing in the fight.
func _on_reaction_triggered(caster: int, reaction_id: StringName, position: Vector2, shot: int) -> void:
	if not _reaction_names.has(reaction_id):
		_reaction_names[reaction_id] = String(reaction_id).capitalize()
	if not _reaction_cues.has(reaction_id) and registry != null:
		_reaction_cues[reaction_id] = CueBase.reaction_cue(reaction_id, cue_of)
	var id: StringName = _reaction_cues.get(reaction_id, CueBase.REACTION_CUE) as StringName
	var heard: bool = _clock - (_reaction_heard.get(reaction_id, -CueBase.REACTION_REPEAT) as float) < CueBase.REACTION_REPEAT
	if not heard:
		_reaction_heard[reaction_id] = _clock
	# The reaction's own hit (kind `reaction`) holds its target by the plain rule; a hold only ever
	# lengthens, so whichever of the two comes first, the caster is held for the longer one.
	play_cue(id, caster, position, Vector2.ZERO, 0.0, Color.WHITE, projectiles.get_look_of(shot) if projectiles != null and shot >= 0 else 0, ActorsScript.NONE, shot, -1, 0, not heard)
	if _label_showing(reaction_id, position):
		return
	var cue: CueBase = cue_of(id)
	var slot: int = _next_reaction
	_next_reaction = (_next_reaction + 1) % REACTION_SLOTS
	var label: Label = _labels[slot]
	var shown: String = _reaction_names[reaction_id] as String
	if label.text != shown:
		label.text = shown
	label.modulate = cue.color if cue != null and cue.color.a > 0.0 else Color.WHITE
	_label_start[slot] = position + Vector2(-label.get_minimum_size().x * 0.5, -18.0)
	label.global_position = _label_start[slot]
	label.visible = true
	_label_left[slot] = REACTION_NAME_SECONDS
	_label_total[slot] = 0.0
	_label_id[slot] = reaction_id


## A discharge jumped from `from` to `to`: the cue `discharge_arc` from the one to the other, as
## long as the gap (a jagged line of lightning in the discharge's colour that burns out; its `arc`
## part, KIND_ARC).
func _on_discharge_arc(caster: int, from: Vector2, to: Vector2) -> void:
	play_cue(DISCHARGE_ARC, caster, from, to - from, from.distance_to(to))


## Discharge arcs showing right now (for tests).
func live_arcs() -> int:
	return _count_flashes(KIND_ARC)


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


## Read the statuses now and then; end the flash of a status that ended.
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


## Keep status `at` shown: a flash that follows its character, a glow in its card's colour
## (`status_color`), started again if a crowd of other flashes took its slot. Hidden while the
## character's sprite is. Its motes are `_status_motes`'.
func _pose_status(at: int) -> void:
	var enemy := instance_from_id(_status_enemies[at]) as Node2D
	var card: Array = _status_card(_status_shown[at])
	var sprite: CanvasItem = null
	if enemy != null:
		sprite = enemy.get_node_or_null("Sprite") as CanvasItem
	if enemy == null or card.is_empty() or (sprite != null and not sprite.is_visible_in_tree()):
		_end_status_effect(at)
		return
	var slot: int = _status_effect[at]
	if slot >= 0 and slot < effect_slots and _flash_seconds[slot] > 0.0 and _flash_follow[slot] == enemy:
		return
	var layer: int = card[ElementBase.STATUS_LOOK_LAYER] as int
	var bits: int = ProjectileManagerScript.pack_look(PackedInt32Array([layer])) if layer > 0 else 0
	_status_effect[at] = _show_flash(KIND_STATUS, enemy.global_position, Vector2.RIGHT, status_color(_status_shown[at]), 0, bits | EXACT, STATUS_ZOOM, FOREVER, 0.0, enemy)


## How status `id` is shown (spell spectacle 2, S6 item 11): the `status_look()` of the element
## card whose status it is, or for a status no element puts on (freeze), of the one whose status it
## deepens from (`FeelPreset.deep_statuses`): [status, tint, look layer, card id], ElementBase's
## STATUS_LOOK_*. Empty for none (an unknown status shows nothing). Found once in the registry's
## cards.
func _status_card(id: StringName) -> Array:
	var from: StringName = preset.deep_statuses.get(id, id) as StringName
	if _status_cards.has(from):
		return _status_cards[from] as Array
	var found: Array = []
	if registry != null and from != &"":
		for card: Resource in registry.get_all(STATUS_CARD_FOLDER):
			if not card is ElementBase:
				continue
			var look: Array = (card as ElementBase).status_look()
			if look[ElementBase.STATUS_LOOK_STATUS] as StringName == from:
				found = look
				break
	_status_cards[from] = found
	return found


## Whether status `id` is shown at full depth (`FeelPreset.deep_statuses`: freeze).
func _status_deep(id: StringName) -> bool:
	return preset.deep_statuses.has(id)


## The colour status `id` glows in and its motes cool from: its card's tint, `status_deep_white` of
## the way to white for a deep one (freeze); white for a status with no card.
func status_color(id: StringName) -> Color:
	var card: Array = _status_card(id)
	if card.is_empty():
		return Color.WHITE
	var tint: Color = card[ElementBase.STATUS_LOOK_TINT] as Color
	tint.a = 1.0
	return tint.lerp(Color.WHITE, preset.status_deep_white) if _status_deep(id) else tint


## The shown statuses' motes over `real_delta` seconds (S6 item 11; the status shader's particles
## until then): each gives off its card's motes round its character, `status_mote_rate` a second
## (`status_deep_motes` times that for a deep one), in its colour.
func _status_motes(real_delta: float) -> void:
	if real_delta <= 0.0 or not _spectacle.motes_on():
		return
	for at in _status_enemies.size():
		if _status_effect[at] < 0:
			continue
		var enemy := instance_from_id(_status_enemies[at]) as Node2D
		var id: StringName = _status_shown[at]
		var card: Array = _status_card(id)
		if enemy == null or card.is_empty():
			continue
		var rate: float = preset.status_mote_rate * (preset.status_deep_motes if _status_deep(id) else 1.0)
		var count: int = floori(rate * real_delta + _rng.randf())
		if count > 0:
			_spectacle.status_motes(card[ElementBase.STATUS_LOOK_CARD] as StringName, card[ElementBase.STATUS_LOOK_LAYER] as int, enemy.global_position, 4.0 * STATUS_ZOOM, status_color(id), count)


## End the flash that shows status `at`, if it still shows it.
func _end_status_effect(at: int) -> void:
	var slot: int = _status_effect[at]
	var enemy := instance_from_id(_status_enemies[at]) as Node2D
	if slot >= 0 and slot < effect_slots and _flash_kind[slot] == KIND_STATUS and _flash_follow[slot] == enemy:
		_flash_seconds[slot] = 0.0
		_flash_follow[slot] = null
	_status_effect[at] = -1


## The status shown on `enemy` (empty for none), for tests.
func status_shown(enemy: Node) -> StringName:
	var at: int = _status_enemies.find(enemy.get_instance_id())
	if at < 0 or _status_effect[at] < 0:
		return &""
	return _status_shown[at]


## Statuses showing right now (for tests).
func live_statuses() -> int:
	return _count_flashes(KIND_STATUS)


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
		var total: float = _label_total[i] if _label_total[i] > 0.0 else REACTION_NAME_SECONDS
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


## Whether the hit on `target` by `caster` that `damage_dealt` announces shows its look: as its shot's
## impact decided (`_impact_looked`), else counted now (`_body_looks`, by the caster's first staff). A
## hit of no body always shows.
func _damage_look_shown(target: Node, caster: int) -> bool:
	if target == null or not is_instance_valid(target):
		return true
	var body: int = target.get_instance_id()
	if body == _impact_target and caster == _impact_caster and Engine.get_physics_frames() == _impact_frame:
		return _impact_looked
	return _body_looks.take(body, SpectacleScript.hit_group(caster, 0))


## A shot struck. On a character, remember how, for the damage event that follows at once; a hit
## past its body's looks this frame for its staff (`_body_looks`) shows nothing, nor does its damage.
## On a wall or pillar (`target` is null), show the impact.
func _on_projectile_impact(caster: int, target: Node, position: Vector2, direction: Vector2) -> void:
	var tag: int = projectiles.impact_tag if projectiles != null else 0
	if target == null:
		_wall_impact(caster, tag, position, direction)
		return
	_impact_target = target.get_instance_id()
	_impact_caster = caster
	_impact_frame = Engine.get_physics_frames()
	_impact_looked = _body_looks.take(_impact_target, SpectacleScript.hit_group(caster, tag))
	if not _impact_looked:
		_impact_shown = false
		return
	var ramp: int = _ramp_of(caster)
	# One hit: its motes all spray or none do, by its staff's share of the frame's (`hit_shares.gd`).
	_impact_shown = _spectacle.begin_hit(caster, tag)
	_impact_at = position
	_impact_aim = direction
	_impact_tag = tag
	# Its cards' motes back along the way it came, in its own ramp.
	if projectiles != null:
		_spectacle.shed_hit(position, -direction, projectiles.impact_core, ramp, projectiles.impact_look, preset.hit_mote_share, tag)
	_hit_flash = true
	_show_impact(caster, ramp, position, direction)
	_hit_flash = false
	_spectacle.end_hit()


## A shot of `caster`'s (tagged `tag`) ended on a wall or pillar at `position`, flying `direction`:
## knocked back off the surface, the shot's own motes and the wall's, and its impact.
func _wall_impact(caster: int, tag: int, position: Vector2, direction: Vector2) -> void:
	var ramp: int = _ramp_of(caster)
	_spectacle.begin_hit(caster, tag)
	_spectacle.shed_on_wall(ramp, position, -direction)
	_show_impact(caster, ramp, position, direction)
	_spectacle.end_hit()


## A bolt or orbit shot whose life ran out goes off: the cue `expire` (a small pop of its own
## colours where it was and a puff of its cards' motes on along the way it flew, a share of their
## count; S6), with the shot's own look while the event is sent. One that ended on a wall already
## showed its impact, and a still one (a rune, a wall's stone) goes off its own way.
func _on_projectile_expired(caster: int, position: Vector2, tag: int, shot: int) -> void:
	if projectiles == null or projectiles.expired_on_wall:
		return
	var body: int = projectiles.impact_body
	if body != ProjectileManagerScript.KIND_BOLT and body != ProjectileManagerScript.KIND_ORBIT:
		return
	play_cue(&"expire", caster, position, projectiles.impact_heading, 0.0, projectiles.impact_core, projectiles.impact_look, ActorsScript.NONE, shot, -1, tag)


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


## A shot was blocked. A shot's own shield (`shot`, the shielded shot) blocks as a barrier does: its
## shell loses that charge's motes (`barriers.gd`) and the cue `shield_block` plays where the
## blocked shot was, turned back toward the shield. A swing's block is a parry (`shield · swing`; the
## projectile manager's `impact_carrier_card` says which carrier blocked): the cue `parry`, a big
## four-point star in Spark gold and a local stop on the parrying actor alone. Other carriers'
## blocks show nothing of their own.
func _on_shot_blocked(caster: int, position: Vector2, _tag: int, shot: int) -> void:
	if projectiles == null or not position.is_finite():
		return
	if shot >= 0:
		var from: Vector2 = projectiles.get_position_of(shot)
		play_cue(SHIELD_BLOCK_CUE, caster, position, (position - from).normalized() if from.is_finite() and from != position else Vector2.ZERO)
		_spectacle.shot_blocked(shot, position)
		return
	if projectiles.impact_carrier_card != &"swing":
		return
	play_cue(CueBase.PARRY_CUE, caster, position)


## The payoff of a shot, on a body or a wall: the `impact_cue` of the card the shot is (the
## projectile manager's `impact_carrier_card` while the impact is sent; `impact`, a flare, for none), in the
## shot's colour and cards (its `impact_core`, `impact_look` and `impact_tag`) and its caster's `ramp`:
## an enemy's lands the same way, in the enemy ramp (staffs F7: one look for every spell). As big as
## the card's radius: a rune goes off in `rune_burst`, a wall's adds a ring (`impact_ring`).
func _show_impact(caster: int, ramp: int, position: Vector2, direction: Vector2) -> void:
	var carrier_card: StringName = &""
	var core: Color = Color.WHITE
	var bits: int = 0
	var tag: int = 0
	if projectiles != null:
		carrier_card = projectiles.impact_carrier_card
		core = projectiles.impact_core
		bits = projectiles.impact_look
		tag = projectiles.impact_tag
	var cues: Array = _carrier_cues_of(carrier_card)
	play_cue(cues[CUE_IMPACT] as StringName, caster, position, direction, cues[CUE_RADIUS] as float, core, bits, ActorsScript.NONE, -1, -1, tag, true, NO_BODY, ramp)


## Play the cue `id` (a `CueBase`, `content/cues/<id>.tres`; `cue_shown` calls this) at `at`, set
## off by `caster` (NONE for none: the enemy ramp; its body is where `away` punches from) along
## `dir`, `size` pixels big (what a part's `reach` is times; the seconds a `lasts_size` part
## lasts), in its ramp with `tint` (as `show_flash`'s `core`) and the cards of the packed `look`,
## on `target` (an actor, for `hold_target`), sent by `shot`, for what broke in the colours of the
## ramp-table source `surface` (a dying body's art; -1: the room's walls), of the spell of `tag` (its
## cards' motes and marks; 0: the tag of `shot`, if any), in `ramp` (a hat ramp, or the enemy ramp:
## for a moment of a seat or of a hit body rather than of the caster's spell, a seat's cast; CASTER_RAMP:
## the caster's, `Actors.ramp_of`). Plays its parts, each by
## the player of its type (`add_cue_part`), then its weight: holds, the game-wide stop, shake and
## punch (both off with the screen shake setting) and its sound; with `weight` false, its parts
## only (a reaction repeated within `CueBase.REACTION_REPEAT`). `body_color` is the own colour of the body
## the cue is of (a dying enemy's `EnemyBase.hit_color`), for its `body` flashes (alpha 0: none).
## With `follow` (a body), its flashes move with that body while they last, where they were played
## from it, and end when it is gone (S6, item 9: a staff's swap, a possession's ring).
## Its `power` is applied here and in the parts' players, by one rule (`CueBase`): times its sizes
## and counts, its holds, shake and punch. A cue with an `every` played again for the same actor
## sooner than that plays nothing (`_cue_due`). An unknown cue plays nothing. A cue is read once for
## playing (`_plan_of`, `CuePlan`). With `follow` (a body), its flashes move with that body while
## they last, where they were played from it, and end when it is gone (S6, item 9: a staff's swap,
## a possession's ring).
func play_cue(id: StringName, caster: int, at: Vector2, dir: Vector2 = Vector2.ZERO, size: float = 0.0, tint: Color = Color.WHITE, look: int = 0, target: int = ActorsScript.NONE, shot: int = -1, surface: int = -1, tag: int = 0, weight: bool = true, body_color: Color = Color(0.0, 0.0, 0.0, 0.0), ramp: int = CASTER_RAMP, follow: Node2D = null) -> void:
	if not at.is_finite() or caster < ActorsScript.NONE or caster >= ActorsScript.ACTORS:
		return
	var plan: CuePlanScript = _cue_plans.get(id) as CuePlanScript
	if plan == null:
		plan = _plan_of(id)
		if plan == null:
			return
	if plan.every > 0.0 and not _cue_due(plan.cue, caster):
		return
	if _hit_flash and not (weight and plan.weighted) and _hides_hit(plan):
		# A hit's look that would show nothing is not played (hundreds of hits a frame in a crowd).
		_cue_flash = -1
		return
	var aim: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	if _cue_depth == _cue_contexts.size():
		_cue_contexts.append(CueContextScript.new())
	var context: CueContextScript = _cue_contexts[_cue_depth]
	context.caster = caster
	context.ramp = _ramp_of(caster) if ramp == CASTER_RAMP else ramp
	context.at = at
	context.aim = aim
	context.size = size
	context.tint = tint
	context.look = look
	context.target = target
	context.shot = shot
	context.surface = surface
	context.body = body_color
	context.follow = follow if follow != null and is_instance_valid(follow) else null
	context.tag = tag if tag != 0 or shot < 0 or projectiles == null else projectiles.get_tag_of(shot)
	context.color = plan.color
	context.power = plan.power
	_cue_depth += 1
	# A cue with a `light` part lights by it alone: the flashes it shows light nothing (S6, item 4).
	var unlit_before: bool = _cue_unlit
	_cue_unlit = plan.lights
	var prepared: Array = plan.prepared
	var n: int = 0
	# A hit's flashes past the frame's share are skipped here, not called only to stop at once.
	var no_flashes: bool = _hit_flash and _hit_flashes_full()
	for player: Callable in plan.players:
		if no_flashes and prepared[n] is CuePlanScript.Flash:
			_cue_flash = -1
		else:
			player.call(prepared[n], context)
		n += 1
	if not plan.unknown.is_empty():
		for type: StringName in plan.unknown:
			_unknown_cue_part(id, type)
	_cue_unlit = unlit_before
	_cue_depth -= 1
	if not weight or not plan.weighted:
		return
	var cue: CueBase = plan.cue
	var power: float = plan.power
	# Its holds and game-wide stop are the game's (`HitStop`, online-ready N4), not drawn here.
	var table: ActorsScript = _actor_table() if cue.kick_way == &"away" else null
	if shake_enabled and (cue.shake > 0.0 or cue.kick > 0.0):
		_refresh_camera()
		_shake(cue.shake * power)
		var way: Vector2 = Vector2.DOWN
		var kick_way: StringName = cue.kick_way
		# Back or along its way only when it has one (a cast with no aim kicks nowhere).
		if kick_way == &"back":
			way = -aim if dir != Vector2.ZERO else Vector2.ZERO
		elif kick_way == &"aim":
			way = aim if dir != Vector2.ZERO else Vector2.ZERO
		elif kick_way == &"away":
			var body: Node2D = table.node_of(caster) as Node2D if table != null and table.is_open(caster) else null
			if body != null and body.global_position.distance_to(at) > 1.0:
				way = body.global_position.direction_to(at)
		_kick = (_kick + way * cue.kick * power).limit_length(MAX_KICK_PIXELS)
	_play(cue.sound)


## Whether `plan`, played as the look of the hit being shown, would show nothing: each of its parts
## is a flash past the frame's share of hit flashes or a part that needs a spray of a hit whose motes
## do not spray (`CuePlan.shows_always` and the two gates).
func _hides_hit(plan: CuePlanScript) -> bool:
	if plan.shows_always:
		return false
	if plan.has_flashes and not _hit_flashes_full():
		return false
	return not plan.has_spray_parts or (_spectacle != null and _spectacle.hit_unsprayed())


## Whether the cue `cue` (which has an `every`) may play for `caster` now, and if so, not again for
## its `every` seconds. Allocates only the first time a cue with an `every` plays.
func _cue_due(cue: CueBase, caster: int) -> bool:
	var first: Variant = _cue_every_at.get(cue.id)
	if first == null:
		first = _cue_next_at.size()
		_cue_every_at[cue.id] = first
		_cue_next_at.resize(int(first) + ActorsScript.ACTORS + 1)
		for i in ActorsScript.ACTORS + 1:
			_cue_next_at[int(first) + i] = -INF
	var at: int = int(first) + caster + 1
	if _clock < _cue_next_at[at]:
		return false
	_cue_next_at[at] = _clock + cue.every
	return true


## Play a cue's parts of the type `type` (`CueBase.PART_TYPES`) with `player`, a Callable taking
## the part (a Dictionary) and the cue's `CueContext`; a player already there is replaced. With
## `prepare` (a Callable taking the part), each part is prepared once when its cue is first played
## and `player` takes what it made instead, so a part played often reads no key while it plays
## (a flash's keys as typed fields: `CuePlan.Flash`). With `needs_spray` (a Callable taking what
## `player` takes), the parts it says true for show nothing for a hit whose motes do not spray
## (`Spectacle.hit_unsprayed`: the spectacle's `often` motes), so a hit's cue of only such parts and
## flashes is not played at all for a hit that would show none of them (`_hides_hit`). Leave it out
## for a type whose parts play whatever the hit. Feel's own flashes are `flash`, the spectacle's
## `motes` and `mark` (`Spectacle.cue_parts`).
func add_cue_part(type: StringName, player: Callable, prepare: Callable = Callable(), needs_spray: Callable = Callable()) -> void:
	_cue_parts[type] = [player, prepare, needs_spray]
	_cue_plans.clear()


## Whether a cue part of the type `type` has a player.
func has_cue_part(type: StringName) -> bool:
	return _cue_parts.has(type)


## A part of the cue `id` of a type nothing plays: skipped and counted, and warned of once per type
## (`CueBase.problems` names it in content; this is for a part a player was taken away from).
func _unknown_cue_part(id: StringName, type: StringName) -> void:
	unknown_cue_parts += 1
	if not _unknown_part_warned.has(type):
		_unknown_part_warned[type] = true
		push_warning("Feel: cue '%s' has a part of the type '%s', which nothing plays" % [id, type])


## A cue's flash part (`CueBase`: a part with no `part`, or `"part": "flash"`) read into its typed
## fields once (`CuePlan.flash_of`; null for a flash Feel has not: the plan leaves it out).
func _prepare_flash(part: Dictionary) -> Variant:
	return CuePlanScript.flash_of(part, _flash_rows)


## A cue's flash (`CuePlan.Flash`, from its part) played with `cue`: its flash at the cue's point
## along its way, sized by its `zoom` or the cue's size times its `reach` (either times the cue's
## power), for its seconds (or the cue's size with `lasts_size`), in its exact `color`, plain, bare,
## the cue's own colour, or the cue's ramp and tint with its cards (without them for `no_cards`).
func _play_flash(flash: CuePlanScript.Flash, cue: CueContextScript) -> void:
	if flash.particles and not particles_enabled:
		return
	if _hit_flash and _hit_flashes_full():
		_cue_flash = -1
		return
	if flash.gated:
		# Only for the cards it names: any card's layer, or one look layer (lightning's arc).
		var layers: int = cue.look & ((1 << MotesScript.LOOK_LAYERS) - 1)
		if flash.if_cards and layers == 0:
			return
		if flash.if_layer > 0 and (layers >> (flash.if_layer - 1)) & 1 == 0:
			return
		# Only at some sizes (a zap's short spark into the air against a zap at a body).
		if cue.size <= flash.size_over or cue.size > flash.size_upto:
			return
	var seconds: float = flash.seconds
	if flash.lasts_size:
		if cue.size <= 0.0:
			return
		seconds = cue.size
	var zoom: int
	var length: float = 0.0
	var steps: float = flash.reach_steps
	if steps >= 0.0:
		# Sized from the cue's: its size times the part's reach, in steps of the flash's zoom.
		zoom = roundi(cue.size * steps * cue.power)
	else:
		zoom = roundi(flash.zoom * cue.power)
		if flash.along:
			# Drawn along its length (an arc): the cue's size times its reach, from the cue's point.
			length = cue.size * (flash.reach if flash.reach >= 0.0 else 1.0)
			if length <= 0.0:
				return
	var way: Vector2 = cue.aim
	var turn: int = flash.way
	if turn != CuePlanScript.WAY_AIM:
		if turn == CuePlanScript.WAY_BACK:
			way = -way
		elif turn == CuePlanScript.WAY_RIGHT:
			way = Vector2.RIGHT
		else:
			way = Vector2.UP
	# Where on the cue's line (`along`, S6 item 9), and the body it follows (a staff's swap).
	var at: Vector2 = cue.at
	if flash.place >= 0.0:
		at += cue.aim * cue.size * flash.place
	var follow: Node2D = cue.follow if cue.follow != null and is_instance_valid(cue.follow) else null
	var paint: int = flash.paint
	if paint == CuePlanScript.PAINT_COLOR:
		_cue_flash = _show_flash(flash.kind, at, way, flash.color, 0, EXACT, zoom, seconds, length, follow)
	elif paint == CuePlanScript.PAINT_PLAIN:
		_cue_flash = _show_flash(flash.kind, at, way, Color.WHITE, 0, 0, zoom, seconds, length, follow)
	elif paint == CuePlanScript.PAINT_BARE:
		_cue_flash = _show_flash(flash.kind, at, way, Color.WHITE, cue.ramp, 0, zoom, seconds, length, follow)
	elif paint == CuePlanScript.PAINT_BODY:
		_cue_flash = _show_flash(flash.kind, at, way, cue.body if cue.body.a > 0.0 else Color.WHITE, 0, 0, zoom, seconds, length, follow)
	elif cue.color.a > 0.0:
		_cue_flash = _show_flash(flash.kind, at, way, cue.color, 0, EXACT, zoom, seconds, length, follow)
	else:
		_cue_flash = _show_flash(flash.kind, at, way, cue.tint, cue.ramp, 0 if paint == CuePlanScript.PAINT_NO_CARDS else cue.look, zoom, seconds, length, follow)
	# A ground strike's flash on the floor, under the bodies (its part's `floor`).
	if flash.floor and _cue_flash >= 0:
		_flash_floor[_cue_flash] = 1
	# A followed cue's flash sits where it was played from its body (S6, item 9).
	if follow != null and _cue_flash >= 0:
		_flash_offset[_cue_flash] = at - follow.global_position
	# One on a staff tip sits where it was played from the tip, along the aim, as the tip turns.
	if _cue_flash >= 0 and _flash_tip[_cue_flash] != ActorsScript.NONE:
		_flash_offset[_cue_flash] = (at - cue.at).rotated(-cue.aim.angle()) if cue.aim.is_finite() else Vector2.ZERO


## The cue `id` read for playing (`CuePlan`: its parts' players and prepared parts), made the first
## time it is played (`play_cue` keeps it by id) and again after a part player changed
## (`add_cue_part`) or `forget_cues`; null for no cue.
func _plan_of(id: StringName) -> CuePlanScript:
	var cue: CueBase = cue_of(id)
	if cue == null:
		return null
	var plan: CuePlanScript = _cue_plans.get(id) as CuePlanScript
	if plan == null or plan.cue != cue:
		plan = CuePlanScript.make(cue, _cue_parts) as CuePlanScript
		_cue_plans[id] = plan
	return plan


## Forget the cues read so far (`cue_of`, and their plans), so the next play reads them again (a
## cue file changed, or a test's own cue).
func forget_cues() -> void:
	_cue_cache.clear()
	_cue_plans.clear()


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
	play_cue(cue, caster, at, direction, size, tint, look, ActorsScript.NONE, -1, -1, _cue_tag())


## The spell runtime's tag of the spell whose cue, carrier card or carrier's end is being sent (its cards'
## motes and marks; `SpellRuntime.cue_tag`), 0 for none.
func _cue_tag() -> int:
	var tag: Variant = spells.get(&"cue_tag") if spells != null else null
	return tag if tag is int else 0


## A carrier with no shot ended (a teleport or dash landing, a slam striking, a
## decoy or familiar going): the streams its cues started end (a dash's streaks), and its card's
## `end_cue` plays, `size` big.
func _on_carrier_ended(caster: int, carrier_card: StringName, at: Vector2, direction: Vector2, size: float, tint: Color, look: int) -> void:
	var tag: int = _cue_tag()
	if _spectacle != null:
		_spectacle.end_streams(caster, tag)
	var cue: StringName = _carrier_cues_of(carrier_card)[CUE_END] as StringName
	if cue != &"":
		play_cue(cue, caster, at, direction, size, tint, look, ActorsScript.NONE, -1, -1, tag)


## The carrier card `carrier_card`'s look as the area `drawer` (Carrier.LOOK_BEAM, LOOK_SWING) draws it
## (`Spells.look_of`; `CardLook.PLAIN` with no Spells, no card, or a card another area draws), asked
## once per id and kept: a cast allocates nothing.
func _carrier_look_of(carrier_card: StringName, drawer: int) -> CardLook:
	var cache: Dictionary = _carrier_looks.get(drawer, {})
	var known: CardLook = cache.get(carrier_card) as CardLook
	if known != null:
		return known
	if spells == null or carrier_card == &"" or not spells.has_method(&"look_of"):
		return CardLook.PLAIN
	var look: CardLook = spells.call(&"look_of", carrier_card, drawer) as CardLook
	cache[carrier_card] = look
	_carrier_looks[drawer] = cache
	return look


## The shader that draws the carrier card `carrier_card`'s look in the area `drawer`, or `plain` when its
## card names none (or is drawn by another area).
func _carrier_shader_of(carrier_card: StringName, drawer: int, plain: Shader) -> Shader:
	var shader: Shader = _carrier_look_of(carrier_card, drawer).shader
	return shader if shader != null else plain


## Warms the carrier cards' own shaders Feel draws (beams' and swing trails', one mesh each:
## `Spells.look_shaders`) before the first room, as it warms its own; Spells knows nothing of how.
func _warm_card_looks() -> void:
	if spells == null or not spells.has_method(&"look_shaders"):
		return
	for drawer: int in [Carrier.LOOK_BEAM, Carrier.LOOK_SWING]:
		for shader: Shader in spells.call(&"look_shaders", drawer):
			ShaderWarmupScript.want(shader, ShaderWarmupScript.MESH)
	# The portals' lenses are a batch of quads (`portal_look.gd`).
	for shader: Shader in spells.call(&"look_shaders", Carrier.LOOK_PORTAL):
		ShaderWarmupScript.want(shader, ShaderWarmupScript.BATCH)


## Gives `node`'s own material `shader` (a beam's or a trail's: each node keeps its own material,
## since each sets its own uniforms), only when it has another, so nothing is recompiled per cast.
static func _use_shader(node: CanvasItem, shader: Shader) -> void:
	var material: ShaderMaterial = node.material as ShaderMaterial
	if material.shader != shader:
		material.shader = shader


## A beam's node: a beam mesh in world space drawn by the beam shader, hidden until shown.
func _make_beam() -> MeshInstance2D:
	var node := MeshInstance2D.new()
	node.mesh = beam_mesh()
	var material := ShaderMaterial.new()
	material.shader = BEAM_SHADER
	node.material = material
	node.top_level = true
	node.visible = false
	node.z_index = SHOWN_BEAM_Z
	add_child(node)
	return node


func _make_beam_path() -> PackedVector3Array:
	var path := PackedVector3Array()
	path.resize(LIVE_BEAM_POINTS)
	return path


## The mesh a beam is drawn as (`shot_beam.gdshader`, PARTICLES ARE GEOMETRY there): small quads
## told in their UV which quad kind (BEAM_Q_*) and slot they are, in BEAM_QUADS' order, as
## `flash_mesh`. The shader places them along the beam's path in the world, so the mesh says
## nothing of where: it is never culled (its box is the whole world). Made once.
static func beam_mesh() -> ArrayMesh:
	if _beam_mesh == null:
		_beam_mesh = _quads_mesh(BEAM_QUADS)
		_beam_mesh.custom_aabb = BatchesScript.WORLD
	return _beam_mesh


## The mesh a swing's trail is drawn as (`SwingTrailsScript.SWING_QUADS`; Q_* in
## `shot_swing.gdshader`), as `beam_mesh`. Made once.
static func swing_mesh() -> ArrayMesh:
	if _swing_mesh == null:
		_swing_mesh = _quads_mesh(SwingTrailsScript.SWING_QUADS)
		_swing_mesh.custom_aabb = BatchesScript.WORLD
	return _swing_mesh


## The swing trails (for tests).
## The shader a swing of the carrier card `carrier_card` trails with (its `look_shader`, or the plain trail's).
func _swing_shader_of(carrier_card: StringName) -> Shader:
	return _carrier_shader_of(carrier_card, Carrier.LOOK_SWING, SwingTrailsScript.SHADER)


func swing_trails() -> SwingTrailsScript:
	return _swing_trails


## The shader's player for a swing of `actor` (`_beam_ramp` of its ramp).
func _swing_ramp(actor: int) -> int:
	return _beam_ramp(_ramp_of(actor))


## Make the flash batches (see "Flashes" above): a MultiMesh of `effect_slots` quads in world
## space for each of the flares, the arcs and the statuses, each drawn by its own shot shader,
## and the arrays behind them.
func _make_flashes() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_status_node = _make_flash_batch(STATUS_SHADER, quad)
	_flash_node = _make_flash_batch(FLASH_SHADER, flash_mesh())
	_arc_node = _make_flash_batch(ARC_SHADER, quad)
	_floor_node = _make_flash_batch(FLASH_SHADER, flash_mesh())
	_floor_node.z_index = FLOOR_Z
	_blast_node = _make_flash_batch(BLAST_SHADER, blast_mesh())
	_size_flashes(effect_slots)
	_read_flash_kinds()


## Read the flash kinds (content/flashes) from the registry: each id's code and its row for a
## cue's flash part, and the table the flash shader draws the table kinds from (`FlashTable`). A
## kind with problems (`FlashKind.problems`; the content test names them) is left out. The cues
## are read again, so their flash parts take the new codes.
func _read_flash_kinds() -> void:
	_flash_kinds.clear()
	_flash_codes.clear()
	_flash_rows.clear()
	_code_light.clear()
	if registry != null:
		for found: Resource in registry.get_all(FLASH_FOLDER):
			var kind: FlashKind = found as FlashKind
			if kind != null and kind.problems().is_empty():
				_flash_kinds.append(kind)
	_table_floor.resize(_flash_kinds.size())
	for row in _flash_kinds.size():
		var kind: FlashKind = _flash_kinds[row]
		var code: int = FLASH_TABLE + row if kind.in_table() else int(DRAW_KINDS[kind.draw])
		_table_floor[row] = 1 if kind.on_floor else 0
		_flash_codes[kind.id] = code
		_flash_rows[kind.id] = [code, kind.step, kind.seconds, kind.along()]
		_code_light[code] = kind.room_light
	var table := ImageTexture.create_from_image(FlashTableScript.image_of(_flash_kinds))
	for node: MultiMeshInstance2D in [_flash_node, _floor_node]:
		(node.material as ShaderMaterial).set_shader_parameter(&"flash_table", table)
	_cue_plans.clear()


## The flash kind `id` (content/flashes), or null.
func flash_kind(id: StringName) -> FlashKind:
	for kind: FlashKind in _flash_kinds:
		if kind.id == id:
			return kind
	return null


## The mesh a flash is drawn as (`shot_flash.gdshader`, PARTICLES ARE GEOMETRY there): small
## quads, each told in its UV which quad kind (FLASH_Q_*) and slot it is, in FLASH_QUADS'
## order. The shader places every quad in the flash's square, or folds it away; a vertex says
## which quad and corner it is in its UV: x the slot + 0.25 or 0.75, y the kind + 0.25 or 0.75.
## Made once.
static func flash_mesh() -> ArrayMesh:
	if _flash_mesh == null:
		_flash_mesh = _quads_mesh(FLASH_QUADS)
	return _flash_mesh


## The mesh an explosion's part is drawn as (`shot_blast.gdshader`): its light and BLAST_PIECES
## small quads, told their kind and slot in their UV as `flash_mesh`'s. Made once.
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


func _make_flash_batch(shader: Shader, mesh: Mesh) -> MultiMeshInstance2D:
	var node := MultiMeshInstance2D.new()
	# Flashes show anywhere in the world; there is no room to fit a box to.
	var multimesh: MultiMesh = BatchesScript.multimesh()
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.visible_instance_count = 0
	node.multimesh = multimesh
	var material := ShaderMaterial.new()
	material.shader = shader
	node.material = material
	node.top_level = true
	node.z_index = FLASH_Z
	add_child(node)
	return node


## Make room for `slots` flashes: the MultiMesh, its buffer and the arrays behind it. The
## flashes showing end (a setting changed in a menu: nobody misses a tenth of a second of sparks).
func _size_flashes(slots: int) -> void:
	effect_slots = slots
	for node: MultiMeshInstance2D in [_flash_node, _arc_node, _status_node, _floor_node, _blast_node]:
		node.multimesh.visible_instance_count = 0
		node.multimesh.instance_count = slots
	_flash_buffer.resize(slots * FLASH_STRIDE)
	_arc_buffer.resize(slots * FLASH_STRIDE)
	_floor_buffer.resize(slots * FLASH_STRIDE)
	_blast_buffer.resize(slots * FLASH_STRIDE)
	_status_buffer.resize(slots * FLASH_STRIDE)
	_flash_kind.resize(slots)
	_flash_at.resize(slots)
	_flash_dir.resize(slots)
	_flash_core.resize(slots)
	_flash_ramp.resize(slots)
	_flash_zoom.resize(slots)
	_flash_look.resize(slots)
	_flash_age.resize(slots)
	_flash_seconds.resize(slots)
	_flash_seconds.fill(0.0)
	_flash_length.resize(slots)
	_flash_follow.resize(slots)
	_flash_follow.fill(null)
	_flash_light.resize(slots)
	_flash_light.fill(0.0)
	_flash_offset.resize(slots)
	_flash_tip.resize(slots)
	_flash_floor.resize(slots)
	_flash_floor.fill(0)
	_flash_tip.fill(ActorsScript.NONE)
	_next_flash = 0
	# The statuses shown lost their flashes; the next step shows them again.
	_status_effect.fill(-1)


## The setting: how many flashes can show at once, snapped by `EffectSlots.snap`. Returns the
## number taken.
func set_effect_slots(slots: int) -> int:
	var snapped: int = EffectSlots.snap(slots)
	if _flash_node == null:
		effect_slots = snapped
	elif snapped != effect_slots:
		_size_flashes(snapped)
	return effect_slots


func _on_effect_slots_changed(slots: int) -> void:
	set_effect_slots(slots)


# --- The spectacle (spectacle.gd): forwards for the tests, the benchmarks and the menus ---------

## The spectacle node.
func spectacle() -> SpectacleScript:
	return _spectacle


## Every actor's damage numbers (tests).
func damage_numbers() -> DamageNumberDrawerScript:
	return _numbers


## The motes (null with the setting off; for tests and the benchmarks).
func motes() -> MotesScript:
	return _spectacle.pool if _spectacle != null else null


## The floor marks (null with the setting off; for tests and the benchmarks).
func marks() -> MarksScript:
	return _spectacle.marks if _spectacle != null else null


## Spell light (null with the setting off; for tests and the benchmarks).
func light() -> SpellLightScript:
	return _spectacle.light if _spectacle != null else null


## The colour table the motes and the floor marks share.
func ramp_table() -> RampTableScript:
	return _spectacle.ramp_table()


## Use `pool` as the motes (`Spectacle.use_motes`; the benchmarks' timed pool).
func use_motes(pool: MotesScript) -> void:
	_spectacle.use_motes(pool)


## The "Particles" setting (`Spectacle.set_mote_cap`). Returns the number taken.
func set_mote_cap(cap: int) -> int:
	return _spectacle.set_mote_cap(cap)


## The "Particle amount" setting (`Spectacle.set_mote_density`). Returns the share taken.
func set_mote_density(density: float) -> float:
	return _spectacle.set_mote_density(density)


## The "Floor marks" setting (`Spectacle.set_floor_marks`).
func set_floor_marks(on: bool) -> void:
	_spectacle.set_floor_marks(on)


## The "Spell light" setting (`Spectacle.set_spell_light`). Returns the setting.
func set_spell_light(on: bool) -> bool:
	return _spectacle.set_spell_light(on)


func _on_screen_shake_changed(enabled: bool) -> void:
	shake_enabled = enabled


## Show a flash of the kind `id` (content/flashes) at `at`, aimed along `dir`, in the ramp of
## `core` (white: the colours of `ramp`, a caster's `Actors.ramp_of`: 0-3 a hat ramp, anything else
## from NONE up the enemy ramp) with the particles of the packed `look`, at `zoom`, for
## `seconds`. An arc runs `length` pixels from `at` along `dir` (its zoom is then the length). A
## flash given a `follow` node moves with it, and ends when it is gone. It takes the next slot, the
## oldest flash when they are all busy, and returns it (-1 for none, or a kind there is not; a hit's
## own flash past its share of a frame's, `_hit_flashes_full`, is none).
func show_flash(id: StringName, at: Vector2, dir: Vector2, core: Color, ramp: int, look: int, zoom: int, seconds: float, length: float = 0.0, follow: Node2D = null) -> int:
	var code: int = int(_flash_codes.get(id, -1))
	return _show_flash(code, at, dir, core, ramp, look, zoom, seconds, length, follow) if code >= 0 else -1


## True when this frame's hit flashes have taken their share of the slots (`_flashes_shown`).
func _hit_flashes_full() -> bool:
	return _flashes_shown >= effect_slots - effect_slots / HIT_FLASH_RESERVE


## `show_flash` by Feel's code for the kind (`_flash_codes`; KIND_STATUS for a status's glow).
func _show_flash(kind: int, at: Vector2, dir: Vector2, core: Color, ramp: int, look: int, zoom: int, seconds: float, length: float = 0.0, follow: Node2D = null) -> int:
	if _flash_node == null or not at.is_finite() or ramp < ActorsScript.NONE or ramp > ActorsScript.RAMP_ENEMY:
		return -1
	if _hit_flash and _hit_flashes_full():
		return -1
	_flashes_shown += 1
	var slot: int = _next_flash
	_next_flash = (_next_flash + 1) % effect_slots
	_flash_kind[slot] = kind
	_flash_at[slot] = at.round()
	_flash_dir[slot] = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	_flash_core[slot] = core
	_flash_ramp[slot] = ramp
	# As big as it is asked to be (the owner, 2026-11-09: no cue is capped in size): an explosion's
	# part takes its radius / 2 as its zoom. The shaders read the size from the row's transform, not
	# the look's red byte (which holds 63 at most).
	_flash_zoom[slot] = maxi(zoom, 1)
	_flash_look[slot] = look
	_flash_age[slot] = 0.0
	_flash_seconds[slot] = maxf(seconds, 0.01)
	_flash_length[slot] = 0.0
	_flash_follow[slot] = follow
	_flash_offset[slot] = Vector2(0.0, -STATUS_RISE) if follow != null else Vector2.ZERO
	_flash_tip[slot] = _cue_tip
	_flash_floor[slot] = 0
	_flash_light[slot] = 0.0 if _cue_unlit else float(_code_light.get(kind, 0.0))
	if kind == KIND_ARC:
		var steps: int = maxi(roundi(length / 4.0), 1)
		_flash_zoom[slot] = steps
		_flash_length[slot] = steps * 4.0
	return slot


## Flash `slot` on its actor's staff tip as it is now, turned with its live aim (a wind-up's ring
## follows the staff as the aim follows the stick, as its lane does: `lanes.gd`); where it was while
## the actor has no aim.
func _place_on_tip(slot: int) -> void:
	if spells == null:
		return
	var actor: int = _flash_tip[slot]
	var tip: Vector2 = spells.call("aim_origin_of", actor)
	var way: Vector2 = spells.call("aim_of", actor)
	if not tip.is_finite() or not way.is_finite() or way.is_zero_approx():
		return
	_flash_at[slot] = (tip + _flash_offset[slot].rotated(way.angle())).round()
	_flash_dir[slot] = way.normalized()


## Age the flashes by `real_delta` and write the live ones into their batches, oldest first.
func _step_flashes(real_delta: float) -> void:
	if _flash_node == null:
		return
	(_flash_node.material as ShaderMaterial).set_shader_parameter(&"sim_time", _clock)
	(_arc_node.material as ShaderMaterial).set_shader_parameter(&"sim_time", _clock)
	(_status_node.material as ShaderMaterial).set_shader_parameter(&"sim_time", _clock)
	(_floor_node.material as ShaderMaterial).set_shader_parameter(&"sim_time", _clock)
	(_blast_node.material as ShaderMaterial).set_shader_parameter(&"sim_time", _clock)
	var out: int = 0
	var arcs: int = 0
	var floors: int = 0
	var blasts: int = 0
	var statuses: int = 0
	for n in effect_slots:
		var slot: int = (_next_flash + n) % effect_slots
		if _flash_seconds[slot] <= 0.0:
			continue
		_flash_age[slot] += real_delta
		var through: float = _flash_age[slot] / _flash_seconds[slot]
		# Read untyped: a freed body put in a typed variable reads as null, and its flash would
		# stay on where it was instead of ending (S6, item 9's regression test).
		var followed: Variant = _flash_follow[slot]
		var follow: Node2D = null
		if typeof(followed) == TYPE_OBJECT:
			if is_instance_valid(followed):
				follow = followed as Node2D
			else:
				through = 1.0
		if through >= 1.0:
			_flash_seconds[slot] = 0.0
			_flash_follow[slot] = null
			continue
		if _flash_tip[slot] != ActorsScript.NONE:
			_place_on_tip(slot)
		elif follow != null:
			_flash_at[slot] = (follow.global_position + _flash_offset[slot]).round()
		var kind: int = _flash_kind[slot]
		var buffer: PackedFloat32Array = _flash_buffer
		var i: int = out * FLASH_STRIDE
		var blast: bool = kind == KIND_SHELL or kind == KIND_FIREBALL
		# A table kind's row, and the code beside its age (its code in the shader that draws it).
		var row: int = kind - FLASH_TABLE if kind >= FLASH_TABLE else 0
		var code: int = FLASH_TABLE_CODE if kind >= FLASH_TABLE else (kind - KIND_SHELL if blast else kind)
		if kind == KIND_ARC:
			buffer = _arc_buffer
			i = arcs * FLASH_STRIDE
			arcs += 1
		elif kind == KIND_STATUS:
			buffer = _status_buffer
			i = statuses * FLASH_STRIDE
			statuses += 1
		elif blast:
			buffer = _blast_buffer
			i = blasts * FLASH_STRIDE
			blasts += 1
		elif _table_floor[row] != 0 or _flash_floor[slot] != 0:
			buffer = _floor_buffer
			i = floors * FLASH_STRIDE
			floors += 1
		else:
			out += 1
		var d: float = FLASH_GRID * _flash_zoom[slot]
		var along: float = d
		var dir: Vector2 = _flash_dir[slot]
		var at: Vector2 = _flash_at[slot]
		if blast:
			# An explosion's part: BLAST_SPAN radii each way, its radius the zoom x 2.
			d = _flash_zoom[slot] * 4.0 * BLAST_SPAN
			along = d
		if _flash_length[slot] > 0.0:
			# An arc: from where it starts along its way, a margin past each end.
			d = ARC_ACROSS
			along = _flash_length[slot] + 2.0 * ARC_MARGIN
			at += dir * _flash_length[slot] * 0.5
		# The transform, its two unused floats its table row and its room light (full precision).
		buffer[i] = dir.x * along
		buffer[i + 1] = dir.y * d
		buffer[i + 2] = float(row)
		buffer[i + 3] = at.x
		buffer[i + 4] = dir.y * along
		buffer[i + 5] = -dir.x * d
		buffer[i + 6] = _flash_light[slot]
		buffer[i + 7] = at.y
		var data: Color = ProjectileManagerScript.look_color(_flash_ramp[slot], _flash_zoom[slot], _flash_look[slot])
		buffer[i + 8] = data.r
		buffer[i + 9] = data.g
		buffer[i + 10] = data.b
		buffer[i + 11] = data.a
		var core: Color = _flash_core[slot]
		buffer[i + 12] = core.r
		buffer[i + 13] = core.g
		buffer[i + 14] = core.b
		# Its age beside its code (the flash shaders read it: `coded_age`).
		buffer[i + 15] = 1.0 - (float(code) + FLASH_FROM + FLASH_SPAN * through) / 16.0
	if out > 0:
		_flash_node.multimesh.buffer = _flash_buffer
	_flash_node.multimesh.visible_instance_count = out
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
	# Spell light draws the same rows (P3b; through the spectacle, `SpellLight.light_flashes`).
	if _spectacle != null:
		_spectacle.light_flashes(_flash_buffer, out, _blast_buffer, blasts, _arc_buffer, arcs, effect_slots)


## How many flashes are showing (for tests and the sheets).
func live_flashes() -> int:
	var live: int = 0
	for slot in effect_slots:
		if _flash_seconds[slot] > 0.0:
			live += 1
	return live


## How many live flashes are of the kind `id`, and (with a `ramp` 0-4) in that ramp.
func flashes_of(id: StringName, ramp: int = -1) -> int:
	return _count_flashes(int(_flash_codes.get(id, -1)), ramp)


func _count_flashes(kind: int, ramp: int = -1) -> int:
	var found: int = 0
	for slot in effect_slots:
		if _flash_seconds[slot] > 0.0 and _flash_kind[slot] == kind and (ramp < 0 or _flash_ramp[slot] == ramp):
			found += 1
	return found


## The newest live flash of Feel's code `kind`'s slot, or -1.
func _newest_flash(kind: int) -> int:
	for n in effect_slots:
		var slot: int = (_next_flash - 1 - n + effect_slots) % effect_slots
		if kind >= 0 and _flash_seconds[slot] > 0.0 and _flash_kind[slot] == kind:
			return slot
	return -1


## The core colour and look of the newest live flash of the kind `id` (for tests): [core, look].
func flash_dress(id: StringName) -> Array:
	var slot: int = _newest_flash(int(_flash_codes.get(id, -1)))
	return [_flash_core[slot], _flash_look[slot]] if slot >= 0 else []


## The newest live flash of the kind `id` (for tests): its place, way, core colour, ramp, zoom,
## look, seconds and room light, or an empty dictionary when none shows.
func flash_info(id: StringName) -> Dictionary:
	return _flash_info_of(_newest_flash(int(_flash_codes.get(id, -1))))


## The newest status glow shown (for tests), as `flash_info`.
func status_info() -> Dictionary:
	return _flash_info_of(_newest_flash(KIND_STATUS))


func _flash_info_of(slot: int) -> Dictionary:
	if slot < 0:
		return {}
	return {"at": _flash_at[slot], "dir": _flash_dir[slot], "core": _flash_core[slot], "ramp": _flash_ramp[slot],
			"zoom": _flash_zoom[slot], "look": _flash_look[slot], "seconds": _flash_seconds[slot], "light": _flash_light[slot]}


## The actor id of a hit body (a kit Actor's `id`), or Actors.NONE for anything else.
static func _actor_of(target: Node) -> int:
	return (target as Actor).id if target is Actor else ActorsScript.NONE


## The hat ramp (0-3) of the actor `target` is, or -1 for an actor of the enemy ramp, no actor or
## an unknown one.
func _hat_ramp_of(target: Node) -> int:
	return _hat_ramp_of_id(_actor_of(target))


## `_hat_ramp_of` for the actor `id` (its body's, `_actor_of`).
func _hat_ramp_of_id(id: int) -> int:
	if id == ActorsScript.NONE:
		return -1
	var ramp: int = _ramp_of(id)
	return ramp if ProjectileManagerScript.is_hat_ramp(ramp) else -1


## The actor table: `actors`, else the "Actors" autoload, kept once found while it is still in the
## tree (performance, 2026-11-02: every hit asks for it, and a lookup by path was the largest part
## of Feel's work for a hit).
func _actor_table() -> ActorsScript:
	if actors != null:
		return actors if is_instance_valid(actors) else null
	if _auto_actors != null and is_instance_valid(_auto_actors) and _auto_actors.is_inside_tree():
		return _auto_actors
	_auto_actors = null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		_auto_actors = tree.root.get_node_or_null(^"Actors") as ActorsScript
	return _auto_actors


## The budget of `caster` (its seat, or SHARED: no actor too), for what Feel keeps per budget.
func _budget_of(caster: int) -> int:
	var table: ActorsScript = _actor_table()
	return table.budget_of(caster) if table != null else ActorsScript.SHARED


## The ramp of `caster`'s spells (NONE for no actor: the enemy ramp).
func _ramp_of(caster: int) -> int:
	var table: ActorsScript = _actor_table()
	return table.ramp_of(caster) if table != null else ActorsScript.NONE


## A death: its body breaks into motes of its own art (S3; the white-hot copy that fell apart
## pixel by pixel before), then the cue `enemy_death` (a white-hot ring, its motes and mark, and a
## puff in the body's own colour; the killer and the shot hold for the kill, the dead body is freed
## at once) or, for a boss, `boss_death`, which also stops the whole game. The killing blow's sound
## gives way to the death's.
func _on_enemy_died(killer: int, enemy: Node, position: Vector2, shot: int) -> void:
	# The body breaks into motes of its own art (S3), from where it stood at its rest scale.
	var body: Sprite2D = _body_sprite(enemy)
	if body != null:
		_spectacle.break_body(body, _rest_transform(body, enemy), preset.death_mote_kind, preset.death_mote_share, preset.death_mote_most, preset.death_mote_speed, preset.death_mote_up)
	# The hit that killed it (its flash still showing here) is silenced for the death's sound.
	if _hit_voice >= 0 and _hit_slot >= 0 and _hit_position == position and _flash_seconds[_hit_slot] > 0.0:
		_voices[_hit_voice].stop()
	# Its motes: the killing shot's cards' kinds (read while the event is sent), and the surface
	# kinds in the colours of the body's own art.
	var look: int = 0
	var core: Color = Color.WHITE
	if projectiles != null and shot >= 0:
		look = projectiles.get_look_of(shot)
		core = projectiles.get_core_of(shot)
	# What broke is the body: its surface kinds and marks in the colours of its own art, its puff in
	# its own colour.
	play_cue(CueBase.BOSS_DEATH_CUE if _is_boss(enemy) else CueBase.ENEMY_DEATH_CUE, killer, position, Vector2.ZERO, 0.0, core, look, ActorsScript.NONE, shot, _spectacle.body_source(body), 0, true, _hit_color_of(enemy))


## The cues the carrier card `carrier_card` names and its radius (`CarrierCard.look_cues`: [cast_cue,
## shown_cue, impact_cue, end_cue, radius], CUE_CAST to CUE_RADIUS), the defaults (`cast` and `impact`, radius
## 0) for an id that is no carrier card; a fallback carrier (`caster`) casts with its own
## `Carrier.cast_cue`; a modifier that shows itself (`carrier_shown` `zap`) brings its
## own `cue` as its shown cue. Read once per card id, then kept: a cast or a hit allocates nothing.
## With no registry yet, or no carrier card id, the defaults are answered but not kept.
func _carrier_cues_of(carrier_card: StringName) -> Array:
	var cached: Variant = _carrier_cues.get(carrier_card)
	if cached != null:
		return cached as Array
	if registry == null or carrier_card == &"":
		return NO_CARRIER_CUES
	var card: Resource = registry.get_resource(&"spells", carrier_card)
	var cues: Array = NO_CARRIER_CUES
	if card is CarrierCard:
		cues = (card as CarrierCard).look_cues()
	elif card == null and Carriers.is_fallback(carrier_card) and Carriers.of(carrier_card).cast_cue() != &"":
		# A cast with no carrier card (its cards landed on the caster): its fallback carrier's own cue.
		cues = NO_CARRIER_CUES.duplicate()
		cues[CUE_CAST] = Carriers.of(carrier_card).cast_cue()
	elif card is ModifierBase and (card as ModifierBase).cue != &"":
		# A modifier that shows itself (a zap: `carrier_shown` names its card) plays its own cue there.
		cues = [NO_CARRIER_CUES[CUE_CAST], (card as ModifierBase).cue, NO_CARRIER_CUES[CUE_IMPACT], &"", 0.0, NO_CARRIER_CUES[CUE_WIND]]
	_carrier_cues[carrier_card] = cues
	return cues


## A seat cast a spell (`spell_cast`, a seat's own staffs only): its carrier card's `cast_cue` at the
## staff tip, in the seat's hat ramp, along its aim (the cast flash, a ring for a ring carrier, the
## camera kicked back), from the actor the seat drives.
func _on_spell_cast(player: int, spell_id: StringName, origin: Vector2, direction: Vector2) -> void:
	if player < 0 or player >= ActorsScript.SEATS:
		return
	var table: ActorsScript = _actor_table()
	var actor: int = table.actor_of_seat(player) if table != null else ActorsScript.NONE
	play_cue(_carrier_cues_of(spell_id)[CUE_CAST] as StringName, actor, origin, direction, 0.0, Color.WHITE, 0, ActorsScript.NONE, -1, -1, 0, true, NO_BODY, player)


## A cast started winding up (`cast_winding`; docs/milestones/cast-timing.md, T6b): the staff's own
## wind-up cue when it names one (`staff_cue`, `StaffBase.wind_cue`: a barrel's fuse, props W6), else
## its carrier card's `wind_cue` (an enemy's telegraph: a lane along the aim, a ring for a cast that
## is not aimed), from the staff tip, its size the wind-up's seconds, on the staff tip as it turns.
## Only for a caster not on the players' team: a telegraph warns the players (owner, 2026-11-01).
func _on_cast_winding(caster: int, _staff: int, carrier_card: StringName, origin: Vector2, direction: Vector2, seconds: float, tint: Color, look: int, tag: int, staff_cue: StringName) -> void:
	if caster < 0 or caster >= ActorsScript.ACTORS or not origin.is_finite():
		return
	var table: ActorsScript = _actor_table()
	if table == null or table.team_of(caster) == ActorsScript.TEAM_WIZARDS:
		return
	var cue: StringName = staff_cue if staff_cue != &"" else _carrier_cues_of(carrier_card)[CUE_WIND] as StringName
	if cue == &"":
		return
	# Its flashes sit on the staff tip as it turns (the aim follows the caster through the wind-up).
	_cue_tip = caster
	play_cue(cue, caster, origin, direction, seconds, tint, look, ActorsScript.NONE, -1, -1, tag, true, NO_BODY, _ramp_of(caster), table.node_of(caster) as Node2D)
	_cue_tip = ActorsScript.NONE


## A cue's `lane` part (`CueBase`; T6b): a telegraph lane for the cast of the cue's tag, as long as
## the cue's size in seconds (`lanes.gd`).
func _play_lane(part: Variant, cue: CueContextScript) -> void:
	if _lanes == null:
		return
	var reach: float = float((part as Dictionary).get("reach", 1.0)) if part is Dictionary else 1.0
	_lanes.spells = spells
	_lanes.play(cue.caster, cue.tag, cue.size, cue.tint, reach)


## The lanes under way (for tests).
func lanes() -> LanesScript:
	return _lanes


## A barrier on an actor changed (combat's `barrier_changed`): the spectacle draws its shell, a
## bubble of motes round the actor in its spell's colours (`barriers.gd`).
func _on_barrier_changed(actor: int, charges: int, seconds: float, tag: int, way: Vector2, radius: float) -> void:
	_spectacle.barrier_changed(actor, charges, seconds, tag, way, radius, _ramp_of(actor))


## A carrier showed itself: its card's `shown_cue` (where a teleport leaves, each end of a swap, a decoy or familiar
## appearing, a dash's dust and lightning arc, S5), then a beam (drawn by `shot_beam.gdshader` in
## the element's ramp) with the cast's cards, in the caster's ramp: an enemy's look the same, in the
## enemy ramp (staffs F7). The beam keeps state of its own (its slot while it fades), so it stays
## in code. A slam's strike is its end (`carrier_ended`); its
## wind-up shows only on the staff (the rising, glowing staff: a ring there distracted from it).
func _on_carrier_shown(caster: int, carrier_card: StringName, origin: Vector2, direction: Vector2, length: float, tint: Color, look: int) -> void:
	if caster < ActorsScript.NONE or caster >= ActorsScript.ACTORS or not origin.is_finite():
		return
	var cue: StringName = _carrier_cues_of(carrier_card)[CUE_SHOWN] as StringName
	if cue != &"":
		play_cue(cue, caster, origin, direction, length, tint, look, ActorsScript.NONE, -1, -1, _cue_tag())
	var ramp: int = _ramp_of(caster)
	if carrier_card != &"beam" or length <= 0.0 or direction == Vector2.ZERO:
		return
	var seconds: float = preset.beam_seconds
	if seconds <= 0.0:
		return
	# Each seat's caster reuses only its own oldest slots, so nobody's beams push out another's;
	# the actors no seat drives share one seat's worth (by budget), so a crowd never takes a seat's.
	var who: int = _budget_of(caster)
	var slot: int = who * SHOWN_BEAMS_PER_PLAYER + _next_shown_beam[who]
	_next_shown_beam[who] = (_next_shown_beam[who] + 1) % SHOWN_BEAMS_PER_PLAYER
	var node: MeshInstance2D = _shown_beams[slot]
	var end: Vector2 = origin + direction.normalized() * length
	var path: PackedVector3Array = _shown_beam_paths[slot]
	path[0] = Vector3(origin.x, origin.y, 0.0)
	path[1] = Vector3(end.x, end.y, length)
	# Drawn by its card's own shader (`CarrierCard.look_shader`), or the plain beam's.
	_use_shader(node, _carrier_shader_of(carrier_card, Carrier.LOOK_BEAM, BEAM_SHADER))
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
	material.set_shader_parameter(&"beam_player", _beam_ramp(ramp))
	material.set_shader_parameter(&"beam_look", look)
	# A shown beam carries its tint and look only: its look works its infusion out from them.
	material.set_shader_parameter(&"beam_infusion_count", 0)
	material.set_shader_parameter(&"beam_glow", preset.beam_alpha)
	var body: Color = Color.WHITE
	if projectiles != null:
		body = projectiles.tint_of(caster)
	_shown_beam_body[slot] = body
	_shown_beam_ramp[slot] = _beam_ramp(ramp)
	_shown_beam_look[slot] = look
	_shown_beam_tint[slot] = tint
	_shown_beam_tag[slot] = _cue_tag()
	_shown_beam_left[slot] = seconds
	_shown_beam_total[slot] = seconds
	node.visible = true
	_pose_shown_beam(slot, 1.0)


## Fade the beams, and give off their motes.
func _step_shown_beams(real_delta: float) -> void:
	for i in SHOWN_BEAM_SLOTS:
		if _shown_beam_left[i] <= 0.0:
			continue
		_shown_beam_left[i] -= real_delta
		if _shown_beam_left[i] <= 0.0:
			_shown_beams[i].visible = false
			continue
		var t: float = _shown_beam_left[i] / _shown_beam_total[i]
		_pose_shown_beam(i, t)
		var path: PackedVector3Array = _shown_beam_paths[i]
		var from: Vector2 = Vector2(path[0].x, path[0].y)
		var end: Vector2 = Vector2(path[1].x, path[1].y)
		_beam_motes(path, 2, path[1].z, end, from.direction_to(end), t, _shown_beam_ramp[i], _shown_beam_look[i], _shown_beam_tint[i], _shown_beam_tag[i], real_delta)


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


func _draw_live_beams(real_delta: float) -> void:
	if _spectacle != null:
		_spectacle.light_beams_begin()
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
		# It dissolves at its end as its carrier says (`Carrier.fade_left`), when it acts no more.
		var fade: float = beams.call("beam_fade", i)
		var flare: float = 1.0 + preset.beam_flare * maxf(1.0 - since / maxf(preset.beam_seconds * preset.beam_flare_share, 0.001), 0.0)
		var flicker: float = 1.0 - preset.beam_flicker_depth * float(int(since * preset.beam_flicker_rate) % 2)
		# Drawn across a fixed width; flare, flicker and fade swell and dissolve its pixels instead
		# of stretching them.
		var caster: int = beams.call("beam_caster", i)
		var body: Color = Color.WHITE
		if projectiles != null:
			body = projectiles.tint_of(caster)
		var tint: Color = beams.call("beam_tint", i)
		# Drawn by its card's own shader (`CarrierCard.look_shader`), or the plain beam's, and lit as
		# its card says (`look_light_intensity`, `look_light_reach`).
		var look: CardLook = _carrier_look_of(beams.call("beam_carrier_card", i) as StringName if beams.has_method("beam_carrier_card") else &"", Carrier.LOOK_BEAM)
		_use_shader(node, look.shader if look.shader != null else BEAM_SHADER)
		var material: ShaderMaterial = node.material as ShaderMaterial
		material.set_shader_parameter(&"core_override", Color(tint.r, tint.g, tint.b, 1.0))
		material.set_shader_parameter(&"body_tint", Color(body.r, body.g, body.b, fade * preset.beam_alpha))
		material.set_shader_parameter(&"beam_path", path)
		material.set_shader_parameter(&"beam_points", used)
		material.set_shader_parameter(&"beam_length", walked)
		material.set_shader_parameter(&"beam_lead", BEAM_LEAD)
		material.set_shader_parameter(&"beam_start", origin)
		material.set_shader_parameter(&"beam_end", end_at)
		material.set_shader_parameter(&"sim_time", _clock)
		# A growing beam is drawn wider as it hits wider (growth, rules R4f).
		var grown: float = float(beams.call("beam_growth", i)) if beams.has_method("beam_growth") else 1.0
		material.set_shader_parameter(&"beam_width", BEAM_WIDTH * grown)
		material.set_shader_parameter(&"beam_player", _beam_ramp(_ramp_of(caster)))
		material.set_shader_parameter(&"beam_look", int(beams.call("beam_look", i)) if beams.has_method("beam_look") else 0)
		# Every infusion on it, in slot order, for a look that shows each (the beam card's strands).
		var infusions: PackedColorArray = beams.call("beam_infusions", i) if beams.has_method("beam_infusions") else PackedColorArray()
		material.set_shader_parameter(&"beam_infusions", infusions)
		material.set_shader_parameter(&"beam_infusion_count", mini(infusions.size(), BEAM_INFUSIONS_MOST))
		material.set_shader_parameter(&"beam_fade", fade)
		material.set_shader_parameter(&"beam_swell", maxf(fade, 0.35) * flare * flicker * grown)
		material.set_shader_parameter(&"beam_glow", preset.beam_alpha)
		node.visible = true
		_beam_motes(path, used, walked, end_at, end_dir, fade, _beam_ramp(_ramp_of(caster)), int(beams.call("beam_look", i)) if beams.has_method("beam_look") else 0, tint, int(beams.call("beam_tag", i)) if beams.has_method("beam_tag") else 0, real_delta)
		# Spell light along the same path (P3b; through the spectacle, `SpellLight.light_beam`).
		if _spectacle != null:
			_spectacle.light_beam(i, path, used, _beam_ramp(_ramp_of(caster)), int(beams.call("beam_look", i)) if beams.has_method("beam_look") else 0, tint, fade, look.light_intensity, look.light_reach)


## The motes a beam gives off over `seconds` (see BEAM_SPLASH_RATE), into the spectacle's births
## while motes are on: its path is the first `points` of `path` (x, y and how far along), `length`
## pixels long, landing at `end_at` going `end_dir`, `fade` whole (1 to 0), of the shader ramp
## `ramp` (0-3 a hat ramp, -1 the enemies'), the look `look`, the tint `tint`, the spell of `tag`.
func _beam_motes(path: PackedVector3Array, points: int, length: float, end_at: Vector2, end_dir: Vector2, fade: float, ramp: int, look: int, tint: Color, tag: int, seconds: float) -> void:
	if seconds <= 0.0 or points < 2 or not _spectacle.motes_on():
		return
	var births: BirthsScript = _spectacle.births
	var core: Color = Color(tint.r, tint.g, tint.b, 1.0)
	if fade > BEAM_SPLASH_FADE:
		for n in births.roll(BEAM_SPLASH_RATE * seconds):
			if not births.add(end_at, -end_dir, 0, ramp, look, core, tag):
				return
	var kinds: int = BirthsScript.emitting_count(look)
	if kinds == 0 or length <= 0.0:
		return
	for n in births.roll(float(mini(4 + 2 * kinds, BEAM_PARTICLES_MOST)) * BEAM_PARTICLE_RATE * seconds):
		var along: float = length * births.dice()
		var k: int = 1
		while k < points - 1 and path[k].z < along:
			k += 1
		var a: Vector2 = Vector2(path[k - 1].x, path[k - 1].y)
		var b: Vector2 = Vector2(path[k].x, path[k].y)
		var span: float = path[k].z - path[k - 1].z
		var at: Vector2 = a.lerp(b, clampf((along - path[k - 1].z) / span, 0.0, 1.0)) if span > 0.0 else a
		var way: Vector2 = a.direction_to(b)
		var out: Vector2 = Vector2(-way.y, way.x) * (1.0 if births.dice() < 0.5 else -1.0)
		if not births.add(at, out, births.emitting_layer(look), ramp, look, core, tag):
			return


## Show beam `slot` at `t` (1 just shown, 0 gone): its rim and glow swell for its first moments
## (the payoff), then thin and flicker, and it dissolves into pixels (`beam_swell`, `beam_fade`).
func _pose_shown_beam(slot: int, t: float) -> void:
	var body: Color = _shown_beam_body[slot]
	var age: float = 1.0 - t
	var material: ShaderMaterial = _shown_beams[slot].material as ShaderMaterial
	material.set_shader_parameter(&"sim_time", _clock)
	material.set_shader_parameter(&"body_tint", Color(body.r, body.g, body.b, t * preset.beam_alpha))
	var flare: float = 1.0 + preset.beam_flare * maxf(1.0 - age / preset.beam_flare_share, 0.0)
	var step: int = int(age * _shown_beam_total[slot] * preset.beam_flicker_rate)
	var flicker: float = 1.0 - preset.beam_flicker_depth * float(step % 2)
	material.set_shader_parameter(&"beam_swell", t * flare * flicker)
	material.set_shader_parameter(&"beam_fade", t)


## Another staff went on show (the personality swap, living staffs H4): the cue `staff_swap` along
## the whole new staff (the cue's line: played at the staff's lower end behind the hand,
## `Actor.butt_position`, along the aim, its size the staff's length from there to its tip,
## `Actor.muzzle_position`, so its parts can cover the whole staff), following
## the body, in the actor's ramp with the colour and cards of the new staff's first spell (S6, item
## 9). StaffLook swaps the body and face at 35% of its POOF_TIME: the cue's look is timed to that.
func _on_staff_shown(caster: int, actor: Node, staff: int) -> void:
	var body: Actor = actor as Actor
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return
	var tag: int = 0
	var tint: Color = Color.WHITE
	var look: int = 0
	if spells != null and spells.has_method(&"current_tag"):
		tag = int(spells.call(&"current_tag", body.id, staff))
		var spell: Object = spells.call(&"profile", tag) as Object if tag != 0 else null
		if spell != null:
			tint = spell.get(&"tint") as Color
			look = int(spell.get(&"look"))
	var butt: Vector2 = body.butt_position()
	play_cue(STAFF_SWAP, caster, butt, body.aim, butt.distance_to(body.muzzle_position()), tint, look, body.id, -1, -1, tag, true, NO_BODY, CASTER_RAMP, body)


## A possession started: the cue `possess_start` on the possessed actor's body (a ring closing in
## the driver's ramp, the sound `possess`).
func _on_possess_started(caster: int, actor: int) -> void:
	_cue_on_body(POSSESS_START, caster, actor)


## A possession ended: the cue `possess_end` on the body let go, if it is still there (a ring going
## out in the driver's ramp).
func _on_possess_ended(caster: int, actor: int) -> void:
	_cue_on_body(POSSESS_END, caster, actor)


## Play the cue `id` of `caster` at the drawn body of `actor` (its `body_offset`), following the
## body; nothing when the body is gone.
func _cue_on_body(id: StringName, caster: int, actor: int) -> void:
	var table: ActorsScript = _actor_table()
	var body: Node2D = table.node_of(actor) as Node2D if table != null and actor != ActorsScript.NONE else null
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return
	play_cue(id, caster, body.global_position + ((body as Actor).body_offset if body is Actor else Vector2.ZERO), Vector2.ZERO, 0.0, Color.WHITE, 0, actor, -1, -1, 0, true, NO_BODY, CASTER_RAMP, body)


func _on_player_downed(player: int) -> void:
	# The event names no position, so a downed wizard's cue draws nothing: the game-wide stop,
	# shake and sound only (its point is never used)...
	play_cue(CueBase.DOWNED_CUE, ActorsScript.NONE, Vector2.ZERO)
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


## Shake the screen by `amount` (trauma, 0 to 1; its pixels are its square times `max_shake_pixels`):
## it raises the shake to `amount` and never adds to it (owner, 2026-11-07: a storm's hits each adding
## theirs kept the screen at its most), so a stream of small shakes holds at one's, and a bigger
## moment (a blast, a swing) still shows bigger.
func _shake(amount: float) -> void:
	_trauma = maxf(_trauma, minf(amount, 1.0))


## A hit's shake, looks and sound (its stop is the game's, `HitStop`).
## A hit with an `aim` (the way the shot flew) sprays along it, `size` times as big, from `at`,
## in the ramp of `tint` (white: `player`'s colours); without one it is a puff at `position`.
func _juice(position: Vector2, shake: float, sound: StringName, aim: Vector2 = Vector2.ZERO, tint: Color = Color.WHITE, size: float = 1.0, at: Vector2 = Vector2.INF, player: int = 0) -> void:
	if shake_enabled:
		_refresh_camera()
		_shake(shake)
	if position != Vector2.INF:
		# The cue `hit` (a spray and its sparks along the way the shot flew) or, with no way,
		# `hit_puff`, `size` steps of HIT_STEP pixels big, in the hit body's colours.
		var from: Vector2 = position if at == Vector2.INF else at
		var zoom: int = clampi(roundi(size), 1, 3)
		_cue_flash = -1
		_hit_flash = true
		play_cue(&"hit" if aim != Vector2.ZERO else &"hit_puff", ActorsScript.NONE, from, aim, zoom * HIT_STEP, tint, 0, ActorsScript.NONE, -1, -1, 0, true, NO_BODY, player)
		_hit_flash = false
		_hit_slot = _cue_flash
		_hit_position = position
	if sound != &"" and _hit_sounds >= HIT_SOUNDS_PER_FRAME:
		_hit_voice = -1
		return
	_hit_voice = _play(sound)
	if _hit_voice >= 0:
		_hit_sounds += 1


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


## True for the death of a boss: an enemy whose data says `boss`.
## The own colour of a body that is no wizard: its enemy data's `hit_color`, or the default for a
## body with none (a stand-in).
static func _hit_color_of(body: Node) -> Color:
	if body is Actor and (body as Actor).data != null:
		return (body as Actor).data.hit_color
	return EnemyBase.DEFAULT_HIT_COLOR


static func _is_boss(enemy: Node) -> bool:
	return enemy is Actor and (enemy as Actor).data != null and (enemy as Actor).data.boss


## Follow the current camera: when it changed, the old one is put back at rest. Looked for once a
## step (every hit asks; `_reset_camera` looks again at once).
func _refresh_camera() -> void:
	if not is_inside_tree() or _camera_step == _steps:
		return
	_camera_step = _steps
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
	_camera_step = -1
	_refresh_camera()
	_apply_camera()


## The shader's `beam_player` for `ramp`: the hat ramp 0-3, or -1 for the enemy ramp.
static func _beam_ramp(ramp: int) -> int:
	return ramp if ProjectileManagerScript.is_hat_ramp(ramp) else -1
