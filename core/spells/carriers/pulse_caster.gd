class_name CarrierPulseCaster
extends CarrierPulseBearer
## The Pulse card's carrier in a cast's own group (`&"pulse"`, the id the card names;
## docs/CARRIERS.md, "Pulse: a strike round what casts it"): one strike round the caster's hand that
## spares the caster, then round the caster's body while it lasts. Since it is on the caster (any
## actor, a wizard, an enemy or a prop) it meets the shots that reach it: a shield on it is the
## caster's barrier, a deflect turns the shots round the caster as it is cast. The same rule as a
## payload's Pulse round the body that fired it (`CarrierPulseBearer`); its look and staff animation
## are the card's (a cast on yourself, `cast_self`).


func id() -> StringName:
	return &"pulse"


## A cast's own Pulse adds its card's wind-down to its staff, as any carrier.
func has_wind_down() -> bool:
	return true


## A deflect turns the shots of other teams within its strike, or within MOVE_GUARD_REACH (a
## teleport's landing) when that is wider, before the strike: round the caster, and round each
## point of a ring of copies (penta), which strike there too.
func _before_strike(spell: CompiledSpell, tag: int, actor: int, at: Vector2, reach: float) -> void:
	if spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0 and kit.projectiles != null:
		kit.turn_shots_round(actor, tag, at, reach, id())
