class_name Sim
extends RefCounted
## The simulation's time and chance (online-ready N3c, docs/milestones/online-ready.md): the tick
## and the run's seed, and every roll the game makes. The Tick owns the game's (`Tick.sim`); an
## area or a body takes it the way it takes `combat` (a member `sim`, DERIVED, set by whoever makes
## it, else found: `Sim.found(node)`), so a test hands its own.
##
## **Chance by hash.** A roll is a hash of the run's seed and what the caller names it by: a
## purpose (`&"scatter"`), a key (whose roll: a cast, a seat, an actor) and a counter (which of its
## rolls). No generator holds state, so a new roll in one system never shifts another's, and
## nothing about chance needs saving beyond the counters the callers keep as state. The same
## name gives the same roll, so a caller never rolls twice by one name: it counts its rolls.
##
##     var turn: float = sim.chance(&"scatter", cast_key, _scatter_rolls) * TAU
##     _scatter_rolls += 1
##
## The tick is not in the hash: a roll is the same whenever it is made, so a test that steps an
## area by hand rolls as the game does. A caller that rolls once a tick names the tick itself
## (`sim.tick` as its counter).
##
## The hash is the engine's of a `Vector4i` (murmur3 of four 32-bit words, then its final mix):
## integer code, the same on every platform (online-ready N2b). Key and counter are taken as 32
## bits each.

## 2^32: a 32-bit roll into [0, 1).
const SPAN: float = 4294967296.0

## The run's seed: 0 until a run starts (`Tick.begin_run` deals one, `SimSeed.fresh`), so a test
## that starts none rolls the same every time.
var run_seed: int = 0
## Ticks since the run began: the game's clock, counted by the Tick after each tick (`Tick.count`
## reads it), so during a tick it is the number of that tick.
var tick: int = 0
## What the run plays by (core/sim/session_rules.gd, online-ready N11): set at the run's start
## (`Tick.begin_run`), from a replay's header while one plays, else from this machine's settings.
var rules: SessionRules = SessionRules.defaults()
## Ticks the whole simulation still stands still (online-ready N4: the game-wide stop of a downed
## wizard or a boss's death, `hold`). Nothing steps then but the input frames; the drawing runs on.
var hold_left: int = 0
## Why the game stands stopped, one reason each (`stop`): the pause menu, and any
## other stop an area makes. Stopped while any is here; the drawing stops too (the Tick pauses the tree).
var stops: Array[StringName] = []

const TickScript := preload("res://core/sim/tick.gd")

## What `found` gives a node out of the tree: a sim at seed 0, shared.
static var _still: Sim = null


## A sim whose run's seed is `value` (a test's).
static func seeded(value: int) -> Sim:
	var made := Sim.new()
	made.run_seed = value
	return made


## The game's sim (the Tick's) for a node in the tree, else a shared one at seed 0.
static func found(node: Node) -> Sim:
	var clock: TickScript = TickScript.of(node) as TickScript
	if clock != null and clock.sim != null:
		return clock.sim
	if _still == null:
		_still = Sim.new()
	return _still


## The whole simulation stands still for `ticks` ticks from the next one (a longer hold replaces a
## shorter one; overlapping holds do not add up).
func hold(ticks: int) -> void:
	hold_left = maxi(hold_left, ticks)


## The game stops for `reason` until `go(reason)`; stopping twice for one reason is once.
func stop(reason: StringName) -> void:
	if not stops.has(reason):
		stops.append(reason)


## `reason` no longer stops the game (the game goes on once no reason is left).
func go(reason: StringName) -> void:
	stops.erase(reason)


## True while some reason stops the game.
func is_stopped() -> bool:
	return not stops.is_empty()


## True while the game is stopped for `reason`.
func stopped_for(reason: StringName) -> bool:
	return stops.has(reason)


## True when the simulation does not step this tick: stopped, or held.
func stands_still() -> bool:
	return hold_left > 0 or not stops.is_empty()


## 32 random bits (0 to 2^32 - 1) named by `purpose`, `key` and `counter`.
func bits(purpose: StringName, key: int, counter: int) -> int:
	return hash(Vector4i(run_seed, (run_seed >> 32) ^ hash(purpose), key, counter))


## A roll in [0, 1).
func chance(purpose: StringName, key: int, counter: int) -> float:
	return float(bits(purpose, key, counter)) / SPAN


## A whole number from 0 to `below` - 1 (0 when `below` is 1 or less).
func chance_int(purpose: StringName, key: int, counter: int, below: int) -> int:
	if below <= 1:
		return 0
	return mini(floori(chance(purpose, key, counter) * float(below)), below - 1)


## A roll in [`from`, `to`).
func chance_range(purpose: StringName, key: int, counter: int, from: float, to: float) -> float:
	return from + (to - from) * chance(purpose, key, counter)
