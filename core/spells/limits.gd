class_name SpellLimits
extends RefCounted
## The spell runtime's numbers. Since the staffs rework (docs/milestones/M2-staffs.md, "Engine
## safeguards") there are no build limits: no complexity budget, no cap on shots, modifiers or
## payload depth, no clamps on the compiled numbers. What is left are engine safeguards that
## keep one step from running away and never change a build (the per-step fire and chain caps;
## the projectile pool lives in `core/projectiles`), and tuning. If the stress benchmark
## (tests/benchmark/stress_runner.gd) or the emergent combo report shows a staff that freezes
## the game, a limit, a mana cost or a cheaper effect is decided then (owner, 2026-10-26).

## Staffs (A4): the numbers of a fallback, the hit made when cards land on the caster or on a
## payload's origin with no carrier (docs/milestones/M2-staffs.md, "Reading a staff").
const FALLBACK_DAMAGE: float = 4.0
const FALLBACK_RADIUS: float = 8.0

## Engine safeguard: payloads all of one player's triggers may fire in one physics step; the
## rest are dropped, never queued, so a cascade cannot snowball across frames.
const MAX_FIRES_PER_STEP: int = 32
## Engine safeguard: chain jumps one player may make in one physics step; the rest are dropped.
const MAX_CHAINS_PER_STEP: int = 16
## Engine safeguard: launches (a burst's later firings, echoes) that may wait at once; the rest
## are dropped.
const MAX_PENDING: int = 128
## Damage of an echo's second firing, as a share of the carrier's.
const ECHO_DAMAGE: float = 0.5
## Reach in pixels of a chain's jump to the next target.
const CHAIN_RANGE: float = 96.0
## Degrees a split fan covers when the form has no spread of its own.
const SPLIT_SPREAD: float = 30.0
## Builds of one staff (the generations) whose shots can be in the air at once.
const GENERATIONS: int = 8
## Staffs per player, one per button: A, X, Y and B.
const STAFFS: int = 4
## Degrees between the carriers of one multicast group, so two bolts cast together do not fly
## as one (tuning, not a limit).
const MULTICAST_SPREAD: float = 12.0
## Pixels ahead of the caster that a rain falls when the form gives no `ray_length`, and that
## the middle of a wall is placed.
const RAIN_REACH: float = 120.0
const WALL_REACH: float = 28.0
## Targets a fissure's line can hit (the line pierces them all up to this many; tuning).
const FISSURE_PIERCE: int = 16
## Seconds a shot made sustained by `hold` lives: until it is switched off, in practice.
const HOLD_LIFETIME: float = 100000.0
## Players, indexes 0 to 3.
const PLAYERS: int = 4

## Seconds a payload's shots cannot hit the target that fired the trigger.
const SOURCE_EXCLUSION: float = 0.1
## Knockback of one hit in pixels per second (M1's fire bolt had 120).
const KNOCKBACK: float = 120.0
## Speed of a chain jump when the spell's own speed is lower (a rune or a beam has none).
const CHAIN_MIN_SPEED: float = 300.0
## Radians per second an orbit form turns when it gives no speed.
const ORBIT_TURN: float = 3.0
## Pixels a payload fired when a shot expires starts back along its path, so a shot that
## ended on a wall fires in front of it.
const EXPIRE_BACKOFF: float = 2.0
## Timer triggers fire no faster than this (seconds): the validator's floor for `interval`.
const MIN_TIMER_INTERVAL: float = 0.1
## Seconds the hit of a fallback lasts (it is an instant area hit; the shot fields need a value).
const MIN_LIFETIME: float = 0.05
