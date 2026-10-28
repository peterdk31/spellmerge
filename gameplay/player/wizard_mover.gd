class_name WizardMover
extends Mover
## The wizard's mover until Combat works by actor id (actors G7; part G5 makes the kit's Mover
## enough, and wizard.tscn then uses it): Combat keeps a wizard's statuses and pushes in its home
## seat's slot (see WizardHurtbox), so the pace and the push are asked by that seat. Everything
## else is the kit's Mover.

func _pace() -> float:
	return actor.combat.wizard_speed_factor(_slot()) if actor.combat != null else 1.0


func _push(delta: float) -> Vector2:
	return actor.combat.consume_wizard_knockback(_slot(), delta) if actor.combat != null else Vector2.ZERO


## The seat slot: the home controller's seat, or -1 (Combat answers "free, no push" for it).
func _slot() -> int:
	return actor.home_controller.seat if actor.home_controller != null else -1
