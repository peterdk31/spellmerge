class_name AIController
extends ActorController
## The enemy AI (M1 part 12; a controller since actors G6, docs/milestones/M2-actors.md): chase
## the nearest actor of another team, then one telegraphed cast of its staff. It drives an actor
## (gameplay/actor) like a seat's controller does: it only writes the actor's intent (where to
## walk, where to aim, when to press its staff); the actor's components walk, cast, get hurt and
## die. It is a child of an enemy's actor scene (content/enemies/ember_imp/ember_imp.tscn), that
## actor's home controller; a possession (G9) may hand it another actor for a while.
##
## States: CHASE (walk to the target), WINDUP (stand still; the aim is locked at its start, so a
## wizard can step aside, while the actor's CreatureLook shows the telegraph), then the cast and
## RECOVER (stand still, the aim still locked, so a beam it holds does not track a wizard who
## stepped aside) before CHASE again.
##
## Targets: the nearest actor of another team than the actor's (`Actor.team`) that can be hit
## now, from the projectile manager's target grid (`nearest_target` with the team), so it costs
## the same in a crowd. A downed wizard is no target there (its hurt circle is off), and a decoy
## within its lure range (`Entities.lure`) is chased first; a decoy that breaks is dropped at
## once. Retargeting runs every RETARGET_TIME seconds (staggered per controller, so 200 enemies
## do not all look in one frame), at once when the target is lost, downed or dying (checked each
## step), and once at the first step. With nobody to chase it looks only every RETARGET_TIME.
##
## Grudges (infighting): when an actor of its own team hurts the actor it drives (a stray blast:
## everything hurts everything, teams only aim), it targets that actor for GRUDGE_TIME seconds,
## then goes back to its team's targets. Heard from the driven actor's own `Actor.damaged` (sent
## with every `damage_dealt` naming it), which carries the attacker's actor id for every hit (a
## shot, a touch, a reaction). Nothing here listens on the bus: a bus listener per enemy was
## called for every hit on anyone (performance pass, 2026-10-28).
##
## The attack is a cast of the actor's staff 0 (its Caster, filled from the enemy's `data`): the
## windup starts only when the next cast is ready (`Caster.cast_ready(windup_time)`: its delay
## nearly over and the mana there), so a telegraph is always followed by its cast; until then it
## holds where it stands. At the end of the windup it presses the staff (`intent.press(0)`), and
## the Caster casts from the actor's staff tip along the locked aim. An actor without a staff
## only chases, all the way, and hurts by touch (its Contact) if it hurts at all.
##
## Statuses: the actor's Mover slows its walk by Combat's pace (chill slows, freeze stops); the
## windup and recovery timers here slow by the same pace, so a frozen enemy's attack waits.
##
## Entities: it names the actor it drives at home to Entities (`set_enemy`), so its decoys copy
## it and its familiars circle it, and ends them when it leaves the tree (`enemy_gone`, before
## the actor's caster closes, so their ends still count).
##
## All timing runs in `think(actor, delta)`, called by the actor's step, so tests drive it with
## fixed deltas. Nothing here allocates per step.

const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EntitiesScript := preload("res://gameplay/ai/entities.gd")

enum State { CHASE, WINDUP, RECOVER }

## Seconds between looking for the nearest target again.
const RETARGET_TIME: float = 0.5
## Seconds it chases a teammate that hurt it before going back to its team's targets.
const GRUDGE_TIME: float = 3.0
## How far it looks for a target: farther than any room, so the nearest anywhere.
const SIGHT: float = 100000.0
## Closer than this to its target it stops walking (an enemy without a staff, on top of it).
const CLOSE_ENOUGH: float = 1.0

## Walk until the target is this close, then start the attack.
@export var attack_range: float = 90.0
## Seconds the telegraph shows before the cast.
@export var windup_time: float = 0.75
## Seconds standing still after the cast.
@export var recover_time: float = 1.0

## The decoys (`Entities.lure`). Only tests set it, before the actor is added; otherwise the
## "Entities" autoload is used.
var entities: EntitiesScript = null

var state: State = State.CHASE
## What it chases (a wizard, an actor, a decoy), or null.
var target: Node2D = null
## The teammate that hurt it last, chased while `grudge_left()` > 0, or null.
var grudge: Node2D = null
## How often it looked for a target (tests count it).
var lookup_count: int = 0

## The actor it drives now, or null.
var _actor: Actor = null
## The aim locked at the start of the windup (unit length).
var _locked_aim: Vector2 = Vector2.DOWN
var _state_left: float = 0.0
var _retarget_left: float = 0.0
var _retarget_offset: float = 0.0
var _grudge_left: float = 0.0
var _looked: bool = false
## Instance id of `target` when it was chosen, or 0 for none.
var _target_id: int = 0
## `target` typed, when it is an actor (most are): the step's "still there?" check is cheaper.
var _target_actor: Actor = null
## The actor id it named to Entities (`set_enemy`), or -1.
var _named: int = -1


func _ready() -> void:
	# Spread retargeting over the half second so 200 enemies do not all look at once.
	_retarget_offset = RETARGET_TIME * float(get_instance_id() % 8) / 8.0


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
	_reset()
	if not actor.damaged.is_connected(_on_damaged):
		actor.damaged.connect(_on_damaged)
	if actor == get_parent():
		_name_to_entities()


## It stops driving `actor` (a guest took over): it forgets its target and its windup.
func stopped(actor: Actor) -> void:
	if actor.damaged.is_connected(_on_damaged):
		actor.damaged.disconnect(_on_damaged)
	_reset()
	_actor = null


## Write the actor's intent for this step (`delta` seconds): look, chase, wind up, cast, recover.
func think(actor: Actor, delta: float) -> void:
	_retarget_left -= delta
	if _grudge_left > 0.0:
		_grudge_left -= delta
		if _grudge_left <= 0.0 or not _is_valid_target(grudge):
			# The grudge is over: back to its team's targets at once.
			_drop_grudge()
	# Look on the timer, at the first step (staggered afterwards) or when the target was just
	# lost. With no target at all only the timer applies. A freed target reads as null, so the
	# id tells "never had one" from "lost it".
	var lost: bool = false
	if _target_id != 0:
		if _target_actor != null:
			# `_is_valid_target`, written out for the usual target (this runs every step).
			lost = not is_instance_valid(_target_actor) or _target_actor.is_down() or _target_actor.is_dying()
		else:
			lost = not _is_valid_target(target)
	if _retarget_left <= 0.0 or lost or not _looked:
		_retarget_left = RETARGET_TIME if _looked else _retarget_offset
		_looked = true
		target = _find_target(actor)
		_target_id = target.get_instance_id() if target != null else 0
		_target_actor = target as Actor
	var intent: ActorIntent = actor.intent
	intent.move = Vector2.ZERO
	match state:
		State.CHASE:
			_chase(actor)
		State.WINDUP:
			intent.aim = _locked_aim
			_state_left -= delta * _pace(actor)
			if _state_left <= 0.0:
				# The cast leaves this step, from the staff tip along the locked aim.
				intent.press(0)
				state = State.RECOVER
				_state_left = recover_time
		State.RECOVER:
			intent.aim = _locked_aim
			_state_left -= delta * _pace(actor)
			if _state_left <= 0.0:
				state = State.CHASE


## True from the start of the windup until the cast leaves: the attack is coming.
func is_telegraphing() -> bool:
	return state == State.WINDUP


## 0.0 at the start of the telegraph, 1.0 when the cast leaves; 0.0 when not telegraphing.
func telegraph_progress() -> float:
	if state != State.WINDUP or windup_time <= 0.0:
		return 0.0
	return clampf(1.0 - _state_left / windup_time, 0.0, 1.0)


## Seconds the grudge still lasts (0 for none).
func grudge_left() -> float:
	return maxf(_grudge_left, 0.0) if grudge != null else 0.0


## Walk to the target; in reach, aim at it and wind up when the next cast is ready.
func _chase(actor: Actor) -> void:
	if target == null:
		return
	var to_target: Vector2 = target.global_position - actor.global_position
	var near: bool = to_target.length_squared() <= attack_range * attack_range
	if to_target != Vector2.ZERO:
		actor.intent.aim = to_target
	if near and actor.caster != null and actor.caster.has_staff(0):
		if not actor.caster.cast_ready(windup_time):
			# In reach but the cast is not ready: hold, so the telegraph only ever shows a cast
			# that comes.
			return
		state = State.WINDUP
		_state_left = windup_time
		_locked_aim = to_target.normalized() if to_target != Vector2.ZERO else actor.aim
		actor.intent.aim = _locked_aim
		return
	# Out of reach, or nothing to cast: walk on (one without a staff walks into its target).
	if to_target.length_squared() > CLOSE_ENOUGH * CLOSE_ENOUGH:
		actor.intent.move = to_target.normalized()


## The grudge, else a decoy in lure range, else the nearest standing actor of another team.
func _find_target(actor: Actor) -> Node2D:
	lookup_count += 1
	if grudge != null and _grudge_left > 0.0:
		return grudge
	var here: Vector2 = actor.global_position
	var decoy: Node2D = _entities().lure(here) if _entities() != null else null
	if decoy != null:
		return decoy
	if actor.projectiles == null:
		return null
	var found: Node2D = actor.projectiles.nearest_target(here + actor.body_offset, SIGHT, ProjectileManagerScript.ACTOR_LAYERS, actor, null, actor.team())
	return found if _is_valid_target(found) else null


## A freed node may still sit in `target` or `grudge`, hence the Variant. A downed wizard, a down
## actor and one that is dying are no targets.
func _is_valid_target(node: Variant) -> bool:
	if not is_instance_valid(node):
		return false
	if node is Actor:
		var other: Actor = node as Actor
		return not other.is_down() and not other.is_dying()
	return not (node.has_method("is_downed") and node.is_downed())


## Chill slows the attack timers, freeze stops them (the Mover slows the walk by the same pace).
## Only the windup and the recovery ask.
func _pace(actor: Actor) -> float:
	return actor.combat.own_pace(actor, actor.id) if actor.combat != null else 1.0


## Someone hurt the actor it drives: an actor of its own team (not itself) earns a grudge.
func _on_damaged(caster: int, _amount: float) -> void:
	if _actor == null or caster < 0 or caster == _actor.id or _actor.actors == null:
		return
	if _actor.actors.team_of(caster) != _actor.team():
		return
	var attacker: Node2D = _actor.actors.node_of(caster) as Node2D
	if attacker == null or attacker == _actor or not _is_valid_target(attacker):
		return
	grudge = attacker
	_grudge_left = GRUDGE_TIME
	# Turn on it at the next step.
	_retarget_left = 0.0


## A grudge carried over from the body this actor replaces (the horde swarm's promotion, which
## keeps a swarmer's grudge): it chases `attacker` for `seconds` more, as if hurt by it just now.
func carry_grudge(attacker: Node2D, seconds: float) -> void:
	if seconds <= 0.0 or not _is_valid_target(attacker):
		return
	grudge = attacker
	_grudge_left = seconds
	_retarget_left = 0.0


func _drop_grudge() -> void:
	grudge = null
	_grudge_left = 0.0
	_retarget_left = 0.0


## A fresh chase: no target, no grudge, no windup.
func _reset() -> void:
	state = State.CHASE
	target = null
	_target_id = 0
	_target_actor = null
	grudge = null
	_grudge_left = 0.0
	_state_left = 0.0
	_looked = false
	_retarget_left = _retarget_offset


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
