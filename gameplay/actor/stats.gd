class_name Stats
extends ActorComponent
## The body's stats (boss plan OB7, docs/milestones/boss-old-broom.md, "Actor stats"): its own copy
## of its `ActorStats` (core/base), taken as it enters play from its enemy's data
## (`EnemyBase.stats`), its prop's (`PropBase.stats`), else this component's `base` (a wizard's
## scene sets its own), and again from a boss's phase that names some (`Phases`, `apply`). What
## changes the numbers later (relics, difficulty) changes this copy, never the shared resource.
## Every actor has one: its scene's, or one the actor adds itself, as it adds a `Footprint`. Never
## stepped: what uses the numbers reads them at the moment.
##
## - `power`: × the damage of its spell hits, read by Combat at the hit from the caster's body
##   (its slam and the burn its hit puts on too; not its contact damage nor its heals).
## - `mass`: a shove on it (Combat's knockback, a pull) is divided by it.
## - `spell_scale`: × the radius of its spells, built into its staffs (`Caster`), so a change
##   asks its caster to build them again (`apply` says so).
## - `resist`: per status, the share it resists (0 to 1), a fixed array in Combat's status order
##   (`Combat.STATUSES`, a freeze as a chill), then the possession's (POSSESS): the status lasts
##   (1 - share) as long (`resist_of`).
##
## State (hashed, in snapshots) like any member (core/sim/README.md).

const CombatScript := preload("res://gameplay/combat/combat.gd")

## The resist array's entry for a possession, after Combat's statuses.
const POSSESS: int = CombatScript.STATUS_COUNT
## How many shares `resist` holds.
const RESIST_COUNT: int = CombatScript.STATUS_COUNT + 1
## The least mass and spell scale a body has (data of 0 or less is a mistake the content checks
## name; the body still never divides by 0).
const LEAST: float = 0.05

## The stats a body whose data names none takes (a wizard's scene; null: every default).
@export var base: ActorStats = null

var power: float = 1.0
var mass: float = 1.0
var spell_scale: float = 1.0
var resist: PackedFloat64Array = PackedFloat64Array()
## True once the numbers were taken from the data: a body made again from a snapshot has its own
## back before its `_ready`, which then takes nothing.
var taken: bool = false


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	if resist.size() != RESIST_COUNT:
		resist.resize(RESIST_COUNT)
	if not taken:
		apply(source())
		taken = true


## The stats the body enters play with: its enemy's, else its prop's, else `base` (null: defaults).
func source() -> ActorStats:
	if actor != null and actor.data != null and actor.data.stats != null:
		return actor.data.stats
	if actor != null and actor.prop != null and actor.prop.stats != null:
		return actor.prop.stats
	return base


## Copy `from` (null: every default) as the body's own. Returns true when its spell scale changed,
## so the staffs it holds must be built again (`Caster.rebuild`).
func apply(from: ActorStats) -> bool:
	var scale_was: float = spell_scale
	if resist.size() != RESIST_COUNT:
		resist.resize(RESIST_COUNT)
	if from == null:
		power = 1.0
		mass = 1.0
		spell_scale = 1.0
		resist.fill(0.0)
	else:
		power = maxf(from.power, 0.0)
		mass = maxf(from.mass, LEAST)
		spell_scale = maxf(from.spell_scale, LEAST)
		for st in CombatScript.STATUS_COUNT:
			resist[st] = from.resist_of(CombatScript.STATUSES[st])
		resist[POSSESS] = from.resist_of(&"possess")
	return spell_scale != scale_was


## The share resisted of Combat's status `st` (its index in `Combat.STATUSES`), or of a possession
## (POSSESS); 0 for anything else.
func resist_of(st: int) -> float:
	return resist[st] if st >= 0 and st < resist.size() else 0.0


## Its numbers are its data's until something changes them (a phase: a boss is never at rest).
func at_rest() -> bool:
	var from: ActorStats = source()
	if from == null:
		return power == 1.0 and mass == 1.0 and spell_scale == 1.0 and resist.count(0.0) == resist.size()
	if power != maxf(from.power, 0.0) or mass != maxf(from.mass, LEAST) or spell_scale != maxf(from.spell_scale, LEAST):
		return false
	for st in CombatScript.STATUS_COUNT:
		if resist[st] != from.resist_of(CombatScript.STATUSES[st]):
			return false
	return resist[POSSESS] == from.resist_of(&"possess")
