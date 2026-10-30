class_name Carrier
extends RefCounted
## A carrier: what a form card fires (`FormBase.carrier`), and the one place that says what it does
## with every other card (docs/CARRIERS.md). Each carrier is one subclass in this folder, found by
## its id (`Carriers.of(&"beam")`); the compiler reads its tables, the spell runtime runs it.
##
## A subclass answers yes/no questions about itself in `traits()` (the flags below: does it fly?
## does it hit? does it last? ...), and from those alone the compiler works out which cards do
## nothing on it, and why (`waste`, `event_waste`): each card says what it needs from a carrier
## (`NEEDS`, `EVENT_NEEDS`), once for every carrier. A new carrier writes no list of cards.
## tests/core/test_card_rules.gd plays every card on every carrier and fails where the answer is
## wrong (a card that does nothing but is not said to, or the other way round).

const B := ModifierBase.Behaviour
const E := TriggerBase.Event

## The modifier behaviours a blast's area hit carries on a carrier that hits nothing itself (heavy's
## knockback and slam ride on it), so what they need (`NEEDS`) stands only without a blast.
const BLAST_CARRIES: Array[int] = [B.HEAVY]

## `traits()` flags.
## A shot flying out on its own: `reach` stretches its life, `return` brings it back.
const FLIES: int = 1 << 0
## A shot that stays in the world a while: arc, magnet and relay ride on it.
const STAYS: int = 1 << 1
## It hits under its own tag: hit cards, infusions and `on hit` work on it.
const HITS: int = 1 << 2
## It lasts a while: timers tick and `on hurt` listens while it lives.
const LASTS: int = 1 << 3
## It goes a distance `reach` stretches (its flight or its `ray_length`).
const REACHES: int = 1 << 4
## Its shield stops only the shots that touch it, so a deflect on it outruns a shield.
const GUARDS: int = 1 << 5
## Homing can steer it (turn it, bend it or place it on a target).
const STEERS: int = 1 << 6
## It uses `speed` and `lifetime` (all but a teleport, which is over at once).
const SPEED: int = 1 << 7
## It fires `shots` (a split makes more).
const SHOTS: int = 1 << 8
## Its shots leave along a fan or a line that `spread` widens.
const SPREAD: int = 1 << 9
## Its hits spend `pierce`.
const PIERCE: int = 1 << 10
## Its shots spread round a circle instead of a fan.
const RING: int = 1 << 11
## A payload its shot fires goes outward from the shot's caster, not along the shot's way.
const OUTWARD: int = 1 << 12
## Held, it is cast anew each time it is over (a rain falls again, a swing sweeps back).
const REPEATS_HELD: int = 1 << 13
## It plays its own staff animation with its wind-up and strike.
const OWN_POSE: int = 1 << 14
## It is over at once, so a homing one looks at least as far as it goes.
const INSTANT_HOMING: int = 1 << 15
## It reads a payload of its own after it, as a trigger does (a rain).
const CARRIES_PAYLOAD: int = 1 << 16
## The staff keeps working through its `lifetime` (a beam, a rain, a dash): its staff animation's
## strike lasts that long.
const HOLDS_STAFF: int = 1 << 17
## Does it travel along a path through the world (a bolt, a hook, a swap, an orbit)? Linger, sticky
## and spiral change that path.
const MOVES: int = 1 << 18
## Is it a line that is there at once (a beam)? It turns at walls, waves, grows and pulls as a line.
const LINE: int = 1 << 19
## Can it stop or turn other shots (its shot, line, sweep or body touches them, or it moves its
## caster, whom its shield then guards)? Shield, deflect and `on block` need it.
const MEETS_SHOTS: int = 1 << 20
## Does it move its caster (a dash, a teleport)? A mirror would cancel it, and nothing keeps it on.
const MOVES_CASTER: int = 1 << 21

## What each modifier behaviour needs from a carrier to do anything, and the words the builder shows
## when it gets none of it ("<Card> does nothing on a <carrier>: <why_not>, and <what()>"):
## "any": at least one of these flags; "not": none of these. A behaviour not here works on every
## carrier (numbers, blast, echo, recoil). A new behaviour adds its line here, never per carrier.
const NEEDS: Dictionary = {
	B.HOMING: {"any": STEERS, "why_not": "it has nothing to aim"},
	B.CHAIN: {"any": HITS, "why_not": "it acts on what the carrier hits"},
	B.SIPHON: {"any": HITS, "why_not": "it acts on what the carrier hits"},
	B.POSSESS: {"any": HITS, "why_not": "it acts on what the carrier hits"},
	B.HEAVY: {"any": HITS, "why_not": "it acts on what the carrier hits (a blast would carry it)"},
	B.RELAY: {"any": HITS, "why_not": "it needs a hit of its own"},
	B.SHIELD: {"any": MEETS_SHOTS, "why_not": "it blocks shots that touch the carrier or guards the caster on a move"},
	B.DEFLECT: {"any": MEETS_SHOTS, "why_not": "it touches no shots"},
	B.HOLD: {"any": LASTS, "not": MOVES_CASTER, "why_not": "nothing keeps it on"},
	B.MIRROR: {"not": MOVES_CASTER, "why_not": "a move and its mirror cancel"},
	B.BOUNCE: {"any": FLIES | LINE, "why_not": "it turns a shot or a beam at walls"},
	B.GHOST: {"any": FLIES | LINE, "why_not": "it only takes a flying shot or a line through walls"},
	B.RETURN: {"any": FLIES, "why_not": "it does not fly out"},
	B.LINGER: {"any": MOVES, "why_not": "it only changes a moving shot"},
	B.STICKY: {"any": MOVES, "why_not": "it only changes a moving shot"},
	B.SPIRAL: {"any": MOVES | LINE, "why_not": "it only changes a moving shot or a beam"},
	B.GROWTH: {"any": STAYS | LINE, "why_not": "it grows a shot in the world or a beam"},
	B.MAGNET: {"any": STAYS | LINE, "why_not": "it needs a shot or a beam that stays in the world"},
	B.ARC: {"any": STAYS, "why_not": "it is not a shot that stays in the air"},
}

## The same for each trigger: what the carrier needs for it ever to go off.
const EVENT_NEEDS: Dictionary = {
	E.HIT: {"any": HITS, "why_not": "it hits nothing"},
	E.TIMER: {"any": LASTS, "why_not": "it is over at once"},
	E.HURT: {"any": LASTS, "why_not": "it is over at once"},
	E.BLOCK: {"any": MEETS_SHOTS, "why_not": "nothing on it can block a shot"},
	E.WALL: {"any": FLIES | LINE, "why_not": "it never meets a wall"},
}


## Its id, the `carrier` a form card names (&"bolt"); &"" for the carrier that runs nothing, which
## `Carriers.of` answers for a name no carrier has.
func id() -> StringName:
	return &""


## Its plain name, as a player reads it ("beam").
func noun() -> String:
	return "nothing"


## What it is, for a wasted card's reason ("a beam is a line, not a shot").
func what() -> String:
	return "no carrier has that name"


func traits() -> int:
	return 0



## Why it sets off no hit of its own, for a reason ("a decoy hits nothing").
func hits_nothing() -> String:
	return "it hits nothing"


## The fields a form card of this carrier must set above 0, with the fix the validator gives
## (`SpellValidator`): {"speed": "A bolt needs a `speed` above 0."}.
func required_fields() -> Dictionary:
	return {}


## The kind of its hits (`HitProfile.kind`), &"" for a shot's own.
func hit_kind() -> StringName:
	return &""


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


## Why `behaviour` does nothing on it, or "" when it does something (with a blast on it, when
## `blasts`): worked out from `NEEDS` and its traits. The carrier that runs nothing (id &"") says so
## for every card.
func waste(behaviour: int, blasts: bool = false) -> String:
	if id() == &"":
		return what()
	if blasts and BLAST_CARRIES.has(behaviour):
		return ""
	return _lacks(NEEDS.get(behaviour, {}))


## Why a trigger of `event` never fires on it, or "" when it can: from `EVENT_NEEDS`.
func event_waste(event: int) -> String:
	if id() == &"":
		return what()
	if event == E.HIT and not hits():
		return hits_nothing()
	return _lacks(EVENT_NEEDS.get(event, {}), false)


## The sentence of a need (a `NEEDS` row) its traits do not meet, else "": its "why_not", and what
## the carrier is when `say_what`.
func _lacks(need: Dictionary, say_what: bool = true) -> String:
	if need.is_empty():
		return ""
	var any: int = int(need.get("any", 0))
	if (any == 0 or traits() & any != 0) and traits() & int(need.get("not", 0)) == 0:
		return ""
	return "%s, and %s" % [need["why_not"], what()] if say_what else str(need["why_not"])


## True when an infusion counts on it: it hits, or a blast on it carries the infusion.
func takes_infusion(blasts: bool) -> bool:
	return hits() or blasts


## True when it takes `recoil` off its own move (a teleport), so the cast's push leaves it alone.
func handles_recoil() -> bool:
	return false


## How far a homing one looks for its target, from its `ray_length` and its homing cards' `reach`
## (`StaffCompiler.homing_range`); 0 where homing cannot steer it.
func homing_range(ray_length: float, reach: float) -> float:
	if not steers():
		return 0.0
	return maxf(reach, ray_length) if has(INSTANT_HOMING) else reach


# The runtime side. The compiler's carriers (`Carriers.of`) are never bound; the spell runtime
# makes its own (`Carriers.make_all`) and binds them, and each runs what it fires. A carrier asks
# the runtime for the shared path (the shot kit, the hit path, moves, entities) through `rt`.

## The runtime that casts this carrier (null for the compiler's, which only reads the tables).
var rt: SpellRuntime = null


## Binds this carrier to `runtime`, which casts it, and the staff animations its casts play. A
## carrier with rows of its own makes them here.
func bind(runtime: SpellRuntime, _staff_poses: StaffPoses) -> void:
	rt = runtime


## One launch of `spell` from `origin` along `direction` (`Spells._launch`): how many shots, rows or
## moves it made (0 when none could start). `lifetime` is the carrier's (a held one's is longer),
## `chain` the jumps its hits carry and `prev` the target they jump from. By default `spell.shots`
## leave in a fan (or round a ring), each made by `shoot`.
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, source: Node, lifetime: float, chain: int, prev: int) -> int:
	var made: int = 0
	var count: int = spell.shots
	for n in count:
		var angle: float = direction.angle() + rt._fan_angle(n, count, spell) + rt._staff_spread(tag, spell)
		made += shoot(spell, tag, actor, origin, direction, Vector2.from_angle(angle), n, count, source, lifetime, chain, prev)
	return made


## Shot `n` of `count` of one launch, along `heading` (`direction` is the launch's aim): 1 when it
## was made. By default a shot flying along `heading`.
func shoot(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, source: Node, lifetime: float, chain: int, prev: int) -> int:
	var slot: int = rt.projectiles.spawn(actor, origin, heading * spell.speed, lifetime, spell.radius, SpellRuntime.HITS, spell.pierce, tag)
	return rt._land_shot(slot, spell, tag, source, chain, prev)


## What a hit of this carrier does of its own, besides the shared hit path (`Spells._on_hit_effects`):
## a hook's pull, a swap's trade. True when it moves what cast it, so its blast waits for the arrival.
func on_hit(_spell: CompiledSpell, _tag: int, _actor: int, _target: Node, _position: Vector2, _slot: int) -> bool:
	return false


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


## A held (`hold`) carrier of `tag` is switched off (its staff cast again or edited): what is still
## on ends. Its shots in the manager are removed by the runtime.
func switch_off(_tag: int) -> void:
	pass


## How far a cast of `spell` reaches along its aim, for an enemy's telegraph (`Spells.next_cast_reach`);
## 0 for one that is not aimed.
func reach_of(_spell: CompiledSpell) -> float:
	return 0.0
