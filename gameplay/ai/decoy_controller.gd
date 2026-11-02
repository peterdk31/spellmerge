class_name DecoyController
extends ActorController
## A decoy's controller (`Entities`): the decoy aims itself. It aims at the nearest standing actor
## of another team it can see (`AIBrain.nearest_foe`, the AI's own look, then the nearest with a
## clear line, `AISight.line_clear`, among SIGHT_CHECKS of the nearer ones; the nearest when none is
## in view), again every `AIBrain.RETARGET_TIME` or at once when its target is gone, so what the
## decoy's triggers fire goes at its foes (a payload fired from an actor's body goes along that
## actor's aim). It walks only when its card homes (`reach` above 0): toward its target while the
## target is within `reach`, at its Mover's speed (`SpellLimits.HOMING_DRIFT`: a homing decoy
## creeps as a homing rune does). It casts nothing of its own, so it winds up nothing: only the
## casts an AI presses are telegraphed (owner, 2026-11-02), and what its triggers fire is the
## card's, on the card's clock. Nothing here allocates per step.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## How many of the nearer foes it checks for a clear line in each of the AI's rings
## (`AIBrain.LOOKS`) when the nearest is behind a wall.
const SIGHT_CHECKS: int = 8

## How far a target may be for it to creep toward it (its card's homing reach); 0: it stands.
var reach: float = 0.0
## What it aims at, or null.
var target: Node2D = null
var _retarget_left: float = 0.0
## The foes near it and their hit circles (`Projectiles.targets_near`), reused.
var _found: Array[Node2D] = []
var _centres: PackedVector2Array = PackedVector2Array()
var _radii: PackedFloat32Array = PackedFloat32Array()


## A fresh start (placed again): no target and no intent left from its last life; it looks at its
## first step and aims the way it was placed until it finds a foe.
func started(actor: Actor) -> void:
	target = null
	_retarget_left = 0.0
	actor.intent.clear()


func think(actor: Actor, delta: float) -> void:
	actor.intent.move = Vector2.ZERO
	_retarget_left -= delta
	if _retarget_left <= 0.0 or (target != null and not AIBrain.can_target(target)):
		_retarget_left = AIBrain.RETARGET_TIME
		target = _pick(actor)
	if target == null:
		return
	var to: Vector2 = target.global_position - actor.global_position
	if to.is_zero_approx():
		return
	actor.intent.aim = to
	if reach > 0.0 and to.length_squared() <= reach * reach and to.length_squared() > AIBrain.CLOSE_ENOUGH * AIBrain.CLOSE_ENOUGH:
		actor.intent.move = to.normalized()


## The nearest foe it can see, else the nearest (its shots may still bounce or bend round).
func _pick(actor: Actor) -> Node2D:
	var nearest: Node2D = AIBrain.nearest_foe(actor)
	var projectiles: ProjectilesScript = actor.projectiles
	if nearest == null or projectiles == null:
		return nearest
	var from: Vector2 = actor.global_position + actor.body_offset
	if AISight.line_clear(projectiles, from, projectiles.nearest_point):
		return nearest
	for ring: float in AIBrain.LOOKS:
		var count: int = projectiles.targets_near(from, ring, ProjectilesScript.ACTOR_LAYERS, actor.team(), _found, _centres, _radii)
		for check in mini(count, SIGHT_CHECKS):
			# The nearest not yet checked (each checked one is moved out of the way).
			var best: int = -1
			for i in count:
				if _centres[i].is_finite() and (best < 0 or _centres[i].distance_squared_to(from) < _centres[best].distance_squared_to(from)):
					best = i
			if best < 0:
				break
			var centre: Vector2 = _centres[best]
			_centres[best] = Vector2.INF
			if _found[best] != actor and AIBrain.can_target(_found[best]) and AISight.line_clear(projectiles, from, centre):
				return _found[best]
	return nearest
