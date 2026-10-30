class_name CarrierSwap
extends Carrier
## A flying shot that trades places with the body it hits (`&"swap"`). Every shot card
## runs on it; its own part is the trade (`on_hit`).


## Modifier cards that do nothing on a swap, with the sentence the builder shows after
## "<Card> does nothing on a Swap: ". Every card not listed does something here.
const DOES_NOTHING: Dictionary = {}
## Trigger cards that never go off on a swap, with the sentence the builder shows.
const NEVER_FIRES: Dictionary = {}


func id() -> StringName:
	return &"swap"


func noun() -> String:
	return "swap"


func what() -> String:
	return "a swap flies out and trades places with what it hits"


func traits() -> int:
	return FLIES | STAYS | HITS | LASTS | REACHES | STEERS | SPEED | SHOTS | SPREAD | PIERCE


func does_nothing() -> Dictionary:
	return DOES_NOTHING


func never_fires() -> Dictionary:
	return NEVER_FIRES


## A swap trades places with the target it hits: its caster's body (through its owner) or the shot
## that cast this one goes where the target was, and the target where the caster stood. A point
## cannot move, so one cast from a point moves the wizard (rules R4c). Its shield guards the move.
func on_hit(spell: CompiledSpell, tag: int, actor: int, target: Node, _position: Vector2, slot: int) -> bool:
	if rt.events == null:
		return false
	var caster: int = rt.projectiles.caster_shot_of(slot) if slot >= 0 and not rt.projectiles.is_cast_by_wizard(slot) else -1
	var node := target as Node2D
	if caster < 0:
		var anchor: Vector2 = rt.projectiles.get_anchor(actor)
		if node != null and anchor.is_finite():
			rt.events.target_move_requested.emit(actor, target, anchor)
			rt.events.caster_move_requested.emit(actor, &"swap", node.global_position, SpellLimits.SWAP_SECONDS, tag)
			rt._moves.shield(spell, tag, actor, -1, SpellLimits.SWAP_SECONDS)
	elif node != null:
		var from: Vector2 = rt.projectiles.get_position_of(caster)
		rt.events.target_move_requested.emit(actor, target, from)
		rt.projectiles.move_shot(caster, node.global_position - from, 0.0)
		rt._moves.shield(spell, tag, actor, caster, 0.0)
	return false
