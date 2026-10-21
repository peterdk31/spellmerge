class_name SpellLimits
extends RefCounted
## The spell limits, which are also the performance limits (docs/milestones/M2-spell-system.md,
## "The spell limits are the performance limits"). Every number is a first guess that the
## stress benchmark (M2 part 25) confirms or lowers, so they live here and nowhere else.

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
