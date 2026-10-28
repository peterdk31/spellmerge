class_name ActorComponent
extends Node
## The base of the actor kit's components (actors G4, docs/milestones/M2-actors.md, "The
## components"): Health, Hurtbox, Contact, Mover, Caster, and later the wizard's Downed. A
## component is a child of its actor; it has no process callback of its own (the actor steps it)
## and reaches its siblings only through `actor` (`actor.health`, `actor.caster`, ...), never by
## node path.
##
## The actor calls, in this order: `setup` once in its `_ready` (after its `data` is applied),
## then `attach` (and again each time it re-enters the tree), `detach` when it leaves the tree.
## `attach` and `detach` are where a component registers the actor with a system and forgets it.

## The actor this component belongs to (set by `setup`).
var actor: Actor = null


## Called once by the actor's `_ready`.
func setup(owner_actor: Actor) -> void:
	actor = owner_actor


## The actor is in the tree with its id open: register it with the systems.
func attach() -> void:
	pass


## The actor leaves the tree: forget it in the systems.
func detach() -> void:
	pass
