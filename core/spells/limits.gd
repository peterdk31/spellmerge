class_name SpellLimits
extends RefCounted
## The spell runtime's numbers. Since the staffs rework (docs/milestones/M2-staffs.md, "Engine
## safeguards") there are no build limits: no complexity budget, no cap on shots, modifiers or
## payload depth, no clamps on the compiled numbers, and no limit on what a card or a trigger
## does (owner, 2026-10-29: interactions are not limited, they follow the rules). What is left is
## engine pacing that spreads load over steps and never drops anything (the per-step fire pacing,
## the arc and magnet turns; the projectile pool lives in `core/projectiles`), room made at
## start that grows when needed, and tuning. If the stress benchmark
## (tests/benchmark/stress_runner.gd) or the emergent combo report shows a staff that freezes
## the game, a limit, a mana cost or a cheaper effect is decided then (owner, 2026-10-26).

const ActorsScript := preload("res://core/actors/actors.gd")

## Staffs (A4): the numbers of a fallback, the hit made when cards land on the caster or on a
## payload's origin with no carrier (docs/milestones/M2-staffs.md, "Reading a staff").
const FALLBACK_DAMAGE: float = 4.0
const FALLBACK_RADIUS: float = 8.0

## Engine pacing, never a limit (owner, 2026-10-29: interactions are not limited, they follow
## the rules): the shots the payloads of one budget's triggers (a seat's, or the shared one) may
## make in one physics step. A fire past it waits for the next step, oldest first, and nothing is
## dropped; one fire always goes in a fresh step, however many shots it makes. The window runs
## from one `Spells.step` to the next, so one frame (the manager's step, then the runtime's) can
## hold up to twice it. Measured with tests/benchmark/fire_cap.gd (docs/DECISIONS.md, 2026-10-29).
const FIRE_SHOTS_PER_STEP: int = 256
## Launches (a burst's later firings, echoes, fires waiting for their step) made ready at start;
## more are made when needed, none is dropped.
const PENDING_START: int = 128
## Damage of an echo's second firing, as a share of the carrier's.
const ECHO_DAMAGE: float = 0.5
## Reach in pixels of a chain's jump to the next target.
const CHAIN_RANGE: float = 96.0
## Share of its shot's damage an `arc` zap hits for (the shot's infusions come along).
const ARC_DAMAGE: float = 0.5
## Zaps all shots together may make in one physics step; more wait for the next.
const MAX_ARCS_PER_STEP: int = 32
## Magnet shots that may pull in one physics step; the others take turns.
const MAX_PULLS_PER_STEP: int = 16
## Pixels per second a `magnet` shot pulls the enemies near it toward itself.
const MAGNET_PULL: float = 200.0
## Degrees a split fan covers when the form has no spread of its own.
const SPLIT_SPREAD: float = 30.0
## Builds of one staff (the generations) whose shots can be in the air at once.
const GENERATIONS: int = 8
## Staffs per caster, one per button for a seat: A, X, Y and B.
const STAFFS: int = 4
## Pixels ahead of the caster that a rain falls when the form gives no `ray_length`, and that
## the middle of a wall is placed.
const RAIN_REACH: float = 120.0
const WALL_REACH: float = 28.0
## Seconds a shot made sustained by `hold` lives: until it is switched off, in practice.
const HOLD_LIFETIME: float = 100000.0
## Seconds the wizard takes to be pulled by a hook, to swap places, and to be pushed by a recoil
## (the player's move may stop early at a wall). A teleport is at once.
const HOOK_SECONDS: float = 0.15
const SWAP_SECONDS: float = 0.1
const RECOIL_SECONDS: float = 0.1
## The per-step fire and chain caps count per budget (`Actors.budget_of`): one for each seat's
## actor, and one that every actor no seat drives shares (`Actors.SHARED`), so a crowd of
## enemy casters shares one budget the size of one player's (actors G3b).
const BUDGETS: int = ActorsScript.SHARED + 1
## Live beam rows made at once (more are made when every one is on: no beam ends another,
## owner 2026-10-29), and the seconds between a live beam's hits. A beam lives its carrier's
## `lifetime`, so a held staff keeps one on.
const BEAM_ROWS_START: int = 64
const BEAM_TICK: float = 0.15
## A deflected shot flies this many times faster, again at every deflect, so a rally speeds up
## (melee I3; the owner's playground, 2026-10-29). Its pool and the hit pass's sweep of its whole
## path each step are the engine's limits; nothing caps the speed.
const DEFLECT_SPEEDUP: float = 1.7
## Slam rows made at once (more when every one is on), and the share of a slam's `lifetime` its
## ring takes to grow to its radius; it holds for the rest (the playground's 0.08 s of 0.12 s).
const SLAM_ROWS_START: int = 16
const SLAM_GROW: float = 0.67
## A homing carrier that is over at once (a beam, a teleport) has no time to turn, so it bends
## toward a target as far as its turn rate turns in this many seconds (the Homing card's 3
## radians a second bend it 43 degrees; more homing bends it further, all the way round).
const INSTANT_HOMING_SECONDS: float = 0.25
## Pixels per second a homing still shot (a rune) creeps toward its target (rules R4i): below the
## slowest walking enemy (30), so a rune that homes is a trap that follows, never a chaser one can
## not walk away from, and over a rune's 8 s it creeps about the Homing card's reach (160 px).
const HOMING_DRIFT: float = 24.0
## A homing teleport whose target is within its distance lands this far outside the target's
## hit circle (a wizard's body radius), not on it.
const LAND_CLEARANCE: float = 6.0
## Homing legs a live beam row has room for at first (it grows): a homing beam bends on to a new
## target after each hit, as many as its pierce gives (as a homing shot picks a new target after
## a hit).
const BEAM_LEGS_START: int = 8
## Each homing card after the first multiplies the turn rate (and an instant carrier's bend) by this.
const HOMING_STACK: float = 1.5
## Swing rows made at once (more are made when every one is on: no swing ends another).
const SWING_ROWS_START: int = 16
## A swing cast within this many seconds of the last one's sweep ending chains straight on: no
## wind-up, the other way round (melee I2; the playground's chain window).
const SWING_CHAIN: float = 0.25
## Degrees the staff leans back past the start of the arc before a sweep and swings on past its
## end; the sweep's ease runs over the whole turn, and only the arc itself hits.
const SWING_LEAN: float = 22.5
## Moves of shots whose end point is still to come (a dash whose caster is a shot) with room made
## at once; more is made when needed.
const SHOT_MOVES_START: int = 64

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
## Seconds the hit of a fallback lasts (it is an instant area hit; the shot fields need a value).
const MIN_LIFETIME: float = 0.05
