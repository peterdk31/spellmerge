class_name Carrier
extends RefCounted
## A carrier: what a form card fires (`FormBase.carrier`), and the one place that says what it does
## with every other card (docs/CARRIERS.md). Each carrier is one subclass in this folder, found by
## its id (`Carriers.of(&"beam")`); the compiler asks it, the spell runtime runs it.
##
## A subclass answers yes/no questions about itself in `traits()` (the flags below: does it fly?
## does it hit? does it last? ...), and from those alone the compiler works out which cards do
## something on it (`works`, `fires`): each card says what it needs from a carrier
## (`ModifierBase.RULES` "needs", `TriggerBase.NEEDS`), once for every carrier. A new carrier writes no
## list of cards.
## tests/core/test_card_rules.gd plays every card on every carrier and fails where the answer is
## wrong (a card that does nothing but is not said to, or the other way round).

## The questions a carrier answers in `traits()` (`CarrierTraits`, where each is explained).
const FLIES: int = CarrierTraits.FLIES
const STAYS: int = CarrierTraits.STAYS
const HITS: int = CarrierTraits.HITS
const LASTS: int = CarrierTraits.LASTS
const REACHES: int = CarrierTraits.REACHES
const GUARDS: int = CarrierTraits.GUARDS
const STEERS: int = CarrierTraits.STEERS
const SPEED: int = CarrierTraits.SPEED
const SHOTS: int = CarrierTraits.SHOTS
const SPREAD: int = CarrierTraits.SPREAD
const PIERCE: int = CarrierTraits.PIERCE
const RING: int = CarrierTraits.RING
const OUTWARD: int = CarrierTraits.OUTWARD
const REPEATS_HELD: int = CarrierTraits.REPEATS_HELD
const OWN_POSE: int = CarrierTraits.OWN_POSE
const INSTANT_HOMING: int = CarrierTraits.INSTANT_HOMING
const CARRIES_PAYLOAD: int = CarrierTraits.CARRIES_PAYLOAD
const HOLDS_STAFF: int = CarrierTraits.HOLDS_STAFF
const MOVES: int = CarrierTraits.MOVES
const LINE: int = CarrierTraits.LINE
const MEETS_SHOTS: int = CarrierTraits.MEETS_SHOTS
const MOVES_CASTER: int = CarrierTraits.MOVES_CASTER
const STRIKES_POINT: int = CarrierTraits.STRIKES_POINT
const BLOCKS: int = CarrierTraits.BLOCKS
const SPAWNS: int = CarrierTraits.SPAWNS
const GATES: int = CarrierTraits.GATES
const CASTS_FROM_SHOT: int = CarrierTraits.CASTS_FROM_SHOT
const CASTS_FROM_BODY: int = CarrierTraits.CASTS_FROM_BODY
const CASTERLESS: int = CarrierTraits.CASTERLESS
const MELEE: int = CarrierTraits.MELEE

## Who may cast a group (`payload_cast_by`, `StaffCompiler`), as bits: an actor's body (the
## caster's own, or a body of its own carrier's: a decoy), a live shot, a point.
const BY_BODY: int = 1
const BY_SHOT: int = 2
const BY_POINT: int = 4
## What draws its look (`look_drawer`), and so which area a card's `look_shader` (and light) is
## for (docs/milestones/card-looks.md): the projectile manager's head batches (LOOK_SHOT: a shot
## that flies or orbits), its quad batches (LOOK_STILL: a still shot), Feel's beams (LOOK_BEAM),
## Feel's swing trails (LOOK_SWING), Entities' familiar orbs (LOOK_ORB), or nothing of its own
## (LOOK_NONE: cues only, or the caster's own look).
const LOOK_NONE: int = 0
const LOOK_SHOT: int = 1
const LOOK_STILL: int = 2
const LOOK_BEAM: int = 3
const LOOK_SWING: int = 4
const LOOK_ORB: int = 5


## Its id, the `carrier` a form card names (&"atom"); &"" for the carrier that runs nothing, which
## `Carriers.of` answers for a name no carrier has.
func id() -> StringName:
	return &""


func traits() -> int:
	return 0


## Where it runs among the carriers each step (`step`) and when they are ended or cleared: lower
## first, then by id. A dash strikes before beams, swings and slams hit (the order the runtime had
## before carriers had their own scripts); the others keep no rows that meet.
func step_order() -> int:
	return 0



## The fields a form card of this carrier must set above 0, with the fix the validator gives
## (`SpellValidator`): {"speed": "A bolt needs a `speed` above 0."}.
func required_fields() -> Dictionary:
	return {}


## True when a cast of it adds a wind-down of its own to its staff's (its form card's
## `wind_down`), so a card's wind-down factor changes something: every carrier a form card fires,
## not a fallback carrier (`CarrierFallback`), which has no form card. A payload's carrier adds
## none either; the compiler knows that one (`StaffCompiler._numbers_count`).
func has_wind_down() -> bool:
	return true


## Which way the staff turns for a cast of it by `actor` along `dir` (`StaffPoses.start`'s
## `side`), asked when the cast starts winding up, before it leaves (`Spells._wind_pose`).
func pose_side(_actor: int, dir: Vector2) -> int:
	return StaffPoses.up_side(dir)


## The kind of its hits (`HitProfile.kind`), &"" for a shot's own.
func hit_kind() -> StringName:
	return &""


## A carrier no form card fires (a fallback) has its own look here, where a form card would carry
## it: its staff animation (`FormBase.staff_pose`, packed) and the cue a seat's cast of it plays
## (`FormBase.cast_cue`; &"" for Feel's default). A form card's carrier answers none: its card says.
func staff_pose() -> PackedFloat32Array:
	return PackedFloat32Array()


func cast_cue() -> StringName:
	return &""


## What draws its look (LOOK_*): by default its shots, which fly (`spawn_row`).
func look_drawer() -> int:
	return LOOK_SHOT


func has(flag: int) -> bool:
	return traits() & flag != 0


func flies() -> bool:
	return has(FLIES)


func stays() -> bool:
	return has(STAYS)


func hits() -> bool:
	return has(HITS)


func lasts() -> bool:
	return has(LASTS)


func reaches() -> bool:
	return has(REACHES)


func guards() -> bool:
	return has(GUARDS)


func steers() -> bool:
	return has(STEERS)


## True when `behaviour` does something on it (with a blast on it, when `blasts`): its traits, or
## the blast, meet what the behaviour needs (`ModifierBase.needs`). The carrier that runs nothing
## (id &"") runs no card.
func works(behaviour: int, blasts: bool = false) -> bool:
	if id() == &"":
		return false
	var need: Dictionary = ModifierBase.needs(behaviour)
	return _meets(need) or (blasts and (need.get("or_cards", []) as Array).has(ModifierBase.Behaviour.BLAST))


## True when a trigger of `event` can ever go off on it, given the cards it needs: its traits meet
## what the trigger needs (`TriggerBase.NEEDS`), or a card can stand in for them.
func fires(event: int) -> bool:
	if id() == &"":
		return false
	var need: Dictionary = TriggerBase.NEEDS.get(event, {})
	return _meets(need) or not (need.get("or_cards", []) as Array).is_empty()


## True when a trigger of `event` goes off on it with the modifier behaviours in `has` (behaviour ->
## true) on it, and an infusion when `infused`: all that the trigger needs (`TriggerBase.NEEDS`).
func fires_with(event: int, has: Dictionary, infused: bool) -> bool:
	if id() == &"":
		return false
	var need: Dictionary = TriggerBase.NEEDS.get(event, {})
	if not _meets(need) and not _has_one(has, need.get("or_cards", [])):
		return false
	var cards: Array = need.get("cards", [])
	if not cards.is_empty() and not _has_one(has, cards) and not (infused and bool(need.get("or_infused", false))):
		return false
	for behaviour: int in need.get("not_cards", []):
		if has.has(behaviour) and works(behaviour):
			return false
	return true


## Who may cast the payload a trigger of `event` fires on this carrier, as `BY_*` bits, when the
## carrier (compiled as `spell`) is itself cast by `by` (`BY_*` bits; a cast's own group is cast by
## the caster's body): the compiler lands a payload's left-over cards on it (`Carriers.fallback`;
## docs/CARRIERS.md, "The fallback carriers"), so a card there is wasted only when none of them
## could use it. Worked out from its yes/no answers, the same for every carrier, as the runtime
## fires each event:
## - `on cast` leaves at once, cast by whoever cast the carrier (`by`).
## - `timer`, `on hurt` and `on recast` fire from where the carrier is while it lasts: its own shot
##   (`CASTS_FROM_SHOT`), its own body (`CASTS_FROM_BODY`) or what it moves (`MOVES_CASTER`: the
##   shot that cast it, else the wizard's body); a line, a strike or a spot is a point.
## - `on expire` fires where it ended: a move's end is what it moved; a shot that pulls ends where
##   what it pulled arrives (that caster); anything else is gone, a point.
## - `on hit`, `on kill` and `on reaction` fire from a shot that may fly on after its hit (it
##   pierces, sticks, or its hits never spend it: a wall), from what a move moves (its strikes are
##   that body's: a dash's pass, a teleport's landing; `hit_caster`), else from the point.
## - `on wall` fires from a shot that bounces on, else from the point.
## - `on block` fires from what its shield stopped the shot with: the shot, or the body its barrier
##   is on; a deflect's block is the turned shot's, from the point.
func payload_cast_by(event: int, spell: CompiledSpell, by: int) -> int:
	match event:
		TriggerBase.Event.CAST:
			return by
		TriggerBase.Event.TIMER, TriggerBase.Event.HURT, TriggerBase.Event.RECAST:
			var bearer: int = _bearer(by)
			return bearer if bearer != 0 else BY_POINT
		TriggerBase.Event.EXPIRE:
			if has(MOVES_CASTER):
				return _bearer(by)
			if has(CASTS_FROM_SHOT) and _with(spell, ModifierBase.Behaviour.PULL):
				# A pull whose hit spent the shot ends where its caster arrives (`CasterMoves.pull`).
				return _moved(by) | BY_POINT
			return BY_POINT
		TriggerBase.Event.HIT, TriggerBase.Event.KILL, TriggerBase.Event.REACTION:
			if has(MOVES_CASTER):
				return _moved(by) | BY_POINT
			var flies_on: bool = not has(PIERCE) or (spell != null and spell.pierce > 0) or _with(spell, ModifierBase.Behaviour.STICKY)
			return BY_SHOT | BY_POINT if has(CASTS_FROM_SHOT) and flies_on else BY_POINT
		TriggerBase.Event.WALL:
			return BY_SHOT | BY_POINT if has(CASTS_FROM_SHOT) and _with(spell, ModifierBase.Behaviour.BOUNCE) else BY_POINT
		TriggerBase.Event.BLOCK:
			if not _with(spell, ModifierBase.Behaviour.SHIELD):
				return BY_POINT
			if has(CASTS_FROM_SHOT):
				return BY_SHOT
			if has(CASTS_FROM_BODY):
				return BY_BODY
			if has(MOVES_CASTER) and by & (BY_BODY | BY_POINT) != 0:
				# Its shield is a barrier on the wizard's body it moves (`CasterMoves.shield`).
				return BY_BODY
	return BY_POINT


## Who casts the payload a hit of this carrier with no shot fires (a strike, a ray: `on hit`,
## `on kill`, `on reaction`), while `caster` (a value as `CarrierKit.caster`) casts the hit for a card
## of `actor`: the point it hit, by default; a carrier whose strikes are the body or shot it moves
## (a dash, a teleport: `CarrierMove`) says that one. The runtime's side of `payload_cast_by`.
func hit_caster(_caster: int, _actor: int) -> int:
	return SpellRuntime.CASTER_POINT


## True when `spell` has a card of `behaviour` on it.
static func _with(spell: CompiledSpell, behaviour: int) -> bool:
	return spell != null and spell.behaviour(behaviour) > 0.0


## What casts the payloads this carrier fires from where it is while it lasts, when it is cast by
## `by`: its own shot, its own body, or what it moves (`_moved`); 0 for none of them (a point).
func _bearer(by: int) -> int:
	if has(CASTS_FROM_BODY):
		return BY_BODY
	if has(CASTS_FROM_SHOT):
		return BY_SHOT
	if has(MOVES_CASTER):
		return _moved(by)
	return 0


## What a move of a caster cast by `by` moves: the shot that cast it (which may end before the move
## does: then the point), else the wizard's body (a point cannot move, so a move cast by one moves
## the wizard, rules R4c).
static func _moved(by: int) -> int:
	var moved: int = 0
	if by & BY_SHOT != 0:
		moved |= BY_SHOT | BY_POINT
	if by & (BY_BODY | BY_POINT) != 0:
		moved |= BY_BODY
	return moved


## True when its traits meet `need` (a needs row; empty: always).
func _meets(need: Dictionary) -> bool:
	var any: int = int(need.get("any", 0))
	return (any == 0 or traits() & any != 0) and traits() & int(need.get("not", 0)) == 0


## True when one of `behaviours` is in `has`.
static func _has_one(has: Dictionary, behaviours: Array) -> bool:
	for behaviour: int in behaviours:
		if has.has(behaviour):
			return true
	return false


## True when an infusion counts on it: it hits, or a blast on it carries the infusion.
func takes_infusion(blasts: bool) -> bool:
	return hits() or blasts


## True when the infusion `element` counts on it: by default when any infusion does
## (`takes_infusion`); a carrier that passes only an infusion's status on (a portal) says which.
func takes_element(_element: ElementBase, blasts: bool) -> bool:
	return takes_infusion(blasts)


## How far a homing one looks for its target, from its `ray_length` and its homing cards' `reach`
## (`CompiledSpell.homing_range`); 0 where homing cannot steer it.
func homing_range(ray_length: float, reach: float) -> float:
	if not steers():
		return 0.0
	return maxf(reach, ray_length) if has(INSTANT_HOMING) else reach


# The runtime side. The compiler's carriers (`Carriers.of`) are never bound; the spell runtime
# makes its own (`Carriers.make_all`) and binds them, and each runs what it fires. A carrier asks
# the runtime for everything else only through `kit` (`CarrierKit`: the cast under way, the aim,
# the shot kit, the hit path, payloads, moves, entities), never through the runtime itself.

## What it may ask of the runtime that casts it (null for the compiler's, which only reads the tables).
var kit: CarrierKit = null


## Binds this carrier to the runtime that casts it, through `runtime_kit`, and the staff animations
## its casts play. A carrier with rows of its own makes them here.
func bind(runtime_kit: CarrierKit, _staff_poses: StaffPoses) -> void:
	kit = runtime_kit


## The slots of a launch made together (`launch`), kept between launches.
var _slots: PackedInt32Array = PackedInt32Array()


## One launch of `spell` from `origin` along `direction` (`Spells._launch`): how many shots, rows or
## moves it made (0 when none could start). `lifetime` is the carrier's (a held one's is longer),
## `chain` the jumps its hits carry and `prev` the target they jump from. By default `spell.shots`
## leave in a fan (or round a ring), each made by `shoot`. The carrier that runs nothing (id &"")
## makes none: the runtime falls back to it, unbound, for a carrier id no carrier has.
##
## A carrier whose shot is one pool row and nothing more (`rows_only`: the atom's flying shots, the
## rune's still ones, the orbit's circling ones) makes them together when the pool has a free slot
## for each: every row first, in order (`spawn_rows`, the spread drawn per shot as before), then all
## of them set up in one `land_shots`, which reads what the launch's shots share once. The same
## shots and records as one at a time (test_spells_land_shots). With no room for each, a spawn may
## drop a shot, maybe one of the launch not yet set up, so they go one at a time.
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, source: Node, lifetime: float, chain: int, prev: int) -> int:
	if id() == &"":
		return 0
	var count: int = spell.shots
	if count >= 2 and rows_only() and kit.projectiles != null and kit.projectiles.has_room_for(count):
		if _slots.size() < count:
			_slots.resize(count)
		spawn_rows(spell, tag, actor, origin, direction, count, lifetime, _slots)
		return kit.land_shots(_slots, count, spell, tag, source, chain, prev)
	var made: int = 0
	for n in count:
		var angle: float = DMath.angle(direction) + kit.fan_angle(n, count, spell) + kit.staff_spread(tag, spell)
		made += shoot(spell, tag, actor, origin, direction, DMath.from_angle(angle), n, count, source, lifetime, chain, prev)
	return made


## Shot `n` of `count` of one launch, along `heading` (`direction` is the launch's aim): 1 when it
## was made. By default its pool row (`spawn_row`), set up (`land_shot`).
func shoot(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, heading: Vector2, n: int, count: int, source: Node, lifetime: float, chain: int, prev: int) -> int:
	if id() == &"":
		return 0
	var slot: int = spawn_row(spell, tag, actor, origin, direction, heading, n, count, lifetime)
	return kit.land_shot(slot, spell, tag, source, chain, prev)


## The pool row of shot `n` of `count` (see `shoot`): its slot, or -1 when the manager refused it.
## By default a shot flying along `heading`.
func spawn_row(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, lifetime: float) -> int:
	return kit.projectiles.spawn(actor, origin, heading * spell.speed, lifetime, spell.radius, SpellRuntime.HITS, spell.pierce, tag)


## The rows of a launch of `count` shots made together (`launch`), their slots written to `slots`
## (-1 for one refused): by default `spawn_row` for each, along its heading in the fan, in order
## (the spread drawn per shot, as one at a time). A carrier may make them faster, the same rows.
func spawn_rows(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, count: int, lifetime: float, slots: PackedInt32Array) -> void:
	for n in count:
		var angle: float = DMath.angle(direction) + kit.fan_angle(n, count, spell) + kit.staff_spread(tag, spell)
		slots[n] = spawn_row(spell, tag, actor, origin, direction, DMath.from_angle(angle), n, count, lifetime)


## True when this carrier's `shoot` is its `spawn_row` set up by `land_shot` and nothing else, so a
## launch may make its rows together (`launch`). False for a carrier whose `shoot` does more (a
## beam, a swing, a slam, a body of its own): it goes one at a time.
func rows_only() -> bool:
	return false


# --- Its end: when it is going ------------------------------------------------------

## The share of its life (0 to 1), at its end, over which it dissolves: its looks fade out
## (`fade_left`) and it does nothing more of its own accord (`active_left`; owner, 2026-10-31: "a zap
## should not trigger if the carrier it triggers from is gone"). 0, the default, for a carrier that
## ends at once (a shot's core goes at its end). A beam's is SpellLimits.BEAM_FADE. A held one (its
## life SpellLimits.HOLD_LIFETIME) has no fade: switched off, it ends at once.
func fade() -> float:
	return 0.0


## Seconds a carrier of this kind with `life_left` of its `span` seconds to go may still act before it
## starts to dissolve (`fade`): what anything it times waits within (a won zap, ...). 0 or less: it
## is going, so a wait still running is dropped and nothing new starts.
func active_left(life_left: float, span: float) -> float:
	if span <= 0.0 or span >= SpellLimits.HOLD_LIFETIME:
		return life_left
	return life_left - fade() * span


## How whole a carrier of this kind with `life_left` of its `span` seconds to go looks, 1 to 0 over its
## `fade` (1 while it is not going): what its looks fade by.
func fade_left(life_left: float, span: float) -> float:
	var share: float = fade()
	if share <= 0.0 or span <= 0.0 or span >= SpellLimits.HOLD_LIFETIME:
		return 1.0
	return clampf(life_left / (share * span), 0.0, 1.0)


## What a hit of this carrier does of its own, besides the shared hit path (`Spells._on_hit_effects`):
## a swap's trade. Not for a blast's hits, which move nothing (rules R4 F2).
func on_hit(_spell: CompiledSpell, _tag: int, _actor: int, _target: Node, _position: Vector2, _slot: int) -> void:
	pass


## A move of this carrier ended at `at` (`CasterMoves.end`), before its blast and `on expire`.
func on_move_end(_spell: CompiledSpell, _tag: int, _actor: int, _at: Vector2, _heading: Vector2) -> void:
	pass


## Runs its rows on by `delta` (`Spells.step`).
func step(_delta: float) -> void:
	pass


## Ends its rows of `tag` quietly (a revoked build, a hold switched off).
func end_of(_tag: int) -> void:
	pass


## Ends its rows of `actor` quietly (its caster closed).
func end_actor(_actor: int) -> void:
	pass


## Every row of it gone at once, quietly (`Spells.clear`).
func clear() -> void:
	pass


## `actor`'s caster opened or closed under its id: what this carrier keeps per actor starts over.
func reset_actor(_actor: int) -> void:
	pass


## The body `old` was replaced by `new` for the same actor (`body_replaced`, the swarm's
## promotion): every row that keeps `old` as a node keeps `new` instead. A row that keeps it by key
## (a chain's last body, N5) needs nothing: the actor's key is the same.
func replace_body(_old: Node, _new: Node) -> void:
	pass


## For a carrier's `replace_body`: `new` for `old` in every row's list of bodies (`struck`, one
## Array per row; empty for none).
static func _replace_in_rows(old: Node, new: Node, struck: Array) -> void:
	for bodies: Array in struck:
		for n in bodies.size():
			var body: Variant = bodies[n]
			if is_instance_valid(body) and body == old:
				bodies[n] = new


## A held (`hold`) carrier of `tag` is switched off (its staff cast again or edited): what is still
## on ends. Its shots in the manager are removed by the runtime.
func switch_off(_tag: int) -> void:
	pass


## How many times one cast that lives `lifetime` seconds hits one target (a beam ticks): once.
func hits_per_target(_lifetime: float) -> int:
	return 1


## A carrier that reads a payload of its own (`CARRIES_PAYLOAD`, a rain) lands it when its waiting
## launch is due (`Spells._run_pending`): `group` falls at `point`.
func land(_spell: CompiledSpell, _group: CompiledGroup, _actor: int, _staff: int, _generation: int, _point: Vector2, _heading: Vector2, _echoed: bool = false) -> void:
	pass


## How far a cast of `spell` reaches along its aim, for an enemy's telegraph (`Spells.next_cast_reach`);
## 0 for one that is not aimed.
func reach_of(_spell: CompiledSpell) -> float:
	return 0.0


## Where a cast of `spell` aimed along `aim` (unit) strikes, as an offset from the caster's hand
## before walls (the runtime stops it at one): the point a staff animation's `land` keys put the
## staff's tip on (`StaffPoses`), and where the carrier's look should be drawn. `ray_length` along
## the aim for a carrier that `STRIKES_POINT` (a slam), INF for the others; a carrier that strikes
## off its aim gives its own.
func strike_point(spell: CompiledSpell, aim: Vector2) -> Vector2:
	return aim * spell.ray_length if has(STRIKES_POINT) else Vector2.INF


## Where its row `row` is now while it is the row born `born` (`CarrierKit.live_join` with
## `SpellRuntime.LC_ROW`: a live carrier's place, for its timer and `on hurt` payloads); INF once
## it has ended. Only a carrier with rows of its own (a beam, a swing) lists one.
func tip_of(_row: int, _born: int) -> Vector2:
	return Vector2.INF
