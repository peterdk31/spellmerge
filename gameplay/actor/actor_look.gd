class_name ActorLook
extends Node2D
## The base of an actor's looks (actors G4, docs/milestones/M2-actors.md, "The components"): the
## wizard's (gameplay/player, G7) and a creature's (gameplay/ai, G6). A look reads the actor and
## draws it; it changes nothing the game plays by. The actor calls `setup` once in its `_ready`
## and `step` last in every step, after the body's velocity is set; a look has no process
## callback of its own.

## The actor this look draws (set by `setup`).
var actor: Actor = null


func setup(owner_actor: Actor) -> void:
	actor = owner_actor


## Draw the actor as it is after this step (`delta` seconds). The base draws nothing.
func step(_delta: float) -> void:
	pass
