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
	## a boomerang carrier). Only on a carrier that flies (`ModifierBase.RULES`).
	RETURN,
	## Each enemy that comes within `behaviour_reach` pixels of the shot has a `behaviour_strength`
	## chance (0 to 1; 0.5 the card) to be zapped, rolled again `SpellLimits.ZAP_AGAIN` (1 s) after it
	## was zapped or lost its roll (owner, 2026-10-31), at a random moment while it is in
	## reach (SpellLimits.ZAP_WAIT_MOST), the one the shot is about to hit too, before it hits (zap cards combine as chances: two are 75%; with nothing near the shot
	## sparks into the air; SpellLimits.ZAP_*; owner, 2026-10-30), at `SpellLimits.ZAP_DAMAGE` of its damage with its infusions; a zap
	## is a hit, so it sets off `on hit` and chains (owner, 2026-10-27). Only on a carrier that
	## stays in the air as a shot, or a line (a beam: the bodies near its line, zapped from it,
	## `CarrierBeam._step_zaps`).
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
	## The carrier is cast `behaviour_strength` times (5 the card; more cards add) instead of once,
	## each copy from a point on a ring round its caster (its body, or the point or shot casting a
	## payload), all aimed in at it (owner, 2026-11-05: it reads no other card; homing steers each
	## copy, as on any carrier). Each copy is cast by its point (`SpellRuntime._penta`). Not on a
	## carrier that moves its caster or strikes from the hand.
	PENTA,
}

## How more cards of one behaviour on a carrier combine (`StaffCompiler.stacked`): counts add
## (bounces, shields, seconds, pixels), factors multiply (two heavy cards are 4 x 4, rule 3,
## docs/milestones/M2-rules.md R1c), chances combine as chances (two 50% zaps are 75%).
enum Stack { ADD, MULTIPLY, CHANCE }

## Everything the spell rules know about each behaviour, one row each, so a behaviour is described
## in one place (the engine code that runs it aside: the projectile manager or the spell runtime):
## - "needs": what it needs from the carrier it rides on to do anything (`Carrier.works`), in the
##   carrier's yes/no answers (`CarrierTraits`): "any": at least one of these flags; "not": none of
##   these; "or_cards": a card with one of these behaviours on the carrier does instead (what a
##   blast strikes is the carrier's hit, rules R4 F2). None: it works on every carrier (numbers,
##   blast, echo, recoil, mirror: a move and its mirror add up to none, rules R4 F1).
## - "stacks": a `Stack` (ADD when missing).
## A card names its behaviour by its name (`behaviour_id`), so a behaviour added or taken out never
## renumbers a card. `tests/core/test_behaviour_table.gd` checks every row.
const RULES: Dictionary = {
	Behaviour.NONE: {},
	Behaviour.HOMING: {"needs": {"any": CarrierTraits.STEERS}},
	# What a blast strikes is the carrier's hit (rules R4 F2), so the hit cards work with one too.
	Behaviour.CHAIN: {"needs": {"any": CarrierTraits.HITS, "or_cards": [Behaviour.BLAST]}},
	Behaviour.SHIELD: {"needs": {"any": CarrierTraits.MEETS_SHOTS}},
	Behaviour.BLAST: {},
	Behaviour.HOLD: {"needs": {"any": CarrierTraits.LASTS, "not": CarrierTraits.MOVES_CASTER}},
	Behaviour.RECOIL: {},
	Behaviour.BOUNCE: {"needs": {"any": CarrierTraits.FLIES | CarrierTraits.LINE}},
	Behaviour.ECHO: {},
	Behaviour.LINGER: {"needs": {"any": CarrierTraits.MOVES}},
	Behaviour.HEAVY: {"needs": {"any": CarrierTraits.HITS, "or_cards": [Behaviour.BLAST]}, "stacks": Stack.MULTIPLY},
	Behaviour.SIPHON: {"needs": {"any": CarrierTraits.HITS, "or_cards": [Behaviour.BLAST]}},
	Behaviour.STICKY: {"needs": {"any": CarrierTraits.MOVES}},
	Behaviour.MAGNET: {"needs": {"any": CarrierTraits.STAYS | CarrierTraits.LINE}},
	Behaviour.GHOST: {"needs": {"any": CarrierTraits.FLIES | CarrierTraits.LINE}},
	Behaviour.SPIRAL: {"needs": {"any": CarrierTraits.MOVES | CarrierTraits.LINE}},
	Behaviour.MIRROR: {},
	Behaviour.GROWTH: {"needs": {"any": CarrierTraits.STAYS | CarrierTraits.LINE}, "stacks": Stack.MULTIPLY},
	Behaviour.RELAY: {"needs": {"any": CarrierTraits.HITS, "or_cards": [Behaviour.BLAST]}},
	Behaviour.RETURN: {"needs": {"any": CarrierTraits.FLIES}},
	Behaviour.ZAP: {"needs": {"any": CarrierTraits.STAYS | CarrierTraits.LINE}, "stacks": Stack.CHANCE},
	Behaviour.POSSESS: {"needs": {"any": CarrierTraits.HITS, "or_cards": [Behaviour.BLAST]}},
	Behaviour.DEFLECT: {"needs": {"any": CarrierTraits.MEETS_SHOTS}},
	# A blast's hits move nothing (rules R4 F2: a pull at every arrival would never end).
	Behaviour.PULL: {"needs": {"any": CarrierTraits.HITS}},
	# A dash or teleport moves its caster, a swing or slam strikes from the hand: nothing of them
	# leaves from a point of a ring. More cards add copies.
	Behaviour.PENTA: {"needs": {"not": CarrierTraits.MOVES_CASTER | CarrierTraits.OWN_POSE}},
}

## The card's behaviour, by its name: a `Behaviour` key in lower case (`&"homing"`); empty for none.
## An unknown name counts as none, and the validator names it (`range_problems`).
@export var behaviour_id: StringName = &""

## `behaviour_id` as a `Behaviour`, for the compiler and the runtime.
var behaviour: Behaviour:
	get:
		return behaviour_of(behaviour_id)
	set(value):
		behaviour_id = name_of(value)


## The `Behaviour` named `id` (NONE for empty or unknown).
static func behaviour_of(id: StringName) -> Behaviour:
	if id == &"" or String(id) != String(id).to_lower():
		return Behaviour.NONE
	return Behaviour.get(String(id).to_upper(), Behaviour.NONE)


## The name a card gives `behaviour` (empty for NONE).
static func name_of(behaviour: int) -> StringName:
	if behaviour <= Behaviour.NONE or behaviour >= Behaviour.size():
		return &""
	return StringName(String(Behaviour.keys()[behaviour]).to_lower())


## What `behaviour` needs from its carrier (`RULES` "needs"; empty: nothing).
static func needs(behaviour: int) -> Dictionary:
	return (RULES.get(behaviour, {}) as Dictionary).get("needs", {})


## How cards of `behaviour` combine (`RULES` "stacks").
static func stacks(behaviour: int) -> Stack:
	return (RULES.get(behaviour, {}) as Dictionary).get("stacks", Stack.ADD)


@export var damage_mult: float = 1.0
@export var speed_mult: float = 1.0
@export var radius_mult: float = 1.0
## Factor on the carrier's wind-down (`FormBase.wind_down`).
@export var wind_down_mult: float = 1.0
## Seconds added to the carrier's wind-up (`FormBase.wind_up`): a charge; a cost, never an effect
## of its own (docs/milestones/cast-timing.md).
@export var wind_up_add: float = 0.0
@export var mana_mult: float = 1.0
## Factor on the number of shots per cast, spread in a fan (split). The compiled spell is
## clamped to the shot limit.
@export var shot_mult: int = 1
## Targets added to each shot's pierce.
@export var extra_pierce: int = 0
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
## as big as its radius, or `zap`'s arc wherever a zap shows itself (`form_shown` names the card;
## as long as the zap). When several cards of one behaviour name a cue, the first in slot order
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

# --- Speed over life -------------------------------------------------------------------

## Factors on a flying shot's speed when it leaves (`speed_start`) and as its life runs out
## (`speed_end`), and how it goes from one to the other (`speed_ease`: 1 evenly, above 1 most of
## the change early, below 1 late; `ProjectileManager.set_speed_curve`). Every shot already bursts
## out and slows (SpellLimits.SHOT_SPEED_*: 2.2, 0.2, 1.5); a card's numbers multiply that, and
## several cards multiply each other. All 1 changes nothing; wasted where the carrier does not fly.
@export var speed_start: float = 1.0
@export var speed_end: float = 1.0
@export var speed_ease: float = 1.0


func kind() -> StringName:
	return &"modifier"


func ranges() -> Dictionary:
	var limits: Dictionary = super()
	limits.merge({
		"damage_mult": Vector2(0.1, 4.0),
		"speed_mult": Vector2(0.1, 4.0),
		"radius_mult": Vector2(0.25, 4.0),
		"wind_down_mult": Vector2(0.1, 4.0),
		"wind_up_add": Vector2(0.0, 5.0),
		"mana_mult": Vector2(0.1, 4.0),
		"shot_mult": Vector2(1, 8),
		"look_layer": Vector2(0.0, 21.0),
		"extra_pierce": Vector2(0, 8),
		"behaviour_strength": Vector2(0.0, 256.0),
		"behaviour_reach": Vector2(0.0, 360.0),
		"spread_mult": Vector2(0.0, 4.0),
		"lifetime_mult": Vector2(0.1, 4.0),
		"reach_mult": Vector2(0.1, 4.0),
		"speed_start": Vector2(0.1, 4.0),
		"speed_end": Vector2(0.0, 4.0),
		"speed_ease": Vector2(0.1, 8.0),
	})
	return limits


## The range problems, and a behaviour name that is not a `Behaviour`.
func range_problems() -> PackedStringArray:
	var problems: PackedStringArray = super()
	if behaviour_id != &"" and behaviour_of(behaviour_id) == Behaviour.NONE:
		problems.append("behaviour_id: %s is not a behaviour (%s)" % [behaviour_id, ", ".join(Behaviour.keys().slice(1)).to_lower()])
	return problems
