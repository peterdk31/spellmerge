class_name CarrierSwap
extends Carrier
## A flying shot that trades places with the body it hits (`&"swap"`). Every shot card
## runs on it; its own part is the trade (`on_hit`).


func id() -> StringName:
	return &"swap"


func traits() -> int:
	return FLIES | STAYS | HITS | LASTS | REACHES | STEERS | SPEED | SHOTS | SPREAD | PIERCE | MOVES | MEETS_SHOTS


## A swap trades places with the target it hits: its caster's body (through its owner) or the shot
## that cast this one goes where the target was, and the target where the caster stood. A point
## cannot move, so one cast from a point moves the wizard (rules R4c). Its shield guards the move.
func on_hit(spell: CompiledSpell, tag: int, actor: int, target: Node, _position: Vector2, slot: int) -> void:
	if kit.events == null:
		return
	var caster: int = kit.projectiles.caster_shot_of(slot) if slot >= 0 and not kit.projectiles.is_cast_by_wizard(slot) else -1
	var node := target as Node2D
	if node == null:
		return
	# Where the target stood, read before it is moved: a body moves the moment it hears the request.
	var there: Vector2 = node.global_position
	var from: Vector2 = kit.projectiles.get_anchor(actor) if caster < 0 else kit.projectiles.get_position_of(caster)
	if not from.is_finite():
		return
	if caster < 0:
		kit.events.target_move_requested.emit(actor, target, from)
		kit.events.caster_move_requested.emit(actor, &"swap", there - from, SpellLimits.SWAP_SECONDS, tag)
		kit.moves().shield(spell, tag, actor, -1, SpellLimits.SWAP_SECONDS)
	else:
		kit.events.target_move_requested.emit(actor, target, from)
		kit.projectiles.move_shot(caster, there - from, 0.0)
		kit.moves().shield(spell, tag, actor, caster, 0.0)
	# The trade shows at both of its ends, each facing the other.
	var apart: float = from.distance_to(there)
	kit.events.form_shown.emit(actor, spell.form_id, from, from.direction_to(there), apart, spell.tint, spell.look)
	kit.events.form_shown.emit(actor, spell.form_id, there, there.direction_to(from), apart, spell.tint, spell.look)
