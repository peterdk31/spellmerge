class_name SpellLimits
extends RefCounted
## The spell limits, which are also the performance limits (docs/milestones/M2-spell-system.md,
## "The spell limits are the performance limits"). Every number was a first guess that the
## stress benchmark (tests/benchmark/stress_runner.gd) confirms or lowers, so they live here
## and nowhere else. M2 part 25 checked them on the headless numbers (4 bots with heavy
## builds, 100 enemies and 1,000 shots, then 200 and 3,000: p95 13.9 and 15.4 ms, inside
## 16.7); nothing was lowered. The first web numbers led to a lower `WORK_PER_STEP`; the web
## stress frame is still unexplained (docs/DECISIONS.md).

## Complexity a whole spell may cost, counting the spell its trigger holds.
const MAX_COMPLEXITY: int = 12
## Shots one cast may make, after split, nova and `shot_mult` multiply. The compiler clamps.
const MAX_SHOTS: int = 24
## Modifiers in one spell.
const MAX_MODIFIERS: int = 3
## Levels a trigger may nest below the cast: the cast is depth 0, its held spell depth 1,
## that spell's held spell depth 2. Nothing sits at depth 3.
const MAX_DEPTH: int = 2
## Held spells all of one player's triggers may fire in one physics step; the rest are
## dropped, never queued (used by the spell runtime, M2 part 6).
const MAX_FIRES_PER_STEP: int = 32
## Chain jumps one player may make in one physics step; the rest are dropped.
const MAX_CHAINS_PER_STEP: int = 16
## Times a timer trigger fires one shot's held spell, whatever its `max_fires`.
const MAX_TIMER_FIRES: int = 4
## Reach in pixels of a chain's jump to the next target.
const CHAIN_RANGE: float = 96.0
## Degrees a split fan covers when the form has no spread of its own.
const SPLIT_SPREAD: float = 30.0
## Builds of one slot (the generations) whose shots can be in the air at once.
const GENERATIONS: int = 8
## Spell slots per player (A and B).
const SLOTS: int = 2
## Players, indexes 0 to 3.
const PLAYERS: int = 4

## Seconds a held spell's shots cannot hit the target that fired the trigger.
const SOURCE_EXCLUSION: float = 0.1
## Knockback of one hit in pixels per second (M1's fire bolt had 120).
const KNOCKBACK: float = 120.0
## Speed of a chain jump when the spell's own speed is lower (a rune or a beam has none).
const CHAIN_MIN_SPEED: float = 300.0
## Radians per second an orbit form turns when it gives no speed.
const ORBIT_TURN: float = 3.0
## Pixels a held spell fired when a shot expires starts back along its path, so a shot that
## ended on a wall fires in front of it.
const EXPIRE_BACKOFF: float = 2.0

## Clamps for the compiled numbers; they match the form's allowed ranges.
const MAX_SPEED: float = 2000.0
const MAX_RADIUS: float = 64.0
const MAX_PIERCE: int = 16
const MIN_COOLDOWN: float = 0.05
const MAX_DAMAGE: int = 999
## Timer triggers fire no faster than this (seconds) and no slower than the maximum.
const MIN_TIMER_INTERVAL: float = 0.1
const MAX_TIMER_INTERVAL: float = 10.0
## Jumps one hit's chain may make, however many chain modifiers add up.
const MAX_CHAIN_JUMPS: int = 6
## Seconds a shot may live; the form's allowed range.
const MIN_LIFETIME: float = 0.05
const MAX_LIFETIME: float = 20.0
