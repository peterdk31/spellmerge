class_name CarrierDecoy
extends CarrierEntity
## A still copy of its caster that enemies target, for `lifetime` seconds (`&"decoy"`).
## It hits nothing itself: only a blast carries hit cards and infusions; its shield or deflect
## guards it.


func id() -> StringName:
	return &"decoy"


func traits() -> int:
	return LASTS | GUARDS | SPEED | SHOTS | SPREAD | MEETS_SHOTS


## The shield charges of the decoy with `tag`, and whether it deflects (rules R4g), for Entities as
## it makes one; none for a tag no build knows.
func decoy_shield(tag: int) -> int:
	var spell: CompiledSpell = rt._profiles.get(tag)
	return roundi(spell.behaviour(ModifierBase.Behaviour.SHIELD)) if spell != null else 0


func decoy_deflects(tag: int) -> bool:
	var spell: CompiledSpell = rt._profiles.get(tag)
	return spell != null and spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0


## A decoy's guard (rules R4g), asked by Entities every step for each decoy with a shield or
## deflect: the shots of other teams than `actor`'s within `reach` of `at` are deflected outward
## by the decoy with `tag` when it deflects, else stopped while its `charges` last, each sending
## its block (`on block`); the one guard of swings and slams (`_guard`). Returns the charges left.
func guard_decoy(actor: int, tag: int, at: Vector2, reach: float, charges: int) -> int:
	var spell: CompiledSpell = rt._profiles.get(tag)
	if spell == null or rt.projectiles == null:
		return charges
	var deflects: bool = spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0
	if not deflects and charges <= 0:
		return charges
	var found: int = rt.projectiles.shots_in_wedge(actor, at, Vector2.RIGHT, 1, -PI, PI, reach)
	return rt._guard(found, actor, tag, deflects, charges, at, Vector2.INF, &"decoy")
