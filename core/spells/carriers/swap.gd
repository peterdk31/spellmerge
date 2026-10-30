class_name CarrierSwap
extends Carrier
## A flying shot that trades places with the body it hits (`&"swap"`). Every shot card
## runs on it; its own part is the trade (`on_hit`).


## Each modifier behaviour (`ModifierBase.Behaviour`) on the swap, every one (keys: see `Carrier`).
const BEHAVIOURS: Dictionary = {
	B.NONE: {"works": Works.YES, "shows": Shows.DRAWN},
	B.HOMING: {"works": Works.YES, "shows": Shows.DRAWN},
	B.CHAIN: {"works": Works.YES, "shows": Shows.DRAWN},
	B.SHIELD: {"works": Works.YES, "shows": Shows.DRAWN},
	B.BLAST: {"works": Works.YES, "shows": Shows.AS_EFFECT},
	B.HOLD: {"works": Works.YES, "shows": Shows.DRAWN},
	B.RECOIL: {"works": Works.YES, "shows": Shows.DRAWN},
	B.BOUNCE: {"works": Works.YES, "shows": Shows.DRAWN},
	B.ECHO: {"works": Works.YES, "shows": Shows.DRAWN},
	B.LINGER: {"works": Works.YES, "shows": Shows.DRAWN},
	B.HEAVY: {"works": Works.YES, "shows": Shows.DRAWN},
	B.SIPHON: {"works": Works.YES, "shows": Shows.DRAWN},
	B.STICKY: {"works": Works.YES, "shows": Shows.DRAWN},
	B.MAGNET: {"works": Works.YES, "shows": Shows.DRAWN},
	B.GHOST: {"works": Works.YES, "shows": Shows.DRAWN},
	B.SPIRAL: {"works": Works.YES, "shows": Shows.DRAWN},
	B.MIRROR: {"works": Works.YES, "shows": Shows.DRAWN},
	B.GROWTH: {"works": Works.YES, "shows": Shows.DRAWN},
	B.RELAY: {"works": Works.YES, "shows": Shows.DRAWN},
	B.RETURN: {"works": Works.YES, "shows": Shows.DRAWN},
	B.ARC: {"works": Works.YES, "shows": Shows.DRAWN},
	B.POSSESS: {"works": Works.YES, "shows": Shows.DRAWN},
	B.DEFLECT: {"works": Works.YES, "shows": Shows.DRAWN},
}
## Each trigger (`TriggerBase.Event`) on the swap: "fires" (does it ever go off here?) and, when it
## never does, "why_not".
const EVENTS: Dictionary = {
	E.HIT: {"fires": true},
	E.EXPIRE: {"fires": true},
	E.TIMER: {"fires": true},
	E.BLOCK: {"fires": true},
	E.KILL: {"fires": true},
	E.CAST: {"fires": true},
	E.WALL: {"fires": true},
	E.HURT: {"fires": true},
	E.REACTION: {"fires": true},
}
## An infusion (an element card) on the swap, with the same keys as a behaviour.
const INFUSIONS: Dictionary = {"works": Works.YES, "shows": Shows.DRAWN}


func id() -> StringName:
	return &"swap"


func noun() -> String:
	return "swap"


func what() -> String:
	return "a swap flies out and trades places with what it hits"


func traits() -> int:
	return FLIES | STAYS | HITS | LASTS | REACHES | STEERS | SPEED | SHOTS | SPREAD | PIERCE


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Dictionary:
	return INFUSIONS


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
