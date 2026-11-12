class_name CarrierFallback
extends Carrier
## The base of the three fallback carriers (docs/CARRIERS.md, "The fallback carriers"): what the
## modifiers and infusions a group read land on when no carrier came after them (reading rule 5,
## docs/milestones/M2-staffs.md). No carrier card fires one; the compiler picks it for those cards
## (`Carriers.fallback`): the caster for the cast's own group (`CarrierCaster`), for a payload what
## fired it, a body or a shot (`CarrierBearer`), or the point it began at when nothing else can have
## (`CarrierPoint`). Otherwise it is a carrier like any other: its yes/no answers decide
## which cards do something on it, and the runtime runs it like any other (echo, mirror, recoil and
## penta all reach it the same way).
##
## What it does: one strike of everything round the point it is cast at, the caster too (self-harm
## is on), `spell.radius` wide (SpellLimits.FALLBACK_RADIUS, as a card scales it) or as wide as its
## blast. A blast on it is that strike, so it explodes there. Cards that only guard (a shield, a
## deflect) use no strike, so they make none (`uses_strike`).


func traits() -> int:
	return HITS


## No carrier card gives it a wind-down, so a card's wind-down factor has nothing to shorten.
func has_wind_down() -> bool:
	return false


## Its hits feel like an explosion (`HitProfile.kind`).
func hit_kind() -> StringName:
	return &"burst"


## Over at once: it is not aimed and reaches nowhere.
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, _source: Node, _lifetime: float, _chain: int, _prev: int) -> int:
	if not origin.is_finite():
		return 0
	var blast: float = spell.behaviour(ModifierBase.Behaviour.BLAST)
	var reach: float = maxf(spell.radius, blast)
	if blast > 0.0 and kit.events != null:
		kit.set_cue_tag(tag)
		kit.events.cue_shown.emit(actor, spell.cue_of(ModifierBase.Behaviour.BLAST), origin, Vector2.ZERO, blast, spell.tint, spell.look)
		kit.set_cue_tag(0)
	_before_strike(spell, tag, actor, origin, reach)
	if spell.strikes:
		var way: Vector2 = direction if not direction.is_zero_approx() else Vector2.RIGHT
		kit.strike_round(spell, tag, actor, origin, way, reach, spell.echo_hit if kit.is_echo(spell) else null)
	_after_strike(spell, tag, actor, origin)
	return 1


## True when a card among `modifiers` and `elements` (what landed on a fallback carrier) uses its
## strike: an infusion, or a modifier that needs more than shots to meet (a blast, a hit card, a card
## of numbers). Cards that only guard (a shield, a deflect: `MEETS_SHOTS`) strike nothing (owner,
## 2026-11-06: a lone Shield or Deflect, on you or on a decoy, costs no health), so the strike,
## which would hit the body they land on, is left out (`CompiledSpell.strikes`).
static func uses_strike(modifiers: Array[ModifierBase], elements: Array[ElementBase]) -> bool:
	if not elements.is_empty():
		return true
	for modifier in modifiers:
		var needs: Dictionary = (ModifierBase.RULES.get(modifier.behaviour, {}) as Dictionary).get("needs", {}) as Dictionary
		if int(needs.get("any", 0)) != CarrierTraits.MEETS_SHOTS:
			return true
	return false


## What it does where it lands before its strike, `reach` pixels round `at` (a deflect turns the
## shots there first, as a teleport's landing does).
func _before_strike(_spell: CompiledSpell, _tag: int, _actor: int, _at: Vector2, _reach: float) -> void:
	pass


## What it does after its strike (a shield, which the strike would otherwise spend).
func _after_strike(_spell: CompiledSpell, _tag: int, _actor: int, _at: Vector2) -> void:
	pass


## What draws its look: no look of its own (cues, or a body that is not the card's).
func look_drawer() -> int:
	return LOOK_NONE
