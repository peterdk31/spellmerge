class_name Carrier
extends RefCounted
## A carrier: what a form card fires (`FormBase.carrier`), and the one place that says what it does
## with every other card (docs/CARRIERS.md). Each carrier is one subclass in this folder, found by
## its id (`Carriers.of(&"beam")`); the compiler asks it, the spell runtime runs it.
##
## A subclass answers yes/no questions about itself in `traits()` (the flags below: does it fly?
## does it hit? does it last? ...), and from those alone the compiler works out which cards do
## something on it (`works`, `fires`): each card says what it needs from a carrier
## (`ModifierBase.NEEDS`, `TriggerBase.NEEDS`), once for every carrier. A new carrier writes no
## list of cards.
## tests/core/test_card_rules.gd plays every card on every carrier and fails where the answer is
## wrong (a card that does nothing but is not said to, or the other way round).

const B := ModifierBase.Behaviour
const E := TriggerBase.Event

## The modifier behaviours a blast's area hit carries on a carrier that hits nothing itself (heavy's
## knockback and slam ride on it), so what they need (`ModifierBase.NEEDS`) stands only without a blast.
const BLAST_CARRIES: Array[int] = [B.HEAVY]

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


## Its id, the `carrier` a form card names (&"bolt"); &"" for the carrier that runs nothing, which
## `Carriers.of` answers for a name no carrier has.
func id() -> StringName:
	return &""


func traits() -> int:
	return 0



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


## True when `behaviour` does something on it (with a blast on it, when `blasts`): its traits meet
## what the behaviour needs (`ModifierBase.NEEDS`). The carrier that runs nothing (id &"") runs no card.
func works(behaviour: int, blasts: bool = false) -> bool:
	if id() == &"":
		return false
	if blasts and BLAST_CARRIES.has(behaviour):
		return true
	return _meets(ModifierBase.NEEDS.get(behaviour, {}))


## True when a trigger of `event` can ever go off on it: its traits meet what the trigger needs
## (`TriggerBase.NEEDS`).
func fires(event: int) -> bool:
	return id() != &"" and _meets(TriggerBase.NEEDS.get(event, {}))


## True when its traits meet `need` (a `NEEDS` row; empty: always).
func _meets(need: Dictionary) -> bool:
	var any: int = int(need.get("any", 0))
	return (any == 0 or traits() & any != 0) and traits() & int(need.get("not", 0)) == 0


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
