class_name CarrierSwap
extends Carrier
## A flying shot that trades places with the body it hits (`FormBase.Motion.SWAP`). Every shot card
## runs on it; its own part is the trade (`on_hit`).


## How the swap takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Use.RUNS, Look.SHOWN],
	B.HOMING: [Use.RUNS, Look.SHOWN],
	B.CHAIN: [Use.RUNS, Look.SHOWN],
	B.SHIELD: [Use.RUNS, Look.SHOWN],
	B.BLAST: [Use.RUNS, Look.CUE],
	B.HOLD: [Use.RUNS, Look.SHOWN],
	B.RECOIL: [Use.RUNS, Look.SHOWN],
	B.BOUNCE: [Use.RUNS, Look.SHOWN],
	B.ECHO: [Use.RUNS, Look.SHOWN],
	B.LINGER: [Use.RUNS, Look.SHOWN],
	B.HEAVY: [Use.RUNS, Look.SHOWN],
	B.SIPHON: [Use.RUNS, Look.SHOWN],
	B.STICKY: [Use.RUNS, Look.SHOWN],
	B.MAGNET: [Use.RUNS, Look.SHOWN],
	B.GHOST: [Use.RUNS, Look.SHOWN],
	B.SPIRAL: [Use.RUNS, Look.SHOWN],
	B.MIRROR: [Use.RUNS, Look.SHOWN],
	B.GROWTH: [Use.RUNS, Look.SHOWN],
	B.RELAY: [Use.RUNS, Look.SHOWN],
	B.RETURN: [Use.RUNS, Look.SHOWN],
	B.ARC: [Use.RUNS, Look.SHOWN],
	B.POSSESS: [Use.RUNS, Look.SHOWN],
	B.DEFLECT: [Use.RUNS, Look.SHOWN],
}
## When each trigger (`TriggerBase.Event`) fires on the swap: "" when it can, else why it never does.
const EVENTS: Dictionary = {
	E.HIT: "",
	E.EXPIRE: "",
	E.TIMER: "",
	E.BLOCK: "",
	E.KILL: "",
	E.CAST: "",
	E.WALL: "",
	E.HURT: "",
	E.REACTION: "",
}
## How the swap takes an infusion.
const INFUSIONS: Array = [Use.RUNS, Look.SHOWN]


func motion() -> int:
	return FormBase.Motion.SWAP


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


func infusions() -> Array:
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
			rt._shield_move(spell, tag, actor, -1, SpellLimits.SWAP_SECONDS)
	elif node != null:
		var from: Vector2 = rt.projectiles.get_position_of(caster)
		rt.events.target_move_requested.emit(actor, target, from)
		rt.projectiles.move_shot(caster, node.global_position - from, 0.0)
		rt._shield_move(spell, tag, actor, caster, 0.0)
	return false
