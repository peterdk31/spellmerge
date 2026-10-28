class_name Hurtbox
extends ActorComponent
## The hurtbox (actors G4, docs/milestones/M2-actors.md, "The components"): the circle where an
## actor can be hit, `radius` pixels round `offset` from its feet (the drawn body). It registers
## the actor with Combat (`register_actor`: its health, this circle and its Contact's damage),
## which makes it a target every spell can hit, and forgets it when the actor leaves the tree.
## While the actor is down the hurtbox is off (shots fly past to the standing ones) and comes
## back when it stands up.
##
## Combat keeps the actor's row under its actor id (actors G5): its hits go to its Health, its
## statuses and push are read back by the Mover; the hurtbox owner (whose own spells pass it) is
## the actor id, set again by the Caster.

## Radius of the hurt circle in pixels (an imp 11, a wizard 8).
@export var radius: float = 8.0
## Where the circle's centre is, from the feet.
@export var offset: Vector2 = Vector2(0.0, -12.0)

## True while the actor is registered with Combat.
var _on: bool = false


func attach() -> void:
	if not actor.is_down():
		_register()


func detach() -> void:
	_unregister()


## Off while the actor is down, on again when it stands (the actor calls it each step).
func step() -> void:
	var down: bool = actor.is_down()
	if down and _on:
		_unregister()
	elif not down and not _on:
		_register()


## True while the hurtbox can be hit.
func is_on() -> bool:
	return _on


func _register() -> void:
	if actor.combat == null:
		return
	var health: int = actor.health.health if actor.health != null else 1
	var touch: int = actor.contact.damage if actor.contact != null else 0
	actor.combat.register_actor(actor, maxi(health, 1), radius, touch, offset)
	_on = true
	if actor.caster != null:
		actor.caster.own_hurtbox()


func _unregister() -> void:
	if _on and actor.combat != null and is_instance_valid(actor.combat):
		actor.combat.unregister_actor(actor)
	_on = false
