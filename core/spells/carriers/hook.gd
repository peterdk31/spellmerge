class_name CarrierHook
extends Carrier
## A flying shot that pulls its caster to where it hits (`FormBase.Motion.HOOK`). Every shot card
## runs on it; its own part is the pull (`on_hit`).


## How the hook takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
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
## When each trigger (`TriggerBase.Event`) fires on the hook: "" when it can, else why it never does.
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
## How the hook takes an infusion.
const INFUSIONS: Array = [Use.RUNS, Look.SHOWN]


func motion() -> int:
	return FormBase.Motion.HOOK


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


func infusions() -> Array:
	return INFUSIONS


## A hook pulls its caster to the hit (rules R4a): the body, through its owner, or the shot that
## cast this one; a point cannot move, so one cast from a point moves the wizard (rules R4c). Its
## shield guards the move (`Spells._shield_move`). Where it ends is its shot's: where what it pulls
## arrives when this hit spent the shot; a shot with pierce left flies on and ends by itself.
func on_hit(spell: CompiledSpell, tag: int, actor: int, _target: Node, position: Vector2, slot: int) -> bool:
	var caster: int = rt.projectiles.caster_shot_of(slot) if slot >= 0 and not rt.projectiles.is_cast_by_wizard(slot) else -1
	var spent: bool = slot < 0 or not rt.projectiles.is_alive(slot)
	if caster < 0 and rt.events != null:
		var anchor: Vector2 = rt.projectiles.get_anchor(actor)
		rt._move_heading[actor] = anchor.direction_to(position) if anchor.is_finite() and not anchor.is_equal_approx(position) else Vector2.RIGHT
		rt.events.caster_move_requested.emit(actor, &"hook", position, SpellLimits.HOOK_SECONDS, tag)
		# After the request: a hook move it replaced was answered with the old value.
		rt._hook_ends[actor] = 1 if spent else 0
		rt._shield_move(spell, tag, actor, -1, SpellLimits.HOOK_SECONDS)
		return true
	if caster >= 0:
		var from: Vector2 = rt.projectiles.get_position_of(caster)
		if rt.projectiles.move_shot(caster, position - from, SpellLimits.HOOK_SECONDS):
			rt._shield_move(spell, tag, actor, caster, SpellLimits.HOOK_SECONDS)
			if spent:
				rt._track_move(caster, tag, SpellLimits.HOOK_SECONDS, from.direction_to(position))
			return true
	return false
