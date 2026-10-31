class_name SpellRuntime
extends Node
## The spell runtime (autoload `Spells`): staffs compiled from cards and cast (docs/milestones/
## M2-staffs.md). The reading rules live in `StaffCompiler` (`compile_staff`); this script casts.
##
## Building: `compile_staff(cards, staff)` reads a staff's cards into its cycle (`CompiledStaff`;
## it refuses nothing), `staff_view` gives the builder plain values, and
## `install_staff(actor, staff, compiled)` makes it the build of one of an actor's four staffs:
## a new generation, the shots a full generation ring revoked removed, and the staff's sustained
## (`hold`) carriers switched off.
##
## Casting: `cast_staff(actor, staff, origin, direction, mana)` fires the next cast of the
## staff's cycle and returns the mana spent or `REFUSED`; delays (the staff's own, every
## carrier's cooldown, the recharge after the last cast) are per actor and staff and tick in
## `step` (physics). A cast is a group: its carriers leave along the aim; each carrier's shots are
## a fan (straight), a ring (orbit), still shots or rays; split and nova multiplied them in the
## compiler; homing is set on each shot. Every shot leaves up to its staff's `spread` degrees off
## its line, at random (`_staff_spread`). Cards that landed on the caster (or a payload's origin)
## strike everything there (`_strike_round`); a dash card asks the caster's body to move
## (`caster_move_requested`). A `hold` carrier lives until its staff is cast again or edited.
##
## Payloads: a trigger's payload (a group) is fired by its shot's `projectile_hit` (on hit),
## `projectile_expired` (on expire) or every `trigger_interval` seconds (timer, `_step_live`; the
## first tick after the interval or half the carrier's life, whichever is shorter). It starts at
## the hit point (the shot's place at expiry, a little back from a wall; where the carrier is now
## for a timer: every carrier that lasts has one, `_lc_tag`), flies along the shot's velocity
## (outward from the caster through the shot for an orbit or still shot, along the beam for a
## ray) and cannot hit the target that fired it
## for `SpellLimits.SOURCE_EXCLUSION` seconds (a beam never hits it). A payload is cast by the
## shot that fired it while that shot flies, else by the point (`_caster`): dash, teleport, pull,
## swap and recoil move that shot, orbit, familiar and return circle it. A trigger fires every
## time its event happens, as long as its carrier lives (owner, 2026-10-29: no per-shot count).
## One budget's trigger fires make at most `fire_shots_per_step` shots per `step` (pacing, not a
## limit): a fire past it waits for the next step, oldest first, and none is dropped
## (`fires_waited` counts them). A beam fires an on-expire payload where it ends when its
## life is over, and a timer from its tip while it is on.
##
## Carriers (docs/CARRIERS.md): each form names its `Carrier` (core/spells/carriers/) that this
## script makes and binds (`Carriers.make_all`) and hands each launch to (`_launch` ->
## `Carrier.launch`); nothing here asks which carrier a spell has. A carrier runs what is its own (a
## swap's trade, a beam's rows, a teleport's landing) and asks this script for the shared path: the
## shot kit (`_land_shot`, `_apply_travel`), moves (`CasterMoves`: dash, teleport, pull, swap and
## recoil move a caster through it) and the hit path, which every hit with no shot slot goes back
## through as a ray (`_ray_begin`, `RayHit`; every area strikes through `_strike`, rules R4 F2), so
## cards, payloads and chains are one path for every carrier. The beam, the swing and
## the slam keep rows of their own; `StaffPoses` plays every carrier's staff animation. The looks read
## them from the objects that keep them (`beams`, `swings`, `slams`, `poses`, at the end of this script).
##
## Beams: a beam lives its `lifetime` (`CarrierBeam.start`), held by its caster (the wizard's aim from
## `set_aim`, or its shot), hits at once and every `SpellLimits.BEAM_TICK`, and a homing one bends
## onto a target. `beam_*` give its look to `gameplay/feel`. Dash and teleport move their caster a
## fixed `ray_length`; speed only sets how long a dash takes. Payloads send no `spell_cast`: the wizard's player does, for its seat.
##
## Chain: a shot of a spell with `chain_jumps` that hits a target spawns a shot of the same
## tag from the hit point to the nearest other target within `SpellLimits.CHAIN_RANGE`
## (never the one just hit or the one before it), with one jump fewer; a beam jumps with
## another beam that pierces nothing (it skips only the one just hit, so it may stop at the
## one before if that stands in its way). A chain makes every jump its cards give it: there is
## no per-step count (owner, 2026-10-29).
##
## Counting: every shot spawned here is counted with `shot_started`, and the manager's
## `shot_ended` signal ends it, so a generation lives as long as its last shot. A shot
## starts its children before it ends (the manager sends `shot_ended` after the handlers).
## `bind` connects to the manager and the event bus (`_ready` binds the autoloads; tests
## bind their own).
##
## `hit_profile(tag, shot)` is what `gameplay/combat` asks on `projectile_hit`.
##
## Multicast spread (B2b): a scatter group sends each carrier in a random direction, drawn from
## a generator seeded by the actor, staff and how many casts the staff has made (a replay is
## the same). A burst group fires `repeats` times; the later firings, and an `echo` carrier's
## second firing, wait in a queue (it grows as needed, nothing is dropped for room) and are
## dropped only if the staff was rebuilt or switched off meanwhile. A cast's
## own later firings start from where the caster has moved to. `mirror` fires the carrier again
## with its aim reversed (a move back the other way: the two add up to none, rules R4 F1); an echo
## hits at half damage.
##
## Payload and line carriers (B2c): `rain` strikes the aim point after its `lifetime` with its own
## hit and cards and drops its payload there (a `form_shown` cue `&"rain"` says where and when; an
## `on expire` trigger on it fires as it lands); `familiar` and `decoy` ask `ai` for an entity
## (`entity_spawn_requested`) a step ahead along the aim, as a rune is placed (`_placed_at`),
## count it as a live shot of their tag until `entity_ended`, guard a decoy with its shield or
## deflect (`guard_decoy`), and fire an entity's `on expire` payload and `blast` at its end
## point. A familiar casts only what its triggers give it (rules R4 F3), as any carrier that lasts; `hold` keeps an entity until its staff is cast again (`entity_end_requested`). `wall`
## is one solid still shot across the aim, a short-lived wall (`CarrierWall.launch`).
##
## Moves, areas and refunds (B2d): a `dash` or `teleport` asks the caster's body to move along
## the aim (`caster_move_requested` carries the way and the distance; a teleport is cut short at
## the first wall); `pull` asks the body to move to whatever its carrier hits; a `swap` shot that
## hits moves its target to where the caster stands (`target_move_requested`) and the caster to
## the target; `recoil` pushes the caster back from each firing of its cast (so `mirror` cancels
## it). Every move adds up (rules R4 F1). A dash strikes every body it passes once and a teleport
## the bodies where it lands, so the hit cards work on them; a move's `shield` guards what it
## moves; a move cast by a point moves the wizard (rules R4c). Where a dash or teleport ends, or a
## pull whose hit spent its shot (`caster_move_finished`), is the carrier's end point: its `blast`
## and its `on expire` payload happen there. A shot or beam with `blast` strikes everything round
## where it ends (`_blast`; a pulling shot's waits for the arrival); `siphon` sends `mana_refund_requested` for each hit; `possess`
## sends `possess_requested` for every actor a carrier with it hits (actors G9; owner, 2026-10-29).
##
## Tags (`SpellTag`): the caster's actor id, staff, generation and node. `begin_generation(actor, staff,
## compiled)` registers every compiled spell of a staff under a new generation and returns the
## tag of its first one; a payload's spells have their own nodes. Shots keep the tag they were
## born with, so a shot still in the air after a rebuild hits with its old numbers
## (`profile(tag)`). A generation is forgotten as a whole (every node together) when its last
## shot has ended (`shot_ended`) and it is no longer current.
##
## Casters (actors G3b, docs/milestones/M2-actors.md): every `actor` in this script is an actor
## id (`core/actors`), the one caster number of wizards and enemies alike: the row of every
## per-caster array (sized `ACTORS`), the caster in every tag (`SpellTag.make`) and the
## `caster` of every event. Nothing here asks whether a caster is a wizard or an enemy; the
## actor table (`actors`, else the projectile manager's, else the `Actors` autoload) answers:
## - damage asks nothing: every spell hits every actor's hurtbox (`HITS`; everything hurts
##   everything), and only its caster's own body is skipped;
## - aim asks the **team** (`Actors.team_of`): a chain's jump and an arc's zap go to another
##   team's body (the manager's homing does the same);
## - the per-step fire pacing and the live beams ask the **budget** (`Actors.budget_of`): a
##   seat's actor has its seat's, every actor no seat drives shares one (`Actors.SHARED`), so a
##   crowd never takes a seat's step;
## - only the HUD's events ask the **seat**: `mana_reserved` goes to the seat that drives the
##   actor (an AI reads `reserved_mana`).
## A body that casts opens its caster with `open_caster(id)` and closes it with `close_caster`
## (its staffs, waiting launches, holds and beams end; its shots in the air fly on). Its siphon
## refunds come as `mana_refund_requested(caster, amount)`, and `on hurt` fires on its
## `actor_hurt`.
##
## Order matters: a shot that spawns children (a payload on hit) must call `shot_started` for
## each child before it calls `shot_ended` for itself, or an old build could be freed between
## the two.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

## Every caster number there is: the actor ids.
const ACTORS: int = ActorsScript.ACTORS
## What every spell hits: every actor's hurtbox (everything hurts everything, actors G3b).
const HITS: int = ProjectilesScript.ACTOR_LAYERS
## A wall's pierce (rules R4 F6): a pierce no hit spends, so it stands through every hit.
const PIERCE_ALL: int = 1 << 30
## How a ray this runtime sends itself looks and blocks (a chain jump, a zap: `form_shown`,
## `block_shot`): as a beam's line. A look, not a carrier: it runs no carrier.
const RAY_FORM: StringName = &"beam"
## The look of a zap and its sparks (Feel draws lightning for it).
const ZAP_FORM: StringName = &"zap"
## Bodies a zap shot remembers rolling for (`_rec_zapped`).
const ZAP_MEMORY: int = 32


## A launch that waits for its time: a group's later firing (burst) or one carrier's echo.
class PendingLaunch:
	extends RefCounted
	var due: float = 0.0
	var actor: int = 0
	var staff: int = 0
	var generation: int = 0
	## The group to fire, or null for the single `spell` of an echo or a held carrier's repeat.
	var group: CompiledGroup = null
	var spell: CompiledSpell = null
	## For a single `spell` or a rain's `landing`: an echo's copy (half damage); for a single
	## `spell`, `again` is a held carrier cast again (`_repeats`).
	var echoed: bool = false
	var again: bool = false
	var origin: Vector2 = Vector2.ZERO
	var heading: Vector2 = Vector2.RIGHT
	var source: Node = null
	## The caster's anchor when it was scheduled (`Vector2.INF` if the launch is not the cast's).
	var anchor: Vector2 = Vector2.INF
	## Who casts it (`_caster` and `_caster_seq` when it was scheduled).
	var caster: int = -1
	var caster_seq: int = 0
	## For a trigger's fire waiting for room in a step's budget (`_fire`): the shots it makes; 0
	## for any other launch.
	var cost: int = 0
	## The scatter stream's seed for this firing, so it points the same way however late it runs.
	var seed: int = 0
	## The rain whose payload this is, so it strikes and its own trigger (`on expire`) fires as it
	## lands; `echoed` when that rain is an echo (it strikes at half damage).
	var landing: CompiledSpell = null


## What `cast` returns when the spell did not fire (cooling down, too little mana, no spell).
const REFUSED: float = -1.0

## The shots one budget's trigger fires may make in one step (`SpellLimits.FIRE_SHOTS_PER_STEP`
## unless a benchmark sets another); a fire past it waits for the next step.
var fire_shots_per_step: int = SpellLimits.FIRE_SHOTS_PER_STEP
## Payloads fired, and fires that had to wait for a later step, since the last `clear`.
var fires_made: int = 0
var fires_waited: int = 0

## The projectile manager and the event bus; `bind` sets them.
var projectiles: ProjectilesScript = null
var events: EventsScript = null

## Tags whose shots the last `begin_generation` call revoked, because all 8 generations of
## the slot were in the air. Until the caller removes those shots from the projectile
## manager they carry a tag that now means the new spell, so read this right after
## `begin_generation`, remove them, and only then call `begin_generation` (which clears it)
## or `shot_ended` again for them. Part 6 does exactly that.
var revoked_tags: PackedInt64Array = PackedInt64Array()

## Registry stand-in for tests: anything with `get_resource(folder, id)`. Null uses `Registry`.
var registry: Node = null
## The actor table (actors G2); tests set their own. Null uses the projectile manager's, else the
## `Actors` autoload.
var actors: ActorsScript = null

## actor * STAFFS + staff -> the current generation (0-7), -1 for no build
var _current: PackedInt32Array = PackedInt32Array()
## actor * STAFFS + staff -> the current build, or null
var _installed: Array[CompiledStaff] = []
## actor * STAFFS + staff -> which cast of its cycle comes next
var _cursor: PackedInt32Array = PackedInt32Array()
## actor * STAFFS + staff -> the tags of its sustained (`hold`) carriers that are on
var _hold_tags: Array[PackedInt64Array] = []
## actor * STAFFS + staff -> the carrier (form id) of its last cast, for the cast's look
var _last_form: Array[StringName] = []
## actor * STAFFS + staff -> the mana its sustained carriers reserve
var _hold_mana: PackedFloat32Array = PackedFloat32Array()
## generation key (`SpellTag.generation_key`) -> how many nodes that generation registered
var _node_counts: Dictionary = {}
## tag -> CompiledSpell
var _profiles: Dictionary = {}
## tag -> live shots
var _live: Dictionary = {}
## generation key (the depth-0 tag) -> live shots of all depths of that generation
var _generation_live: Dictionary = {}

## actor * STAFFS + staff -> seconds before that staff may cast again
var _cooldown: PackedFloat32Array = PackedFloat32Array()
## Payloads each actor has fired in this step.
var _fires_used: PackedInt32Array = PackedInt32Array()
## What each shot knows, by projectile slot; valid while `_rec_seq` matches the manager's.
var _rec_seq: PackedInt64Array = PackedInt64Array()
var _rec_chain: PackedInt32Array = PackedInt32Array()
## Instance id of the target a chain came from.
var _rec_prev: PackedInt64Array = PackedInt64Array()
## The live carriers with a `timer` or `on hurt` trigger, `_lc_count` of them (rules R4d): every
## carrier that lasts joins as it starts (`_lc_join`), whatever it is, and `_lc_where` says where
## it is now: the shot in a slot (`LC_SLOT`; also the shot a dash moves), a row of its carrier
## (`LC_ROW`: a beam's or a swing's tip, `Carrier.tip_of`), an actor's body (a wizard's dash) or a point (a rain's spot, a decoy, and a familiar's orb,
## which Entities moves: `familiar_at`, keyed by `_lc_seq`). One `_lc_tied` to its row ends with
## it (a shot, a beam, a swing); the others
## live `_lc_left` seconds (a rain, a dash, an entity) or until they leave (`_lc_leave`: an
## entity that ended, a rain whose landing was dropped). `_lc_clock` is the seconds to the next tick, `_lc_at` where it was last,
## `_lc_way` its way where nothing else gives one.
const LC_SLOT: int = 0
const LC_ROW: int = 1
const LC_ACTOR: int = 2
const LC_POINT: int = 3
var _lc_tag: PackedInt64Array = PackedInt64Array()
var _lc_kind: PackedInt32Array = PackedInt32Array()
var _lc_ref: PackedInt32Array = PackedInt32Array()
var _lc_seq: PackedInt64Array = PackedInt64Array()
var _lc_tied: PackedByteArray = PackedByteArray()
var _lc_left: PackedFloat32Array = PackedFloat32Array()
var _lc_clock: PackedFloat32Array = PackedFloat32Array()
var _lc_at: PackedVector2Array = PackedVector2Array()
var _lc_way: PackedVector2Array = PackedVector2Array()
var _lc_count: int = 0
## Slots of live shots with `zap`, `_zapper_count` of them, flagged in `_rec_zapper`;
## `_rec_zap_rolls` is how many random numbers each has drawn (its rolls are a hash of its sequence
## number and that count: the same every run, `_zap_roll`), and `_rec_zapped` the instance ids of
## the bodies it has rolled for, ZAP_MEMORY a slot side by side, `_rec_zapped_count` of them (each
## body rolls once a shot; past ZAP_MEMORY the oldest is forgotten).
var _zappers: PackedInt32Array = PackedInt32Array()
var _zapper_count: int = 0
var _rec_zapper: PackedByteArray = PackedByteArray()
var _rec_zap_rolls: PackedInt32Array = PackedInt32Array()
var _rec_zapped: PackedInt64Array = PackedInt64Array()
var _rec_zapped_count: PackedInt32Array = PackedInt32Array()
## Zaps made in this step (`SpellLimits.MAX_ZAPS_PER_STEP`), and the steps run (which half of the
## zap shots looks this step, SpellLimits.ZAP_EVERY).
var _zaps_used: int = 0
var _zap_steps: int = 0
## The bodies in a zap shot's reach and their centres (reused, `targets_near`).
var _zap_near: Array[Node2D] = []
var _zap_centres: PackedVector2Array = PackedVector2Array()
## Slots of live shots with `magnet`, `_magnet_count` of them, flagged in `_rec_magnet`.
var _magnets: PackedInt32Array = PackedInt32Array()
var _magnet_count: int = 0
## Where in `_magnets` the next step's pulls start (it rotates when there are more than the cap).
var _magnet_from: int = 0
var _rec_magnet: PackedByteArray = PackedByteArray()
## What a shot hits with when it is not its spell's own `hit`, by slot (null: `hit`): an echo's
## `echo_hit`, what a relay shot became after it hit an actor that had cast an infusion, or what
## the hit a chain jump came from hit with. `_rec_zap` is the same for the shot's zaps (`zap_hit`).
var _rec_relay: Array[HitProfile] = []
var _rec_zap: Array[HitProfile] = []
## The carrier of each actor's last cast that had an infusion (for `relay`), or null.
var _last_infused: Array[CompiledSpell] = []

## Launches that wait for their time (a burst's later firings, an echo), oldest first.
var _pending: Array[PendingLaunch] = []
## Spare records (`SpellLimits.PENDING_START` made at once, more when needed); `_delay` takes one
## and `_release_launch` gives it back.
var _pending_free: Array[PendingLaunch] = []
var _clock: float = 0.0
## actor * STAFFS + staff -> casts made, which seeds the next cast's scatter and staff spread.
var _cast_count: PackedInt32Array = PackedInt32Array()
var _scatter: RandomNumberGenerator = RandomNumberGenerator.new()
## The carrier whose echo is being launched: its shots hit at the echo's half damage.
var _echo_spell: CompiledSpell = null

## Who casts the launch being fired: the actor's body (CASTER_WIZARD, a staff's own cast), the
## point it starts from (CASTER_POINT: a payload whose shot is gone, or one a beam, a rain or an
## entity fired), or the slot of the shot that fired the payload, while it is the shot with
## `_caster_seq`. One rule for every card that names the caster: dash, teleport, pull, swap and
## recoil move it; orbit, familiar and a returning shot circle it or come back to it.
const CASTER_WIZARD: int = ProjectilesScript.CASTER_WIZARD
const CASTER_POINT: int = ProjectilesScript.CASTER_POINT
var _caster: int = CASTER_WIZARD
var _caster_seq: int = 0

## The ray being sent (`RayHit`): what a hit with no shot slot is (a beam's, a swing's, a slam's, a
## dash's, a rain's, a zap, a jump). `_rays[0]` is the empty one (no ray out, tag 0); every
## `_ray_begin` takes the next record of the stack (made once, then reused) and `_ray_end` gives it
## back, so a ray sent from inside another's hit handler leaves the outer one as it was.
var _rays: Array[RayHit] = [RayHit.new()]
var _ray_depth: int = 0
var _ray: RayHit = _rays[0]
## The bodies the strikes under way are striking (`_strike`), and where and which way each is met
## (two points a body): a stack, as a hit a strike sends can strike again.
var _strike_bodies: Array[Node] = []
var _strike_marks: PackedVector2Array = PackedVector2Array()
## True while a `blast` strikes (`_blast`): its hits pull and swap nothing (rules R4 F2).
var _blasting: bool = false
## caster -> the angle from its aim to the way its body walked at its last cast (0 standing;
## `cast_staff`'s `walk`): a dash it casts itself is turned by it.
var _walk_turn: PackedFloat32Array = PackedFloat32Array()
## While `entity_spawn_requested` is sent, the key of the entity it asks for (0 at other times):
## Entities keeps it and hands it back with `familiar_at`. `_entity_keys` counts them out.
var entity_key: int = 0
var _entity_keys: int = 0
## Beam jumps waiting to be cast. A jump is made in a hit handler, i.e. inside the previous
## beam's `ray()`, so casting it there would nest one `ray()` deeper per jump (a long chain
## would recurse as deep as it jumps). The outermost beam casts them, first in first out, once
## its own `ray()` has returned. A ring of JUMP_QUEUE rows that doubles when it is full
## (`_grow_jumps`), so no jump is lost and a busy frame allocates only the first time.
const JUMP_QUEUE: int = 64
var _jq_spell: Array[CompiledSpell] = []
var _jq_target: Array[Node2D] = []
var _jq_tag: PackedInt64Array = PackedInt64Array()
var _jq_actor: PackedInt32Array = PackedInt32Array()
var _jq_pos: PackedVector2Array = PackedVector2Array()
var _jq_dir: PackedVector2Array = PackedVector2Array()
var _jq_len: PackedFloat32Array = PackedFloat32Array()
var _jq_chain: PackedInt32Array = PackedInt32Array()
var _jq_prev: PackedInt64Array = PackedInt64Array()
var _jq_hit: Array[HitProfile] = []
var _jq_head: int = 0
var _jq_count: int = 0
var _jq_busy: bool = false

## The path of a beam's jump, for its guard (`_shoot_ray`); RAY_SEGMENTS is plenty for
## its turns at walls, and a path with more is guarded along its first ones.
var _ray_guard_points: PackedVector2Array = PackedVector2Array()
## actor -> the wizard's staff tip and aim from `set_aim` (INF when it holds none), and 1 once
## the actor has sent one (a test that never does keeps its beams where they were cast).
var _aim_origin: PackedVector2Array = PackedVector2Array()
var _aim_dir: PackedVector2Array = PackedVector2Array()
var _aim_seen: PackedByteArray = PackedByteArray()
## actor -> the wizard's hand (`set_aim`'s `pivot`; INF when not given): what a swing turns round.
var _aim_pivot: PackedVector2Array = PackedVector2Array()
## caster * STAFFS + staff -> the last generation that staff used, so a build after an empty
## staff, or a caster opened again under the same id, goes on round the ring (old shots in the air keep theirs).
var _ring: PackedInt32Array = PackedInt32Array()
## This runtime's carriers, by id (`Carriers.make_all`, bound to it through `_kit`).
var _carriers: Dictionary = {}
## The carrier that runs nothing (id &""), for a spell whose carrier id no carrier has.
var _no_carrier: Carrier = Carrier.new()
## What the carriers (and `_poses`, `_moves`) may ask of this runtime: all they use of it.
var _kit: CarrierKit = null
## Each actor's staff animation, for any carrier with a `staff_pose`.
var _poses: StaffPoses = null
## The moves carriers make of their caster or of the shot that cast them (dash, teleport, pull,
## swap, recoil): `CasterMoves`.
var _moves: CasterMoves = null


func _init() -> void:
	_kit = CarrierKit.new(self)
	_poses = StaffPoses.new(_kit)
	_moves = CasterMoves.new(_kit)
	_carriers = Carriers.make_all()
	for carrier: Carrier in _carriers.values():
		carrier.bind(_kit, _poses)
	_current.resize(ACTORS * SpellLimits.STAFFS)
	_current.fill(-1)
	_installed.resize(ACTORS * SpellLimits.STAFFS)
	_cursor.resize(ACTORS * SpellLimits.STAFFS)
	_hold_mana.resize(ACTORS * SpellLimits.STAFFS)
	_cast_count.resize(ACTORS * SpellLimits.STAFFS)
	for i in ACTORS * SpellLimits.STAFFS:
		_hold_tags.append(PackedInt64Array())
		_last_form.append(&"")
	for i in ACTORS:
		_last_infused.append(null)
	_aim_origin.resize(ACTORS)
	_aim_origin.fill(Vector2.INF)
	_walk_turn.resize(ACTORS)
	_aim_dir.resize(ACTORS)
	_aim_dir.fill(Vector2.INF)
	_aim_seen.resize(ACTORS)
	_aim_pivot.resize(ACTORS)
	_aim_pivot.fill(Vector2.INF)
	_ring.resize(ACTORS * SpellLimits.STAFFS)
	_ring.fill(-1)
	_cooldown.resize(ACTORS * SpellLimits.STAFFS)
	_fires_used.resize(SpellLimits.BUDGETS)
	for i in SpellLimits.PENDING_START:
		_pending_free.append(PendingLaunch.new())
	_jq_spell.resize(JUMP_QUEUE)
	_jq_target.resize(JUMP_QUEUE)
	_jq_tag.resize(JUMP_QUEUE)
	_jq_actor.resize(JUMP_QUEUE)
	_jq_pos.resize(JUMP_QUEUE)
	_jq_dir.resize(JUMP_QUEUE)
	_jq_len.resize(JUMP_QUEUE)
	_jq_chain.resize(JUMP_QUEUE)
	_jq_prev.resize(JUMP_QUEUE)
	_jq_hit.resize(JUMP_QUEUE)
	_lc_grow(64)
	_zappers.resize(64)
	_magnets.resize(64)
	_ray_guard_points.resize(64)


func _ready() -> void:
	if projectiles == null:
		bind(get_node_or_null("/root/Projectiles") as ProjectilesScript, get_node_or_null("/root/Events") as EventsScript)


func _physics_process(delta: float) -> void:
	step(delta)


## Connect to a projectile manager and an event bus (either may be null, then casting is
## refused). Safe to call again: the old ones are disconnected.
func bind(manager: ProjectilesScript, bus: EventsScript) -> void:
	if projectiles != null and is_instance_valid(projectiles):
		projectiles.shot_ended.disconnect(shot_ended)
		projectiles.wall_met.disconnect(_on_wall_met)
	if events != null and is_instance_valid(events):
		events.projectile_hit.disconnect(_on_hit)
		events.projectile_expired.disconnect(_on_expired)
		events.shot_blocked.disconnect(_on_shot_blocked)
		events.shield_blocked.disconnect(_on_shield_blocked)
		events.shot_deflected.disconnect(_on_shot_deflected)
		events.kill_landed.disconnect(_on_kill)
		events.actor_hurt.disconnect(_on_hurt)
		events.reaction_landed.disconnect(_on_reaction)
		events.entity_ended.disconnect(_on_entity_ended)
		events.caster_move_finished.disconnect(_moves.finished)
	projectiles = manager
	events = bus
	if projectiles != null:
		projectiles.shot_ended.connect(shot_ended)
		projectiles.wall_met.connect(_on_wall_met)
	if events != null:
		events.projectile_hit.connect(_on_hit)
		events.projectile_expired.connect(_on_expired)
		events.shot_blocked.connect(_on_shot_blocked)
		events.shield_blocked.connect(_on_shield_blocked)
		events.shot_deflected.connect(_on_shot_deflected)
		events.kill_landed.connect(_on_kill)
		events.actor_hurt.connect(_on_hurt)
		events.reaction_landed.connect(_on_reaction)
		events.entity_ended.connect(_on_entity_ended)
		events.caster_move_finished.connect(_moves.finished)


## True when the card `card_id` does something on the carrier `carrier` (`FormBase.carrier`) on its
## own: for the builder, a reward screen or a bot, before the card is placed
## (`StaffCompiler.card_works`). False for an unknown card.
func card_works(card_id: StringName, carrier: StringName) -> bool:
	var card: SpellComponent = _component(card_id)
	return card != null and StaffCompiler.card_works(card, carrier)


## Compiles a staff's cards (ids by slot, `&""` for an empty slot) into its cycle, the casts it
## makes until it recharges (staffs A4; the rules are docs/milestones/M2-staffs.md, "Reading a
## staff", and `StaffCompiler`). It never errors and refuses nothing: an unknown or useless
## card is listed in `wasted`.
func compile_staff(cards: Array[StringName], staff: StaffBase) -> CompiledStaff:
	return StaffCompiler.new(_component).compile(cards, staff)


## What the builder shows of a staff, as plain values so that nothing outside `core/spells`
## reads a compiled staff: `empty`; `cards` (the card ids by slot, `&""` for an empty slot); `casts`, one Dictionary per cast of the cycle with `slots`
## (read order), `name` (the generated spell name, `SpellNamer`), `text`, `mana`, `delay`, `damage` (each carrier's hit times its shots and the group's repeats, payloads left out), `recharges`, `wrapped`, `targets` (card slot -> the
## carrier's slot, or `StaffCompiler.TARGET_CASTER` / `TARGET_POINT`) and `wasted` (slot ->
## true); `wasted` for the staff (cards that did nothing in any cast that read them); and
## `staff`, the StaffBase given, only to hand back to `staff_view` for a preview of other cards
## (the radial builder shows what a card would change before it is put in).
func staff_view(cards: Array[StringName], staff: StaffBase) -> Dictionary:
	var compiled: CompiledStaff = compile_staff(cards, staff)
	var casts: Array[Dictionary] = []
	for cast in compiled.casts:
		casts.append({
			"slots": cast.slots, "name": cast.spell_name, "text": cast.description, "mana": cast.mana, "delay": cast.delay,
			"damage": _cast_damage(cast),
			"recharges": cast.recharges, "wrapped": cast.wrapped,
			"targets": cast.targets.duplicate(), "wasted": cast.wasted.duplicate(),
		})
	var row: Array[StringName] = []
	row.assign(compiled.cards)
	return {"empty": compiled.is_empty(), "cards": row, "casts": casts, "wasted": compiled.wasted.duplicate(), "staff": staff}


## The shareable text code of a staff's cards (staffs D2, `StaffCode`).
static func staff_code(cards: Array[StringName]) -> String:
	return StaffCode.encode(cards)


## Read a pasted staff code: `{ok, cards, error}` (`StaffCode.parse`), every id checked against
## the registry. `slots` pads the cards to that many (0: as written).
func parse_staff_code(text: String, slots: int = 0) -> Dictionary:
	return StaffCode.parse(text, _is_card, slots)


func _is_card(id: StringName) -> bool:
	return _component(id) != null


## The damage one cast deals if every shot of it lands once (a beam: every hit of its life):
## each carrier's hit times its shots, times the group's repeats. Payloads are left out (they
## depend on what is hit), so it is the builder's "at least" number; to a tenth (an atom's 0.3).
static func _cast_damage(cast: CompiledCast) -> float:
	if cast.group == null:
		return 0.0
	var total: float = 0.0
	for spell in cast.group.spells:
		total += spell.damage * float(maxi(spell.shots, 1) * Carriers.of(spell.carrier).hits_per_target(spell.lifetime))
	return snappedf(total * float(maxi(cast.group.repeats, 1)), 0.1)


## What the builder shows of the component `id`: its name (the id when it has none, "" for
## an unknown id), its 16x16 icon (null when unknown) and its kind (`&"form"`, `&"element"`,
## `&"modifier"` or `&"trigger"`, `&""` when unknown). Scripts outside `core/` and
## `content/spells/` learn these here and never read the component's fields.
func component_name(id: StringName) -> String:
	var component: SpellComponent = _component(id)
	return _name_of(component) if component != null else ""


func component_icon(id: StringName) -> Texture2D:
	var component: SpellComponent = _component(id)
	return component.icon if component != null else null


## The card's own numbers for the builder, as short lines of at most three (none for an unknown
## id): a carrier's damage (times its shots), mana and delay ("Dmg 3x8", "Mana 10", "Delay 1s");
## a modifier's changes ("Dmg x0.5", "Shots x3", "Homes in"); an element's status and how long it
## lasts ("Burn 3s"); when a trigger fires its payload ("On hit"); a multicast's draws.
func component_stats(id: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	var component: SpellComponent = _component(id)
	if component is FormBase:
		var form: FormBase = component
		var hits: int = maxi(form.shots, 1) * Carriers.of(form.carrier).hits_per_target(form.lifetime)
		out.append("Dmg " + _short(form.base_damage) if hits <= 1 else "Dmg %sx%d" % [_short(form.base_damage), hits])
		out.append("Mana " + _short(form.mana_cost))
		out.append("Delay %ss" % _short(form.cooldown))
	elif component is ModifierBase:
		var modifier: ModifierBase = component
		var words: Dictionary = {
			ModifierBase.Behaviour.HOMING: "Homes in", ModifierBase.Behaviour.CHAIN: "Chains %s",
			ModifierBase.Behaviour.SHIELD: "Blocks %s", ModifierBase.Behaviour.BOUNCE: "Bounces %s",
		}
		if words.has(modifier.behaviour):
			var word: String = words[modifier.behaviour]
			out.append(word % _short(modifier.behaviour_strength) if word.contains("%s") else word)
		elif modifier.behaviour != ModifierBase.Behaviour.NONE:
			out.append(String(ModifierBase.Behaviour.keys()[modifier.behaviour]).capitalize())
		if modifier.extra_pierce != 0:
			out.append("Pierce +%d" % modifier.extra_pierce)
		var mults: Array = [
			["Dmg", modifier.damage_mult], ["Mana", modifier.mana_mult], ["Shots", float(modifier.shot_mult)],
			["Delay", modifier.cooldown_mult], ["Speed", modifier.speed_mult], ["Size", modifier.radius_mult],
			["Spread", modifier.spread_mult], ["Reach", modifier.reach_mult],
		]
		for pair: Array in mults:
			if not is_equal_approx(float(pair[1]), 1.0):
				out.append("%s x%s" % [pair[0], _short(float(pair[1]))])
	elif component is ElementBase:
		var element: ElementBase = component
		if element.status_id != &"":
			out.append("%s %ss" % [String(element.status_id).capitalize(), _short(element.status_duration)])
		if element.heals:
			out.append("Heals wizards")
		if not is_equal_approx(element.damage_scale, 1.0):
			out.append("Dmg x" + _short(element.damage_scale))
	elif component is TriggerBase:
		var trigger: TriggerBase = component
		if trigger.event == TriggerBase.Event.TIMER:
			out.append("Every %ss" % _short(trigger.interval))
		else:
			out.append("On " + String(TriggerBase.Event.keys()[trigger.event]).to_lower())
	elif component is MulticastBase:
		var multicast: MulticastBase = component
		if multicast.extra_draws > 0:
			out.append("+%d carriers" % multicast.extra_draws)
		if multicast.repeats > 1:
			out.append("%d times" % multicast.repeats)
		if multicast.mana_cost > 0.0:
			out.append("Mana " + _short(multicast.mana_cost))
	if out.size() > 3:
		out.resize(3)
	return out


## A number as the builder writes it: at most two decimals and no trailing zeros, keeping the
## leading zero (0.35 is "0.35": ".35" in the pixel font read as 35).
static func _short(value: float) -> String:
	var text: String = "%.2f" % value
	return text.rstrip("0").rstrip(".")


## The one-line description of the component `id` for the builder, from its lore file in
## `content/story/lore/components/`. Empty for an unknown id or a missing file; the builder
## shows nothing for an empty one.
func component_description(id: StringName) -> String:
	var source: Node = registry if registry != null else get_node_or_null("/root/Registry")
	if source == null:
		return ""
	return source.call("get_lore", &"component", id)


func component_kind(id: StringName) -> StringName:
	var component: SpellComponent = _component(id)
	return component.kind() if component != null else &""


## The spell registered under `tag`, or null when its generation is gone.
func profile(tag: int) -> CompiledSpell:
	return _profiles.get(tag)


## Registers every spell of `compiled` under a new generation of this actor's staff and
## returns the tag of its first spell, or 0 for an empty staff (the staff then has no build)
## or a bad actor or staff. The staff's generation advances; if its shots from 8 builds ago are
## still in the air the oldest generation is revoked (see `revoked_tags`).
func begin_generation(actor: int, staff: int, compiled: CompiledStaff) -> int:
	revoked_tags.clear()
	if compiled == null or not _in_range(actor, staff) or compiled.nodes.size() > SpellTag.NODE_MASK + 1:
		return 0
	var index: int = actor * SpellLimits.STAFFS + staff
	_release_hold(index)
	# The old build casts no more: its cast's later firings go (a payload of a shot in the air
	# fires on, as the shot flies on).
	_drop_pending(func(launch: PendingLaunch) -> bool: return launch.actor == actor and launch.staff == staff and launch.caster == CASTER_WIZARD)
	var old: int = _current[index]
	if compiled.is_empty():
		_installed[index] = null
		_cursor[index] = 0
		_current[index] = -1
		if old >= 0:
			_release_generation(actor, staff, old)
		return 0
	var generation: int = (_ring[index] + 1) % SpellLimits.GENERATIONS
	_ring[index] = generation
	_current[index] = generation
	var key: int = SpellTag.generation_key(SpellTag.make(actor, staff, 0, generation))
	for node in _node_counts.get(key, 0):
		var stale: int = SpellTag.make(actor, staff, node, generation)
		if _live.get(stale, 0) > 0:
			revoked_tags.append(stale)
		_profiles.erase(stale)
		_live.erase(stale)
	# The revoked build's waiting payloads go with its shots (its numbers are the new build's now).
	_drop_pending(func(launch: PendingLaunch) -> bool: return launch.actor == actor and launch.staff == staff and launch.generation == generation)
	_generation_live.erase(key)
	for spell in compiled.nodes:
		_profiles[SpellTag.make(actor, staff, spell.node, generation)] = spell
	_node_counts[key] = compiled.nodes.size()
	_installed[index] = compiled
	_cursor[index] = 0
	if old >= 0:
		_release_generation(actor, staff, old)
	return SpellTag.make(actor, staff, 0, generation)


## The tag of the current build of this staff at `node`, or 0 when it has no build.
func current_tag(actor: int, slot: int, node: int = 0) -> int:
	if not _in_range(actor, slot):
		return 0
	var generation: int = _current[actor * SpellLimits.STAFFS + slot]
	return 0 if generation < 0 else SpellTag.make(actor, slot, node, generation)


## A shot with `tag` was spawned. Ignored for a tag that has no spell.
func shot_started(tag: int) -> void:
	if _profiles.has(tag):
		_live[tag] = _live.get(tag, 0) + 1
		var key: int = SpellTag.generation_key(tag)
		_generation_live[key] = _generation_live.get(key, 0) + 1


## A shot with `tag` ended (hit, expired or was removed). The generation's spells (every
## node) are freed once its last shot of any node is gone and a newer build has replaced it. A
## sustained (`hold`) carrier whose last shot ends frees its mana reservation.
func shot_ended(tag: int) -> void:
	var live: int = _live.get(tag, 0)
	if live <= 0:
		return
	if live == 1:
		_live.erase(tag)
		_end_hold_of(tag)
		_poses.end_strike(tag)
	else:
		_live[tag] = live - 1
	_generation_gone(tag)


## One shot of `tag`'s generation, or one launch that keeps it (`_delay`), is gone: an old
## generation with none left is freed.
func _generation_gone(tag: int) -> void:
	var key: int = SpellTag.generation_key(tag)
	var in_air: int = _generation_live.get(key, 0) - 1
	if in_air > 0:
		_generation_live[key] = in_air
		return
	_generation_live.erase(key)
	if not _is_current(tag):
		_erase_generation(tag)


## Live shots counted for `tag`.
func live_shots(tag: int) -> int:
	return _live.get(tag, 0)


## Generations of this staff that still have spells registered (the current one and any
## older ones with shots in the air).
func generations_held(actor: int, slot: int) -> int:
	var count: int = 0
	if not _in_range(actor, slot):
		return 0
	for generation in SpellLimits.GENERATIONS:
		if _node_counts.has(SpellTag.generation_key(SpellTag.make(actor, slot, 0, generation))):
			count += 1
	return count


## What one hit of a shot with `tag` does, or null when the tag is no spell's (a shot of no staff)
## or its generation is gone. `shot` is the shot that hit (the event's `shot`; -1 for a ray or a
## strike). Shared and read-only; allocates nothing.
func hit_profile(tag: int, shot: int = -1) -> HitProfile:
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null:
		return null
	# A relay shot hits with what it took on (the hit names its shot).
	var slot: int = shot if projectiles != null else -1
	if slot >= 0 and slot < _rec_relay.size() and _rec_relay[slot] != null and _same(slot) and projectiles.get_tag_of(slot) == tag:
		return _rec_relay[slot]
	# A ray (a beam, a swing, a zap, a jump of any) has no slot: it hits with what the
	# one being sent carries (an echo's half, a zap's share, a jump's parent hit).
	if _ray.hit != null and tag == _ray.tag:
		return _ray.hit
	return spell.hit


## Makes `compiled` (from `compile_staff`) the build of this actor's staff (0-3), starting its
## cycle at the first cast, and removes the shots the new generation revoked. Editing a staff
## switches its sustained (`hold`) carriers off. Returns the tag of its first spell, or 0 for an
## empty staff (which leaves the staff with no build) or a bad actor or staff.
func install_staff(actor: int, staff: int, compiled: CompiledStaff) -> int:
	var tag: int = begin_generation(actor, staff, compiled)
	if projectiles != null:
		for revoked in revoked_tags:
			projectiles.remove_by_tag(revoked)
	for revoked in revoked_tags:
		for carrier: Carrier in _carriers.values():
			carrier.end_of(revoked)
	return tag


## Seconds before this actor's staff may cast again.
func cooldown_left(actor: int, slot: int) -> float:
	return _cooldown[actor * SpellLimits.STAFFS + slot] if _in_range(actor, slot) else 0.0


## Which cast of its cycle this actor's staff makes next (0 after a recharge).
func cast_index(actor: int, staff: int) -> int:
	return _cursor[actor * SpellLimits.STAFFS + staff] if _in_range(actor, staff) else 0


## The carrier (form id) of the last cast this actor's staff made, `&""` before any or for a
## cast with no carrier (cards that landed on the caster). The wizard's player sends it with `spell_cast`.
func last_form(actor: int, staff: int) -> StringName:
	return _last_form[actor * SpellLimits.STAFFS + staff] if _in_range(actor, staff) else &""


## True while this actor's staff has sustained (`hold`) carriers switched on.
func is_holding(actor: int, staff: int) -> bool:
	return _in_range(actor, staff) and not _hold_tags[actor * SpellLimits.STAFFS + staff].is_empty()


## Fires the next cast of this actor's staff from `origin` along `direction`. `mana` is what
## the caster has. Returns the mana spent (0.0 or more) when it fired, or `REFUSED` when it did
## not (nothing built, still in its delay, too little mana, no direction, or every shot starting
## inside a wall); the caller then takes that much mana and reads no field. A refused cast
## changes nothing, except that a cast with nothing in it (every card wasted) still moves the
## staff on, so it never sticks there.
##
## While the staff has sustained (`hold`) carriers on, a cast switches them all off instead,
## frees their reservation and returns 0.0. The caller decides which presses may do that (a
## held button should not switch on and off again and again).
##
## `walk` is the way the caster's body walks (zero when it stands): a dash it casts itself takes
## that way in place of `direction` (`CarrierMove`; staffs A6a, kept by the owner in R4 F1).
func cast_staff(actor: int, staff: int, origin: Vector2, direction: Vector2, mana: float, walk: Vector2 = Vector2.ZERO) -> float:
	if projectiles == null or not _in_range(actor, staff) or not origin.is_finite():
		return REFUSED
	if not direction.is_finite() or direction.is_zero_approx():
		return REFUSED
	var index: int = actor * SpellLimits.STAFFS + staff
	var compiled: CompiledStaff = _installed[index]
	if compiled == null or compiled.is_empty() or _cooldown[index] > 0.0:
		return REFUSED
	if not _hold_tags[index].is_empty():
		_release_hold(index)
		_cooldown[index] = compiled.staff.cast_delay if compiled.staff != null else 0.0
		return 0.0
	var cast: CompiledCast = compiled.casts[mini(_cursor[index], compiled.casts.size() - 1)]
	if mana < cast.mana:
		return REFUSED
	var aim: Vector2 = direction.normalized()
	_walk_turn[actor] = aim.angle_to(walk) if walk.is_finite() and not walk.is_zero_approx() else 0.0
	if cast.group.is_empty():
		_after_cast(index, compiled, cast)
		return REFUSED
	_scatter.seed = hash(Vector3i(actor, staff, _cast_count[index]))
	if _launch_group(cast.group, actor, staff, _current[index], origin, aim, null, true) == 0:
		return REFUSED
	_cast_count[index] += 1
	_after_cast(index, compiled, cast)
	_last_infused[actor] = null
	for carrier in cast.group.spells:
		if not carrier.element_ids.is_empty():
			_last_infused[actor] = carrier
			break
	var first: CompiledSpell = cast.group.spells[0]
	_last_form[index] = first.form_id
	return cast.mana


## The delay and the next cast of the cycle, after `cast` fired (or had nothing in it).
func _after_cast(index: int, compiled: CompiledStaff, cast: CompiledCast) -> void:
	_cooldown[index] = cast.delay
	_cursor[index] = 0 if cast.recharges else (_cursor[index] + 1) % compiled.casts.size()


## Runs the cooldowns and the timer triggers by `delta` seconds, and opens a new step for
## the fire and jump caps. The autoload calls it every physics step; the order of the two
## autoloads in project.godot (Projectiles first) is what makes it run after the manager.
## So a cap's window is this step's timer fires plus the next step's hits, and a `cast` made
## between the two (a beam's on-expire spell, an actor's own cast) counts against whichever
## window is open.
func step(delta: float) -> void:
	for c in _cooldown.size():
		_cooldown[c] = maxf(_cooldown[c] - delta, 0.0)
	_fires_used.fill(0)
	_clock += delta
	_run_waiting_fires()
	_moves.step(delta)
	for carrier: Carrier in _carriers.values():
		carrier.step(delta)
	_step_live(delta)
	_step_zaps(delta)
	_step_magnets()
	_run_pending()


## The shots made by one launch of `spell`, returned as how many were made (a beam counts
## as one). `source` is the target that fired the trigger, or null.
func _launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, source: Node, chain: int = -1, prev: int = 0) -> int:
	var carrier: Carrier = _carrier_of(spell)
	var carried: int = spell.chain_jumps if chain < 0 else chain
	# A held carrier lives until switched off; one that repeats (`_repeats`) lives its own life each time.
	var held: bool = _holds(spell, tag)
	var lifetime: float = SpellLimits.HOLD_LIFETIME if held and not _repeats(spell) else spell.lifetime
	# Any carrier may move the staff (its card's `staff_pose`); a swing's and a slam's start theirs
	# with their own wind-up, side and strike.
	if not spell.staff_pose.is_empty() and not spell.has_trait(Carrier.OWN_POSE):
		if _caster == CASTER_WIZARD and actor >= 0 and actor < ACTORS and _poses.started_at(actor) != _clock and direction.is_finite() and not direction.is_zero_approx():
			_poses.start(actor, spell, tag, maxf(spell.wind_up, 0.0), StaffPoses.strike_of(spell, lifetime), direction.normalized(), StaffPoses.up_side(direction))
	return carrier.launch(spell, tag, actor, origin, direction, source, lifetime, carried, prev)


## The carrier that runs `spell` (`Carrier`, by its id; one that runs nothing for a fallback).
func _carrier_of(spell: CompiledSpell) -> Carrier:
	var carrier: Carrier = _carriers.get(spell.carrier)
	return carrier if carrier != null else _no_carrier


## A shot a carrier spawned in `slot` (-1 when the manager refused it) takes its cards (`_apply_travel`)
## and its record, and does not hit `source` for a while: 1 when it was made.
func _land_shot(slot: int, spell: CompiledSpell, tag: int, source: Node, chain: int, prev: int) -> int:
	if slot < 0:
		return 0
	_apply_travel(slot, spell)
	_register(slot, tag, spell, chain, prev)
	if source != null:
		projectiles.exclude(slot, source, SpellLimits.SOURCE_EXCLUSION)
	return 1


## Sends a ray: until `_ray_end`, every hit with no shot slot is this one (`_on_hit`, `hit_profile`,
## `_relay`), with `tag`'s cards, going along `dir`, with `chain` jumps left after `prev`, hitting
## with `hit` when not its spell's own (null), as a zap of shot `zap_slot` (-1 for none). Returns the
## record, so a sweep can turn `dir` from body to body and read what `relay` left in `hit`.
func _ray_begin(tag: int, dir: Vector2, chain: int, prev: int, hit: HitProfile, zap_slot: int) -> RayHit:
	_ray_depth += 1
	if _ray_depth == _rays.size():
		_rays.append(RayHit.new())
	_ray = _rays[_ray_depth]
	_ray.set_to(tag, dir, chain, prev, hit, zap_slot)
	return _ray


## Ends the ray `_ray_begin` sent: the one it was sent from (or none) is the ray again.
func _ray_end() -> void:
	_ray.hit = null
	_ray_depth -= 1
	_ray = _rays[_ray_depth]


## The one strike (rules R4 F2): the carrier `spell` with `tag` hits each of the first `found`
## bodies of the last `Projectiles.sweep` round `centre` that is not in `struck` yet (and adds it),
## where the sweep met it, as a ray (`_ray_begin`) that `_on_hit` reads: its infusions, heavy,
## chain (`chain` jumps left, `prev` the body before), siphon, possess, relay and `on hit` go with
## it, and the hit's push throws the body outward from `centre` (a whole circle strikes from
## `centre`, `Projectiles.sweep`). `hit` is what it hits with when not its spell's own (an echo's),
## else null. A swing, a slam, a dash, a teleport, a rain and a blast all strike through here. The
## bodies are copied out first (onto `_strike_bodies`): what a hit sets off can sweep. Returns what
## it hit with at the end (relay may have taken an element on), for a carrier that strikes again
## to keep, as a live beam does.
func _strike(spell: CompiledSpell, tag: int, actor: int, found: int, struck: Array, centre: Vector2, chain: int, prev: int, hit: HitProfile) -> HitProfile:
	var first: int = _strike_bodies.size()
	for i in found:
		var node: Node = projectiles.sweep_nodes[i]
		if not struck.has(node):
			struck.append(node)
			_strike_bodies.append(node)
			_strike_marks.append(projectiles.sweep_points[i])
			_strike_marks.append(projectiles.sweep_heads[i])
	var last: int = _strike_bodies.size()
	if last == first:
		return hit
	var ray: RayHit = _ray_begin(tag, Vector2.RIGHT, chain, prev, hit, -1)
	for n in range(first, last):
		var point: Vector2 = _strike_marks[n * 2]
		var head: Vector2 = _strike_marks[n * 2 + 1]
		ray.dir = centre.direction_to(point) if not centre.is_equal_approx(point) else head
		projectiles.strike(actor, _strike_bodies[n], point, head, tag, spell.form_id)
	var took: HitProfile = ray.hit
	_ray_end()
	_strike_bodies.resize(first)
	_strike_marks.resize(first * 2)
	_cast_jumps()
	return took


## The carrier `spell` with `tag` strikes every body within `reach` of `at` at once (`_strike`),
## with `hit` (null: its own): a rain where it lands, a teleport where it lands, a blast. With
## `everyone` (a blast, the cards that land on a point) its caster's own body is struck too, and a
## wall hides no body: an explosion at a shot's end on a wall is in the wall.
func _strike_round(spell: CompiledSpell, tag: int, actor: int, at: Vector2, way: Vector2, reach: float, hit: HitProfile, everyone: bool = false, chain: int = -1, prev: int = 0) -> void:
	var found: int = projectiles.sweep(ActorsScript.NONE if everyone else actor, at, way, 1, -PI, PI, reach, HITS, null, not everyone)
	if found > 0:
		_strike(spell, tag, actor, found, [], at, spell.chain_jumps if chain < 0 else chain, prev, hit)


## The live shot casting the launch being fired, or -1 when the caster is the wizard, a point,
## or a shot that has ended since.
func _caster_shot() -> int:
	return live_caster_shot(_caster, _caster_seq)


## `caster` when it is a shot's slot and that shot (`seq`) still flies, else -1.
func live_caster_shot(caster: int, seq: int) -> int:
	if caster >= 0 and projectiles.is_alive(caster) and projectiles.get_seq_of(caster) == seq:
		return caster
	return -1


## `_launch_group` cast by `caster`: CASTER_WIZARD, CASTER_POINT, or a shot's slot (a shot that
## is not alive makes the point the caster). The caster from before is set again afterwards.
func _launch_as(group: CompiledGroup, actor: int, staff: int, generation: int, origin: Vector2, heading: Vector2, source: Node, caster: int) -> int:
	var saved: int = _caster
	var saved_seq: int = _caster_seq
	_caster = CASTER_POINT
	if caster == CASTER_WIZARD:
		_caster = CASTER_WIZARD
	elif caster >= 0 and projectiles.is_alive(caster):
		_caster = caster
		_caster_seq = projectiles.get_seq_of(caster)
	var made: int = _launch_group(group, actor, staff, generation, origin, heading, source, _caster == CASTER_WIZARD)
	_caster = saved
	_caster_seq = saved_seq
	return made


## Where a carrier its caster places (a rune, a decoy, a familiar) appears: a step ahead of
## `origin` along `heading`, twice its size (rules R4 F3), so a mirror's copy is placed behind;
## with a wall in the way, at `origin` (never in the wall).
func _placed_at(spell: CompiledSpell, origin: Vector2, heading: Vector2) -> Vector2:
	var ahead: Vector2 = origin + heading * spell.radius * 2.0
	return ahead if projectiles.clip_to_walls(origin, ahead) == ahead else origin


## Hand a shot the behaviours of its cards that the projectile manager runs (staffs B1): a bolt,
## a rune, an orbit and a wall's shots from the staff and a chain jump alike (rules R1b). Each
## setter takes what the shot can do and refuses the rest (rules R4h: a rune does not move, an
## orbit does not fly). A plain shot costs one comparison per behaviour and no call.
func _apply_travel(slot: int, spell: CompiledSpell) -> void:
	if spell.homing_range > 0.0:
		projectiles.set_homing_curve(slot, spell.homing_curve, spell.homing_range)
	if spell.behaviour(ModifierBase.Behaviour.RETURN) > 0.0:
		projectiles.set_return(slot)
	if spell.behaviours.is_empty():
		return
	var bounce: float = spell.behaviour(ModifierBase.Behaviour.BOUNCE)
	if bounce > 0.0:
		projectiles.set_bounce(slot, roundi(bounce))
	if spell.behaviour(ModifierBase.Behaviour.GHOST) > 0.0:
		projectiles.set_ghost(slot)
	var spiral: float = spell.behaviour(ModifierBase.Behaviour.SPIRAL)
	if spiral > 0.0:
		projectiles.set_spiral(slot, spiral)
	var linger: float = spell.behaviour(ModifierBase.Behaviour.LINGER)
	if linger > 0.0:
		projectiles.set_linger(slot, linger)
	var growth: float = spell.behaviour(ModifierBase.Behaviour.GROWTH)
	if growth > 1.0:
		projectiles.set_growth(slot, growth)
	var sticky: float = spell.behaviour(ModifierBase.Behaviour.STICKY)
	if sticky > 0.0:
		projectiles.set_sticky(slot, sticky)
	_apply_shield(slot, spell)


## A shot with `shield` blocks that many enemy shots.
func _apply_shield(slot: int, spell: CompiledSpell) -> void:
	if slot < 0 or spell.behaviours.is_empty():
		return
	var shield: float = spell.behaviour(ModifierBase.Behaviour.SHIELD)
	if shield > 0.0:
		projectiles.set_shield(slot, roundi(shield))
	if spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0:
		projectiles.set_deflect(slot, true)


## The shots of every spell of `group`, fired together from `origin` along `direction` by this
## actor's staff in its `generation` (each spell's tag names its node); returns how many were
## made (a fallback counts as one). The carriers of one group leave along the same aim (only the
## staff's `spread` sets them apart, shot by shot); a scatter group sends each in a random
## direction instead. A burst group fires again `repeats - 1` times, `repeat_interval` seconds
## apart (at once when that is 0), reading nothing again. A fallback strikes everything on the
## spot: the caster's for a cast, the payload's origin for a payload. `source` is the target that
## fired the payload, or null. `from_caster` is true for the cast's own group, whose later
## firings (burst, echo) start from where the caster has moved to.
func _launch_group(group: CompiledGroup, actor: int, staff: int, generation: int, origin: Vector2, direction: Vector2, source: Node, from_caster: bool = false) -> int:
	var made: int = _fire_group(group, actor, staff, generation, origin, direction, source, from_caster)
	if made > 0:
		for n in range(1, group.repeats):
			if group.repeat_interval <= 0.0:
				_fire_group(group, actor, staff, generation, origin, direction, source, from_caster)
			else:
				_delay(n * group.repeat_interval, group, null, actor, staff, generation, origin, direction, source, from_caster)
	return made


## One firing of `group` (see `_launch_group`).
func _fire_group(group: CompiledGroup, actor: int, staff: int, generation: int, origin: Vector2, direction: Vector2, source: Node, from_caster: bool) -> int:
	var made: int = 0
	for spell in group.spells:
		var heading: Vector2 = direction
		if spell.fallback == CompiledSpell.FALLBACK_NONE and group.scatter:
			heading = direction.rotated(_scatter.randf() * TAU)
		made += _fire_spell(spell, actor, staff, generation, origin, heading, source, from_caster, false)
	return made


## One carrier of a group, launched; returns the shots made. `mirror` fires it once more with its
## aim reversed (a wall behind, a rain at the point mirrored through the caster, an orbit starting
## on the other side of its circle, a dash or teleport back the other way: the two moves add up
## to none, rules R4 F1), and `echo` schedules it once more. `echoed` is true for that second firing, which hits at half damage and does not
## echo again; on a held carrier it is a second held copy. `again` is a held carrier cast again
## (`_repeats`): it echoes no more.
func _fire_spell(spell: CompiledSpell, actor: int, staff: int, generation: int, origin: Vector2, heading: Vector2, source: Node, from_caster: bool, echoed: bool, again: bool = false) -> int:
	var tag: int = SpellTag.make(actor, staff, spell.node, generation)
	if spell.fallback != CompiledSpell.FALLBACK_NONE:
		return _fallback_hit(spell, tag, actor, origin)
	_echo_spell = spell if echoed else null
	var launched: int = _launch(spell, tag, actor, origin, heading, source)
	if launched > 0:
		_recoil(spell, tag, actor, heading)
	if launched > 0 and spell.behaviour(ModifierBase.Behaviour.MIRROR) > 0.0:
		var backwards: int = _launch(spell, tag, actor, origin, -heading, source)
		launched += backwards
		if backwards > 0:
			_recoil(spell, tag, actor, -heading)
	_echo_spell = null
	if launched > 0 and _holds(spell, tag):
		_start_hold(tag)
		if _repeats(spell):
			var repeat: PendingLaunch = _delay(maxf(spell.wind_up, 0.0) + spell.lifetime, null, spell, actor, staff, generation, origin, heading, source, from_caster)
			repeat.again = true
			repeat.echoed = echoed
	# `on cast`: the payload leaves at once, from where the carrier did, cast by the carrier's caster.
	if launched > 0 and spell.payload != null and spell.trigger_event == TriggerBase.Event.CAST:
		if from_caster:
			_fire(spell.payload, actor, staff, generation, origin, heading, source, _caster, true)
		else:
			_fire(spell.payload, actor, staff, generation, origin, heading, source, _caster)
	var echo: float = spell.behaviour(ModifierBase.Behaviour.ECHO)
	if launched > 0 and not echoed and not again and echo > 0.0:
		_delay(echo, null, spell, actor, staff, generation, origin, heading, source, from_caster).echoed = true
	return launched


## `recoil`: the caster is pushed back from a firing along `heading` (a firing the other way
## pushes the other way, so `mirror` cancels it). It is one more move, and every move adds up (a
## dash's or a teleport's too: a recoil longer than a teleport takes it back past its start).
func _recoil(spell: CompiledSpell, tag: int, actor: int, heading: Vector2) -> void:
	var push: float = spell.behaviour(ModifierBase.Behaviour.RECOIL)
	if push <= 0.0:
		return
	if _caster != CASTER_WIZARD:
		# A payload's recoil pushes the shot that cast it (a point has nothing to push).
		var shot: int = _caster_shot()
		if shot >= 0:
			projectiles.move_shot(shot, -heading * push, SpellLimits.RECOIL_SECONDS)
		return
	if events != null:
		events.caster_move_requested.emit(actor, &"recoil", -heading * push, SpellLimits.RECOIL_SECONDS, tag)


## A `blast` at the end point `at` of the carrier with `tag`: its explosion (`cue_shown`, the cue
## its blast card names) and a strike of everything within its strength (`_strike_round`,
## `everyone`): each body it catches is a hit of the carrier (rules R4 F2), with what the carrier
## hits with now as `burst` (`CompiledSpell.blast_hit`) and the chain jumps it has left (the ray's
## being sent, else the shot `shot`'s), so a jump's blast jumps no further than the jump. Its hits
## blast no more. Nothing without a blast.
func _blast(spell: CompiledSpell, tag: int, actor: int, at: Vector2, shot: int = -1) -> void:
	var radius: float = spell.behaviour(ModifierBase.Behaviour.BLAST)
	if radius <= 0.0 or events == null or not at.is_finite():
		return
	events.cue_shown.emit(actor, spell.cue_of(ModifierBase.Behaviour.BLAST), at, Vector2.ZERO, radius, spell.tint, spell.look)
	var chain: int = spell.chain_jumps
	var prev: int = 0
	if tag == _ray.tag:
		chain = _ray.chain
		prev = _ray.prev
	elif shot >= 0 and _same(shot) and projectiles.get_tag_of(shot) == tag:
		chain = _rec_chain[shot]
		prev = _rec_prev[shot]
	var was: bool = _blasting
	_blasting = true
	_strike_round(spell, tag, actor, at, Vector2.RIGHT, radius, _blast_hit(spell, hit_profile(tag, shot)), true, chain, prev)
	_blasting = was


## Queues a launch `wait` seconds from now: `group` (a burst's later firing) or, with no group,
## `spell` (an echo). The queue grows as needed; nothing is dropped for room. A launch the wizard
## casts (`caster` CASTER_WIZARD: the cast's later firings) goes when its staff is rebuilt; any
## other (a payload of a shot or a point) keeps its build, as a shot in the air does, and fires.
func _delay(wait: float, group: CompiledGroup, spell: CompiledSpell, actor: int, staff: int, generation: int, origin: Vector2, heading: Vector2, source: Node, from_caster: bool) -> PendingLaunch:
	if _pending_free.is_empty():
		_pending_free.append(PendingLaunch.new())
	var launch: PendingLaunch = _pending_free.pop_back()
	launch.cost = 0
	launch.landing = null
	launch.echoed = false
	launch.again = false
	launch.seed = hash(Vector3i(_scatter.seed, roundi(wait * 1000.0), 0 if group != null else 1))
	launch.due = _clock + maxf(wait, 0.0)
	launch.actor = actor
	launch.staff = staff
	launch.generation = generation
	launch.group = group
	launch.spell = spell
	launch.origin = origin
	launch.heading = heading
	launch.source = source
	launch.anchor = Vector2.INF
	launch.caster = _caster
	launch.caster_seq = _caster_seq
	if from_caster and projectiles != null:
		launch.anchor = projectiles.get_anchor(actor)
	if launch.caster != CASTER_WIZARD:
		var key: int = SpellTag.generation_key(SpellTag.make(actor, staff, 0, generation))
		_generation_live[key] = _generation_live.get(key, 0) + 1
	_pending.append(launch)
	return launch


## Fires the queued launches that are due. A cast's later firing whose staff was rebuilt since is
## dropped (`_delay`). A cast's own launch starts as far from where it was cast as the caster has moved.
func _run_pending() -> void:
	var i: int = 0
	while i < _pending.size():
		var launch: PendingLaunch = _pending[i]
		if launch.due > _clock or launch.cost > 0:
			i += 1
			continue
		_pending.remove_at(i)
		if launch.caster == CASTER_WIZARD and _current[launch.actor * SpellLimits.STAFFS + launch.staff] != launch.generation:
			_release_launch(launch)
			continue
		var keeps: bool = launch.caster != CASTER_WIZARD
		var origin: Vector2 = launch.origin
		var from_caster: bool = launch.anchor.is_finite()
		if from_caster and projectiles != null:
			var now: Vector2 = projectiles.get_anchor(launch.actor)
			if now.is_finite():
				origin += now - launch.anchor
		# A payload's later firing is cast by its shot if that still flies, else from the point.
		var caster: int = launch.caster
		if caster >= 0 and not (projectiles.is_alive(caster) and projectiles.get_seq_of(caster) == launch.caster_seq):
			caster = CASTER_POINT
		var caster_seq: int = launch.caster_seq
		var source: Node = launch.source if is_instance_valid(launch.source) else null
		var group: CompiledGroup = launch.group
		var spell: CompiledSpell = launch.spell
		var actor: int = launch.actor
		var staff: int = launch.staff
		var generation: int = launch.generation
		var heading: Vector2 = launch.heading
		var landing: CompiledSpell = launch.landing
		var echoed: bool = launch.echoed
		var again: bool = launch.again
		_scatter.seed = launch.seed
		_release_launch(launch)
		var saved: int = _caster
		var saved_seq: int = _caster_seq
		_caster = caster
		_caster_seq = caster_seq
		if landing != null:
			_carrier_of(landing).land(landing, group, actor, staff, generation, origin, heading, echoed)
		elif group != null:
			_fire_group(group, actor, staff, generation, origin, heading, source, from_caster)
		elif not again:
			_fire_spell(spell, actor, staff, generation, origin, heading, source, from_caster, echoed)
		elif _hold_tags[actor * SpellLimits.STAFFS + staff].has(SpellTag.make(actor, staff, spell.node, generation)):
			# A held carrier cast again while it is on, along where its wizard aims now.
			if caster == CASTER_WIZARD and _aim_dir[actor].is_finite():
				heading = _aim_dir[actor]
			_fire_spell(spell, actor, staff, generation, origin, heading, source, from_caster, echoed, true)
		_caster = saved
		_caster_seq = saved_seq
		if keeps:
			_generation_gone(SpellTag.make(actor, staff, 0, generation))


## Gives a finished record back to the pool.
func _release_launch(launch: PendingLaunch) -> void:
	launch.cost = 0
	launch.group = null
	launch.spell = null
	launch.landing = null
	launch.source = null
	_pending_free.append(launch)


## Forgets the waiting launches `drops` picks (an edit, a switch-off or a closed caster; never
## per frame). One that kept its build (`_delay`) lets go of it; a rain's landing that goes takes
## the rain off the live carriers, so its timer ends with it.
func _drop_pending(drops: Callable) -> void:
	var i: int = _pending.size() - 1
	while i >= 0:
		var launch: PendingLaunch = _pending[i]
		if drops.call(launch):
			_pending.remove_at(i)
			if launch.landing != null:
				_lc_leave(SpellTag.make(launch.actor, launch.staff, launch.landing.node, launch.generation), false)
			var keeps: bool = launch.caster != CASTER_WIZARD
			var tag: int = SpellTag.make(launch.actor, launch.staff, 0, launch.generation)
			_release_launch(launch)
			if keeps:
				_generation_gone(tag)
		i -= 1


## True when `launch` fires a carrier with one of `tags` (its group's own carriers, its echo, or
## a rain of it landing).
func _fires_any(launch: PendingLaunch, tags: PackedInt64Array) -> bool:
	if launch.spell != null:
		return tags.has(SpellTag.make(launch.actor, launch.staff, launch.spell.node, launch.generation))
	if launch.landing != null and tags.has(SpellTag.make(launch.actor, launch.staff, launch.landing.node, launch.generation)):
		return true
	if launch.group != null:
		for spell in launch.group.spells:
			if tags.has(SpellTag.make(launch.actor, launch.staff, spell.node, launch.generation)):
				return true
	return false


## The cards that landed on the caster or on a payload's origin: a strike of everything there
## (`_strike_round`, `everyone`; a blast is as wide as its strength, and explodes).
func _fallback_hit(spell: CompiledSpell, tag: int, actor: int, at: Vector2) -> int:
	var blast: float = spell.behaviour(ModifierBase.Behaviour.BLAST)
	if blast > 0.0 and events != null and at.is_finite():
		events.cue_shown.emit(actor, spell.cue_of(ModifierBase.Behaviour.BLAST), at, Vector2.ZERO, blast, spell.tint, spell.look)
	if at.is_finite():
		_strike_round(spell, tag, actor, at, Vector2.RIGHT, maxf(spell.radius, blast), null, true)
	# After the strike, which can reach the caster itself and would spend the barrier.
	if _caster == CASTER_WIZARD:
		_moves.shield_caster(spell, tag, actor, 0.0)
	return 1


## Degrees (as radians) off the aim of shot `n` of `count`: none for one shot, an even ring
## for a 360 degree spread, otherwise an even fan centred on the aim.
func _fan_angle(n: int, count: int, spell: CompiledSpell) -> float:
	if count <= 1 or spell.has_trait(Carrier.RING):
		return 0.0
	if spell.spread >= 360.0:
		return TAU * n / count
	return deg_to_rad(spell.spread) * (float(n) / (count - 1) - 0.5)


## Radians a shot of `spell` (cast as `tag`) leaves off its line: random, up to its staff's
## `spread` degrees times the spell's `spread_mult` either side, from the generator seeded per
## cast (so the same cast spreads the same way). With no spread (the `dev` staff, or a factor of
## 0) it aims true and draws nothing from the generator.
func _staff_spread(tag: int, spell: CompiledSpell) -> float:
	var actor: int = SpellTag.caster_of(tag)
	var staff: int = SpellTag.staff_of(tag)
	if not _in_range(actor, staff):
		return 0.0
	var compiled: CompiledStaff = _installed[actor * SpellLimits.STAFFS + staff]
	if compiled == null or compiled.staff == null:
		return 0.0
	var degrees: float = compiled.staff.spread * spell.spread_mult
	if degrees <= 0.0:
		return 0.0
	return deg_to_rad(degrees) * (_scatter.randf() * 2.0 - 1.0)


## Gives the manager's shot in `slot` its record and counts it.
func _register(slot: int, tag: int, spell: CompiledSpell, chain: int, prev: int) -> void:
	projectiles.set_core(slot, spell.tint)
	projectiles.set_look(slot, spell.look)
	if _rec_seq.size() < projectiles.get_cap():
		var size: int = projectiles.get_cap()
		var old_size: int = _rec_seq.size()
		_rec_seq.resize(size)
		for at in range(old_size, size):
			_rec_seq[at] = -1
		_rec_chain.resize(size)
		_rec_prev.resize(size)
		_rec_zapper.resize(size)
		_rec_magnet.resize(size)
		_rec_zap_rolls.resize(size)
		_rec_zapped_count.resize(size)
		_rec_zapped.resize(size * ZAP_MEMORY)
		_rec_relay.resize(size)
		_rec_zap.resize(size)
	_rec_relay[slot] = spell.echo_hit if spell == _echo_spell else null
	_rec_zap[slot] = spell.echo_zap_hit if spell == _echo_spell else null
	if _caster != CASTER_WIZARD:
		# A payload's shot: an orbit circles the shot that cast it and a returning one flies back
		# to it, or to the point it was cast from.
		var shot: int = _caster_shot()
		if shot >= 0:
			projectiles.set_caster_shot(slot, shot)
		elif projectiles.is_cast_by_wizard(slot):
			projectiles.set_caster_point(slot, projectiles.get_position_of(slot))
	_rec_seq[slot] = projectiles.get_seq_of(slot)
	_rec_chain[slot] = chain
	_rec_prev[slot] = prev
	shot_started(tag)
	var life: float = projectiles.get_life_of(slot)
	var at: Vector2 = projectiles.get_position_of(slot)
	_lc_join(spell, tag, LC_SLOT, slot, projectiles.get_seq_of(slot), true, life, at, projectiles.get_velocity_of(slot))
	if spell.zap_chance > 0.0 and spell.zap_reach > 0.0:
		# A fresh shot: it has rolled for no body yet.
		_rec_zap_rolls[slot] = 0
		_rec_zapped_count[slot] = 0
		if _rec_zapper[slot] == 0:
			if _zapper_count == _zappers.size():
				_zappers.resize(_zappers.size() * 2)
			_zappers[_zapper_count] = slot
			_zapper_count += 1
			_rec_zapper[slot] = 1
	if spell.behaviour(ModifierBase.Behaviour.MAGNET) > 0.0 and _rec_magnet[slot] == 0:
		if _magnet_count == _magnets.size():
			_magnets.resize(_magnets.size() * 2)
		_magnets[_magnet_count] = slot
		_magnet_count += 1
		_rec_magnet[slot] = 1


## One beam (a chain jump of any ray): counted while it is cast, with its context set
## for the hit handler. It pierces as its carrier does and passes walls with ghost.
func _shoot_ray(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, heading: Vector2, chain: int, prev: int, source: Node, length: float = -1.0, hit: HitProfile = null) -> void:
	shot_started(tag)
	var ray: RayHit = _ray_begin(tag, heading, chain, prev, hit, -1)
	var reach: float = spell.ray_length if length < 0.0 else length
	var got: float = projectiles.ray(actor, origin, heading, reach, spell.pierce, HITS, tag, spell.radius * 0.5, source, _bounces(spell), _ghost(spell))
	var end: Vector2 = origin + heading * got
	var end_heading: Vector2 = heading
	if got > 0.0 and (spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0 or spell.behaviour(ModifierBase.Behaviour.SHIELD) > 0.0):
		_ray_guard_points[0] = origin
		_ray_guard_points[1] = end
		var count: int = 2
		if projectiles.ray_path_count > 2:
			count = mini(projectiles.ray_path_count, _ray_guard_points.size())
			for n in count:
				_ray_guard_points[n] = projectiles.ray_path[n]
		_guard_path(spell, tag, actor, _ray_guard_points, 0, count, got, spell.radius * 0.5, roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD)))
	if got > 0.0 and projectiles.ray_path_count > 2:
		# It turned at walls: a cue for every straight leg, and it ends where the last one does.
		end = projectiles.ray_end
		end_heading = projectiles.ray_end_heading
		if events != null:
			for n in projectiles.ray_path_count - 1:
				var from: Vector2 = projectiles.ray_path[n]
				var to: Vector2 = projectiles.ray_path[n + 1]
				if not from.is_equal_approx(to):
					events.form_shown.emit(actor, RAY_FORM, from, from.direction_to(to), from.distance_to(to), spell.tint, spell.look)
	elif got > 0.0 and events != null:
		events.form_shown.emit(actor, RAY_FORM, origin, heading, got, spell.tint, spell.look)
	# A `ray()` that did nothing (too deep, or a bad aim) has no end to fire the payload from.
	if got > 0.0:
		_blast(spell, tag, actor, end)
	if got > 0.0 and spell.payload != null and spell.trigger_event == TriggerBase.Event.EXPIRE:
		_fire_payload(spell, tag, actor, end, end_heading, null)
	_ray_end()
	shot_ended(tag)
	_cast_jumps()


## The shots of other teams touching the path `points[first]` to `points[first + count - 1]`
## (cut `reach` pixels along) of a beam with `tag`, `width` pixels either side as its
## hits: each is deflected off the line (`deflect`), else stopped while `charges` last (melee
## I3). Returns the charges left.
func _guard_path(spell: CompiledSpell, tag: int, actor: int, points: PackedVector2Array, first: int, count: int, reach: float, width: float, charges: int) -> int:
	var deflects: bool = spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0
	if (not deflects and charges <= 0) or count < 2 or reach <= 0.0:
		return charges
	var walked: float = 0.0
	for n in range(first, first + count - 1):
		var a: Vector2 = points[n]
		var b: Vector2 = points[n + 1]
		var piece: float = a.distance_to(b)
		if walked + piece > reach:
			b = a.move_toward(b, reach - walked)
		var found: int = projectiles.shots_on_segment(actor, a, b, width)
		charges = _guard(found, actor, tag, deflects, charges, a, b, RAY_FORM)
		walked += piece
		if walked >= reach or (not deflects and charges <= 0):
			break
	return charges


## Deflects (with `deflects`) or stops (while `charges` last) the `found` shots of
## `Projectiles.guard_slots` that touched a carrier of `actor` with `tag`: outward from `a` when
## `b` is INF (a swing's hand), else off the segment from `a` to `b` (a beam's line);
## a block is sent as `form`'s, the carrier's id (`block_shot`: Feel tells a swing's parry by it).
## Returns the charges left. The list is copied first: what a deflect sets off can run another guard.
func _guard(found: int, actor: int, tag: int, deflects: bool, charges: int, a: Vector2, b: Vector2, form: StringName) -> int:
	if found == 0:
		return charges
	var slots: PackedInt32Array = projectiles.guard_slots.slice(0, found)
	for slot in slots:
		if not projectiles.is_alive(slot):
			continue
		var at: Vector2 = projectiles.get_position_of(slot)
		if deflects:
			var from: Vector2 = a if not b.is_finite() else Geometry2D.get_closest_point_to_segment(at, a, b)
			var normal: Vector2 = at - from
			if normal.is_zero_approx():
				normal = -projectiles.get_velocity_of(slot)
			projectiles.deflect_shot(slot, actor, normal, tag)
		elif charges > 0:
			charges -= 1
			projectiles.block_shot(slot, actor, tag, form)
	return charges


## How many times `spell`'s beam turns at a wall: its bounce cards' count.
func _bounces(spell: CompiledSpell) -> int:
	return roundi(spell.behaviour(ModifierBase.Behaviour.BOUNCE))


## True when `spell`'s rays pass through walls (ghost), as its shots do.
static func _ghost(spell: CompiledSpell) -> bool:
	return spell.behaviour(ModifierBase.Behaviour.GHOST) > 0.0


## Where `actor`'s wizard holds its staffs now: the staff tip (`origin`) and the aim. The actor
## calls it every physics step, so a beam the wizard casts follows the aim while it lives.
## `pivot` is the hand the staff hangs from (what a swing turns round); left out, swings turn
## round the tip.
func set_aim(actor: int, origin: Vector2, direction: Vector2, pivot: Vector2 = Vector2.INF) -> void:
	if actor < 0 or actor >= ACTORS or not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx():
		return
	_aim_origin[actor] = origin
	_aim_dir[actor] = direction.normalized()
	_aim_seen[actor] = 1
	_aim_pivot[actor] = pivot if pivot.is_finite() else Vector2.INF


## `actor`'s wizard holds nothing any more (down, or gone): its beams end.
func clear_aim(actor: int) -> void:
	if actor < 0 or actor >= ACTORS:
		return
	_aim_origin[actor] = Vector2.INF
	_aim_dir[actor] = Vector2.INF


## Casts the queued beam jumps, if this is the outermost beam. Each jump's own jumps join the
## end of the queue, so the chain runs as a loop, one `ray()` deep per jump.
func _cast_jumps() -> void:
	if _jq_busy:
		return
	_jq_busy = true
	while _jq_count > 0:
		var at: int = _jq_head
		_jq_head = (_jq_head + 1) % _jq_spell.size()
		_jq_count -= 1
		var spell: CompiledSpell = _jq_spell[at]
		var target: Node2D = _jq_target[at]
		var hit: HitProfile = _jq_hit[at]
		_jq_spell[at] = null
		_jq_target[at] = null
		_jq_hit[at] = null
		if spell == null or not is_instance_valid(target):
			continue
		_shoot_ray(spell, _jq_tag[at], _jq_actor[at], _jq_pos[at], _jq_dir[at], _jq_chain[at], _jq_prev[at], target, _jq_len[at], hit)
	_jq_busy = false


## Doubles the beam jump ring, its waiting jumps first in the same order.
func _grow_jumps() -> void:
	var size: int = _jq_spell.size()
	var spells: Array[CompiledSpell] = []
	var targets: Array[Node2D] = []
	var tags := PackedInt64Array()
	var actors := PackedInt32Array()
	var places := PackedVector2Array()
	var dirs := PackedVector2Array()
	var lengths := PackedFloat32Array()
	var chains := PackedInt32Array()
	var prevs := PackedInt64Array()
	var hits: Array[HitProfile] = []
	for n in size * 2:
		var at: int = (_jq_head + n) % size
		var kept: bool = n < _jq_count
		spells.append(_jq_spell[at] if kept else null)
		targets.append(_jq_target[at] if kept else null)
		tags.append(_jq_tag[at] if kept else 0)
		actors.append(_jq_actor[at] if kept else 0)
		places.append(_jq_pos[at] if kept else Vector2.ZERO)
		dirs.append(_jq_dir[at] if kept else Vector2.ZERO)
		lengths.append(_jq_len[at] if kept else 0.0)
		chains.append(_jq_chain[at] if kept else 0)
		prevs.append(_jq_prev[at] if kept else 0)
		hits.append(_jq_hit[at] if kept else null)
	_jq_spell = spells
	_jq_target = targets
	_jq_tag = tags
	_jq_actor = actors
	_jq_pos = places
	_jq_dir = dirs
	_jq_len = lengths
	_jq_chain = chains
	_jq_prev = prevs
	_jq_hit = hits
	_jq_head = 0


## Fires the payload of `spell` (whose shot has `tag`) from `at` along `heading`, in the same
## actor's staff and generation as the shot.
## Fires the payload of `spell` from `at`. Its caster is the shot in `slot` that fired it while
## that shot still flies, otherwise the point `at` (see `_caster`).
func _fire_payload(spell: CompiledSpell, tag: int, actor: int, at: Vector2, heading: Vector2, source: Node, slot: int = -1) -> void:
	_fire(spell.payload, actor, SpellTag.staff_of(tag), SpellTag.generation_of(tag), at, heading, source, slot if slot >= 0 else CASTER_POINT)


## A trigger fires `group`: now, when this step's budget (`fire_shots_per_step` shots for the
## caster's budget: every actor no seat drives shares one) has room or nothing has fired from it
## yet, else it waits for the next step's room, oldest first (`_run_waiting_fires`), and is cast
## then by `caster` if that shot still flies, else from the point. Nothing is dropped (owner,
## 2026-10-29). With `from_caster` (`on cast`) it leaves as the cast's own launch does.
func _fire(group: CompiledGroup, actor: int, staff: int, generation: int, at: Vector2, heading: Vector2, source: Node, caster: int, from_caster: bool = false) -> void:
	if group == null or group.is_empty():
		return
	var cost: int = _shots_of(group)
	var budget: int = _budget(actor)
	if _fires_used[budget] > 0 and _fires_used[budget] + cost > fire_shots_per_step:
		var saved: int = _caster
		var saved_seq: int = _caster_seq
		if not from_caster:
			_caster = caster if caster >= 0 and projectiles.is_alive(caster) else CASTER_POINT
			_caster_seq = projectiles.get_seq_of(caster) if _caster >= 0 else 0
		var launch: PendingLaunch = _delay(0.0, group, null, actor, staff, generation, at, heading, source, from_caster)
		launch.cost = cost
		_caster = saved
		_caster_seq = saved_seq
		fires_waited += 1
		return
	_fires_used[budget] += cost
	fires_made += 1
	if from_caster:
		_launch_group(group, actor, staff, generation, at, heading, source, true)
	else:
		_launch_as(group, actor, staff, generation, at, heading, source, caster)


## The shots one firing of `group` makes, at least 1 for each carrier (a beam, a move, an area).
func _shots_of(group: CompiledGroup) -> int:
	var shots: int = 0
	for spell in group.spells:
		shots += maxi(spell.shots, 1)
	return maxi(shots, 1)


## The fires that waited for room (`_fire`), oldest first, while their budget has room in this
## step; a cast's own (`on cast`) whose staff was rebuilt since is dropped (`_delay`).
func _run_waiting_fires() -> void:
	var i: int = 0
	while i < _pending.size():
		var launch: PendingLaunch = _pending[i]
		if launch.cost <= 0:
			i += 1
			continue
		var budget: int = _budget(launch.actor)
		if _fires_used[budget] > 0 and _fires_used[budget] + launch.cost > fire_shots_per_step:
			i += 1
			continue
		_pending.remove_at(i)
		if launch.caster == CASTER_WIZARD and _current[launch.actor * SpellLimits.STAFFS + launch.staff] != launch.generation:
			_release_launch(launch)
			continue
		var keeps: bool = launch.caster != CASTER_WIZARD
		_fires_used[budget] += launch.cost
		fires_made += 1
		var origin: Vector2 = launch.origin
		var from_caster: bool = launch.anchor.is_finite()
		if from_caster and projectiles != null:
			var now: Vector2 = projectiles.get_anchor(launch.actor)
			if now.is_finite():
				origin += now - launch.anchor
		var caster: int = launch.caster
		if caster >= 0 and not (projectiles.is_alive(caster) and projectiles.get_seq_of(caster) == launch.caster_seq):
			caster = CASTER_POINT
		var source: Node = launch.source if is_instance_valid(launch.source) else null
		var group: CompiledGroup = launch.group
		var actor: int = launch.actor
		var staff: int = launch.staff
		var generation: int = launch.generation
		var heading: Vector2 = launch.heading
		_scatter.seed = launch.seed
		_release_launch(launch)
		if from_caster:
			var saved: int = _caster
			var saved_seq: int = _caster_seq
			_caster = caster
			_caster_seq = launch.caster_seq
			_launch_group(group, actor, staff, generation, origin, heading, source, true)
			_caster = saved
			_caster_seq = saved_seq
		else:
			_launch_as(group, actor, staff, generation, origin, heading, source, caster)
		if keeps:
			_generation_gone(SpellTag.make(actor, staff, 0, generation))


## True when the record of `slot` was made for the shot the manager last had there (it may
## have ended just now).
func _same(slot: int) -> bool:
	return slot >= 0 and slot < _rec_seq.size() and _rec_seq[slot] == projectiles.get_seq_of(slot)


## True when `slot` holds a live shot this record was made for.
func _knows(slot: int) -> bool:
	return _same(slot) and projectiles.is_alive(slot)


## The way a payload fired by a shot goes: its velocity, or outward from the shot's caster
## through the shot for an orbit or still one (or one with no velocity).
func _heading(spell: CompiledSpell, slot: int, at: Vector2, actor: int) -> Vector2:
	var velocity: Vector2 = projectiles.get_velocity_of(slot)
	if spell.has_trait(Carrier.OUTWARD) or velocity.is_zero_approx():
		var anchor: Vector2 = projectiles.get_caster_of(slot) if slot >= 0 else projectiles.get_anchor(actor)
		if anchor.is_finite() and not (at - anchor).is_zero_approx():
			return (at - anchor).normalized()
	return Vector2.RIGHT if velocity.is_zero_approx() else velocity.normalized()


## When a carrier that lives `life` seconds first does what it does every `interval` (a timer's
## tick, an arc's zap): after the interval, or half its life when that is shorter, so a short
## carrier (a swap, a nova, a beam) does it once before it ends (owner, 2026-10-29).
static func first_tick(interval: float, life: float) -> float:
	return minf(interval, life * 0.5)


## Lists a carrier of `tag` that lasts, when it has a `timer` or `on hurt` trigger (see `_lc_tag`):
## `kind` and `ref` (with `seq`, the row's birth) say where it is, `tied` that it ends with that
## row, else it lives `life` seconds; `at` is where it starts and `way` its way.
func _lc_join(spell: CompiledSpell, tag: int, kind: int, ref: int, seq: int, tied: bool, life: float, at: Vector2, way: Vector2) -> void:
	if spell.payload == null or (spell.trigger_event != TriggerBase.Event.TIMER and spell.trigger_event != TriggerBase.Event.HURT):
		return
	if _lc_count == _lc_tag.size():
		_lc_grow(_lc_count * 2)
	var i: int = _lc_count
	_lc_count += 1
	_lc_tag[i] = tag
	_lc_kind[i] = kind
	_lc_ref[i] = ref
	_lc_seq[i] = seq
	_lc_tied[i] = 1 if tied else 0
	_lc_left[i] = INF if tied else life
	_lc_clock[i] = first_tick(spell.trigger_interval, life)
	_lc_at[i] = at
	_lc_way[i] = way.normalized() if way.is_finite() and not way.is_zero_approx() else Vector2.RIGHT


func _lc_grow(size: int) -> void:
	_lc_tag.resize(size)
	_lc_kind.resize(size)
	_lc_ref.resize(size)
	_lc_seq.resize(size)
	_lc_tied.resize(size)
	_lc_left.resize(size)
	_lc_clock.resize(size)
	_lc_at.resize(size)
	_lc_way.resize(size)


## Takes live carrier `i` off the list (the last one takes its place).
func _lc_remove(i: int) -> void:
	_lc_count -= 1
	_lc_tag[i] = _lc_tag[_lc_count]
	_lc_kind[i] = _lc_kind[_lc_count]
	_lc_ref[i] = _lc_ref[_lc_count]
	_lc_seq[i] = _lc_seq[_lc_count]
	_lc_tied[i] = _lc_tied[_lc_count]
	_lc_left[i] = _lc_left[_lc_count]
	_lc_clock[i] = _lc_clock[_lc_count]
	_lc_at[i] = _lc_at[_lc_count]
	_lc_way[i] = _lc_way[_lc_count]


## A carrier of `tag` that is not tied to a row ended (an entity): one of its entries leaves, or
## with `every` all of them (its build was revoked).
func _lc_leave(tag: int, every: bool) -> void:
	var i: int = _lc_count - 1
	while i >= 0:
		if _lc_tag[i] == tag and _lc_tied[i] == 0:
			_lc_remove(i)
			if not every:
				return
		i -= 1


## Where live carrier `i` is now, or `Vector2.INF` when the row it follows is gone.
func _lc_where(i: int) -> Vector2:
	var ref: int = _lc_ref[i]
	match _lc_kind[i]:
		LC_SLOT:
			return projectiles.get_position_of(ref) if projectiles.get_seq_of(ref) == _lc_seq[i] else Vector2.INF
		LC_ROW:
			var spell: CompiledSpell = _profiles.get(_lc_tag[i])
			return _carrier_of(spell).tip_of(ref, _lc_seq[i]) if spell != null else Vector2.INF
		LC_ACTOR:
			return projectiles.get_anchor(ref)
	return _lc_at[i]


## Runs the live carriers on by `delta`: each that ended leaves the list, each timer whose clock
## runs out fires its payload from where its carrier is. Payloads may list more carriers; they
## run from this step on.
func _step_live(delta: float) -> void:
	var i: int = 0
	while i < _lc_count:
		var spell: CompiledSpell = _profiles.get(_lc_tag[i])
		var at: Vector2 = _lc_where(i)
		_lc_left[i] -= delta
		if spell == null or _lc_left[i] <= 0.0 or (_lc_tied[i] == 1 and not at.is_finite()):
			_lc_remove(i)
			continue
		if at.is_finite():
			_lc_at[i] = at
		if spell.trigger_event == TriggerBase.Event.TIMER:
			_lc_clock[i] -= delta
			if _lc_clock[i] <= 0.0:
				_lc_clock[i] += spell.trigger_interval
				_lc_fire(i, spell, _lc_at[i])
		i += 1


## Fires the payload of live carrier `i` from `from`, along its way where it is: a shot's own
## (`_heading`), else outward from its caster's body through it, else its `_lc_way`. Its shot casts
## the payload while it flies, else the point does.
func _lc_fire(i: int, spell: CompiledSpell, from: Vector2) -> void:
	var tag: int = _lc_tag[i]
	var actor: int = SpellTag.caster_of(tag)
	var at: Vector2 = _lc_at[i]
	var slot: int = _lc_ref[i]
	if _lc_kind[i] != LC_SLOT or not projectiles.is_alive(slot) or projectiles.get_seq_of(slot) != _lc_seq[i]:
		slot = -1
	var way: Vector2 = _lc_way[i]
	if slot >= 0:
		way = _heading(spell, slot, at, actor)
	else:
		var body: Vector2 = projectiles.get_anchor(actor)
		if body.is_finite() and not (at - body).is_zero_approx():
			way = (at - body).normalized()
	_fire_payload(spell, tag, actor, from, way, null, slot)


## Runs the `zap` shots (half of them each step, SpellLimits.ZAP_EVERY): each body of another team
## that has come within a shot's reach since it last looked rolls the shot's chance, once, and on a
## win is zapped at once (`_zap`), the body the shot is about to hit too (owner, 2026-10-30). At
## most `SpellLimits.MAX_ZAPS_PER_STEP` zaps a step; a body over the cap rolls in a later step. A
## shot with no body in reach now and then throws a spark into the air (`_spark`).
func _step_zaps(delta: float) -> void:
	_zaps_used = 0
	_zap_steps += 1
	var i: int = 0
	while i < _zapper_count:
		var slot: int = _zappers[i]
		if not _knows(slot):
			_rec_zapper[slot] = 0
			_zapper_count -= 1
			_zappers[i] = _zappers[_zapper_count]
			continue
		i += 1
		if (slot + _zap_steps) % SpellLimits.ZAP_EVERY != 0:
			continue
		var tag: int = projectiles.get_tag_of(slot)
		var spell: CompiledSpell = _profiles.get(tag)
		if spell == null or spell.zap_chance <= 0.0:
			continue
		var at: Vector2 = projectiles.get_position_of(slot)
		var near: int = projectiles.targets_near(at, spell.zap_reach, HITS, _team(SpellTag.caster_of(tag)), _zap_near, _zap_centres)
		if near == 0:
			if _zaps_used < SpellLimits.MAX_ZAPS_PER_STEP and _zap_roll(slot) < SpellLimits.ZAP_SPARKS * delta * SpellLimits.ZAP_EVERY:
				_spark(slot, spell)
			continue
		for k in near:
			if _zaps_used >= SpellLimits.MAX_ZAPS_PER_STEP or not _knows(slot):
				break
			var body: Node2D = _zap_near[k]
			if not is_instance_valid(body) or _has_rolled(slot, body.get_instance_id()):
				continue
			_rolled(slot, body.get_instance_id())
			if _zap_roll(slot) < spell.zap_chance:
				_zap(slot, spell, _zap_centres[k])


## True when the zap shot in `slot` has rolled for the body of instance id `id`.
func _has_rolled(slot: int, id: int) -> bool:
	var first: int = slot * ZAP_MEMORY
	for n in mini(_rec_zapped_count[slot], ZAP_MEMORY):
		if _rec_zapped[first + n] == id:
			return true
	return false


## The zap shot in `slot` has rolled for the body of instance id `id` (in a ring: past ZAP_MEMORY
## the oldest is forgotten).
func _rolled(slot: int, id: int) -> void:
	var n: int = _rec_zapped_count[slot]
	_rec_zapped[slot * ZAP_MEMORY + n % ZAP_MEMORY] = id
	_rec_zapped_count[slot] = n + 1


## A random number in [0, 1) for the zap shot in `slot`: a hash of its sequence number and how many
## it drew before, so a run is the same every time (tests, replays) and no two shots alike.
func _zap_roll(slot: int) -> float:
	var n: int = _rec_zap_rolls[slot]
	_rec_zap_rolls[slot] = n + 1
	var h: int = (int(projectiles.get_seq_of(slot)) * 73856093) ^ (n * 19349663) ^ 83492791
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0


## The zap shot in `slot` throws a harmless spark into the air: a short zap's look in a random
## direction (it has no body in reach).
func _spark(slot: int, spell: CompiledSpell) -> void:
	if events == null:
		return
	var way: Vector2 = Vector2.from_angle(_zap_roll(slot) * TAU)
	var length: float = lerpf(SpellLimits.ZAP_SPARK_SHORTEST, SpellLimits.ZAP_SPARK_LONGEST, _zap_roll(slot))
	_zaps_used += 1
	events.form_shown.emit(SpellTag.caster_of(projectiles.get_tag_of(slot)), ZAP_FORM, projectiles.get_position_of(slot), way, length, spell.tint, spell.look)


## Every `magnet` shot pulls the enemies within its card's reach toward where it is, each step
## (`pull_requested`; combat keeps the pull as a push that the next pull replaces); a carrier with
## rows of its own pulls with them in its `step` (a live beam toward its line). At most
## `SpellLimits.MAX_PULLS_PER_STEP` shots pull in a step; which ones rotates, so none starves.
func _step_magnets() -> void:
	var i: int = 0
	while i < _magnet_count:
		var slot: int = _magnets[i]
		var spell: CompiledSpell = null
		if _knows(slot):
			spell = _profiles.get(projectiles.get_tag_of(slot))
		# A slot that a spent magnet shot left to a shot without the card goes off the list, too.
		if spell == null or spell.behaviour(ModifierBase.Behaviour.MAGNET) <= 0.0:
			_rec_magnet[slot] = 0
			_magnet_count -= 1
			_magnets[i] = _magnets[_magnet_count]
			continue
		i += 1
	if _magnet_count == 0:
		return
	var pulls: int = mini(_magnet_count, SpellLimits.MAX_PULLS_PER_STEP)
	for k in pulls:
		var slot: int = _magnets[(_magnet_from + k) % _magnet_count]
		var tag: int = projectiles.get_tag_of(slot)
		var spell: CompiledSpell = _profiles.get(tag)
		var at: Vector2 = projectiles.get_position_of(slot)
		events.pull_requested.emit(SpellTag.caster_of(tag), at, spell.behaviour(ModifierBase.Behaviour.MAGNET), SpellLimits.MAGNET_PULL, tag, at)
	_magnet_from = (_magnet_from + pulls) % _magnet_count


## Shot `slot`'s zap of the body whose hit circle is at `aim`: a short ray there, hitting with its
## `zap_hit` (`hit_profile`). It is a hit of the shot like any other: it uses the shot's trigger
## fires and chain jumps, so `on hit` payloads and chains go off from the zapped body.
func _zap(slot: int, spell: CompiledSpell, aim: Vector2) -> void:
	var tag: int = projectiles.get_tag_of(slot)
	var at: Vector2 = projectiles.get_position_of(slot)
	var actor: int = SpellTag.caster_of(tag)
	_zaps_used += 1
	var way: Vector2 = at.direction_to(aim) if not at.is_equal_approx(aim) else Vector2.RIGHT
	var ray: RayHit = _ray_begin(tag, way, _rec_chain[slot], _rec_prev[slot], _rec_zap[slot] if _rec_zap[slot] != null else spell.zap_hit, slot)
	var got: float = projectiles.ray(actor, at, way, at.distance_to(aim) + 2.0, 0, HITS, tag, 0.0, null)
	_ray_end()
	if got > 0.0 and events != null:
		events.form_shown.emit(actor, ZAP_FORM, at, way, got, spell.tint, spell.look)
	_cast_jumps()


func _on_hit(actor: int, target: Node, position: Vector2, tag: int, shot: int) -> void:
	if not SpellTag.is_spell_tag(tag):
		return
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null:
		return
	# `relay` takes on what the actor hit last cast, before Combat reads this hit's profile (Spells
	# hears `projectile_hit` first: its autoload comes before Combat's).
	_relay(target, tag, shot)
	var slot: int = shot
	var chain: int = spell.chain_jumps
	var prev: int = 0
	var heading: Vector2 = Vector2.RIGHT
	var by_ray: bool = slot < 0
	if by_ray:
		if tag != _ray.tag:
			return
		chain = _ray.chain
		prev = _ray.prev
		heading = _ray.dir
	else:
		if _same(slot):
			chain = _rec_chain[slot]
			prev = _rec_prev[slot]
		heading = _heading(spell, slot, position, actor)
	# A chain goes on hitting as the hit it jumps from did (an echo's half, a relay's merge); a
	# zap's jumps as its shot does.
	var carried: HitProfile = null
	var carried_zap: HitProfile = null
	var from: int = _ray.zap_slot if by_ray else slot
	if from >= 0 and _same(from):
		carried = _rec_relay[from]
		carried_zap = _rec_zap[from]
	elif by_ray:
		carried = _ray.hit
	var held: bool = spell.payload != null and spell.trigger_event == TriggerBase.Event.HIT
	var struck: int = target.get_instance_id()
	_on_hit_effects(spell, tag, actor, target, position, slot)
	if held:
		_fire_payload(spell, tag, actor, position, heading, target, slot)
	if chain > 0:
		_jump(spell, tag, actor, position, target as Node2D, struck, prev, chain - 1, by_ray, carried, carried_zap)


## What a hit of a carrier does besides its payload and chain: siphon refunds mana, possess takes
## the target, `pull` pulls its caster to the hit (`CasterMoves.pull`), the carrier's own part runs
## (`Carrier.on_hit`: a swap's trade), and a spent shot's `blast` goes off (a beam's waits for its
## end, a pulling shot's for the arrival). What a blast strikes moves nothing (that would move
## again at every arrival, rules R4 F2): only the carrier's own hits do (`_blasting`).
func _on_hit_effects(spell: CompiledSpell, tag: int, actor: int, target: Node, position: Vector2, slot: int) -> void:
	var refund: float = spell.behaviour(ModifierBase.Behaviour.SIPHON)
	if refund > 0.0:
		_refund(actor, refund)
	var possess: float = spell.behaviour(ModifierBase.Behaviour.POSSESS)
	if possess > 0.0:
		_possess(actor, target, possess, tag)
	var spent: bool = slot >= 0 and not projectiles.is_alive(slot)
	var pulled: bool = false
	if not _blasting:
		if spell.behaviour(ModifierBase.Behaviour.PULL) > 0.0:
			pulled = _moves.pull(spell, tag, actor, position, slot, spent)
		_carrier_of(spell).on_hit(spell, tag, actor, target, position, slot)
	# A spent shot's blast goes off where it hit; a pulling one's waits for the arrival.
	if spent and not pulled:
		_blast(spell, tag, actor, position, slot)


## `possess` (actors G9; owner, 2026-10-29): every actor a carrier with it hits is possessed for
## `seconds` (`possess_requested`; the actor kit adds it to the caster's controller's bodies and
## skips one that is already its). A target no actor owns, and the caster's own body, are not.
func _possess(actor: int, target: Node, seconds: float, tag: int) -> void:
	if events == null or not is_instance_valid(target) or actor < 0 or actor >= ACTORS:
		return
	var victim: int = projectiles.target_owner_of(target)
	if victim < 0 or victim >= ACTORS or victim == actor:
		return
	events.possess_requested.emit(actor, victim, seconds, tag)


## Sends a chain on from `position` to the nearest other target, if there is one in range. The
## jump hits with `hit` and zaps with `zap` (null: the spell's own), as the hit it came from did.
func _jump(spell: CompiledSpell, tag: int, actor: int, position: Vector2, target: Node2D, struck: int, prev: int, chain: int, by_ray: bool, hit: HitProfile = null, zap: HitProfile = null) -> void:
	var before: Node2D = null
	if prev != 0:
		before = instance_from_id(prev) as Node2D
	var best: Node2D = projectiles.nearest_target(position, SpellLimits.CHAIN_RANGE, HITS, target, before, _team(actor))
	if best == null:
		return
	var aim: Vector2 = projectiles.nearest_point
	if not aim.is_finite() or aim.is_equal_approx(position):
		return
	var along: Vector2 = position.direction_to(aim)
	var distance: float = position.distance_to(aim)
	if by_ray:
		if _jq_count >= _jq_spell.size():
			_grow_jumps()
		var end: int = (_jq_head + _jq_count) % _jq_spell.size()
		_jq_count += 1
		_jq_spell[end] = spell
		_jq_target[end] = target
		_jq_tag[end] = tag
		_jq_actor[end] = actor
		_jq_pos[end] = position
		_jq_dir[end] = along
		_jq_len[end] = distance + spell.radius + 8.0
		_jq_chain[end] = chain
		_jq_prev[end] = struck
		_jq_hit[end] = hit
		return
	# A flying jump is its carrier fired again from the hit (rules R1b, rule 2): every card it has
	# (homing, bounce, ghost, spiral, linger, growth, sticky, return, shield, pierce, arc, magnet,
	# its trigger), one jump fewer. Only its aim, its source exclusion and its speed (at least
	# CHAIN_MIN_SPEED, for a carrier that does not fly) differ; it flies as far as its carrier
	# would, and at least far enough to reach the target.
	var speed: float = maxf(spell.speed, SpellLimits.CHAIN_MIN_SPEED)
	var life: float = maxf((distance + 16.0) / speed * 1.5 + 0.05, spell.lifetime * spell.speed / speed)
	var slot: int = projectiles.spawn(actor, position, along * speed, life, spell.radius, HITS, spell.pierce, tag)
	if slot < 0:
		return
	_apply_travel(slot, spell)
	_register(slot, tag, spell, chain, struck)
	_rec_relay[slot] = hit
	_rec_zap[slot] = zap
	projectiles.exclude(slot, target, SpellLimits.SOURCE_EXCLUSION)


func _on_expired(actor: int, position: Vector2, tag: int, shot: int) -> void:
	var event: int = TriggerBase.Event.EXPIRE
	var spell: CompiledSpell = _profiles.get(tag)
	if spell != null and spell.trigger_event == TriggerBase.Event.WALL and projectiles.expired_on_wall:
		event = TriggerBase.Event.WALL
	# Every carrier blasts at its end point (rules R1d): a pulling shot that missed, where it ended.
	if spell != null:
		_blast(spell, tag, actor, position, shot)
	_fire_event(event, actor, position, tag, null, shot, true)


## `on wall` at every wall that does not end the shot (a bounce) and at every wall a beam
## turns at or ends on (owner, 2026-10-29); a shot's last wall is `_on_expired`'s. The
## payload goes the way the shot or beam goes on. A zap (`_zap`, its shot's tag) that ends on a
## wall is not its shot meeting one: it sets off nothing (rules R4a).
func _on_wall_met(actor: int, position: Vector2, heading: Vector2, tag: int, shot: int) -> void:
	if _ray.zap_slot >= 0:
		return
	_fire_event(TriggerBase.Event.WALL, actor, position, tag, null, shot, false, heading)


func _on_shot_blocked(actor: int, position: Vector2, tag: int, shot: int) -> void:
	_fire_event(TriggerBase.Event.BLOCK, actor, position, tag, null, shot)


func _on_shield_blocked(actor: int, position: Vector2, tag: int) -> void:
	# A barrier on the caster blocks: no shot of this carrier is part of it.
	_fire_event(TriggerBase.Event.BLOCK, actor, position, tag, null, -1)


## A deflect is a block (owner, 2026-10-29): it sets off `on block` too.
func _on_shot_deflected(actor: int, position: Vector2, tag: int, shot: int) -> void:
	_fire_event(TriggerBase.Event.BLOCK, actor, position, tag, null, shot)


func _on_kill(actor: int, target: Node, position: Vector2, tag: int, shot: int) -> void:
	_fire_event(TriggerBase.Event.KILL, actor, position, tag, target if is_instance_valid(target) else null, shot)


func _on_reaction(actor: int, _reaction_id: StringName, target: Node, position: Vector2, tag: int, shot: int) -> void:
	_fire_event(TriggerBase.Event.REACTION, actor, position, tag, target if is_instance_valid(target) else null, shot)


## Fires the payload of the shot with `tag` from `at`, when that shot's trigger is `event` (the
## shared way of the events that name a shot's tag). When the event is being sent for that
## very shot (`shot`, the event's), its record limits how often it fires. `back_off` pulls the
## point out of a wall; `way`, when given, is the way the payload goes.
func _fire_event(event: int, actor: int, at: Vector2, tag: int, source: Node, shot: int, back_off: bool = false, way: Vector2 = Vector2.ZERO) -> void:
	if not SpellTag.is_spell_tag(tag):
		return
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null or spell.payload == null or spell.trigger_event != event:
		return
	var slot: int = shot
	if slot >= 0 and (not _same(slot) or projectiles.get_tag_of(slot) != tag):
		slot = -1
	# A beam has no slot: while its `ray()` runs, its payload goes along the beam.
	var by_ray: bool = slot < 0 and tag == _ray.tag
	var heading: Vector2 = way if not way.is_zero_approx() else (_ray.dir if by_ray else _heading(spell, slot, at, actor))
	if back_off:
		at -= heading * SpellLimits.EXPIRE_BACKOFF
	_fire_payload(spell, tag, actor, at, heading, source, slot)


## `on hurt`: every live carrier of the hurt actor with that trigger fires its payload from where
## the actor was hurt (a wizard or an enemy alike, actors G3b), whatever the carrier is (a shot, a
## beam, a dash, an entity...; `_lc_tag`).
func _on_hurt(actor: int, _amount: float, position: Vector2, _tag: int, _kind: StringName) -> void:
	if actor < 0 or actor >= ACTORS:
		return
	# Payloads may list more such carriers; they sit past `count` and wait for the next hurt.
	var count: int = _lc_count
	for i in count:
		var tag: int = _lc_tag[i]
		var spell: CompiledSpell = _profiles.get(tag)
		if spell == null or spell.trigger_event != TriggerBase.Event.HURT or SpellTag.caster_of(tag) != actor:
			continue
		var at: Vector2 = _lc_where(i)
		if at.is_finite():
			_lc_at[i] = at
		elif _lc_tied[i] == 1:
			continue
		_lc_fire(i, spell, position)


## `relay` (owner, 2026-10-28): a shot with it that hits any actor (a wizard, an enemy, a
## teammate, whoever) takes on the infusions of that actor's last cast that had one
## (`_last_infused`): their elements, each with its status, join this hit and its later ones,
## its zaps and its chain jumps. The rest of the hit stays as it was (heal, slam, damage, kind).
## An actor that never cast an infused carrier gives nothing. A ray with it (a beam or a
## jump of one; rules R4f) keeps what it took on in `_ray.hit` for its later hits, a live beam
## for as long as it is on (`_bm_hit`). Allocates two profiles per such hit, never per frame.
func _relay(target: Node, tag: int, shot: int) -> void:
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null or spell.behaviour(ModifierBase.Behaviour.RELAY) <= 0.0 or not is_instance_valid(target):
		return
	var donor_actor: int = projectiles.target_owner_of(target)
	if donor_actor < 0 or donor_actor >= ACTORS:
		return
	var slot: int = shot
	if slot < 0 and tag == _ray.tag:
		slot = _ray.zap_slot
	var by_ray: bool = slot < 0 and tag == _ray.tag
	var donor: CompiledSpell = _last_infused[donor_actor]
	if donor == null or (not by_ray and (slot < 0 or not _same(slot) or projectiles.get_tag_of(slot) != tag)):
		return
	var base: HitProfile = _ray.hit if by_ray else _rec_relay[slot]
	if base == null:
		base = spell.hit
	var merged: HitProfile = null
	for n in donor.hit.element_ids.size():
		var id: StringName = donor.hit.element_ids[n]
		if base.element_ids.has(id) or (merged != null and merged.element_ids.has(id)):
			continue
		if merged == null:
			merged = base.copy()
		_add_element(merged, donor.hit, n)
	if merged == null:
		return
	if by_ray:
		_ray.hit = merged
		return
	if base.element_id == &"":
		projectiles.set_core(slot, donor.tint)
	_rec_relay[slot] = merged
	_rec_zap[slot] = StaffCompiler.zap_hit(merged) if spell.zap_hit != null else null
	if slot == _ray.zap_slot:
		_ray.hit = _rec_zap[slot]


## Adds element `n` of `from` to `onto`, with its status (none if `from` has none for it), as
## its last element.
static func _add_element(onto: HitProfile, from: HitProfile, n: int) -> void:
	var id: StringName = &""
	var duration: float = 0.0
	var strength: float = 0.0
	if n == 0:
		id = from.status_id
		duration = from.status_duration
		strength = from.status_strength
	elif n - 1 < from.later_status_ids.size():
		id = from.later_status_ids[n - 1]
		duration = from.later_status_durations[n - 1]
		strength = from.later_status_strengths[n - 1]
	onto.element_ids.append(from.element_ids[n])
	if onto.element_ids.size() == 1:
		onto.element_id = from.element_ids[n]
		onto.status_id = id
		onto.status_duration = duration
		onto.status_strength = strength
		return
	var later: int = onto.element_ids.size() - 2
	while onto.later_status_ids.size() < later:
		onto.later_status_ids.append(&"")
		onto.later_status_durations.append(0.0)
		onto.later_status_strengths.append(0.0)
	onto.later_status_ids.append(id)
	onto.later_status_durations.append(duration)
	onto.later_status_strengths.append(strength)


## Forgets every registered spell and shot count (a new run, and tests).
func clear() -> void:
	_cooldown.fill(0.0)
	_fires_used.fill(0)
	_jq_head = 0
	_jq_count = 0
	_moves.clear()
	_caster = CASTER_WIZARD
	for carrier: Carrier in _carriers.values():
		carrier.clear()
	_poses.clear()
	_aim_pivot.fill(Vector2.INF)
	_aim_origin.fill(Vector2.INF)
	_aim_dir.fill(Vector2.INF)
	_aim_seen.fill(0)
	for launch in _pending:
		_release_launch(launch)
	_pending.clear()
	_ring.fill(-1)
	_last_form.fill(&"")
	_cast_count.fill(0)
	_lc_count = 0
	_zapper_count = 0
	_magnet_count = 0
	_magnet_from = 0
	_rec_magnet.fill(0)
	_rec_seq.fill(-1)
	_rec_zapper.fill(0)
	_rec_relay.fill(null)
	_rec_zap.fill(null)
	_jq_hit.fill(null)
	_last_infused.fill(null)
	fires_made = 0
	fires_waited = 0
	_current.fill(-1)
	_cursor.fill(0)
	_hold_mana.fill(0.0)
	for i in _installed.size():
		_installed[i] = null
		_hold_tags[i].clear()
	_node_counts.clear()
	_profiles.clear()
	_live.clear()
	_generation_live.clear()
	revoked_tags.clear()


## Opens the caster `actor` (an actor id a body opened in the actor table, actors G3b): its
## staffs, delays, aim and the rest start new, so it installs, casts and aims (`install_staff`,
## `cast_staff`, `set_aim`) from a clean row; generations go on round the ring, so shots of an
## earlier caster with the same id keep theirs. A body calls it once, before its first build.
## Returns false for an id outside the table.
func open_caster(actor: int) -> bool:
	if actor < 0 or actor >= ACTORS:
		return false
	# Whatever an earlier caster with this id left (builds, holds, beams, launches) goes first.
	close_caster(actor)
	return true


## The caster `actor` is gone (its body left or died): its staffs are emptied, its own waiting
## launches (a cast's later firings), holds and beams end. Its shots in the air fly on with their
## own numbers until they end, and their waiting payloads fire on, as after an edit. The body
## closes its actor id in the table itself.
func close_caster(actor: int) -> void:
	if actor < 0 or actor >= ACTORS:
		return
	_drop_pending(func(launch: PendingLaunch) -> bool: return launch.actor == actor and launch.caster == CASTER_WIZARD)
	for staff in SpellLimits.STAFFS:
		var index: int = actor * SpellLimits.STAFFS + staff
		_release_hold(index)
		var old: int = _current[index]
		_installed[index] = null
		_current[index] = -1
		if old >= 0:
			_release_generation(actor, staff, old)
	for carrier: Carrier in _carriers.values():
		carrier.end_actor(actor)
	_reset_caster(actor)


## The mana the next cast of this caster's staff costs (`cast_staff` refuses with less), 0.0
## while its sustained carriers are on (that press switches them off), or REFUSED when it has no
## build. An enemy's AI asks before it winds up, so a telegraph is always followed by its cast.
func next_cast_mana(actor: int, staff: int) -> float:
	if not _in_range(actor, staff):
		return REFUSED
	var index: int = actor * SpellLimits.STAFFS + staff
	var compiled: CompiledStaff = _installed[index]
	if compiled == null or compiled.is_empty():
		return REFUSED
	if not _hold_tags[index].is_empty():
		return 0.0
	return compiled.casts[mini(_cursor[index], compiled.casts.size() - 1)].mana


## True when the next cast of this actor's staff can leave within `within` seconds with `mana`:
## its delay is no longer than that, and `mana` less what its sustained carriers hold
## (`reserved_mana`) pays `next_cast_mana`. False with no build. One call for what an enemy's AI
## asks every step while its target is in reach (performance pass, 2026-10-28).
func cast_ready(actor: int, staff: int, within: float, mana: float) -> bool:
	if not _in_range(actor, staff):
		return false
	var index: int = actor * SpellLimits.STAFFS + staff
	if _cooldown[index] > within:
		return false
	var compiled: CompiledStaff = _installed[index]
	if compiled == null or compiled.is_empty():
		return false
	var cost: float = 0.0
	if _hold_tags[index].is_empty():
		cost = compiled.casts[mini(_cursor[index], compiled.casts.size() - 1)].mana
	var first: int = actor * SpellLimits.STAFFS
	var reserved: float = 0.0
	for at in SpellLimits.STAFFS:
		reserved += _hold_mana[first + at]
	return maxf(mana - reserved, 0.0) >= cost


## How far the next cast of this caster's staff reaches along its aim, for an enemy's telegraph:
## its first carrier's flight (speed x life), a beam's or swing's length, a rain's aim point;
## 0 for one that is not aimed (a nova's ring, an orbit, a still shot, a decoy...) or no build.
func next_cast_reach(actor: int, staff: int) -> float:
	var first: CompiledSpell = _next_carrier(actor, staff)
	if first == null:
		return 0.0
	return _carrier_of(first).reach_of(first)


## The hit radius of the next cast's first carrier (0 for none), for the width of a telegraph.
func next_cast_radius(actor: int, staff: int) -> float:
	var first: CompiledSpell = _next_carrier(actor, staff)
	return first.radius if first != null else 0.0


## The first carrier of the next cast of this staff, or null (no build, or nothing in the cast).
func _next_carrier(actor: int, staff: int) -> CompiledSpell:
	if not _in_range(actor, staff):
		return null
	var index: int = actor * SpellLimits.STAFFS + staff
	var compiled: CompiledStaff = _installed[index]
	if compiled == null or compiled.is_empty():
		return null
	var cast: CompiledCast = compiled.casts[mini(_cursor[index], compiled.casts.size() - 1)]
	return null if cast.group.is_empty() else cast.group.spells[0]


## Siphon: mana comes back to the actor `actor`, whoever it is; its body (a wizard's player,
## an enemy's AI) takes it from `mana_refund_requested`.
func _refund(actor: int, amount: float) -> void:
	if events != null and actor >= 0 and actor < ACTORS:
		events.mana_refund_requested.emit(actor, amount)


## The actor table: the injected one, else the projectile manager's (its own or the `Actors`
## autoload), else the autoload (null outside a game or test run).
func _actor_table() -> ActorsScript:
	if actors != null:
		return actors if is_instance_valid(actors) else null
	if projectiles != null and is_instance_valid(projectiles):
		return projectiles.actor_table()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"Actors") as ActorsScript if tree != null and tree.root != null else null


## The seat `seat`'s (0-3) own body, or Actors.NONE: for the HUD, which knows seats, shows the
## player's own wizard also while the seat drives another actor (possess; owner, 2026-10-28) and
## asks Spells by caster (`cast_index`, `cooldown_left`).
func home_of_seat(seat: int) -> int:
	var table: ActorsScript = _actor_table()
	return table.home_of_seat(seat) if table != null else ActorsScript.NONE


## The team `actor` aims for (Actors.NONE for no actor): a chain's jump and an arc's zap skip its
## bodies.
func _team(actor: int) -> int:
	var table: ActorsScript = _actor_table()
	return table.team_of(actor) if table != null else ActorsScript.NONE


## Which per-step fire and chain count, and which share of the beams and waiting launches, an
## actor spends: its seat's while a seat drives it, else the shared one (`Actors.SHARED`).
func _budget(actor: int) -> int:
	var table: ActorsScript = _actor_table()
	return table.budget_of(actor) if table != null else ActorsScript.SHARED


## A caster's own state back to new (its builds are handled by the caller).
func _reset_caster(caster: int) -> void:
	for staff in SpellLimits.STAFFS:
		var index: int = caster * SpellLimits.STAFFS + staff
		_cooldown[index] = 0.0
		_cursor[index] = 0
		_cast_count[index] = 0
		_hold_mana[index] = 0.0
		_last_form[index] = &""
	_moves.reset_actor(caster)
	for carrier: Carrier in _carriers.values():
		carrier.reset_actor(caster)
	_aim_origin[caster] = Vector2.INF
	_aim_dir[caster] = Vector2.INF
	_aim_seen[caster] = 0
	_aim_pivot[caster] = Vector2.INF
	_poses.reset_actor(caster)
	_last_infused[caster] = null


## A caster's staff: any actor id and staff 0-3 (a caster never opened casts from a clean row).
func _in_range(actor: int, staff: int) -> bool:
	return staff >= 0 and staff < SpellLimits.STAFFS and actor >= 0 and actor < ACTORS


func _is_current(tag: int) -> bool:
	var index: int = SpellTag.caster_of(tag) * SpellLimits.STAFFS + SpellTag.staff_of(tag)
	return _current[index] == SpellTag.generation_of(tag)


## Erases the profiles of every node of the tag's generation.
func _erase_generation(tag: int) -> void:
	var key: int = SpellTag.generation_key(tag)
	for node in _node_counts.get(key, 0):
		_profiles.erase(SpellTag.make(SpellTag.caster_of(tag), SpellTag.staff_of(tag), node, SpellTag.generation_of(tag)))
	_node_counts.erase(key)


## The old generation is no longer current: free it now if none of its shots is in the air.
func _release_generation(actor: int, staff: int, generation: int) -> void:
	var key: int = SpellTag.generation_key(SpellTag.make(actor, staff, 0, generation))
	if _generation_live.get(key, 0) == 0:
		_erase_generation(key)


## True when `spell`, fired under `tag`, is a sustained (`hold`) carrier: it has the card and its
## build is still its staff's. A hold of an older build (the staff was edited, or its caster
## closed, while a shot that fires it was in the air) was switched off with it: it lives its own life.
func _holds(spell: CompiledSpell, tag: int) -> bool:
	return spell.behaviour(ModifierBase.Behaviour.HOLD) > 0.0 and _is_current(tag)


## True when a held `spell` is cast again rather than kept on: a rain and a swing are over at once,
## so while held each is cast anew every wind-up and lifetime (a rain falls again, a swing sweeps
## back), until switched off. Its hold ends only then, not between two of them.
static func _repeats(spell: CompiledSpell) -> bool:
	return spell != null and spell.has_trait(Carrier.REPEATS_HELD)


## A sustained (`hold`) carrier made shots: it stays on and its staff reserves the mana of the
## cast it belongs to until it is switched off (`cast_staff` again, an edit) or its last shot ends.
## The same for every firing: the cast's own carrier, a payload's, a burst's later firing. The
## firings of one carrier share its tag, so it is listed once; a staff reserves one cast's mana.
func _start_hold(tag: int) -> void:
	if _live.get(tag, 0) <= 0 and not _repeats(profile(tag)):
		return
	var actor: int = SpellTag.caster_of(tag)
	var index: int = actor * SpellLimits.STAFFS + SpellTag.staff_of(tag)
	if _hold_tags[index].has(tag):
		return
	if _hold_tags[index].is_empty():
		_hold_mana[index] = _cast_mana_of(_installed[index], SpellTag.node_of(tag))
	_hold_tags[index].append(tag)
	_send_reserved(actor)


## The mana of the cast of `compiled` that `node` belongs to (its own carrier or one of its
## payloads), or 0.0 when none has it.
func _cast_mana_of(compiled: CompiledStaff, node: int) -> float:
	if compiled == null:
		return 0.0
	for cast in compiled.casts:
		if _group_has(cast.group, node):
			return cast.mana
	return 0.0


## True when `node` is a carrier of `group` or of a payload below it.
func _group_has(group: CompiledGroup, node: int) -> bool:
	if group == null:
		return false
	for spell in group.spells:
		if spell.node == node or _group_has(spell.payload, node) or _group_has(spell.own_payload, node):
			return true
	return false


## Switches off the sustained carriers of this staff: their shots go, their waiting firings
## (a burst's later ones, a payload that fires them) go, their mana is free. Other waiting
## launches of the staff fire on.
func _release_hold(index: int) -> void:
	if _hold_tags[index].is_empty():
		return
	var tags: PackedInt64Array = _hold_tags[index].duplicate()
	_drop_pending(func(launch: PendingLaunch) -> bool: return _fires_any(launch, tags))
	_hold_tags[index].clear()
	_hold_mana[index] = 0.0
	for tag in tags:
		for carrier: Carrier in _carriers.values():
			carrier.switch_off(tag)
		_lc_leave(tag, true)
	if projectiles != null:
		for tag in tags:
			# remove_by_tag sends no shot_ended, so the counts are ended here.
			for _n in projectiles.remove_by_tag(tag):
				shot_ended(tag)
	_send_reserved(floori(float(index) / SpellLimits.STAFFS))


## The last shot of `tag` ended: if it was a sustained carrier, it is off now.
func _end_hold_of(tag: int) -> void:
	if not SpellTag.is_spell_tag(tag):
		return
	var index: int = SpellTag.caster_of(tag) * SpellLimits.STAFFS + SpellTag.staff_of(tag)
	var at: int = _hold_tags[index].find(tag)
	if at < 0 or _repeats(profile(tag)):
		return
	_hold_tags[index].remove_at(at)
	if _hold_tags[index].is_empty():
		_hold_mana[index] = 0.0
		_send_reserved(SpellTag.caster_of(tag))


## Mana this actor's sustained carriers hold, over all their staffs.
func reserved_mana(actor: int) -> float:
	var total: float = 0.0
	if actor >= 0 and actor < ACTORS:
		for staff in SpellLimits.STAFFS:
			total += _hold_mana[actor * SpellLimits.STAFFS + staff]
	return total


## Tells the HUD of the seat that drives `actor` what its sustained carriers hold (an AI reads
## `reserved_mana` itself; the event is the seat's).
func _send_reserved(actor: int) -> void:
	if events == null:
		return
	var table: ActorsScript = _actor_table()
	var seat: int = table.seat_of(actor) if table != null else ActorsScript.NONE
	if seat != ActorsScript.NONE:
		events.mana_reserved.emit(seat, reserved_mana(actor))


func _component(id: StringName) -> SpellComponent:
	var source: Node = registry if registry != null else get_node_or_null("/root/Registry")
	if source == null:
		return null
	return source.call("get_resource", &"spells", id) as SpellComponent


func _name_of(component: SpellComponent) -> String:
	return component.display_name if not component.display_name.is_empty() else String(component.id)



## What a blast of `spell` strikes with when its carrier hits with `hit`: the compiled `burst` copy
## of its own hit or its echo's, else (relay took an element on, a jump's parent hit) a new one.
func _blast_hit(spell: CompiledSpell, hit: HitProfile) -> HitProfile:
	if hit == spell.hit and spell.blast_hit != null:
		return spell.blast_hit
	if hit == spell.echo_hit and spell.echo_blast_hit != null:
		return spell.echo_blast_hit
	return StaffCompiler.blast_hit(hit if hit != null else spell.hit)


## Where the familiar with `key` (`entity_key`) is now, told by Entities every step: what its
## triggers cast comes from there.
func familiar_at(key: int, at: Vector2) -> void:
	if key == 0 or not at.is_finite():
		return
	for i in _lc_count:
		if _lc_seq[i] == key and _lc_kind[i] == LC_POINT:
			_lc_at[i] = at
			return


## An entity `ai` made for a carrier ended where it stood: the carrier its kind names (a decoy, a
## familiar) runs its end (`CarrierEntity.entity_ended`).
func _on_entity_ended(actor: int, kind: StringName, position: Vector2, tag: int) -> void:
	var carrier: CarrierEntity = _carriers.get(kind) as CarrierEntity
	if carrier != null:
		carrier.entity_ended(actor, position, tag)

# The carriers and the staff animations, for their looks (`gameplay/feel`, the actor's look), `ai`,
# the actor's mover and the tests: each is read from the object that keeps it.

## This runtime's carrier `id` (bound, with the rows it keeps), or the one that runs nothing for
## an id no carrier has. A reader that wants one carrier's own getters asks that carrier's class
## (`CarrierBeam.of(spells)`), so this runtime names none.
func carrier(id: StringName) -> Carrier:
	var found: Carrier = _carriers.get(id)
	return found if found != null else _no_carrier


## Each actor's staff animation (`StaffPoses`: where each actor's staff is now).
func poses() -> StaffPoses:
	return _poses
