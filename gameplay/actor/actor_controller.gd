class_name ActorController
extends Node
## What drives an actor (actors G4, docs/milestones/M2-actors.md, "The actor"): the base of the
## player's controller (gameplay/player, the seat and its input) and the AI's (gameplay/ai). One
## controller drives an actor at a time; the actor's own is its `home_controller`, and
## `Actor.drive` hands it a guest (possess, G9).
##
## A controller only writes the actor's intent (`actor.intent`) in `think`; it never moves the
## body, casts or touches health itself. The actor's team and seat are its driver's: the actor
## table (`core/actors`) follows every change of driver.
##
## A subclass overrides `think`, and `started`/`stopped` when it keeps state about the actor it
## drives (an AI's target and windup start over when it comes back), and `set_aside` when it
## tells someone that another controller took its actor (possess, G9: the seat's panel).
##
## `driving` is the actor it drives now (null for none), kept by `Actor.drive` only: a controller
## drives at most one actor, and handing it to another takes it off the first.

const ActorsScript := preload("res://core/actors/actors.gd")

## Whom it aims at (`Actors.TEAM_WIZARDS`, `Actors.TEAM_ENEMIES`, ...). Teams are for aim only.
@export var team: int = ActorsScript.TEAM_ENEMIES
## The human seat (0-3) it is, or -1 for none (an AI).
@export var seat: int = ActorsScript.NONE

## The actor it drives now, or null. Set by `Actor.drive` (and the home actor's `_ready`) only.
var driving: Actor = null


## Write `actor.intent` for this step (`delta` seconds). The base wants nothing.
func think(_actor: Actor, _delta: float) -> void:
	pass


## It starts driving `actor` (its home actor's `_ready`, or a `drive`).
func started(_actor: Actor) -> void:
	pass


## It stops driving `actor` (a `release`, or a guest taking over).
func stopped(_actor: Actor) -> void:
	pass


## A possession took `actor`, the actor it drove, for `seconds`; it drives nothing meanwhile
## (`stopped` came first). It is handed back with `started`. The base does nothing.
func set_aside(_actor: Actor, _seconds: float) -> void:
	pass
