class_name PuppetController
extends ActorController
## A body a controller possesses but does not sit in (possess, G9, `possession.gd`; owner,
## 2026-10-29): it wants what its `leader_controller` wants. Each step it copies the intent of the
## actor the leader drives (walk, aim direction, presses and held buttons), so the body walks the
## same way and casts its own staffs when the leader casts. While the leader drives nothing (it
## waits for its home body) the puppet stands. Its team is the leader's; it is no seat, so the
## seat stays on the one actor its leader drives. Made by the possession, and freed when the
## possession ends or the leader moves into its body.

## The controller it copies.
var leader_controller: ActorController = null


func think(actor: Actor, _delta: float) -> void:
	var by: Actor = leader_controller.driving if is_instance_valid(leader_controller) else null
	if by == null or not is_instance_valid(by):
		actor.intent.clear()
		return
	actor.intent.copy_from(by.intent)


## A hit cast from its body is its leader's possession.
func leader() -> ActorController:
	return leader_controller if is_instance_valid(leader_controller) else self
