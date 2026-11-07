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
##   same way (`reaction_<id>`, else `reaction`; `boss_death` or `enemy_death`; a shot's card's
##   `impact_cue` where it strikes; a carrier card's `end_cue`; `parry` for a swing's block).
## - **A reaction's cue** holds at most once every `REACTION_REPEAT` seconds per reaction, counted
##   in Combat's steps (so a test that steps Combat by hand counts as the game does).
##
## A card's cast, shown and wind cues hold nothing (`tests/gameplay/combat/test_hit_stop.gd` fails
## on one with a hold).
##
## Its numbers were Feel's preset's (`hit_stop_seconds`, `hit_stop_rest`, the kinds' `stop`) and
## Feel's `REACTION_REPEAT`; they are the game's now, the same for everyone.

const ActorsScript := preload("res://core/actors/actors.gd")

## A tick's seconds (the Tick's DT).
const TICK_SECONDS: float = 1.0 / 60.0
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
## A reaction's cue holds at most once in this many seconds, per reaction.
const REACTION_REPEAT: float = 0.3
## The cue of a reaction with no cue of its own (`reaction_<id>`).
const REACTION_CUE: StringName = &"reaction"
const PARRY_CUE: StringName = &"parry"
const DOWNED_CUE: StringName = &"player_downed"
const ENEMY_DEATH_CUE: StringName = &"enemy_death"
const BOSS_DEATH_CUE: StringName = &"boss_death"

## Not state: its Combat, the game's time, and caches of content (core/sim/README.md).
const DERIVED: Array[StringName] = [&"combat", &"sim", &"_cues", &"_reaction_cues", &"_form_cues"]

## The Combat that owns it: its actor table, projectile manager and registry are the ones used.
var combat: Node = null
## The game's time and its game-wide stop. Only tests set it; otherwise Combat's (`Sim.found`).
var sim: Sim = null
## Per reaction id, Combat's step from which its cue holds again.
var _reaction_next: Dictionary[StringName, int] = {}
## Caches of content: cue by id (null for none), a reaction's cue id, a card's [impact, end] cues.
var _cues: Dictionary = {}
var _reaction_cues: Dictionary = {}
var _form_cues: Dictionary = {}


## A hit of `kind` by the actor `by` on the actor `target` (either NONE), by the shot `shot` (-1
## for none): the plain hold.
func hit(by: int, target: int, kind: StringName, shot: int) -> void:
	var actors: ActorsScript = _actors()
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
		_sim().hold(roundi(of.stop_game / TICK_SECONDS))
	var actors: ActorsScript = _actors()
	if actors == null or (of.hold <= 0.0 and of.hold_target <= 0.0):
		return
	var held: bool = of.hold > 0.0 and actors.hold(caster, of.hold * of.power, REST)
	held = (of.hold_target > 0.0 and actors.hold(target, of.hold_target * of.power, REST)) or held
	if of.hold_shot and held and shot >= 0:
		_freeze(shot, maxf(of.hold, of.hold_target) * of.power)


## A reaction `reaction_id` set off by `by`, from the shot `shot`: its cue's holds, at most once
## every REACTION_REPEAT seconds per reaction.
func reaction(by: int, reaction_id: StringName, shot: int) -> void:
	var now: int = combat.get(&"_steps") as int if combat != null else 0
	if now < (_reaction_next.get(reaction_id, 0) as int):
		return
	_reaction_next[reaction_id] = now + roundi(REACTION_REPEAT / TICK_SECONDS)
	cue(_reaction_cue(reaction_id), by, ActorsScript.NONE, shot)


## The actor `killer` killed `enemy` (a boss when its data says so), with the shot `shot`.
func killed(killer: int, enemy: Node, shot: int) -> void:
	var boss: bool = enemy is Actor and (enemy as Actor).data != null and (enemy as Actor).data.boss
	cue(BOSS_DEATH_CUE if boss else ENEMY_DEATH_CUE, killer, ActorsScript.NONE, shot)


## A wizard went down.
func downed() -> void:
	cue(DOWNED_CUE, ActorsScript.NONE)


## `caster`'s swing blocked a shot: a parry.
func parried(caster: int) -> void:
	cue(PARRY_CUE, caster)


## `caster`'s carrier of the card `form` ended with no shot (a slam's strike): its card's `end_cue`.
func carrier_ended(caster: int, form: StringName) -> void:
	var id: StringName = _form_cue(form, 1)
	if id != &"":
		cue(id, caster)


## A shot of `caster`'s, of the card `form`, struck a body or a wall: its card's `impact_cue`.
func impact(caster: int, form: StringName) -> void:
	var id: StringName = _form_cue(form, 0)
	if id != &"":
		cue(id, caster)


func _actors() -> ActorsScript:
	return combat.call(&"_table") as ActorsScript if combat != null else null


func _sim() -> Sim:
	if sim == null:
		if combat == null or not combat.is_inside_tree():
			return Sim.found(null)
		sim = Sim.found(combat)
	return sim


## Combat's registry, else the Registry autoload (a test world built out of the tree has the
## game's content all the same: the rule must hold there as in the game).
func _registry() -> Node:
	var registry: Node = combat.get(&"registry") as Node if combat != null else null
	if registry == null:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			registry = tree.root.get_node_or_null(^"Registry")
	return registry


func _freeze(shot: int, seconds: float) -> void:
	var projectiles: Node = combat.get(&"projectiles") as Node if combat != null else null
	if projectiles != null:
		projectiles.call(&"freeze_shot", shot, seconds)


func _cue(id: StringName) -> CueBase:
	if id == &"":
		return null
	if _cues.has(id):
		return _cues[id] as CueBase
	var of: CueBase = null
	var registry: Node = _registry()
	if registry != null:
		of = registry.call(&"get_resource", &"cues", id) as CueBase
	_cues[id] = of
	return of


func _reaction_cue(reaction_id: StringName) -> StringName:
	if _reaction_cues.has(reaction_id):
		return _reaction_cues[reaction_id] as StringName
	var own: StringName = StringName("reaction_" + String(reaction_id))
	var id: StringName = own if _cue(own) != null else REACTION_CUE
	_reaction_cues[reaction_id] = id
	return id


## The card `form`'s impact cue (`which` 0) or end cue (1), &"" for none.
func _form_cue(form: StringName, which: int) -> StringName:
	if not _form_cues.has(form):
		var cues: PackedStringArray = PackedStringArray(["", ""])
		var registry: Node = _registry()
		if registry != null and form != &"":
			var card: Resource = registry.call(&"get_resource", &"spells", form) as Resource
			if card is FormBase:
				cues[0] = String((card as FormBase).impact_cue)
				cues[1] = String((card as FormBase).end_cue)
		_form_cues[form] = cues
	return StringName((_form_cues[form] as PackedStringArray)[which])
