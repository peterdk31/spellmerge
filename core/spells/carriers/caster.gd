class_name CarrierCaster
extends CarrierFallback
## The fallback carrier of a cast's own group (`&"caster"`, docs/CARRIERS.md): the modifiers and
## infusions left with no carrier after them land on the caster. It strikes round the caster's hand
## (`CarrierFallback`), and since it is on the caster (any actor, a wizard or an enemy) it meets the
## shots that reach it: a shield on it is the caster's barrier, a deflect turns the shots round the caster as it is cast.


func id() -> StringName:
	return &"caster"


func traits() -> int:
	return HITS | MEETS_SHOTS


## A deflect turns the shots of other teams within its strike, or within MOVE_GUARD_REACH (a
## teleport's landing) when that is wider, before the strike.
func _before_strike(spell: CompiledSpell, tag: int, actor: int, at: Vector2, reach: float) -> void:
	if spell.behaviour(ModifierBase.Behaviour.DEFLECT) <= 0.0 or kit.projectiles == null:
		return
	var around: float = maxf(reach, SpellLimits.MOVE_GUARD_REACH)
	kit.guard(kit.projectiles.shots_on_segment(actor, at, at, around), actor, tag, true, 0, at, at, id())


## A shield on it is a barrier on the actor whose body cast it, a wizard or an enemy (a ring of
## copies, penta, is cast by points, which have none). After the strike, which reaches the caster and
## would spend it.
func _after_strike(spell: CompiledSpell, tag: int, actor: int, _at: Vector2) -> void:
	if kit.caster() == SpellRuntime.CASTER_BODY:
		kit.moves().shield_caster(spell, tag, actor, 0.0)
