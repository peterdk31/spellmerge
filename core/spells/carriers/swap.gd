class_name CarrierSwap
extends Carrier
## A flying shot that trades places with the body it hits (`&"swap"`). Every shot card
## runs on it; its own part is the trade (`on_hit`).


func id() -> StringName:
	return &"swap"


func traits() -> int:
	return FLIES | STAYS | HITS | LASTS | REACHES | STEERS | SPEED | SHOTS | SPREAD | PIERCE | MOVES | MEETS_SHOTS | CASTS_FROM_SHOT


## A swap trades places with the target it hits: what cast it (`CasterMoves.moved_by`: the body
## that cast it, through its owner, or the shot that cast this one) goes where the target was, and
## the target where it stood. A point cannot move, so one cast from a point moves the wizard (rules
## R4c). Its shield guards the move.
func on_hit(spell: CompiledSpell, tag: int, actor: int, target: Node, _position: Vector2, slot: int) -> void:
	if kit.events == null:
		return
	var moved: int = CasterMoves.moved_by(kit.shot_caster(slot) if slot >= 0 else kit.caster(), actor)
	var body: int = SpellRuntime.body_of(moved, actor)
	var node := target as Node2D
	if node == null:
		return
	# Where the target stood, read before it is moved: a body moves the moment it hears the request.
	var there: Vector2 = node.global_position
	var from: Vector2 = kit.projectiles.get_anchor(body) if body >= 0 else kit.projectiles.get_position_of(moved)
	if not from.is_finite():
		return
	kit.events.target_move_requested.emit(actor, target, from)
	if body >= 0:
		kit.events.caster_move_requested.emit(body, &"swap", there - from, SpellLimits.SWAP_SECONDS, tag)
		kit.moves().shield(spell, tag, body, -1, SpellLimits.SWAP_SECONDS)
	else:
		kit.projectiles.move_shot(moved, there - from, 0.0)
		kit.moves().shield(spell, tag, -1, moved, 0.0)
	# The trade shows at both of its ends, each facing the other.
	var apart: float = from.distance_to(there)
	kit.events.carrier_shown.emit(actor, spell.carrier_card_id, from, from.direction_to(there), apart, spell.tint, spell.look)
	kit.events.carrier_shown.emit(actor, spell.carrier_card_id, there, there.direction_to(from), apart, spell.tint, spell.look)
