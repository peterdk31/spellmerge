class_name CarrierBearer
extends CarrierFallback
## The fallback carrier of a payload that a body or a live shot may cast (`&"bearer"`,
## docs/CARRIERS.md "The fallback carriers"): the modifiers and infusions it read with no carrier
## after them land on whatever fired it (owner, 2026-11-06). Which that may be is the compiler's
## to know (`Carrier.payload_cast_by`); which it is, the runtime's (`CarrierKit.caster_body`,
## `caster_shot`):
## - **a body** (a decoy's own; the wizard's, for a dash's timer or end, an `on cast`): the strike
##   is round it, a shield is a barrier on that body's actor and a deflect turns the shots round it
##   once, as it lands, as on the caster (`CarrierCaster`);
## - **a shot** (a bolt's timer, a piercing bolt's hit): the strike is round it, a shield adds that
##   many shield charges to the shot, a deflect makes it deflect while it lives, as a move's shield
##   does to the shot it moves (`CasterMoves.shield`);
## - **nothing** (that shot has ended, that body has gone): it strikes round the point, as
##   `CarrierPoint` does, and a shield or deflect has no one to guard.
## The payload's actor stays the wizard (its hits, budget, colours and tag); only where its cards
## land is the bearer's.


func id() -> StringName:
	return &"bearer"


func traits() -> int:
	return HITS | MEETS_SHOTS


## A deflect turns the shots of other teams round a body (within its strike, or MOVE_GUARD_REACH
## when that is wider), or makes the shot deflect, before the strike.
func _before_strike(spell: CompiledSpell, tag: int, actor: int, at: Vector2, reach: float) -> void:
	if spell.behaviour(ModifierBase.Behaviour.DEFLECT) <= 0.0 or kit.projectiles == null:
		return
	if kit.caster_body(actor) >= 0:
		kit.turn_shots_round(actor, tag, at, reach, id())
		return
	var shot: int = kit.caster_shot()
	if shot >= 0:
		kit.projectiles.set_deflect(shot, true)


## A shield is a barrier on the body's actor, or charges on the shot (after the strike, which
## reaches the body and would spend it).
func _after_strike(spell: CompiledSpell, tag: int, actor: int, _at: Vector2) -> void:
	var body: int = kit.caster_body(actor)
	if body >= 0:
		kit.moves().shield_caster(spell, tag, body, 0.0)
		return
	var shot: int = kit.caster_shot()
	if shot >= 0:
		kit.moves().shield(spell, tag, actor, shot, 0.0)
