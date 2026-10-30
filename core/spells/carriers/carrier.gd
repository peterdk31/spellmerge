class_name Carrier
extends RefCounted
## A carrier: what a form card fires (`FormBase.carrier`), and the one place that says what it does
## with every other card (docs/CARRIERS.md). Each carrier is one subclass in this folder, found by
## its id (`Carriers.of(&"beam")`); the compiler reads its tables, the spell runtime runs it.
##
## A subclass must answer for every card kind, with no default (tests/core/test_carriers.gd fails
## on a missing row). Each row is a small dictionary whose keys say what its values answer:
## - `behaviours()`: one row per `ModifierBase.Behaviour` (a modifier card's effect):
##   - "works": does the card work on this carrier? A `Works` value.
##   - "shows": if it works, how does it look? A `Shows` value.
##   - "why_not": if it does not work (or only with a blast), why, as a player reads it after
##     "Bounce does nothing on a Decoy: ".
##   - "why_nothing_shows": if it shows nothing, why.
##   `{"works": Works.YES, "shows": Shows.DRAWN}`,
##   `{"works": Works.NO, "why_not": "it does not fly out"}`.
## - `events()`: one per `TriggerBase.Event` (a trigger card): "fires" (does it ever go off on this
##   carrier?) and, when it never does, "why_not". The compiler adds the checks that depend on the
##   other cards (a block needs a shield).
## - `infusions()`: an element card on this carrier, with a behaviour row's keys.
## `traits()` says which numbers and shared rules apply to it (the flags below).

const B := ModifierBase.Behaviour
const E := TriggerBase.Event

## Does the card work on this carrier?
enum Works {
	## Yes, the usual way, by the code every carrier shares: the shot kit (`Spells._apply_travel`),
	## the hit path (`_on_hit`), the cast path (`_fire_spell`: echo, mirror, recoil, hold) or the
	## end point (blast).
	YES,
	## Yes, done by this carrier's own code (its script, or a runtime service only it calls), and the
	## shared code leaves it alone: a beam bends, bounces and waves along its line.
	OWN_WAY,
	## No: the card does nothing here and is listed as wasted, with the reason.
	NO,
	## Only when the carrier also has a blast, whose area hit carries the card (heavy on a decoy).
	ONLY_WITH_BLAST,
}

## How a card that works shows on this carrier.
enum Shows {
	## Its look (`look_layer`, an infusion's tint) is drawn on what the carrier shows.
	DRAWN,
	## As its own effect (`ModifierBase.cue`: a blast's explosion, in the cast's tint and looks); on an
	## `ONLY_WITH_BLAST` row, as the effect of the blast that carries it.
	AS_EFFECT,
	## Nothing of it shows on this carrier; the row's "why_nothing_shows" says why.
	NOTHING,
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
## It reads a payload of its own after it, as a trigger does (a rain).
const CARRIES_PAYLOAD: int = 1 << 16
## The staff keeps working through its `lifetime` (a beam, a rain, a dash): its staff animation's
## strike lasts that long.
const HOLDS_STAFF: int = 1 << 17


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


func behaviours() -> Dictionary:
	return {}


func events() -> Dictionary:
	return {}


func infusions() -> Dictionary:
	return {}


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


## Whether `behaviour` works on it (a `Works`); a row it lacks is `Works.NO`.
func works(behaviour: int) -> int:
	return int(behaviours().get(behaviour, {}).get("works", Works.NO))


## Why `behaviour` does nothing on it, or "" when it works (with a blast on it, when `blasts`).
func waste(behaviour: int, blasts: bool = false) -> String:
	var row: Dictionary = behaviours().get(behaviour, {})
	if row.is_empty():
		return what()
	match int(row["works"]):
		Works.YES, Works.OWN_WAY:
			return ""
		Works.ONLY_WITH_BLAST:
			return "" if blasts else str(row["why_not"])
	return str(row["why_not"])


## How `behaviour` shows on it (a `Shows`), or -1 where it does not work.
func shows(behaviour: int) -> int:
	return int(behaviours().get(behaviour, {}).get("shows", -1))


## Why `behaviour` shows nothing on it (a `Shows.NOTHING` row), "" otherwise.
func why_nothing_shows(behaviour: int) -> String:
	return str(behaviours().get(behaviour, {}).get("why_nothing_shows", ""))


## Why a trigger of `event` never fires on it, or "" when it can.
func event_waste(event: int) -> String:
	var row: Dictionary = events().get(event, {})
	if row.is_empty():
		return what()
	return "" if bool(row["fires"]) else str(row["why_not"])


## True when an infusion counts on it (with a blast on it, when `blasts`).
func takes_infusion(blasts: bool) -> bool:
	var works_here: int = int(infusions().get("works", Works.NO))
	return works_here == Works.YES or works_here == Works.OWN_WAY or (works_here == Works.ONLY_WITH_BLAST and blasts)


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
