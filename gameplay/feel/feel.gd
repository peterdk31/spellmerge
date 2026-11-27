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
## - a sound from `core/registry` by id, played on Audio (core/audio: Feel decides what plays and
##   when, Audio how); nothing plays on `null`. Every actor's cast (`cast_left`) sounds its carriers'
##   own sounds with its infusions' faint hints over them (`cast_sounds.gd`), an enemy's quieter.
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
## colours; a swing's block (`shot_blocked` while the projectile manager's `impact_carrier` is
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
## Its code is split by effect family (gameplay/feel/README.md, "Feel's jobs"): this script holds
## every member and constant, what Feel makes (`_ready`), a frame's order (`step`) and the API; the
## flashes, cues, hits, statuses, beams, casts and the view are each a job's (`feel_<name>.gd`,
## `_job_<name>`), and a function moved there keeps a one-line wrapper here when others call it.
##
## Nothing is allocated while playing: the flash batch is made once, and the sounds' players are
## Audio's.
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
const PulseRingsScript := preload("res://gameplay/feel/pulse_rings.gd")
const PortalLookScript := preload("res://gameplay/feel/portal_look.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const MarksScript := preload("res://gameplay/feel/marks.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const SpectacleScript := preload("res://gameplay/feel/spectacle.gd")
const FeelJobsScript := preload("res://gameplay/feel/feel_jobs.gd")
const LanesScript := preload("res://gameplay/feel/lanes.gd")
const RemnantsScript := preload("res://gameplay/feel/remnants.gd")
const AudioScript := preload("res://core/audio/audio.gd")
const HeldSoundsScript := preload("res://gameplay/feel/held_sounds.gd")
const CastSoundsScript := preload("res://gameplay/feel/cast_sounds.gd")
const HitRepeatsScript := preload("res://gameplay/feel/hit_repeats.gd")
const BeamSoundsScript := preload("res://gameplay/feel/beam_sounds.gd")
const CardSoundsScript := preload("res://gameplay/feel/card_sounds.gd")
const CueSizeScript := preload("res://gameplay/feel/cue_size.gd")
const RoomAmbienceScript := preload("res://gameplay/feel/room_ambience.gd")
const BodySoundsScript := preload("res://gameplay/feel/body_sounds.gd")
const BossIntroSoundScript := preload("res://gameplay/feel/boss_intro_sound.gd")
const PickupSoundsScript := preload("res://gameplay/feel/pickup_sounds.gd")
const CueContextScript := preload("res://gameplay/feel/cue_context.gd")
const CuePlanScript := preload("res://gameplay/feel/cue_plan.gd")
const BodyLooksScript := preload("res://gameplay/feel/body_looks.gd")
const FlashTableScript := preload("res://gameplay/feel/flash_table.gd")
const PartyCameraScript := preload("res://gameplay/feel/party_camera.gd")
const FoeMarkersScript := preload("res://gameplay/feel/foe_markers.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const FramesScript := preload("res://core/sim/frames.gd")
const DamageNumberDrawerScript := preload("res://gameplay/feel/damage_number_drawer.gd")
const TeammateMarkersScript := preload("res://gameplay/feel/teammate_markers.gd")
const SplitScreenScript := preload("res://gameplay/feel/split_screen.gd")
const EffectsAutoScript := preload("res://gameplay/feel/effects_auto.gd")
const SplitBudgetScript := preload("res://gameplay/feel/split_budget.gd")
const EffectsQualityScript := preload("res://gameplay/feel/effects_quality.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")
const AltarCodeScript := preload("res://gameplay/feel/altar_code.gd")
const GatherDoorLooksScript := preload("res://gameplay/feel/gather_door_looks.gd")
const RoomHearingScript := preload("res://gameplay/feel/room_hearing.gd")
const MouthLooksScript := preload("res://gameplay/feel/mouth_looks.gd")
const LockLooksScript := preload("res://gameplay/feel/lock_looks.gd")
const RuneLooksScript := preload("res://gameplay/feel/rune_looks.gd")
const UnseenDarkScript := preload("res://gameplay/feel/unseen_dark.gd")
const UnseenRoomsScript := preload("res://gameplay/feel/unseen_rooms.gd")
const DecalPagesScript := preload("res://gameplay/feel/decal_pages.gd")
const UnseenStandingScript := preload("res://gameplay/feel/unseen_standing.gd")
const UnseenMaskScript := preload("res://gameplay/feel/unseen_mask.gd")
const RoomsViewBoxesScript := preload("res://gameplay/feel/view_boxes.gd")
const TeleportLooksScript := preload("res://gameplay/feel/teleport_looks.gd")
const VoidBackdropScript := preload("res://gameplay/feel/void_backdrop.gd")
const RoomTintsScript := preload("res://gameplay/feel/room_tints.gd")
const MouthSymbolsScript := preload("res://gameplay/feel/mouth_symbols.gd")
const PartyMapViewScript := preload("res://gameplay/feel/party_map_view.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const GroundItemsScript := preload("res://gameplay/feel/ground_items.gd")
const CoinsScript := preload("res://gameplay/feel/coins.gd")
const SpecialRoomLooksScript := preload("res://gameplay/feel/special_room_looks.gd")
const RewardItemsScript := preload("res://gameplay/feel/reward_items.gd")
const AwayBarsScript := preload("res://gameplay/feel/away_bars.gd")
const CoverScript := preload("res://gameplay/feel/cover.gd")
const CoverRoomsScript := preload("res://gameplay/feel/cover_rooms.gd")
const GroundLayoutScript := preload("res://gameplay/feel/ground/ground_layout.gd")
## Beams on screen per player: one cast makes at most 24 shots (the spell limit),
## so a split fan is drawn whole; past that the player's oldest slot is taken over.
const SHOWN_BEAMS_PER_PLAYER: int = 24
## Four players' beam sprites and the enemies' (one share for every enemy caster, staffs F7).
const SHOWN_BEAM_SLOTS: int = SHOWN_BEAMS_PER_PLAYER * 5
## The share of the beam sprites every enemy's beam takes turns in.
const ENEMY_SHOWN_BEAMS: int = 4
## Beams and rings draw above the room, under the shots (50) and the flashes (20).
const SHOWN_BEAM_Z: int = 18
## The share of a layered body's death motes each of its parts breaks into (boss plan OB8): its parts
## also fly apart whole as a remnant, so fewer motes read as splinters round them.
const REMNANT_MOTE_SHARE: float = 0.5
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

## The registry folder of the rooms (a room's music).
const ROOM_FOLDER: StringName = &"rooms"
## One-shot sounds that can play at once (Audio's world voices, core/audio).
const SOUND_VOICES: int = AudioScript.VOICES
## How often the bodies' phases and the music are looked at (s; `body_sounds.gd`).
const MUSIC_POLL: float = BodySoundsScript.POLL
## The share of the effect slots a frame's hit flashes leave to the rest (casts, kills,
## statuses): `effect_slots` / this (`_flashes_shown`).
const HIT_FLASH_RESERVE: int = 4
## How big a spot of wall one staff's impact look shows on in a frame (`_wall_impact`), in pixels.
const WALL_SPOT: float = 16.0
## The voices a frame's hit sounds may start (`_hit_sounds`): past them each would only cut short
## one of the same frame before it was heard, and the rest stay free for kills, casts and cues.
## Four, a third of the voices (half of the eight there were before the casts' sounds and hints).
const HIT_SOUNDS_PER_FRAME: int = 4
## The hit kinds a carrier's own hit sound plays for (`CarrierCard.hit_sound`: a shot, a ray, a sweep,
## a slam's wave and a pulse's ring); the rest keep their kind's.
const CARD_SOUND_KINDS: Array[StringName] = [&"shot", &"ray", &"swing", &"burst"]
## The quietest a dissolving beam's hum plays (decibels), before it ends.
const BEAM_FADE_FLOOR: float = -24.0
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
## of the palette material it is nearest (kind 30 in the shader, the bit past the enemy ramp's).
const EXACT: int = ProjectileManagerScript.LOOK_ENEMY_RAMP << 1
## Another staff on show plays the cue `staff_swap` (S6, item 9) along the new staff, following the
## body.
const STAFF_SWAP: StringName = &"staff_swap"
## An explosion's parts (the flash kinds `shell` and `fireball`), drawn by `shot_blast.gdshader` in
## a batch of their own; their fragments and rubble are motes and their scorch a floor mark (S3, the
## cues' `motes` and `mark` parts). The square each is drawn in: BLAST_SPAN radii each way (the
## shader's; its seconds are the kinds' own, keep them equal).
const BLAST_SPAN: float = 2.2
## What `_carrier_card_cues_of` answers: the places of a carrier card's cues and radius, and the defaults.
const CUE_CAST: int = 0
const CUE_SHOWN: int = 1
const CUE_IMPACT: int = 2
const CUE_END: int = 3
const CUE_RADIUS: int = 4
const CUE_WIND: int = 5
const NO_CARRIER_CARD_CUES: Array = [&"cast", &"", &"impact", &"", 0.0, &"wind"]
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
## The cue of a boss's entrance, on its body as its banner shows (`boss_shown`, boss plan OB16). A
## boss with an intro has its overlay's sounds instead (`boss_intro_sound.gd`,
## docs/milestones/boss-intro.md, rule 8), and this cue only when no intro played for it (the run's
## rule off, a boss a phase called: `BossIntroWait`).
const BOSS_INTRO: StringName = &"boss_intro"
## How much quieter an enemy's cast sounds than a wizard's (decibels; the owner, 2026-11-18: an
## audio telegraph, under the players' own).
const ENEMY_CAST_VOLUME: float = -6.0
## The sound of a cast whose carrier card names none of its own (`cast_sounds.gd`).
const CAST_SOUND: StringName = CastSoundsScript.FALLBACK

## Feel's code by effect family (gameplay/feel/README.md, "Feel's jobs"): each an Object of its own
## that works on Feel's members, its containers through aliases of its own (`_link_jobs`), made
## first so a setter that runs early finds them, and freed with Feel.
var _job_flashes: FeelFlashes = FeelFlashes.new()
var _job_cues: FeelCues = FeelCues.new()
var _job_hits: FeelHits = FeelHits.new()
var _job_statuses: FeelStatuses = FeelStatuses.new()
var _job_beams: FeelBeams = FeelBeams.new()
var _job_casts: FeelCasts = FeelCasts.new()
var _job_view: FeelView = FeelView.new()
## The services. Only tests set these, before adding the node; otherwise the
## autoloads are used.
var events: EventsScript = null
## The Audio service every sound plays on (core/audio; docs/milestones/sound.md, section 5): Feel
## decides what plays and when, Audio how. Only tests set it, before adding the node; otherwise the
## `Audio` autoload is used.
var audio: AudioScript = null
## The registry and the projectile manager are handed on to the spectacle whenever they change.
var registry: RegistryScript = null:
	set(value):
		registry = value
		_status_cards.clear()
		if _flash_node != null:
			_job_flashes._read_flash_kinds()
		if _spectacle != null:
			_spectacle.registry = value
		if _numbers != null:
			_numbers.registry = value
		if _intro_sound != null:
			_intro_sound.registry = value
		_card_sounds.registry = value
		if _ambience != null:
			_ambience.registry = value
		_hearing.registry = value
		if _locks != null:
			_locks.registry = value
		if _spawn_look != null:
			_spawn_look.forget_styles()
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
## The frames service (core/sim/frames.gd), asked only which seats are played on this machine
## (the party camera); null looks for the "Frames" autoload.
var frames: FramesScript = null
## The input manager, asked only whether a seat of this machine holds the map (`party_map_view.gd`);
## null looks for the "PlayerInput" autoload.
var input: InputManagerScript = null
## The "Actors" autoload once found (`_actor_table`), while it is still there.
var _auto_actors: ActorsScript = null
## Tests turn this off: Feel steps only when the test calls `step` (no real clock in `_process`).
var drive_engine: bool = true
## A benchmark's fixed clock (tests/benchmark/fixed_steps.gd): while above 0, every drawn frame is
## this many seconds of the view (the camera's easing, the motes, the reveals), as the Tick runs one
## tick a frame, so what is drawn is the same every run; 0: the real clock. Never set by the game.
var fixed_view_delta: float = 0.0
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
			_job_view._reset_camera()
## The last hit `_on_damage_dealt` gave its flash, hold and sound, by the hit actor's id: the
## physics frame and Feel's step (`_steps`), the body (instance id), the attacker and the kind.
## Another hit with all of them the same (no time has passed for Feel or the game) would only do
## them again: the flash is restarted to the same time, the hold is refused for
## both bodies (each rests from the first), and the same sound would start on the next voice in the
## same frame. So it skips them (a crowd of shots on one body: docs/DECISIONS.md, 2026-11-02).
var _juiced_frame: PackedInt64Array = PackedInt64Array()
var _juiced_step: PackedInt64Array = PackedInt64Array()
## Feel's steps so far (`step`).
var _steps: int = 0
## A benchmark's look at where a step goes (`profile_parts`): microseconds summed a part of
## `PROFILE_PARTS`, by the clock it hands (`profile_clock`), as the Tick's `step_profile`; empty
## (the default) times nothing.
var step_profile: PackedInt64Array = PackedInt64Array()
var profile_clock: Callable = Callable()
var _profile_since: int = 0
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
## What each held sound is for and when it ends (`held_sounds.gd`, boss plan OB15); Audio plays them.
var _cast_sounds: CastSoundsScript = null
var _held: HeldSoundsScript = null
## The sounds the spell cards name, read once, shared by the cast sounds, the hits and the beams.
var _card_sounds: CardSoundsScript = CardSoundsScript.new()
## A live beam's hum and its infusions' loops (`beam_sounds.gd`).
var _beam_sounds: BeamSoundsScript = null
## The room in play's sound under the music (atmosphere D, `room_ambience.gd`): which, and its accents.
var _ambience: RoomAmbienceScript = null
## What the bodies sound of their own: their phases' held sounds and cues, and the music they and the
## room ask for (`body_sounds.gd`).
var _body_sounds: BodySoundsScript = null
## The boss intro's two cues, played while the tree is paused for it, and what holds a boss with an
## intro's entrance cue back until it is known whether its intro played.
var _intro_sound: BossIntroSoundScript = null
## Each kind of pickup's sound (`pickup_sounds.gd`).
var _pickup_sounds: PickupSoundsScript = PickupSoundsScript.new()
var _intro_wait: BossIntroWait = BossIntroWait.new()
## The sound the death cue being played sounds in place of its own (an enemy's `death_sound`), read
## once by the next `play_cue` (so a cue its parts play does not take it).
var _sound_instead: StringName = &""
## The tag of the move whose staff's `move_cue` plays now (0: none): its held parts last the move.
var _cue_move: int = 0
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
## (`_carrier_card_look_of`; docs/milestones/card-looks.md): {Carrier.LOOK_BEAM or LOOK_SWING: {card id:
## CardLook}}. Beams' and swing trails' materials take its shader; a beam's light its light. Feel
## reads no card field.
var _carrier_card_looks: Dictionary = {}
## The swings' trails (`swing_trails.gd`, melee I4), drawn from `Spells`' live swings every frame.
var _swing_trails: SwingTrailsScript = null
## The Pulses' rings (`pulse_rings.gd`, props W9a): motes along each live ring's edge, every frame,
## from one typed read of them (`CarrierPulse.read_view` into `_pulse_view`, refilled each frame).
var _pulse_rings: PulseRingsScript = PulseRingsScript.new()
var _pulse_view: PulseView = PulseView.new()
## The open portals' gates (`PortalLookScript`), drawn every frame from one typed read of them
## (`CarrierPortal.read_view` into `_portal_view`, refilled each frame).
var _portal_look: PortalLookScript = null
var _portal_view: PortalView = PortalView.new()
## The spectacle (`spectacle.gd`): motes, floor marks, spell light and their settings.
var _spectacle: SpectacleScript = null
## The ground cover (ground cover GC3): one view a room (`cover_rooms.gd`, each a `cover.gd`;
## connected biomes CB3b), at the floor marks' z, before the spectacle in the tree, so the marks lie
## over it.
var _cover_rooms: CoverRoomsScript = null
## The flat looks' version last handed to the light as readers (`CoverRooms.flats_version`).
var _floor_readers_version: int = -1
## The room's ground, drawn again from its shape as it is laid out (`ground/ground_layout.gd`,
## connected biomes CB4).
var _ground_layout: GroundLayoutScript = null
## The look of a fall into a hole (hub rework HR-H2), drawn from the bodies' state, and its motes'
## thrower (made once).
var _fall_look: FallLook = FallLook.new()
var _fall_motes: Callable = Callable()
## The look of an enemy spawning (enemy spawning EA2: a mark on the floor, then the body rising out of
## it), drawn from the bodies' state; a node at the floor marks' z, under the bodies (made in `_ready`).
var _spawn_look: SpawnLook = null
## The party's camera: it holds this machine's wizards (`Frames.seats_here`), eased as it is drawn.
var party_camera: PartyCameraScript = PartyCameraScript.new()
## The telegraph lanes of casts winding up (`lane` cue parts; docs/milestones/cast-timing.md, T6b).
var _lanes: LanesScript = null
## What dead layered bodies leave: their parts flying apart (boss plan OB8, `remnants.gd`).
var _remnants: RemnantsScript = null
## Every actor's damage numbers (`damage_number_drawer.gd`, props W5).
var _numbers: DamageNumberDrawerScript = null
## The markers at the screen's edge for teammates in none of this machine's views
## (`teammate_markers.gd`).
var _markers: TeammateMarkersScript = null
## The markers at a view's edge for the foes of a fight out of it (`foe_markers.gd`; the owner,
## 2026-11-23).
var _foe_markers: FoeMarkersScript = null
## The Voronoi split screen (connected biomes CB6, `split_screen.gd`): this machine's wizards in a
## view each group once they no longer fit in one picture. Stepped after the party camera.
var split_screen: SplitScreenScript = null
## How it splits (`SplitScreenSetting`; `set_split_mode`): the Voronoi split by default.
var split_mode: int = SplitScreenSetting.DEFAULT
## The "Effects" setting (`EffectsSetting`; `set_effects_mode`). HIGH, a fixed row, until told (the
## pause menu always tells, its default Auto), so tests and benchmarks, whose frames are not the
## machine's, draw the look the owner chose. Read only.
var effects_mode: int = EffectsSetting.HIGH
## The "Effects: Auto" watcher (`effects_auto.gd`): stepped every drawn frame; its row is drawn while
## `effects_mode` is AUTO. The one place the effects' row is chosen; the split screen's budget
## (`split_budget.gd`) only adds its own fallbacks on top while split, and holds it from rising.
var effects_auto: EffectsAutoScript = EffectsAutoScript.new()
## Seconds until the display's shortest frame is read again, and the split budget's rung last frame.
var _floor_wait: float = 0.0
var _rung_seen: int = 0
## The split camera's HUD corners last sent to the HUD (`hud_corners_changed`), by its count.
var _corners_sent: int = 0
## The one picture as views (`ScreenViews.set_single`), for the markers while the screen is not split.
var _one_view: ScreenViewsScript = ScreenViewsScript.new()
## This machine's views in layout pixels, for the markers' layer (`_marker_layer`, drawn at the
## picture's scale: core/display/picture_grid.gd).
var _layout_views: ScreenViewsScript = ScreenViewsScript.new()
var _marker_layer: CanvasLayer = null
## The open room's code over the hub's altar (`altar_code.gd`).
var _altar_code: AltarCodeScript = null
## A biome's gather doors, its gate and the portal home (connected biomes CB7, `gather_door_looks.gd`).
var _gather_doors: GatherDoorLooksScript = null
## A biome's pieces as this machine hears them (connected biomes CB12, `room_hearing.gd`): which
## places Audio plays from, and the room the music and the bed follow.
var _hearing: RoomHearingScript = RoomHearingScript.new()
## A biome's bridge mouths (shimmer, flare, seal: `mouth_looks.gd`), its key doors and secret rocks
## (`lock_looks.gd`) and the dark over its unvisited rooms (`unseen_dark.gd`; CB12).
var _mouths: MouthLooksScript = null
var _locks: LockLooksScript = null
## A biome's secret runes (`rune_looks.gd`; the owner, 2026-11-20).
var _runes: RuneLooksScript = null
var _unseen: UnseenDarkScript = null
## What the rooms nobody has entered hold, not drawn under their dark (`unseen_rooms.gd`; the owner,
## 2026-11-21).
var _unseen_rooms: UnseenRoomsScript = UnseenRoomsScript.new()
## Each laid room's decals (the candles, a torch) drawn from one page each (`decal_pages.gd`).
var _decal_pages: DecalPagesScript = DecalPagesScript.new()
## What stands there, hidden one by one (the owner, 2026-11-21, on #899): the bodies and the rooms'
## mists (`unseen_standing.gd`), and the looks that draw what lies on the floor, each told the dark's
## mask (`UnseenDark.mask`) and drawn again whenever it changes (`_masked_looks`, the mask's changes
## they were drawn for).
var _unseen_standing: UnseenStandingScript = UnseenStandingScript.new()
var _masked_looks: Array[CanvasItem] = []
var _masked_for: int = -1
## The one picture's box as the party camera stands this frame, for `_unseen_rooms` (`_rooms_seen`).
var _rooms_seen_box: RoomsViewBoxesScript = RoomsViewBoxesScript.new()
## Where a wizard teleported from the Y map left: a column of its light narrowing away (`teleport_looks.gd`).
var _teleports: TeleportLooksScript = null
## The black void under a biome's slabs (`void_backdrop.gd`; the owner, 2026-11-19).
var _void: VoidBackdropScript = null
## Each room's own light tinted by its kind (`room_tints.gd`; CB12b), onto the spell light.
var _tints: RoomTintsScript = null
## What each mouth tells of the room behind it, and the held Y map (connected biomes CB9).
var _mouth_symbols: MouthSymbolsScript = null
var _party_map: PartyMapViewScript = null
## The items on the ground (`ground_items.gd`, items I6).
var _ground_items: GroundItemsScript = null
## The coins on the floor (`coins.gd`, connected biomes CB10).
var _coins: CoinsScript = null
## The shops' shelves, the fountains' pools and the keys on the floor (`special_room_looks.gd`,
## connected biomes CB11).
var _special_rooms: SpecialRoomLooksScript = null
## The players' reward items on the floor (`reward_items.gd`; the owner's ask of 2026-11-19).
var _reward_items: RewardItemsScript = null
## The health bars over wizards whose seat drives another body (`away_bars.gd`, items I8).
var _away_bars: AwayBarsScript = null
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
## What each live beam's node (`_live_beams`, by index) was last given of the uniforms that seldom
## change, in `FeelBeams.LiveSet`'s order: the beams job sets one only when its value changes, and
## every one again when the node's shader changes. An entry is made with its node.
var _live_set: Array[Array] = []
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
var _arc_node: MultiMeshInstance2D = null
var _arc_buffer: PackedFloat32Array = PackedFloat32Array()
var _status_node: MultiMeshInstance2D = null
var _status_buffer: PackedFloat32Array = PackedFloat32Array()
var _floor_node: MultiMeshInstance2D = null
var _floor_buffer: PackedFloat32Array = PackedFloat32Array()
## An explosion's parts, and its scorch under the bodies (`shot_blast.gdshader`).
var _blast_node: MultiMeshInstance2D = null
var _blast_buffer: PackedFloat32Array = PackedFloat32Array()
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
## The staff whose wind-up each flash shows (a wind-up cue's, `_on_cast_winding`), or -1: it ends
## the frame that wind-up is over, left or cancelled (a lit barrel shot apart blows at once, and its
## fuse's look ends with its fuse; props W9c), as a lane does (`lanes.gd`).
var _flash_wind: PackedInt32Array = PackedInt32Array()
## 1 for a wind-up's flash that lasts its wind-up (a `lasts_size` part, as the closing ring): its
## seconds follow what the wind-up has left (`Spells.cooldown_left`), so a chill that stretches the
## wind-up, or a freeze that holds it, stretches or holds the ring too, as it does the lane.
var _flash_lasts_wind: PackedByteArray = PackedByteArray()
## The actor whose staff tip the flashes of the cue playing now sit on (`_on_cast_winding`), or NONE,
## and the staff winding up.
var _cue_tip: int = ActorsScript.NONE
var _cue_wind: int = -1
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
## The carrier card whose hit `hit_landed` announced (its `card`, `&""` for none): its own hit sound
## plays in place of its kind's (`CastSounds.hit_sound`).
var _kind_card: StringName = &""
## How much quieter a hit sound plays when it comes again soon (`hit_repeats.gd`).
var _hit_repeats: HitRepeatsScript = HitRepeatsScript.new()
var _impact_at: Vector2 = Vector2.ZERO
var _impact_aim: Vector2 = Vector2.ZERO
## How far past the picture's edge (world pixels) a hit or a cue still shakes and kicks the camera
## (`_in_picture`): a blast just off the screen is still felt.
const SHAKE_REACH: float = 64.0
## Camera kick of casts (pixels), added to the shake.
var _kick: Vector2 = Vector2.ZERO
var _last_usec: int = 0
## The cues and radius read from the carrier cards, by card id (see `_carrier_card_cues_of`).
var _carrier_card_cues: Dictionary = {}
## The cues read from `content/cues`, by id (see `cue_of`).
var _cue_cache: Dictionary = {}
## The cues that play at most `every` seconds apart (`CueBase.every`): each one's first index in
## `_cue_next_at` by id, and there, by actor (its id + 1: none first), the clock time (`_clock`)
## from which it may play again. Grown once per such cue, then written in place.
var _cue_every_at: Dictionary = {}
var _cue_next_at: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	_link_jobs()


## Links every job to Feel's members (`link`). Feel only ever changes its containers in place
## (resize, fill, clear), never puts another in a member's place, so once is enough.
func _link_jobs() -> void:
	_job_flashes.link(self)
	_job_cues.link(self)
	_job_hits.link(self)
	_job_statuses.link(self)
	_job_beams.link(self)
	_job_casts.link(self)
	_job_view.link(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# The jobs are plain objects (a call into one costs less than into a counted one): freed with it.
		# This comes after `_exit_tree`, which must call no job.
		_job_flashes.free()
		_job_cues.free()
		_job_hits.free()
		_job_statuses.free()
		_job_beams.free()
		_job_casts.free()
		_job_view.free()


## Leaving the tree (a test's Feel freed, the game quitting): what it started on Audio stops, so
## nothing it held outlives it on a shared Audio.
func _exit_tree() -> void:
	if audio != null and is_instance_valid(audio):
		audio.silence()
		if audio.ears.heard == Callable(_hearing, &"hears"):
			audio.ears.heard = Callable()
	if _held != null:
		_held.clear()


func _ready() -> void:
	_rng.seed = 1
	# The damage numbers' glyphs rasterized now, never in play (core/base/glyph_warmup.gd: safe with
	# a separate render thread).
	GlyphWarmup.warm_game()
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
		_shown_beams.append(_job_beams._make_beam())
		_shown_beam_paths.append(_job_beams._make_beam_path())
	_job_flashes._make_flashes()
	for i in LIVE_BEAMS:
		_live_beams.append(_job_beams._make_beam())
		_live_paths.append(_job_beams._make_beam_path())
	_swing_trails = SwingTrailsScript.new(FeelBeams.swing_mesh())
	add_child(_swing_trails)
	_portal_look = PortalLookScript.new()
	add_child(_portal_look)
	_ground_layout = GroundLayoutScript.new()
	_ground_layout.name = "Ground"
	_ground_layout.events = events
	_ground_layout.registry = registry
	add_child(_ground_layout)
	# Before the spectacle: at the marks' z the later node draws on top, so the marks lie over the cover.
	_cover_rooms = CoverRoomsScript.new(MARK_Z)
	_cover_rooms.name = "CoverRooms"
	_cover_rooms.events = events
	_cover_rooms.registry = registry
	add_child(_cover_rooms)
	_spectacle = SpectacleScript.new()
	_spectacle.name = "Spectacle"
	_spectacle.events = events
	_spectacle.registry = registry
	_spectacle.particles_enabled = particles_enabled
	add_child(_spectacle)
	# Burning cover's embers and smoke cool through the spectacle's ramps (GC8).
	_cover_rooms.set_ramp_table(_spectacle.ramp_table())
	# The floor flashes (a slam's burst and star) share the floor marks' z; at one z the later node
	# draws on top, so they come after the spectacle, whose mark layer (made whenever the setting
	# turns on) is inside it: a new strike shows over the marks earlier ones left.
	move_child(_floor_node, _spectacle.get_index())
	# A spawn's mark lies on the floor, over the marks and the cover, under every body.
	_spawn_look = SpawnLook.new()
	_spawn_look.name = "SpawnLook"
	_spawn_look.z_index = MARK_Z
	_spawn_look.play_cue = _job_cues._play_spawn_cue
	_spawn_look.style_of = _job_cues._spawn_style
	add_child(_spawn_look)
	_lanes = LanesScript.new()
	_lanes.name = "Lanes"
	# Over the shots and every flash, so a shot's telegraph is never hidden.
	# But a move's (a dash's pass): painted on the floor, under every body (`Lanes.floor_z`).
	_lanes.z_index = SHOWN_BEAM_Z + 2
	_lanes.floor_z = MARK_Z
	add_child(_lanes)
	_remnants = RemnantsScript.new()
	_remnants.name = "Remnants"
	add_child(_remnants)
	if audio == null:
		audio = get_node_or_null("/root/Audio") as AudioScript
	_held = HeldSoundsScript.new()
	_held.audio = audio
	_cast_sounds = CastSoundsScript.new()
	_cast_sounds.audio = audio
	_card_sounds.registry = registry
	_cast_sounds.cards = _card_sounds
	_beam_sounds = BeamSoundsScript.new()
	_beam_sounds.held = _held
	_beam_sounds.cards = _card_sounds
	_ambience = RoomAmbienceScript.new()
	_ambience.name = "RoomAmbience"
	_ambience.events = events
	_ambience.registry = registry
	_ambience.audio = audio
	add_child(_ambience)
	_body_sounds = BodySoundsScript.new()
	_body_sounds.held = _held
	_body_sounds.heard = _hearing.hears
	_body_sounds.audio = audio
	_body_sounds.play_cue = _job_cues._play_body_cue
	_intro_sound = BossIntroSoundScript.new()
	_intro_sound.name = "BossIntroSound"
	_intro_sound.registry = registry
	_intro_sound.audio = audio
	add_child(_intro_sound)
	_pickup_sounds.audio = audio
	_job_cues.add_cue_part(&"held", _job_casts._play_held)
	_numbers = DamageNumberDrawerScript.new()
	_numbers.name = "DamageNumbers"
	_numbers.events = events
	_numbers.registry = registry
	add_child(_numbers)
	# On a layer of its own over the HUD's, in screen pixels.
	# Laid out in layout pixels and drawn at the picture's scale, as the HUD (PictureGrid).
	var marker_layer := CanvasLayer.new()
	marker_layer.name = "MarkerLayer"
	marker_layer.layer = TeammateMarkersScript.LAYER
	add_child(marker_layer)
	PictureGrid.keep_fitted(marker_layer)
	_marker_layer = marker_layer
	split_screen = SplitScreenScript.new()
	add_child(split_screen)
	_job_view.set_split_mode(split_mode)
	# The foes' first: a teammate's marker is drawn over a foe's.
	_foe_markers = FoeMarkersScript.new()
	_foe_markers.name = "FoeMarkers"
	marker_layer.add_child(_foe_markers)
	_markers = TeammateMarkersScript.new()
	_markers.name = "TeammateMarkers"
	marker_layer.add_child(_markers)
	_altar_code = AltarCodeScript.new()
	_altar_code.name = "AltarCode"
	add_child(_altar_code)
	_altar_code.bind(events)
	_gather_doors = GatherDoorLooksScript.new()
	_gather_doors.name = "GatherDoors"
	add_child(_gather_doors)
	_gather_doors.bind(events)
	_hearing.registry = registry
	_hearing.bind(events)
	if audio != null:
		audio.ears.heard = _hearing.hears
	_mouths = MouthLooksScript.new()
	_mouths.name = "MouthLooks"
	_mouths.pieces = _hearing
	add_child(_mouths)
	_mouths.bind(events)
	_locks = LockLooksScript.new()
	_locks.name = "LockLooks"
	_locks.registry = registry
	add_child(_locks)
	_locks.bind(events)
	_runes = RuneLooksScript.new()
	_runes.name = "RuneLooks"
	_runes.registry = registry
	add_child(_runes)
	_runes.bind(events)
	_void = VoidBackdropScript.new()
	_void.name = "VoidBackdrop"
	add_child(_void)
	_unseen = UnseenDarkScript.new()
	_unseen.name = "UnseenDark"
	_unseen.pieces = _hearing
	add_child(_unseen)
	_unseen.bind(events)
	_unseen_rooms.bind(events)
	_decal_pages.bind(events)
	_teleports = TeleportLooksScript.new()
	_teleports.name = "TeleportLooks"
	add_child(_teleports)
	_teleports.bind(events)
	_tints = RoomTintsScript.new()
	_tints.pieces = _hearing
	_tints.bind(events)
	if _spectacle != null:
		_spectacle.kind_air.pieces = _hearing
	_mouth_symbols = MouthSymbolsScript.new()
	_mouth_symbols.name = "MouthSymbols"
	_mouth_symbols.pieces = _hearing
	_mouth_symbols.mouths = _mouths
	add_child(_mouth_symbols)
	_party_map = PartyMapViewScript.new()
	_party_map.name = "PartyMap"
	_party_map.pieces = _hearing
	add_child(_party_map)
	_party_map.bind(events)
	_ground_items = GroundItemsScript.new()
	_ground_items.name = "GroundItems"
	add_child(_ground_items)
	_ground_items.bind(events)
	_coins = CoinsScript.new()
	_coins.name = "Coins"
	add_child(_coins)
	_coins.bind(events)
	_special_rooms = SpecialRoomLooksScript.new()
	_special_rooms.name = "SpecialRoomLooks"
	add_child(_special_rooms)
	_special_rooms.bind(events)
	_reward_items = RewardItemsScript.new()
	_reward_items.name = "RewardItems"
	add_child(_reward_items)
	_reward_items.bind(events)
	_job_view._mask_looks()
	_away_bars = AwayBarsScript.new()
	_away_bars.name = "AwayBars"
	add_child(_away_bars)
	_job_cues.add_cue_part(&"flash", _job_flashes._play_flash, _job_flashes._prepare_flash)
	_job_cues.add_cue_part(&"lane", _job_casts._play_lane)
	var parts: Dictionary = _spectacle.cue_parts()
	for type: StringName in parts:
		var row: Array = parts[type] as Array
		_job_cues.add_cue_part(type, row[0] as Callable, row[1] as Callable if row.size() > 1 else Callable(), row[2] as Callable if row.size() > 2 else Callable())
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
	if events == null:
		push_warning("Feel: the Events autoload is missing, so there is no juice.")
		return
	events.damage_dealt.connect(_job_hits._on_damage_dealt)
	events.hit_landed.connect(_job_hits._on_hit_landed)
	events.heal_dealt.connect(_job_cues._on_heal_dealt)
	events.enemy_died.connect(_job_hits._on_enemy_died)
	events.player_downed.connect(_job_statuses._on_player_downed)
	events.spell_cast.connect(_job_casts._on_spell_cast)
	events.barrier_changed.connect(_job_casts._on_barrier_changed)
	events.staff_shown.connect(_job_cues._on_staff_shown)
	events.possess_started.connect(_job_cues._on_possess_started)
	events.possess_ended.connect(_job_cues._on_possess_ended)
	events.boss_shown.connect(_job_cues._on_boss_shown)
	_intro_sound.bind(events)
	_pickup_sounds.bind(events)
	_intro_wait.bind(events)
	_intro_wait.released.connect(_job_cues._on_boss_released)
	events.projectile_impact.connect(_job_hits._on_projectile_impact)
	events.carrier_shown.connect(_job_beams._on_carrier_shown)
	events.cast_winding.connect(_job_casts._on_cast_winding)
	events.aim_locked.connect(_job_casts._on_aim_locked)
	events.carrier_ended.connect(_job_cues._on_carrier_ended)
	events.cast_left.connect(_job_casts._on_cast_left)
	events.caster_move_finished.connect(_job_casts._on_caster_move_finished)
	events.cue_shown.connect(_job_cues._on_cue_shown)
	events.reaction_triggered.connect(_job_statuses._on_reaction_triggered)
	events.discharge_arc.connect(_job_statuses._on_discharge_arc)
	events.status_applied.connect(_job_statuses._on_status_applied)
	events.effect_slots_changed.connect(_on_effect_slots_changed)
	events.screen_shake_changed.connect(_on_screen_shake_changed)
	events.split_screen_changed.connect(_job_view.set_split_mode)
	events.effects_changed.connect(_job_view.set_effects_mode)
	events.projectile_expired.connect(_job_hits._on_projectile_expired)
	events.shot_deflected.connect(_job_hits._on_shot_deflected)
	events.shot_blocked.connect(_job_hits._on_shot_blocked)
	events.room_entered.connect(_job_view._on_room_entered)
	events.main_menu_requested.connect(_job_view._on_main_menu_requested)
	if combat == null:
		combat = get_node_or_null("/root/Combat")
	if projectiles == null:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectileManagerScript
	if spells == null:
		spells = get_node_or_null("/root/Spells")
	_job_beams._warm_card_looks()
	if _portal_look != null and spells is SpellRuntime:
		_portal_look.use_shaders((spells as SpellRuntime).look_shaders(Carrier.LOOK_PORTAL))
	if projectiles != null and projectiles.texture == null:
		projectiles.texture = preset.bolt_texture
	_spectacle.attach(projectiles, spells)


func _process(delta: float) -> void:
	var real_delta: float = delta
	if fixed_view_delta > 0.0:
		real_delta = fixed_view_delta
		_last_usec = Time.get_ticks_usec()
	elif drive_engine:
		# Real time from the clock, so a test's or benchmark's tick rate cannot skew it.
		var now: int = Time.get_ticks_usec()
		real_delta = minf(float(now - _last_usec) / 1000000.0, 0.25)
		_last_usec = now
	step(real_delta)


## The parts of a step `step_profile` sums, in order.
const PROFILE_PARTS: PackedStringArray = ["camera and split", "markers, flashes and beams", "carriers, statuses, falls, spawns", "cover", "spectacle", "rooms and sound", "labels and numbers"]


## Time each part of every step from now, by `clock` (microseconds); `step_profile` sums them from 0.
func profile_parts(clock: Callable) -> void:
	profile_clock = clock
	step_profile = PackedInt64Array()
	step_profile.resize(PROFILE_PARTS.size())


## The part `part` of this step ends now (a profile's; nothing without one).
func _profile_mark(part: int) -> void:
	if step_profile.is_empty():
		return
	var now: int = int(profile_clock.call())
	if part >= 0:
		step_profile[part] += now - _profile_since
	_profile_since = now


## Advance by `real_delta` seconds of real time (not slowed by hit-stop).
func step(real_delta: float) -> void:
	_profile_mark(-1)
	# The world's camera now, for the party camera: looked for afresh every drawn frame (a new
	# world's is there at once), before the step is counted, so the first hit after it still looks
	# again (`_refresh_camera` looks once a step).
	_camera_step = -1
	_job_view._refresh_camera()
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
		_job_view._apply_camera()
	party_camera.follow(_job_view._live_camera())
	var seats_here: int = _job_view._seats_here()
	party_camera.look(_actor_table(), seats_here)
	party_camera.step(real_delta)
	var grid_now: RoomGrid = projectiles.grid() if projectiles != null and is_instance_valid(projectiles) else null
	if split_screen != null:
		var world_camera: Camera2D = party_camera.camera if is_instance_valid(party_camera.camera) else null
		split_screen.void_bounds = projectiles.bounds() if grid_now != null and grid_now.places() > 0 else Rect2()
		split_screen.step(real_delta, _actor_table(), seats_here, world_camera)
		_spectacle.set_void_blank(split_screen.void_rect())
		_job_view._tell_hud_corners()
		_spectacle.set_split(split_screen.views(), split_screen.mote_share(), split_screen.light_downscale())
	_job_view._step_effects(real_delta)
	_profile_mark(0)
	if _markers != null:
		var views_now: ScreenViewsScript = _job_view._views_shown().scaled_into(_layout_views, 1.0 / _marker_layer.transform.get_scale().x)
		_markers.step(_actor_table(), seats_here, views_now, _clock)
		_foe_markers.step(real_delta, _actor_table(), grid_now, seats_here, views_now)
	if _away_bars != null:
		_away_bars.step(_actor_table())
	_intro_wait.settle()
	_job_hits._step_reactions(real_delta)
	_job_beams._step_shown_beams(real_delta)
	_job_flashes._step_flashes(real_delta)
	_flashes_shown = 0
	_hit_sounds = 0
	_job_beams._draw_live_beams(real_delta)
	_profile_mark(1)
	if _swing_trails != null:
		_swing_trails.step(spells.call("carrier", &"swing") if spells != null and spells.has_method("carrier") else null, _clock, _job_beams._swing_ramp, preset.beam_alpha, _spectacle.births if _spectacle.motes_on() else null, _job_beams._swing_shader_of)
	if _spectacle.motes_on():
		var rings: CarrierPulse = CarrierPulse.of(spells as SpellRuntime) if spells is SpellRuntime else null
		if rings != null:
			rings.read_view(_pulse_view)
		else:
			_pulse_view.rings = 0
		_pulse_rings.step(_pulse_view, real_delta, _job_beams._swing_ramp, _spectacle.births)
	if _portal_look != null:
		_job_view._step_portals()
	_job_statuses._status_motes(real_delta)
	if not _fall_motes.is_valid():
		_fall_motes = _job_statuses._throw_fall_motes
	_fall_look.step(_actor_table(), real_delta, _fall_motes if _spectacle.motes_on() else Callable())
	if _spawn_look != null:
		_spawn_look.step(_actor_table(), real_delta)
	_profile_mark(2)
	var picture: Rect2 = _job_view._picture()
	var focus: Vector2 = _job_view._focus(picture)
	# The world's stirs first (atmosphere E): the cover, the lights and the motes read them.
	_spectacle.step_stirs(_clock, picture)
	_cover_rooms.step(_clock, _actor_table(), focus, _spectacle.pool if _spectacle.motes_on() else null, picture, _spectacle.stirs.version, _spectacle.stirs.hand_to)
	# The floor's look reads the light and lights it (docs/milestones/floor-look.md).
	if _cover_rooms.flats_version() != _floor_readers_version:
		_floor_readers_version = _cover_rooms.flats_version()
		var readers: Array[ShaderMaterial] = []
		_cover_rooms.flat_materials(readers)
		_spectacle.read_floor(readers)
	_spectacle.light_floor(_cover_rooms.lights.rows, _cover_rooms.lights.count)
	# The bodies the cover found part the mist (atmosphere F): one gathering, read by both.
	_spectacle.hand_bodies(cover().bodies(), cover().body_count())
	_profile_mark(3)
	# What stands where nobody has seen yet is hidden before the shadows and the lights are cast from
	# the bodies drawn (the owner, 2026-11-21, on #899): the bodies and the rooms' mists, by the mask
	# as the dark laid it last frame.
	if _unseen != null:
		_unseen_standing.step(_unseen.mask, _actor_table(), _spectacle.mist, _spectacle.room_mists)
	_spectacle.step(_clock, _actor_table())
	_profile_mark(4)
	if _lanes != null:
		_lanes.spells = spells
		_lanes.step(real_delta)
	if _held != null:
		_held.spells = spells
		_held.step()
	_job_view._step_rooms(real_delta, seats_here)
	if _body_sounds != null:
		_body_sounds.step(real_delta, _actor_table())
	if _ambience != null:
		_ambience.step(real_delta, focus)
	_profile_mark(5)
	_job_statuses._step_labels(real_delta)
	if _remnants != null:
		_remnants.step(real_delta)
	if _numbers != null:
		_numbers.step(real_delta)
	_job_statuses._step_statuses(real_delta)
	_profile_mark(6)


## A biome's rooms as this machine sees and hears them (connected biomes CB12): the places heard
## (Audio's ears ask), the music and the bed of the room followed, the mouths, the gather doors'
## wizards and the dark of the unvisited rooms.
func _step_rooms(real_delta: float, seats_here: int) -> void:
	_job_view._step_rooms(real_delta, seats_here)


## What stands where nobody has seen yet, hidden (for tests).
func unseen_standing() -> UnseenStandingScript:
	return _unseen_standing


## This machine's views now: the split screen's, or the party camera's one picture as one view.
func _views_shown() -> ScreenViewsScript:
	return _job_view._views_shown()


## Sprites flashing right now (for tests).
func reacting_sprites() -> int:
	return _react_count


## Current camera kick in pixels (for tests).
func kick() -> Vector2:
	return _kick


## Current shake strength, 0 to 1.
func trauma() -> float:
	return _trauma


## Discharge arcs showing right now (for tests).
func live_arcs() -> int:
	return _job_flashes.live_arcs()


## How status `id` is shown (spell spectacle 2, S6 item 11): the `status_look()` of the element
## card whose status it is, or for a status no element puts on (freeze), of the one whose status it
## deepens from (`FeelPreset.deep_statuses`): [status, tint, look layer, card id], ElementBase's
## STATUS_LOOK_*. Empty for none (an unknown status shows nothing). Found once in the registry's
## cards.
func _status_card(id: StringName) -> Array:
	return _job_statuses._status_card(id)


## The colour status `id` glows in and its motes cool from: its card's tint, `status_deep_white` of
## the way to white for a deep one (freeze); white for a status with no card.
func status_color(id: StringName) -> Color:
	return _job_statuses.status_color(id)


## The status shown on `enemy` (empty for none), for tests.
func status_shown(enemy: Node) -> StringName:
	return _job_statuses.status_shown(enemy)


## Statuses showing right now (for tests).
func live_statuses() -> int:
	return _job_statuses.live_statuses()


## Reaction names showing right now (for tests).
func live_labels() -> int:
	return _job_statuses.live_labels()


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
	_job_cues.play_cue(id, caster, at, dir, size, tint, look, target, shot, surface, tag, weight, body_color, ramp, follow)


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
	_job_cues.add_cue_part(type, player, prepare, needs_spray)


## Whether a cue part of the type `type` has a player.
func has_cue_part(type: StringName) -> bool:
	return _job_cues.has_cue_part(type)


## Forget the cues read so far (`cue_of`, and their plans), so the next play reads them again (a
## cue file changed, or a test's own cue).
func forget_cues() -> void:
	_job_cues.forget_cues()


## The cue `id` (`content/cues/<id>.tres`), or null when there is none or no registry yet. Read
## once per id, then kept: a cue allocates nothing.
func cue_of(id: StringName) -> CueBase:
	return _job_cues.cue_of(id)


## The shader that draws the carrier card `carrier_card`'s look in the area `drawer`, or `plain` when its
## card names none (or is drawn by another area).
func _carrier_card_shader_of(carrier_card: StringName, drawer: int, plain: Shader) -> Shader:
	return _job_beams._carrier_card_shader_of(carrier_card, drawer, plain)


## Warms the carrier cards' own shaders Feel draws (beams' and swing trails', one mesh each:
## `Spells.look_shaders`) before the first room, as it warms its own; Spells knows nothing of how.
func _warm_card_looks() -> void:
	_job_beams._warm_card_looks()


## The mesh a beam is drawn as (`shot_beam.gdshader`, PARTICLES ARE GEOMETRY there): small quads
## told in their UV which quad kind (BEAM_Q_*) and slot they are, in BEAM_QUADS' order, as
## `flash_mesh`. The shader places them along the beam's path in the world, so the mesh says
## nothing of where: it is never culled (its box is the whole world). Made once.
static func beam_mesh() -> ArrayMesh:
	return FeelBeams.beam_mesh()


## The mesh a swing's trail is drawn as (`SwingTrailsScript.SWING_QUADS`; Q_* in
## `shot_swing.gdshader`), as `beam_mesh`. Made once.
static func swing_mesh() -> ArrayMesh:
	return FeelBeams.swing_mesh()


## The swing trails (for tests).
func swing_trails() -> SwingTrailsScript:
	return _swing_trails


## The flash kind `id` (content/flashes), or null.
func flash_kind(id: StringName) -> FlashKind:
	return _job_flashes.flash_kind(id)


## The mesh a flash is drawn as (`shot_flash.gdshader`, PARTICLES ARE GEOMETRY there): small
## quads, each told in its UV which quad kind (FLASH_Q_*) and slot it is, in FLASH_QUADS'
## order. The shader places every quad in the flash's square, or folds it away; a vertex says
## which quad and corner it is in its UV: x the slot + 0.25 or 0.75, y the kind + 0.25 or 0.75.
## Made once.
static func flash_mesh() -> ArrayMesh:
	return FeelFlashes.flash_mesh()


## The mesh an explosion's part is drawn as (`shot_blast.gdshader`): its light and BLAST_PIECES
## small quads, told their kind and slot in their UV as `flash_mesh`'s. Made once.
static func blast_mesh() -> ArrayMesh:
	return FeelFlashes.blast_mesh()


## The setting: how many flashes can show at once, snapped by `EffectSlots.snap`. Returns the
## number taken.
func set_effect_slots(slots: int) -> int:
	return _job_flashes.set_effect_slots(slots)


func _on_effect_slots_changed(slots: int) -> void:
	_job_flashes.set_effect_slots(slots)


# --- The spectacle (spectacle.gd): forwards for the tests, the benchmarks and the menus ---------

## The spectacle node.
func spectacle() -> SpectacleScript:
	return _spectacle


## Every actor's damage numbers (tests).
func damage_numbers() -> DamageNumberDrawerScript:
	return _numbers


## The items on the ground's look (for tests).
func ground_items() -> GroundItemsScript:
	return _ground_items


## The coins on the floor's look (for tests).
func reward_items() -> RewardItemsScript:
	return _reward_items


func coins() -> CoinsScript:
	return _coins


## The special rooms' look: shelves, pools and keys (connected biomes CB11; for tests).
func special_rooms() -> SpecialRoomLooksScript:
	return _special_rooms


## The gather doors' look (connected biomes CB7).
func gather_doors() -> GatherDoorLooksScript:
	return _gather_doors


## A biome's pieces as heard, its mouths, key doors and secret rocks, the unvisited rooms' dark (for
## tests; connected biomes CB12).
func room_hearing() -> RoomHearingScript:
	return _hearing


func mouth_looks() -> MouthLooksScript:
	return _mouths


func lock_looks() -> LockLooksScript:
	return _locks


func rune_looks() -> RuneLooksScript:
	return _runes


## Where a teleported wizard left (for tests).
func teleport_looks() -> TeleportLooksScript:
	return _teleports


func unseen_dark() -> UnseenDarkScript:
	return _unseen


## The parts of the world drawn this frame, for what lies out of every view (`unseen_rooms.gd`): the
## split's views' boxes (`ScreenViews`, laid this frame), else the party camera's picture where it
## was put this frame (`PartyCamera.visible_rect`): the viewport's canvas transform follows the
## camera only after this frame's process, a frame late, and on a long pan a room at the leading
## edge would come in a frame after its place on screen. Without a party camera, the spectacle's.
func _rooms_seen() -> RoomsViewBoxesScript:
	return _job_view._rooms_seen()


## What the unvisited rooms hold, not drawn (for tests).
func unseen_rooms() -> UnseenRoomsScript:
	return _unseen_rooms


## The black void under a biome's slabs (for tests).
func void_backdrop() -> VoidBackdropScript:
	return _void


## Each room's tint by its kind (CB12b; for tests and the screenshots).
func room_tints() -> RoomTintsScript:
	return _tints


## What each mouth tells of the room behind it and the held Y map (for tests; connected biomes CB9).
func mouth_symbols() -> MouthSymbolsScript:
	return _mouth_symbols


func party_map() -> PartyMapViewScript:
	return _party_map


## The room's code over the altar (for tests).
func altar_code() -> AltarCodeScript:
	return _altar_code


## The health bars over wizards whose seat is away (for tests).
func away_bars() -> AwayBarsScript:
	return _away_bars


## The markers for teammates out of the picture (for tests).
func teammate_markers() -> TeammateMarkersScript:
	return _markers


## The markers for a fight's foes out of view (for tests).
func foe_markers() -> FoeMarkersScript:
	return _foe_markers


## The motes (null with the setting off; for tests and the benchmarks).
func motes() -> MotesScript:
	return _spectacle.pool if _spectacle != null else null


## The first room's ground cover's look (a row run's room, a biome's start room; for tests and the
## screenshots).
func cover() -> CoverScript:
	return _cover_rooms.first() if _cover_rooms != null else null


## Every room's ground cover's look (`cover_rooms.gd`: `view_of(number)`), for tests.
func cover_rooms() -> CoverRoomsScript:
	return _cover_rooms


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


## Whether the per-frame effects' independent pieces run on the worker threads (`feel_jobs.gd`: on by
## default where the engine has threads and 4 or more cores, never on the web or fewer cores, whatever is asked). This
## machine's, never a run's: what is drawn is the same either way. Returns the setting.
func set_effect_threads(on: bool) -> bool:
	_spectacle.jobs.threaded = on and FeelJobsScript.default_threaded()
	return _spectacle.jobs.threaded


## Whether the effects that can are worked out by compute shaders on the GPU (`GpuCompute`: on by
## default on the desktop's Mobile renderer, never on the web's Compatibility one or headless; the light
## grid, `light_grid_gpu.gd`). This machine's, never a run's: what is drawn is the same within a byte
## of light either way. Returns whether the light grid is on the GPU now.
func set_gpu_effects(on: bool) -> bool:
	GpuCompute.allowed = on
	var lit: SpellLightScript = light()
	return lit.use_gpu(on) if lit != null else false


## The "Dynamic lighting" setting (once "Spell light"; `Spectacle.set_spell_light`). Returns the
## setting.
func set_spell_light(on: bool) -> bool:
	return _spectacle.set_spell_light(on)


## The atmosphere's switches (docs/milestones/atmosphere.md, "Settings"; the spectacle hears their
## events itself): "Shadows", "Ambient particles", "Fog" and "Environment interaction". Each returns
## the setting.
func set_shadows(on: bool) -> bool:
	return _spectacle.set_shadows(on)


func set_ambient_particles(on: bool) -> bool:
	return _spectacle.set_ambient_particles(on)


func set_fog(on: bool) -> bool:
	return _spectacle.set_fog(on)


func set_environment_interaction(on: bool) -> bool:
	return _spectacle.set_environment_interaction(on)


func _on_screen_shake_changed(enabled: bool) -> void:
	shake_enabled = enabled


## How this machine's screen splits (`SplitScreenSetting`: DYNAMIC, the Voronoi split, or EQUAL,
## equal panes; the pause menu's "Split screen", `split_screen_changed`). View only.
func set_split_mode(mode: int) -> void:
	_job_view.set_split_mode(mode)


## The "Effects" setting's `mode` (`EffectsSetting`; the pause menu's "Effects", `effects_changed`):
## AUTO lets the watcher choose the row from the drawn frames' times, starting at HIGH; LOW, MEDIUM
## and HIGH draw that row. Taken in one frame (the owner's exception to "Smooth", 2026-11-22). View only.
func set_effects_mode(mode: int) -> void:
	_job_view.set_effects_mode(mode)


## The shortest frame this machine draws (seconds; 0: none known): the display's refresh and the
## frame cap (`Engine.max_fps`), so Auto never counts a 50 Hz display's frames as slow. View only.
static func shortest_frame() -> float:
	return FeelView.shortest_frame()


## Show a flash of the kind `id` (content/flashes) at `at`, aimed along `dir`, in the ramp of
## `core` (white: the colours of `ramp`, a caster's `Actors.ramp_of`: 0-3 a hat ramp, anything else
## from NONE up the enemy ramp) with the particles of the packed `look`, at `zoom`, for
## `seconds`. An arc runs `length` pixels from `at` along `dir` (its zoom is then the length). A
## flash given a `follow` node moves with it, and ends when it is gone. It takes the next slot, the
## oldest flash when they are all busy, and returns it (-1 for none, or a kind there is not; a hit's
## own flash past its share of a frame's, `_hit_flashes_full`, is none).
func show_flash(id: StringName, at: Vector2, dir: Vector2, core: Color, ramp: int, look: int, zoom: int, seconds: float, length: float = 0.0, follow: Node2D = null) -> int:
	return _job_flashes.show_flash(id, at, dir, core, ramp, look, zoom, seconds, length, follow)


## How many flashes are showing (for tests and the sheets).
func live_flashes() -> int:
	return _job_flashes.live_flashes()


## How many live flashes are of the kind `id`, and (with a `ramp` 0-4) in that ramp.
func flashes_of(id: StringName, ramp: int = -1) -> int:
	return _job_flashes.flashes_of(id, ramp)


## The core colour and look of the newest live flash of the kind `id` (for tests): [core, look].
func flash_dress(id: StringName) -> Array:
	return _job_flashes.flash_dress(id)


## The newest live flash of the kind `id` (for tests): its place, way, core colour, ramp, zoom,
## look, seconds and room light, or an empty dictionary when none shows.
func flash_info(id: StringName) -> Dictionary:
	return _job_flashes.flash_info(id)


## The newest status glow shown (for tests), as `flash_info`.
func status_info() -> Dictionary:
	return _job_flashes.status_info()


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


## The remnants dead layered bodies left (for tests).
func remnants() -> RemnantsScript:
	return _remnants


## The cues the carrier card `carrier_card` names and its radius (`CarrierCard.look_cues`: [cast_cue,
## shown_cue, impact_cue, end_cue, radius], CUE_CAST to CUE_RADIUS), the defaults (`cast` and `impact`, radius
## 0) for an id that is no carrier card; a modifier that shows itself (`carrier_shown` `zap`, `siphon`) brings its
## own `cue` as its shown cue. Read once per card id, then kept: a cast or a hit allocates nothing.
## With no registry yet, or no carrier card id, the defaults are answered but not kept.
func _carrier_card_cues_of(carrier_card: StringName) -> Array:
	return _job_cues._carrier_card_cues_of(carrier_card)


## The lanes under way (for tests).
func lanes() -> LanesScript:
	return _lanes


## Feel's held sounds (for tests).
func held_sounds() -> HeldSoundsScript:
	return _held


## The room's sound under the music (for tests).
func ambience() -> RoomAmbienceScript:
	return _ambience


## The cast sounds (for tests).
func cast_sounds() -> CastSoundsScript:
	return _cast_sounds


## The sound of live beam `i` of `beams` (its card's hum and its infusions' loops, `beam_sounds.gd`)
## for this frame, from its caster's body (else its `origin`): an enemy's ENEMY_CAST_VOLUME quieter,
## as its cast is; a prop's none (the world's); as it dissolves (`fade`, 1 to 0) it fades with it,
## down to BEAM_FADE_FLOOR.
func _sound_beam(beams: Object, i: int, caster: int, origin: Vector2, fade: float) -> void:
	_job_beams._sound_beam(beams, i, caster, origin, fade)


## The motes a beam gives off over `seconds` (see BEAM_SPLASH_RATE), into the spectacle's births
## while motes are on: its path is the first `points` of `path` (x, y and how far along), `length`
## pixels long, landing at `end_at` going `end_dir`, `fade` whole (1 to 0), of the shader ramp
## `ramp` (0-3 a hat ramp, -1 the enemies'), the look `look`, the tint `tint`, the spell of `tag`.
func _beam_motes(path: PackedVector3Array, points: int, length: float, end_at: Vector2, end_dir: Vector2, fade: float, ramp: int, look: int, tint: Color, tag: int, seconds: float) -> void:
	_job_beams._beam_motes(path, points, length, end_at, end_dir, fade, ramp, look, tint, tag, seconds)


## The boss intro's sounds (for tests).
func boss_intro_sound() -> BossIntroSoundScript:
	return _intro_sound


## Plays a sound where it happens (`at`; INF: the middle of the picture), `volume` decibels on top of
## its own, at `pitch` times its own; returns the voice used, or -1 for none.
func _play(id: StringName, at: Vector2 = Vector2.INF, volume: float = 0.0, pitch: float = 1.0) -> int:
	if audio == null:
		return -1
	return audio.play(id, at, volume, AudioScript.BUS_SFX, pitch)

