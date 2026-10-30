class_name Downed
extends ActorComponent
## Downed (actors G7, docs/milestones/M2-actors.md, "The components"): the wizard's rule for 0
## health. An actor with this component is `downable`: when its Health is used up it is downed
## instead of dying (`Actor.set_down`): it stands where it fell, casts nothing, holds no orbit or
## beam, its hurtbox is off and shots fly past it, and `player_downed(seat)` is sent. A teammate
## who stays beside it long enough revives it (`coop` calls `revive(reviver)`): it stands with
## REVIVE_HEALTH and `player_revived(seat, reviver)` is sent.
##
## The seat is the one of the actor's home controller (`seat()`: the wizard's own PlayerController),
## whoever drives the body now, so a seat is downed and revived only through its own wizard.
##
## `protect(seconds)` makes the actor unhurtable for a while (`Health.protect`): flow uses
## JOIN_PROTECTION for a wizard who joins mid-run or stands up for a new wave, coop a shorter time
## after a revive. `revive_progress` from `coop` (for this seat) is kept for the revive ring the
## look draws (`revive_progress()`, 0 to 1).
##
## Nothing here allocates.

const ActorsScript := preload("res://core/actors/actors.gd")

## Health after a revive.
const REVIVE_HEALTH: float = 50.0
## Seconds a wizard who joins mid-run (or stands up for a new wave) cannot be hurt.
const JOIN_PROTECTION: float = 2.0

## How far a teammate's revive has got (0 to 1), from `revive_progress`.
var _revive_progress: float = 0.0


## The Downed component of `body`, or null. Works before `body` is in the tree.
static func of(body: Node) -> Downed:
	if body == null:
		return null
	for child in body.get_children():
		if child is Downed:
			return child as Downed
	return null


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	actor.downable = true
	if actor.health != null and not actor.health.depleted.is_connected(_on_depleted):
		actor.health.depleted.connect(_on_depleted)


func attach() -> void:
	if actor.events != null and not actor.events.revive_progress.is_connected(_on_revive_progress):
		actor.events.revive_progress.connect(_on_revive_progress)


func detach() -> void:
	if actor.events != null and is_instance_valid(actor.events) and actor.events.revive_progress.is_connected(_on_revive_progress):
		actor.events.revive_progress.disconnect(_on_revive_progress)


## The seat this body belongs to: its home controller's (-1 for none).
func seat() -> int:
	return actor.home_controller.seat if actor != null and actor.home_controller != null else ActorsScript.NONE


func is_down() -> bool:
	return actor != null and actor.is_down()


## How far a teammate's revive has got, 0 to 1 (0 when standing).
func revive_progress() -> float:
	return _revive_progress


## Bring the downed actor back with REVIVE_HEALTH; `reviver` is the seat of the teammate who did
## it. Returns false if it was not down.
func revive(reviver: int) -> bool:
	if not is_down():
		return false
	actor.set_down(false)
	_revive_progress = 0.0
	if actor.health != null:
		actor.health.reset(REVIVE_HEALTH)
	if actor.events != null:
		actor.events.player_revived.emit(seat(), reviver)
	return true


## Cannot be hurt for `seconds` (at least what is left). A downed actor stays as it is.
func protect(seconds: float) -> void:
	if not is_down() and actor.health != null:
		actor.health.protect(seconds)


func _on_depleted(_killer: int) -> void:
	if is_down():
		return
	actor.set_down(true)
	_revive_progress = 0.0
	if actor.events != null:
		actor.events.player_downed.emit(seat())


func _on_revive_progress(player: int, progress: float) -> void:
	if player == seat():
		_revive_progress = clampf(progress, 0.0, 1.0)
