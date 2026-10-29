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
## drives (an AI's target and windup start over when it comes back), `set_aside` when it keeps
## state about another controller taking its actor (possess, G9), and `watch_home` when it reads
## its own body while it is away (a seat's panel shows its own wizard; owner, 2026-10-28).
##
## `driving` is the actor it drives now (null for none), kept by `Actor.drive` only: a controller
## drives at most one actor, and handing it to another takes it off the first.
##
## Possess (G9, `possession.gd`): `possessions` are the bodies it possesses, oldest first. It
## drives the oldest; the others are driven by puppets (`PuppetController`) that copy its intent.
## `home_actor` is the body whose home controller it is, and `leader()` the controller a
## possession cast from the body it drives belongs to (a puppet's is its leader's).

const ActorsScript := preload("res://core/actors/actors.gd")

## Whom it aims at (`Actors.TEAM_WIZARDS`, `Actors.TEAM_ENEMIES`, ...). Teams are for aim only.
@export var team: int = ActorsScript.TEAM_ENEMIES
## The human seat (0-3) it is, or -1 for none (an AI).
@export var seat: int = ActorsScript.NONE

## The actor it drives now, or null. Set by `Actor.drive` (and the home actor's `_ready`) only.
var driving: Actor = null
## The actor whose home controller it is (set by that actor's `_ready`), or null.
var home_actor: Actor = null
## The possessions it holds, oldest first (kept by `Possession` only).
var possessions: Array[Possession] = []


## Write `actor.intent` for this step (`delta` seconds). The base wants nothing.
func think(_actor: Actor, _delta: float) -> void:
	pass


## It starts driving `actor` (its home actor's `_ready`, or a `drive`).
func started(_actor: Actor) -> void:
	pass


## It stops driving `actor` (a `release`, or a guest taking over).
func stopped(_actor: Actor) -> void:
	pass


## True while it winds up a cast it has committed to (an AI's telegraph): the face's furious
## brows (`Face`). The base never does.
func is_telegraphing() -> bool:
	return false


## A possession took `actor`, the actor it drove, for `seconds`; it drives nothing meanwhile
## (`stopped` came first). It is handed back with `started`. The base does nothing.
func set_aside(_actor: Actor, _seconds: float) -> void:
	pass


## Called each step of `home`, the actor whose home controller this is, while it does not drive
## it (it drives another actor, or another controller drives `home`; possess). Read only: it never
## writes the intent. The base does nothing.
func watch_home(_home: Actor, _delta: float) -> void:
	pass


## The controller whose possession a hit cast from the body it drives starts: itself.
func leader() -> ActorController:
	return self


## True when `body` is one of the bodies it possesses.
func possesses(body: Actor) -> bool:
	for possession in possessions:
		if possession.target == body:
			return true
	return false


## End every possession it holds, newest first (its home body leaves the tree with it).
func end_possessions() -> void:
	for at in range(possessions.size() - 1, -1, -1):
		if at < possessions.size():
			possessions[at].end()
