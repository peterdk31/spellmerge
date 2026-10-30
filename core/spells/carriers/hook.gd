class_name CarrierHook
extends Carrier
## A flying shot that pulls its caster to where it hits (`&"hook"`). Every shot card
## runs on it; its own part is the pull (`on_hit`).


## Modifier cards that do nothing on a hook, with the sentence the builder shows after
## "<Card> does nothing on a Hook: ". Every card not listed does something here.
const DOES_NOTHING: Dictionary = {}
## Trigger cards that never go off on a hook, with the sentence the builder shows.
const NEVER_FIRES: Dictionary = {}


func id() -> StringName:
	return &"hook"


func noun() -> String:
	return "hook"


func what() -> String:
	return "a hook flies out and pulls its caster to what it hits"


func traits() -> int:
	return FLIES | STAYS | HITS | LASTS | REACHES | STEERS | SPEED | SHOTS | SPREAD | PIERCE


func does_nothing() -> Dictionary:
	return DOES_NOTHING


func never_fires() -> Dictionary:
	return NEVER_FIRES


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
