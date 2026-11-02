class_name DecoyController
extends ActorController
## A decoy's controller (`Entities`): the decoy aims itself. It aims at the nearest standing actor
## of another team (`AIBrain.nearest_foe`, the AI's own look, again every `AIBrain.RETARGET_TIME`
## or at once when its target is gone), so what the decoy's triggers fire goes at its foes (a
## payload fired from an actor's body goes along that actor's aim). It walks only when its card
## homes (`reach` above 0): toward its target while the target is within `reach`, at its Mover's
## speed (`SpellLimits.HOMING_DRIFT`: a homing decoy creeps as a homing rune does). It casts
## nothing of its own. Nothing here allocates per step.

## How far a target may be for it to creep toward it (its card's homing reach); 0: it stands.
var reach: float = 0.0
## What it aims at, or null.
var target: Node2D = null
var _retarget_left: float = 0.0


## A fresh start (placed again): no target, it looks at its first step.
func started(_actor: Actor) -> void:
	target = null
	_retarget_left = 0.0


func think(actor: Actor, delta: float) -> void:
	_retarget_left -= delta
	if _retarget_left <= 0.0 or (target != null and not AIBrain.can_target(target)):
		_retarget_left = AIBrain.RETARGET_TIME
		target = AIBrain.nearest_foe(actor)
	actor.intent.move = Vector2.ZERO
	if target == null:
		return
	var to: Vector2 = target.global_position - actor.global_position
	if to.is_zero_approx():
		return
	actor.intent.aim = to
	if reach > 0.0 and to.length_squared() <= reach * reach and to.length_squared() > AIBrain.CLOSE_ENOUGH * AIBrain.CLOSE_ENOUGH:
		actor.intent.move = to.normalized()
