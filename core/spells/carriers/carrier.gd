class_name Carrier
extends RefCounted
## A carrier: what a form card fires (`FormBase.Motion`), and the one place that says what it does
## with every other card (docs/CARRIERS.md). Each motion has one subclass in this folder,
## found by `Carriers.of(motion)`; the compiler reads its tables, the spell runtime runs it.
##
## A subclass must answer for every card kind, with no default (tests/core/test_carriers.gd fails
## on a missing row):
## - `behaviours()`: one row per `ModifierBase.Behaviour`, `[Use, Look]` when it runs, with a
##   reason after `Look.NONE` unless `look_note()` gives one for the carrier, and
##   `[Use.WASTED, "why"]` when it does nothing (the reason a player reads after "Bounce does
##   nothing on a Decoy: "). `Use.WITH_BLAST` runs only when the carrier also has a blast.
## - `events()`: one per `TriggerBase.Event`, "" when the trigger can fire on it, else why it never
##   does. The compiler adds the checks that depend on the other cards (a block needs a shield).
## - `infusions()`: how it takes an element, `[Use, Look]` as a behaviour row.
## `traits()` says which numbers and shared rules apply to it (the flags below).

const B := ModifierBase.Behaviour
const E := TriggerBase.Event

## How a card runs on a carrier.
enum Use {
	## The shared path runs it: the shot kit (`Spells._apply_travel`), the hit path (`_on_hit`), the
	## cast path (`_fire_spell`: echo, mirror, recoil, hold) or the end point (blast).
	RUNS,
	## The carrier's own path runs it (its script, or a runtime service only it calls: a move, an
	## entity's guard), and the shared path leaves it alone.
	OWN,
	## It does nothing on this carrier; the card is listed as wasted with the reason.
	WASTED,
	## It runs only when the carrier also has a blast, whose area hit carries it.
	WITH_BLAST,
}

## How a card that runs shows on a carrier.
enum Look {
	## The carrier draws the card's `look_layer` (and an infusion's tint) on what it shows.
	SHOWN,
	## The card's cue plays (`ModifierBase.cue`: a blast's explosion, with the cast's tint and looks);
	## on a `WITH_BLAST` row, the blast's cue that carries it.
	CUE,
	## Nothing of the card shows on this carrier: the row or `look_note()` says why.
	NONE,
}

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


## The `FormBase.Motion` this carrier runs (-1 for the retired slot).
func motion() -> int:
	return -1


## Its plain name, as a player reads it ("beam").
func noun() -> String:
	return "retired carrier"


## What it is, for a wasted card's reason ("a beam is a line, not a shot").
func what() -> String:
	return "no card may use this carrier"


func traits() -> int:
	return 0


func behaviours() -> Dictionary:
	return {}


func events() -> Dictionary:
	return {}


func infusions() -> Array:
	return []


## Why it sets off no hit of its own, for a reason ("a decoy hits nothing").
func hits_nothing() -> String:
	return "it hits nothing"


## Why none of its cards' looks show, for its `Look.NONE` rows that give no reason of their own.
func look_note() -> String:
	return ""


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


## How `behaviour` runs on it (a `Use`); a row it lacks is wasted.
func use_of(behaviour: int) -> int:
	var row: Array = behaviours().get(behaviour, [])
	return row[0] if not row.is_empty() else Use.WASTED


## Why `behaviour` does nothing on it, or "" when it runs (with a blast on it, when `blasts`).
func waste(behaviour: int, blasts: bool = false) -> String:
	var row: Array = behaviours().get(behaviour, [])
	if row.is_empty():
		return what()
	match row[0]:
		Use.RUNS, Use.OWN:
			return ""
		Use.WITH_BLAST:
			return "" if blasts else str(row[2])
	return str(row[1])


## How `behaviour` shows on it (a `Look`), or -1 where it does not run.
func look_of(behaviour: int) -> int:
	var row: Array = behaviours().get(behaviour, [])
	return row[1] if row.size() > 1 and row[0] != Use.WASTED else -1


## Why `behaviour` does not show on it (a `Look.NONE` row), "" otherwise.
func look_reason(behaviour: int) -> String:
	var row: Array = behaviours().get(behaviour, [])
	if look_of(behaviour) != Look.NONE:
		return ""
	return str(row[2]) if row.size() > 2 else look_note()


## Why a trigger of `event` never fires on it, or "" when it can.
func event_waste(event: int) -> String:
	return str(events().get(event, what()))


## True when an infusion counts on it (with a blast on it, when `blasts`).
func takes_infusion(blasts: bool) -> bool:
	var row: Array = infusions()
	if row.is_empty():
		return false
	return row[0] == Use.RUNS or row[0] == Use.OWN or (row[0] == Use.WITH_BLAST and blasts)


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


## A move of this carrier ended at `at` (`Spells._move_end`), before its blast and `on expire`.
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


## How far a cast of `spell` reaches along its aim, for an enemy's telegraph (`Spells.next_cast_reach`);
## 0 for one that is not aimed.
func reach_of(_spell: CompiledSpell) -> float:
	return 0.0
