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
	## Knockback times `behaviour_strength` (more cards multiply); a knock into a wall hurts (B3).
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
	## Grows `behaviour_strength` times bigger per second of flight (more cards multiply), up to the room's size (B1): a
	## wider hit circle, the same damage (owner, 2026-10-27: size is the card; damage is overcharge's).
	GROWTH,
	## Takes on the infusions of the last cast of any actor its shot hits (B2; owner, 2026-10-28).
	RELAY,
	## Flies out for half its life, then back to its caster (owner, 2026-10-27: a modifier, not
	## a boomerang carrier). Only on a carrier that flies (`ModifierBase.NEEDS`).
	RETURN,
	## Each enemy that comes within `behaviour_reach` pixels of the shot has a `behaviour_strength`
	## chance (0 to 1; 0.5 the card) to be zapped, once per shot, at a random moment while it is in
	## reach (SpellLimits.ZAP_WAIT_MOST), the one the shot is about to hit too, before it hits (zap cards combine as chances: two are 75%; with nothing near the shot
	## sparks into the air; SpellLimits.ZAP_*; owner, 2026-10-30), at `SpellLimits.ZAP_DAMAGE` of its damage with its infusions; a zap
	## is a hit, so it sets off `on hit` and chains (owner, 2026-10-27). Only on a carrier that
	## stays in the air as a shot.
	ZAP,
	## Every actor the carrier hits is possessed for `behaviour_strength` seconds (actors G9,
	## `possess_requested`; owner, 2026-10-29): the caster's controller drives the oldest of the
	## bodies it possesses and the others copy its intent; the caster's body stands. The rule is in
	## `gameplay/actor/possession.gd`.
	POSSESS,
	## Shots of another team that touch the carrier turn and become its caster's, each time
	## `SpellLimits.DEFLECT_SPEEDUP` times faster (melee I3; owner, 2026-10-29): on every carrier
	## that touches shots (a shot, a swing's sweep, a beam's line). It turns as many as touch it, goes
	## before a shield (which keeps its charge) and sets off `on block`. Strength unused (1).
	DEFLECT,
	## Whatever the carrier hits, its caster is pulled to, over `SpellLimits.PULL_SECONDS` (rules R4
	## F1; owner, 2026-10-30: the old Hook carrier is `pull · bolt`): the wizard, or the shot that
	## cast it. Several hits make several pulls, and they add. Strength unused (1).
	PULL,
}

## What each behaviour needs from the carrier it rides on to do anything, in the carrier's yes/no
## answers (`CarrierTraits`): "any": at least one of these flags; "not": none of these; "or_cards":
## a card with one of these behaviours on the carrier does instead (what a blast strikes is the
## carrier's hit, rules R4 F2). A behaviour not here works on every carrier (numbers, blast, echo,
## recoil, mirror: a move and its mirror add up to none, rules R4 F1). A new behaviour adds its line here, never per carrier; the compiler checks it every
## time a staff is built (`Carrier.works`).
const NEEDS: Dictionary = {
	Behaviour.HOMING: {"any": CarrierTraits.STEERS},
	# What a blast strikes is the carrier's hit (rules R4 F2), so these work with one too.
	Behaviour.CHAIN: {"any": CarrierTraits.HITS, "or_cards": [Behaviour.BLAST]},
	Behaviour.SIPHON: {"any": CarrierTraits.HITS, "or_cards": [Behaviour.BLAST]},
	Behaviour.POSSESS: {"any": CarrierTraits.HITS, "or_cards": [Behaviour.BLAST]},
	Behaviour.HEAVY: {"any": CarrierTraits.HITS, "or_cards": [Behaviour.BLAST]},
	Behaviour.RELAY: {"any": CarrierTraits.HITS, "or_cards": [Behaviour.BLAST]},
	# A blast's hits move nothing (rules R4 F2: a pull at every arrival would never end).
	Behaviour.PULL: {"any": CarrierTraits.HITS},
	Behaviour.SHIELD: {"any": CarrierTraits.MEETS_SHOTS},
	Behaviour.DEFLECT: {"any": CarrierTraits.MEETS_SHOTS},
	Behaviour.HOLD: {"any": CarrierTraits.LASTS, "not": CarrierTraits.MOVES_CASTER},
	Behaviour.BOUNCE: {"any": CarrierTraits.FLIES | CarrierTraits.LINE},
	Behaviour.GHOST: {"any": CarrierTraits.FLIES | CarrierTraits.LINE},
	Behaviour.RETURN: {"any": CarrierTraits.FLIES},
	Behaviour.LINGER: {"any": CarrierTraits.MOVES},
	Behaviour.STICKY: {"any": CarrierTraits.MOVES},
	Behaviour.SPIRAL: {"any": CarrierTraits.MOVES | CarrierTraits.LINE},
	Behaviour.GROWTH: {"any": CarrierTraits.STAYS | CarrierTraits.LINE},
	Behaviour.MAGNET: {"any": CarrierTraits.STAYS | CarrierTraits.LINE},
	Behaviour.ZAP: {"any": CarrierTraits.STAYS},
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
## For HOMING the radius in pixels of the tightest curve it turns on (at any speed: a fast shot
## turns faster, on the same curve); number of jumps for CHAIN; unused for NONE.
@export var behaviour_strength: float = 0.0
## Pixels the behaviour reaches. For HOMING, how far a shot looks for a target (one in flight
## looks again as it flies; a beam looks at least as far as it is long), on every form homing
## steers (`Carrier.homing_range`). Unused by the others.
@export var behaviour_reach: float = 0.0

# --- Look (staffs B6a) ----------------------------------------------------------------

## The particles this card makes its shots give off: a LOOK_* kind of `core/projectiles` (0
## none, 1 embers, 2 frost flecks ... see the LOOK_* constants in
## `core/projectiles/projectile_manager.gd`). A shot gives off the kinds of all its infusions
## and modifiers, mixed at random from its tail; two cards with the same kind add nothing more.
@export var look_layer: int = 0
## The cue (`content/cues`) Feel plays when this card's behaviour goes off: `blast`'s explosion,
## as big as its radius. When several cards of one behaviour name a cue, the first in slot order
## is played (`CompiledSpell.cue_of`); none plays nothing.
@export var cue: StringName = &""

# --- Aim (staff spread) ---------------------------------------------------------------

## Factor on the staff's `spread` for the next carrier's shots: below 1 they leave truer
## (sniper), above 1 wilder. Several multiply. A staff with no spread aims true whatever it is.
@export var spread_mult: float = 1.0

# --- Life (slow) ----------------------------------------------------------------------

## Factor on the carrier's `lifetime`. With `speed_mult` it makes a slow shot that still goes as
## far (slow: speed x0.3, lifetime x3). Several multiply.
@export var lifetime_mult: float = 1.0

# --- Range (reach) ----------------------------------------------------------------------

## Factor on how far the carrier goes: a flying shot's `lifetime` (its range is speed x life),
## every other carrier's `ray_length` (a beam's, a dash's, a rain's aim point...). Several
## multiply. Wasted where the carrier has no range (`Carrier.reaches`).
@export var reach_mult: float = 1.0


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
		"look_layer": Vector2(0.0, 21.0),
		"extra_pierce": Vector2(0, 8),
		"behaviour": Vector2(0, Behaviour.size() - 1),
		"behaviour_strength": Vector2(0.0, 256.0),
		"behaviour_reach": Vector2(0.0, 360.0),
		"spread_mult": Vector2(0.0, 4.0),
		"lifetime_mult": Vector2(0.1, 4.0),
		"reach_mult": Vector2(0.1, 4.0),
	})
	return limits
