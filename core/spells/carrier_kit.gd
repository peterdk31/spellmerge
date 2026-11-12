class_name CarrierKit
extends RefCounted
## What a carrier may ask of the spell runtime that runs it (docs/CARRIERS.md, "What a carrier
## runs"): the cast under way, the aim, the shared shot kit, the shared hit path and what a carrier
## leaves behind. A carrier (and the runtime's own helpers, `CasterMoves` and `StaffPoses`) uses
## only this, never the runtime's own members, so this file is the whole of what a new carrier
## needs to know about `Spells`. Each call is the runtime's one rule for it, shared by every carrier.
## The runtime's constants (`SpellRuntime.ACTORS`, `HITS`, `CASTER_BODY`, `CASTER_POINT`, the
## live carrier kinds `LC_*`) are read from `SpellRuntime` itself.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

## Not state: services, caches and scratch, set up again (core/sim/README.md).
const DERIVED: Array[StringName] = [&"projectiles", &"events"]

var _rt: SpellRuntime = null
## The body made for the last `request_entity` (`entity_body`).
var _entity_body: int = -1


func _init(runtime: SpellRuntime) -> void:
	_rt = runtime


# --- The world -----------------------------------------------------------------

## The looks the next events show are the spell `tag`'s (`SpellRuntime.cue_tag`; 0 for none): set
## round a `carrier_shown` or `carrier_ended`, so the cue it plays throws its cards' motes and marks
## (gameplay/feel; docs/milestones/spell-spectacle-2.md, S2 and S5). For looks only.
func set_cue_tag(tag: int) -> void:
	_rt.cue_tag = tag


## The projectile manager the runtime casts into (null before `Spells.bind`).
var projectiles: ProjectilesScript:
	get:
		return _rt.projectiles

## The event bus (null in a test that binds none).
var events: EventsScript:
	get:
		return _rt.events


## Seconds the runtime has stepped (`Spells.step`): what a carrier times its rows by.
func clock() -> float:
	return _rt._clock


# --- The cast under way ------------------------------------------------------------

## The spell registered under `tag`, or null when its build is gone.
func spell_of(tag: int) -> CompiledSpell:
	return _rt._profiles.get(tag)


## The carrier that runs `spell`: the one its `carrier` names, or the one that runs nothing.
func carrier_of(spell: CompiledSpell) -> Carrier:
	return _rt._carrier_of(spell)


## Who casts the launch being fired, one value: the actor's own body (`SpellRuntime.CASTER_BODY`),
## the body of an actor that fired a payload (`SpellRuntime.body_caster`), the slot of the live shot
## that fired it (see `caster_seq`), or `CASTER_POINT` (a point, also for a shot that has ended
## since). Every carrier asks this one: `SpellRuntime.body_of(caster, actor)` names the body, a slot
## is the shot; a row its caster holds keeps the value (`live_caster_shot` for a shot later).
func caster() -> int:
	return _rt._live_caster(_rt._caster, _rt._caster_seq)


## The birth (`Projectiles.get_seq_of`) of the shot `caster` names, when it names one.
func caster_seq() -> int:
	return _rt._caster_seq


## The actor whose body casts the launch being fired by `actor`: `actor` itself for its own cast,
## the body that fired a payload (a decoy, the wizard dashing), or -1 for a shot or a point: what a
## move moves, an orbit circles, a held carrier follows and a payload's left-over cards land on.
func caster_body(actor: int) -> int:
	return SpellRuntime.body_of(_rt._caster, actor)


## Where the caster of the launch being fired by `actor` is now: the body's anchor, the shot's
## place, else `origin` (the point it is cast from).
func caster_place(actor: int, origin: Vector2) -> Vector2:
	var body: int = caster_body(actor)
	if body >= 0 and _rt.projectiles.get_anchor(body).is_finite():
		return _rt.projectiles.get_anchor(body)
	var shot: int = caster_shot()
	return _rt.projectiles.get_position_of(shot) if shot >= 0 else origin


## What a carrier does from here to the matching `cast_done` is cast by `caster` (a value as
## `caster()`, with `seq`, the shot's birth, for a slot): a row's later step hits as the launch that
## made it (a held beam, a swing, a slam, a dash's pass), so its pull, swap or payload reads the
## caster that row keeps. One pair, around each step of a row.
func cast_as(caster: int, seq: int) -> void:
	_rt._cast_as(caster, seq)


func cast_done() -> void:
	_rt._cast_done()


## A one-off homing pick (a teleport's target): a random target of another team
## within `within` of `at`, any way round, rolled afresh each time (`Spells.pick_target`). Its centre,
## or INF; `projectiles.homing_target_reach` is how far its hit shape reaches toward `at`.
func pick_target(actor: int, at: Vector2, within: float) -> Vector2:
	return _rt.pick_target(actor, at, within)


## Who cast the shot in `slot` (a value as `caster`): what its pull or swap moves.
func shot_caster(slot: int) -> int:
	return _rt.shot_caster(slot)


## The turning Penta ring the copy being cast now stands on (`SpellRuntime._penta`): its centre,
## its radius (0 when the copy is on none) and the copy's angle on it now.
func ring_centre() -> Vector2:
	return _rt._ring_centre


func ring_radius() -> float:
	return _rt._ring_radius


func ring_angle() -> float:
	return _rt._ring_angle


## How fast and which way that ring turns, radians a second.
func ring_turn() -> float:
	return _rt._ring_turn


## The point at `angle` on such a ring, stopped short of a wall.
func ring_point(centre: Vector2, radius: float, angle: float) -> Vector2:
	return SpellRuntime.ring_point(_rt.projectiles, centre, radius, angle)


## The live shot casting the launch being fired, or -1 when the caster is the wizard, a point, or
## a shot that has ended since: the shot a carrier cast by a shot moves or circles.
func caster_shot() -> int:
	return _rt._caster_shot()


## `caster` when it is a shot's slot and that shot (`seq`) still flies, else -1.
func live_caster_shot(caster_slot: int, seq: int) -> int:
	return _rt.live_caster_shot(caster_slot, seq)


## True while `spell` is launched as an echo: its hits are its `echo_hit`.
func is_echo(spell: CompiledSpell) -> bool:
	return _rt._echo_spell == spell


## A shot (or a row a carrier counts as one) with `tag` started, or ended: its build is kept while
## any is out (`Spells.shot_started`, `shot_ended`).
func shot_started(tag: int) -> void:
	_rt.shot_started(tag)


func shot_ended(tag: int) -> void:
	_rt.shot_ended(tag)


# --- The aim (`Spells.set_aim`) ----------------------------------------------------

## The staff tip of `actor` (INF when it holds none): where a live beam starts.
func aim_origin(actor: int) -> Vector2:
	return _rt._aim_origin[actor]


## The aim of `actor` (INF when it holds none).
func aim_dir(actor: int) -> Vector2:
	return _rt._aim_dir[actor]


## The hand of `actor` (INF when not given): what a swing or a slam turns round.
func aim_pivot(actor: int) -> Vector2:
	return _rt._aim_pivot[actor]


## True once `actor` has sent an aim (a test that never does keeps its rows where they were cast).
func aim_seen(actor: int) -> bool:
	return _rt._aim_seen[actor] != 0


## The angle from the aim of `actor` to the way its body walked at its last cast (0 standing): a
## move it casts itself (MOVES_CASTER) is turned by it.
func walk_turn(actor: int) -> float:
	return _rt._walk_turn[actor]


# --- Shots ---------------------------------------------------------------------------

## Radians off the aim of shot `n` of `count`: none for one shot, an even ring for a 360 degree
## spread, otherwise an even fan centred on the aim.
func fan_angle(n: int, count: int, spell: CompiledSpell) -> float:
	return _rt._fan_angle(n, count, spell)


## Radians a shot of `spell` (cast as `tag`) leaves off its line from its staff's spread.
func staff_spread(tag: int, spell: CompiledSpell) -> float:
	return _rt._staff_spread(tag, spell)


## Where a carrier its caster places (a rune, a decoy, a familiar) appears: a step ahead of
## `origin` along `heading`, never in a wall.
func placed_at(spell: CompiledSpell, origin: Vector2, heading: Vector2) -> Vector2:
	return _rt._placed_at(spell, origin, heading)


## The floor line of what falls now (Skyfall: the fall being cast, or the falling shot casting),
## INF for none.
func floor_now() -> float:
	return _rt._skyfall.floor_now()


## Where a carrier placed at `point` goes: there, or on the floor line below it while it falls
## (Skyfall, `core/spells/skyfall.gd`). Every carrier that places itself asks this.
func on_floor(spell: CompiledSpell, point: Vector2) -> Vector2:
	return _rt._skyfall.on_floor(spell, point)


## Orbit: how fast a beam of `spell` sweeps round its caster, in radians a second (0 for one that
## does not circle; core/spells/orbit.gd).
func orbit_sweep(spell: CompiledSpell) -> float:
	return _rt._orbit.sweep_of(spell)


## The carrier `actor` holds has turned its staff `radians` round the hand, on top of its animation
## (`StaffPoses.turn_staff`: a sweeping beam turns the staff with it).
func turn_staff(actor: int, radians: float) -> void:
	_rt._poses.turn_staff(actor, radians)


## A shot spawned in `slot` (-1 when the manager refused it) takes its cards and its record and does
## not hit `source` for a while: 1 when it was made. What a carrier calls after `projectiles.spawn`.
func land_shot(slot: int, spell: CompiledSpell, tag: int, source: Node, chain: int, prev: int) -> int:
	return _rt._land_shot(slot, spell, tag, source, chain, prev)


## `land_shot` for each of the first `count` shots in `slots` (as `ProjectileManager.spawn_batch`
## wrote them; -1 for one not made), in turn: how many were made.
func land_shots(slots: PackedInt32Array, count: int, spell: CompiledSpell, tag: int, source: Node, chain: int, prev: int) -> int:
	return _rt._land_shots(slots, count, spell, tag, source, chain, prev)


## The shot in `slot` takes on the infusions of `donor` for its later hits (a portal's: it passed
## through one), its core `tint` when it had none.
func infuse_shot(slot: int, donor: HitProfile, tint: Color) -> void:
	_rt._infuse_shot(slot, donor, tint)
## `base` with the infusions of `donor` it lacks, or null when `donor` adds none.
func merge_hit(base: HitProfile, donor: HitProfile) -> HitProfile:
	return SpellRuntime.merge_hit(base, donor)
# --- Hits with no shot slot (a beam's, a sweep's, a strike, a zap, a jump) --------------

## Sends a ray: until `ray_end`, every hit with no shot slot is this one, with `tag`'s cards, going
## along `dir`, with `chain` jumps left after `prev`, hitting with `hit` when not its spell's own
## (null), as a zap of shot `zap_slot` (-1 for none). Returns the record (`RayHit`).
func ray_begin(tag: int, dir: Vector2, chain: int, prev: int, hit: HitProfile, zap_slot: int) -> RayHit:
	return _rt._ray_begin(tag, dir, chain, prev, hit, zap_slot)


## Ends the ray `ray_begin` sent.
func ray_end() -> void:
	_rt._ray_end()


## A zap of the carrier `spell` with `tag` from `at` to the body whose hit circle is at `aim`, with
## `chain` jumps left after `prev`, hitting with `hit` (`spell.zap_hit` or what replaces it): a hit
## of the carrier like any other, drawn as lightning (`Spells._zap_ray`). It casts its jumps too.
func zap(spell: CompiledSpell, tag: int, at: Vector2, aim: Vector2, chain: int, prev: int, hit: HitProfile) -> void:
	_rt._zap_ray(spell, tag, at, aim, chain, prev, hit, -1)


## True while zaps this step have room under `SpellLimits.MAX_ZAPS_PER_STEP`.
func zap_room() -> bool:
	return _rt._zaps_used < SpellLimits.MAX_ZAPS_PER_STEP


## A harmless spark of `spell` with `tag`: a zap's look from `at` along `way`, `length` pixels long.
func spark(spell: CompiledSpell, tag: int, at: Vector2, way: Vector2, length: float) -> void:
	_rt._zaps_used += 1
	if _rt.events != null:
		_rt.events.carrier_shown.emit(SpellTag.caster_of(tag), SpellRuntime.ZAP_CARD, at, way, length, spell.tint, spell.look)


## The team of `actor` (`Actors.team_of`; NONE without an actor table): what a zap aims away from.
func team(actor: int) -> int:
	return _rt._team(actor)


## Casts the chain jumps the hits so far queued (after a ray, outside its hit handler).
func cast_jumps() -> void:
	_rt._cast_jumps()


## The one strike (rules R4 F2): `spell` with `tag` hits each of the first `found` bodies of the
## last `Projectiles.sweep` round `centre` not in `struck` yet (and adds it), pushing it outward
## from `centre`. Returns what it hit with at the end (relay may have changed it). See `Spells._strike`.
func strike(spell: CompiledSpell, tag: int, actor: int, found: int, struck: Array, centre: Vector2, chain: int, prev: int, hit: HitProfile) -> HitProfile:
	return _rt._strike(spell, tag, actor, found, struck, centre, chain, prev, hit)


## `spell` with `tag` strikes every body within `reach` of `at` at once, with `hit` (null: its own),
## its caster's own too but `spare` (`spared`); a wall hides none.
func strike_round(spell: CompiledSpell, tag: int, actor: int, at: Vector2, way: Vector2, reach: float, hit: HitProfile, spare: Node = null) -> void:
	_rt._strike_round(spell, tag, actor, at, way, reach, hit, -1, 0, spare)


## The node of the actor `body`'s body (`caster_body`), null for -1 or none.
func body_node(body: int) -> Node:
	return _rt._body_node(body)


## What a strike of `spell` spares: `body`, the body it is cast from (or the one a move carries),
## when its carrier is melee (`Carrier.MELEE`: it never leaves that body, so never hits it), else
## nothing (a ranged one spares it only until it has left it, which the projectile manager measures). The one rule every carrier that strikes or rays reads (owner, 2026-11-06).
func spared(spell: CompiledSpell, body: Node) -> Node:
	return body if carrier_of(spell).has(Carrier.MELEE) else null


## Deflects (with `deflects`) or stops (while `charges` last) the `found` shots of
## `Projectiles.guard_slots` that touched a carrier of `actor` with `tag`: outward from `a` when `b`
## is INF, else off the segment from `a` to `b`. A block is sent as `carrier_card`'s (`block_shot`: a
## swing's is a parry). Returns the charges left.
func guard(found: int, actor: int, tag: int, deflects: bool, charges: int, a: Vector2, b: Vector2, carrier_card: StringName) -> int:
	return _rt._guard(found, actor, tag, deflects, charges, a, b, carrier_card)


## Turns the shots of other teams than `actor`'s within `reach` of `at` (MOVE_GUARD_REACH at
## least) outward from it, once, for the carrier with `tag` (`guard` with a deflect; the block is
## sent as `carrier_card`'s): a deflect on the caster as it is cast, a teleport's landing, a decoy as it
## appears, a payload's deflect landing on the body that fired it.
func turn_shots_round(actor: int, tag: int, at: Vector2, reach: float, carrier_card: StringName) -> void:
	if _rt.projectiles == null or not at.is_finite():
		return
	var around: float = maxf(reach, SpellLimits.MOVE_GUARD_REACH)
	_rt._guard(_rt.projectiles.shots_on_segment(actor, at, at, around), actor, tag, true, 0, at, at, carrier_card)


## `guard` along the path `points[first]` to `points[first + count - 1]` (cut `reach` pixels along),
## `width` pixels either side: a beam's line. Returns the charges left.
func guard_path(spell: CompiledSpell, tag: int, actor: int, points: PackedVector2Array, first: int, count: int, reach: float, width: float, charges: int) -> int:
	return _rt._guard_path(spell, tag, actor, points, first, count, reach, width, charges)


## How many times `spell`'s line turns at a wall: its bounce cards' count.
func bounces(spell: CompiledSpell) -> int:
	return _rt._bounces(spell)


## True when `spell`'s rays pass through walls (ghost).
func ghost(spell: CompiledSpell) -> bool:
	return SpellRuntime._ghost(spell)


# --- What a carrier leaves behind --------------------------------------------------

## A `blast` at the end point `at` of the carrier with `tag` (nothing without a blast card).
func blast(spell: CompiledSpell, tag: int, actor: int, at: Vector2) -> void:
	_rt._blast(spell, tag, actor, at)


## Fires the payload of every trigger of `spell` on `event` (a `TriggerBase.Event`) from `at`
## along `heading`, cast by the point `at`.
func fire_payloads(spell: CompiledSpell, event: int, tag: int, actor: int, at: Vector2, heading: Vector2, source: Node) -> void:
	_rt._fire_payloads(spell, event, tag, actor, at, heading, source)


## A trigger fires `group` from `at` along `heading`, cast by `caster` (a value as `caster()`: a
## shot's slot, a body, a point), now or when this step's budget has room. Nothing is dropped.
func fire(group: CompiledGroup, actor: int, staff: int, generation: int, at: Vector2, heading: Vector2, source: Node, caster: int) -> void:
	_rt._fire(group, actor, staff, generation, at, heading, source, caster)


## Queues a launch of `group` (or, with none, `spell`) `wait` seconds from now; returns the
## waiting launch (`SpellRuntime.PendingLaunch`), which a carrier may mark.
func delay(wait: float, group: CompiledGroup, spell: CompiledSpell, actor: int, staff: int, generation: int, origin: Vector2, heading: Vector2, source: Node, from_caster: bool) -> SpellRuntime.PendingLaunch:
	return _rt._delay(wait, group, spell, actor, staff, generation, origin, heading, source, from_caster)


# --- Live carriers (a `timer` or `on hurt` trigger on a carrier that lasts) -------------

## Lists a carrier of `tag` that lasts, when it has a `timer` or `on hurt` trigger: `kind`
## (`SpellRuntime.LC_SLOT` a shot, `LC_ROW` a row of this carrier, which `Carrier.tip_of` places,
## `LC_ACTOR` an actor's body, `LC_POINT` a point) and `ref` (with `seq`, the row's birth) say where
## it is; `tied` that it ends with that row, else it lives `life` seconds; `at` is where it starts
## and `way` its way.
func live_join(spell: CompiledSpell, tag: int, kind: int, ref: int, seq: int, tied: bool, life: float, at: Vector2, way: Vector2) -> void:
	_rt._lc_join(spell, tag, kind, ref, seq, tied, life, at, way)


## A live carrier of `tag` that is not tied to a row ended: one of its entries leaves, or with
## `every` all of them.
func live_leave(tag: int, every: bool) -> void:
	_rt._lc_leave(tag, every)


## The entity with `key` (`request_entity`'s) of `tag` ended: its entries leave, no other's.
func live_leave_key(tag: int, key: int) -> void:
	_rt._lc_leave_key(tag, key)


# --- Moves and entities ------------------------------------------------------------

## The moves of a caster or of the shot that cast a carrier (`CasterMoves`).
func moves() -> CasterMoves:
	return _rt._moves


## Asks `ai` for an entity of `kind` (`entity_spawn_requested`) under a new key, which
## `Spells.entity_key` holds while the request is sent (Entities keeps it and hands it back with
## `familiar_at`); Entities names the actor it made in `Spells.entity_body` (`entity_body`). Returns
## the key.
func request_entity(actor: int, kind: StringName, at: Vector2, seconds: float, tag: int, anchor: int) -> int:
	_rt._entity_keys += 1
	_rt.entity_key = _rt._entity_keys
	_rt.entity_body = -1
	_rt.events.entity_spawn_requested.emit(actor, kind, at, seconds, tag, anchor)
	_rt.entity_key = 0
	_entity_body = _rt.entity_body
	_rt.entity_body = -1
	return _rt._entity_keys


## The actor id of the body made for the last `request_entity` (a decoy), or -1 for none.
func entity_body() -> int:
	return _entity_body
