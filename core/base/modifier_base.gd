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
	## Grows `behaviour_strength` times bigger and stronger per second of flight (B1).
	GROWTH,
	## Takes on a teammate's infusions when it passes through them (B1, B2).
	RELAY,
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
		"extra_pierce": Vector2(0, 8),
		"behaviour": Vector2(0, Behaviour.size() - 1),
		"behaviour_strength": Vector2(0.0, 256.0),
	})
	return limits
