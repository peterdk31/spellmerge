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
	if rt.events == null:
		return
	var caster: int = rt.projectiles.caster_shot_of(slot) if slot >= 0 and not rt.projectiles.is_cast_by_wizard(slot) else -1
	var node := target as Node2D
	if caster < 0:
		var anchor: Vector2 = rt.projectiles.get_anchor(actor)
		if node != null and anchor.is_finite():
			rt.events.target_move_requested.emit(actor, target, anchor)
			rt.events.caster_move_requested.emit(actor, &"swap", node.global_position - anchor, SpellLimits.SWAP_SECONDS, tag)
			rt._moves.shield(spell, tag, actor, -1, SpellLimits.SWAP_SECONDS)
	elif node != null:
		var from: Vector2 = rt.projectiles.get_position_of(caster)
		rt.events.target_move_requested.emit(actor, target, from)
		rt.projectiles.move_shot(caster, node.global_position - from, 0.0)
		rt._moves.shield(spell, tag, actor, caster, 0.0)
