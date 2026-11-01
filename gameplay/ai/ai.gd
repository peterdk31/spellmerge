class_name AIController
extends ActorController
## The enemy AI as a controller (actors G6; enemy AI AI5, docs/milestones/M2-enemy-ai.md): it drives
## an actor (gameplay/actor) the way a seat's controller does, by writing the actor's intent and
## nothing else. The thinking is an `AIBrain` (`brain.gd`): it reads what each of the actor's
## staffs casts next and plays them by its behaviours, so a new enemy needs staffs and a profile,
## never code. It is a child of an enemy's actor scene, that actor's home controller; a possession
## (G9) may hand it another actor for a while, and then it plays that actor's staffs (a wizard's
## four, say) by its own profile.
##
## Its profile is its home actor's data's (`EnemyBase.profile`, else `AIProfile.fallback()`), or
## `profile` when set. Grudges (infighting) come from the driven actor's own `Actor.damaged` (sent
## with every `damage_dealt` naming it): nothing here listens on the bus (performance pass,
## 2026-10-28). It names its home actor to Entities (`set_enemy`), so its decoys copy it and its
## familiars circle it, and ends them when it leaves the tree (`enemy_gone`, before the actor's
## caster closes). The team board (`Entities.board`) lets its team stagger their attacks and tells
## it where its teammates stand and how hurt they are.
##
## All timing runs in `think(actor, delta)`, called by the actor's step, so tests drive it with
## fixed deltas. Nothing here allocates per step.

const EntitiesScript := preload("res://gameplay/ai/entities.gd")

## The executor's steps (`AIBrain.State`).
const State := AIBrain.State

## The brain's timings, named here for the other code that matches them (the horde swarm).
const RETARGET_TIME: float = AIBrain.RETARGET_TIME
const GRUDGE_TIME: float = AIBrain.GRUDGE_TIME
const SIGHT: float = AIBrain.SIGHT
const CLOSE_ENOUGH: float = AIBrain.CLOSE_ENOUGH

## How it plays (null: its home actor's data's profile, else the shared default).
@export var profile: AIProfile = null

## The decoys (`Entities.lure`). Only tests set it, before the actor is added; otherwise the
## "Entities" autoload is used.
var entities: EntitiesScript = null
## The team board. Only tests set it, before the actor is added; otherwise `Entities.board`.
var board: TeamBoard = null
## The thinking (made once).
var brain: AIBrain = AIBrain.new()

## The step it is in (`AIBrain.State`).
var state: int:
	get:
		return brain.state
## What it chases (a wizard, an actor, a decoy), or null.
var target: Node2D:
	get:
		return brain.target
## The teammate that hurt it last, or null.
var grudge: Node2D:
	get:
		return brain.grudge
## How often it looked for a target (tests count it).
var lookup_count: int:
	get:
		return brain.lookup_count
## The windup of the attack under way, else the one the next attack of its telegraph staff would
## take (seconds).
var windup_time: float:
	get:
		return brain.windup_time if brain.state == AIBrain.State.WINDUP else brain.windup_for(brain.telegraph_staff())
## The rest after the attack under way, else after the next attack of its telegraph staff.
var recover_time: float:
	get:
		return brain.recover_time if brain.state == AIBrain.State.RECOVER else brain.rest_for(brain.telegraph_staff())

## The actor it drives now, or null.
var _actor: Actor = null
## The actor id it named to Entities (`set_enemy`), or -1.
var _named: int = -1


func _enter_tree() -> void:
	# Back in the tree (the actor opened a new id first, as a parent enters before its children).
	if _actor != null and _actor == get_parent():
		_name_to_entities()


func _exit_tree() -> void:
	# Before the actor closes its caster and its id (children leave the tree first).
	_forget_entities()


## It starts driving `actor` (its home actor's `_ready`, or a possession): a fresh chase.
func started(actor: Actor) -> void:
	_actor = actor
	# Seeded by the actor id, so a run with the same actors repeats (and a crowd is staggered).
	brain.setup(actor, _profile_for(actor), maxi(actor.id, 0) * 7919 + 17)
	brain.entities = _entities()
	if board != null:
		brain.board = board
	else:
		brain.board = brain.entities.board if brain.entities != null else null
	if not actor.damaged.is_connected(_on_damaged):
		actor.damaged.connect(_on_damaged)
	if actor.caster != null and not actor.caster.staff_built.is_connected(_on_staff_built):
		actor.caster.staff_built.connect(_on_staff_built)
	if actor == get_parent():
		_name_to_entities()


## It stops driving `actor` (a guest took over): it forgets its target and its windup.
func stopped(actor: Actor) -> void:
	if actor.damaged.is_connected(_on_damaged):
		actor.damaged.disconnect(_on_damaged)
	if actor.caster != null and actor.caster.staff_built.is_connected(_on_staff_built):
		actor.caster.staff_built.disconnect(_on_staff_built)
	brain.reset()
	_actor = null


## Write the actor's intent for this step (`delta` seconds).
func think(actor: Actor, delta: float) -> void:
	if brain.actor != actor:
		started(actor)
	brain.think(delta, actor.intent)


## True from the start of the windup until the cast leaves: the attack is coming.
func is_telegraphing() -> bool:
	return brain.is_telegraphing()


## 0.0 at the start of the telegraph, 1.0 when the cast leaves; 0.0 when not telegraphing.
func telegraph_progress() -> float:
	return brain.telegraph_progress()


## The staff its telegraph is for (the one wound up).
func telegraph_staff() -> int:
	return brain.telegraph_staff()


## A boss's phase began: stand through its transition, then play by its profile (if it has one).
func phase_started(_actor: Actor, phase: EnemyPhase) -> void:
	brain.transition(phase.transition, phase.profile)


## Seconds the grudge still lasts (0 for none).
func grudge_left() -> float:
	return brain.grudge_left()


## A grudge carried over from the body this actor replaces (the horde swarm's promotion, which
## keeps a swarmer's grudge): it chases `attacker` for `seconds` more, as if hurt by it just now.
func carry_grudge(attacker: Node2D, seconds: float) -> void:
	brain.carry_grudge(attacker, seconds)


## `profile`, else the home actor's data's, else the shared default.
func _profile_for(actor: Actor) -> AIProfile:
	if profile != null:
		return profile
	var home: Actor = get_parent() as Actor
	for body: Actor in [home, actor]:
		if body != null and body.data != null:
			return body.data.profile_or_fallback()
	return AIProfile.fallback()


## A staff of the actor it drives was built anew.
func _on_staff_built(_at: int) -> void:
	brain.staffs_changed()


## Someone hurt the actor it drives.
func _on_damaged(caster: int, _amount: float) -> void:
	brain.hurt_by(caster)


## `entities`, else the "Entities" autoload (only in the tree).
func _entities() -> EntitiesScript:
	if entities == null and is_inside_tree():
		entities = get_node_or_null(^"/root/Entities") as EntitiesScript
	return entities if entities != null and is_instance_valid(entities) else null


## Name its home actor to Entities by its id, so its decoys copy it and its familiars circle it.
func _name_to_entities() -> void:
	if _actor == null or _actor.id < 0 or _entities() == null:
		return
	_named = _actor.id
	entities.set_enemy(_named, _actor)


## Its home actor leaves: its decoys and familiars end where they are.
func _forget_entities() -> void:
	if _named < 0:
		return
	if entities != null and is_instance_valid(entities):
		entities.enemy_gone(_named)
	_named = -1
