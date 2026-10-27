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
## Share of its shot's damage an `arc` zap hits for (the shot's infusions come along).
const ARC_DAMAGE: float = 0.5
## Fewest seconds between two zaps of one shot, whatever its card says.
const ARC_MIN_INTERVAL: float = 0.1
## Zaps all shots together may make in one physics step; more wait for the next.
const MAX_ARCS_PER_STEP: int = 32
## Degrees a split fan covers when the form has no spread of its own.
const SPLIT_SPREAD: float = 30.0
## Builds of one staff (the generations) whose shots can be in the air at once.
const GENERATIONS: int = 8
## Staffs per player, one per button: A, X, Y and B.
const STAFFS: int = 4
## Pixels ahead of the caster that a rain falls when the form gives no `ray_length`, and that
## the middle of a wall is placed.
const RAIN_REACH: float = 120.0
const WALL_REACH: float = 28.0
## Targets a fissure's line can hit (the line pierces them all up to this many; tuning).
const FISSURE_PIERCE: int = 16
## Seconds a shot made sustained by `hold` lives: until it is switched off, in practice.
const HOLD_LIFETIME: float = 100000.0
## Seconds the wizard takes to be pulled by a hook, to swap places, and to be pushed by a recoil
## (the player's move may stop early at a wall). A teleport is at once.
const HOOK_SECONDS: float = 0.15
const SWAP_SECONDS: float = 0.1
const RECOIL_SECONDS: float = 0.1
## Players, indexes 0 to 3.
const PLAYERS: int = 4
## Enemy casters (staffs F5, "Enemy staffs"): rows FIRST_ENEMY_CASTER to CASTERS - 1, one per
## enemy that casts a staff (`Spells.open_enemy_caster`); the same numbers as the projectile
## manager's and `SpellTag`'s enemy rows.
const FIRST_ENEMY_CASTER: int = PLAYERS
const ENEMY_CASTERS: int = 256
const CASTERS: int = FIRST_ENEMY_CASTER + ENEMY_CASTERS
## The per-step fire and chain caps count per player and once for all enemies together, so a
## crowd of casters shares one budget the size of one player's.
const BUDGETS: int = PLAYERS + 1
## Of the shared live beams and waiting launches (BEAMS, MAX_PENDING), the most enemies hold at
## once. Enemies never end a player's beam or take a player's launch slot.
const ENEMY_BEAMS: int = 16
const ENEMY_PENDING: int = 32
## Live beams at once over every player (one more ends the oldest), and the seconds between a
## live beam's hits. A beam lives its carrier's `lifetime`, so a held staff keeps one on.
const BEAMS: int = 64
const BEAM_TICK: float = 0.15
## A homing carrier that is over at once (a beam, a teleport) has no time to turn, so it bends
## toward a target as far as its turn rate turns in this many seconds (the Homing card's 3
## radians a second bend it 43 degrees), and at most INSTANT_HOMING_MAX degrees.
const INSTANT_HOMING_SECONDS: float = 0.25
const INSTANT_HOMING_MAX: float = 90.0
## A homing teleport whose target is within its distance lands this far outside the target's
## hit circle (a wizard's body radius), not on it.
const LAND_CLEARANCE: float = 6.0
## The most targets a homing beam bends on to, one after another: with pierce it hits one, then
## bends on toward another from there (as a homing shot picks a new target after a hit).
const BEAM_LEGS: int = 8
## Each homing card after the first multiplies the turn rate (and an instant carrier's bend) by this.
const HOMING_STACK: float = 1.5
## Moves of shots at once whose end point is still to come (a dash whose caster is a shot).
const SHOT_MOVES: int = 64

## Seconds a payload's shots cannot hit the target that fired the trigger.
const SOURCE_EXCLUSION: float = 0.1
## Knockback of one hit in pixels per second (M1's fire bolt had 120).
const KNOCKBACK: float = 120.0
## A heavy hit's knock into a wall hurts for this share of the hit's damage (at least 1).
const SLAM_SHARE: float = 1.0
## Share of a mend hit's strength that an enemy takes as damage.
const HEAL_ENEMY_SHARE: float = 0.1
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
