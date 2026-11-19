extends Node
## The spectacle: everything Feel draws that is drawn only (docs/milestones/spell-spectacle.md and
## spell-spectacle-2.md, S1): the motes (`mote.gd`), the floor marks (`marks.gd`), spell light
## (`spell_light.gd`) and the ramp table the motes and marks share (`ramp_table.gd`). A child of
## Feel, made once; it owns their settings ("Particles", "Particle amount", "Floor marks", "Dynamic
## lighting", "Shadows", "Ambient particles", "Fog" and "Environment interaction", each through its
## event; docs/milestones/atmosphere.md, "Settings") and the room they are in (`room_entered`: the walls' colours and
## the mark layer's fit), and plays a cue's `motes`, `mark`, `light` and `stream` parts (`cue_parts`,
## which Feel adds to its table of part players).
##
## Feel says when: its hit and wall handlers call `shed_hit` and `shed_on_wall` with what it
## already worked out (the caster's ramp, the preset's shares, the shot's tag), in the order it
## draws them, a shot's end plays its cue (`expire`, a `motes` part with a `share`; S6), and `step`
## runs once a frame. The
## spectacle says what: which kinds (a spell's, from its cards: `card_kinds.gd`; S2), in which
## colours, where they settle. Nothing here changes a fight.
##
## A new drawn-only system goes here the same way: made in `_ready`, its setting through its own
## event, its cue parts in `cue_parts`.

const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const MarksScript := preload("res://gameplay/feel/marks.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const CueContextScript := preload("res://gameplay/feel/cue_context.gd")
## A cue's `motes` part as typed fields (`motes_part.gd`).
const MotesPart := preload("res://gameplay/feel/motes_part.gd")
const CardKindsScript := preload("res://gameplay/feel/card_kinds.gd")
const BirthsScript := preload("res://gameplay/feel/births.gd")
const StreamsScript := preload("res://gameplay/feel/streams.gd")
const JetsScript := preload("res://gameplay/feel/jets.gd")
const HitSharesScript := preload("res://gameplay/feel/hit_shares.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const BarriersScript := preload("res://gameplay/feel/barriers.gd")
const StillMotesScript := preload("res://gameplay/feel/still_motes.gd")
const SourceMotesScript := preload("res://gameplay/feel/source_motes.gd")
const PlacedMotesScript := preload("res://gameplay/feel/placed_motes.gd")
const CarriedLightsScript := preload("res://gameplay/feel/carried_lights.gd")
const AirMotesScript := preload("res://gameplay/feel/air_motes.gd")
const KindAirScript := preload("res://gameplay/feel/kind_air.gd")
const LightBlockersScript := preload("res://gameplay/feel/light_blockers.gd")
const BodyShadowsScript := preload("res://gameplay/feel/body_shadows.gd")
const StirsScript := preload("res://gameplay/feel/stirs.gd")
const SpotStirsScript := preload("res://gameplay/feel/spot_stirs.gd")
const MistScript := preload("res://gameplay/feel/mist.gd")

## Motes draw under the floor marks, the beams and every flash and telegraph (Feel's SHOWN_BEAM_Z 18
## less 2; docs/milestones/spell-spectacle.md, "Budget and degradation": never over a telegraph).
const MOTE_Z: int = 16
## The floor marks lie on the room's floor (RoomBase.FLOOR_Z) and under every body (0).
const MARK_Z: int = RoomBase.FLOOR_Z + 1
## Spell light is applied just under the motes: above the room and every body (a body layer is
## at most a few), under every spell, flash and telegraph (`spell_light.gd`; P3a).
const LIGHT_Z: int = MOTE_Z - 1
## How long a switched layer ("Shadows", "Fog") takes to ease from none to full or back (s: 15
## frames at 60, docs/STYLE.md "Smooth": at least 3). Dynamic lighting itself comes and goes at once.
const LAYER_FADE_SECONDS: float = 0.25
## The folders of the mote kinds, the mark kinds and the rooms in the registry, and a mark part's
## radius with no size to go by.
const MOTE_FOLDER: StringName = &"motes"
const MARK_FOLDER: StringName = &"marks"
const ROOM_FOLDER: StringName = &"rooms"
const MARK_RADIUS: float = 8.0
## A `light` part's reach (px) when it names none and the cue has no size, how bright it is and
## how long it lasts when it does not say (S6, item 4).
const LIGHT_RADIUS: float = 40.0
const LIGHT_STRENGTH: float = 1.0
const LIGHT_SECONDS: float = 0.3
## The look bit of an exact colour (Feel's EXACT: kind 24 of the shot look).
const EXACT: int = 1 << 23
## A status's motes (`status_motes`): how far they drift (pixels), their kind's speed up times
## this, and how flat the oval round the character they leave from is.
const STATUS_DRIFT: float = 6.0
const STATUS_UP: float = 0.3
const STATUS_FLAT: float = 0.8

## What a shot's spell sheds, from its cards (`card_kinds.gd`; spell-spectacle-2.md, S2).
var cards: CardKindsScript = CardKindsScript.new()
## The services: Feel hands down its own (and again whenever it is given new ones).
var events: EventsScript = null
var registry: RegistryScript = null:
	set(value):
		registry = value
		cards.registry = value
		cards.clear()
		if shadows != null:
			shadows.style_of = _spawn_style_of
		if pool != null:
			pool.set_infusions(InfusionTable.of_registry(value))
## The spell runtime, which a shot's tag gives its spell from (`profile`; null for none: every
## shot's motes by its look). Feel hands it down with the projectile manager (`attach`).
var spells: Object = null:
	set(value):
		spells = value
		cards.spells = value
		cards.clear()
## The projectile manager: the trails' births, the walls the marks keep off, the batches the light
## mirrors (null in some tests: then no light and no trail motes).
var projectiles: ProjectileManagerScript = null
## Feel's switch for the stress benchmark (`Feel.particles_enabled`): off, no motes are thrown.
var particles_enabled: bool = true
## The motes Feel's own drawings give off this frame (a swing's sparks, a beam's splash, their
## cards' particles; S6 item 10): births in the trails' format, given off after the trails' in
## `step`. Feel adds to it only while `motes_on`.
var births: BirthsScript = BirthsScript.new()
## The cues' mote streams under way (`stream` parts: a dash's streaks and cards along its way;
## `streams.gd`), given off into `births` each step. Feel ends one when its carrier ends
## (`end_streams`).
var streams: StreamsScript = StreamsScript.new()
## The cues' mote jets under way (`motes` parts with `for`: a stream poured out of a staff;
## `jets.gd`), each frame's share thrown by the motes player.
var jets: JetsScript = JetsScript.new(_play_motes_part)
## The motes still carriers' shots give off while they stand (`still_motes.gd`: a wall's stream, a
## pool's rising motes), from the rows the projectile manager draws them by.
var still_motes: StillMotesScript = StillMotesScript.new()

## The motes, and how many they hold (`MoteCap.default_cap()` until the setting changes it). They
## always exist (S3: every particle is a mote; the smallest "Particles" stop is a Minimal ring).
## Read only.
var pool: MotesScript = null
var mote_cap: int = MoteCap.default_cap()
## The "Particle amount" setting (`MoteDensity`): every burst's count is times this.
var mote_density: float = MoteDensity.DEFAULT
## While the screen is split, every burst's count is times this too (`set_split`; the split's
## fallback of fewer motes a view, connected biomes CB6; 1: as many).
var split_share: float = 1.0
## The views the light follows while the screen is split (`set_split`; empty: one picture), and
## how much smaller their buffers past the first are.
var _split_views: Array[Viewport] = []
var _split_downscale: int = SpellLightScript.DOWNSCALE
## The "Tailless motes" dev setting (`TaillessMotes`): the motes' rows a frame follow its pool.
var tailless_motes: int = TaillessMotes.DEFAULT
## The floor marks (null with the "Floor marks" setting off), and the setting. Read only.
var marks: MarksScript = null
var floor_marks: bool = FloorMarks.default_on()
## Spell light (null with the setting off, or with no projectile manager), and the setting.
var light: SpellLightScript = null
## The barriers' shells (`barriers.gd`: a Shield's bubble of motes round an actor), stepped with
## the motes and drawn with their material.
var barriers: BarriersScript = null
var spell_light: bool = SpellLightSetting.default_on()
## The atmosphere's settings (docs/milestones/atmosphere.md, "Settings"): the light blocked and the
## bodies' shadows (C), the room's air dust (B) and its mist (F), each only while spell light is on,
## and the world's stirs (E). Read only: set through `set_shadows`, `set_ambient_particles`,
## `set_fog` and `set_environment_interaction`.
var shadows_on: bool = ShadowsSetting.default_on()
var ambient_particles: bool = AmbientParticles.default_on()
var fog: bool = FogSetting.default_on()
var environment_interaction: bool = EnvironmentInteraction.default_on()
## How far the shadows and the mist have come in (0 to 1; `_fade_layers`). Read only.
var _shadows_share: float = 0.0
var _mist_share: float = 0.0
## The room's light where nothing lights it (`RoomBase.ambient`, from `room_entered`; P3b), kept
## for a light made later. Read only.
var ambient: float = 1.0
## The colour of the room's dark (`RoomBase.shade`; atmosphere A), kept with the ambient. Read only.
var shade: Color = Color.WHITE
## The lights the wizards carry at their staff tips (atmosphere A), written each frame while the
## light is on. Read only.
var carried_lights: CarriedLightsScript = CarriedLightsScript.new()
## What blocks the light (atmosphere C): the room's standing walls (from `room_built`) and the props
## that block light, handed to the spell light whenever they change while it is on. Read only.
var blockers: LightBlockersScript = LightBlockersScript.new()
## The bodies' shadows (atmosphere C; null with spell light off, or "Shadows" off once faded out),
## under every body. Read only.
var shadows: BodyShadowsScript = null

## The world's stirs (atmosphere E): the shots' wake and the blasts' push, worked out once a frame
## (`step_stirs`) for what takes notice of them: the room's lights (`spot_stirs`), the ground cover
## (Feel hands them to it) and the stirred motes (handed to the pool's material). Read only.
var stirs: StirsScript = StirsScript.new()
## The room's lights' duck and lean (atmosphere E), stepped while spell light is on. Read only.
var spot_stirs: SpotStirsScript = SpotStirsScript.new()

## The room's low floor mist (atmosphere F; null with spell light off, or "Fog" off once faded out),
## over the floor, the marks and the bodies' shadows and under every body. Read only.
var mist: MistScript = null

## The room's mist (`RoomBase.mist`, from `use_room`), the room laid's size, walls and holes (from
## `room_built`, read only when it names a mist), and the bodies' feet Feel hands over each frame
## (`hand_bodies`: the ground cover's), for a mist made later.
var _mist_data: RoomMist = null
var _room_size: Vector2 = Vector2.ZERO
var _room_walls: Array[Rect2] = []
var _room_holes: Array[Rect2] = []
var _feet: PackedVector2Array = PackedVector2Array()
var _feet_count: int = 0
## The pool's material the stirs were last handed to, and their `version` then.
var _stirred_material: ShaderMaterial = null
var _stirred_version: int = -1
## No owners for a light's rows (the room's spots: nobody carries them).
var _no_owners: PackedInt32Array = PackedInt32Array()
## The ramp table the motes and the floor marks share: a surface's colours and a body's art, one
## row each, so a mote and the mark it leaves read the same colours.
var _ramp_table: RampTableScript = RampTableScript.new()
## What the world's things give off as their art (`source_motes.gd`, `MoteSource`: the hub's island
## edge, a prop's embers and glimmers; props W7), and the standing motes of its masks.
var source_motes: SourceMotesScript = SourceMotesScript.new(_ramp_table)
## What drifts in the room's air (`air_motes.gd`, `RoomBase.air`; atmosphere B), given off while
## motes are thrown, spell light is on (its dust is lit only: with no light it would be unseen) and
## "Ambient particles" is on.
var air: AirMotesScript = AirMotesScript.new(_ramp_table)
## What drifts in each room kind's air, over its own rooms alone (`kind_air.gd`, `RoomKind.air_motes`;
## connected biomes CB12b), given off as the room's air is, laid from the grid first each frame (Feel
## hands it its room hearing, `kind_air.pieces`).
var kind_air: KindAirScript = KindAirScript.new(_ramp_table)
var _standing: PlacedMotesScript = null
## The room's surface colours (`RoomBase.surface_colors`, from `room_entered`; empty for none),
## and their source in the ramp table (-1 for none).
var _surface_colors: PackedColorArray = PackedColorArray()
var _surface_source: int = -1
## The mote kinds the room's walls shed (`RoomBase.surface_kinds`, empty: every surface kind), and
## their indices in the pool (`_take_surface_kinds`).
var _surface_ids: Array[StringName] = []
var _surface_kinds: PackedInt32Array = PackedInt32Array()
## The colours of each body art read so far (texture -> colours), and the pixels of each frame of
## one ([texture, frame rect] -> PackedVector2Array; `break_body`).
var _art_colors: Dictionary = {}
var _art_pixels: Dictionary = {}
## The art and the place of the last body broken (`broken_from`, `broken_at`; for tests).
var _broken_from: Texture2D = null
var _broken_at: Vector2 = Vector2.INF
## The room the marks were last fitted to (`room_entered`), to fit a layer made later.
var _mark_room: StringName = &""
## The walls of every piece of the world built so far (a biome's pieces, each at its place; a row
## run's one room): what the light is blocked by (`_on_room_built`).
var _world_walls: Array[Rect2] = []
## Feel's clock at the last step.
var _clock: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## A hit framed by Feel (`begin_hit` to `end_hit`; false: none), and whether it sprays: every
## write of the hits' class inside it follows that one roll, so a hit sprays whole or not at all.
var _hit_held: bool = false
var _hit_on: bool = false


func _ready() -> void:
	ShaderWarmupScript.want(MotesScript.SHADER, ShaderWarmupScript.BATCH)
	ShaderWarmupScript.want(SpellLightScript.LIGHT_SHADER, ShaderWarmupScript.BATCH)
	ShaderWarmupScript.want(SpellLightScript.APPLY_SHADER, ShaderWarmupScript.RECT)
	ShaderWarmupScript.want(SpellLightScript.BEAM_SHADER, ShaderWarmupScript.MESH)
	ShaderWarmupScript.want(BodyShadowsScript.SHADER, ShaderWarmupScript.BATCH)
	ShaderWarmupScript.want(MistScript.SHADER, ShaderWarmupScript.RECT)
	_make_motes(mote_cap)
	barriers = BarriersScript.new(MOTE_Z)
	barriers.name = "Barriers"
	add_child(barriers)
	_standing = PlacedMotesScript.new(MOTE_Z, "StandingMotes")
	add_child(_standing)
	source_motes.watch(get_tree())
	ShaderWarmupScript.want(MarksScript.SHADER, ShaderWarmupScript.BATCH)
	set_floor_marks(floor_marks)
	if events == null:
		return
	events.mote_cap_changed.connect(set_mote_cap)
	events.mote_density_changed.connect(set_mote_density)
	events.tailless_motes_changed.connect(set_tailless_motes)
	events.spell_light_changed.connect(set_spell_light)
	events.shadows_changed.connect(set_shadows)
	events.ambient_particles_changed.connect(set_ambient_particles)
	events.fog_changed.connect(set_fog)
	events.environment_interaction_changed.connect(set_environment_interaction)
	events.room_entered.connect(_on_room_entered)
	events.room_entered.connect(_fit_marks)
	events.room_built.connect(_on_room_built)
	events.floor_marks_changed.connect(set_floor_marks)
	events.projectile_impact.connect(_on_impact)


## The projectile manager and the spell runtime are known (Feel finds them after its children are
## made): spell light can be made now.
func attach(manager: ProjectileManagerScript, runtime: Object = null) -> void:
	if projectiles != null and projectiles != manager and projectiles.still_shots_drawn.is_connected(_on_still_shots_drawn):
		projectiles.still_shots_drawn.disconnect(_on_still_shots_drawn)
		projectiles.batches_grown.disconnect(_on_batches_grown)
	projectiles = manager
	spells = runtime
	_make_light(spell_light)
	still_motes.attach(manager, runtime as SpellRuntime)
	if manager != null and not manager.still_shots_drawn.is_connected(_on_still_shots_drawn):
		manager.still_shots_drawn.connect(_on_still_shots_drawn)
		manager.batches_grown.connect(_on_batches_grown)


## A shot or a beam struck something: on a wall (no target), a card's still shots there part their
## streams for a moment (`still_motes.gd`, the wall's stream).
func _on_impact(_caster: int, target: Node, position: Vector2, _direction: Vector2) -> void:
	if target == null:
		still_motes.struck(position, projectiles.sim_time if projectiles != null else 0.0)


## A watched card body's still shots were drawn: they give off their motes (`still_motes.gd`).
func _on_still_shots_drawn(view: StillShotView) -> void:
	still_motes.give_off(view, pool if motes_on() else null)


## The manager numbered a card body: watch the still cards' bodies again (a body keeps its number).
func _on_batches_grown(_count: int) -> void:
	still_motes.attach(projectiles, spells as SpellRuntime)


## Once a frame, at Feel's clock `now`, before anything reads them: the world's stirs (atmosphere E)
## stepped with the shots' births the projectile manager drew last and the view `view` (the
## camera's picture; empty: the viewport's).
func step_stirs(now: float, view: Rect2 = Rect2()) -> void:
	var births: PackedFloat32Array = projectiles.spark_births if projectiles != null else PackedFloat32Array()
	var count: int = projectiles.spark_birth_count if projectiles != null else 0
	stirs.step(now, births, count, view if view.has_area() else view_rect())


## A blast at `at` of `radius` px at Feel's clock `now` (an explosion's part): the world's stirs push
## out from it (atmosphere E).
func blast(at: Vector2, radius: float, now: float) -> void:
	stirs.blast(at, radius, now)


## Once a frame, at Feel's clock `now`: the trails' particles thrown, the streams', the world's mote sources' and Feel's own
## drawings' given off, the barriers' shells drawn where their actors are (`table`, the actor
## table), then the motes and the marks stepped.
func step(now: float, table: ActorsScript = null) -> void:
	var delta: float = clampf(now - _clock, 0.0, 0.25)
	_clock = now
	_fade_layers(delta)
	cards.new_frame()
	_trail_motes()
	streams.step(now, projectiles, births, motes_on())
	# A jet throws through the motes player, so it pours only while motes are thrown.
	if motes_on():
		jets.step(now)
	else:
		jets.clear()
	_drawn_motes()
	var view: Rect2 = view_rect()
	source_motes.give_off(now, pool if motes_on() else null, view, _standing)
	var air_pool: MotesScript = pool if motes_on() and light != null and ambient_particles else null
	air.give_off(now, air_pool, view, projectiles.bounds() if projectiles != null else Rect2())
	kind_air.lay(projectiles.grid() if projectiles != null else null)
	kind_air.give_off(now, air_pool, view)
	if barriers != null:
		barriers.step(now, pool if motes_on() else null, table, projectiles)
	if pool != null:
		var drawn: ShaderMaterial = pool.draw_material()
		if drawn != _stirred_material or stirs.version != _stirred_version:
			_stirred_material = drawn
			_stirred_version = stirs.version
			stirs.hand_to(drawn)
		pool.step(now)
	if marks != null:
		marks.step(now)
	if light != null:
		light.step_cues(now)
		carried_lights.step(table, now)
		light.light_carried(carried_lights.rows, carried_lights.count)
		# With "Shadows" off the light is handed no blockers (`set_shadows`) and none are read.
		if shadows != null and blockers.step(table, now):
			light.set_blockers(blockers.boxes, blockers.bodies, blockers.count)
		spot_stirs.step(light, stirs, now)
	if shadows != null:
		shadows.begin_lights()
		shadows.add_lights(light.spot_rows(), light.spot_count(), SpellLightScript.SPOT_ROW_STRENGTH, _no_owners)
		shadows.add_lights(carried_lights.rows, carried_lights.count, SpellLightScript.SPOT_ROW_STRENGTH, carried_lights.owners)
		shadows.step(table, now, view, blockers)
	if mist != null:
		mist.step(now, _feet, _feet_count, stirs.version, stirs.hand_to)
	_free_faded()


## The bodies' feet that part the mist this frame (atmosphere F): the first `count` of `feet` (world
## px; Feel hands the ground cover's, `Cover.bodies`, the bodies nearest the camera's middle). Copied
## into the spectacle's own buffer (grown when more come, never shrunk), so whoever handed them may
## write theirs again before the next `step` reads them.
func hand_bodies(feet: PackedVector2Array, count: int) -> void:
	_feet_count = clampi(count, 0, feet.size())
	if _feet.size() < _feet_count:
		_feet.resize(_feet_count)
	for k in _feet_count:
		_feet[k] = feet[k]


## The barrier on `actor` changed (combat's `barrier_changed`; `ramp` the actor's): its shell, in
## the colours of the spell with `tag` (its tint and looks; a plain Shield's are its caster's).
func barrier_changed(actor: int, charges: int, seconds: float, tag: int, way: Vector2, radius: float, ramp: int) -> void:
	if barriers == null:
		return
	var core: Color = Color.WHITE
	var look: int = 0
	if spells != null and tag != 0 and spells.has_method(&"profile"):
		var spell: Variant = spells.call(&"profile", tag)
		if spell is CompiledSpell:
			core = (spell as CompiledSpell).tint
			look = (spell as CompiledSpell).look
	barriers.change(actor, charges, seconds, way, radius, MotesScript.spell_source(ramp, look), core, pool if motes_on() else null)


## A shot's shield blocked another (`shot_blocked` naming the shielded `shot`) at `at`: its shell
## loses that charge's share.
func shot_blocked(shot: int, at: Vector2) -> void:
	if barriers != null:
		barriers.shot_blocked(shot, at, projectiles, pool if motes_on() else null)


## The cue parts the spectacle plays (`CueBase.PART_TYPES`), for Feel's table: part type -> a
## Callable taking the part and the cue's `CueContext`.
func cue_parts() -> Dictionary:
	return {&"motes": [play_motes_part, prepare_motes_part, motes_need_spray], &"mark": [play_mark_part], &"light": [play_light_part], &"stream": [play_stream_part, prepare_stream_part]}


## Whether the motes part `part` shows only for a hit whose motes spray (an `often` part, a hit's
## sparks: `play_motes_part`), for Feel's `add_cue_part`.
static func motes_need_spray(part: MotesPart) -> bool:
	return part.often


## Whether the hit framed now (`begin_hit`, `hold_hit`) is one whose motes do not spray: its `often`
## parts show nothing. False with no hit framed (a part then rolls a hit of its own).
func hit_unsprayed() -> bool:
	return _hit_held and not _hit_on


# --- Where motes come from (Feel calls these, in the order it draws) ------------------------

## Whether motes are thrown now: there is a pool and particles are on.
func motes_on() -> bool:
	return pool != null and particles_enabled


## The group a hit of the actor `caster` with the tag `tag` is shared in (`hit_shares.gd`): the
## spell's caster's staff (the projectile manager's `group_of`), the caster's first staff for a hit
## of no spell, OTHER for a hit of no one's.
static func hit_group(caster: int, tag: int) -> int:
	if tag >= SpellTag.FLAG and tag < SpellTag.LIMIT:
		# `group_of(SpellTag.caster_of(tag), tag)` written out: hundreds of hits a frame ask it.
		return ((tag >> SpellTag.CASTER_SHIFT) & SpellTag.CASTER_MASK) * ProjectileManagerScript.GROUP_STAFFS + ((tag >> SpellTag.STAFF_SHIFT) & 3)
	if caster >= 0 and caster < ActorsScript.ACTORS:
		return ProjectileManagerScript.group_of(caster, tag)
	return HitSharesScript.OTHER


## A hit of `caster`'s shot tagged `tag` begins (Feel frames a shot's impact with this and
## `end_hit`): it rolls its staff's share once (`Motes.open_hit`), and every hit write until
## `end_hit` follows it. Returns whether it sprays (Feel keeps it for the hit's damage, `hold_hit`).
func begin_hit(caster: int, tag: int) -> bool:
	if _hit_held:
		end_hit()
	_hit_held = true
	_hit_on = pool != null and particles_enabled and pool.open_hit(hit_group(caster, tag))
	return _hit_on


## More of a hit already rolled (`begin_hit` returned `shown`): its body's spray, played by the
## damage that follows its impact, until `end_hit`. Its rows are the hit's.
func hold_hit(caster: int, tag: int, shown: bool) -> void:
	if _hit_held:
		end_hit()
	_hit_held = true
	_hit_on = shown and pool != null and particles_enabled
	if _hit_on:
		pool.hold_hit(hit_group(caster, tag))


## The hit framed by `begin_hit` or `hold_hit` is done.
func end_hit() -> void:
	if not _hit_held:
		return
	_hit_held = false
	if _hit_on:
		_hit_on = false
		pool.close_hit()


## A write of the hits' class (a shed, an `often` part, a status's motes) writes by the framing
## hit's roll (`_hit_on` while `_hit_held`), else by a roll of its own, of `caster`'s spell tagged
## `tag`, closed by `pool.close_hit` after its writes (written out at each: hundreds a frame).
func _open_hit(caster: int, tag: int) -> bool:
	return pool.open_hit(hit_group(caster, tag))


## A shot (of the tag `tag`) hit a body at `at`: its cards' motes (`look`, its `core` colour, in
## `ramp`) back along `away`, `share` of their count, if its hit sprays (`begin_hit`).
func shed_hit(at: Vector2, away: Vector2, core: Color, ramp: int, look: int, share: float, tag: int = 0) -> void:
	if pool == null or not particles_enabled or not (_hit_on if _hit_held else _open_hit(ActorsScript.NONE, tag)):
		return
	pool.shed_kinds(cards.motes_of(tag, look), at, away, core, ramp, look, share)
	if not _hit_held:
		pool.close_hit()


## A shot of an actor of `ramp` ended on a wall at `at`: its cards' motes in its own ramp (the
## projectile manager's `impact_look`, `impact_core` and `impact_tag` while the impact is sent) and
## the wall's surface motes (the room's, `surface_kinds`) in the room's colours, thrown along
## `away` (back off the wall).
func shed_on_wall(ramp: int, at: Vector2, away: Vector2) -> void:
	if pool == null or not particles_enabled:
		return
	var look: int = projectiles.impact_look if projectiles != null else 0
	var core: Color = projectiles.impact_core if projectiles != null else Color.WHITE
	var tag: int = projectiles.impact_tag if projectiles != null else 0
	if not (_hit_on if _hit_held else _open_hit(ActorsScript.NONE, tag)):
		return
	pool.shed_kinds(cards.motes_of(tag, look), at, away, core, ramp, look)
	if _surface_source >= 0:
		for k in _surface_kinds:
			pool.throw(k, at, away, _surface_source, Color.WHITE)
	if not _hit_held:
		pool.close_hit()


## The mote kinds the room's walls shed: its `surface_kinds`, or every surface kind (read it,
## never change it).
func surface_kinds() -> PackedInt32Array:
	return _surface_kinds


## A body breaking into motes (S3: a death, in place of the white-hot copy that fell apart pixel by
## pixel): about `share` of the pixels of the art `sprite` shows (times the area of `to_world`'s
## scale, at most `most`), each a mote of the surface kind `kind` (a body is a surface that broke)
## in its art's colours, from where that pixel was (`to_world`: the sprite's world transform, at its
## rest scale), falling to the body's feet, flung out from its middle at `speed` (px/s, slowest and
## fastest) and `up`.
func break_body(sprite: Sprite2D, to_world: Transform2D, kind: StringName, share: float, most: int, speed: Vector2, up: Vector2) -> void:
	if sprite == null or sprite.texture == null:
		return
	_broken_from = sprite.texture
	_broken_at = to_world.origin
	if pool == null or not particles_enabled or share <= 0.0:
		return
	var source: int = body_source(sprite)
	var k: int = pool.kind_index(kind)
	if source < 0 or k < 0:
		return
	var rect: Rect2i = ArtPixels.frame_of(sprite)
	var key: Array = [sprite.texture, rect]
	var pixels: Variant = _art_pixels.get(key)
	if pixels == null:
		pixels = ArtPixels.pixels_of(sprite.texture, rect)
		_art_pixels[key] = pixels
	var art: PackedVector2Array = pixels as PackedVector2Array
	if art.is_empty():
		return
	var scale: Vector2 = to_world.get_scale().abs()
	var want: int = clampi(roundi(float(art.size()) * share * scale.x * scale.y), 1, most)
	var step: float = float(art.size()) / float(want)
	var size: Vector2 = Vector2(rect.size)
	var corner: Vector2 = sprite.offset - (size * 0.5 if sprite.centered else Vector2.ZERO)
	var points := PackedVector2Array()
	points.resize(want)
	var feet: float = -INF
	for i in want:
		var p: Vector2 = art[mini(floori((float(i) + 0.5) * step), art.size() - 1)]
		if sprite.flip_h:
			p.x = size.x - 1.0 - p.x
		var world: Vector2 = to_world * (corner + p + Vector2(0.5, 0.5))
		points[i] = world
		feet = maxf(feet, world.y)
	pool.crumble(k, points, feet, to_world * (corner + size * 0.5), speed, 360.0, up, source, Color.WHITE)


## The art the last body broken was drawn with, and where its sprite was (for tests).
func broken_from() -> Texture2D:
	return _broken_from


func broken_at() -> Vector2:
	return _broken_at


## The ramp table's source for the colours of a body's art (the `sprite` it shows, read once per
## texture; `ArtPixels.colours_of`), -1 when it has none (the room's walls' then), or with
## neither motes nor floor marks to show it.
func body_source(sprite: Sprite2D) -> int:
	if pool == null and marks == null:
		return -1
	if sprite == null or sprite.texture == null:
		return -1
	var colours: Variant = _art_colors.get(sprite.texture)
	if colours == null:
		colours = ArtPixels.colours_of(sprite.texture, ArtPixels.frame_of(sprite))
		_art_colors[sprite.texture] = colours
	return _ramp_table.source(colours as PackedColorArray)


## The shots' trail particles as motes (spell spectacle P1d): the projectile manager hands them out
## while there are motes (`spark_motes`), and they are thrown before the motes step. With
## `particles_enabled` off (the stress benchmark's "no particles") the trails stay without their
## particle slots and none are thrown: no trail particles at all, not the shader's instead.
func _trail_motes() -> void:
	if projectiles == null:
		return
	var on: bool = pool != null
	if projectiles.spark_motes != on:
		projectiles.spark_motes = on
	if not on:
		return
	# The tails laid as motes (S5 step 4) take rows of their own: the most the manager lays a frame,
	# kept from the frame's hits and moments (`tail_rows`) and handed to the births here, so a lone
	# Fireball's tail is never cut by a Storm's hits.
	var tails: int = projectiles.tail_births_cap if projectiles.tail_births_on else 0
	var rows: int = TaillessMotes.frame_rows_of(tailless_motes) + tails
	if pool.frame_rows != rows:
		pool.frame_rows = rows
	pool.tail_rows = tails
	pool.open_tail_rows()
	if particles_enabled and projectiles.spark_birth_count > 0:
		pool.give_off(projectiles.spark_births, projectiles.spark_birth_count)


## What Feel's own drawings gave off this frame (`births`), thrown like the trails' and forgotten.
func _drawn_motes() -> void:
	if births.count > 0 and motes_on():
		pool.give_off(births.rows, births.count)
	births.clear()


## A status's motes (spell spectacle 2, S6 item 11): `count` motes of the element card `card`'s
## kinds (those that name it, else those of its look layer `layer`), each from a random point of
## an oval `reach` pixels round `at` (a character), drifting out STATUS_DRIFT pixels and a little
## up (STATUS_UP of its kind's own), cooling from the exact colour `core`. One of many a frame: a
## hit of the statuses' own group (`hit_shares.gd`), so it leaves the moments' rows alone and
## never takes a staff's share.
func status_motes(card: StringName, layer: int, at: Vector2, reach: float, core: Color, count: int) -> void:
	if count <= 0 or not motes_on() or not at.is_finite():
		return
	var found: PackedInt32Array = pool.kinds_of_card(card)
	if found.is_empty():
		found = pool.kinds_of_layer(layer)
	if found.is_empty() or not (_hit_on if _hit_held else pool.open_hit(HitSharesScript.STATUSES)):
		return
	var source: int = MotesScript.spell_source(0, MotesScript.LOOK_EXACT)
	for n in count:
		var k: int = found[0] if found.size() == 1 else found[_rng.randi_range(0, found.size() - 1)]
		var angle: float = _rng.randf() * TAU
		var out: Vector2 = Vector2(cos(angle), sin(angle))
		var from: Vector2 = at + Vector2(out.x, out.y * STATUS_FLAT) * reach * (0.5 + 0.5 * _rng.randf())
		pool.throw_part(k, from, out, source, core, 1, STATUS_DRIFT, -1.0, STATUS_UP, false, true)
	if not _hit_held:
		pool.close_hit()


# --- Cue parts -------------------------------------------------------------------------------

## A cue's `motes` part (`CueBase`) played with `cue`: the kinds it names thrown as it says, the
## cue's size times its `reach` out (or its `radius`), in its exact `color` or the cue's own, else in
## the cue's ramp with its tint and the cards of its look (in the caster's ramp alone when `bare`);
## its count and reach times the cue's power. One of many a frame (`often`, a hit's sparks, S6 2; and
## any with a `share`, a shot's end) is a hit (`hit_shares.gd`: its cue's caster's staff's share, or
## the hit Feel framed with `begin_hit`), skipped before its kinds are looked up when it does not
## spray; one with a `share` throws each kind its own count times the share (and the power), split
## between the kinds, as they shed.
func play_motes_part(part: MotesPart, cue: CueContextScript) -> void:
	if pool == null or not particles_enabled:
		return
	if part.lasts > 0.0:
		# A jet (`for`): its count poured over its seconds (`jets.gd`).
		jets.start(part, cue, _clock)
		return
	if not part.often:
		_play_motes_part(part, cue)
		return
	if not (_hit_on if _hit_held else _open_hit(cue.caster, cue.tag)):
		return
	_play_motes_part(part, cue)
	if not _hit_held:
		pool.close_hit()


func _play_motes_part(part: MotesPart, cue: CueContextScript) -> void:
	var way: Vector2 = cue.aim
	var turn: StringName = part.way
	if turn != &"aim":
		if turn == &"back":
			way = -way
		elif turn == &"right":
			way = Vector2.RIGHT
		elif turn == &"up":
			way = Vector2.UP
	var reach: float = part.radius
	if part.reach >= 0.0 and cue.size > 0.0:
		reach = cue.size * part.reach
	reach *= cue.power
	# In an exact colour (the part's, else the cue's own), or in the cue's ramp, tint and cards.
	# A bare part keeps to the caster's ramp even in a cue with a colour of its own, as a bare flash.
	var colour: Color = part.color if part.color.a > 0.0 else (Color(0.0, 0.0, 0.0, 0.0) if part.bare else cue.color)
	var exact: bool = colour.a > 0.0
	var spell: int = MotesScript.spell_source(cue.ramp, MotesScript.LOOK_EXACT if exact else cue.look)
	var core: Color = colour if exact else cue.tint
	# The cards whose infusions colour the part's spell-coloured motes (none in an exact colour, a
	# body's own or the bare ramp).
	var cards_look: int = 0 if exact or part.body or part.bare else cue.look
	if part.body and not exact:
		# The body's own colour (a death puff's sparks), in no one's ramp and without the cards.
		spell = MotesScript.spell_source(0, 0)
		core = cue.body if cue.body.a > 0.0 else Color.WHITE
	elif part.bare and not exact:
		# The caster's ramp without the cards (a cast's sparks, in the seat's colours).
		spell = MotesScript.spell_source(cue.ramp, 0)
		core = Color.WHITE
	var surface: int = cue.surface if cue.surface >= 0 else _surface_source
	var at: Vector2 = cue.at
	if part.place >= 0.0:
		# Where on the cue's line (`along`, S6 item 9).
		at += cue.aim * cue.size * part.place
	if part.below != 0.0:
		at.y += part.below
	# Thrown from all along the cue's line (`line`: a staff coming apart), else from its point.
	var line: Vector2 = cue.aim * cue.size if part.line else Vector2.ZERO
	var life: float = part.life
	var named: StringName = part.named
	if named != &"spell" and named != &"surface":
		# One kind by its id: looked up once a pool (the pool is made again when its cap changes),
		# with whether it is a surface kind and its own count.
		if part.pool_seen != pool:
			part.pool_seen = pool
			part.kind_at = pool.kind_index(named)
			if part.kind_at >= 0:
				part.kind_surface = pool.kinds()[part.kind_at].surface
				part.kind_count = pool.kinds()[part.kind_at].count
		if part.kind_at < 0:
			return
		var alone: bool = part.colours == &"surface" or (part.kind_surface and part.colours != &"spell" and not exact)
		var each: int
		if part.share >= 0.0:
			each = maxi(roundi(float(part.kind_count) * part.share * cue.count_times()), 1)
			pool.throw_part(part.kind_at, at, way, surface if alone else spell, Color.WHITE if alone else core, each, 0.0, part.spread, part.up, false, true, line, life, 0 if alone else cards_look)
			return
		each = -1 if part.count < 0 and cue.count_times() == 1.0 else maxi(roundi(float(part.kind_count if part.count < 0 else part.count) * cue.count_times()), 1)
		if part.gather > 0.0 and cue.size > 0.0:
			_gather(part, cue, at, surface if alone else spell, Color.WHITE if alone else core, part.kind_count if each < 0 else each, life, 0 if alone else cards_look)
			return
		pool.throw_part(part.kind_at, at, way, surface if alone else spell, Color.WHITE if alone else core, each, reach, part.spread, part.up, part.ring, part.often, line, life, 0 if alone else cards_look)
		return
	var kinds: PackedInt32Array = cards.motes_of(cue.tag, cue.look) if named == &"spell" else _surface_kinds
	var count: int = part.count
	var shed: bool = part.share >= 0.0
	var share: float = part.share * cue.count_times() / float(maxi(kinds.size(), 1))
	# What a surface sheds (the walls', or a room's own kinds) cools through the surface's colours,
	# as does a part whose `colours` say so; one whose `colours` are the spell's, through its ramp.
	var of_surface: bool = named == &"surface" or part.colours == &"surface"
	# A jet's frame share (`for`, jets.gd) is split exactly, the remainder turning round the kinds
	# from frame to frame, so a jet pours its count in all and no kind gets one it is not due.
	var jet: bool = part.lasts > 0.0 and count >= 0
	var n_kinds: int = maxi(kinds.size(), 1)
	var at_kind: int = 0
	for k in kinds:
		# A card's own surface kind (grit) cools through the walls' colours, unless in an exact one.
		var walls: bool = of_surface or (pool.kinds()[k].surface and part.colours != &"spell" and not exact)
		var source: int = surface if walls else spell
		if shed:
			pool.throw_part(k, at, way, source, Color.WHITE if walls else core, maxi(roundi(float(pool.kinds()[k].count) * share), 1), 0.0, part.spread, part.up, false, true, line, life, 0 if walls else cards_look)
			continue
		# How many of this kind: its share of the part's count (else its own count), times the power.
		var each_share: float = float(pool.kinds()[k].count) if count < 0 else float(count) / float(kinds.size())
		var each: int = -1 if count < 0 and cue.count_times() == 1.0 else maxi(roundi(each_share * cue.count_times()), 1)
		if jet:
			each = jet_share(count, n_kinds, part.turn, at_kind)
			at_kind += 1
			if each == 0:
				continue
		pool.throw_part(k, at, way, source, Color.WHITE if walls else core, each, reach, part.spread, part.up, part.ring, part.often, line, life, 0 if walls else cards_look)
	if jet:
		part.turn = posmod(part.turn + count, n_kinds)


## A `gather` part's `count` motes (`CueBase`): each from a point of the cloud `part.gather` wide
## round `at`, aimed at the end of the cue's line and thrown exactly as far (times its `reach`),
## so they come to a point there.
func _gather(part: MotesPart, cue: CueContextScript, at: Vector2, source: int, core: Color, count: int, life: float, look: int) -> void:
	var end: Vector2 = cue.at + cue.aim * cue.size
	var times: float = part.reach if part.reach >= 0.0 else 1.0
	for n in count:
		var from: Vector2 = at + Vector2.from_angle(_rng.randf() * TAU) * part.gather * sqrt(_rng.randf())
		var to_end: Vector2 = end - from
		if to_end.length_squared() < 1.0:
			continue
		pool.throw_part(part.kind_at, from, to_end, source, core, 1, to_end.length() * times * cue.power, 0.0, part.up, false, false, Vector2.ZERO, life, look)


## A jet's frame share of `count` for the kind `at` of `kinds` (jets.gd): an even split, the
## remainder going to the kinds from `turn` on, so turning `turn` on by the count each frame gives
## every kind its share in all and the shares add up to `count`.
static func jet_share(count: int, kinds: int, turn: int, at: int) -> int:
	return count / kinds + (1 if posmod(at - turn, kinds) < count % kinds else 0)


## A cue's `motes` part read into its typed fields once (`Feel.add_cue_part`'s `prepare`, S6 2: a
## hit's sparks are played hundreds of times a second).
func prepare_motes_part(part: Dictionary) -> MotesPart:
	var made := MotesPart.new()
	made.named = StringName(part.get("kind", "spell"))
	made.colours = StringName(part.get("colours", ""))
	made.count = int(part.get("count", -1))
	made.reach = float(part["reach"]) if part.has("reach") else -1.0
	made.radius = float(part.get("radius", 0.0))
	made.spread = float(part.get("spread", -1.0))
	made.up = float(part.get("up", 1.0))
	made.ring = bool(part.get("ring", false))
	made.share = float(part.get("share", -1.0))
	made.often = bool(part.get("often", false)) or made.share >= 0.0
	made.body = bool(part.get("body", false))
	made.bare = bool(part.get("bare", false))
	made.way = StringName(part.get("way", "aim"))
	made.below = float(part.get("below", 0.0))
	made.color = part["color"] as Color if part.has("color") else Color(0.0, 0.0, 0.0, 0.0)
	made.place = clampf(float(part["along"]), 0.0, 1.0) if part.has("along") else -1.0
	made.line = bool(part.get("line", false))
	made.life = float(part.get("life", 1.0))
	made.lasts = float(part.get("for", 0.0))
	made.gather = float(part.get("gather", 0.0))
	return made


## A cue's `stream` part (`CueBase`) played with `cue`: a stream of motes from its caster starts
## (`streams.gd`), going the cue's way until it moves, in the cue's ramp with its tint and cards, of
## its spell (its tag). Nothing with no projectile manager (no anchors to follow).
func play_stream_part(part: StreamsScript.Part, cue: CueContextScript) -> void:
	if projectiles == null or cue.caster < 0:
		return
	streams.start(part, cue.caster, cue.tag, cue.ramp, cue.look, cue.tint, projectiles.get_anchor(cue.caster), cue.aim, _clock)


## A cue's `stream` part read into its typed fields once (`Feel.add_cue_part`'s `prepare`).
func prepare_stream_part(part: Dictionary) -> StreamsScript.Part:
	return StreamsScript.prepare(part)


## The carrier of the spell tagged `tag` that `caster` showed has ended (`carrier_ended`): its
## streams end.
func end_streams(caster: int, tag: int) -> void:
	streams.end(caster, tag)


## Stamp a cue's mark part (`CueBase`, "part": "mark") played with `cue`: its mark, or with
## `cards` the marks of the cards of the cue's look when they have any; the cue's size x its
## `reach` pixels round (or its `radius`), turned at random or along the cue's way, in the colours
## of a spell of its ramp with its tint and of what broke (a dying body's art, else the walls).
func play_mark_part(part: Dictionary, cue: CueContextScript) -> void:
	if marks == null:
		return
	var radius: float = float(part.get("radius", MARK_RADIUS))
	if part.has("reach") and cue.size > 0.0:
		radius = cue.size * float(part["reach"])
	radius *= cue.power
	var source: int = MotesScript.spell_source(cue.ramp, cue.look)
	var turn: float = cue.aim.angle() if StringName(part.get("rot", "random")) == &"aim" else marks.random_turn()
	var found: PackedInt32Array = cards.marks_of(cue.tag, cue.look) if bool(part.get("cards", false)) else PackedInt32Array()
	if found.is_empty():
		var named: StringName = StringName(part.get("mark", ""))
		if named == &"":
			# Only its cards' marks, and they have none.
			return
		found = PackedInt32Array([marks.kind_index(named)])
	var surface: int = cue.surface if cue.surface >= 0 else _surface_source
	for k in found:
		marks.stamp(k, cue.at, radius, turn, source, cue.tint, surface)


## A cue's `light` part (CueBase; S6, item 4), played with `cue`: the room lit round the cue's point
## while Spell light is on, out to its `radius` pixels (or the cue's size times its `reach`; either
## times the cue's power), `strength` bright, fading over its `seconds`, in its exact `color`,
## plain, in the caster's ramp alone (`bare`), in the cue's own colour, or in the cue's ramp, tint
## and cards: as a flash would be.
func play_light_part(part: Dictionary, cue: CueContextScript) -> void:
	if light == null:
		return
	var reach: float = float(part.get("radius", LIGHT_RADIUS))
	if part.has("reach") and cue.size > 0.0:
		reach = cue.size * float(part["reach"])
	reach *= cue.power
	var strength: float = float(part.get("strength", LIGHT_STRENGTH))
	var seconds: float = float(part.get("seconds", LIGHT_SECONDS))
	var at: Vector2 = cue.point_of(part)
	if part.has("color"):
		light.flash(at, reach, strength, seconds, part["color"] as Color, 0, EXACT, _clock)
	elif bool(part.get("plain", false)):
		light.flash(at, reach, strength, seconds, Color.WHITE, 0, 0, _clock)
	elif bool(part.get("bare", false)):
		light.flash(at, reach, strength, seconds, Color.WHITE, cue.ramp, 0, _clock)
	elif cue.color.a > 0.0:
		light.flash(at, reach, strength, seconds, cue.color, 0, EXACT, _clock)
	else:
		light.flash(at, reach, strength, seconds, cue.tint, cue.ramp, cue.look, _clock)


# --- Settings ----------------------------------------------------------------------------------

## The "Particles" setting: how many motes the ring holds (from `MoteCap`'s Minimal stop to its
## top one; a 0, Off before S3, is Minimal). A new size remakes the ring, ending the motes in the
## air. Returns the number taken.
func set_mote_cap(cap: int) -> int:
	var taken: int = clampi(cap, MoteCap.STOPS[0], MoteCap.STOPS[-1])
	if taken != mote_cap or pool == null:
		_make_motes(taken)
	return mote_cap


## Use `motes` as the pool from now on, in place of the one made for the setting (its cap is the
## setting's now). For the benchmarks, which hand one that times its own calls
## (tests/benchmark/timed_motes.gd); null (the stress benchmark's "no particles") leaves none.
func use_motes(motes: MotesScript) -> void:
	if pool != null:
		pool.queue_free()
		remove_child(pool)
		pool = null
	pool = motes
	mote_cap = motes.cap() if motes != null else 0
	if motes != null:
		pool.name = "Motes"
		pool.density = mote_density * split_share
		pool.frame_rows = TaillessMotes.frame_rows_of(tailless_motes)
		add_child(pool)
		pool.step(_clock)
		pool.settle_into(marks)
		# A spell's motes in each of its infusions' colours (`Motes.set_infusions`).
		pool.set_infusions(InfusionTable.of_registry(registry))
		# Its lit-only kinds read the spell light's buffer (atmosphere B).
		pool.set_light(light.buffer() if light != null else null, SpellLightScript.lit_steps())
		if light != null:
			light.read_by(&"motes", pool.draw_material())
	cards.use_motes(pool)
	if pool != null:
		pool.use_cards(cards if pool.has_card_kinds() else null)
	_take_surface_kinds()
	_surface_source = _ramp_table.source(_surface_colors)


## The colour table the motes and the floor marks share (a pool handed to `use_motes` is made
## with it, so its table sources are the marks').
func ramp_table() -> RampTableScript:
	return _ramp_table


func _make_motes(cap: int) -> void:
	use_motes(MotesScript.new(cap, MOTE_Z, _mote_kinds(), _ramp_table))


## The mote kinds of the registry (content/motes), in id order.
func _mote_kinds() -> Array[MoteKind]:
	var kinds: Array[MoteKind] = []
	if registry != null:
		for found: Resource in registry.get_all(MOTE_FOLDER):
			if found is MoteKind:
				kinds.append(found as MoteKind)
	return kinds


## The "Particle amount" setting: the share of its count every burst of motes throws (snapped by
## `MoteDensity.snap`). Returns the share taken.
func set_mote_density(density: float) -> float:
	mote_density = MoteDensity.snap(density)
	if pool != null:
		pool.density = mote_density * split_share
	return mote_density


## The screen split into `views` (their viewports, in the split screen's order; empty: one
## picture): the light follows each (a buffer a view; `extra_downscale` how much smaller those past
## the first are), and the motes throw `share` of their count (the split's fallbacks; 1 and
## SpellLight.DOWNSCALE: none). Called every drawn frame; nothing changes while it is the same.
func set_split(views: Array[Viewport], share: float = 1.0, extra_downscale: int = SpellLightScript.DOWNSCALE) -> void:
	var next_share: float = clampf(share, 0.0, 1.0) if views.size() > 1 else 1.0
	if next_share != split_share:
		split_share = next_share
		if pool != null:
			pool.density = mote_density * split_share
	_split_views = views
	_split_downscale = extra_downscale
	if light != null:
		light.use_views(views, extra_downscale)


## The "Tailless motes" dev setting: the motes may write `TaillessMotes.frame_rows_of(births)`
## rows a frame, so the bigger births' pool the projectile manager takes with the tails off is
## drawn. Returns the rows a frame.
func set_tailless_motes(births: int) -> int:
	tailless_motes = TaillessMotes.snap(births)
	var rows: int = TaillessMotes.frame_rows_of(tailless_motes)
	if pool != null:
		pool.frame_rows = rows
	return rows


## The "Floor marks" setting: on makes the mark layer (fitted to the room it was last told of),
## off frees it and every mark with it.
func set_floor_marks(on: bool) -> void:
	floor_marks = on
	if on and marks == null:
		var kinds: Array[MarkKind] = []
		if registry != null:
			for found: Resource in registry.get_all(MARK_FOLDER):
				if found is MarkKind:
					kinds.append(found as MarkKind)
		marks = MarksScript.new(MARK_Z, kinds)
		marks.name = "Marks"
		marks.set_ramp_table(_ramp_table.texture())
		add_child(marks)
		_keep_mist_last()
		if _mark_room != &"":
			_fit_marks(_mark_room)
	elif not on and marks != null:
		marks.queue_free()
		remove_child(marks)
		marks = null
	cards.use_marks(marks)
	if pool != null:
		pool.settle_into(marks)


## The "Dynamic lighting" setting (once "Spell light"): on makes the light buffer and its rect, off frees them (no nodes).
## Returns the setting.
func set_spell_light(on: bool) -> bool:
	if on != spell_light or (light == null) == on:
		_make_light(on)
	return spell_light


func _make_light(on: bool) -> void:
	spell_light = on
	if light != null:
		light.release()
		remove_child(light)
		light.queue_free()
		light = null
	# A light made anew starts with its spots at rest.
	spot_stirs = SpotStirsScript.new()
	if on and projectiles != null:
		light = SpellLightScript.new(projectiles, LIGHT_Z)
		light.name = "SpellLight"
		light.set_ambient(ambient, shade)
		add_child(light)
		light.use_views(_split_views, _split_downscale)
		# What blocks it is handed over at the next step while "Shadows" is on (atmosphere C).
		blockers.refresh()
	# The shadows and the mist come and go with it, at once (atmosphere C, F), each by its own
	# setting too.
	_fit_shadows(true)
	_fit_mist(true)
	# The motes' lit-only kinds read the light buffer, or with none are not drawn (atmosphere B).
	if pool != null:
		pool.set_light(light.buffer() if light != null else null, SpellLightScript.lit_steps())
		if light != null:
			light.read_by(&"motes", pool.draw_material())


## The "Shadows" setting (atmosphere C): on, while spell light is on, the light is blocked by the
## room's standing walls and pillars and the bodies cast shadows. A flip eases the layer in or out
## over LAYER_FADE_SECONDS (`_fade_layers`: the boxes' strength and the bodies' casts and shapes by
## whole pixels); faded out, the shadows' batch is freed (a body's own drawn shadow shows again) and
## the light is handed no blockers. With spell light off it only keeps the choice. Returns the
## setting.
func set_shadows(on: bool) -> bool:
	shadows_on = on
	_fit_shadows(false)
	return shadows_on


## The bodies' shadows made while spell light and "Shadows" are on (eased in from none, or at full
## with a light made at once, `at_once`); with the light gone, freed with it. One switched off fades
## out in `_fade_layers` (at once with `at_once`). The light is handed the blockers anew at the next
## step (`refresh`: what crumbled meanwhile is rubble already).
func _fit_shadows(at_once: bool) -> void:
	if shadows != null and (light == null or (at_once and not shadows_on)):
		_free_shadows()
	elif shadows == null and light != null and shadows_on:
		_shadows_share = 1.0 if at_once else 0.0
		blockers.refresh()
		blockers.set_share(_shadows_share)
		shadows = BodyShadowsScript.new(MARK_Z)
		shadows.share = _shadows_share
		shadows.style_of = _spawn_style_of
		add_child(shadows)
		_keep_mist_last()
	elif shadows != null and not shadows_on:
		# Fading out: the bodies with a drawn shadow keep their shape to hand over to it.
		shadows.find_drawn_owners()


func _free_shadows() -> void:
	remove_child(shadows)
	shadows.queue_free()
	shadows = null
	_shadows_share = 0.0
	if light != null:
		light.set_blockers(blockers.boxes, blockers.bodies, 0)


## The "Fog" setting (atmosphere F): on, while spell light is on, the room's mist is drawn. A flip
## eases it in or out over LAYER_FADE_SECONDS (its thickness); faded out, it is freed. Returns the
## setting.
func set_fog(on: bool) -> bool:
	fog = on
	_fit_mist(false)
	return fog


## The mist made while spell light and "Fog" are on (it glows by the light, and lies over the
## shadows; eased in from none, or at full with a light made at once), freed with the light; one
## switched off fades out in `_fade_layers` (at once with `at_once`).
func _fit_mist(at_once: bool) -> void:
	if mist != null and (light == null or (at_once and not fog)):
		_free_mist()
	elif mist == null and light != null and fog:
		_mist_share = 1.0 if at_once else 0.0
		mist = MistScript.new(MARK_Z)
		mist.set_share(_mist_share)
		add_child(mist)
		mist.lay(_room_size, _room_walls, _room_holes)
		mist.use(_mist_data)
		_keep_mist_last()
	if mist != null:
		# The light's buffer, again when the light was made anew under it.
		mist.use_light(light.buffer())
		light.read_by(&"mist", mist.material as ShaderMaterial)


func _free_mist() -> void:
	remove_child(mist)
	mist.queue_free()
	mist = null
	_mist_share = 0.0


## The shadows and the mist eased toward their settings, `delta` seconds on (a whole layer from none
## to full over LAYER_FADE_SECONDS); before the blockers are stepped, so a changed share is handed to
## the light this frame.
func _fade_layers(delta: float) -> void:
	var most: float = delta / LAYER_FADE_SECONDS
	if shadows != null:
		_shadows_share = move_toward(_shadows_share, 1.0 if shadows_on else 0.0, most)
		shadows.share = _shadows_share
		blockers.set_share(_shadows_share)
	if mist != null:
		_mist_share = move_toward(_mist_share, 1.0 if fog else 0.0, most)
		mist.set_share(_mist_share)


## The layers faded out all the way are freed (after the frame's step: the light was handed no
## blockers by it).
func _free_faded() -> void:
	if shadows != null and not shadows_on and _shadows_share <= 0.0:
		_free_shadows()
	if mist != null and not fog and _mist_share <= 0.0:
		_free_mist()


## The "Ambient particles" setting (atmosphere B): whether the room's air gives off its dust (while
## spell light is on; the dust in the air lives out its short life). Returns the setting.
func set_ambient_particles(on: bool) -> bool:
	ambient_particles = on
	return ambient_particles


## The "Environment interaction" setting (atmosphere E): off, the world's stirs read no shot and
## start no blast, so the lights, the cover, the dust and the mist ease back to rest and are then
## handed a still field. Returns the setting.
func set_environment_interaction(on: bool) -> bool:
	environment_interaction = on
	stirs.enabled = on
	return environment_interaction


## Feel's flash rows, just uploaded (the flares', the explosions' and the arcs'; `slots` rows
## each), lit by the spell light while it is on (P3b; `SpellLight.light_flashes`).
func light_flashes(flare_rows: PackedFloat32Array, flares: int, blast_rows: PackedFloat32Array, blasts: int, arc_rows: PackedFloat32Array, arcs: int, slots: int) -> void:
	if light != null:
		light.light_flashes(flare_rows, flares, blast_rows, blasts, arc_rows, arcs, slots)


## Before Feel draws its live beams: none lit until `light_beam` lights one (P3b).
func light_beams_begin() -> void:
	if light != null:
		light.light_beams_begin()


## Live beam `i`'s light along the path Feel just gave its shader (`SpellLight.light_beam`), as
## bright and as far as its card says (`intensity`, `reach`: its `look_light_*`, 1 as any beam).
func light_beam(i: int, path: PackedVector3Array, points: int, player: int, look: int, core: Color, fade: float, intensity: float = 1.0, reach: float = 1.0) -> void:
	if light != null:
		light.light_beam(i, path, points, player, look, core, fade, intensity, reach)


## The part of the world on screen now (empty outside a tree): what the mote sources give off
## near.
func view_rect() -> Rect2:
	var view: Viewport = get_viewport() if is_inside_tree() else null
	if view == null:
		return Rect2()
	# While the screen is split (CB6): the box round what every view shows.
	var split: ScreenViews = ScreenViews.on(view)
	if split != null and split.is_split():
		return split.world_box()
	return view.get_canvas_transform().affine_inverse() * view.get_visible_rect()


# --- The room ------------------------------------------------------------------------------------

## A room was laid out (`room_built`; atmosphere C): its standing walls block the light from now on.
func _on_room_built(room_id: StringName, number: int, layout_root: Node) -> void:
	var walls: Array[Rect2] = RoomPlaces.wall_rects(layout_root)
	var piece := layout_root as Node2D
	# A biome's pieces stand at their places (connected biomes CB3): their walls at them.
	var at: Vector2 = piece.position if piece != null else Vector2.ZERO
	for i in walls.size():
		walls[i].position += at
	if number != EventsScript.FIRST_ROOM:
		# A biome's later piece: its walls join the world's; the mist and the room's look are the
		# first room's.
		_world_walls.append_array(walls)
		blockers.use_walls(_world_walls)
		return
	_world_walls = walls.duplicate()
	blockers.use_walls(walls)
	# The mist's room (atmosphere F), read only when the room names a mist.
	var room: RoomBase = registry.get_resource(ROOM_FOLDER, room_id) as RoomBase if registry != null else null
	if room != null and room.mist != null:
		var places: RoomPlaces = RoomPlaces.read(layout_root)
		lay_mist(places.size, walls, places.holes)
	else:
		lay_mist(Vector2.ZERO, [] as Array[Rect2], [] as Array[Rect2])


## The room the mist lies in (atmosphere F): its size (px, from the origin), walls and holes (world
## px); a zero size: none (`room_built` calls this; tests too).
func lay_mist(size: Vector2, walls: Array[Rect2], holes: Array[Rect2]) -> void:
	_room_size = size
	_room_walls = walls
	_room_holes = holes
	if mist != null:
		mist.lay(size, walls, holes)


## The mist is the last of the children at the marks' z, so it lies over the marks and the shadows.
func _keep_mist_last() -> void:
	if mist != null and mist.get_parent() == self:
		move_child(mist, -1)


## A new room: its colours for its walls' motes (`RoomBase.surface_colors`), its ambient light
## (`RoomBase.ambient`, P3b; and its dark's colour, `RoomBase.shade`) and its air (`RoomBase.air`).
func _on_room_entered(room_id: StringName, number: int) -> void:
	if number != EventsScript.FIRST_ROOM:
		return
	use_room(registry.get_resource(ROOM_FOLDER, room_id) as RoomBase if registry != null else null)
	# The room's world is in the tree by now: its mote sources are read again (each from now).
	source_motes.take(get_tree() if is_inside_tree() else null)


## The room `room` (null for none) is the one played in now: its walls' colours and motes, its
## ambient light and its air (`room_entered` calls this; tests too).
func use_room(room: RoomBase) -> void:
	# A jet poured in the room before ends with it.
	jets.clear()
	_surface_colors = room.surface_colors() if room != null else PackedColorArray()
	_surface_ids = room.surface_kinds if room != null else ([] as Array[StringName])
	_take_surface_kinds()
	ambient = room.ambient if room != null else 1.0
	shade = room.shade if room != null else Color.WHITE
	air.use(room.air if room != null else null)
	_mist_data = room.mist if room != null else null
	if mist != null:
		mist.use(_mist_data)
	# The last room's wake and blasts are not this one's.
	stirs.clear()
	if light != null:
		light.set_ambient(ambient, shade)
	_surface_source = _ramp_table.source(_surface_colors)


## The pool's indices of the room's surface kinds (`RoomBase.surface_kinds`; a kind the pool does not
## have is left out), or every surface kind of the pool when the room names none.
func _take_surface_kinds() -> void:
	_surface_kinds = PackedInt32Array()
	if pool == null:
		return
	if _surface_ids.is_empty():
		_surface_kinds = pool.surface_kinds()
		return
	for id in _surface_ids:
		var k: int = pool.kind_index(id)
		if k >= 0 and not _surface_kinds.has(k):
			_surface_kinds.append(k)


## A new room: the mark layer wiped and fitted to its bounds and walls (the projectile manager's,
## set before `room_entered`) in its floor's colours.
func _fit_marks(room_id: StringName, number: int = EventsScript.FIRST_ROOM) -> void:
	if number != EventsScript.FIRST_ROOM:
		return
	_mark_room = room_id
	if marks == null:
		return
	var room: RoomBase = registry.get_resource(ROOM_FOLDER, room_id) as RoomBase if registry != null else null
	var bounds: Rect2 = projectiles.bounds() if projectiles != null else Rect2()
	# Its holes are masked as its walls are (hub rework HR-H2): no mark is laid over a hole.
	marks.enter(bounds, projectiles.grid().wall_image(true) if projectiles != null else null, ProjectileManagerScript.WALL_CELL)
	marks.set_floor_colors(room.floor_colors() if room != null else PackedColorArray())


## The spawn style of id `id` from the registry (null: none), for the bodies' shadows (`BodyShadows.style_of`).
func _spawn_style_of(id: StringName) -> SpawnStyle:
	return registry.get_resource(SpawnStyle.FOLDER, id) as SpawnStyle if registry != null else null
