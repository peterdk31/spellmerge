class_name ModifierBase
extends SpellComponent
## A modifier (split, pierce, homing, chain, bigger, faster): changes the spell's numbers
## or adds a behaviour. A spell has up to three, and the same one may appear twice.
## Multipliers multiply the form's numbers and adds are added, in slot order.

## A behaviour beyond the numbers, run by the projectile manager or the spell runtime.
enum Behaviour {
	## Numbers only.
	NONE,
	## Shots turn toward the nearest target by `behaviour_strength` radians per second;
	## a ray aims at the nearest target near its aim instead (`core/projectiles`).
	HOMING,
	## A hit sends one new shot on to the nearest other target, `behaviour_strength`
	## times in all (`core/spells`).
	CHAIN,
	# Staffs (A3, docs/milestones/M2-staffs.md). `behaviour_strength` is what the comment says;
	# where it means nothing, set it to 1. Each is run by the kit named.
	## Blocks `behaviour_strength` hits (stacks); on the caster or a self carrier, a barrier (B1, B3).
	SHIELD,
	## Explodes at the carrier's end point, radius `behaviour_strength` pixels (B2, B3).
	BLAST,
	## Sustained: stays until switched off and reserves its mana (A5, B4).
	HOLD,
	## Pushes the caster back `behaviour_strength` pixels when cast (B2, B4).
	RECOIL,
	## Bounces off walls, `behaviour_strength` times (B1).
	BOUNCE,
	## Fires the carrier again `behaviour_strength` seconds later at half damage (B2).
	ECHO,
	## Stops mid-air for `behaviour_strength` seconds, then goes on (B1).
	LINGER,
	## Knockback times `behaviour_strength`; a knock into a wall hurts (B3).
	HEAVY,
	## Hits refund `behaviour_strength` mana each (B2, B4).
	SIPHON,
	## Sticks to the target it hits for `behaviour_strength` seconds, then expires there (B1).
	STICKY,
	## Pulls enemies within `behaviour_strength` pixels toward its path (B1, B3).
	MAGNET,
	## Passes through walls (B1).
	GHOST,
	## Flies in a sine wave `behaviour_strength` pixels wide (B1).
	SPIRAL,
	## Also fires the carrier backwards (B2).
	MIRROR,
	## Grows `behaviour_strength` times bigger per second of flight, up to `GROWTH_MAX` (B1): a
	## wider hit circle, the same damage (owner, 2026-10-27: size is the card; damage is overcharge's).
	GROWTH,
	## Takes on a teammate's infusions when it passes through them (B1, B2).
	RELAY,
	## Flies out for half its life, then back to its caster (owner, 2026-10-27: a modifier, not
	## a boomerang carrier). Only on a carrier that flies (`StaffCompiler.behaviour_runs`).
	RETURN,
	## Zaps the nearest enemy within `behaviour_reach` pixels `behaviour_strength` times a second
	## (arc cards add up) while the shot lives, at `SpellLimits.ARC_DAMAGE` of its damage with its infusions; a zap
	## is a hit, so it sets off `on hit` and chains (owner, 2026-10-27). Only on a carrier that
	## stays in the air as a shot.
	ARC,
}

@export var damage_mult: float = 1.0
@export var speed_mult: float = 1.0
@export var radius_mult: float = 1.0
@export var cooldown_mult: float = 1.0
@export var mana_mult: float = 1.0
## Factor on the number of shots per cast, spread in a fan (split). The compiled spell is
## clamped to the shot limit.
@export var shot_mult: int = 1
## Targets added to each shot's pierce.
@export var extra_pierce: int = 0
@export var behaviour: Behaviour = Behaviour.NONE
## Turn rate for HOMING, number of jumps for CHAIN; unused for NONE.
@export var behaviour_strength: float = 0.0
## Pixels the behaviour reaches. For HOMING, how far a shot looks for a target (one in flight
## looks again as it flies; a beam looks at least as far as it is long), on every form homing
## steers (`StaffCompiler.homing_range`). Unused by the others.
@export var behaviour_reach: float = 0.0

# --- Look (staffs B6a) ----------------------------------------------------------------

## The particles this card makes its shots give off: a LOOK_* kind of `core/projectiles` (0
## none, 1 embers, 2 frost flecks, 3 gusts, 4 pulled-in pixels, 5 sparks, 6 rising motes,
## 7 glints, 8 streaks and a longer core, 9 a burst, 10 orbiting sparks, 11 a weave of the
## body, 12 glitter). A shot gives off the kinds of all its infusions and modifiers, mixed at
## random from its tail; two cards with the same kind add nothing more.
@export var look_layer: int = 0

# --- Aim (staff spread) ---------------------------------------------------------------

## Factor on the staff's `spread` for the next carrier's shots: below 1 they leave truer
## (sniper), above 1 wilder. Several multiply. A staff with no spread aims true whatever it is.
@export var spread_mult: float = 1.0

# --- Life (slow) ----------------------------------------------------------------------

## Factor on the carrier's `lifetime`. With `speed_mult` it makes a slow shot that still goes as
## far (slow: speed x0.3, lifetime x3). Several multiply.
@export var lifetime_mult: float = 1.0


func kind() -> StringName:
	return &"modifier"


func ranges() -> Dictionary:
	var limits: Dictionary = super()
	limits.merge({
		"damage_mult": Vector2(0.1, 4.0),
		"speed_mult": Vector2(0.1, 4.0),
		"radius_mult": Vector2(0.25, 4.0),
		"cooldown_mult": Vector2(0.1, 4.0),
		"mana_mult": Vector2(0.1, 4.0),
		"shot_mult": Vector2(1, 8),
		"look_layer": Vector2(0.0, 12.0),
		"extra_pierce": Vector2(0, 8),
		"behaviour": Vector2(0, Behaviour.size() - 1),
		"behaviour_strength": Vector2(0.0, 256.0),
		"behaviour_reach": Vector2(0.0, 360.0),
		"spread_mult": Vector2(0.0, 4.0),
		"lifetime_mult": Vector2(0.1, 4.0),
	})
	return limits
