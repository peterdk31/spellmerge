class_name WizardHurtbox
extends Hurtbox
## The wizard's hurtbox until Combat works by actor id (actors G7; part G5 makes the kit's Hurtbox
## enough, and wizard.tscn then uses it). Today Combat keeps wizards apart from enemies, in four
## seat slots, with the rules only a wizard has (barriers, its statuses, `downed_note`, enemies'
## touch), and the kit's `register_actor` puts an actor on the enemies' model (which would count
## the wizard as an enemy and free it at 0 health). So this one registers the actor in its home
## seat's slot (`Combat.register_player`) with the same circle, and forgets it when it leaves.
##
## Combat's seat slots take a downed wizard's target off and put it back on revive themselves
## (`player_downed`, `player_revived`), so `step` leaves it registered while down.

func step() -> void:
	pass


func _register() -> void:
	var slot: int = _slot()
	if actor.combat == null or slot < 0:
		return
	actor.combat.register_player(slot, actor, radius, offset)
	_on = true
	if actor.caster != null:
		actor.caster.own_hurtbox()


func _unregister() -> void:
	var slot: int = _slot()
	if _on and slot >= 0 and actor.combat != null and is_instance_valid(actor.combat) and actor.combat.wizard_of(slot) == actor:
		actor.combat.unregister_player(slot)
	_on = false


## The seat slot: the home controller's seat (0-3), or -1.
func _slot() -> int:
	var seat: int = actor.home_controller.seat if actor.home_controller != null else -1
	return seat if seat >= 0 and seat < 4 else -1
