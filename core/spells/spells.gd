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
## ask combat for an area hit there (`area_hit_requested`); a dash card asks the caster's body to move
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
## Beams: a beam lives its `lifetime` (`_start_beam`), held by its caster (the wizard's aim from
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
## `hit_profile(tag)` is what `gameplay/combat` asks on `projectile_hit`.
##
## Multicast spread (B2b): a scatter group sends each carrier in a random direction, drawn from
## a generator seeded by the actor, staff and how many casts the staff has made (a replay is
## the same). A burst group fires `repeats` times; the later firings, and an `echo` carrier's
## second firing, wait in a queue (it grows as needed, nothing is dropped for room) and are
## dropped only if the staff was rebuilt or switched off meanwhile. A cast's
## own later firings start from where the caster has moved to. `mirror` fires the carrier again
## with its aim reversed (every carrier but a move, rules R4g); an echo hits at half damage.
##
## Payload and line carriers (B2c): `rain` strikes the aim point after its `lifetime` with its own
## hit and cards and drops its payload there (a `form_shown` cue `&"rain"` says where and when; an
## `on expire` trigger on it fires as it lands); `familiar` and `decoy` ask `ai` for an entity
## (`entity_spawn_requested`), count it as a live shot of their tag until `entity_ended`, fire a
## familiar's payload on every `familiar_cast_requested` (the familiar's infusions and hit cards
## ride on it, compiled in), guard a decoy with its shield or deflect (`guard_decoy`), and fire an
## entity's `on expire` payload and `blast` at its end point; `hold` keeps an entity until its staff is cast again (`entity_end_requested`). `wall`
## is a line of still shots across the aim; `fissure` is a beam that pierces everything on its line.
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
## and its `on expire` payload happen there. A shot or beam with `blast` asks combat for an area
## hit where it ends (a pulling shot's blast waits for the arrival); `siphon` sends `mana_refund_requested` for each hit; `possess`
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


## A dash under way (rules R4c, `_start_pass`): it strikes every body its mover passes, once each.
class MovePass:
	extends RefCounted
	var tag: int = 0
	var spell: CompiledSpell = null
	var actor: int = 0
	## The shot it moves and that shot's seq, or -1 for the actor's own body.
	var shot: int = -1
	var seq: int = 0
	## Where the mover was at the last step (where it started, before the first), and the seconds left.
	var last: Vector2 = Vector2.INF
	var left: float = 0.0
	## The chain jumps its hits carry, the body before them, and what it hits with when not its
	## spell's own `hit` (an echo's), as a swing's.
	var chain: int = 0
	var prev: int = 0
	var hit: HitProfile = null
	var struck: Array[Node] = []


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
## caster -> the way the wizard's (or enemy's) last asked move goes, for the payload fired where it ends
var _move_heading: PackedVector2Array = PackedVector2Array()
## tag -> the pulls of the wizard under way whose hit spent their shot, so the arrival is the
## carrier's end point; a shot that flies on ends by itself (rules R4a).
var _pull_ends: Dictionary = {}
## Per actor, the homing of the wizard's last dash; the actor steers with it (`move_homing`).
var _dash_homing: Array[Homing] = []
## The homing of the teleport being cast (it is over at once), and one that never homes.
var _teleport_homing: Homing = Homing.new()
## Per actor, the target their last homing teleport landed at (0 for none): the next one picks
## another while it can, as a homing shot does after a hit, so hops go from enemy to enemy.
var _landed_at: PackedInt64Array = PackedInt64Array()
var _no_homing: Homing = Homing.new()
## tag -> entities (decoys, familiars) alive that came from it; each counts as a live shot
var _entities: Dictionary = {}
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
## it is now: the shot in a slot (`LC_SLOT`; also the shot a dash moves), a beam's tip, a swing's
## tip, an actor's body (a wizard's dash, a familiar round its wizard) or a fixed point (a rain's
## spot, a decoy). One `_lc_tied` to its row ends with it (a shot, a beam, a swing); the others
## live `_lc_left` seconds (a rain, a dash, an entity) or until they leave (`_lc_leave`: an
## entity that ended). `_lc_clock` is the seconds to the next tick, `_lc_at` where it was last,
## `_lc_way` its way where nothing else gives one.
const LC_SLOT: int = 0
const LC_BEAM: int = 1
const LC_SWING: int = 2
const LC_ACTOR: int = 3
const LC_POINT: int = 4
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
## Slots of live shots with `arc`, `_arc_count` of them, flagged in `_rec_arc`; `_rec_arc_clock` is
## the seconds to each one's next zap.
var _arcs: PackedInt32Array = PackedInt32Array()
var _arc_count: int = 0
var _rec_arc: PackedByteArray = PackedByteArray()
var _rec_arc_clock: PackedFloat32Array = PackedFloat32Array()
## Zaps made in this step (`SpellLimits.MAX_ARCS_PER_STEP`), and the slot of the shot whose zap
## is being sent (-1 for none): the zap is a hit of that shot (`relay`, chain jumps).
var _arcs_used: int = 0
var _arc_slot: int = -1
## Slots of live shots with `magnet`, `_magnet_count` of them, flagged in `_rec_magnet`.
var _magnets: PackedInt32Array = PackedInt32Array()
var _magnet_count: int = 0
## Where in `_magnets` the next step's pulls start (it rotates when there are more than the cap).
var _magnet_from: int = 0
var _rec_magnet: PackedByteArray = PackedByteArray()
## What a shot hits with when it is not its spell's own `hit`, by slot (null: `hit`): an echo's
## `echo_hit`, what a relay shot became after it hit an actor that had cast an infusion, or what
## the hit a chain jump came from hit with. `_rec_zap` is the same for the shot's zaps (`arc_hit`).
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
## A fissure hits everything on its line: a pierce no line spends.
const PIERCE_ALL: int = 1 << 30
const CASTER_WIZARD: int = ProjectilesScript.CASTER_WIZARD
const CASTER_POINT: int = ProjectilesScript.CASTER_POINT
## Points a live beam row has room for at first: its start, RAY_SEGMENTS a leg for each target it
## bends to and a straight end (`_beam_path`), or the path its ray walked with a point at every
## turn at a wall (`_beam_keep_path`). The rows grow when one needs more (`_fit_beam_points`).
const BEAM_POINTS_START: int = SpellLimits.BEAM_LEGS_START * ProjectilesScript.RAY_SEGMENTS + 2
var _caster: int = CASTER_WIZARD
var _caster_seq: int = 0
## Moves of shots whose end point is still to come (a dash whose caster is a shot): the shot,
## its sequence number, the carrier's tag, seconds left, its heading and where it was last seen.
var _mv_slot: PackedInt32Array = PackedInt32Array()
var _mv_seq: PackedInt64Array = PackedInt64Array()
var _mv_tag: PackedInt64Array = PackedInt64Array()
var _mv_left: PackedFloat32Array = PackedFloat32Array()
var _mv_heading: PackedVector2Array = PackedVector2Array()
var _mv_at: PackedVector2Array = PackedVector2Array()
var _mv_count: int = 0
## The dashes under way (`_start_pass`), and spare records for the next ones.
var _passes: Array[MovePass] = []
var _passes_free: Array[MovePass] = []

## The beam being cast: its tag and direction.
var _ray_tag: int = 0
var _ray_dir: Vector2 = Vector2.ZERO
var _ray_chain: int = 0
var _ray_prev: int = 0
## What the ray being sent hits with when not its spell's own `hit` (null): an echo's, a zap's,
## or what the hit a chain jump came from hit with.
var _ray_hit: HitProfile = null
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

## The live beams (see `_start_beam`), rows that double when every one is on (`_grow_beams`);
## `_bm_on` says which are in use. Each keeps what a shot's record keeps (fires, chain) plus where it is: its origin,
## way, the curve's pull and end, how far it got and where (its tip), and its caster.
var _bm_on: PackedByteArray = PackedByteArray()
var _bm_born: PackedInt64Array = PackedInt64Array()
var _bm_next_born: int = 0
var _bm_spell: Array[CompiledSpell] = []
var _bm_source: Array[Node] = []
var _bm_tag: PackedInt64Array = PackedInt64Array()
var _bm_actor: PackedInt32Array = PackedInt32Array()
var _bm_caster: PackedInt32Array = PackedInt32Array()
var _bm_caster_seq: PackedInt64Array = PackedInt64Array()
var _bm_life: PackedFloat32Array = PackedFloat32Array()
var _bm_span: PackedFloat32Array = PackedFloat32Array()
var _bm_tick: PackedFloat32Array = PackedFloat32Array()
## The homing of each leg of each live beam (`_bm_legs` a row): the target it keeps.
var _bm_homing: Array[Homing] = []
var _bm_legs: int = SpellLimits.BEAM_LEGS_START
## Each live beam's path, `_bm_stride` points a row (see `_beam_path`), and how many it uses.
var _bm_points: PackedVector2Array = PackedVector2Array()
var _bm_stride: int = BEAM_POINTS_START
## For `_beam_steer`: the beam being walked, where its legs' targets are in its path (made by
## `_beam_path`, the reached ones kept at each turn), the points it hands back, and the Callable
## made once.
var _steer_row: int = -1
var _steer_goals: PackedInt32Array = PackedInt32Array()
var _steer_goal_count: int = 0
var _steer_points: PackedVector2Array = PackedVector2Array()
var _steer_call: Callable = _beam_steer
## The scratch of `_wave` (a spiral beam's path).
var _wave_points: PackedVector2Array = PackedVector2Array()
var _wave_index: PackedInt32Array = PackedInt32Array()
var _bm_count: PackedInt32Array = PackedInt32Array()
var _bm_turn: PackedFloat32Array = PackedFloat32Array()
var _bm_chain: PackedInt32Array = PackedInt32Array()
var _bm_prev: PackedInt64Array = PackedInt64Array()
## What live beam `at` hits with when not its spell's own `hit` (null): an echo's half, and what
## `relay` took on while it is on (`_relay`).
var _bm_hit: Array[HitProfile] = []
## Shield charges live beam `at` has left for shots it touches (melee I3, `_guard_path`).
var _bm_shield: PackedInt32Array = PackedInt32Array()
## The path of a fissure or a beam's jump, for its guard (`_shoot_ray`); RAY_SEGMENTS is plenty for
## its turns at walls, and a path with more is guarded along its first ones.
var _ray_guard_points: PackedVector2Array = PackedVector2Array()
var _bm_origin: PackedVector2Array = PackedVector2Array()
var _bm_dir: PackedVector2Array = PackedVector2Array()
var _bm_bend: PackedVector2Array = PackedVector2Array()
var _bm_end: PackedVector2Array = PackedVector2Array()
var _bm_reach: PackedFloat32Array = PackedFloat32Array()
var _bm_tip: PackedVector2Array = PackedVector2Array()
var _bm_tip_dir: PackedVector2Array = PackedVector2Array()
var _bm_hit_at: PackedFloat32Array = PackedFloat32Array()
## The live swings (melee I2, see `_start_swing`): `SpellLimits.SWING_ROWS_START` rows at first,
## more when every one is on (no swing ends another); `_sw_on` says which are in use. Each keeps what a beam keeps for its hits (fires, chain, echo, its
## caster) and its sweep: the point it turns round (`_sw_origin`, the wizard's hand), the aim
## locked at the cast, which way it turns (1 clockwise on screen, -1 back), how long it has run,
## its wind-up, and how far it has turned (radians off the aim). The bodies it has struck (a list
## a swing, with where and which way; as many as it meets) are not struck by it again.
var _sw_on: PackedByteArray = PackedByteArray()
var _sw_born: PackedInt64Array = PackedInt64Array()
var _sw_next_born: int = 0
var _sw_spell: Array[CompiledSpell] = []
var _sw_source: Array[Node] = []
var _sw_tag: PackedInt64Array = PackedInt64Array()
var _sw_actor: PackedInt32Array = PackedInt32Array()
var _sw_caster: PackedInt32Array = PackedInt32Array()
var _sw_caster_seq: PackedInt64Array = PackedInt64Array()
var _sw_origin: PackedVector2Array = PackedVector2Array()
var _sw_dir: PackedVector2Array = PackedVector2Array()
var _sw_side: PackedInt32Array = PackedInt32Array()
var _sw_age: PackedFloat32Array = PackedFloat32Array()
var _sw_wind: PackedFloat32Array = PackedFloat32Array()
var _sw_turned: PackedFloat32Array = PackedFloat32Array()
var _sw_chain: PackedInt32Array = PackedInt32Array()
var _sw_prev: PackedInt64Array = PackedInt64Array()
var _sw_echo: PackedByteArray = PackedByteArray()
## Shield charges swing `at` has left for shots its sweep touches (melee I3, `_swing_guard`).
var _sw_shield: PackedInt32Array = PackedInt32Array()
var _sw_struck: Array[Array] = []
var _sw_points: Array[Array] = []
var _sw_heads: Array[Array] = []
## The live slams (melee I8, see `_start_slam`): SLAM_ROWS_START rows at first, more when every
## one is on. Each keeps what a swing keeps for its hits, the hand it is held by and the aim locked
## at the cast, how long it has run and its wind-up, where it struck (INF before the impact), its
## shield charges for shots in its ring, and the bodies its ring has struck.
var _sl_on: PackedByteArray = PackedByteArray()
var _sl_born: PackedInt64Array = PackedInt64Array()
var _sl_next_born: int = 0
var _sl_spell: Array[CompiledSpell] = []
var _sl_source: Array[Node] = []
var _sl_tag: PackedInt64Array = PackedInt64Array()
var _sl_actor: PackedInt32Array = PackedInt32Array()
var _sl_caster: PackedInt32Array = PackedInt32Array()
var _sl_caster_seq: PackedInt64Array = PackedInt64Array()
var _sl_origin: PackedVector2Array = PackedVector2Array()
var _sl_dir: PackedVector2Array = PackedVector2Array()
var _sl_impact: PackedVector2Array = PackedVector2Array()
var _sl_age: PackedFloat32Array = PackedFloat32Array()
var _sl_wind: PackedFloat32Array = PackedFloat32Array()
var _sl_chain: PackedInt32Array = PackedInt32Array()
var _sl_prev: PackedInt64Array = PackedInt64Array()
var _sl_echo: PackedByteArray = PackedByteArray()
var _sl_shield: PackedInt32Array = PackedInt32Array()
var _sl_struck: Array[Array] = []
## actor -> which way its last swing turned (the next turns the other way) and when its last sweep
## ended (a swing within SWING_CHAIN of it has no wind-up).
var _sw_last_side: PackedInt32Array = PackedInt32Array()
var _sw_last_end: PackedFloat32Array = PackedFloat32Array()
## actor -> when its last swing started: the swings of one cast (a split, a mirror) turn the same way.
var _sw_last_start: PackedFloat32Array = PackedFloat32Array()
## actor -> its body's last staff animation (`staff_pose`): when it began (INF for none), the
## carrier's wind-up and strike in seconds (its strike ends early when its last shot does: the tag
## it plays for), the aim locked at the cast, which way it turns (a swing's side), its keys
## (`FormBase.packed_pose`), the carrier's tint (its glow's colour), and where the staff was when it
## began (POSE_CHANNELS numbers a body, in its own frame: what the first key starts from).
var _pose_start: PackedFloat32Array = PackedFloat32Array()
var _pose_wind: PackedFloat32Array = PackedFloat32Array()
var _pose_strike: PackedFloat32Array = PackedFloat32Array()
var _pose_tag: PackedInt64Array = PackedInt64Array()
var _pose_dir: PackedVector2Array = PackedVector2Array()
## 1 when the animation keeps the aim of the cast (a swing, a slam: their aim is locked), 0 when
## it turns with the live aim (a held beam follows it).
var _pose_lock: PackedByteArray = PackedByteArray()
var _pose_side: PackedInt32Array = PackedInt32Array()
var _pose_keys: Array[PackedFloat32Array] = []
var _pose_tint: PackedColorArray = PackedColorArray()
var _pose_from: PackedFloat32Array = PackedFloat32Array()
## The pose worked out last (`_pose_now`), for whom and when: the channels and the mood.
var _pose_out: PackedFloat32Array = PackedFloat32Array()
var _pose_out_mood: int = 0
var _pose_out_actor: int = -1
var _pose_out_clock: float = -1.0
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


func _init() -> void:
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
	_move_heading.resize(ACTORS)
	_move_heading.fill(Vector2.RIGHT)
	_landed_at.resize(ACTORS)
	_aim_origin.resize(ACTORS)
	_aim_origin.fill(Vector2.INF)
	_aim_dir.resize(ACTORS)
	_aim_dir.fill(Vector2.INF)
	_aim_seen.resize(ACTORS)
	_aim_pivot.resize(ACTORS)
	_aim_pivot.fill(Vector2.INF)
	_sw_last_side.resize(ACTORS)
	_sw_last_side.fill(-1)
	_sw_last_end.resize(ACTORS)
	_sw_last_end.fill(-INF)
	_sw_last_start.resize(ACTORS)
	_sw_last_start.fill(-INF)
	_pose_start.resize(ACTORS)
	_pose_start.fill(INF)
	_pose_wind.resize(ACTORS)
	_pose_strike.resize(ACTORS)
	_pose_dir.resize(ACTORS)
	_pose_side.resize(ACTORS)
	_pose_keys.resize(ACTORS)
	_pose_tag.resize(ACTORS)
	_pose_lock.resize(ACTORS)
	_pose_tint.resize(ACTORS)
	_pose_from.resize(ACTORS * POSE_CHANNELS)
	_pose_out.resize(POSE_CHANNELS)
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
	_arcs.resize(64)
	_magnets.resize(64)
	_bm_on.resize(SpellLimits.BEAM_ROWS_START)
	_bm_born.resize(SpellLimits.BEAM_ROWS_START)
	_bm_spell.resize(SpellLimits.BEAM_ROWS_START)
	_bm_source.resize(SpellLimits.BEAM_ROWS_START)
	_bm_tag.resize(SpellLimits.BEAM_ROWS_START)
	_bm_actor.resize(SpellLimits.BEAM_ROWS_START)
	_bm_caster.resize(SpellLimits.BEAM_ROWS_START)
	_bm_caster_seq.resize(SpellLimits.BEAM_ROWS_START)
	_bm_life.resize(SpellLimits.BEAM_ROWS_START)
	_bm_span.resize(SpellLimits.BEAM_ROWS_START)
	_bm_tick.resize(SpellLimits.BEAM_ROWS_START)
	_bm_turn.resize(SpellLimits.BEAM_ROWS_START)
	for i in SpellLimits.BEAM_ROWS_START * _bm_legs:
		_bm_homing.append(Homing.new())
	for i in ACTORS:
		_dash_homing.append(Homing.new())
	_bm_points.resize(SpellLimits.BEAM_ROWS_START * _bm_stride)
	_bm_count.resize(SpellLimits.BEAM_ROWS_START)
	_bm_chain.resize(SpellLimits.BEAM_ROWS_START)
	_bm_prev.resize(SpellLimits.BEAM_ROWS_START)
	_bm_hit.resize(SpellLimits.BEAM_ROWS_START)
	_bm_shield.resize(SpellLimits.BEAM_ROWS_START)
	_ray_guard_points.resize(64)
	_bm_origin.resize(SpellLimits.BEAM_ROWS_START)
	_bm_dir.resize(SpellLimits.BEAM_ROWS_START)
	_bm_bend.resize(SpellLimits.BEAM_ROWS_START)
	_bm_end.resize(SpellLimits.BEAM_ROWS_START)
	_bm_reach.resize(SpellLimits.BEAM_ROWS_START)
	_bm_tip.resize(SpellLimits.BEAM_ROWS_START)
	_bm_tip_dir.resize(SpellLimits.BEAM_ROWS_START)
	_bm_hit_at.resize(SpellLimits.BEAM_ROWS_START)
	_grow_swings(SpellLimits.SWING_ROWS_START)
	_grow_slams(SpellLimits.SLAM_ROWS_START)
	_mv_slot.resize(SpellLimits.SHOT_MOVES_START)
	_mv_seq.resize(SpellLimits.SHOT_MOVES_START)
	_mv_tag.resize(SpellLimits.SHOT_MOVES_START)
	_mv_left.resize(SpellLimits.SHOT_MOVES_START)
	_mv_heading.resize(SpellLimits.SHOT_MOVES_START)
	_mv_at.resize(SpellLimits.SHOT_MOVES_START)


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
		events.familiar_cast_requested.disconnect(_on_familiar_cast)
		events.caster_move_finished.disconnect(_on_move_finished)
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
		events.familiar_cast_requested.connect(_on_familiar_cast)
		events.caster_move_finished.connect(_on_move_finished)


## Compiles a staff's cards (ids by slot, `&""` for an empty slot) into its cycle, the casts it
## makes until it recharges (staffs A4; the rules are docs/milestones/M2-staffs.md, "Reading a
## staff", and `StaffCompiler`). It never errors and refuses nothing: an unknown or useless
## card is listed in `wasted` with the reason.
func compile_staff(cards: Array[StringName], staff: StaffBase) -> CompiledStaff:
	return StaffCompiler.new(_component).compile(cards, staff)


## What the builder shows of a staff, as plain values so that nothing outside `core/spells`
## reads a compiled staff: `empty`; `cards` (the card ids by slot, `&""` for an empty slot); `casts`, one Dictionary per cast of the cycle with `slots`
## (read order), `name` (the generated spell name, `SpellNamer`), `text`, `mana`, `delay`, `damage` (each carrier's hit times its shots and the group's repeats, payloads left out), `recharges`, `wrapped`, `targets` (card slot -> the
## carrier's slot, or `StaffCompiler.TARGET_CASTER` / `TARGET_POINT`) and `wasted` (slot ->
## reason); `wasted` for the staff (cards that did nothing in any cast that read them); and
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
## depend on what is hit), so it is the builder's "at least" number.
static func _cast_damage(cast: CompiledCast) -> int:
	if cast.group == null:
		return 0
	var total: int = 0
	for spell in cast.group.spells:
		total += spell.damage * maxi(spell.shots, 1) * beam_hits(spell.motion, spell.lifetime)
	return total * maxi(cast.group.repeats, 1)


## How many times a carrier with `motion` that lives `lifetime` seconds hits one target: a live
## beam once at once and then every `SpellLimits.BEAM_TICK` seconds of its life; anything else once.
static func beam_hits(motion: int, lifetime: float) -> int:
	if motion != FormBase.Motion.RAY:
		return 1
	return maxi(ceili(lifetime / SpellLimits.BEAM_TICK - 0.001), 1)


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
		var hits: int = maxi(form.shots, 1) * beam_hits(form.motion, form.lifetime)
		out.append("Dmg %d" % form.base_damage if hits <= 1 else "Dmg %dx%d" % [form.base_damage, hits])
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
			["Spread", modifier.spread_mult],
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
		_end_pose_strike(tag)
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


## What one hit of a shot with `tag` does, or null when the tag is no spell's (a shot of
## no staff) or its generation is gone. Shared and read-only; allocates nothing.
func hit_profile(tag: int) -> HitProfile:
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null:
		return null
	# A relay shot hits with what it took on (the hit being sent names its slot).
	var slot: int = projectiles.event_slot if projectiles != null else -1
	if slot >= 0 and slot < _rec_relay.size() and _rec_relay[slot] != null and _same(slot) and projectiles.get_tag_of(slot) == tag:
		return _rec_relay[slot]
	# A ray (a beam, a fissure, a swing, a zap, a jump of any) has no slot: it hits with what the
	# one being sent carries (an echo's half, a zap's share, a jump's parent hit).
	if _ray_hit != null and tag == _ray_tag:
		return _ray_hit
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
		_end_entities(revoked)
		_end_beams_of(revoked)
		_end_swings_of(revoked)
		_end_slams_of(revoked)
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
func cast_staff(actor: int, staff: int, origin: Vector2, direction: Vector2, mana: float) -> float:
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
	_step_moves(delta)
	_step_passes(delta)
	_step_beams(delta)
	_step_swings(delta)
	_step_slams(delta)
	_step_live(delta)
	_step_arcs(delta)
	_step_magnets()
	_run_pending()


## The shots made by one launch of `spell`, returned as how many were made (a beam counts
## as one). `source` is the target that fired the trigger, or null.
func _launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, source: Node, chain: int = -1, prev: int = 0) -> int:
	var count: int = spell.shots
	var made: int = 0
	var carried: int = spell.chain_jumps if chain < 0 else chain
	# A held carrier lives until switched off; one that repeats (`_repeats`) lives its own life each time.
	var held: bool = _holds(spell, tag)
	var lifetime: float = SpellLimits.HOLD_LIFETIME if held and not _repeats(spell) else spell.lifetime
	# Any carrier may move the staff (its card's `staff_pose`); a swing's and a slam's start theirs
	# with their own wind-up, side and strike.
	if not spell.staff_pose.is_empty() and spell.motion != FormBase.Motion.SWING and spell.motion != FormBase.Motion.SLAM:
		if _caster == CASTER_WIZARD and actor >= 0 and actor < ACTORS and _pose_start[actor] != _clock and direction.is_finite() and not direction.is_zero_approx():
			_start_pose(actor, spell, tag, maxf(spell.wind_up, 0.0), _pose_strike_of(spell, lifetime), direction.normalized(), up_side(direction))
	if spell.motion == FormBase.Motion.DASH or spell.motion == FormBase.Motion.TELEPORT:
		return _move_caster(spell, tag, actor, origin, direction, carried, prev)
	if spell.motion == FormBase.Motion.DECOY or spell.motion == FormBase.Motion.FAMILIAR:
		return _spawn_entities(spell, tag, actor, origin, count, lifetime)
	if spell.motion == FormBase.Motion.RAIN:
		return _telegraph_rain(spell, tag, actor, origin, direction)
	if spell.motion == FormBase.Motion.WALL:
		return _launch_wall(spell, tag, actor, origin, direction, source, lifetime, carried, prev)
	var base: float = direction.angle()
	for n in count:
		var angle: float = base + _fan_angle(n, count, spell) + _staff_spread(tag, spell)
		var heading: Vector2 = Vector2.from_angle(angle)
		# A held fissure stays open: a beam that pierces everything on its line (`_ray_pierce`).
		if spell.motion == FormBase.Motion.RAY or (held and spell.motion == FormBase.Motion.FISSURE):
			if _start_beam(spell, tag, actor, origin, heading, carried, prev, source, lifetime):
				made += 1
			continue
		if spell.motion == FormBase.Motion.SWING:
			if _start_swing(spell, tag, actor, origin, heading, carried, prev, source):
				made += 1
			continue
		if spell.motion == FormBase.Motion.SLAM:
			if _start_slam(spell, tag, actor, origin, heading, carried, prev, source):
				made += 1
			continue
		if spell.motion == FormBase.Motion.FISSURE:
			_shoot_ray(spell, tag, actor, origin, heading, carried, prev, source, -1.0, spell.echo_hit if _echo_spell == spell else null)
			made += 1
			continue
		var slot: int = -1
		match spell.motion:
			FormBase.Motion.ORBIT:
				var turn: float = SpellLimits.ORBIT_TURN
				if spell.speed > 0.0 and spell.orbit_radius > 0.0:
					turn = spell.speed / spell.orbit_radius
				# An orbit circles its caster: the wizard, or for a payload the shot or the point.
				var centre: Vector2 = Vector2.INF
				if _caster != CASTER_WIZARD:
					var shot: int = _caster_shot()
					centre = projectiles.get_position_of(shot) if shot >= 0 else origin
				slot = projectiles.spawn_orbit(actor, spell.orbit_radius, base + TAU * n / count, turn, lifetime, spell.radius, HITS, spell.pierce, tag, centre)
			FormBase.Motion.STILL:
				var at: Vector2 = origin if count == 1 else origin + heading * spell.radius * 2.0
				slot = projectiles.spawn(actor, at, Vector2.ZERO, lifetime, spell.radius, HITS, spell.pierce, tag, ProjectilesScript.MOTION_STILL)
			_:
				slot = projectiles.spawn(actor, origin, heading * spell.speed, lifetime, spell.radius, HITS, spell.pierce, tag)
		if slot < 0:
			continue
		_apply_travel(slot, spell)
		made += 1
		_register(slot, tag, spell, carried, prev)
		if source != null:
			projectiles.exclude(slot, source, SpellLimits.SOURCE_EXCLUSION)
	# The ring is only a cue, drawn once, and only when a shot really flew.
	if events != null and made > 0 and count > 1 and spell.spread >= 360.0 and spell.motion == FormBase.Motion.STRAIGHT:
		events.form_shown.emit(actor, &"nova", origin, direction, 0.0, spell.tint, spell.look)
	return made


## Dash and teleport move their caster `ray_length` pixels along `direction`: a card's distance
## is fixed, and its speed only says how long a dash takes (`move_seconds`), so `faster` arrives
## sooner, not farther. The body is asked through its owner (`caster_move_requested`, the way and
## the distance; it answers with `caster_move_finished` where it stops, and a teleport is cut
## short at the first wall). A shot that cast it dashes or blinks along `direction` itself, and
## its end point comes when the move is over. Homing turns a dash as it goes (the wizard's through
## `move_homing`, a shot's in `move_shot`) and bends a teleport's way at once, landing it at its
## target's edge when that is nearer than its distance. A teleport's payload is cast by the
## wizard where it lands, so teleports in payloads hop on from there.
## A dash strikes every body its mover passes (`_start_pass`) and a teleport the bodies where it
## lands (`_land_strike`), with its hit (rules R4c). Every move adds up (rules R4 F1): its
## `recoil` is one more move (`_recoil`), and its `shield` guards what it moves (`_shield_move`).
## A point cannot move, so a dash or teleport cast by one moves the wizard to it (rules R4c, F1).
## A move with nothing to move does nothing and returns 0.
func _move_caster(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, chain: int, prev: int) -> int:
	var dash: bool = spell.motion == FormBase.Motion.DASH
	var distance: float = move_distance(spell.ray_length, spell.speed, spell.lifetime)
	var shot: int = _caster_shot()
	var wizard: bool = _caster == CASTER_WIZARD
	if not wizard and shot < 0:
		var anchor: Vector2 = projectiles.get_anchor(actor)
		if not anchor.is_finite() or anchor.is_equal_approx(origin):
			return 0
		# Its wizard goes to the point, from where its body is.
		direction = anchor.direction_to(origin)
		distance = anchor.distance_to(origin)
		origin = anchor
		wizard = true
	if not dash:
		# A teleport is over at once: like a beam, it bends its way toward a target, and like a
		# beam it ends there when the target is within its distance: at the target's edge.
		_teleport_homing.start(spell, hash(Vector3i(actor, tag, roundi(_clock * 1000.0))))
		_teleport_homing.avoid = _landed_at[actor] if actor >= 0 and actor < _landed_at.size() else 0
		var goal: Vector2 = _teleport_homing.point(projectiles, actor, origin, direction)
		if goal.is_finite() and not goal.is_equal_approx(origin):
			direction = origin.direction_to(goal)
			var gap: float = origin.distance_to(goal) - _teleport_homing.target_radius - SpellLimits.LAND_CLEARANCE
			if gap <= distance and actor >= 0 and actor < _landed_at.size():
				_landed_at[actor] = _teleport_homing.keep
			distance = minf(distance, maxf(gap, 0.0))
	var offset: Vector2 = direction * distance
	var seconds: float = move_seconds(spell.ray_length, spell.speed, spell.lifetime) if dash else 0.0
	if wizard:
		if events != null:
			_move_heading[actor] = direction
			if dash:
				_dash_homing[actor].start(spell, hash(Vector2i(actor, tag)))
				events.caster_move_requested.emit(actor, &"dash", offset, seconds, tag)
				var reach: float = origin.distance_to(projectiles.clip_to_walls(origin, origin + offset))
				events.form_shown.emit(actor, &"dash", origin, direction, reach, spell.tint, spell.look)
				# Its way is drawn where the caster really goes (it may home, and other moves add).
				projectiles.follow_caster(actor, spell.tint, spell.look, seconds)
				_start_pass(spell, tag, actor, -1, seconds, chain, prev)
				_lc_join(spell, tag, LC_ACTOR, actor, 0, false, seconds, origin, direction)
			else:
				events.caster_move_requested.emit(actor, &"teleport", offset, 0.0, tag)
			_shield_move(spell, tag, actor, -1, seconds)
		return 1
	var turn: float = spell.homing_turn if spell.homing_range > 0.0 else 0.0
	if not projectiles.move_shot(shot, offset, seconds, turn, spell.homing_range):
		return 0
	_shield_move(spell, tag, actor, shot, seconds)
	if dash:
		_start_pass(spell, tag, actor, shot, seconds, chain, prev)
	_track_move(shot, tag, seconds, direction)
	_lc_join(spell, tag, LC_SLOT, shot, projectiles.get_seq_of(shot), false, seconds, projectiles.get_position_of(shot), direction)
	return 1


## A dash under way (rules R4c): for its `seconds` (and SpellLimits.PASS_GRACE more, as its mover
## is moved and told a step later) it strikes every body its mover passes, once each, with its hit
## (`_pass_step`): the actor's own body (`shot` -1, its anchor) or the shot it moves. A new dash of
## the same body ends the one before (its mover replaces the move). Its echo hits as an echo.
func _start_pass(spell: CompiledSpell, tag: int, actor: int, shot: int, seconds: float, chain: int, prev: int) -> void:
	for other in _passes:
		if other.actor == actor and other.shot == shot:
			other.left = 0.0
	if _passes_free.is_empty():
		_passes_free.append(MovePass.new())
	var dash: MovePass = _passes_free.pop_back()
	dash.tag = tag
	dash.spell = spell
	dash.actor = actor
	dash.shot = shot
	dash.seq = projectiles.get_seq_of(shot) if shot >= 0 else 0
	dash.last = projectiles.get_anchor(actor) if shot < 0 else projectiles.get_position_of(shot)
	dash.left = seconds + SpellLimits.PASS_GRACE
	dash.chain = chain
	dash.prev = prev
	dash.hit = spell.echo_hit if _echo_spell == spell else null
	dash.struck.clear()
	_passes.append(dash)
	shot_started(tag)


## Runs the dashes under way on by `delta`: each strikes what its mover passed since the last step
## (and deflects the shots it passed, with `deflect`), then ends when its time is up, its mover is
## gone or its build is forgotten.
func _step_passes(delta: float) -> void:
	var i: int = 0
	while i < _passes.size():
		var dash: MovePass = _passes[i]
		var at: Vector2 = Vector2.INF
		if dash.shot < 0:
			at = projectiles.get_anchor(dash.actor)
		elif projectiles.is_alive(dash.shot) and projectiles.get_seq_of(dash.shot) == dash.seq:
			at = projectiles.get_position_of(dash.shot)
		if dash.left > 0.0 and at.is_finite() and _profiles.get(dash.tag) == dash.spell:
			_pass_step(dash, dash.last if dash.last.is_finite() else at, at)
			dash.last = at
			dash.left -= delta
		else:
			dash.left = 0.0
		if dash.left > 0.0:
			i += 1
			continue
		_passes.remove_at(i)
		var tag: int = dash.tag
		dash.spell = null
		dash.hit = null
		dash.struck.clear()
		_passes_free.append(dash)
		shot_ended(tag)


## The dash `dash` moved from `from` to `to`: it strikes each body within SpellLimits.PASS_REACH of that
## way that it has not struck yet (`Projectiles.sweep` all round points PASS_REACH apart, so a
## fast dash misses nothing), and with `deflect` turns the shots within MOVE_GUARD_REACH of it.
func _pass_step(dash: MovePass, from: Vector2, to: Vector2) -> void:
	var spell: CompiledSpell = dash.spell
	var reach: float = SpellLimits.PASS_REACH
	var way: Vector2 = from.direction_to(to) if not from.is_equal_approx(to) else _move_heading[dash.actor]
	if spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0:
		_guard(projectiles.shots_on_segment(dash.actor, from, to, SpellLimits.MOVE_GUARD_REACH), dash.actor, dash.tag, true, 0, from, to)
	var samples: int = maxi(ceili(from.distance_to(to) / reach), 1)
	for n in samples:
		var point: Vector2 = from.lerp(to, float(n + 1) / samples)
		var found: int = projectiles.sweep(dash.actor, point, way, 1, -PI, PI, reach, HITS)
		if found > 0:
			_strike_bodies(spell, dash.tag, dash.actor, found, dash.struck, point, way, dash.chain, dash.prev, dash.hit)
		if dash.left <= 0.0 or _profiles.get(dash.tag) != spell:
			return


## A teleport landed at `at` (rules R4c): it strikes each body within SpellLimits.LAND_REACH of it,
## pushed outward from there, and with `deflect` turns the shots within MOVE_GUARD_REACH.
func _land_strike(spell: CompiledSpell, tag: int, actor: int, at: Vector2, heading: Vector2) -> void:
	if spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0:
		_guard(projectiles.shots_on_segment(actor, at, at, SpellLimits.MOVE_GUARD_REACH), actor, tag, true, 0, at, at)
	var found: int = projectiles.sweep(actor, at, heading, 1, -PI, PI, SpellLimits.LAND_REACH, HITS)
	if found > 0:
		var struck: Array[Node] = []
		_strike_bodies(spell, tag, actor, found, struck, at, heading, spell.chain_jumps, 0, spell.echo_hit if _echo_spell == spell else null)


## Strikes the first `found` bodies of `Projectiles.sweep` that are not in `struck` yet (and adds
## them), each pushed outward from `centre` (along `way` when it is on it), in the beam context
## `_ray_*` that `_on_hit` reads, as a swing's and a slam's: its hits carry its cards, payloads
## and chains. `hit` is what it hits with when not its spell's own (an echo's), else null.
func _strike_bodies(spell: CompiledSpell, tag: int, actor: int, found: int, struck: Array[Node], centre: Vector2, way: Vector2, chain: int, prev: int, hit: HitProfile) -> void:
	var first: int = struck.size()
	for i in found:
		var node: Node = projectiles.sweep_nodes[i]
		if not struck.has(node):
			struck.append(node)
	var last: int = struck.size()
	if last == first:
		return
	var saved_tag: int = _ray_tag
	var saved_dir: Vector2 = _ray_dir
	var saved_chain: int = _ray_chain
	var saved_prev: int = _ray_prev
	var saved_hit: HitProfile = _ray_hit
	var saved_arc: int = _arc_slot
	_ray_tag = tag
	_ray_chain = chain
	_ray_prev = prev
	_ray_hit = hit
	_arc_slot = -1
	_ray_dir = way
	for row in range(first, last):
		var node: Node = struck[row]
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var body: Vector2 = (node as Node2D).global_position
		var out: Vector2 = centre.direction_to(body) if not centre.is_equal_approx(body) else way
		projectiles.strike(actor, node, centre, out, tag, spell.form_id)
	_ray_tag = saved_tag
	_ray_dir = saved_dir
	_ray_chain = saved_chain
	_ray_prev = saved_prev
	_ray_hit = saved_hit
	_arc_slot = saved_arc
	_cast_jumps()


## The homing of `actor`'s last dash, for the wizard to turn it as it goes (`Homing.steer`); one
## that does not home when the dash does not, or `actor` is out of range.
func move_homing(actor: int) -> Homing:
	return _dash_homing[actor] if actor >= 0 and actor < _dash_homing.size() else _no_homing


## How far a dash or teleport card moves its caster: its `ray_length` (a card made before moves
## had a distance falls back to speed x lifetime).
static func move_distance(length: float, speed: float, lifetime: float) -> float:
	return length if length > 0.0 else speed * lifetime


## How long a dash takes: its distance at its speed (its lifetime when it has no speed).
static func move_seconds(length: float, speed: float, lifetime: float) -> float:
	if length > 0.0 and speed > 0.0:
		return length / speed
	return lifetime


## Waits for the end of the move of `shot` (`seconds` from now; at once for 0), which is the end
## point of the carrier `tag`: its `blast` and its `on expire` payload happen there. The carrier
## counts as a live shot until then.
func _track_move(shot: int, tag: int, seconds: float, heading: Vector2) -> void:
	shot_started(tag)
	if seconds <= 0.0:
		_move_end(tag, projectiles.get_position_of(shot), heading, shot)
		shot_ended(tag)
		return
	if _mv_count == _mv_slot.size():
		var size: int = _mv_count * 2
		_mv_slot.resize(size)
		_mv_seq.resize(size)
		_mv_tag.resize(size)
		_mv_left.resize(size)
		_mv_heading.resize(size)
		_mv_at.resize(size)
	_mv_slot[_mv_count] = shot
	_mv_seq[_mv_count] = projectiles.get_seq_of(shot)
	_mv_tag[_mv_count] = tag
	_mv_left[_mv_count] = seconds
	_mv_heading[_mv_count] = heading
	_mv_at[_mv_count] = projectiles.get_position_of(shot)
	_mv_count += 1


## Runs the shot moves on by `delta`; one that is over ends where its shot is (or was last seen).
func _step_moves(delta: float) -> void:
	var i: int = 0
	while i < _mv_count:
		var shot: int = _mv_slot[i]
		var alive: bool = projectiles.is_alive(shot) and projectiles.get_seq_of(shot) == _mv_seq[i]
		if alive:
			_mv_at[i] = projectiles.get_position_of(shot)
		_mv_left[i] -= delta
		if _mv_left[i] > 0.0:
			i += 1
			continue
		var tag: int = _mv_tag[i]
		var at: Vector2 = _mv_at[i]
		var heading: Vector2 = _mv_heading[i]
		_mv_count -= 1
		_mv_slot[i] = _mv_slot[_mv_count]
		_mv_seq[i] = _mv_seq[_mv_count]
		_mv_tag[i] = _mv_tag[_mv_count]
		_mv_left[i] = _mv_left[_mv_count]
		_mv_heading[i] = _mv_heading[_mv_count]
		_mv_at[i] = _mv_at[_mv_count]
		_move_end(tag, at, heading, shot if alive else CASTER_POINT)
		shot_ended(tag)


## A move by the carrier `tag` ended at `at`: a teleport strikes what is where it landed
## (`_land_strike`), its `blast` goes off there and its `on expire` payload leaves from there,
## cast by `caster` (the wizard, the shot that moved, or the point).
func _move_end(tag: int, at: Vector2, heading: Vector2, caster: int) -> void:
	var spell: CompiledSpell = _profiles.get(tag)
	var actor: int = SpellTag.caster_of(tag)
	if spell == null or not at.is_finite():
		return
	if spell.motion == FormBase.Motion.TELEPORT:
		_land_strike(spell, tag, actor, at, heading)
	_blast(spell, tag, actor, at)
	if spell.payload != null and spell.trigger_event == TriggerBase.Event.EXPIRE:
		_fire(spell.payload, actor, SpellTag.staff_of(tag), SpellTag.generation_of(tag), at, heading, null, caster)


## The live shot casting the launch being fired, or -1 when the caster is the wizard, a point,
## or a shot that has ended since.
func _caster_shot() -> int:
	if _caster >= 0 and projectiles.is_alive(_caster) and projectiles.get_seq_of(_caster) == _caster_seq:
		return _caster
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


## Rain: for each of its shots, a cue at the aim point and a launch of its payload there after
## its `lifetime`. The aim point is `ray_length` (or `SpellLimits.RAIN_REACH`) along the shot's
## heading, stopped at a wall; homing moves it onto a target near it (`_homed_place`). Returns
## how many were set. A held rain falls again and again (`_repeats`).
func _telegraph_rain(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, heading: Vector2) -> int:
	var reach: float = spell.ray_length if spell.ray_length > 0.0 else SpellLimits.RAIN_REACH
	var placed: int = 0
	for n in spell.shots:
		var along: Vector2 = heading.rotated(_fan_angle(n, spell.shots, spell))
		var point: Vector2 = _homed_place(spell, actor, tag + n, origin, projectiles.clip_to_walls(origin, origin + along * reach))
		var group: CompiledGroup = spell.own_payload if spell.own_payload != null else CompiledGroup.new()
		var launch: PendingLaunch = _delay(spell.lifetime, group, null, actor, SpellTag.staff_of(tag), SpellTag.generation_of(tag), point, along, null, false)
		launch.landing = spell
		launch.echoed = _echo_spell == spell
		_lc_join(spell, tag, LC_POINT, -1, 0, false, spell.lifetime, point, along)
		placed += 1
		if events != null:
			events.form_shown.emit(actor, &"rain", point, along, spell.lifetime, spell.tint, spell.look)
	return placed


## A rain lands: it strikes every body within its splash (`SpellLimits.RAIN_SPLASH`, or its size
## when that is larger) with its own hit and cards (an echo's at half), then its `blast` goes off,
## its payload falls (a group, so a burst repeats it), then its own `on expire` trigger fires, all
## at the aim point (its end point, rules R1d and R4g).
func _land_rain(spell: CompiledSpell, group: CompiledGroup, actor: int, staff: int, generation: int, point: Vector2, heading: Vector2, echoed: bool = false) -> void:
	var tag: int = SpellTag.make(actor, staff, spell.node, generation)
	_strike_round(spell, tag, actor, point, heading, maxf(spell.radius, SpellLimits.RAIN_SPLASH), spell.echo_hit if echoed else null)
	_blast(spell, tag, actor, point)
	if group != null and not group.is_empty():
		_fire(group, actor, staff, generation, point, heading, null, CASTER_POINT)
	if spell.payload != null and spell.trigger_event == TriggerBase.Event.EXPIRE:
		_fire(spell.payload, actor, staff, generation, point, heading, null, CASTER_POINT)


## The carrier `spell` with `tag` strikes every body within `reach` of `at` at once, outward from
## `at`, with `hit` (null: its own) in the beam context `_ray_*` that `_on_hit` reads, so the
## whole hit goes with it: infusions, heavy, chain, siphon, possess and `on hit` (a slam's ring
## strikes the same way as it grows). The bodies are copied first: what a hit sets off can sweep.
func _strike_round(spell: CompiledSpell, tag: int, actor: int, at: Vector2, way: Vector2, reach: float, hit: HitProfile) -> void:
	var found: int = projectiles.sweep(actor, at, way, 1, -PI, PI, reach, HITS)
	if found == 0:
		return
	var struck: Array[Node] = []
	for i in found:
		struck.append(projectiles.sweep_nodes[i])
	var saved_tag: int = _ray_tag
	var saved_dir: Vector2 = _ray_dir
	var saved_chain: int = _ray_chain
	var saved_prev: int = _ray_prev
	var saved_hit: HitProfile = _ray_hit
	var saved_arc: int = _arc_slot
	_ray_tag = tag
	_ray_chain = spell.chain_jumps
	_ray_prev = 0
	_ray_hit = hit
	_arc_slot = -1
	for node in struck:
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var body: Vector2 = (node as Node2D).global_position
		_ray_dir = at.direction_to(body) if not at.is_equal_approx(body) else way
		projectiles.strike(actor, node, at, _ray_dir, tag, &"rain")
	_ray_tag = saved_tag
	_ray_dir = saved_dir
	_ray_chain = saved_chain
	_ray_prev = saved_prev
	_ray_hit = saved_hit
	_arc_slot = saved_arc
	_cast_jumps()


## Wall: `shots` still shots in a line across `direction`, `spread` pixels apart (the shot's
## diameter when the form has none), centred `SpellLimits.WALL_REACH` ahead of `origin` (homing
## moves the centre onto a target near it, `_homed_place`). A shot born in a wall is skipped.
## Shield charges apply, so `shield . wall` stops other teams' shots.
func _launch_wall(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, source: Node, lifetime: float, carried: int, prev: int) -> int:
	var centre: Vector2 = _homed_place(spell, actor, tag, origin, projectiles.clip_to_walls(origin, origin + direction * SpellLimits.WALL_REACH))
	var across: Vector2 = direction.orthogonal()
	var gap: float = spell.spread if spell.spread > 0.0 else spell.radius * 2.0
	var made: int = 0
	for n in spell.shots:
		var at: Vector2 = centre + across * (n - (spell.shots - 1) * 0.5) * gap
		var slot: int = projectiles.spawn(actor, at, Vector2.ZERO, lifetime, spell.radius, HITS, spell.pierce, tag, ProjectilesScript.MOTION_STILL)
		if slot < 0:
			continue
		made += 1
		_apply_travel(slot, spell)
		if spell.homing_range > 0.0:
			# Its homing went into where the wall stands: its shots keep still (a chain jump homes).
			projectiles.set_homing(slot, 0.0, spell.homing_range)
		_register(slot, tag, spell, carried, prev)
		if source != null:
			projectiles.exclude(slot, source, SpellLimits.SOURCE_EXCLUSION)
	return made


## Where a carrier placed at `point` ahead of its caster at `origin` (a rain, a wall) goes when it
## homes (rules R4i): onto a target within its homing reach of the point, picked as a homing
## shot picks one (`homing_point`, any way round), stopped at a wall on the way; else `point`.
func _homed_place(spell: CompiledSpell, actor: int, tag: int, origin: Vector2, point: Vector2) -> Vector2:
	if spell.homing_range <= 0.0:
		return point
	var goal: Vector2 = projectiles.homing_point(actor, point, Vector2.RIGHT, PI, ProjectilesScript.ACTOR_LAYERS, spell.homing_range, 0, hash(Vector3i(actor, tag, roundi(_clock * 1000.0))))
	return point if not goal.is_finite() else projectiles.clip_to_walls(origin, goal)


## Decoys and familiars: `ai` makes the entity (`entity_spawn_requested`, `lifetime` seconds, or
## until ended for a `hold`). Each counts as a live shot of `tag` until `entity_ended`, so its
## build stays known while it lives. Returns how many were asked for.
func _spawn_entities(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, count: int, lifetime: float) -> int:
	if events == null or not _profiles.has(tag):
		return 0
	var kind: StringName = &"decoy" if spell.motion == FormBase.Motion.DECOY else &"familiar"
	var seconds: float = INF if lifetime >= SpellLimits.HOLD_LIFETIME else lifetime
	var anchor: int = _entity_caster()
	# Where it is: a decoy stays where it was made, a familiar circles its caster.
	var where: int = LC_POINT
	if kind == &"familiar" and anchor != -2:
		where = LC_ACTOR if anchor == -1 else LC_SLOT
	var ref: int = actor if where == LC_ACTOR else anchor
	for n in count:
		_entities[tag] = _entities.get(tag, 0) + 1
		shot_started(tag)
		events.entity_spawn_requested.emit(actor, kind, origin, seconds, tag, anchor)
		_lc_join(spell, tag, where, ref, projectiles.get_seq_of(ref) if where == LC_SLOT else 0, false, seconds, origin, Vector2.RIGHT)
	return count


## What an entity circles or copies, for `entity_spawn_requested`: the wizard (-1), the shot that
## cast it, or nothing (-2: it stays where it was made).
func _entity_caster() -> int:
	if _caster == CASTER_WIZARD:
		return -1
	var shot: int = _caster_shot()
	return shot if shot >= 0 else -2


## An entity of this actor ended where it stood: its `blast` and its `on expire` payload happen
## there (the end point), then it stops counting as a live shot.
func _on_entity_ended(actor: int, _kind: StringName, position: Vector2, tag: int) -> void:
	if not SpellTag.is_spell_tag(tag) or actor != SpellTag.caster_of(tag):
		return
	var count: int = _entities.get(tag, 0)
	if count <= 0:
		return
	if count == 1:
		_entities.erase(tag)
	else:
		_entities[tag] = count - 1
	_lc_leave(tag, false)
	var spell: CompiledSpell = _profiles.get(tag)
	if spell != null and position.is_finite():
		_blast(spell, tag, actor, position)
		if spell.payload != null and spell.trigger_event == TriggerBase.Event.EXPIRE:
			_fire(spell.payload, actor, SpellTag.staff_of(tag), SpellTag.generation_of(tag), position, Vector2.RIGHT, null, CASTER_POINT)
	shot_ended(tag)


## The familiar with `tag` casts: its payload (what came after it on the staff) leaves `position`
## along `direction`, in the staff and generation of the familiar's own cards.
func _on_familiar_cast(actor: int, position: Vector2, direction: Vector2, tag: int) -> void:
	if not SpellTag.is_spell_tag(tag) or actor != SpellTag.caster_of(tag) or not _entities.has(tag) or not position.is_finite():
		return
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null or spell.own_payload == null or spell.own_payload.is_empty():
		return
	var aim: Vector2 = direction.normalized() if direction.is_finite() and not direction.is_zero_approx() else Vector2.RIGHT
	_fire(spell.own_payload, actor, SpellTag.staff_of(tag), SpellTag.generation_of(tag), position, aim, null, CASTER_POINT)


## The shield charges of the decoy with `tag`, and whether it deflects (rules R4g), for Entities as
## it makes one; none for a tag no build knows.
func decoy_shield(tag: int) -> int:
	var spell: CompiledSpell = _profiles.get(tag)
	return roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD)) if spell != null else 0


func decoy_deflects(tag: int) -> bool:
	var spell: CompiledSpell = _profiles.get(tag)
	return spell != null and spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0


## A decoy's guard (rules R4g), asked by Entities every step for each decoy with a shield or
## deflect: the shots of other teams than `actor`'s within `reach` of `at` are deflected outward
## by the decoy with `tag` when it deflects, else stopped while its `charges` last, each sending
## its block (`on block`); the one guard of swings and slams (`_guard`). Returns the charges left.
func guard_decoy(actor: int, tag: int, at: Vector2, reach: float, charges: int) -> int:
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null or projectiles == null:
		return charges
	var deflects: bool = spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0
	if not deflects and charges <= 0:
		return charges
	var found: int = projectiles.shots_in_wedge(actor, at, Vector2.RIGHT, 1, -PI, PI, reach)
	return _guard(found, actor, tag, deflects, charges, at, Vector2.INF, &"decoy")


## A revoked build's entities are told to end, and forgotten (their `entity_ended` is then ignored).
func _end_entities(tag: int) -> void:
	_lc_leave(tag, true)
	if _entities.erase(tag) and events != null:
		events.entity_end_requested.emit(SpellTag.caster_of(tag), tag)


## Hand a shot the behaviours of its cards that the projectile manager runs (staffs B1): a bolt,
## a rune, an orbit and a wall's shots from the staff and a chain jump alike (rules R1b). Each
## setter takes what the shot can do and refuses the rest (rules R4h: a rune does not move, an
## orbit does not fly). A plain shot costs one comparison per behaviour and no call.
func _apply_travel(slot: int, spell: CompiledSpell) -> void:
	if spell.homing_range > 0.0:
		projectiles.set_homing(slot, spell.homing_turn, spell.homing_range)
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
## apart (at once when that is 0), reading nothing again. A fallback asks for an area hit on the
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
## on the other side of its circle; a dash or teleport has its mirror wasted), and `echo` schedules
## it once more. `echoed` is true for that second firing, which hits at half damage and does not
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
	# A move's mirror would cancel it (rules R4g): a dash or teleport moves its caster once.
	if launched > 0 and spell.behaviour(ModifierBase.Behaviour.MIRROR) > 0.0 and spell.motion != FormBase.Motion.DASH and spell.motion != FormBase.Motion.TELEPORT:
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


## The area hit of a `blast` at the end point `at` of the carrier with `tag`, as wide as its
## strength, with the hit profile of its tag, and its explosion (`cue_shown`, the cue its blast card
## names). Nothing without a blast.
func _blast(spell: CompiledSpell, tag: int, actor: int, at: Vector2) -> void:
	var radius: float = spell.behaviour(ModifierBase.Behaviour.BLAST)
	if radius > 0.0 and events != null and at.is_finite():
		events.area_hit_requested.emit(actor, at, radius, tag)
		events.cue_shown.emit(actor, spell.cue_of(ModifierBase.Behaviour.BLAST), at, Vector2.ZERO, radius, spell.tint, spell.look)


## Where a dash or teleport ended, or a pull whose hit spent its shot (`_pull_ends`): the
## carrier's end point. Its `blast` and its `on expire` payload happen there. A move whose build
## has been forgotten does nothing.
func _on_move_finished(actor: int, mode: StringName, position: Vector2, tag: int) -> void:
	if not SpellTag.is_spell_tag(tag) or actor != SpellTag.caster_of(tag) or not position.is_finite():
		return
	if mode == &"pull" and _pull_ends.get(tag, 0) > 0:
		_pull_ends[tag] -= 1
		if _pull_ends[tag] == 0:
			_pull_ends.erase(tag)
	elif mode != &"dash" and mode != &"teleport":
		return
	# The caster's body moved, so it casts what its end point fires.
	_move_end(tag, position, _move_heading[actor], CASTER_WIZARD)


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
			_land_rain(landing, group, actor, staff, generation, origin, heading, echoed)
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
## per frame). One that kept its build (`_delay`) lets go of it.
func _drop_pending(drops: Callable) -> void:
	var i: int = _pending.size() - 1
	while i >= 0:
		var launch: PendingLaunch = _pending[i]
		if drops.call(launch):
			_pending.remove_at(i)
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


## `shield` on the caster itself: a barrier on the casting actor with the card's charges, for as
## long as the carrier lasts (a move's own time at least). It comes with every move of the
## wizard (`_shield_move`) and the cards landing on the caster. Combat gives it a minimum time.
func _shield_caster(spell: CompiledSpell, tag: int, actor: int, move_seconds: float) -> void:
	var charges: int = roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD))
	if charges > 0 and events != null:
		events.wizard_shield_requested.emit(actor, charges, maxf(spell.lifetime, move_seconds), tag)


## `shield` on a move, one rule for every spell that moves its caster (dash, teleport, pull, swap;
## rules R4c): what it moves is guarded for the move, the wizard (`shot` -1) by a barrier
## (`_shield_caster`), a shot by that many more shield charges, kept until they are spent.
func _shield_move(spell: CompiledSpell, tag: int, actor: int, shot: int, seconds: float) -> void:
	if shot < 0:
		_shield_caster(spell, tag, actor, seconds)
		return
	var charges: int = roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD))
	if charges > 0:
		projectiles.set_shield(shot, projectiles.get_shield_of(shot) + charges)


## The cards that landed on the caster or on a payload's origin: an area hit there with the
## spell's profile (a blast is as wide as its strength, and explodes). Combat decides what it does
## (staffs B3).
func _fallback_hit(spell: CompiledSpell, tag: int, actor: int, at: Vector2) -> int:
	if events != null:
		var blast: float = spell.behaviour(ModifierBase.Behaviour.BLAST)
		events.area_hit_requested.emit(actor, at, maxf(spell.radius, blast), tag)
		if blast > 0.0 and at.is_finite():
			events.cue_shown.emit(actor, spell.cue_of(ModifierBase.Behaviour.BLAST), at, Vector2.ZERO, blast, spell.tint, spell.look)
	# After the area hit, which can reach the caster itself and would spend the barrier.
	if _caster == CASTER_WIZARD:
		_shield_caster(spell, tag, actor, 0.0)
	return 1


## Degrees (as radians) off the aim of shot `n` of `count`: none for one shot, an even ring
## for a 360 degree spread, otherwise an even fan centred on the aim.
func _fan_angle(n: int, count: int, spell: CompiledSpell) -> float:
	if count <= 1 or spell.motion == FormBase.Motion.ORBIT:
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
		_rec_arc.resize(size)
		_rec_magnet.resize(size)
		_rec_arc_clock.resize(size)
		_rec_relay.resize(size)
		_rec_zap.resize(size)
	_rec_relay[slot] = spell.echo_hit if spell == _echo_spell else null
	_rec_zap[slot] = spell.echo_arc_hit if spell == _echo_spell else null
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
	if spell.arc_interval > 0.0 and spell.arc_reach > 0.0:
		_rec_arc_clock[slot] = first_tick(spell.arc_interval, life)
		if _rec_arc[slot] == 0:
			if _arc_count == _arcs.size():
				_arcs.resize(_arcs.size() * 2)
			_arcs[_arc_count] = slot
			_arc_count += 1
			_rec_arc[slot] = 1
	if spell.behaviour(ModifierBase.Behaviour.MAGNET) > 0.0 and _rec_magnet[slot] == 0:
		if _magnet_count == _magnets.size():
			_magnets.resize(_magnets.size() * 2)
		_magnets[_magnet_count] = slot
		_magnet_count += 1
		_rec_magnet[slot] = 1


## One beam (a fissure, a chain jump of any ray): counted while it is cast, with its context set
## for the hit handler. It pierces as its carrier does (`_ray_pierce`) and passes walls with ghost.
func _shoot_ray(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, heading: Vector2, chain: int, prev: int, source: Node, length: float = -1.0, hit: HitProfile = null) -> void:
	shot_started(tag)
	var saved_tag: int = _ray_tag
	var saved_dir: Vector2 = _ray_dir
	var saved_chain: int = _ray_chain
	var saved_prev: int = _ray_prev
	var saved_hit: HitProfile = _ray_hit
	var saved_arc: int = _arc_slot
	_ray_tag = tag
	_ray_dir = heading
	_ray_chain = chain
	_ray_prev = prev
	_ray_hit = hit
	_arc_slot = -1
	var reach: float = spell.ray_length if length < 0.0 else length
	var got: float = projectiles.ray(actor, origin, heading, reach, _ray_pierce(spell), HITS, tag, spell.radius * 0.5, source, _bounces(spell), _ghost(spell))
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
					events.form_shown.emit(actor, &"beam", from, from.direction_to(to), from.distance_to(to), spell.tint, spell.look)
	elif got > 0.0 and events != null:
		events.form_shown.emit(actor, &"beam", origin, heading, got, spell.tint, spell.look)
	# A `ray()` that did nothing (too deep, or a bad aim) has no end to fire the payload from.
	if got > 0.0:
		_blast(spell, tag, actor, end)
	if got > 0.0 and spell.payload != null and spell.trigger_event == TriggerBase.Event.EXPIRE:
		_fire_payload(spell, tag, actor, end, end_heading, null)
	_ray_tag = saved_tag
	_ray_dir = saved_dir
	_ray_chain = saved_chain
	_ray_prev = saved_prev
	_ray_hit = saved_hit
	_arc_slot = saved_arc
	shot_ended(tag)
	_cast_jumps()


## The shots of other teams touching the path `points[first]` to `points[first + count - 1]`
## (cut `reach` pixels along) of a beam or fissure with `tag`, `width` pixels either side as its
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
		charges = _guard(found, actor, tag, deflects, charges, a, b)
		walked += piece
		if walked >= reach or (not deflects and charges <= 0):
			break
	return charges


## Deflects (with `deflects`) or stops (while `charges` last) the `found` shots of
## `Projectiles.guard_slots` that touched a carrier of `actor` with `tag`: outward from `a` when
## `b` is INF (a swing's hand), else off the segment from `a` to `b` (a beam's or fissure's line);
## a block is sent with that form (`block_shot`). Returns the charges left.
## The list is copied first: what a deflect sets off can run another guard.
func _guard(found: int, actor: int, tag: int, deflects: bool, charges: int, a: Vector2, b: Vector2, form: StringName = &"") -> int:
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
			# A swing's block is a parry; Feel tells them apart by the form.
			if form == &"":
				form = &"swing" if not b.is_finite() else &"beam"
			projectiles.block_shot(slot, actor, tag, form)
	return charges


## A live beam (`beam` carrier): it lives its `lifetime` (a `hold` one until it is switched off),
## held by its caster: from the wizard's staff tip along its aim (`set_aim`), from the shot whose
## trigger cast it along that shot's way, or from a fixed point. A homing one bends along a curve
## to the nearest target in front of it. It hits what is on it at once and then every
## `SpellLimits.BEAM_TICK` seconds; between hits it only finds how far it gets, for its look.
## Its `blast` and `on expire` payload happen where it ends when its life is over. Returns false
## when it could not start (no direction).
func _start_beam(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, heading: Vector2, chain: int, prev: int, source: Node, lifetime: float) -> bool:
	if not heading.is_finite() or heading.is_zero_approx() or not origin.is_finite():
		return false
	# A free row, or new rows when every one is on: no beam ends another.
	var at: int = _bm_on.find(0)
	if at < 0:
		at = _bm_on.size()
		_grow_beams()
	_bm_on[at] = 1
	_bm_born[at] = _bm_next_born
	_bm_next_born += 1
	_bm_spell[at] = spell
	_bm_source[at] = source
	_bm_tag[at] = tag
	_bm_actor[at] = actor
	_bm_life[at] = lifetime
	_bm_span[at] = lifetime
	_bm_tick[at] = 0.0
	_bm_chain[at] = chain
	_bm_prev[at] = prev
	_bm_hit[at] = spell.echo_hit if _echo_spell == spell else null
	_bm_shield[at] = roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD))
	_bm_origin[at] = origin
	_bm_dir[at] = heading.normalized()
	_bm_reach[at] = 0.0
	_bm_hit_at[at] = _clock
	# How far off its caster's way the beam points (a fan, a multicast or a mirror keeps it).
	_bm_caster[at] = _caster
	_bm_caster_seq[at] = _caster_seq
	_bm_turn[at] = 0.0
	var legs: int = maxi(spell.pierce, 0) + 1
	_fit_beam_legs(legs)
	for leg in legs:
		_bm_homing[at * _bm_legs + leg].start(spell, hash(Vector2i(_bm_born[at], leg)))
	_bm_count[at] = 0
	if _caster == CASTER_WIZARD:
		if _aim_dir[actor].is_finite():
			_bm_turn[at] = _aim_dir[actor].angle_to(heading)
	else:
		var shot: int = _caster_shot()
		var way: Vector2 = projectiles.get_velocity_of(shot) if shot >= 0 else Vector2.ZERO
		if way.is_zero_approx():
			_bm_caster[at] = CASTER_POINT
		else:
			_bm_turn[at] = way.angle_to(heading)
	shot_started(tag)
	_beam_step(at, 0.0)
	if _bm_on[at] != 0:
		_lc_join(spell, tag, LC_BEAM, at, _bm_born[at], true, lifetime, _bm_tip[at], _bm_dir[at])
	return true


## Runs live beam `at` on by `delta`: its life, where its caster holds it, its path and its hit.
func _beam_step(at: int, delta: float) -> void:
	_bm_life[at] -= delta
	if _bm_life[at] <= 0.0:
		_end_beam(at, true)
		return
	_beam_follow(at)
	if _bm_on[at] == 0:
		return
	_beam_path(at)
	_bm_tick[at] -= delta
	var hit: bool = _bm_tick[at] <= 0.0
	if hit:
		_bm_tick[at] = maxf(_bm_tick[at] + SpellLimits.BEAM_TICK, 0.001)
	var spell: CompiledSpell = _bm_spell[at]
	var tag: int = _bm_tag[at]
	_beam_cast(at, hit)
	# Every step, not only on its hits: a shot must not slip through between two ticks.
	if _bm_on[at] != 0 and _bm_spell[at] == spell and _bm_tag[at] == tag:
		_bm_shield[at] = _guard_path(spell, tag, _bm_actor[at], _bm_points, at * _bm_stride, _bm_count[at], _bm_reach[at], _beam_width(at), _bm_shield[at])


## Puts live beam `at` where its caster holds it now. A beam whose wizard has no aim any more
## (down, gone) ends quietly; one whose shot is gone stays where the shot last was.
func _beam_follow(at: int) -> void:
	var caster: int = _bm_caster[at]
	if caster == CASTER_WIZARD:
		var actor: int = _bm_actor[at]
		if _aim_origin[actor].is_finite():
			_bm_origin[at] = _aim_origin[actor]
			_bm_dir[at] = _aim_dir[actor].rotated(_bm_turn[at])
		elif _aim_seen[actor] != 0:
			_end_beam(at, false)
	elif caster >= 0:
		if projectiles.is_alive(caster) and projectiles.get_seq_of(caster) == _bm_caster_seq[at]:
			_bm_origin[at] = projectiles.get_position_of(caster)
			var way: Vector2 = projectiles.get_velocity_of(caster)
			if not way.is_zero_approx():
				_bm_dir[at] = way.normalized().rotated(_bm_turn[at])
		else:
			_bm_caster[at] = CASTER_POINT


## The path live beam `at` follows (`_bm_points`): straight along its way for its `ray_length`,
## or, when it homes, bent onto a target in front of it (picked by `Projectiles.homing_point` and
## kept while it can), then for each pierce it has bent on from there toward another, as a homing
## shot picks a new target after a hit; past the last it goes straight on. With spiral the whole
## path waves sideways (`_wave`). Its hits cut it at its `ray_length` (`ray_points`). `beam_bend`
## and `beam_end` keep its first curve. Where each
## leg's target is in the path goes to `_steer_goals`, for `_beam_steer`: a homing beam that turns
## at a wall homes again from there with the legs it has not reached.
func _beam_path(at: int) -> void:
	var spell: CompiledSpell = _bm_spell[at]
	var origin: Vector2 = _bm_origin[at]
	var way: Vector2 = _bm_dir[at]
	var length: float = spell.ray_length
	var legs: int = maxi(spell.pierce, 0) + 1 if spell.homing_range > 0.0 else 0
	_fit_beam_points(legs * ProjectilesScript.RAY_SEGMENTS + 2)
	var base: int = at * _bm_stride
	_bm_points[base] = origin
	var count: int = 1
	_bm_bend[at] = origin + way * (length * 0.5)
	_bm_end[at] = origin + way * length
	var from: Vector2 = origin
	var walked: float = 0.0
	_steer_goal_count = 0
	if spell.homing_range > 0.0:
		for leg in legs:
			var homing: Homing = _bm_homing[at * _bm_legs + leg]
			var goal: Vector2 = homing.point(projectiles, _bm_actor[at], from, way)
			if not goal.is_finite() or walked >= length or _picked_before(at, leg):
				homing.keep = 0
				break
			var bend: Vector2 = from + way * (from.distance_to(goal) * 0.6)
			if leg == 0:
				_bm_bend[at] = bend
				_bm_end[at] = goal
			for n in range(1, ProjectilesScript.RAY_SEGMENTS + 1):
				var t: float = float(n) / ProjectilesScript.RAY_SEGMENTS
				var u: float = 1.0 - t
				var point: Vector2 = from * (u * u) + bend * (2.0 * u * t) + goal * (t * t)
				walked += _bm_points[base + count - 1].distance_to(point)
				_bm_points[base + count] = point
				count += 1
			_add_steer_goal(count - 1)
			# It leaves the target the way the curve came in.
			if not goal.is_equal_approx(bend):
				way = bend.direction_to(goal)
			from = goal
	if walked < length:
		_bm_points[base + count] = from + way * (length - walked)
		count += 1
	var spiral: float = spell.behaviour(ModifierBase.Behaviour.SPIRAL)
	if spiral > 0.0:
		# It waves along the whole path; its legs' targets keep their place in it.
		var made: int = _wave(_bm_points, base + 1, count - 1, spiral * 0.5, origin)
		_fit_beam_points(made + 1)
		base = at * _bm_stride
		for n in made:
			_bm_points[base + 1 + n] = _wave_points[n]
		for k in _steer_goal_count:
			_steer_goals[k] = _wave_index[_steer_goals[k] - 1]
		count = made + 1
	_bm_count[at] = count


## A homing or spiral live beam (`_steer_row`) turned off a wall at point `turn` of its path
## (`at`, going `way` off the wall, `left` pixels of it left): it homes again from there, as it did
## from its staff, with the legs it had not reached before the wall (a leg's target past the turn
## was not reached: `_steer_goals`), then goes straight on for what is left, waving all the way
## with spiral. Returns the points after `at` (`Projectiles.ray_points` asks at every turn); the
## same rule as a homing or spiral shot, which steers and weaves again after it bounces.
func _beam_steer(turn: int, at: Vector2, way: Vector2, left: float) -> PackedVector2Array:
	var row: int = _steer_row
	var spell: CompiledSpell = _bm_spell[row] if row >= 0 else null
	var count: int = 0
	var spiral: float = spell.behaviour(ModifierBase.Behaviour.SPIRAL) if spell != null else 0.0
	if spell == null or (spell.homing_range <= 0.0 and spiral <= 0.0):
		_steer_points.resize(0)
		return _steer_points
	var reached: int = 0
	while reached < _steer_goal_count and _steer_goals[reached] < turn:
		reached += 1
	_steer_goal_count = reached
	var legs: int = maxi(spell.pierce, 0) + 1 if spell.homing_range > 0.0 else 0
	var from: Vector2 = at
	var heading: Vector2 = way
	var walked: float = 0.0
	if _steer_points.size() < legs * ProjectilesScript.RAY_SEGMENTS + 1:
		_steer_points.resize(legs * ProjectilesScript.RAY_SEGMENTS + 1)
	for leg in range(reached, mini(legs, _bm_legs)):
		var homing: Homing = _bm_homing[row * _bm_legs + leg]
		var goal: Vector2 = homing.point(projectiles, _bm_actor[row], from, heading)
		if not goal.is_finite() or walked >= left or _picked_before(row, leg):
			homing.keep = 0
			break
		var bend: Vector2 = from + heading * (from.distance_to(goal) * 0.6)
		var prev: Vector2 = from
		for n in range(1, ProjectilesScript.RAY_SEGMENTS + 1):
			var t: float = float(n) / ProjectilesScript.RAY_SEGMENTS
			var u: float = 1.0 - t
			var point: Vector2 = from * (u * u) + bend * (2.0 * u * t) + goal * (t * t)
			walked += prev.distance_to(point)
			_steer_points[count] = point
			count += 1
			prev = point
		# The goal's index in the path: the turn's, plus the points after it.
		_add_steer_goal(turn + count)
		if not goal.is_equal_approx(bend):
			heading = bend.direction_to(goal)
		from = goal
	if walked < left:
		if _steer_points.size() <= count:
			_steer_points.resize(count + 1)
		_steer_points[count] = from + heading * (left - walked)
		count += 1
	if spiral > 0.0 and count > 0:
		var made: int = _wave(_steer_points, 0, count, spiral * 0.5, at)
		for k in range(reached, _steer_goal_count):
			_steer_goals[k] = turn + _wave_index[_steer_goals[k] - turn - 1]
		if _steer_points.size() < made:
			_steer_points.resize(made)
		for n in made:
			_steer_points[n] = _wave_points[n]
		count = made
	_steer_points.resize(count)
	return _steer_points


## Notes that a leg's target is point `index` of the steered beam's path.
func _add_steer_goal(index: int) -> void:
	if _steer_goal_count == _steer_goals.size():
		_steer_goals.resize(maxi(8, _steer_goal_count * 2))
	_steer_goals[_steer_goal_count] = index
	_steer_goal_count += 1


## True when leg `leg` of live beam `at` picked a target an earlier leg already bent to: the
## beam then goes straight on instead of doubling back.
func _picked_before(at: int, leg: int) -> bool:
	var id: int = _bm_homing[at * _bm_legs + leg].keep
	for before in leg:
		if _bm_homing[at * _bm_legs + before].keep == id:
			return true
	return false


## Live beam `at` along its curve: with `hit`, its hits, payloads and chain jumps (in the beam
## context `_ray_*` that `_on_hit` reads); without, only how far it gets.
func _beam_cast(at: int, hit: bool) -> void:
	var spell: CompiledSpell = _bm_spell[at]
	var tag: int = _bm_tag[at]
	var actor: int = _bm_actor[at]
	var source: Node = _bm_source[at] if is_instance_valid(_bm_source[at]) else null
	var bounces: int = _bounces(spell)
	var ghost: bool = _ghost(spell)
	var width: float = _beam_width(at)
	# A homing or spiral beam that turns at a wall homes and waves again from there (`_beam_steer`).
	var steer: Callable = _steer_call if bounces > 0 and (spell.homing_range > 0.0 or spell.behaviour(ModifierBase.Behaviour.SPIRAL) > 0.0) else Callable()
	_steer_row = at
	if not hit:
		_bm_reach[at] = projectiles.ray_points(actor, _bm_points, at * _bm_stride, _bm_count[at], spell.ray_length, _ray_pierce(spell), HITS, tag, width, source, false, bounces, steer, ghost)
		_bm_tip[at] = projectiles.ray_end
		_bm_tip_dir[at] = projectiles.ray_end_heading
		if bounces > 0:
			_beam_keep_path(at)
		return
	var saved_tag: int = _ray_tag
	var saved_dir: Vector2 = _ray_dir
	var saved_chain: int = _ray_chain
	var saved_prev: int = _ray_prev
	var saved_hit: HitProfile = _ray_hit
	var saved_arc: int = _arc_slot
	_ray_tag = tag
	_ray_dir = _bm_dir[at]
	_ray_chain = _bm_chain[at]
	_ray_prev = _bm_prev[at]
	_ray_hit = _bm_hit[at]
	_arc_slot = -1
	var got: float = projectiles.ray_points(actor, _bm_points, at * _bm_stride, _bm_count[at], spell.ray_length, _ray_pierce(spell), HITS, tag, width, source, true, bounces, steer, ghost)
	var tip: Vector2 = projectiles.ray_end
	var tip_dir: Vector2 = projectiles.ray_end_heading
	var turned: bool = bounces > 0 and projectiles.ray_path_count > 0
	# What relay took on stays for its later hits.
	var took: HitProfile = _ray_hit
	_ray_tag = saved_tag
	_ray_dir = saved_dir
	_ray_chain = saved_chain
	_ray_prev = saved_prev
	_ray_hit = saved_hit
	_arc_slot = saved_arc
	# A hit handler may have ended this beam (a rebuild) or reused its row.
	if _bm_on[at] != 0 and _bm_spell[at] == spell and _bm_tag[at] == tag:
		_bm_hit[at] = took
		_bm_reach[at] = got
		_bm_tip[at] = tip
		_bm_tip_dir[at] = tip_dir
		_bm_hit_at[at] = _clock
		if turned:
			_beam_keep_path(at)
	_cast_jumps()


## Live beam `at` follows the path its last ray walked (`Projectiles.ray_path`), so a beam that
## turned at walls is drawn along its turns.
func _beam_keep_path(at: int) -> void:
	var count: int = projectiles.ray_path_count
	if count < 2:
		return
	_fit_beam_points(count)
	var base: int = at * _bm_stride
	for n in count:
		_bm_points[base + n] = projectiles.ray_path[n]
	_bm_count[at] = count


## How many times `spell`'s beam or fissure turns at a wall: its bounce cards' count.
func _bounces(spell: CompiledSpell) -> int:
	return roundi(spell.behaviour(ModifierBase.Behaviour.BOUNCE))


## True when `spell`'s rays pass through walls (ghost), as its shots do.
static func _ghost(spell: CompiledSpell) -> bool:
	return spell.behaviour(ModifierBase.Behaviour.GHOST) > 0.0


## How many targets past the first a ray of `spell` hits, a chain jump of it too (rules R4f): a
## fissure every one on its line, anything else its pierce.
static func _ray_pierce(spell: CompiledSpell) -> int:
	return PIERCE_ALL if spell.motion == FormBase.Motion.FISSURE else spell.pierce


## How far either side of its line live beam `at` hits: half its carrier's size, times its
## growth for every second it has been on, up to the room's size (as a growing shot).
func _beam_width(at: int) -> float:
	var spell: CompiledSpell = _bm_spell[at]
	var width: float = spell.radius * 0.5
	var growth: float = spell.behaviour(ModifierBase.Behaviour.GROWTH)
	if growth > 1.0:
		width = minf(width * pow(growth, _bm_span[at] - _bm_life[at]), maxf(projectiles.room_size(), width))
	return width


## Live beam `at` pulls (magnet) the enemies within its card's reach toward its line: one pull for
## each piece of its path, as far as it got (`pull_requested` with the piece's two ends).
func _beam_pull(at: int) -> void:
	var spell: CompiledSpell = _bm_spell[at]
	var reach: float = spell.behaviour(ModifierBase.Behaviour.MAGNET)
	var base: int = at * _bm_stride
	var walked: float = 0.0
	for n in _bm_count[at] - 1:
		if walked >= _bm_reach[at]:
			break
		var a: Vector2 = _bm_points[base + n]
		var b: Vector2 = _bm_points[base + n + 1]
		var piece: float = a.distance_to(b)
		if walked + piece > _bm_reach[at]:
			b = a.move_toward(b, _bm_reach[at] - walked)
		events.pull_requested.emit(_bm_actor[at], a, reach, SpellLimits.MAGNET_PULL, _bm_tag[at], b)
		walked += piece


## The path `start`, `points[first]` .. `points[first + count - 1]` waving sideways (spiral on a
## beam, rules R4f), as a spiral shot weaves round its line: every piece cut into pieces of
## BEAM_WAVE / BEAM_WAVE_STEPS pixels at most, each new point moved `amp * sin` of how far along
## it is (a wave every BEAM_WAVE pixels; `start` stays put) off its piece. The points after
## `start` go to `_wave_points`; `_wave_index[i]` is how many of them reach `points[first + i]`
## (its index in the waved path, `start` being 0). Returns how many. Allocation-free once grown.
func _wave(points: PackedVector2Array, first: int, count: int, amp: float, start: Vector2) -> int:
	var most: float = SpellLimits.BEAM_WAVE / SpellLimits.BEAM_WAVE_STEPS
	if _wave_index.size() < count:
		_wave_index.resize(count)
	var made: int = 0
	var walked: float = 0.0
	var from: Vector2 = start
	for i in count:
		var to: Vector2 = points[first + i]
		var piece: float = from.distance_to(to)
		var pieces: int = maxi(ceili(piece / most), 1)
		var side: Vector2 = from.direction_to(to).orthogonal()
		if _wave_points.size() < made + pieces:
			_wave_points.resize(maxi(made + pieces, _wave_points.size() * 2))
		for n in range(1, pieces + 1):
			var t: float = float(n) / pieces
			_wave_points[made] = from.lerp(to, t) + side * (amp * sin(TAU * (walked + piece * t) / SpellLimits.BEAM_WAVE))
			made += 1
		_wave_index[i] = made
		walked += piece
		from = to
	return made


## Live beam `at` is over. With `finished` (its life ran out), its `blast` and its `on expire`
## payload happen where it ends; a beam switched off, rebuilt or dropped ends quietly.
func _end_beam(at: int, finished: bool) -> void:
	if _bm_on[at] == 0:
		return
	_bm_on[at] = 0
	var spell: CompiledSpell = _bm_spell[at]
	var tag: int = _bm_tag[at]
	var actor: int = _bm_actor[at]
	_bm_spell[at] = null
	_bm_source[at] = null
	_bm_hit[at] = null
	var tip: Vector2 = _bm_tip[at]
	if finished and spell != null and _bm_reach[at] > 0.0 and tip.is_finite():
		_blast(spell, tag, actor, tip)
		if spell.payload != null and spell.trigger_event == TriggerBase.Event.EXPIRE:
			_fire_payload(spell, tag, actor, tip, _bm_tip_dir[at] if not _bm_tip_dir[at].is_zero_approx() else _bm_dir[at], null)
	shot_ended(tag)


## Doubles the live beam rows (every one is on). A frame allocates only the first time it has
## more beams than any before it.
func _grow_beams() -> void:
	var size: int = _bm_on.size() * 2
	_bm_on.resize(size)
	_bm_born.resize(size)
	_bm_spell.resize(size)
	_bm_source.resize(size)
	_bm_tag.resize(size)
	_bm_actor.resize(size)
	_bm_caster.resize(size)
	_bm_caster_seq.resize(size)
	_bm_life.resize(size)
	_bm_span.resize(size)
	_bm_tick.resize(size)
	_bm_turn.resize(size)
	_bm_count.resize(size)
	_bm_chain.resize(size)
	_bm_prev.resize(size)
	_bm_hit.resize(size)
	_bm_shield.resize(size)
	_bm_origin.resize(size)
	_bm_dir.resize(size)
	_bm_bend.resize(size)
	_bm_end.resize(size)
	_bm_reach.resize(size)
	_bm_tip.resize(size)
	_bm_tip_dir.resize(size)
	_bm_hit_at.resize(size)
	_bm_points.resize(size * _bm_stride)
	while _bm_homing.size() < size * _bm_legs:
		_bm_homing.append(Homing.new())


## Every live beam row has room for `count` points: the rows are laid out again, wider, the
## first time a beam needs more (a homing beam with more pierce, a beam turning at more walls).
func _fit_beam_points(count: int) -> void:
	if count <= _bm_stride:
		return
	var stride: int = maxi(count, _bm_stride * 2)
	var points := PackedVector2Array()
	points.resize(_bm_on.size() * stride)
	for row in _bm_on.size():
		for n in mini(_bm_count[row], _bm_stride):
			points[row * stride + n] = _bm_points[row * _bm_stride + n]
	_bm_points = points
	_bm_stride = stride


## Every live beam row has room for `legs` homing legs (laid out again, wider, when it has not).
func _fit_beam_legs(legs: int) -> void:
	if legs <= _bm_legs:
		return
	var width: int = maxi(legs, _bm_legs * 2)
	var homing: Array[Homing] = []
	for row in _bm_on.size():
		for leg in width:
			homing.append(_bm_homing[row * _bm_legs + leg] if leg < _bm_legs else Homing.new())
	_bm_homing = homing
	_bm_legs = width


## Ends the live beams of `tag` quietly (a `hold` switched off, a revoked build).
func _end_beams_of(tag: int) -> void:
	for at in _bm_on.size():
		if _bm_on[at] != 0 and _bm_tag[at] == tag:
			_end_beam(at, false)


## Runs every live beam on by `delta` (a beam started meanwhile, by a payload, waits for the next).
func _step_beams(delta: float) -> void:
	var first_new: int = _bm_next_born
	for at in _bm_on.size():
		if _bm_on[at] != 0 and _bm_born[at] < first_new:
			_beam_step(at, delta)


## A swing (`swing` carrier, melee I2; docs/milestones/M2-staffs.md, "Phase I: melee"): the staff
## leans back for the carrier's `wind_up`, then sweeps its `arc` round the wizard's hand in its
## `lifetime`, out to its `ray_length`, centred on the aim locked now. Each step it strikes every
## body in the wedge it turned through since the last step (`Projectiles.sweep`), so a fast
## sweep misses nothing, and each body once; its hits carry payloads and chains as a beam's do.
## Swings turn clockwise and back by turns, and one cast within SWING_CHAIN of the last sweep's
## end has no wind-up. It is held by its caster as a beam is: the wizard's hand (`set_aim`), the
## shot that cast it, or a fixed point. Its `blast` and `on expire` happen at the end of the arc.
## Returns false when it could not start (no direction).
func _start_swing(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, heading: Vector2, chain: int, prev: int, source: Node) -> bool:
	if not heading.is_finite() or heading.is_zero_approx() or not origin.is_finite():
		return false
	# A free row, or new rows when every one is on: no swing ends another.
	var at: int = _sw_on.find(0)
	if at < 0:
		at = _sw_on.size()
		_grow_swings(at * 2)
	var side: int = 1
	var wind: float = maxf(spell.wind_up, 0.0)
	var mine: bool = actor >= 0 and actor < ACTORS
	# The first swing of a cast is the body's; the others of the same cast (a split, a mirror) turn
	# the same way and move no body of their own.
	var first: bool = true
	if mine:
		first = _sw_last_start[actor] != _clock
		side = -_sw_last_side[actor] if first else _sw_last_side[actor]
		_sw_last_side[actor] = side
		_sw_last_start[actor] = _clock
		if _clock - _sw_last_end[actor] <= SpellLimits.SWING_CHAIN:
			wind = 0.0
	var half: float = deg_to_rad(spell.arc) * 0.5
	_sw_on[at] = 1
	_sw_born[at] = _sw_next_born
	_sw_next_born += 1
	_sw_spell[at] = spell
	_sw_source[at] = source
	_sw_tag[at] = tag
	_sw_actor[at] = actor
	_sw_caster[at] = _caster
	_sw_caster_seq[at] = _caster_seq
	_sw_origin[at] = origin
	_sw_dir[at] = heading.normalized()
	_sw_side[at] = side
	_sw_age[at] = 0.0
	_sw_wind[at] = wind
	_sw_turned[at] = -(half + deg_to_rad(SpellLimits.SWING_LEAN))
	_sw_chain[at] = chain
	_sw_prev[at] = prev
	_sw_echo[at] = 1 if _echo_spell == spell else 0
	_sw_shield[at] = roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD))
	_sw_struck[at].clear()
	_sw_points[at].clear()
	_sw_heads[at].clear()
	if _caster == CASTER_WIZARD:
		if mine and _aim_pivot[actor].is_finite():
			_sw_origin[at] = _aim_pivot[actor]
		if mine and first:
			_start_pose(actor, spell, tag, wind, maxf(spell.lifetime, 0.001), _sw_dir[at], side, true)
	elif _caster_shot() < 0:
		_sw_caster[at] = CASTER_POINT
	shot_started(tag)
	_swing_step(at, 0.0)
	if _sw_on[at] != 0:
		_lc_join(spell, tag, LC_SWING, at, _sw_born[at], true, wind + spell.lifetime, swing_tip(at), _sw_dir[at])
	return true


## Runs swing `at` on by `delta`: where its caster holds it, then, past its wind-up, its sweep.
func _swing_step(at: int, delta: float) -> void:
	_sw_age[at] += delta
	_swing_follow(at)
	if _sw_on[at] == 0:
		return
	var spell: CompiledSpell = _sw_spell[at]
	var into: float = _sw_age[at] - _sw_wind[at]
	if into < 0.0:
		return
	var tag: int = _sw_tag[at]
	var sweep: float = maxf(spell.lifetime, 0.001)
	var half: float = deg_to_rad(spell.arc) * 0.5
	var lean: float = half + deg_to_rad(SpellLimits.SWING_LEAN)
	var turned: float = lerpf(-lean, lean, swing_ease(clampf(into / sweep, 0.0, 1.0)))
	var from: float = maxf(_sw_turned[at], -half)
	var to: float = minf(turned, half)
	_sw_turned[at] = turned
	if to >= from:
		_swing_guard(at, from, to)
		if _sw_on[at] == 0 or _sw_spell[at] != spell or _sw_tag[at] != tag:
			return
		_swing_cast(at, from, to)
	if into >= sweep and _sw_on[at] != 0 and _sw_spell[at] == spell and _sw_tag[at] == tag:
		_end_swing(at, true)


## How far through its turn a sweep is, `x` of its time gone: slow, fast, slow (the playground's).
static func swing_ease(x: float) -> float:
	return 2.0 * x * x if x < 0.5 else 1.0 - 2.0 * (1.0 - x) * (1.0 - x)


## Puts swing `at` where its caster holds it now: the wizard's hand (a wizard with no aim any more,
## down or gone, ends it quietly), or the shot that cast it while that flies.
func _swing_follow(at: int) -> void:
	var caster: int = _sw_caster[at]
	if caster == CASTER_WIZARD:
		var actor: int = _sw_actor[at]
		if actor < 0 or actor >= ACTORS:
			return
		if _aim_origin[actor].is_finite():
			_sw_origin[at] = _aim_pivot[actor] if _aim_pivot[actor].is_finite() else _aim_origin[actor]
		elif _aim_seen[actor] != 0:
			_end_swing(at, false)
	elif caster >= 0:
		if projectiles.is_alive(caster) and projectiles.get_seq_of(caster) == _sw_caster_seq[at]:
			_sw_origin[at] = projectiles.get_position_of(caster)
		else:
			_sw_caster[at] = CASTER_POINT


## Swing `at` turned from `from` to `to` radians off its aim: the shots of other teams in that
## wedge are deflected outward from the hand (`deflect`), else stopped while its shield has
## charges (melee I3).
func _swing_guard(at: int, from: float, to: float) -> void:
	var spell: CompiledSpell = _sw_spell[at]
	var deflects: bool = spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0
	if not deflects and _sw_shield[at] <= 0:
		return
	var origin: Vector2 = _sw_origin[at]
	var found: int = projectiles.shots_in_wedge(_sw_actor[at], origin, _sw_dir[at], _sw_side[at], from, to, spell.ray_length)
	_sw_shield[at] = _guard(found, _sw_actor[at], _sw_tag[at], deflects, _sw_shield[at], origin, Vector2.INF)


## Swing `at` turned from `from` to `to` radians off its aim: it strikes each body in that wedge it
## has not struck yet (in the beam context `_ray_*` that `_on_hit` reads), outward from its hand.
func _swing_cast(at: int, from: float, to: float) -> void:
	var spell: CompiledSpell = _sw_spell[at]
	var tag: int = _sw_tag[at]
	var actor: int = _sw_actor[at]
	var source: Node = _sw_source[at] if is_instance_valid(_sw_source[at]) else null
	var origin: Vector2 = _sw_origin[at]
	var found: int = projectiles.sweep(actor, origin, _sw_dir[at], _sw_side[at], from, to, spell.ray_length, HITS, source)
	if found == 0:
		return
	var struck: Array = _sw_struck[at]
	var points: Array = _sw_points[at]
	var heads: Array = _sw_heads[at]
	var first: int = struck.size()
	for i in found:
		var node: Node = projectiles.sweep_nodes[i]
		if struck.has(node):
			continue
		struck.append(node)
		points.append(projectiles.sweep_points[i])
		heads.append(projectiles.sweep_heads[i])
	var last: int = struck.size()
	if last == first:
		return
	var saved_tag: int = _ray_tag
	var saved_dir: Vector2 = _ray_dir
	var saved_chain: int = _ray_chain
	var saved_prev: int = _ray_prev
	var saved_hit: HitProfile = _ray_hit
	var saved_arc: int = _arc_slot
	_ray_tag = tag
	_ray_chain = _sw_chain[at]
	_ray_prev = _sw_prev[at]
	_ray_hit = spell.echo_hit if _sw_echo[at] != 0 else null
	_arc_slot = -1
	for row in range(first, last):
		# A hit handler may have ended this swing (a rebuild) or reused its row.
		if _sw_on[at] == 0 or _sw_tag[at] != tag:
			break
		var point: Vector2 = points[row]
		_ray_dir = origin.direction_to(point) if not origin.is_equal_approx(point) else _sw_dir[at]
		projectiles.strike(actor, struck[row], point, heads[row], tag, &"swing")
	_ray_tag = saved_tag
	_ray_dir = saved_dir
	_ray_chain = saved_chain
	_ray_prev = saved_prev
	_ray_hit = saved_hit
	_arc_slot = saved_arc
	_cast_jumps()


## Swing `at` is over. With `finished` (its sweep is done), its `blast` and `on expire` payload
## happen at the end of its arc, and its caster's next swing may chain on; one ended early (a
## rebuild, its wizard down, the cap) ends quietly.
func _end_swing(at: int, finished: bool) -> void:
	if _sw_on[at] == 0:
		return
	_sw_on[at] = 0
	var spell: CompiledSpell = _sw_spell[at]
	var tag: int = _sw_tag[at]
	var actor: int = _sw_actor[at]
	_sw_spell[at] = null
	_sw_source[at] = null
	_sw_struck[at].clear()
	if finished and spell != null:
		if actor >= 0 and actor < ACTORS:
			_sw_last_end[actor] = _clock
		var end: Vector2 = swing_end_point(_sw_origin[at], _sw_dir[at], _sw_side[at], spell.arc, spell.ray_length)
		end = projectiles.clip_to_walls(_sw_origin[at], end)
		_blast(spell, tag, actor, end)
		if spell.payload != null and spell.trigger_event == TriggerBase.Event.EXPIRE:
			_fire_payload(spell, tag, actor, end, _sw_dir[at], null)
	shot_ended(tag)


## The end point of a swing round `origin` aimed along `direction`, turning `side` through `arc`
## degrees out to `reach`: where its arc ends.
static func swing_end_point(origin: Vector2, direction: Vector2, side: int, arc: float, reach: float) -> Vector2:
	return origin + direction.normalized().rotated(deg_to_rad(arc) * 0.5 * (1.0 if side >= 0 else -1.0)) * reach


## Where the tip of swing `at`'s staff is now: on its arc as far as it has turned (leaning back
## before its sweep), `ray_length` out.
func swing_tip(at: int) -> Vector2:
	var half: float = deg_to_rad(swing_arc(at)) * 0.5
	var turned: float = clampf(_sw_turned[at], -half, half) * (1.0 if _sw_side[at] >= 0 else -1.0)
	return _sw_origin[at] + _sw_dir[at].rotated(turned) * swing_reach(at)


## Makes room for `size` swing rows (the new ones off, each with its own struck list).
func _grow_swings(size: int) -> void:
	var old: int = _sw_on.size()
	_sw_on.resize(size)
	_sw_born.resize(size)
	_sw_spell.resize(size)
	_sw_source.resize(size)
	_sw_tag.resize(size)
	_sw_actor.resize(size)
	_sw_caster.resize(size)
	_sw_caster_seq.resize(size)
	_sw_origin.resize(size)
	_sw_dir.resize(size)
	_sw_side.resize(size)
	_sw_age.resize(size)
	_sw_wind.resize(size)
	_sw_turned.resize(size)
	_sw_chain.resize(size)
	_sw_prev.resize(size)
	_sw_echo.resize(size)
	_sw_shield.resize(size)
	for i in range(old, size):
		_sw_struck.append([])
		_sw_points.append([])
		_sw_heads.append([])


## Ends the swings of `tag` quietly (a revoked build, a hold switched off).
func _end_swings_of(tag: int) -> void:
	for at in _sw_on.size():
		if _sw_on[at] != 0 and _sw_tag[at] == tag:
			_end_swing(at, false)


## A slam (`slam` carrier, melee I8; docs/milestones/M2-staffs.md, "Phase I: melee"): the staff
## rises for the carrier's `wind_up`, held by its caster as a swing is (the wizard's hand, the shot
## that cast it, or a point), with the aim locked now; then it strikes the floor `ray_length`
## ahead (short of a wall) and a ring grows from there to its `radius` over SLAM_GROW of its
## `lifetime` and holds for the rest. The ring strikes each body in it once (`Projectiles.sweep`
## all round the impact, so a wall between hides a body), outward from the impact, so the hit's
## knockback throws it outward; its caster's own body is skipped, a teammate is hit. Its hits carry
## payloads and chains as a beam's do, and a shield or deflect works on the shots in its ring. Its
## `blast` and `on expire` happen at the impact when the ring is done. `form_shown` tells looks of
## the wind-up (`slam_mark`: where it will strike, for the seconds until then) and the impact.
## Returns false when it could not start (no direction).
func _start_slam(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, heading: Vector2, chain: int, prev: int, source: Node) -> bool:
	if not heading.is_finite() or heading.is_zero_approx() or not origin.is_finite():
		return false
	var at: int = _sl_on.find(0)
	if at < 0:
		at = _sl_on.size()
		_grow_slams(at * 2)
	_sl_on[at] = 1
	_sl_born[at] = _sl_next_born
	_sl_next_born += 1
	_sl_spell[at] = spell
	_sl_source[at] = source
	_sl_tag[at] = tag
	_sl_actor[at] = actor
	_sl_caster[at] = _caster
	_sl_caster_seq[at] = _caster_seq
	_sl_origin[at] = origin
	_sl_dir[at] = heading.normalized()
	_sl_impact[at] = Vector2.INF
	_sl_age[at] = 0.0
	_sl_wind[at] = maxf(spell.wind_up, 0.0)
	_sl_chain[at] = chain
	_sl_prev[at] = prev
	_sl_echo[at] = 1 if _echo_spell == spell else 0
	_sl_shield[at] = roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD))
	_sl_struck[at].clear()
	var mine: bool = actor >= 0 and actor < ACTORS
	if _caster == CASTER_WIZARD:
		if mine and _aim_pivot[actor].is_finite():
			_sl_origin[at] = _aim_pivot[actor]
		if mine and _pose_start[actor] != _clock:
			_start_pose(actor, spell, tag, _sl_wind[at], maxf(spell.lifetime, 0.001), _sl_dir[at], up_side(_sl_dir[at]), true)
	elif _caster_shot() < 0:
		_sl_caster[at] = CASTER_POINT
	shot_started(tag)
	if events != null and _sl_wind[at] > 0.0:
		var mark: Vector2 = projectiles.clip_to_walls(_sl_origin[at], _sl_origin[at] + _sl_dir[at] * spell.ray_length)
		events.form_shown.emit(actor, &"slam_mark", mark, _sl_dir[at], _sl_wind[at], spell.tint, spell.look)
	_slam_step(at, 0.0)
	return true


## Runs slam `at` on by `delta`: held by its caster through its wind-up, then its impact and ring.
func _slam_step(at: int, delta: float) -> void:
	_sl_age[at] += delta
	var spell: CompiledSpell = _sl_spell[at]
	var tag: int = _sl_tag[at]
	if not _sl_impact[at].is_finite():
		_slam_follow(at)
		if _sl_on[at] == 0 or _sl_age[at] < _sl_wind[at]:
			return
		var impact: Vector2 = projectiles.clip_to_walls(_sl_origin[at], _sl_origin[at] + _sl_dir[at] * spell.ray_length)
		_sl_impact[at] = impact
		if events != null:
			events.form_shown.emit(_sl_actor[at], &"slam", impact, _sl_dir[at], spell.radius, spell.tint, spell.look)
	var into: float = _sl_age[at] - _sl_wind[at]
	var life: float = maxf(spell.lifetime, 0.001)
	var reach: float = spell.radius * clampf(into / (life * SpellLimits.SLAM_GROW), 0.0, 1.0)
	_slam_guard(at, reach)
	if _sl_on[at] == 0 or _sl_spell[at] != spell or _sl_tag[at] != tag:
		return
	_slam_cast(at, reach)
	if into >= life and _sl_on[at] != 0 and _sl_spell[at] == spell and _sl_tag[at] == tag:
		_end_slam(at, true)


## Puts slam `at` where its caster holds it now, until it strikes (as `_swing_follow`).
func _slam_follow(at: int) -> void:
	var caster: int = _sl_caster[at]
	if caster == CASTER_WIZARD:
		var actor: int = _sl_actor[at]
		if actor < 0 or actor >= ACTORS:
			return
		if _aim_origin[actor].is_finite():
			_sl_origin[at] = _aim_pivot[actor] if _aim_pivot[actor].is_finite() else _aim_origin[actor]
		elif _aim_seen[actor] != 0:
			_end_slam(at, false)
	elif caster >= 0:
		if projectiles.is_alive(caster) and projectiles.get_seq_of(caster) == _sl_caster_seq[at]:
			_sl_origin[at] = projectiles.get_position_of(caster)
		else:
			_sl_caster[at] = CASTER_POINT


## The shots of other teams in slam `at`'s ring (`reach` across now): deflected outward from the
## impact (`deflect`), else stopped while its shield has charges (melee I3).
func _slam_guard(at: int, reach: float) -> void:
	var spell: CompiledSpell = _sl_spell[at]
	var deflects: bool = spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0
	if (not deflects and _sl_shield[at] <= 0) or reach <= 0.0:
		return
	var impact: Vector2 = _sl_impact[at]
	var found: int = projectiles.shots_in_wedge(_sl_actor[at], impact, _sl_dir[at], 1, -PI, PI, reach)
	_sl_shield[at] = _guard(found, _sl_actor[at], _sl_tag[at], deflects, _sl_shield[at], impact, Vector2.INF, &"slam")


## Slam `at`'s ring, `reach` across now: it strikes each body in it it has not struck yet, outward
## from the impact, in the beam context `_ray_*` that `_on_hit` reads (as `_swing_cast`).
func _slam_cast(at: int, reach: float) -> void:
	if reach <= 0.0:
		return
	var spell: CompiledSpell = _sl_spell[at]
	var tag: int = _sl_tag[at]
	var actor: int = _sl_actor[at]
	var source: Node = _sl_source[at] if is_instance_valid(_sl_source[at]) else null
	var impact: Vector2 = _sl_impact[at]
	var found: int = projectiles.sweep(actor, impact, _sl_dir[at], 1, -PI, PI, reach, HITS, source)
	if found == 0:
		return
	var struck: Array = _sl_struck[at]
	var first: int = struck.size()
	for i in found:
		var node: Node = projectiles.sweep_nodes[i]
		if not struck.has(node):
			struck.append(node)
	var last: int = struck.size()
	if last == first:
		return
	var saved_tag: int = _ray_tag
	var saved_dir: Vector2 = _ray_dir
	var saved_chain: int = _ray_chain
	var saved_prev: int = _ray_prev
	var saved_echo: CompiledSpell = _echo_spell
	var saved_hit: HitProfile = _ray_hit
	_ray_tag = tag
	_ray_hit = null
	_ray_chain = _sl_chain[at]
	_ray_prev = _sl_prev[at]
	_echo_spell = spell if _sl_echo[at] != 0 else null
	for row in range(first, last):
		# A hit handler may have ended this slam (a rebuild) or reused its row.
		if _sl_on[at] == 0 or _sl_tag[at] != tag:
			break
		var node: Node = struck[row]
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var body: Vector2 = (node as Node2D).global_position
		var out: Vector2 = impact.direction_to(body) if not impact.is_equal_approx(body) else _sl_dir[at]
		_ray_dir = out
		# Struck at the impact, so the hit's push throws it outward from there.
		projectiles.strike(actor, node, impact, out, tag, &"slam")
	_ray_tag = saved_tag
	_ray_dir = saved_dir
	_ray_chain = saved_chain
	_ray_prev = saved_prev
	_echo_spell = saved_echo
	_ray_hit = saved_hit
	_cast_jumps()


## Slam `at` is over. With `finished` (its ring is done), its `blast` and `on expire` payload happen
## at the impact, the payload along the slam's aim; one ended early ends quietly.
func _end_slam(at: int, finished: bool) -> void:
	if _sl_on[at] == 0:
		return
	_sl_on[at] = 0
	var spell: CompiledSpell = _sl_spell[at]
	var tag: int = _sl_tag[at]
	var actor: int = _sl_actor[at]
	var impact: Vector2 = _sl_impact[at]
	_sl_spell[at] = null
	_sl_source[at] = null
	_sl_struck[at].clear()
	if finished and spell != null and impact.is_finite():
		_blast(spell, tag, actor, impact)
		if spell.payload != null and spell.trigger_event == TriggerBase.Event.EXPIRE:
			_fire_payload(spell, tag, actor, impact, _sl_dir[at], null)
	shot_ended(tag)


## Makes room for `size` slam rows (the new ones off, each with its own struck list).
func _grow_slams(size: int) -> void:
	var old: int = _sl_on.size()
	_sl_on.resize(size)
	_sl_born.resize(size)
	_sl_spell.resize(size)
	_sl_source.resize(size)
	_sl_tag.resize(size)
	_sl_actor.resize(size)
	_sl_caster.resize(size)
	_sl_caster_seq.resize(size)
	_sl_origin.resize(size)
	_sl_dir.resize(size)
	_sl_impact.resize(size)
	_sl_age.resize(size)
	_sl_wind.resize(size)
	_sl_chain.resize(size)
	_sl_prev.resize(size)
	_sl_echo.resize(size)
	_sl_shield.resize(size)
	for i in range(old, size):
		_sl_struck.append([])


## Ends the slams of `tag` quietly (a revoked build, a hold switched off).
func _end_slams_of(tag: int) -> void:
	for at in _sl_on.size():
		if _sl_on[at] != 0 and _sl_tag[at] == tag:
			_end_slam(at, false)


## Runs every live slam on by `delta` (one started meanwhile, by a payload, waits for the next).
func _step_slams(delta: float) -> void:
	var first_new: int = _sl_next_born
	for at in _sl_on.size():
		if _sl_on[at] != 0 and _sl_born[at] < first_new:
			_slam_step(at, delta)


## Live slams over every caster, and whether row `at` is one, for tests.
func slam_count() -> int:
	return _sl_on.count(1)


func slam_slots() -> int:
	return _sl_on.size()


func slam_on(at: int) -> bool:
	return at >= 0 and at < _sl_on.size() and _sl_on[at] != 0


## Where slam `at` struck (INF while it winds up).
func slam_impact(at: int) -> Vector2:
	return _sl_impact[at]


## Runs every live swing on by `delta` (one started meanwhile, by a payload, waits for the next).
func _step_swings(delta: float) -> void:
	var first_new: int = _sw_next_born
	for at in _sw_on.size():
		if _sw_on[at] != 0 and _sw_born[at] < first_new:
			_swing_step(at, delta)


## Numbers a pose has: FormBase.POSE_CHANNELS (turn, lift, push, glow, stretch, shake).
const POSE_CHANNELS: int = 6


## How long `spell`'s strike lasts for its staff animation (`FormBase.staff_pose`): the working time
## of a carrier the staff keeps working (a beam's, rain's or dash's `lifetime`, a held one's until its
## last shot ends); none for one that leaves the staff (a bolt, a rune, an orbit).
static func _pose_strike_of(spell: CompiledSpell, lifetime: float) -> float:
	match spell.motion:
		FormBase.Motion.RAY, FormBase.Motion.RAIN, FormBase.Motion.DASH:
			return maxf(lifetime, 0.0)
	return 0.0


## Starts `actor`'s staff animation for `spell` (its `staff_pose`, cast with `tag`) now: `wind` and
## `strike` seconds of wind-up and strike, the aim `dir` locked now, turning `side` (1, or -1 for a
## backhand). It starts from where the last one has the staff now, so a new cast never jumps.
func _start_pose(actor: int, spell: CompiledSpell, tag: int, wind: float, strike: float, dir: Vector2, side: int, lock: bool = false) -> void:
	var at: int = actor * POSE_CHANNELS
	var was: Vector2 = staff_pose_dir(actor)
	if was.is_zero_approx():
		for c in POSE_CHANNELS:
			_pose_from[at + c] = 0.0
	else:
		_pose_now(actor)
		var heading: float = was.angle() + deg_to_rad(_pose_out[0]) * _pose_side[actor]
		for c in POSE_CHANNELS:
			_pose_from[at + c] = _pose_out[c]
		_pose_from[at] = rad_to_deg(angle_difference(dir.angle(), heading)) * side
	_pose_out_actor = -1
	if spell.staff_pose.is_empty():
		_pose_start[actor] = INF
		return
	_pose_start[actor] = _clock
	_pose_wind[actor] = wind
	_pose_strike[actor] = strike
	_pose_tag[actor] = tag
	_pose_dir[actor] = dir
	_pose_lock[actor] = 1 if lock else 0
	_pose_side[actor] = side
	_pose_keys[actor] = spell.staff_pose
	_pose_tint[actor] = spell.tint


## The carrier with `tag` has no shot left: the strike of the animation it plays ends now.
func _end_pose_strike(tag: int) -> void:
	var actor: int = SpellTag.caster_of(tag)
	if actor < 0 or actor >= ACTORS or not is_finite(_pose_start[actor]) or _pose_tag[actor] != tag:
		return
	var into: float = maxf(_clock - _pose_start[actor] - _pose_wind[actor], 0.0)
	if into < _pose_strike[actor]:
		_pose_strike[actor] = into
		_pose_out_actor = -1


## Where `actor`'s staff is in its animation now (its carrier's `staff_pose`), for its look: x the
## turn off the aim locked at the cast (radians, a backhand's the other way), y the lift and z the
## push along that aim (pixels). Zero when it plays none: then `staff_pose_dir` is zero too and the
## look follows the aim. A new animation starts from where the last one had the staff.
func staff_pose(actor: int) -> Vector3:
	if not _pose_now(actor):
		return Vector3.ZERO
	return Vector3(deg_to_rad(_pose_out[0]) * _pose_side[actor], _pose_out[1], _pose_out[2])


## How strongly `actor`'s staff glows now (0 to 1), and in what colour: its carrier's infusion's,
## or white for a plain one (the look takes the player's colour then).
func staff_glow(actor: int) -> float:
	return _pose_out[3] if _pose_now(actor) else 0.0


func staff_glow_tint(actor: int) -> Color:
	return _pose_tint[actor] if actor >= 0 and actor < ACTORS else Color.WHITE


## How much `actor`'s staff is stretched along its aim now (0 none, negative squashed), and the
## pixels it shakes by.
func staff_stretch(actor: int) -> float:
	return _pose_out[4] if _pose_now(actor) else 0.0


func staff_shake(actor: int) -> float:
	return _pose_out[5] if _pose_now(actor) else 0.0


## The mood `actor`'s staff animation shows on its face now (`FormBase.POSE_MOODS`), or empty.
func staff_mood(actor: int) -> StringName:
	if not _pose_now(actor) or _pose_out_mood <= 0:
		return &""
	return FormBase.POSE_MOODS[_pose_out_mood - 1]


## The aim `actor`'s staff animation turns from, or zero when it plays none: the aim of the cast
## for a carrier that locks it (a swing, a slam), else the live aim (a held beam turns with it).
func staff_pose_dir(actor: int) -> Vector2:
	if not _pose_now(actor):
		return Vector2.ZERO
	if _pose_lock[actor] == 0 and _aim_dir[actor].is_finite() and not _aim_dir[actor].is_zero_approx():
		return _aim_dir[actor]
	return _pose_dir[actor]


## Works out `actor`'s animation now into `_pose_out` and `_pose_out_mood` (once per actor and
## clock); false when it plays none (none started, or past its last key). The keys run from where
## the staff was at the cast; "hold" keys repeat, each round from the last of them, while the
## strike lasts. Allocation-free.
func _pose_now(actor: int) -> bool:
	if actor < 0 or actor >= ACTORS or not is_finite(_pose_start[actor]):
		return false
	if _pose_out_actor == actor and _pose_out_clock == _clock:
		return _pose_out_mood >= 0
	_pose_out_actor = actor
	_pose_out_clock = _clock
	var keys: PackedFloat32Array = _pose_keys[actor]
	var s: float = _clock - _pose_start[actor]
	var wind: float = _pose_wind[actor]
	var strike: float = _pose_strike[actor]
	var stride: int = FormBase.POSE_STRIDE
	var count: int = keys.size() / stride
	# Where the last key passed left the staff (the start: where it was at the cast), and when.
	var base: int = actor * POSE_CHANNELS
	var from_key: int = -1
	var from_t: float = 0.0
	var mood: int = 0
	var k: int = 0
	while k < count:
		var phase: int = roundi(keys[k * stride + FormBase.PK_PHASE])
		if phase == FormBase.POSE_PHASES["hold"]:
			# The run of hold keys, played round and round through the strike.
			var first: int = k
			while k < count and roundi(keys[k * stride + FormBase.PK_PHASE]) == phase:
				k += 1
			var last: int = k - 1
			var period: float = keys[last * stride + FormBase.PK_AT]
			if s < wind and strike > 0.0:
				# Still winding up past its last wind key: it stays there until the strike.
				return _pose_between(keys, actor, from_key, first, 0.0, mood)
			if s >= wind and s < wind + strike and period > 0.0:
				var into: float = s - wind
				var round_n: int = floori(into / period)
				var u: float = into - round_n * period
				var h_from: int = from_key if round_n == 0 else last
				var h_t: float = 0.0
				for h in range(first, last + 1):
					var t: float = keys[h * stride + FormBase.PK_AT]
					if u < t:
						return _pose_between(keys, actor, h_from, h, clampf((u - h_t) / (t - h_t), 0.0, 1.0) if t > h_t else 1.0, mood)
					h_from = h
					h_t = t
					mood = _mood_of(keys, h, mood)
				return _pose_between(keys, actor, h_from, h_from, 1.0, mood)
			if s >= wind + strike or strike <= 0.0:
				from_key = last if strike > 0.0 else from_key
				from_t = wind + strike
			continue
		var at: float = keys[k * stride + FormBase.PK_AT]
		var t: float = at * wind if phase == 0 else (wind + at * strike if phase == 1 else wind + strike + at)
		if s < t:
			return _pose_between(keys, actor, from_key, k, clampf((s - from_t) / (t - from_t), 0.0, 1.0) if t > from_t else 1.0, mood)
		from_key = k
		from_t = t
		mood = _mood_of(keys, k, mood)
		k += 1
	_pose_out_mood = -1
	return false


## The mood shown once key `k` is passed: its own, else the one before.
static func _mood_of(keys: PackedFloat32Array, k: int, mood: int) -> int:
	var own: int = roundi(keys[k * FormBase.POSE_STRIDE + FormBase.PK_MOOD])
	return own if own > 0 else mood


## Puts into `_pose_out` the pose `x` of the way from key `from` (-1: where the staff was at the
## cast) to key `to`, eased by `to`'s ease, with `mood`; true.
func _pose_between(keys: PackedFloat32Array, actor: int, from: int, to: int, x: float, mood: int) -> bool:
	var stride: int = FormBase.POSE_STRIDE
	var eased: float = pose_ease(x, roundi(keys[to * stride + FormBase.PK_EASE]))
	for c in POSE_CHANNELS:
		var a: float = _pose_from[actor * POSE_CHANNELS + c] if from < 0 else keys[from * stride + FormBase.PK_CHANNELS + c]
		_pose_out[c] = lerpf(a, keys[to * stride + FormBase.PK_CHANNELS + c], eased)
	_pose_out_mood = mood
	return true


## The side a staff animation turns for a carrier that is no swing: the one where a negative turn
## lifts the head (toward the top of the screen) whichever way it faces.
static func up_side(aim: Vector2) -> int:
	return 1 if aim.x >= 0.0 else -1


## `x` (0 to 1) of the way into a key, eased by `ease` (`FormBase.POSE_EASES`: 0 slow, fast, slow;
## 1 slowing into the key; 2 speeding up into it).
static func pose_ease(x: float, ease: int) -> float:
	match ease:
		1:
			return 1.0 - (1.0 - x) * (1.0 - x)
		2:
			return x * x
	return swing_ease(x)


## The live swings, for their look (`gameplay/feel`): `swing_slots()` rows, each on or off. A
## swing on turns round `swing_origin` from `swing_dir` (the aim locked at the cast), `swing_side`
## 1 clockwise on screen or -1 back; `swing_turned` is how far it has turned (radians, from minus
## to plus half its `swing_arc` and SWING_LEAN past; it waits at the start through its wind-up),
## out to `swing_reach`.
func swing_slots() -> int:
	return _sw_on.size()


func swing_on(at: int) -> bool:
	return at >= 0 and at < _sw_on.size() and _sw_on[at] != 0


func swing_actor(at: int) -> int:
	return _sw_actor[at]


func swing_tag(at: int) -> int:
	return _sw_tag[at]


func swing_origin(at: int) -> Vector2:
	return _sw_origin[at]


func swing_dir(at: int) -> Vector2:
	return _sw_dir[at]


func swing_side(at: int) -> int:
	return _sw_side[at]


func swing_turned(at: int) -> float:
	return _sw_turned[at]


func swing_arc(at: int) -> float:
	return _sw_spell[at].arc if _sw_spell[at] != null else 0.0


func swing_reach(at: int) -> float:
	return _sw_spell[at].ray_length if _sw_spell[at] != null else 0.0


## Which swing row `at` holds: a number no other swing had, so its look knows a new swing in a
## row used again.
func swing_born(at: int) -> int:
	return _sw_born[at]


## Seconds swing `at` has run (its wind-up first), its wind-up and its sweep.
func swing_age(at: int) -> float:
	return _sw_age[at]


func swing_wind(at: int) -> float:
	return _sw_wind[at]


func swing_sweep(at: int) -> float:
	return maxf(_sw_spell[at].lifetime, 0.001) if _sw_spell[at] != null else 0.001


## The tint and packed look kinds of swing `at` (`CompiledSpell.tint`, `look`), so it shows its cards.
func swing_tint(at: int) -> Color:
	return _sw_spell[at].tint if _sw_spell[at] != null else Color.WHITE


func swing_look(at: int) -> int:
	return _sw_spell[at].look if _sw_spell[at] != null else 0


## Live swings over every caster.
func swing_count() -> int:
	return _sw_on.count(1)


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


## The live beams, for their look (`gameplay/feel` draws them every frame): `beam_slots()` rows,
## each on or off. A beam on runs along its path (`beam_point_count`, `beam_point`; a homing one
## bends onto a target, `beam_end`, through `beam_bend`, and with pierce on to more), cut to its
## first `beam_reach` pixels (its length, a wall, or the target that spends it).
## `beam_since_hit` is seconds since its last hit; `beam_left` is its life left, 0 to 1.
func beam_slots() -> int:
	return _bm_on.size()


func beam_on(at: int) -> bool:
	return at >= 0 and at < _bm_on.size() and _bm_on[at] != 0


## The caster (actor id) of live beam `at`; its look is drawn in that actor's ramp.
func beam_caster(at: int) -> int:
	return _bm_actor[at]


func beam_origin(at: int) -> Vector2:
	return _bm_origin[at]


## The points of live beam `at`'s path, from its start; it is drawn along them for its first
## `beam_reach` pixels.
func beam_point_count(at: int) -> int:
	return _bm_count[at]


func beam_point(at: int, n: int) -> Vector2:
	return _bm_points[at * _bm_stride + n]


func beam_bend(at: int) -> Vector2:
	return _bm_bend[at]


func beam_end(at: int) -> Vector2:
	return _bm_end[at]


func beam_reach(at: int) -> float:
	return _bm_reach[at]


## How many times wider than its carrier live beam `at` is now (growth; 1.0 for a plain beam).
func beam_growth(at: int) -> float:
	var spell: CompiledSpell = _bm_spell[at]
	if spell == null or spell.radius <= 0.0:
		return 1.0
	return _beam_width(at) / (spell.radius * 0.5)


func beam_tint(at: int) -> Color:
	return _bm_spell[at].tint if _bm_spell[at] != null else Color.WHITE


## The packed look kinds of live beam `at` (`CompiledSpell.look`), so it shows its cards.
func beam_look(at: int) -> int:
	return _bm_spell[at].look if _bm_spell[at] != null else 0


func beam_since_hit(at: int) -> float:
	return _clock - _bm_hit_at[at]


func beam_left(at: int) -> float:
	return clampf(_bm_life[at] / _bm_span[at], 0.0, 1.0) if _bm_span[at] > 0.0 and _bm_span[at] < SpellLimits.HOLD_LIFETIME else 1.0


## Live beams on now (tests).
func beam_count() -> int:
	return _bm_on.count(1)


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
	if spell.motion == FormBase.Motion.ORBIT or spell.motion == FormBase.Motion.STILL or velocity.is_zero_approx():
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
		LC_BEAM:
			return _bm_tip[ref] if _bm_on[ref] != 0 and _bm_born[ref] == _lc_seq[i] else Vector2.INF
		LC_SWING:
			return swing_tip(ref) if _sw_on[ref] != 0 and _sw_born[ref] == _lc_seq[i] else Vector2.INF
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


## Runs the `arc` shots on by `delta`: each whose clock runs out zaps (`_zap`), at most
## `SpellLimits.MAX_ARCS_PER_STEP` in all; one over the cap zaps in a later step.
func _step_arcs(delta: float) -> void:
	_arcs_used = 0
	var i: int = 0
	while i < _arc_count:
		var slot: int = _arcs[i]
		if not _knows(slot):
			_rec_arc[slot] = 0
			_arc_count -= 1
			_arcs[i] = _arcs[_arc_count]
			continue
		_rec_arc_clock[slot] -= delta
		if _rec_arc_clock[slot] <= 0.0 and _arcs_used < SpellLimits.MAX_ARCS_PER_STEP:
			_zap(slot)
		i += 1


## Every `magnet` shot pulls the enemies within its card's reach toward where it is, each step
## (`pull_requested`; combat keeps the pull as a push that the next pull replaces), and every
## live `magnet` beam toward its line (`_beam_pull`). At most `SpellLimits.MAX_PULLS_PER_STEP`
## shots pull in a step; which ones rotates, so none starves.
func _step_magnets() -> void:
	# A live beam with magnet pulls toward its line every step it is on (rules R4f).
	for at in _bm_on.size():
		if _bm_on[at] != 0 and _bm_spell[at].behaviour(ModifierBase.Behaviour.MAGNET) > 0.0:
			_beam_pull(at)
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


## Shot `slot`'s zap: a short ray to the nearest body of another team within its `arc_reach`, hitting with its
## `arc_hit` (`hit_profile`). It is a hit of the shot like any other: it uses the shot's trigger
## fires and chain jumps, so `on hit` payloads and chains go off from the zapped body. With no
## body in reach the shot tries again next step.
func _zap(slot: int) -> void:
	var tag: int = projectiles.get_tag_of(slot)
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null or spell.arc_interval <= 0.0:
		_rec_arc_clock[slot] = INF
		return
	var at: Vector2 = projectiles.get_position_of(slot)
	var actor: int = SpellTag.caster_of(tag)
	var target: Node2D = projectiles.nearest_target(at, spell.arc_reach, HITS, null, null, _team(actor))
	var aim: Vector2 = projectiles.nearest_point
	if target == null or not aim.is_finite():
		return
	_rec_arc_clock[slot] += spell.arc_interval
	if _rec_arc_clock[slot] <= 0.0:
		_rec_arc_clock[slot] = spell.arc_interval
	_arcs_used += 1
	var way: Vector2 = at.direction_to(aim) if not at.is_equal_approx(aim) else Vector2.RIGHT
	var saved_tag: int = _ray_tag
	var saved_dir: Vector2 = _ray_dir
	var saved_chain: int = _ray_chain
	var saved_prev: int = _ray_prev
	var saved_hit: HitProfile = _ray_hit
	var saved_arc: int = _arc_slot
	_ray_tag = tag
	_ray_dir = way
	_ray_chain = _rec_chain[slot]
	_ray_prev = _rec_prev[slot]
	_ray_hit = _rec_zap[slot] if _rec_zap[slot] != null else spell.arc_hit
	_arc_slot = slot
	var got: float = projectiles.ray(actor, at, way, at.distance_to(aim) + 2.0, 0, HITS, tag, 0.0, null)
	_ray_tag = saved_tag
	_ray_dir = saved_dir
	_ray_chain = saved_chain
	_ray_prev = saved_prev
	_ray_hit = saved_hit
	_arc_slot = saved_arc
	if got > 0.0 and events != null:
		events.form_shown.emit(actor, &"beam", at, way, got, spell.tint, spell.look)
	_cast_jumps()


func _on_hit(actor: int, target: Node, position: Vector2, tag: int) -> void:
	if not SpellTag.is_spell_tag(tag):
		return
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null:
		return
	# `relay` takes on what the actor hit last cast, before Combat reads this hit's profile (Spells
	# hears `projectile_hit` first: its autoload comes before Combat's).
	_relay(target, tag)
	var slot: int = projectiles.event_slot
	var chain: int = spell.chain_jumps
	var prev: int = 0
	var heading: Vector2 = Vector2.RIGHT
	var by_ray: bool = slot < 0
	if by_ray:
		if tag != _ray_tag:
			return
		chain = _ray_chain
		prev = _ray_prev
		heading = _ray_dir
	else:
		if _same(slot):
			chain = _rec_chain[slot]
			prev = _rec_prev[slot]
		heading = _heading(spell, slot, position, actor)
	# A chain goes on hitting as the hit it jumps from did (an echo's half, a relay's merge); a
	# zap's jumps as its shot does.
	var carried: HitProfile = null
	var carried_zap: HitProfile = null
	var from: int = _arc_slot if by_ray else slot
	if from >= 0 and _same(from):
		carried = _rec_relay[from]
		carried_zap = _rec_zap[from]
	elif by_ray:
		carried = _ray_hit
	var held: bool = spell.payload != null and spell.trigger_event == TriggerBase.Event.HIT
	var struck: int = target.get_instance_id()
	_on_hit_effects(spell, tag, actor, target, position, slot)
	if held:
		_fire_payload(spell, tag, actor, position, heading, target, slot)
	if chain > 0:
		_jump(spell, tag, actor, position, target as Node2D, struck, prev, chain - 1, by_ray, carried, carried_zap)


## What a hit of a carrier does besides its payload and chain: siphon refunds mana; pull pulls
## the caster to the hit; a swap trades places with the target; a spent shot's `blast` goes off
## (a beam's waits for its end, a pulling shot's for the arrival).
func _on_hit_effects(spell: CompiledSpell, tag: int, actor: int, target: Node, position: Vector2, slot: int) -> void:
	var refund: float = spell.behaviour(ModifierBase.Behaviour.SIPHON)
	if refund > 0.0:
		_refund(actor, refund)
	var possess: float = spell.behaviour(ModifierBase.Behaviour.POSSESS)
	if possess > 0.0:
		_possess(actor, target, possess, tag)
	# Pull pulls its caster to the hit and a swap trades places with it: the body (through its
	# owner), or the shot that cast this one. A point cannot move, so one cast from a point moves
	# the wizard (rules R4c). Either is guarded by the card's shield for the move (`_shield_move`).
	var caster: int = projectiles.caster_shot_of(slot) if slot >= 0 and not projectiles.is_cast_by_wizard(slot) else -1
	# A shot this hit spent ends where what it pulls arrives (rules R4a); one with pierce left
	# flies on and ends by itself (`_on_expired`), and a line or a strike ends as it does.
	var spent: bool = slot >= 0 and not projectiles.is_alive(slot)
	var pulled: bool = false
	if spell.behaviour(ModifierBase.Behaviour.PULL) > 0.0:
		if caster < 0 and events != null:
			var anchor: Vector2 = projectiles.get_anchor(actor)
			if anchor.is_finite():
				_move_heading[actor] = anchor.direction_to(position) if not anchor.is_equal_approx(position) else Vector2.RIGHT
				events.caster_move_requested.emit(actor, &"pull", position - anchor, SpellLimits.PULL_SECONDS, tag)
				if spent:
					_pull_ends[tag] = _pull_ends.get(tag, 0) + 1
				_shield_move(spell, tag, actor, -1, SpellLimits.PULL_SECONDS)
				pulled = true
		elif caster >= 0:
			var from: Vector2 = projectiles.get_position_of(caster)
			if projectiles.move_shot(caster, position - from, SpellLimits.PULL_SECONDS):
				_shield_move(spell, tag, actor, caster, SpellLimits.PULL_SECONDS)
				if spent:
					_track_move(caster, tag, SpellLimits.PULL_SECONDS, from.direction_to(position))
				pulled = true
	if spell.motion == FormBase.Motion.SWAP and events != null:
		var node := target as Node2D
		if caster < 0:
			var anchor: Vector2 = projectiles.get_anchor(actor)
			if node != null and anchor.is_finite():
				events.target_move_requested.emit(actor, target, anchor)
				events.caster_move_requested.emit(actor, &"swap", node.global_position - anchor, SpellLimits.SWAP_SECONDS, tag)
				_shield_move(spell, tag, actor, -1, SpellLimits.SWAP_SECONDS)
		elif node != null:
			var from: Vector2 = projectiles.get_position_of(caster)
			events.target_move_requested.emit(actor, target, from)
			projectiles.move_shot(caster, node.global_position - from, 0.0)
			_shield_move(spell, tag, actor, caster, 0.0)
	# A spent shot's blast goes off where it hit; a pulling one's waits for the arrival.
	if spent and not pulled:
		_blast(spell, tag, actor, position)


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


func _on_expired(actor: int, position: Vector2, tag: int) -> void:
	var event: int = TriggerBase.Event.EXPIRE
	var spell: CompiledSpell = _profiles.get(tag)
	if spell != null and spell.trigger_event == TriggerBase.Event.WALL and projectiles.expired_on_wall:
		event = TriggerBase.Event.WALL
	# Every carrier blasts at its end point (rules R1d): a pulling shot that missed, where it ended.
	if spell != null:
		_blast(spell, tag, actor, position)
	_fire_event(event, actor, position, tag, null, true)


## `on wall` at every wall that does not end the shot (a bounce) and at every wall a beam or
## fissure turns at or ends on (owner, 2026-10-29); a shot's last wall is `_on_expired`'s. The
## payload goes the way the shot or beam goes on. A zap (`_zap`, its shot's tag) that ends on a
## wall is not its shot meeting one: it sets off nothing (rules R4a).
func _on_wall_met(actor: int, position: Vector2, heading: Vector2, tag: int) -> void:
	if _arc_slot >= 0:
		return
	_fire_event(TriggerBase.Event.WALL, actor, position, tag, null, false, heading)


func _on_shot_blocked(actor: int, position: Vector2, tag: int) -> void:
	_fire_event(TriggerBase.Event.BLOCK, actor, position, tag, null)


func _on_shield_blocked(actor: int, position: Vector2, tag: int) -> void:
	_fire_event(TriggerBase.Event.BLOCK, actor, position, tag, null)


## A deflect is a block (owner, 2026-10-29): it sets off `on block` too.
func _on_shot_deflected(actor: int, position: Vector2, tag: int) -> void:
	_fire_event(TriggerBase.Event.BLOCK, actor, position, tag, null)


func _on_kill(actor: int, target: Node, position: Vector2, tag: int) -> void:
	_fire_event(TriggerBase.Event.KILL, actor, position, tag, target if is_instance_valid(target) else null)


func _on_reaction(actor: int, _reaction_id: StringName, target: Node, position: Vector2, tag: int) -> void:
	_fire_event(TriggerBase.Event.REACTION, actor, position, tag, target if is_instance_valid(target) else null)


## Fires the payload of the shot with `tag` from `at`, when that shot's trigger is `event` (the
## shared way of the events that name a shot's tag). When the event is being sent for that
## very shot, its record limits how often it fires. `back_off` pulls the point out of a wall;
## `way`, when given, is the way the payload goes.
func _fire_event(event: int, actor: int, at: Vector2, tag: int, source: Node, back_off: bool = false, way: Vector2 = Vector2.ZERO) -> void:
	if not SpellTag.is_spell_tag(tag):
		return
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null or spell.payload == null or spell.trigger_event != event:
		return
	var slot: int = projectiles.event_slot
	if slot >= 0 and (not _same(slot) or projectiles.get_tag_of(slot) != tag):
		slot = -1
	# A beam has no slot: while its `ray()` runs, its payload goes along the beam.
	var by_ray: bool = slot < 0 and tag == _ray_tag
	var heading: Vector2 = way if not way.is_zero_approx() else (_ray_dir if by_ray else _heading(spell, slot, at, actor))
	if back_off:
		at -= heading * SpellLimits.EXPIRE_BACKOFF
	_fire_payload(spell, tag, actor, at, heading, source, slot)


## `on hurt`: every live carrier of the hurt actor with that trigger fires its payload from where
## the actor was hurt (a wizard or an enemy alike, actors G3b), whatever the carrier is (a shot, a
## beam, a dash, an entity...; `_lc_tag`).
func _on_hurt(actor: int, _amount: int, position: Vector2, _tag: int, _kind: StringName) -> void:
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
## An actor that never cast an infused carrier gives nothing. A ray with it (a beam, a fissure, a
## jump of either; rules R4f) keeps what it took on in `_ray_hit` for its later hits, a live beam
## for as long as it is on (`_bm_hit`). Allocates two profiles per such hit, never per frame.
func _relay(target: Node, tag: int) -> void:
	var spell: CompiledSpell = _profiles.get(tag)
	if spell == null or spell.behaviour(ModifierBase.Behaviour.RELAY) <= 0.0 or not is_instance_valid(target):
		return
	var donor_actor: int = projectiles.target_owner_of(target)
	if donor_actor < 0 or donor_actor >= ACTORS:
		return
	var slot: int = projectiles.event_slot
	if slot < 0 and tag == _ray_tag:
		slot = _arc_slot
	var by_ray: bool = slot < 0 and tag == _ray_tag
	var donor: CompiledSpell = _last_infused[donor_actor]
	if donor == null or (not by_ray and (slot < 0 or not _same(slot) or projectiles.get_tag_of(slot) != tag)):
		return
	var base: HitProfile = _ray_hit if by_ray else _rec_relay[slot]
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
		_ray_hit = merged
		return
	if base.element_id == &"":
		projectiles.set_core(slot, donor.tint)
	_rec_relay[slot] = merged
	_rec_zap[slot] = StaffCompiler.zap_hit(merged) if spell.arc_hit != null else null
	if slot == _arc_slot:
		_ray_hit = _rec_zap[slot]


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
	_mv_count = 0
	for dash in _passes:
		dash.spell = null
		dash.hit = null
		dash.struck.clear()
		_passes_free.append(dash)
	_passes.clear()
	_caster = CASTER_WIZARD
	_bm_on.fill(0)
	_bm_spell.fill(null)
	_bm_source.fill(null)
	_sw_on.fill(0)
	_sw_spell.fill(null)
	_sw_source.fill(null)
	for at in _sw_struck.size():
		_sw_struck[at].clear()
	_sw_last_side.fill(-1)
	_sw_last_end.fill(-INF)
	_sw_last_start.fill(-INF)
	_pose_start.fill(INF)
	_aim_pivot.fill(Vector2.INF)
	_aim_origin.fill(Vector2.INF)
	_aim_dir.fill(Vector2.INF)
	_aim_seen.fill(0)
	for launch in _pending:
		_release_launch(launch)
	_pending.clear()
	_ring.fill(-1)
	_landed_at.fill(0)
	_move_heading.fill(Vector2.RIGHT)
	_pull_ends.clear()
	_last_form.fill(&"")
	_cast_count.fill(0)
	_lc_count = 0
	_arc_count = 0
	_magnet_count = 0
	_magnet_from = 0
	_rec_magnet.fill(0)
	_rec_seq.fill(-1)
	_rec_arc.fill(0)
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
	_entities.clear()
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


## The caster `actor` is gone (its body left or died): its staffs are emptied, its waiting
## launches, holds and beams end. Its shots in the air fly on with their own numbers until they
## end. The body closes its actor id in the table itself.
func close_caster(actor: int) -> void:
	if actor < 0 or actor >= ACTORS:
		return
	_drop_pending(func(launch: PendingLaunch) -> bool: return launch.actor == actor)
	for staff in SpellLimits.STAFFS:
		var index: int = actor * SpellLimits.STAFFS + staff
		_release_hold(index)
		var old: int = _current[index]
		_installed[index] = null
		_current[index] = -1
		if old >= 0:
			_release_generation(actor, staff, old)
	for at in _bm_on.size():
		if _bm_on[at] != 0 and _bm_actor[at] == actor:
			_end_beam(at, false)
	for at in _sw_on.size():
		if _sw_on[at] != 0 and _sw_actor[at] == actor:
			_end_swing(at, false)
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
## its first carrier's flight (speed x life), a beam's, fissure's or swing's length, a rain's aim point;
## 0 for one that is not aimed (a nova's ring, an orbit, a still shot, a decoy...) or no build.
func next_cast_reach(actor: int, staff: int) -> float:
	var first: CompiledSpell = _next_carrier(actor, staff)
	if first == null:
		return 0.0
	match first.motion:
		FormBase.Motion.STRAIGHT:
			return first.speed * first.lifetime if first.spread < 360.0 else 0.0
		FormBase.Motion.RAY, FormBase.Motion.FISSURE, FormBase.Motion.SWING:
			return first.ray_length
		FormBase.Motion.SLAM:
			return first.ray_length + first.radius
		FormBase.Motion.RAIN:
			return first.ray_length if first.ray_length > 0.0 else SpellLimits.RAIN_REACH
	return 0.0


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
	_move_heading[caster] = Vector2.RIGHT
	for tag: int in _pull_ends.keys():
		if SpellTag.caster_of(tag) == caster:
			_pull_ends.erase(tag)
	_landed_at[caster] = 0
	_aim_origin[caster] = Vector2.INF
	_aim_dir[caster] = Vector2.INF
	_aim_seen[caster] = 0
	_aim_pivot[caster] = Vector2.INF
	_sw_last_side[caster] = -1
	_sw_last_end[caster] = -INF
	_sw_last_start[caster] = -INF
	_pose_start[caster] = INF
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
	return spell != null and (spell.motion == FormBase.Motion.RAIN or spell.motion == FormBase.Motion.SWING)


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
	if events != null:
		for tag in tags:
			if _entities.has(tag):
				events.entity_end_requested.emit(SpellTag.caster_of(tag), tag)
	for tag in tags:
		_end_beams_of(tag)
		_end_swings_of(tag)
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
