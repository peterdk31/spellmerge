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
## staff's cycle and returns the mana spent or `REFUSED`; the wait after it (its carriers'
## wind-down, and the staff's cooldown after the cycle's last cast; docs/milestones/
## cast-timing.md) is per actor and staff and ticks in
## `step` (physics). A cast is a group: its carriers leave along the aim; each carrier's shots are
## a fan (straight), a ring (orbit), still shots or rays; split multiplied them in the
## compiler, and a nova casts the carrier several ways (`_cast_nova`); homing is set on each shot. Every shot leaves up to its staff's `spread` degrees off
## its line, at random (`_staff_spread`). Cards that landed on the caster (or a payload's origin)
## strike everything there (`_strike_round`); a dash card asks the caster's body to move
## (`caster_move_requested`). A `hold` carrier lives until its staff is cast again or edited.
##
## Payloads: each trigger of a carrier has its own payload (a group; `CompiledSpell.triggers`),
## fired by its shot's `projectile_hit` (on hit), `projectile_expired` (on expire) or every
## tick of that timer (timer, `_step_live`; a tick is the payload's whole wind-up, docs/
## milestones/cast-timing.md T8, and the payload then leaves without waiting again; the first tick
## after that or half the carrier's life, whichever is shorter). It starts at
## the hit point (the shot's place at expiry, a little back from a wall; where the carrier is now
## for a timer: every carrier that lasts has one, `_lc_tag`), flies along the shot's velocity
## (outward from the caster through the shot for an orbit or still shot, along the beam for a
## ray) and cannot hit the target that fired it until it has been clear of it
## (`ProjectileManager.exclude`; owner, 2026-11-06; a beam, which never moves off it, never hits
## it), as long as it starts touching it (`_launch`; owner, 2026-11-05): one that starts outside it,
## a Penta copy on its ring, hits it as it hits anything. A rune is the exception: it arms
## (`SpellLimits.RUNE_ARM`) and then hits whatever is on it, its source too. A payload is cast by the
## shot that fired it while that shot flies, by the body that fired it (a decoy's, a dashing wizard's
## timer, `on hurt` or end, a barrier's block: `body_caster`; owner, 2026-11-06), else by the point
## (`_caster`): dash, teleport, pull, swap and recoil move that shot or body, orbit, familiar and
## return circle it, a beam, swing or slam is held by it. A payload's Pulse is round it too
## (docs/CARRIERS.md, "Pulse: a ring from the cast point"); its actor stays the wizard. A trigger fires every
## time its event happens, as long as its carrier lives (owner, 2026-10-29: no per-shot count).
## One budget's trigger fires make at most `fire_shots_per_step` shots per `step` (pacing, not a
## limit): a fire past it waits for the next step, oldest first, and none is dropped
## (`fires_waited` counts them). A beam fires an on-expire payload where it ends when its
## life is over, and a timer from its tip while it is on.
##
## Carriers (docs/CARRIERS.md): each carrier card names its `Carrier` (core/spells/carriers/) that this
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
## Entities and walls (B2c): `familiar` and `decoy` ask `ai` for an entity
## (`entity_spawn_requested`) a step ahead along the aim, as a rune is placed (`_placed_at`),
## count it as a live shot of their tag until `entity_ended`, give a decoy's body its shield as a
## barrier and turn the shots round it with its deflect as it appears (`CarrierDecoy`), and fire an
## entity's `on expire` payload and `blast` at its end point. A familiar casts only what its triggers give it (rules R4 F3), as any carrier that lasts; `hold` keeps an entity until its staff is cast again (`entity_end_requested`). `wall`
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
##   everything), its caster's own too (owner, 2026-11-06), sparing only the body it is cast from
##   until it has left it (`_launch`);
## - aim asks the **team** (`Actors.team_of`): a chain's jump and an arc's zap go to another
##   team's body (the manager's homing does the same);
## - the per-step fire pacing and the live beams ask the **budget** (`Actors.budget_of`): a
##   seat's actor has its seat's, every actor no seat drives shares one (`Actors.SHARED`), so a
##   crowd never takes a seat's step;
## - only the HUD's events ask the **seat**: `mana_reserved` goes to the seat that drives the
##   actor (an AI reads `reserved_mana`).
## A body that casts opens its caster with `open_caster(id)` and closes it with `close_caster`
## (its staffs, waiting launches, holds and beams end; its shots in the air fly on). Its siphon
## refunds come as `mana_refund_requested(caster, staff, amount)`, and `on hurt` fires on its
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
## Seconds past when a staff that poured is ready again (`_pour_until`) that a held cast of it still
## follows on and pours, skipping its staff's wind-up (a step or two of a held button).
const POUR_GRACE: float = 0.1
## What every spell hits: every actor's hurtbox (everything hurts everything, actors G3b).
const HITS: int = ProjectilesScript.ACTOR_LAYERS
## A wall's pierce (rules R4 F6): a pierce no hit spends, so it stands through every hit.
const PIERCE_ALL: int = 1 << 30
## How a ray this runtime sends itself looks and blocks (a chain jump, a zap: `carrier_shown`,
## `block_shot`): as a beam's line. A look, not a carrier: it runs no carrier.
const RAY_CARD: StringName = &"beam"
## The look of a zap and its sparks (Feel draws lightning for it).
const ZAP_CARD: StringName = &"zap"
## The look of a siphon's mana coming back (`carrier_shown` names the Siphon card, whose `cue`
## Feel plays): from the hit to the caster's staff tip.
const SIPHON_CARD: StringName = &"siphon"
## Bodies a zap shot remembers rolling for (`_rec_zapped`), and the won zaps it can keep waiting
## (`_rec_due_body`; past that it makes the zap at once).
const ZAP_MEMORY: int = 32
const ZAP_DUE: int = 8


## A launch that waits for its time: a group's later firing (burst) or one carrier's echo.
class PendingLaunch:
	extends RefCounted
	## State as who they point at: other bodies, never entered (core/sim/README.md).
	const REFS: Array[StringName] = [&"source"]
	var due: float = 0.0
	var actor: int = 0
	var staff: int = 0
	var generation: int = 0
	## The group to fire, or null for the single `spell` of an echo or a held carrier's repeat.
	var group: CompiledGroup = null
	var spell: CompiledSpell = null
	## For a single `spell`: `echoed` is an echo's copy (half damage), `again` a held carrier cast
	## again (`_repeats`).
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
	## A payload that waited out its wind-up (`_fire`): it fires now as `_fire` would, its wind-up
	## over.
	var wound: bool = false
	## Skyfall: a single `spell` that falls from its hole at `origin` onto this floor line (`Skyfall`);
	## INF for any other launch.
	var fall_floor: float = INF


## What `cast` returns when the spell did not fire (cooling down, too little mana, no spell).
const REFUSED: float = -1.0

## Not state: services, caches and scratch, set up again (core/sim/README.md).
const DERIVED: Array[StringName] = [&"projectiles", &"events", &"registry", &"actors", &"sim", &"_zap_near", &"_strike_bodies", &"_hurt_firing", &"_outer", &"_outer_count", &"_looks", &"_look_drawers", &"_launch_look", &"_skyfall", &"_orbit", &"_leaving", &"_job_views", &"_job_generations", &"_job_casts", &"_job_launches", &"_job_fires", &"_job_strikes", &"_job_lasting", &"_job_zaps", &"_job_hits"]
## State as who they point at: other bodies, never entered (core/sim/README.md).
const REFS: Array[StringName] = [&"_rec_due_body", &"_jq_target"]
## State as its size alone: the spare launch records, each set whole when `_delay` takes it
## (core/sim/README.md).
const SPARES: Array[StringName] = [&"_pending_free"]
## State kept by caster, hashed caster by caster (`actor_part`, "Spells 7" beside the body "actor 7")
## and not with the rest of Spells (props W3, core/sim/README.md, "The hash"): the tables that grow
## with the casters. A snapshot saves them whole.
const BY_ACTOR: Array[StringName] = [&"_installed", &"_profiles", &"_node_counts", &"_live", &"_generation_live", &"_last_infused"]
## The session's settings a new run keeps (`begin_run`): a benchmark's fire budget.
const RUN_KEEPS: Array[StringName] = [&"fire_shots_per_step"]

## The shots one budget's trigger fires may make in one step (`SpellLimits.FIRE_SHOTS_PER_STEP`
## unless a benchmark sets another); a fire past it waits for the next step. A run's comes from its
## rules (`take_rules`, online-ready N11).
var fire_shots_per_step: int = SpellLimits.FIRE_SHOTS_PER_STEP
## The cast `cast_left` is sent for, while it is sent (`leaving_cast`; scratch, DERIVED).
var _leaving: CompiledCast = null
## Payloads fired, and fires that had to wait for a later step, since the last `clear`.
var fires_made: int = 0
var fires_waited: int = 0

## The projectile manager and the event bus; `bind` sets them.
var projectiles: ProjectilesScript = null
var events: EventsScript = null
## The game's chance (core/sim/sim.gd): found at the first roll (`Sim.found`); a test may set its own.
var sim: Sim = null

## Tags whose shots the last `begin_generation` call revoked, because all 8 generations of
## the slot were in the air. Until the caller removes those shots from the projectile
## manager they carry a tag that now means the new spell, so read this right after
## `begin_generation`, remove them, and only then call `begin_generation` (which clears it)
## or `shot_ended` again for them. Part 6 does exactly that.
var revoked_tags: PackedInt64Array = PackedInt64Array()
## The tag of the spell whose `cue_shown` is being sent (a blast's), or whose `carrier_shown` or
## `carrier_ended` a carrier sends (`CarrierKit.set_cue_tag`: a dash's, a move's end), 0 outside
## them, so the cue's motes and marks can be its cards' (gameplay/feel; spell-spectacle-2.md, S2
## and S5). For looks only.
var cue_tag: int = 0

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
## actor * STAFFS + staff -> the carrier (carrier card id) of its last cast, for the cast's look
var _last_carrier_card: Array[StringName] = []
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
## actor -> its sum of `_generation_live`: 0 when nothing of its builds is alive (no shot, no
## launch that keeps a build), so its only generations are its staffs' current ones (an older one
## is freed with its last shot). Written with `_generation_live` only (`_add_live`, `_take_live`,
## `_drop_live`).
var _caster_live: PackedInt32Array = PackedInt32Array()
## Every actor id from this one on has nothing in the BY_ACTOR tables: one past the highest that ever
## had a build (`begin_generation`), so the parts are `actor_parts()` of them.
var _caster_rows: int = 0

## actor * STAFFS + staff -> seconds before that staff may cast again
var _cooldown: PackedFloat32Array = PackedFloat32Array()
## Every cooldown row from this one on is 0: `step` counts down only the rows below it, not all
## ACTORS x STAFFS of them (4,096 since 2026-10-30, about 0.3 ms a physics step in GDScript).
## Actor ids are handed out lowest first, so it stays near the highest id that ever cast.
var _cooldown_rows: int = 0
## actor * STAFFS + staff -> when its winding cast leaves (`_clock`; INF: none winds up), the
## walk turn, place and aim it was pressed with (the place and aim the cast leaves along when the
## caster's are not known then), and how many staffs wind up now (docs/milestones/cast-timing.md).
var _wind_due: PackedFloat64Array = PackedFloat64Array()
var _wind_walk: PackedFloat32Array = PackedFloat32Array()
var _wind_origin: PackedVector2Array = PackedVector2Array()
var _wind_dir: PackedVector2Array = PackedVector2Array()
var _winding: int = 0
## Payloads each actor has fired in this step.
var _fires_used: PackedInt32Array = PackedInt32Array()
## What each shot knows, by projectile slot; valid while `_rec_seq` matches the manager's.
## What passes over the floor touches it once every this many pixels of its way (the cover's cell,
## `CoverLayout.CELL`), at most PASS_MOST times a step (a blink's way is touched at its end).
const PASS_SPACING: float = 16.0
const PASS_MOST: int = 64
## What passed over the floor since the last send (`floor_passed`, the floor's first slice), sent at
## Spells' step's end and emptied: each entry's caster, its spell's tag, its element and where.
## State, not scratch: a beam or a swing launched after Spells' step (a body's press, a payload in
## Combat) touches as it starts, and that entry waits for the next tick's send, through a snapshot.
var _pass_casters: PackedInt32Array = PackedInt32Array()
var _pass_tags: PackedInt64Array = PackedInt64Array()
var _pass_elements: Array[StringName] = []
var _pass_at: PackedVector2Array = PackedVector2Array()
var _rec_seq: PackedInt64Array = PackedInt64Array()
var _rec_chain: PackedInt32Array = PackedInt32Array()
## The key (`ProjectileManager.key_of`, N5) of the target a chain came from, 0 for none.
var _rec_prev: PackedInt64Array = PackedInt64Array()
## The live carriers with a trigger of `TriggerBase.LIVE` (timer, on hurt, on recast, on near), `_lc_count` of them (rules R4d): every
## carrier that lasts joins as it starts (`_lc_join`), whatever it is, and `_lc_where` says where
## it is now: the shot in a slot (`LC_SLOT`; also the shot a dash moves), a row of its carrier
## (`LC_ROW`: a beam's or a swing's tip, `Carrier.tip_of`), an actor's body (a wizard's dash, a decoy) or a point (a familiar's orb,
## which Entities moves: `familiar_at`, keyed by `_lc_seq`). One `_lc_tied` to its row ends with
## it (a shot, a beam, a swing); the others
## live `_lc_left` seconds (a dash, an entity) or until they leave (`_lc_leave`: an
## entity that ended). `_lc_clock` is the seconds to the next tick (`on near`: to its next look),
## `_lc_at` where it was last, `_lc_way` its way where nothing else gives one, and `_lc_team` its
## caster's team when it joined (`on near`'s foes once that caster is gone).
const LC_SLOT: int = 0
const LC_ROW: int = 1
const LC_ACTOR: int = 2
const LC_POINT: int = 3
## Which of its carrier's `triggers` each entry fires (a carrier with two timers has two entries).
var _lc_trigger: PackedInt32Array = PackedInt32Array()
var _lc_tag: PackedInt64Array = PackedInt64Array()
var _lc_kind: PackedInt32Array = PackedInt32Array()
var _lc_ref: PackedInt32Array = PackedInt32Array()
var _lc_seq: PackedInt64Array = PackedInt64Array()
var _lc_tied: PackedByteArray = PackedByteArray()
var _lc_left: PackedFloat32Array = PackedFloat32Array()
var _lc_clock: PackedFloat32Array = PackedFloat32Array()
var _lc_at: PackedVector2Array = PackedVector2Array()
var _lc_way: PackedVector2Array = PackedVector2Array()
var _lc_team: PackedInt32Array = PackedInt32Array()
var _lc_count: int = 0
## Slots of live shots with `zap`, `_zapper_count` of them, flagged in `_rec_zapper`;
## `_rec_zap_rolls` is how many random numbers each has drawn (its rolls are a hash of its sequence
## number and that count: the same every run, `_zap_roll`), and `_rec_zapped` the keys of the bodies
## it has rolled for (`ProjectileManager.key_of`, N5), with `_rec_zapped_at` the moment each was zapped or lost its roll,
## ZAP_MEMORY a slot side by side, `_rec_zapped_count` of them (a body rolls again
## SpellLimits.ZAP_AGAIN after that moment; past ZAP_MEMORY the oldest is forgotten).
var _zappers: PackedInt32Array = PackedInt32Array()
var _zapper_count: int = 0
var _rec_zapper: PackedByteArray = PackedByteArray()
var _rec_zap_rolls: PackedInt32Array = PackedInt32Array()
var _rec_zapped: PackedInt64Array = PackedInt64Array()
var _rec_zapped_at: PackedFloat64Array = PackedFloat64Array()
var _rec_zapped_count: PackedInt32Array = PackedInt32Array()
## The zaps each shot has won but not made yet, ZAP_DUE a slot side by side, `_rec_due_count` of
## them: the body and the moment (`_clock`) it is zapped.
var _rec_due_body: Array[Node2D] = []
var _rec_due_at: PackedFloat64Array = PackedFloat64Array()
var _rec_due_count: PackedInt32Array = PackedInt32Array()
## Zaps made in this step (`SpellLimits.MAX_ZAPS_PER_STEP`), and the steps run (which half of the
## zap shots looks this step, SpellLimits.ZAP_EVERY).
var _zaps_used: int = 0
var _zap_steps: int = 0
## The bodies in a zap shot's reach, their centres and sizes (reused, `targets_near`).
var _zap_near: Array[Node2D] = []
var _zap_centres: PackedVector2Array = PackedVector2Array()
var _zap_radii: PackedFloat32Array = PackedFloat32Array()
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
## actor * STAFFS + staff -> casts made, which names the next cast's scatter and staff spread.
var _cast_count: PackedInt32Array = PackedInt32Array()
## actor * STAFFS + staff -> until when (`_clock`) its last cast pours on: set as a cast of a carrier
## that pours on when held (`Carrier.pours_held`: a spray) leaves, to when the staff is ready again
## and `POUR_GRACE` more; -1 for none, and after a new press. A cast of such a carrier that is not a
## press (`cast_staff`) by then skips its staff's wind-up: only a cast that follows on is poured.
var _pour_until: PackedFloat64Array = PackedFloat64Array()
## actor * STAFFS + staff -> how far the novas of its latest cast stand turned off their aim, as a
## share of the gap between two ways (`_nova_share`): SpellLimits.RING_STEP more each cast.
var _cast_turn: PackedFloat32Array = PackedFloat32Array()
## The scatter and spread rolls of the cast or later firing being launched: its key (the cast's
## actor, staff and count; a later firing's from it) and the rolls made by it so far (`_scatter_roll`).
var _scatter_key: int = 0
var _scatter_rolls: int = 0
## The carrier whose echo is being launched: its shots hit at the echo's half damage.
var _echo_spell: CompiledSpell = null
## One slot, for the one-shot carrier cards of `_land_shots`, `_travel_shots` and `_register_shots`.
var _one_slot: PackedInt32Array = PackedInt32Array([-1])

## Who casts the launch being fired, one value (`_caster`): the actor's own body for its own cast
## (CASTER_BODY, a staff's cast, by any actor: a player's wizard or an enemy); the body of an actor
## that fired a payload (`body_caster(id)`, CASTER_BODIES and below: a decoy's, or the wizard's for a
## dash's timer or end, a barrier's block; owner, 2026-11-06); the point it starts from
## (CASTER_POINT: a payload whose shot is gone, or one a beam or a familiar fired); or the
## slot of the shot that fired the payload, while it is the shot with `_caster_seq`. One rule for
## every card that names the caster: dash, teleport, pull, swap and recoil move it; orbit, familiar
## and a returning shot circle it or come back to it; a beam, swing or slam is held by it; the cards
## a payload leaves with no carrier land on it. The actor stays the cast's own: credit, budgets,
## colours and tag. A payload's caster keeps the payload's build, as a shot in the air does; only
## the actor's own cast (CASTER_BODY) goes with its staff's rebuild.
const CASTER_BODY: int = ProjectilesScript.CASTER_BODY
const CASTER_POINT: int = ProjectilesScript.CASTER_POINT
const CASTER_BODIES: int = -3
var _caster: int = CASTER_BODY
var _caster_seq: int = 0
## One-off homing picks made so far (`pick_target`), so each rolls afresh.
var _picks: int = 0
## The casters set aside while another casts (`_cast_as`, `_cast_done`): caster and seq side by
## side, `_outer_count` pairs deep. Empty between calls.
var _outer: PackedInt64Array = PackedInt64Array()
var _outer_count: int = 0
## The shots cast by another actor's body (`_follow_body`): slot, birth and that body, `_fl_count`.
var _fl_slot: PackedInt32Array = PackedInt32Array()
var _fl_seq: PackedInt64Array = PackedInt64Array()
var _fl_body: PackedInt32Array = PackedInt32Array()
var _fl_count: int = 0
## The tags of the `on hurt` carriers whose payload is being fired now (`_on_hurt`): a hurt that
## payload deals at once to the same body (its strike round a decoy) does not fire it again inside
## itself. Empty between calls.
var _hurt_firing: PackedInt64Array = PackedInt64Array()
## The turning ring the copy being cast now stands on (`_penta`): its centre, its radius (0 when
## the copy is on none) and the copy's angle on it now. A carrier whose copy stays on its point
## and aims from it (a beam) keeps it, to turn with the ring (`CarrierKit.ring_*`). Empty between
## launches.
var _ring_centre: Vector2 = Vector2.ZERO
var _ring_radius: float = 0.0
var _ring_angle: float = 0.0
## How fast and which way that ring turns, radians a second.
var _ring_turn: float = 0.0
## Each Penta card's last ring, by its tag (`_penta`): the angle it stood at, the clock then, and
## how fast and which way it turns (the next cast of that card turns the other way).
var _penta_rings: Dictionary = {}

## The ray being sent (`RayHit`): what a hit with no shot slot is (a beam's, a swing's, a slam's, a
## dash's, a zap, a jump). `_rays[0]` is the empty one (no ray out, tag 0); every
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
## `cast_staff`'s `walk`): a move it casts itself is turned by it.
var _walk_turn: PackedFloat32Array = PackedFloat32Array()
## While `entity_spawn_requested` is sent, the key of the entity it asks for (0 at other times):
## Entities keeps it and hands it back with `familiar_at`, and names it here again while it sends
## that entity's `entity_ended`, so the entity that ended leaves, not another of its tag.
## `_entity_keys` counts them out.
var entity_key: int = 0
## The actor id of the body Entities made for that request (a decoy is an actor), set by Entities
## while `entity_spawn_requested` is sent; -1 for none (a familiar is a point).
var entity_body: int = -1
var _entity_keys: int = 0
## Beam jumps waiting to be cast. A jump is made in a hit handler, i.e. inside the previous
## beam's `ray()`, so casting it there would nest one `ray()` deeper per jump (a long chain
## would recurse as deep as it jumps). The outermost beam casts them, first in first out, once
## its own `ray()` has returned. A ring of JUMP_QUEUE rows that doubles when it is full
## (`_grow_jumps`), so no jump is lost and a busy frame allocates only the first time. Each keeps
## who cast the hit it jumps from (`_jq_caster`, `_jq_caster_seq`), and is cast by it.
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
var _jq_caster: PackedInt32Array = PackedInt32Array()
var _jq_caster_seq: PackedInt64Array = PackedInt64Array()
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
## caster * STAFFS + staff -> where the ring stood when the caster now under that id opened
## (`open_caster`), and how many builds it has begun since (at most GENERATIONS; 0 once it closed):
## which generations are its own (`cast_by_open`), so a shot of an earlier caster with the same id
## is never taken for this one's (boss plan OB7: power is read from the caster's body).
var _open_ring: PackedInt32Array = PackedInt32Array()
var _open_builds: PackedInt32Array = PackedInt32Array()
## This runtime's carriers, by id (`Carriers.make_all`, bound to it through `_kit`).
var _carriers: Dictionary = {}
## The carrier that runs nothing (id &""), for a spell whose carrier id no carrier has.
var _no_carrier: Carrier = Carrier.new()
## The shot in `slot` hits with `profile` of its own (a relay's, an infusion's, a flying jump's): its
## hits are never merged with its spell's other shots' (`ProjectileManager.set_hits_alone`), whose
## profile is the tag's.
func _set_relay(slot: int, profile: HitProfile) -> void:
	_rec_relay[slot] = profile
	if profile != null and projectiles != null:
		projectiles.set_hits_alone(slot)


## What the carriers (and `_poses`, `_moves`) may ask of this runtime: all they use of it.
var _kit: CarrierKit = null
## Each actor's staff animation, for any carrier with a `staff_pose`.
var _poses: StaffPoses = null
## The moves carriers make of their caster or of the shot that cast them (dash, teleport, pull,
## swap, recoil): `CasterMoves`.
var _moves: CasterMoves = null
## What Plow carries (`core/spells/plow.gd`).
var _plow: Plow = null
## The Skyfall modifier, all of it (`core/spells/skyfall.gd`).
var _skyfall: Skyfall = null
## The circling modifier (core/spells/orbit.gd).
var _orbit: Orbit = null
## The runtime's code by job (core/README.md, "The spell runtime"): plain objects this runtime makes,
## links and frees; each works on this runtime's members, its arrays through aliases of its own
## (`_link_jobs`). Not state (DERIVED).
var _job_views: SpellViews = SpellViews.new()
var _job_generations: SpellGenerations = SpellGenerations.new()
var _job_casts: SpellCasts = SpellCasts.new()
var _job_launches: SpellLaunches = SpellLaunches.new()
var _job_fires: SpellFires = SpellFires.new()
var _job_strikes: SpellStrikes = SpellStrikes.new()
var _job_lasting: SpellLasting = SpellLasting.new()
var _job_zaps: SpellZaps = SpellZaps.new()
var _job_hits: SpellHits = SpellHits.new()


func _init() -> void:
	_link_jobs()
	_kit = CarrierKit.new(self)
	_poses = StaffPoses.new(_kit)
	_moves = CasterMoves.new(_kit)
	_plow = Plow.new(_kit)
	_skyfall = Skyfall.new(_kit)
	_orbit = Orbit.new(_kit)
	_carriers = Carriers.make_all()
	for carrier: Carrier in _carriers.values():
		carrier.bind(_kit, _poses)
	_current.resize(ACTORS * SpellLimits.STAFFS)
	_current.fill(-1)
	_installed.resize(ACTORS * SpellLimits.STAFFS)
	_cursor.resize(ACTORS * SpellLimits.STAFFS)
	_hold_mana.resize(ACTORS * SpellLimits.STAFFS)
	_cast_count.resize(ACTORS * SpellLimits.STAFFS)
	_pour_until.resize(ACTORS * SpellLimits.STAFFS)
	_pour_until.fill(-1.0)
	_cast_turn.resize(ACTORS * SpellLimits.STAFFS)
	for i in ACTORS * SpellLimits.STAFFS:
		_hold_tags.append(PackedInt64Array())
		_last_carrier_card.append(&"")
	for i in ACTORS:
		_last_infused.append(null)
	_aim_origin.resize(ACTORS)
	_aim_origin.fill(Vector2.INF)
	_walk_turn.resize(ACTORS)
	_caster_live.resize(ACTORS)
	_aim_dir.resize(ACTORS)
	_aim_dir.fill(Vector2.INF)
	_aim_seen.resize(ACTORS)
	_aim_pivot.resize(ACTORS)
	_aim_pivot.fill(Vector2.INF)
	_ring.resize(ACTORS * SpellLimits.STAFFS)
	_ring.fill(-1)
	_open_ring.resize(ACTORS * SpellLimits.STAFFS)
	_open_ring.fill(-1)
	_open_builds.resize(ACTORS * SpellLimits.STAFFS)
	_cooldown.resize(ACTORS * SpellLimits.STAFFS)
	_wind_due.resize(ACTORS * SpellLimits.STAFFS)
	_wind_due.fill(INF)
	_wind_walk.resize(ACTORS * SpellLimits.STAFFS)
	_wind_origin.resize(ACTORS * SpellLimits.STAFFS)
	_wind_dir.resize(ACTORS * SpellLimits.STAFFS)
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
	_jq_caster.resize(JUMP_QUEUE)
	_jq_caster_seq.resize(JUMP_QUEUE)
	_job_lasting._lc_grow(64)
	_zappers.resize(64)
	_magnets.resize(64)
	_ray_guard_points.resize(64)


func _ready() -> void:
	# The tick steps it (core/sim/tick.gd, core/sim/sim_area.gd).
	SimArea.join(self, &"Spells").steps(&"Spells", step).renewed_by(begin_run).takes_rules(take_rules)
	if projectiles == null:
		bind(get_node_or_null("/root/Projectiles") as ProjectilesScript, get_node_or_null("/root/Events") as EventsScript)
	register_bodies()


## Publishes the infusion table (every infusion's colour by its look layer, `InfusionTable`) for the
## shaders, reads every carrier card's look once (`_looks`, for `look_of` and `look_shaders`) and hands each
## shot carrier card's own shader (LOOK_SHOT, LOOK_STILL) to the projectile manager now
## (`register_body`, with the mesh its shots are written as; a still one's look shape and clock with
## it, `_shape_body`), so it has its batches and is warmed before the first room, not first drawn
## in the middle of one. A launch numbers and shapes any it did not know too (`_body_of`). The other areas warm the shaders they draw themselves (`look_shaders`).
func register_bodies() -> void:
	_job_views.register_bodies()


## Each carrier card's look by its id, read from the card once (at start, `register_bodies`, or the
## first time one is asked for): {id: CardLook}, and the area that draws its carrier ({id:
## Carrier.LOOK_*}). Caches (DERIVED).
var _looks: Dictionary = {}
var _look_drawers: Dictionary = {}


## The carrier card `carrier_card`'s look as the area `drawer` (Carrier.LOOK_*: Feel's beams or swing
## trails, Entities' orbs) draws it: its own shader and light (`CarrierCard.look_shader`,
## `look_light_intensity`, `look_light_reach`), or `CardLook.PLAIN` when its carrier is drawn by
## another area (a bolt's zap is a beam, but a bolt's shader draws heads) and for an id that is no
## carrier card (a chain's jump). So no area reads the card (docs/milestones/card-looks.md). Shared
## and read only; allocates nothing once the card was read.
func look_of(carrier_card: StringName, drawer: int) -> CardLook:
	return _job_views.look_of(carrier_card, drawer)


## Every carrier card's own shader the area `drawer` draws (Carrier.LOOK_*), so that area warms them
## before the first room (`ShaderWarmup.want`, as it draws them). A new array each call: once, at
## start.
func look_shaders(drawer: int) -> Array[Shader]:
	return _job_views.look_shaders(drawer)


## Every still carrier card whose shots give off motes while they stand (`CarrierCard.look_motes`,
## drawn by a shader of its own), by id, for Feel to give them off (`gameplay/feel/still_motes.gd`,
## which asks `look_of(carrier card, Carrier.LOOK_STILL)` for them). A new array each call: once, at start.
func still_mote_cards() -> Array[StringName]:
	return _job_views.still_mote_cards()


## What one launch's shots are drawn as (`_launch_look_of`), filled for each launch and reused: a
## launch allocates nothing (DERIVED scratch).
var _launch_look: LaunchLook = LaunchLook.new()


## `SpellViews._body_of` (_job_views), for the kit and the tests.
func _body_of(carrier_card: StringName, shader: Shader, mesh: int) -> int:
	return _job_views._body_of(carrier_card, shader, mesh)


## `_shot_mesh`'s answer for a carrier whose look is not the projectile manager's shots.
const NO_SHOT_MESH: int = 1


## Connect to a projectile manager and an event bus (either may be null, then casting is
## refused). Safe to call again: the old ones are disconnected.
func bind(manager: ProjectilesScript, bus: EventsScript) -> void:
	if projectiles != null and is_instance_valid(projectiles):
		projectiles.shot_ended.disconnect(shot_ended)
		projectiles.wall_met.disconnect(_job_hits._on_wall_met)
	if events != null and is_instance_valid(events):
		events.projectile_hit.disconnect(_job_hits._on_hit)
		events.projectile_expired.disconnect(_job_hits._on_expired)
		events.shot_blocked.disconnect(_job_hits._on_shot_blocked)
		events.shield_blocked.disconnect(_job_hits._on_shield_blocked)
		events.shot_deflected.disconnect(_job_hits._on_shot_deflected)
		events.kill_landed.disconnect(_job_hits._on_kill)
		events.actor_hurt.disconnect(_job_hits._on_hurt)
		events.reaction_landed.disconnect(_job_hits._on_reaction)
		events.entity_ended.disconnect(_job_hits._on_entity_ended)
		events.caster_move_finished.disconnect(_moves.finished)
		events.room_left.disconnect(_on_room_left)
		events.floor_strike_requested.disconnect(_job_hits._on_floor_strike)
		events.reaction_struck.disconnect(_job_hits._on_reaction_struck)
	projectiles = manager
	events = bus
	if projectiles != null:
		projectiles.shot_ended.connect(shot_ended)
		projectiles.wall_met.connect(_job_hits._on_wall_met)
	if events != null:
		events.floor_strike_requested.connect(_job_hits._on_floor_strike)
		events.reaction_struck.connect(_job_hits._on_reaction_struck)
		events.projectile_hit.connect(_job_hits._on_hit)
		events.projectile_expired.connect(_job_hits._on_expired)
		events.shot_blocked.connect(_job_hits._on_shot_blocked)
		events.shield_blocked.connect(_job_hits._on_shield_blocked)
		events.shot_deflected.connect(_job_hits._on_shot_deflected)
		events.kill_landed.connect(_job_hits._on_kill)
		events.actor_hurt.connect(_job_hits._on_hurt)
		events.reaction_landed.connect(_job_hits._on_reaction)
		events.entity_ended.connect(_job_hits._on_entity_ended)
		events.caster_move_finished.connect(_moves.finished)
		events.room_left.connect(_on_room_left)


## The party left room `room` (`room_left`; connected biomes CB3: a row run's each room, a biome's
## world as a whole, ALL_ROOMS): what was cast ends with it (`leave_room`).
func _on_room_left(_room: int) -> void:
	leave_room()


## True when the card `card_id` does something on the carrier `carrier` (`CarrierCard.carrier`) on its
## own: for the builder, a reward screen or a bot, before the card is placed
## (`StaffCompiler.card_works`). False for an unknown card.
func card_works(card_id: StringName, carrier: StringName) -> bool:
	return _job_views.card_works(card_id, carrier)


## Compiles a staff's cards (ids by slot, `&""` for an empty slot) into its cycle, the casts it
## makes until its cycle ends (staffs A4; the rules are docs/milestones/M2-staffs.md, "Reading a
## staff", and `StaffCompiler`). It never errors and refuses nothing: an unknown or useless
## card is listed in `wasted`. `spell_scale` is the casting body's (boss plan OB7, its `Stats`):
## × every spell's size (`Carrier.scale_size`), 1 as the cards say. `slots`: the slots it reads (-1:
## the staff's own; an elite's first staff has one more, connected biomes CB11).
func compile_staff(cards: Array[StringName], staff: StaffBase, spell_scale: float = 1.0, slots: int = -1) -> CompiledStaff:
	return _job_views.compile_staff(cards, staff, spell_scale, slots)


## What the builder shows of a staff, as plain values so that nothing outside `core/spells`
## reads a compiled staff: `empty`; `cards` (the card ids by slot, `&""` for an empty slot); `casts`, one Dictionary per cast of the cycle with `slots`
## (read order), `text`, `mana`, `wind_up` (the seconds it winds up before it leaves), `wind_down` (the seconds its staff is busy after it), `delay` (the wait in all: the wind-down, and the staff's cooldown when the cycle ends with it), `damage` (each carrier's hit times its shots and the group's repeats, payloads left out), `ends_cycle`, `wrapped`, `targets` (card slot -> the
## carrier's slot) and `wasted` (slot ->
## true), and `tree` (the cast as the builder's tree draws it, `cast_tree`); `wasted` for the
## staff (cards that did nothing in any cast that read them); `name`, the staff's name shown (`StaffBase.display_name`, "" for none; items I3: the builder names a staff in the bag by it); and `staff`, the StaffBase given, only to hand back to `staff_view` for a preview of other cards
## (the radial builder shows what a card would change before it is put in).
func staff_view(cards: Array[StringName], staff: StaffBase) -> Dictionary:
	return _job_views.staff_view(cards, staff)


## The rows of one cast as the builder's tree draws them (docs/milestones/M2-builder-tree.md,
## part T3), depth first: a row per carrier and one per trigger that fires. Each row is plain
## values: `depth` (0 for the cast's own carriers, one more per payload level), `trigger` (the
## trigger card's slot, -1 for a carrier row), `slots` (the cards the row shows: a group's
## multicasts on its first carrier's row, then that carrier's own cards, `CompiledSpell.card_slots`;
## a trigger row shows the first carrier its payload fires) and `name` (the carrier's or the
## trigger card's display name). The cast's first row also has its `mana` and `damage`. A
## payload's further carriers (a multicast in it) are rows of their own at the payload's depth,
## with no trigger. A wasted trigger has no row.
func cast_tree(cast: CompiledCast) -> Array[Dictionary]:
	return _job_views.cast_tree(cast)


## What the builder shows of the component `id`: its name (the id when it has none, "" for
## an unknown id), its 16x16 icon (null when unknown) and its kind (`&"carrier"`, `&"element"`,
## `&"modifier"` or `&"trigger"`, `&""` when unknown). Scripts outside `core/` and
## `content/spells/` learn these here and never read the component's fields.
func component_name(id: StringName) -> String:
	return _job_views.component_name(id)


func component_icon(id: StringName) -> Texture2D:
	return _job_views.component_icon(id)


## Card `id`'s 1x icon (`icon_small`, the HUD's small cells), null for none.
func component_icon_small(id: StringName) -> Texture2D:
	return _job_views.component_icon_small(id)


## Card `id`'s icon for a cell `side` layout pixels across: its 1x icon in a cell too small for its
## 2x one (`IconDetail.fitting`).
func component_icon_for(id: StringName, side: float) -> Texture2D:
	return _job_views.component_icon_for(id, side)


## The card's own numbers for the builder, as short lines of at most three (none for an unknown
## id): a carrier's damage (times its shots), mana and delay ("Dmg 3x8", "Mana 10", "Delay 1s");
## a modifier's changes ("Dmg x0.5", "Shots x3", "Homes in"); an element's status and how long it
## lasts ("Burn 3s"); when a trigger fires its payload ("On hit"); a multicast's draws.
func component_stats(id: StringName) -> PackedStringArray:
	return _job_views.component_stats(id)


## A number as the builder writes it: at most two decimals and no trailing zeros, keeping the
## leading zero (0.35 is "0.35": ".35" in the pixel font read as 35).
static func _short(value: float) -> String:
	var text: String = "%.2f" % value
	return text.rstrip("0").rstrip(".")


## The one-line description of the component `id` for the builder, from the card itself
## (`SpellComponent.description`). Empty for an unknown id or a card without one; the builder
## shows nothing for an empty one.
func component_description(id: StringName) -> String:
	return _job_views.component_description(id)


func component_kind(id: StringName) -> StringName:
	return _job_views.component_kind(id)


## The spell registered under `tag`, or null when its generation is gone.
func profile(tag: int) -> CompiledSpell:
	return _profiles.get(tag)


## The cards of the spell registered under `tag`, as plain ids: its carrier card, then its infusions and its
## modifiers in slot order, each once (empty when its generation is gone). For looks only:
## gameplay/feel's motes and marks by card (docs/milestones/spell-spectacle-2.md, S2).
func cards_of(tag: int) -> Array[StringName]:
	return _job_views.cards_of(tag)


## Registers every spell of `compiled` under a new generation of this actor's staff and
## returns the tag of its first spell, or 0 for an empty staff (the staff then has no build)
## or a bad actor or staff. The staff's generation advances; if its shots from 8 builds ago are
## still in the air the oldest generation is revoked (see `revoked_tags`).
func begin_generation(actor: int, staff: int, compiled: CompiledStaff) -> int:
	return _job_generations.begin_generation(actor, staff, compiled)


## The tag of the current build of this staff at `node`, or 0 when it has no build.
func current_tag(actor: int, slot: int, node: int = 0) -> int:
	if not _job_casts._in_range(actor, slot):
		return 0
	var generation: int = _current[actor * SpellLimits.STAFFS + slot]
	return 0 if generation < 0 else SpellTag.make(actor, slot, node, generation)


## A shot with `tag` was spawned. Ignored for a tag that has no spell.
func shot_started(tag: int) -> void:
	if _profiles.has(tag):
		_live[tag] = _live.get(tag, 0) + 1
		_job_generations._add_live(SpellTag.generation_key(tag))


## A shot with `tag` ended (hit, expired or was removed). The generation's spells (every
## node) are freed once its last shot of any node is gone and a newer build has replaced it. A
## sustained (`hold`) carrier whose last shot ends frees its mana reservation.
func shot_ended(tag: int) -> void:
	_job_generations.shot_ended(tag)


## Live shots counted for `tag`.
func live_shots(tag: int) -> int:
	return _live.get(tag, 0)


## Generations of this staff that still have spells registered (the current one and any
## older ones with shots in the air).
func generations_held(actor: int, slot: int) -> int:
	return _job_generations.generations_held(actor, slot)


## What one hit of a shot with `tag` does, or null when the tag is no spell's (a shot of no staff)
## or its generation is gone. `shot` is the shot that hit (the event's `shot`; -1 for a ray or a
## strike). Shared and read-only; allocates nothing.
func hit_profile(tag: int, shot: int = -1) -> HitProfile:
	return _job_generations.hit_profile(tag, shot)


## Makes `compiled` (from `compile_staff`) the build of this actor's staff (0-3), starting its
## cycle at the first cast, and removes the shots the new generation revoked. Editing a staff
## switches its sustained (`hold`) carriers off. Returns the tag of its first spell, or 0 for an
## empty staff (which leaves the staff with no build) or a bad actor or staff.
func install_staff(actor: int, staff: int, compiled: CompiledStaff) -> int:
	return _job_generations.install_staff(actor, staff, compiled)


## How far the carrier of `tag` reaches along its aim (its flight, a beam's or swing's length;
## 0 for one that is not aimed) and its hit radius: a telegraph lane's length
## and width (gameplay/feel/lanes.gd). 0 for a tag with no carrier.
func carrier_reach(tag: int) -> float:
	var spell: CompiledSpell = _profiles.get(tag) as CompiledSpell
	return _job_launches._carrier_of(spell).reach_of(spell) if spell != null else 0.0


func carrier_radius(tag: int) -> float:
	var spell: CompiledSpell = _profiles.get(tag) as CompiledSpell
	return spell.radius if spell != null else 0.0


## How wide the cast `tag` strikes either side of its aim at its far end (`Carrier.lane_radius`: a
## spray's cone is wider there than its hit radius); what a telegraph lane widens to.
func carrier_lane(tag: int) -> float:
	var spell: CompiledSpell = _profiles.get(tag) as CompiledSpell
	return _job_launches._carrier_of(spell).lane_radius(spell) if spell != null else 0.0


## How wide the cast `tag` of `actor`'s body strikes either side of its way when that is its body's
## width (`Carrier.pass_radius`: a dash's pass), all along it and as far past its end; 0 for a cast
## as wide as its spell. A telegraph lane is drawn that wide, along its way (`carrier_pass_length`)
## and that much longer.
func carrier_pass(tag: int, actor: int) -> float:
	var spell: CompiledSpell = _profiles.get(tag) as CompiledSpell
	if spell == null or actor < 0 or actor >= ACTORS:
		return 0.0
	return _job_launches._carrier_of(spell).pass_radius(spell, actor)


## How far the cast `tag` moves its caster along its way, when it strikes as wide as its body
## (`Carrier.pass_length`: a dash's distance); 0 for any other.
func carrier_pass_length(tag: int) -> float:
	var spell: CompiledSpell = _profiles.get(tag) as CompiledSpell
	return _job_launches._carrier_of(spell).pass_length(spell) if spell != null else 0.0


## Where `actor` holds its staff's tip and the way it aims (`set_aim`), INF while it has none: what a
## telegraph lane follows while the cast winds up.
func aim_origin_of(actor: int) -> Vector2:
	return _aim_origin[actor] if actor >= 0 and actor < ACTORS and _aim_seen[actor] != 0 else Vector2.INF


func aim_of(actor: int) -> Vector2:
	return _aim_dir[actor] if actor >= 0 and actor < ACTORS and _aim_seen[actor] != 0 else Vector2.INF


## True while this actor's staff winds up a cast (docs/milestones/cast-timing.md): pressed, not
## yet left. `cooldown_left` counts the wind-up down then.
func is_winding(actor: int, staff: int) -> bool:
	return _job_casts._in_range(actor, staff) and _wind_due[actor * SpellLimits.STAFFS + staff] != INF


## Seconds before this actor's staff may cast again.
func cooldown_left(actor: int, slot: int) -> float:
	return _cooldown[actor * SpellLimits.STAFFS + slot] if _job_casts._in_range(actor, slot) else 0.0


## This actor's staff `slot` may cast again in no less than `seconds` (items I7: a staff put on a
## hand is drawn, and waits its own cooldown, so moving staffs between hands skips no delay).
func hold_staff(actor: int, slot: int, seconds: float) -> void:
	_job_casts.hold_staff(actor, slot, seconds)


## This actor's staff `slot` may cast at once: no cooldown left (boss plan OB14: a boss's phase's
## staffs start ready). A cast it winds up is left to leave.
func ready_staff(actor: int, slot: int) -> void:
	_job_casts.ready_staff(actor, slot)


## Which cast of its cycle this actor's staff makes next (0 once its cycle ended).
func cast_index(actor: int, staff: int) -> int:
	return _cursor[actor * SpellLimits.STAFFS + staff] if _job_casts._in_range(actor, staff) else 0


## The staff (`StaffBase`) this actor holds in slot `staff` now, or null: for what is drawn of its
## own moments (Feel: a staff's `cast_cue`, `shown_cue` and `wall_cue`, boss plan OB15). Read only.
func staff_of(actor: int, staff: int) -> StaffBase:
	if not _job_casts._in_range(actor, staff):
		return null
	var compiled: CompiledStaff = _installed[actor * SpellLimits.STAFFS + staff]
	return compiled.staff if compiled != null else null


## The cast leaving now, while `cast_left` is sent for it (null at any other time): what Feel's
## cast sounds read of it (its carriers' cards and infusions, `gameplay/feel/cast_sounds.gd`). Read
## only.
func leaving_cast() -> CompiledCast:
	return _leaving


## The carrier card (its id) of the last cast this actor's staff made, `&""` before any. The
## wizard's player sends it with `spell_cast`.
func last_carrier_card(actor: int, staff: int) -> StringName:
	return _last_carrier_card[actor * SpellLimits.STAFFS + staff] if _job_casts._in_range(actor, staff) else &""


## True while this actor's staff has sustained (`hold`) carriers switched on.
func is_holding(actor: int, staff: int) -> bool:
	return _job_casts._in_range(actor, staff) and not _hold_tags[actor * SpellLimits.STAFFS + staff].is_empty()


## Fires the next cast of this actor's staff from `origin` along `direction`. `mana` is what
## the caster has. Returns the mana spent (0.0 or more) when it fired, or `REFUSED` when it did
## not (nothing built, still in its delay, no cast left its mana pays, no direction, or every shot
## starting inside a wall); the caller then takes that much mana and reads no field. A cast the
## mana does not pay is skipped (docs/milestones/cast-timing.md, T3): the press fires the first
## one after it that it pays, up to the cycle's end; with none, the cycle ends (its cooldown runs,
## `cast_fizzled`) and nothing is paid. A refused cast changes nothing else, except that a cast
## with nothing in it (every card wasted) still moves the staff on, so it never sticks there.
##
## While the staff has sustained (`hold`) carriers on, a cast switches them all off instead,
## frees their reservation and returns 0.0. The caller decides which presses may do that (a
## held button should not switch on and off again and again).
##
## A held cast (this, not `press_staff`) of a carrier that pours on when held (`Carrier.pours_held`:
## a spray) that follows on from such a cast (by when the staff is ready again and `POUR_GRACE`)
## skips its staff's wind-up: an enemy telegraphs its spray
## once, then pours it while it holds the button (its cards' own wind-up stays; a player's staff has
## none). A held swing still winds up every time.
##
## `walk` is the way the caster's body walks (zero when it stands): a move it casts itself (a dash,
## a teleport: MOVES_CASTER) takes that way in place of `direction` (`CarrierMove`; staffs A6a, kept
## by the owner in R4 F1, teleport too since 2026-11-08).
func cast_staff(actor: int, staff: int, origin: Vector2, direction: Vector2, mana: float, walk: Vector2 = Vector2.ZERO) -> float:
	return _job_casts.cast_staff(actor, staff, origin, direction, mana, walk)


## `actor`'s winding casts leave no more and its staffs are free (a new driver took the body: the
## cast was the old one's; docs/milestones/cast-timing.md).
func cancel_winds(actor: int) -> void:
	_job_casts.cancel_winds(actor)


## The winding cast of `actor`'s staff `staff` leaves no more and the staff is free (a prop left the
## state that wound it up, props W6); nothing was paid.
func cancel_wind(actor: int, staff: int) -> void:
	_job_casts.cancel_wind(actor, staff)


## `actor`'s winding casts wait `seconds` longer (its Caster asks while the body is slowed: a chill
## stretches a wind-up, a freeze holds it; docs/milestones/cast-timing.md). Allocates nothing.
func hold_winds(actor: int, seconds: float) -> void:
	_job_casts.hold_winds(actor, seconds)


## Runs the cooldowns and the timer triggers by `delta` seconds, and opens a new step for
## the fire and jump caps. The autoload calls it every physics step; the order of the two
## autoloads in project.godot (Projectiles first) is what makes it run after the manager.
## So a cap's window is this step's timer fires plus the next step's hits, and a `cast` made
## between the two (a beam's on-expire spell, an actor's own cast) counts against whichever
## window is open.
func step(delta: float) -> void:
	# The shots that entered a new floor cell in the manager's step (it steps first), before the
	# carriers add theirs (the floor's first slice).
	_job_strikes._trail_shots()
	for c in _cooldown_rows:
		_cooldown[c] = maxf(_cooldown[c] - delta, 0.0)
	_fires_used.fill(0)
	# The zap cap's window opens before the carriers step: a live beam zaps in its `step`.
	_zaps_used = 0
	_clock += delta
	if _winding > 0:
		_job_casts._release_winds()
	_job_fires._run_waiting_fires()
	_job_launches._step_followers()
	_moves.step(delta)
	for carrier: Carrier in _carriers.values():
		carrier.step(delta)
	# After the carriers: a dash's pass that ended has let its carries go.
	_plow.step(delta)
	_job_lasting._step_live(delta)
	_job_zaps._step_zaps(delta)
	_job_zaps._step_magnets()
	_job_fires._run_pending()
	_job_strikes._send_passed()


## `SpellLaunches._launch` (_job_launches), for the kit and the tests.
func _launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, source: Node, chain: int = -1, prev: int = 0) -> int:
	return _job_launches._launch(spell, tag, actor, origin, direction, source, chain, prev)


## `SpellLaunches._carrier_of` (_job_launches), for the kit and the tests.
func _carrier_of(spell: CompiledSpell) -> Carrier:
	return _job_launches._carrier_of(spell)


## `SpellLaunches._land_shot` (_job_launches), for the kit and the tests.
func _land_shot(slot: int, spell: CompiledSpell, tag: int, source: Node, chain: int, prev: int) -> int:
	return _job_launches._land_shot(slot, spell, tag, source, chain, prev)


## `SpellLaunches._land_shots` (_job_launches), for the kit and the tests.
func _land_shots(slots: PackedInt32Array, count: int, spell: CompiledSpell, tag: int, source: Node, chain: int, prev: int) -> int:
	return _job_launches._land_shots(slots, count, spell, tag, source, chain, prev)


## `SpellStrikes._ray_begin` (_job_strikes), for the kit and the tests.
func _ray_begin(tag: int, dir: Vector2, chain: int, prev: int, hit: HitProfile, zap_slot: int) -> RayHit:
	return _job_strikes._ray_begin(tag, dir, chain, prev, hit, zap_slot)


## `SpellStrikes._ray_end` (_job_strikes), for the kit and the tests.
func _ray_end() -> void:
	_job_strikes._ray_end()


## `SpellStrikes._strike` (_job_strikes), for the kit and the tests.
func _strike(spell: CompiledSpell, tag: int, actor: int, found: int, struck: Array, centre: Vector2, chain: int, prev: int, hit: HitProfile) -> HitProfile:
	return _job_strikes._strike(spell, tag, actor, found, struck, centre, chain, prev, hit)


## `SpellStrikes._strike_bodies_at` (_job_strikes), for the kit and the tests.
func _strike_bodies_at(spell: CompiledSpell, tag: int, actor: int, nodes: Array[Node], points: PackedVector2Array, heads: PackedVector2Array, count: int, struck: Array, centre: Vector2, chain: int, prev: int, hit: HitProfile) -> HitProfile:
	return _job_strikes._strike_bodies_at(spell, tag, actor, nodes, points, heads, count, struck, centre, chain, prev, hit)


## `SpellStrikes._strike_round` (_job_strikes), for the kit and the tests.
func _strike_round(spell: CompiledSpell, tag: int, actor: int, at: Vector2, way: Vector2, reach: float, hit: HitProfile, chain: int = -1, prev: int = 0, spare: Node = null) -> void:
	_job_strikes._strike_round(spell, tag, actor, at, way, reach, hit, chain, prev, spare)


## `SpellLaunches._caster_shot` (_job_launches), for the kit and the tests.
func _caster_shot() -> int:
	return _job_launches._caster_shot()


## `caster` when it is a shot's slot and that shot (`seq`) still flies, else -1.
func live_caster_shot(caster: int, seq: int) -> int:
	return _job_launches.live_caster_shot(caster, seq)


## The caster (`_caster`) that is the body of the actor `body`: what a payload it fired is cast by.
static func body_caster(body: int) -> int:
	return CASTER_BODIES - body


## The actor whose body the caster `caster` is, in a launch by `actor`: `actor` for its own cast,
## the actor a `body_caster` names; -1 for a shot or a point.
static func body_of(caster: int, actor: int) -> int:
	if caster == CASTER_BODY:
		return actor
	return CASTER_BODIES - caster if caster <= CASTER_BODIES else -1


## `SpellLaunches._live_caster` (_job_launches), for the kit and the tests.
func _live_caster(caster: int, seq: int) -> int:
	return _job_launches._live_caster(caster, seq)


## `SpellLaunches._cast_as` (_job_launches), for the kit and the tests.
func _cast_as(caster: int, seq: int) -> void:
	_job_launches._cast_as(caster, seq)


## A one-off homing pick for a card of `actor` (a teleport's target): a target of
## another team within `within` pixels of `at`, any way round, picked at random, rolled afresh for
## each pick (owner, 2026-11-06: "homing should just always pick a random enemy in range"; it may
## be the one picked last). Its centre, or INF for none; `projectiles.homing_target_reach` is how
## far its hit shape reaches toward `at`. A flying shot's steering keeps its target (`Projectiles.home_velocity`).
func pick_target(actor: int, at: Vector2, within: float) -> Vector2:
	return _job_launches.pick_target(actor, at, within)


## `SpellLaunches._cast_done` (_job_launches), for the kit and the tests.
func _cast_done() -> void:
	_job_launches._cast_done()


## `SpellLaunches._placed_at` (_job_launches), for the kit and the tests.
func _placed_at(spell: CompiledSpell, origin: Vector2, heading: Vector2) -> Vector2:
	return _job_launches._placed_at(spell, origin, heading)


## `SpellLaunches._apply_travel` (_job_launches), for the kit and the tests.
func _apply_travel(slot: int, spell: CompiledSpell) -> void:
	_job_launches._apply_travel(slot, spell)


## The angle the first Penta ring of the card with `tag` stands at: a start of its own (the same
## on every machine, and another for another card or build).
static func penta_start(tag: int) -> float:
	return float(posmod(hash(tag), 4096)) / 4096.0 * TAU


## The point at `angle` on the ring of `radius` round `centre`, stopped short of a wall.
static func ring_point(manager: ProjectilesScript, centre: Vector2, radius: float, angle: float) -> Vector2:
	var point: Vector2 = centre + DMath.from_angle(angle) * radius
	return manager.grid().clip_to_walls(centre, point) if manager != null else point


## `SpellStrikes._blast` (_job_strikes), for the kit and the tests.
func _blast(spell: CompiledSpell, tag: int, actor: int, at: Vector2, shot: int = -1) -> void:
	_job_strikes._blast(spell, tag, actor, at, shot)


## `SpellStrikes._touch_floor` (_job_strikes), for the kit and the tests.
func _touch_floor(spell: CompiledSpell, actor: int, at: Vector2, radius: float, tag: int) -> void:
	_job_strikes._touch_floor(spell, actor, at, radius, tag)


## `SpellStrikes._spill` (_job_strikes), for the kit and the tests.
func _spill(spell: CompiledSpell, actor: int, at: Vector2, tag: int) -> void:
	_job_strikes._spill(spell, actor, at, tag)


## `SpellStrikes._pass_floor` (_job_strikes), for the kit and the tests.
func _pass_floor(spell: CompiledSpell, tag: int, actor: int, from: Vector2, to: Vector2) -> void:
	_job_strikes._pass_floor(spell, tag, actor, from, to)


## `SpellFires._delay` (_job_fires), for the kit and the tests.
func _delay(wait: float, group: CompiledGroup, spell: CompiledSpell, actor: int, staff: int, generation: int, origin: Vector2, heading: Vector2, source: Node, from_caster: bool) -> PendingLaunch:
	return _job_fires._delay(wait, group, spell, actor, staff, generation, origin, heading, source, from_caster)


## `SpellLaunches._fan_angle` (_job_launches), for the kit and the tests.
func _fan_angle(n: int, count: int, spell: CompiledSpell) -> float:
	return _job_launches._fan_angle(n, count, spell)


## `SpellLaunches._staff_spread` (_job_launches), for the kit and the tests.
func _staff_spread(tag: int, spell: CompiledSpell) -> float:
	return _job_launches._staff_spread(tag, spell)


## Who cast the shot in `slot` (see `_caster`): the live shot that cast it, the body that cast it
## (its own actor's: CASTER_BODY; another's while it follows it: `body_caster`), else the point. It
## still answers for a shot ended by the hit being sent (a pull's), until its slot is used again.
func shot_caster(slot: int) -> int:
	return _job_launches.shot_caster(slot)


## `SpellLaunches._grow_records` (_job_launches), for the kit and the tests.
func _grow_records(size: int) -> void:
	_job_launches._grow_records(size)


## `SpellStrikes._shoot_ray` (_job_strikes), for the kit and the tests.
func _shoot_ray(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, heading: Vector2, chain: int, prev: int, source: Node, length: float = -1.0, hit: HitProfile = null) -> void:
	_job_strikes._shoot_ray(spell, tag, actor, origin, heading, chain, prev, source, length, hit)


## `SpellStrikes._guard_path` (_job_strikes), for the kit and the tests.
func _guard_path(spell: CompiledSpell, tag: int, actor: int, points: PackedVector2Array, first: int, count: int, reach: float, width: float, charges: int, carrier: StringName) -> int:
	return _job_strikes._guard_path(spell, tag, actor, points, first, count, reach, width, charges, carrier)


## `SpellStrikes._guard` (_job_strikes), for the kit and the tests.
func _guard(found: int, actor: int, tag: int, deflects: bool, charges: int, a: Vector2, b: Vector2, carrier: StringName) -> int:
	return _job_strikes._guard(found, actor, tag, deflects, charges, a, b, carrier)


## `SpellStrikes._guard_shots` (_job_strikes), for the kit and the tests.
func _guard_shots(slots: PackedInt32Array, actor: int, tag: int, deflects: bool, charges: int, a: Vector2, b: Vector2, carrier: StringName) -> int:
	return _job_strikes._guard_shots(slots, actor, tag, deflects, charges, a, b, carrier)


## `SpellStrikes._bounces` (_job_strikes), for the kit and the tests.
func _bounces(spell: CompiledSpell) -> int:
	return _job_strikes._bounces(spell)


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
	# Down or gone: its winding casts leave no more.
	for staff in SpellLimits.STAFFS:
		_job_casts._cancel_wind(actor * SpellLimits.STAFFS + staff)


## `SpellFires._cast_jumps` (_job_fires), for the kit and the tests.
func _cast_jumps() -> void:
	_job_fires._cast_jumps()


## `SpellFires._fire_payloads` (_job_fires), for the kit and the tests.
func _fire_payloads(spell: CompiledSpell, event: int, tag: int, actor: int, at: Vector2, heading: Vector2, source: Node, caster: int = CASTER_POINT) -> void:
	_job_fires._fire_payloads(spell, event, tag, actor, at, heading, source, caster)


## `SpellFires._fire` (_job_fires), for the kit and the tests.
func _fire(group: CompiledGroup, actor: int, staff: int, generation: int, at: Vector2, heading: Vector2, source: Node, caster: int, wound: bool = false) -> void:
	_job_fires._fire(group, actor, staff, generation, at, heading, source, caster, wound)


## How many times one firing of `spell` casts its carrier: twice with Mirror, times its Nova ways,
## times its Penta ring's copies where Penta works.
func copies_of(spell: CompiledSpell) -> int:
	return _job_launches.copies_of(spell)


## A snapshot restored (online-ready N10, core/sim/snapshot.gd): every live shot this runtime knows
## draws as its card's body and light again. The projectile manager keeps them as VIEW, numbered by
## this machine as it first meets each card's shader (`register_body`), so a restored world numbers
## them here, by the shot's spell (N12 found the numbers parting a restored world).
func rebuild_derived() -> void:
	_link_jobs()
	if projectiles == null:
		return
	for slot in mini(_rec_seq.size(), projectiles.get_cap()):
		if not _knows(slot):
			continue
		var spell: CompiledSpell = _profiles.get(projectiles.get_tag_of(slot))
		if spell == null:
			continue
		var launch: LaunchLook = _job_views._launch_look_of(spell)
		projectiles.set_body(slot, launch.body)
		projectiles.set_light(slot, launch.light_intensity, launch.light_reach)


## True when the record of `slot` was made for the shot the manager last had there (it may
## have ended just now).
func _same(slot: int) -> bool:
	return slot >= 0 and slot < _rec_seq.size() and _rec_seq[slot] == projectiles.get_seq_of(slot)


## True when `slot` holds a live shot this record was made for.
func _knows(slot: int) -> bool:
	return _same(slot) and projectiles.is_alive(slot)


## When a carrier that lives `life` seconds first does what it does every `interval` (a timer's
## tick, an arc's zap): after the interval, or half its life when that is shorter, so a short
## carrier (a swap, an atom, a beam) does it once before it ends (owner, 2026-10-29).
static func first_tick(interval: float, life: float) -> float:
	return minf(interval, life * 0.5)


## `SpellLasting._lc_join` (_job_lasting), for the kit and the tests.
func _lc_join(spell: CompiledSpell, tag: int, kind: int, ref: int, seq: int, tied: bool, life: float, at: Vector2, way: Vector2) -> void:
	_job_lasting._lc_join(spell, tag, kind, ref, seq, tied, life, at, way)


## `SpellLasting._lc_leave` (_job_lasting), for the kit and the tests.
func _lc_leave(tag: int, every: bool) -> void:
	_job_lasting._lc_leave(tag, every)


## `SpellLasting._lc_leave_key` (_job_lasting), for the kit and the tests.
func _lc_leave_key(tag: int, key: int) -> void:
	_job_lasting._lc_leave_key(tag, key)


## `SpellLasting._lc_where` (_job_lasting), for the kit and the tests.
func _lc_where(i: int) -> Vector2:
	return _job_lasting._lc_where(i)


## The `n`th random number in [0, 1) of the zapper born `seed` (a shot's sequence number, a live
## beam's birth): a hash, the same every run.
static func zap_hash(seed: int, n: int) -> float:
	var h: int = (seed * 73856093) ^ (n * 19349663) ^ 83492791
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0


## `SpellZaps._zap_ray` (_job_zaps), for the kit and the tests.
func _zap_ray(spell: CompiledSpell, tag: int, at: Vector2, aim: Vector2, chain: int, prev: int, hit: HitProfile, slot: int) -> void:
	_job_zaps._zap_ray(spell, tag, at, aim, chain, prev, hit, slot)


## A new press of this actor's staff (not a held button's repeat: the caller tells them apart, as
## for a `hold`'s switch-off): its live `on recast` carriers go off (`recast_staff`), then it casts
## (`cast_staff`, whose return this is), so the carrier this press casts is not one of them.
func press_staff(actor: int, staff: int, origin: Vector2, direction: Vector2, mana: float, walk: Vector2 = Vector2.ZERO) -> float:
	return _job_casts.press_staff(actor, staff, origin, direction, mana, walk)


## `on recast`: staff `staff` of `actor` is pressed again (`press_staff`). Every live carrier that
## staff cast with that trigger fires its payload from where it is now, the way a timer's tick does,
## whether or not the staff is ready to cast again: the press is the detonation. It fires every
## time while the carrier lives; a payload's own `on recast` waits for the next press. Returns how
## many fired.
func recast_staff(actor: int, staff: int) -> int:
	return _job_casts.recast_staff(actor, staff)


## `base` with every element of `donor` it does not have yet (each with its status), as relay
## merges them; null when `donor` adds nothing. What a portal's infusion gives what goes through
## it (docs/milestones/portal.md).
static func merge_hit(base: HitProfile, donor: HitProfile) -> HitProfile:
	if base == null or donor == null:
		return null
	var merged: HitProfile = null
	for n in donor.element_ids.size():
		var id: StringName = donor.element_ids[n]
		if base.element_ids.has(id) or (merged != null and merged.element_ids.has(id)):
			continue
		if merged == null:
			merged = base.copy()
		_add_element(merged, donor, n)
	return merged


## `SpellHits._infuse_shot` (_job_hits), for the kit and the tests.
func _infuse_shot(slot: int, donor: HitProfile, tint: Color) -> void:
	_job_hits._infuse_shot(slot, donor, tint)


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


## The run's rules (core/sim/session_rules.gd; the Tick hands them over before `begin_run`): the
## shots a trigger's fires may make in one step.
func take_rules(rules: SessionRules) -> void:
	if rules != null:
		fire_shots_per_step = rules.fire_shots

## A run starts (`Tick.begin_run`, online-ready N3b): everything `clear` forgets, then a fresh
## runtime's state (core/sim/sim_fresh.gd): its clock, record sequence numbers, pools, staffs, poses
## and carriers, the same objects, with this session's settings (RUN_KEEPS).
func begin_run() -> void:
	clear()
	SimFresh.renew(self)
	_link_jobs()


## Links every job to this runtime's members again (`link`): at start, and whenever its arrays may
## have been replaced by others (a snapshot's restore, `rebuild_derived`; a run's renew, `begin_run`).
func _link_jobs() -> void:
	_job_views.link(self)
	_job_generations.link(self)
	_job_casts.link(self)
	_job_launches.link(self)
	_job_fires.link(self)
	_job_strikes.link(self)
	_job_lasting.link(self)
	_job_zaps.link(self)
	_job_hits.link(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# The jobs are plain objects (a call into one costs less than into a counted one): freed with it.
		_job_views.free()
		_job_generations.free()
		_job_casts.free()
		_job_launches.free()
		_job_fires.free()
		_job_strikes.free()
		_job_lasting.free()
		_job_zaps.free()
		_job_hits.free()


## Forgets every registered spell and shot count (a new run, and tests).
func clear() -> void:
	_cooldown.fill(0.0)
	_cooldown_rows = 0
	_wind_due.fill(INF)
	_winding = 0
	_fires_used.fill(0)
	_jq_head = 0
	_jq_count = 0
	_moves.clear()
	_plow.clear()
	_caster = CASTER_BODY
	_picks = 0
	_outer_count = 0
	_fl_count = 0
	for carrier: Carrier in _carriers.values():
		carrier.clear()
	_poses.clear()
	_aim_pivot.fill(Vector2.INF)
	_aim_origin.fill(Vector2.INF)
	_aim_dir.fill(Vector2.INF)
	_aim_seen.fill(0)
	for launch in _pending:
		_job_fires._release_launch(launch)
	_pending.clear()
	_penta_rings.clear()
	_ring.fill(-1)
	_open_ring.fill(-1)
	_open_builds.fill(0)
	_last_carrier_card.fill(&"")
	_cast_count.fill(0)
	_pour_until.fill(-1.0)
	_cast_turn.fill(0.0)
	_lc_count = 0
	_zapper_count = 0
	_magnet_count = 0
	_magnet_from = 0
	_rec_magnet.fill(0)
	_rec_seq.fill(-1)
	_rec_zapper.fill(0)
	_rec_due_count.fill(0)
	_rec_due_body.fill(null)
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
	_caster_live.fill(0)
	_caster_rows = 0
	revoked_tags.clear()


## How many casters' parts the state hash takes (props W3; core/sim/README.md, "The hash"): actor
## ids 0 to this less one, each `actor_part(id)`. Every other id has nothing in the BY_ACTOR tables.
func actor_parts() -> int:
	return _caster_rows


## Caster `actor`'s share of the BY_ACTOR tables, for the state hash (walked as "Spells 7", in the
## spread hash's part with the body "actor 7"; core/sim/README.md, "The hash"), empty for an id with
## none (a caster gone, its shots ended):
## - `[builds, infused]`: its builds as installed, staff by staff (FROZEN: one leaf each), and the
##   carrier of its last infused cast;
## - only while something of its builds is alive (`_caster_live`), a third entry: each generation it
##   holds by name ("s0g3": staff 0, generation 3), with its node count, what is alive of it, its
##   live shots by node and, for a build no longer current, its spells; a report names the field.
## A resting caster needs no more: its only generations are its staffs' current ones, whose spells
## are its builds' nodes, set and freed together (`actor_part_problems` checks both). Looked up by
## key, never by sorting a table.
func actor_part(actor: int) -> Array:
	var base: int = actor * SpellLimits.STAFFS
	var any: bool = _caster_live[actor] > 0 or _last_infused[actor] != null
	for staff in SpellLimits.STAFFS:
		any = any or _installed[base + staff] != null
	if not any:
		return []
	var builds: Array = _installed.slice(base, base + SpellLimits.STAFFS)
	if _caster_live[actor] == 0:
		return [builds, _last_infused[actor]]
	var generations: Dictionary = {}
	for staff in SpellLimits.STAFFS:
		var current: int = _current[base + staff]
		for generation in SpellLimits.GENERATIONS:
			var key: int = SpellTag.generation_key(SpellTag.make(actor, staff, 0, generation))
			if not _node_counts.has(key):
				continue
			var nodes: int = _node_counts[key]
			var live := PackedInt32Array()
			var spells: Array = []
			for node in nodes:
				var tag: int = SpellTag.make(actor, staff, node, generation)
				live.append(_live.get(tag, 0))
				if generation != current:
					spells.append(_profiles.get(tag))
			generations["s%dg%d" % [staff, generation]] = {"nodes": nodes, "alive": _generation_live.get(key, 0), "live": live, "spells": spells}
	return [builds, _last_infused[actor], generations]


## What `actor_part` stands on, checked (an empty list when it holds): each caster's live count is
## the sum of its generations' (`_caster_live`); every spell, node count and live count belongs to a
## generation that is held; a caster with nothing alive holds only its staffs' current generations;
## and a current generation's spells are its installed build's nodes. A test asks after play (every
## card's walk, tests/core/test_state_walked.gd), so a new writer of the BY_ACTOR tables that breaks
## one is named, not hashed past. Not for the game: it walks every table.
func actor_part_problems() -> PackedStringArray:
	var out := PackedStringArray()
	var sums := PackedInt32Array()
	sums.resize(ACTORS)
	for key: int in _generation_live:
		sums[SpellTag.caster_of(key)] += int(_generation_live[key])
	for actor in ACTORS:
		if sums[actor] != _caster_live[actor]:
			out.append("caster %d: live count %d, its generations' %d" % [actor, _caster_live[actor], sums[actor]])
		if actor >= _caster_rows and (sums[actor] > 0 or _last_infused[actor] != null):
			out.append("caster %d: has state at or past actor_parts() (%d)" % [actor, _caster_rows])
	for key: int in _node_counts:
		var actor: int = SpellTag.caster_of(key)
		var index: int = actor * SpellLimits.STAFFS + SpellTag.staff_of(key)
		var current: bool = _current[index] == SpellTag.generation_of(key)
		if actor >= _caster_rows:
			out.append("caster %d: a generation at or past actor_parts() (%d)" % [actor, _caster_rows])
		if not current and _caster_live[actor] == 0:
			out.append("caster %d staff %d: an older generation %d held with nothing alive" % [actor, SpellTag.staff_of(key), SpellTag.generation_of(key)])
		if current:
			var build: CompiledStaff = _installed[index]
			if build == null or build.nodes.size() != int(_node_counts[key]):
				out.append("caster %d staff %d: the current generation's node count is not its build's" % [actor, SpellTag.staff_of(key)])
				continue
			for spell in build.nodes:
				if _profiles.get(SpellTag.make(actor, SpellTag.staff_of(key), spell.node, SpellTag.generation_of(key))) != spell:
					out.append("caster %d staff %d: a current spell is not its build's node %d" % [actor, SpellTag.staff_of(key), spell.node])
	for tag: int in _profiles:
		if not _node_counts.has(SpellTag.generation_key(tag)) or SpellTag.node_of(tag) >= int(_node_counts.get(SpellTag.generation_key(tag), 0)):
			out.append("tag %d: a spell of no held generation's nodes" % tag)
	for tag: int in _live:
		if not _profiles.has(tag) or _caster_live[SpellTag.caster_of(tag)] == 0:
			out.append("tag %d: live shots of no spell, or of a caster with nothing alive" % tag)
	for key: int in _generation_live:
		if not _node_counts.has(key):
			out.append("generation %d: alive but not held" % key)
	return out


## Opens the caster `actor` (an actor id a body opened in the actor table, actors G3b): its
## staffs, delays, aim and the rest start new, so it installs, casts and aims (`install_staff`,
## `cast_staff`, `set_aim`) from a clean row; generations go on round the ring, so shots of an
## earlier caster with the same id keep theirs. A body calls it once, before its first build.
## Returns false for an id outside the table.
func open_caster(actor: int) -> bool:
	return _job_casts.open_caster(actor)


## True when the spell tag `tag` is of a build the caster open now under its id began (`open_caster`,
## then `install_staff`), not one of an earlier caster with the same id whose shots still fly, nor
## of a caster closed since: what reads the caster's body at the hit (Combat's power, boss plan OB7)
## asks it first. Builds count from the caster's open; past GENERATIONS of them every generation
## of the ring is its own (the older shots of each were revoked as it began them).
func cast_by_open(tag: int) -> bool:
	return _job_casts.cast_by_open(tag)


## The caster `actor` is gone (its body left or died): its staffs are emptied, its own waiting
## launches (a cast's later firings), holds and beams end. Its shots in the air fly on with their
## own numbers until they end, and their waiting payloads fire on, as after an edit. The body
## closes its actor id in the table itself.
func close_caster(actor: int) -> void:
	_job_casts.close_caster(actor)


## Which cast of this actor's staff's cycle a press with `mana` fires (an unaffordable one is
## skipped; docs/milestones/cast-timing.md, T3), -1 when the mana pays none left in the cycle or it
## has no build: what the corner panel marks.
func firing_cast(actor: int, staff: int, mana: float) -> int:
	return _job_casts.firing_cast(actor, staff, mana)


## The mana the next cast of this caster's staff costs: the one a press with `mana` would fire
## (an unaffordable one is skipped; with INF, the one at the cursor), 0.0 while its sustained
## carriers are on (that press switches them off), or REFUSED when it has no build. An enemy's AI
## asks before it winds up, so a telegraph is always followed by its cast.
func next_cast_mana(actor: int, staff: int, mana: float = INF) -> float:
	return _job_casts.next_cast_mana(actor, staff, mana)


## True when a cast of this actor's staff can leave within `within` seconds with `mana` (that
## staff's pool): its delay is no longer than that, and `mana` less what the staff's sustained
## carriers hold (`reserved_mana`) pays a cast before the cycle's end (the ones it cannot pay are
## skipped; docs/milestones/cast-timing.md). False with no build. One call for what an enemy's AI
## asks every step while its target is in reach (performance pass, 2026-10-28).
func cast_ready(actor: int, staff: int, within: float, mana: float) -> bool:
	return _job_casts.cast_ready(actor, staff, within, mana)


## How far the next cast of this caster's staff reaches along its aim, for an enemy's telegraph:
## its first carrier's flight (speed x life), a beam's or swing's length;
## 0 for one that is not aimed (a nova, an orbit, a still shot, a decoy...) or no build.
func next_cast_reach(actor: int, staff: int, mana: float = INF) -> float:
	return _job_casts.next_cast_reach(actor, staff, mana)


## What the next cast of this caster's staff does (`CastSense`; docs/milestones/M2-enemy-ai.md),
## for an AI that plays whatever staffs it holds: the one a press with `mana` would fire; null
## with no build.
func next_cast_sense(actor: int, staff: int, mana: float = INF) -> CastSense:
	return _job_casts.next_cast_sense(actor, staff, mana)


## The hit radius of the next cast's first carrier (0 for none), for the width of a telegraph.
func next_cast_radius(actor: int, staff: int, mana: float = INF) -> float:
	return _job_casts.next_cast_radius(actor, staff, mana)


## The node of the actor `body`'s body (null for -1, an actor with none, or no table).
func _body_node(body: int) -> Node:
	if body < 0:
		return null
	var table: ActorsScript = _actor_table()
	return table.node_of(body) if table != null else null


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


## The body seat `seat`'s (0-3) HUD is about (`Actors.shown_of_seat`, items I8): the one it drives,
## else its own wizard; for the HUD, which knows seats and asks Spells by caster (`cast_index`,
## `cooldown_left`).
func shown_of_seat(seat: int) -> int:
	var table: ActorsScript = _actor_table()
	return table.shown_of_seat(seat) if table != null else ActorsScript.NONE


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


## The party left the room for the next of the run (`room_left`, run generation RG4): what every
## caster's spells left in it ends quietly with it, as the room goes (no blast, no payload, no end
## point): its casts winding up, its waiting launches, its held carriers, every carrier's own rows
## (beams, portals, rings, swings, slams, decoys and familiars) and its moves. The shots in the air are the projectile
## manager's to end (each `shot_ended`). Every caster keeps its builds, delays and mana: the party
## goes on as it is.
func leave_room() -> void:
	_job_casts.leave_room()


## `SpellGenerations._release_hold` (_job_generations), for the kit and the tests.
func _release_hold(index: int) -> void:
	_job_generations._release_hold(index)


## Mana the sustained carriers of this actor's staff `staff` hold from that staff's pool.
func reserved_mana(actor: int, staff: int) -> float:
	return _hold_mana[actor * SpellLimits.STAFFS + staff] if _job_casts._in_range(actor, staff) else 0.0


## `SpellViews._component` (_job_views), for the kit and the tests.
func _component(id: StringName) -> SpellComponent:
	return _job_views._component(id)


## Where the familiar with `key` (`entity_key`) is now, told by Entities every step: what its
## triggers cast comes from there.
func familiar_at(key: int, at: Vector2) -> void:
	_job_hits.familiar_at(key, at)


# The carriers and the staff animations, for their looks (`gameplay/feel`, the actor's look), `ai`,
# the actor's mover and the tests: each is read from the object that keeps it.

## This runtime's carrier `id` (bound, with the rows it keeps), or the one that runs nothing for
## an id no carrier has. A reader that wants one carrier's own getters asks that carrier's class
## (`CarrierBeam.of(spells)`), so this runtime names none.
func carrier(id: StringName) -> Carrier:
	var found: Carrier = _carriers.get(id)
	return found if found != null else _no_carrier


## What Plow carries (`Plow`: the carry velocity a body's mover reads, `velocity_of`).
func plow() -> Plow:
	return _plow


## Each actor's staff animation (`StaffPoses`: where each actor's staff is now).
func poses() -> StaffPoses:
	return _poses
