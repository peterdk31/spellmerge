class_name Footprint
extends ActorComponent
## The ground a body blocks (props W4, docs/milestones/props.md): a rectangle `size` pixels across,
## its centre `offset` from the feet, laid into the projectile manager's wall grid
## (`ProjectileManager.set_footprint`) while `blocks` is on and the actor is in the tree. Bodies
## slide along it and shots and rays end on it as on any wall; the body's own spells leave it.
##
## It is for a body that does not move (a prop: no Mover, and a body with no Mover never moves,
## `Actor.move`): it is laid where the body stands when it enters the tree, and taken out when it
## leaves. A prop's state turns it on and off (`set_blocks`: rubble blocks nothing, W6).
##
## A shot that meets it hits the body, because the body's hurt circle covers every cell it can lay
## (the step is cut at the wall, then tested for hits along what is left of it): `problems()` says
## when the circle does not, or when the body has a Mover.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

## Its width and height in pixels. The wall grid's cells (`ProjectileManager.WALL_CELL`) whose
## centres lie in it are laid: make it at least a cell across.
@export var size: Vector2 = Vector2(16.0, 16.0)
## Its centre, from the feet.
@export var offset: Vector2 = Vector2.ZERO
## Whether it blocks now (`set_blocks`).
@export var blocks: bool = true


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	for problem in problems():
		push_warning("Footprint of %s: %s" % [owner_actor.name, problem])


func attach() -> void:
	_lay()


func detach() -> void:
	if actor.projectiles != null and is_instance_valid(actor.projectiles):
		actor.projectiles.set_footprint(actor.id, Rect2())


## Block from now on (`on`), or block nothing.
func set_blocks(on: bool) -> void:
	if on == blocks:
		return
	blocks = on
	_lay()


## The world rectangle it covers where the body stands now.
func rect() -> Rect2:
	return Rect2(actor.global_position + offset - size * 0.5, size)


## What is laid lives in the projectile manager's footprints, hashed there; nothing here differs
## between two bodies made alike but `blocks`, which the manager's table shows (props W2's rest).
func at_rest() -> bool:
	return true


## What is wrong with it on its actor (empty: nothing): a Mover (the body would walk off it), or a
## hurt circle that does not cover every cell it can lay, so a shot could end on it without hitting
## the body. A body without a Hurtbox is a wall that takes no hits, which is allowed.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if actor == null:
		return found
	if actor.mover != null:
		found.append("its body has a Mover; a footprint is laid where the body stands, for a body that does not move")
	if size.x < ProjectilesScript.WALL_CELL or size.y < ProjectilesScript.WALL_CELL:
		found.append("it is %s px, under a cell (%d px) across: it may lay no cell" % [size, ProjectilesScript.WALL_CELL])
	var hurtbox: Hurtbox = actor.hurtbox
	if hurtbox != null:
		var reach: float = farthest_from(hurtbox.offset)
		if reach > hurtbox.radius:
			found.append("its cells reach %.1f px from the hurt circle's centre, past its radius %.1f: a shot could end on it without a hit" % [reach, hurtbox.radius])
	return found


## How far from `point` (from the feet) the cells it can lay reach at most: they reach half a cell
## past the rectangle (a cell whose centre is in it is laid), wherever the body stands.
func farthest_from(point: Vector2) -> float:
	var half: Vector2 = size * 0.5 + Vector2.ONE * ProjectilesScript.WALL_CELL * 0.5
	var away: Vector2 = (offset - point).abs() + half
	return away.length()


func _lay() -> void:
	if actor == null or actor.projectiles == null or actor.id == ActorsScript.NONE or not actor.is_inside_tree():
		return
	actor.projectiles.set_footprint(actor.id, rect() if blocks else Rect2())
