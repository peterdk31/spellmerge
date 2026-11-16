class_name ActorStats
extends Resource
## An actor's stats (boss plan OB7, docs/milestones/boss-old-broom.md, "Actor stats"): read-only
## data shared like a card, named by an enemy (`EnemyBase.stats`), a boss's phase
## (`EnemyPhase.stats`), a prop (`PropBase.stats`) or a wizard's scene (its `Stats` component's
## `base`). The body copies the numbers into its own state as it enters play (the actor kit's
## `Stats`, gameplay/actor); what changes them later (a phase, and later relics and difficulty)
## changes the copy, never this resource. Every default leaves the game as it is.

## The statuses a body may resist, as the data names them; `possess` is the possession's seconds.
## A freeze is a chill's (three chills in a row): it lasts as the chill's share says.
const RESISTED: Array[StringName] = [&"burn", &"chill", &"gust", &"hex", &"static", &"soak", &"possess"]

## × the damage of the body's spell hits and what follows from them: heavy's slam, a burn its hit
## puts on. Not its contact damage (its own number) nor its heals.
@export_range(0.0, 10.0, 0.05, "or_greater") var power: float = 1.0
## A shove on the body (a spell's knockback, a pull) is divided by it. Above 0.
@export_range(0.05, 20.0, 0.05, "or_greater") var mass: float = 1.0
## × the size of the body's spells (a shot's radius, a pulse's ring, a blast, a swing's arc, a pool): the
## actor's counterpart of `bigger`'s radius, without its damage or speed. Above 0.
@export_range(0.05, 4.0, 0.05, "or_greater") var spell_scale: float = 1.0
## Each status's share resisted (0 to 1): it lasts (1 - share) as long; 1 never takes it.
@export_range(0.0, 1.0, 0.05) var resist_burn: float = 0.0
@export_range(0.0, 1.0, 0.05) var resist_chill: float = 0.0
@export_range(0.0, 1.0, 0.05) var resist_gust: float = 0.0
@export_range(0.0, 1.0, 0.05) var resist_hex: float = 0.0
@export_range(0.0, 1.0, 0.05) var resist_static: float = 0.0
@export_range(0.0, 1.0, 0.05) var resist_soak: float = 0.0
## A possession of the body lasts (1 - share) as long.
@export_range(0.0, 1.0, 0.05) var resist_possess: float = 0.0


## The share of `status` resisted (0 to 1); a freeze as a chill, anything else 0.
func resist_of(status: StringName) -> float:
	match status:
		&"burn":
			return clampf(resist_burn, 0.0, 1.0)
		&"chill", &"freeze":
			return clampf(resist_chill, 0.0, 1.0)
		&"gust":
			return clampf(resist_gust, 0.0, 1.0)
		&"hex":
			return clampf(resist_hex, 0.0, 1.0)
		&"static":
			return clampf(resist_static, 0.0, 1.0)
		&"soak":
			return clampf(resist_soak, 0.0, 1.0)
		&"possess":
			return clampf(resist_possess, 0.0, 1.0)
	return 0.0


## What is wrong with the numbers, as lines for the content checks (empty when nothing is): a mass
## or spell scale of 0 or less, a power below 0, a share outside 0 to 1.
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if not (power >= 0.0):
		out.append("power is below 0: set it to 0 or more (1 leaves the hits as they are)")
	if not (mass > 0.0):
		out.append("mass is 0 or less: set it above 0 (1 leaves shoves as they are)")
	if not (spell_scale > 0.0):
		out.append("spell_scale is 0 or less: set it above 0 (1 leaves the spells' size as it is)")
	var shares: Array[float] = [resist_burn, resist_chill, resist_gust, resist_hex, resist_static, resist_soak, resist_possess]
	for i in RESISTED.size():
		if not (shares[i] >= 0.0 and shares[i] <= 1.0):
			out.append("resist_%s is outside 0 to 1: a share of the status's time" % RESISTED[i])
	return out
