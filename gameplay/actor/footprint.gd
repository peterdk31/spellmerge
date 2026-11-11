class_name Footprint
extends ActorComponent
## The ground a body stands on (props W4, docs/milestones/props.md): a circle of `radius` round
## `offset` from its feet, or a box `size` across. Every actor has one: its scene's, or one the
## actor adds itself as it adds `Phases` (`Actor._find_components`), with the default circle.
##
## One rule, by whether the body can move (owner, 2026-11-11):
## - **A body that walks** (it has a Mover) slides along the walls as its circle (`Actor.move`,
##   `ProjectileManager.slide_body`), and lands clear of them as it (a teleport). Bodies that walk
##   part softly (Combat's push), never by their footprints.
## - **A body that cannot move** (no Mover: a prop, a training dummy) is solid ground to the bodies
##   that walk: it lays its footprint, the box when it has a `size`, else the circle, into the
##   projectile manager's ground grid (`set_footprint`) while it is in the tree and `solid`
##   (`set_solid`: a broken crate's rubble is not, W6), where it stands when it enters.
##
## Nothing else sees it: shots, rays and sight pass over it, and hit the body by its hurt circle
## as any other (a piercing shot goes on through a prop). The hurt circle is the body's own shape
## (a tree's canopy), the footprint its feet (the trunk).

const ActorsScript := preload("res://core/actors/actors.gd")

## The circle's radius in pixels: the body against the walls (a wizard 6, a mite 5).
@export var radius: float = 6.0
## A box this wide and high in place of the circle, for a body that cannot move (zero: the circle).
## A body that walks slides as its circle whatever this is.
@export var size: Vector2 = Vector2.ZERO
## Its centre, from the feet, where a body that cannot move lays it (a body that walks slides as the
## circle at its feet).
@export var offset: Vector2 = Vector2.ZERO
## Whether a body that cannot move blocks the bodies that walk (`set_solid`).
@export var solid: bool = true


func attach() -> void:
	_lay()


func detach() -> void:
	if actor.mover == null and actor.projectiles != null and is_instance_valid(actor.projectiles):
		actor.projectiles.set_footprint(actor.id, Vector2.ZERO, Vector2.ZERO, 0.0)


## Block the bodies that walk from now on (`on`), or not.
func set_solid(on: bool) -> void:
	if on == solid:
		return
	solid = on
	_lay()


## The body grew or shrank by `factor` (`Actor.set_size`): the circle, the box and its place with it.
func scale_by(factor: float) -> void:
	radius *= factor
	size *= factor
	offset *= factor
	_lay()


## What a body that cannot move lays is the projectile manager's ground, hashed there; nothing here
## differs between two bodies made alike (props W2's rest).
func at_rest() -> bool:
	return true


## Lay it where the body stands (a body that cannot move, in the tree with an id), or nothing.
func _lay() -> void:
	if actor == null or actor.mover != null or actor.projectiles == null or actor.id == ActorsScript.NONE or not actor.is_inside_tree():
		return
	if solid:
		actor.projectiles.set_footprint(actor.id, actor.global_position + offset, size, radius)
	else:
		actor.projectiles.set_footprint(actor.id, Vector2.ZERO, Vector2.ZERO, 0.0)
