class_name HitStop
extends RefCounted
## Hit-stop as a rule of the game (online-ready N4, docs/milestones/online-ready.md): which bodies a
## moment holds still, for how long, and when the whole game stands still. Combat owns it and tells
## it the moments as they happen (a hit, a kill, a reaction, a parry, a carrier's end, a cue the
## simulation shows, a downed wizard); Feel only draws them (the flash, the shake, the sound). So
## the holds are the same with or without Feel, on every machine, counted on the game's ticks.
##
## - **A hit** holds its attacker, its target and the shot that hit for `SECONDS` times its kind's
##   factor (`KIND_STOP`), as a plain hold: a body still resting from its last hold (`REST` after
##   it, `Actors.hold`) is not held again, so a crowd's hits do not freeze it.
## - **A moment with a cue** holds as the cue says (`CueBase.hold` the caster, `hold_target` the
##   target, `hold_shot` the shot, each times its `power`), always (a kill, a reaction, a parry,
##   a slam's strike), and `stop_game` stands the whole game still for as many ticks (`Sim.hold`):
##   a downed wizard and a boss's death. Which cue a moment has is Feel's choice too, made the
##   same way (`CueBase.reaction_cue`; `boss_death` or `enemy_death`; a shot's card's
##   `impact_cue` where it strikes; a carrier card's `end_cue`; `parry` for a swing's block).
## - **A reaction's cue** holds at most once every `CueBase.REACTION_REPEAT` seconds per
##   reaction, counted in Combat's steps (so a test that steps Combat by hand counts as the game
##   does).
##
## A card's cast, shown and wind cues hold nothing (`tests/gameplay/combat/test_hit_stop.gd` fails
## on one with a hold).
##
## Its numbers were Feel's preset's (`hit_stop_seconds`, `hit_stop_rest`, the kinds' `stop`); they
## are the game's now, the same for everyone. The cue names and the reaction repeat are CueBase's,
## shared with Feel, so the two always agree.

const ActorsScript := preload("res://core/actors/actors.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const TickScript := preload("res://core/sim/tick.gd")
## A plain hit's stop, in seconds.
const SECONDS: float = 0.04
## How long a body rests after a stop before a plain hit holds it again, in seconds.
const REST: float = 0.15
## A hit's stop by its kind (Combat's `hit_landed` kinds), as a factor of SECONDS; a kind not
## here stops as a shot.
const KIND_STOP: Dictionary[StringName, float] = {
	&"shot": 1.0,
	&"ray": 0.5,
	&"swing": 1.25,
	&"burst": 1.5,
	&"reaction": 1.0,
	&"status": 0.0,
}

## Not state: the services it holds and stops through, and caches of content (core/sim/README.md).
const DERIVED: Array[StringName] = [&"actors", &"projectiles", &"registry", &"sim", &"_cues", &"_reaction_cues", &"_carrier_card_cues"]

## What it holds and stops through, handed over by its owner (Combat's `bind`): the bodies' holds
## (the actor table), the shots' (the projectile manager), the cues (the registry) and the
## game-wide stop (the sim). It reaches nothing else.
var actors: ActorsScript = null
var projectiles: ManagerScript = null
var registry: RegistryScript = null
var sim: Sim = null
## Steps taken (`step`, once per Combat step): the clock a reaction's repeat is counted on, so a
## test that steps Combat by hand counts as the game does.
var steps: int = 0
## Per reaction id, the step from which its cue holds again.
var _reaction_next: Dictionary[StringName, int] = {}
## Caches of content: cue by id (null for none), a reaction's cue id, a card's [impact, end] cues.
var _cues: Dictionary = {}
var _reaction_cues: Dictionary = {}
var _carrier_card_cues: Dictionary = {}


## Hand over the services (Combat's, each time they may have changed: its setup and its step).
## The sim is set on its own (Combat's, or a test's).
func bind(table: ActorsScript, manager: ManagerScript, content: RegistryScript) -> void:
	actors = table
	projectiles = manager
	registry = content


## One step of its owner's (Combat's `step`).
func step() -> void:
	steps += 1


## A hit of `kind` by the actor `by` on the actor `target` (either NONE), by the shot `shot` (-1
## for none): the plain hold.
func hit(by: int, target: int, kind: StringName, shot: int) -> void:
	if actors == null:
		return
	var seconds: float = SECONDS * KIND_STOP.get(kind, 1.0)
	if seconds <= 0.0:
		return
	var held: bool = actors.hold(by, seconds, REST, true)
	held = actors.hold(target, seconds, REST, true) or held
	if held and shot >= 0:
		_freeze(shot, seconds)


## The moment of the cue `id` (content/cues): its holds and its game-wide stop.
func cue(id: StringName, caster: int, target: int = ActorsScript.NONE, shot: int = -1) -> void:
	var of: CueBase = _cue(id)
	if of == null:
		return
	if of.stop_game > 0.0:
		if sim != null:
			sim.hold(roundi(of.stop_game / TickScript.DT))
	if actors == null or (of.hold <= 0.0 and of.hold_target <= 0.0):
		return
	var held: bool = of.hold > 0.0 and actors.hold(caster, of.hold * of.power, REST)
	held = (of.hold_target > 0.0 and actors.hold(target, of.hold_target * of.power, REST)) or held
	if of.hold_shot and held and shot >= 0:
		_freeze(shot, maxf(of.hold, of.hold_target) * of.power)


## A reaction `reaction_id` set off by `by`, from the shot `shot`: its cue's holds, at most once
## every CueBase.REACTION_REPEAT seconds per reaction.
func reaction(by: int, reaction_id: StringName, shot: int) -> void:
	if steps < (_reaction_next.get(reaction_id, 0) as int):
		return
	_reaction_next[reaction_id] = steps + roundi(CueBase.REACTION_REPEAT / TickScript.DT)
	cue(_reaction_cue(reaction_id), by, ActorsScript.NONE, shot)


## The actor `killer` killed `enemy` (a boss when its data says so), with the shot `shot`.
func killed(killer: int, enemy: Node, shot: int) -> void:
	var boss: bool = enemy is Actor and (enemy as Actor).data != null and (enemy as Actor).data.boss
	cue(CueBase.BOSS_DEATH_CUE if boss else CueBase.ENEMY_DEATH_CUE, killer, ActorsScript.NONE, shot)


## A wizard went down.
func downed() -> void:
	cue(CueBase.DOWNED_CUE, ActorsScript.NONE)


## `caster`'s swing blocked a shot: a parry.
func parried(caster: int) -> void:
	cue(CueBase.PARRY_CUE, caster)


## `caster`'s carrier of the card `carrier_card` ended with no shot (a slam's strike): its card's `end_cue`.
func carrier_ended(caster: int, carrier_card: StringName) -> void:
	var id: StringName = _carrier_card_cue(carrier_card, 1)
	if id != &"":
		cue(id, caster)


## A shot of `caster`'s, of the card `carrier_card`, struck a body or a wall: its card's `impact_cue`.
func impact(caster: int, carrier_card: StringName) -> void:
	var id: StringName = _carrier_card_cue(carrier_card, 0)
	if id != &"":
		cue(id, caster)


func _freeze(shot: int, seconds: float) -> void:
	if projectiles != null:
		projectiles.freeze_shot(shot, seconds)


func _cue(id: StringName) -> CueBase:
	if id == &"":
		return null
	if _cues.has(id):
		return _cues[id] as CueBase
	var of: CueBase = null
	if registry != null:
		of = registry.get_resource(&"cues", id) as CueBase
	_cues[id] = of
	return of


func _reaction_cue(reaction_id: StringName) -> StringName:
	if _reaction_cues.has(reaction_id):
		return _reaction_cues[reaction_id] as StringName
	var id: StringName = CueBase.reaction_cue(reaction_id, _cue)
	_reaction_cues[reaction_id] = id
	return id


## The card `carrier_card`'s impact cue (`which` 0) or end cue (1), &"" for none.
func _carrier_card_cue(carrier_card: StringName, which: int) -> StringName:
	# (Kept as names, read with one lookup: a shot's impact asks on every hit.)
	var cues: Variant = _carrier_card_cues.get(carrier_card)
	if cues == null:
		var made: Array[StringName] = [&"", &""]
		if registry != null and carrier_card != &"":
			var card: Resource = registry.get_resource(&"spells", carrier_card)
			if card is CarrierCard:
				made[0] = (card as CarrierCard).impact_cue
				made[1] = (card as CarrierCard).end_cue
		_carrier_card_cues[carrier_card] = made
		cues = made
	return (cues as Array[StringName])[which]
