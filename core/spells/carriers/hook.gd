class_name CarrierHook
extends Carrier
## A flying shot that pulls its caster to where it hits (`&"hook"`). Every shot card
## runs on it; its own part is the pull (`on_hit`).


## Each modifier behaviour (`ModifierBase.Behaviour`) on the hook, every one (keys: see `Carrier`).
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
## Each trigger (`TriggerBase.Event`) on the hook: "fires" (does it ever go off here?) and, when it
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
## An infusion (an element card) on the hook, with the same keys as a behaviour.
const INFUSIONS: Dictionary = {"works": Works.YES, "shows": Shows.DRAWN}


func id() -> StringName:
	return &"hook"


func noun() -> String:
	return "hook"


func what() -> String:
	return "a hook flies out and pulls its caster to what it hits"


func traits() -> int:
	return FLIES | STAYS | HITS | LASTS | REACHES | STEERS | SPEED | SHOTS | SPREAD | PIERCE


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Dictionary:
	return INFUSIONS


## A hook pulls its caster to the hit (rules R4a): the body, through its owner, or the shot that
## cast this one; a point cannot move, so one cast from a point moves the wizard (rules R4c). Its
## shield guards the move (`CasterMoves.shield`). Where it ends is its shot's: where what it pulls
## arrives when this hit spent the shot; a shot with pierce left flies on and ends by itself.
func on_hit(spell: CompiledSpell, tag: int, actor: int, _target: Node, position: Vector2, slot: int) -> bool:
	var caster: int = rt.projectiles.caster_shot_of(slot) if slot >= 0 and not rt.projectiles.is_cast_by_wizard(slot) else -1
	var spent: bool = slot < 0 or not rt.projectiles.is_alive(slot)
	if caster < 0 and rt.events != null:
		var anchor: Vector2 = rt.projectiles.get_anchor(actor)
		rt._moves.move_heading[actor] = anchor.direction_to(position) if anchor.is_finite() and not anchor.is_equal_approx(position) else Vector2.RIGHT
		rt.events.caster_move_requested.emit(actor, &"hook", position, SpellLimits.HOOK_SECONDS, tag)
		# After the request: a hook move it replaced was answered with the old value.
		rt._moves.hook_ends[actor] = 1 if spent else 0
		rt._moves.shield(spell, tag, actor, -1, SpellLimits.HOOK_SECONDS)
		return true
	if caster >= 0:
		var from: Vector2 = rt.projectiles.get_position_of(caster)
		if rt.projectiles.move_shot(caster, position - from, SpellLimits.HOOK_SECONDS):
			rt._moves.shield(spell, tag, actor, caster, SpellLimits.HOOK_SECONDS)
			if spent:
				rt._moves.track(caster, tag, SpellLimits.HOOK_SECONDS, from.direction_to(position))
			return true
	return false
