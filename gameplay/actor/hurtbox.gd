class_name Hurtbox
extends ActorComponent
## The hurtbox (actors G4, docs/milestones/M2-actors.md, "The components"): the shape where an
## actor can be hit, round `offset` from its feet (the drawn body): a circle of `radius`, or a box
## `size` across for a long body (props, docs/milestones/props.md: a bench, a big boss). Both are one
## shape to every hit test (`HitShape`). It registers
## the actor with Combat (`register_actor`: its health, this shape and its Contact's damage),
## which makes it a target every spell can hit, and forgets it when the actor leaves the tree.
## While the actor is down the hurtbox is off (shots fly past to the standing ones) and comes
## back when it stands up; so while it is not `enabled` (a prop's rubble, props W6).
##
## Combat keeps the actor's row under its actor id (actors G5): its hits go to its Health, its
## statuses and push are read back by the Mover; the hurtbox owner (whose own spells pass it) is
## the actor id, set again by the Caster.

## Radius of the hurt circle in pixels (an imp 11, a wizard 8).
@export var radius: float = 8.0
## A box this wide and high in place of the circle (zero: the circle).
@export var size: Vector2 = Vector2.ZERO
## Where the shape's centre is, from the feet.
@export var offset: Vector2 = Vector2(0.0, -12.0)

## Whether the shape can be hit at all (props W6: a prop's state that is not `hittable`, rubble).
## `set_enabled` while the actor is in play.
@export var enabled: bool = true

## True while the actor is registered with Combat (read only). The actor steps the hurtbox only
## while this equals its down state or its being off (something to do: register or forget it).
var registered: bool = false


func attach() -> void:
	if _wanted():
		_register()


func detach() -> void:
	_unregister()


## Off while the actor is down or the hurtbox is not `enabled`, on again when both are over (the
## actor calls it when `registered` is not what they want).
func step() -> void:
	var wanted: bool = _wanted()
	if registered and not wanted:
		_unregister()
	elif wanted and not registered:
		_register()


## Can be hit from now on (`on`), or not: registered with Combat or forgotten at once (a still body
## is never stepped).
func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	if actor != null and actor.is_inside_tree():
		step()


## True while the hurtbox can be hit.
func is_on() -> bool:
	return registered


## Half the box either way of the centre (`HitShape`'s `half`), zero for the circle.
func half() -> Vector2:
	return size * 0.5 if is_box() else Vector2.ZERO


## The circle's radius, or 0 for a box (its corners are square).
func round_radius() -> float:
	return 0.0 if is_box() else radius


## True when the shape is a box (`size` set).
func is_box() -> bool:
	return size.x > 0.0 and size.y > 0.0


## How far the shape reaches from its centre at most (`HitShape.outer_radius`: the circle's radius,
## a box's corner), for what asks how big the body is (the AI's reach, its dodging).
func outer_radius() -> float:
	return HitShape.outer_radius(half(), round_radius())


## Registered as it wants to be, as a standing actor's is (props W2: its circle follows the actor's
## size, which its `rest_leaf` holds; whether it is `enabled` follows a prop's state, which its
## `Reactions` holds).
func at_rest() -> bool:
	return registered == _wanted()


func _wanted() -> bool:
	return enabled and not actor.is_down()


func _register() -> void:
	if actor.combat == null:
		return
	var health: float = actor.health.health if actor.health != null else 1.0
	var touch: int = actor.contact.damage if actor.contact != null else 0
	actor.combat.register_actor(actor, health, round_radius(), touch, offset, half())
	registered = true
	if actor.caster != null:
		actor.caster.own_hurtbox()


func _unregister() -> void:
	if registered and actor.combat != null and is_instance_valid(actor.combat):
		actor.combat.unregister_actor(actor)
	registered = false
