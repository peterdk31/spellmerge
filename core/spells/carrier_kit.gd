class_name CarrierKit
extends RefCounted
## What a carrier may ask of the spell runtime that runs it (docs/CARRIERS.md, "What a carrier
## runs"): the cast under way, the aim, the shared shot kit, the shared hit path and what a carrier
## leaves behind. A carrier (and the runtime's own helpers, `CasterMoves` and `StaffPoses`) uses
## only this, never the runtime's own members, so this file is the whole of what a new carrier
## needs to know about `Spells`. Each call is the runtime's one rule for it, shared by every carrier.
## The runtime's constants (`SpellRuntime.ACTORS`, `HITS`, `CASTER_WIZARD`, `CASTER_POINT`, the
## live carrier kinds `LC_*`) are read from `SpellRuntime` itself.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

var _rt: SpellRuntime = null


func _init(runtime: SpellRuntime) -> void:
	_rt = runtime


# --- The world -----------------------------------------------------------------

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


## Who casts the launch being fired: `SpellRuntime.CASTER_WIZARD` (the actor's body),
## `CASTER_POINT` (a point), or the slot of the shot that fired it (see `caster_seq`).
func caster() -> int:
	return _rt._caster


## The birth (`Projectiles.get_seq_of`) of the shot `caster` names, when it names one.
func caster_seq() -> int:
	return _rt._caster_seq


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
## dash it casts itself is turned by it.
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


## A shot spawned in `slot` (-1 when the manager refused it) takes its cards and its record and does
## not hit `source` for a while: 1 when it was made. What a carrier calls after `projectiles.spawn`.
func land_shot(slot: int, spell: CompiledSpell, tag: int, source: Node, chain: int, prev: int) -> int:
	return _rt._land_shot(slot, spell, tag, source, chain, prev)


## The two halves of `land_shot`, for a carrier that sets the shot up in between (a wall): the
## behaviours the projectile manager runs, then the shot's record (`chain` jumps left after `prev`).
func apply_travel(slot: int, spell: CompiledSpell) -> void:
	_rt._apply_travel(slot, spell)


func register(slot: int, tag: int, spell: CompiledSpell, chain: int, prev: int) -> void:
	_rt._register(slot, tag, spell, chain, prev)


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
		_rt.events.form_shown.emit(SpellTag.caster_of(tag), SpellRuntime.ZAP_FORM, at, way, length, spell.tint, spell.look)


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


## `spell` with `tag` strikes every body within `reach` of `at` at once, with `hit` (null: its own).
func strike_round(spell: CompiledSpell, tag: int, actor: int, at: Vector2, way: Vector2, reach: float, hit: HitProfile) -> void:
	_rt._strike_round(spell, tag, actor, at, way, reach, hit)


## Deflects (with `deflects`) or stops (while `charges` last) the `found` shots of
## `Projectiles.guard_slots` that touched a carrier of `actor` with `tag`: outward from `a` when `b`
## is INF, else off the segment from `a` to `b`. A block is sent as `form`'s (`block_shot`: a
## swing's is a parry). Returns the charges left.
func guard(found: int, actor: int, tag: int, deflects: bool, charges: int, a: Vector2, b: Vector2, form: StringName) -> int:
	return _rt._guard(found, actor, tag, deflects, charges, a, b, form)


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


## A trigger fires `group` from `at` along `heading`, cast by `caster` (`CASTER_POINT`,
## `CASTER_WIZARD` or a shot's slot), now or when this step's budget has room. Nothing is dropped.
func fire(group: CompiledGroup, actor: int, staff: int, generation: int, at: Vector2, heading: Vector2, source: Node, caster_slot: int) -> void:
	_rt._fire(group, actor, staff, generation, at, heading, source, caster_slot)


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


# --- Moves and entities ------------------------------------------------------------

## The moves of a caster or of the shot that cast a carrier (`CasterMoves`).
func moves() -> CasterMoves:
	return _rt._moves


## Asks `ai` for an entity of `kind` (`entity_spawn_requested`) under a new key, which
## `Spells.entity_key` holds while the request is sent (Entities keeps it and hands it back with
## `familiar_at`). Returns the key.
func request_entity(actor: int, kind: StringName, at: Vector2, seconds: float, tag: int, anchor: int) -> int:
	_rt._entity_keys += 1
	_rt.entity_key = _rt._entity_keys
	_rt.events.entity_spawn_requested.emit(actor, kind, at, seconds, tag, anchor)
	_rt.entity_key = 0
	return _rt._entity_keys
