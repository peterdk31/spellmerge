class_name CarrierBolt
extends Carrier
## A shot that flies out on its own along the aim (`&"bolt"`: the bolt, and the nova, a
## bolt whose shots fan all the way round). The plain carrier: every card runs on it through the
## shot path (`Spells._apply_travel`, the projectile manager's kit).


func id() -> StringName:
	return &"bolt"


func traits() -> int:
	return FLIES | STAYS | HITS | LASTS | REACHES | GUARDS | STEERS | SPEED | SHOTS | SPREAD | PIERCE | MOVES | MEETS_SHOTS


func required_fields() -> Dictionary:
	return {
		"speed": "A bolt needs a `speed` above 0.",
	}


## A fan of flying shots; a nova (a fan all the way round) shows its ring once, when a shot flew.
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, source: Node, lifetime: float, chain: int, prev: int) -> int:
	var made: int = super(spell, tag, actor, origin, direction, source, lifetime, chain, prev)
	if rt.events != null and made > 0 and spell.shots > 1 and spell.spread >= 360.0:
		rt.events.form_shown.emit(actor, &"nova", origin, direction, 0.0, spell.tint, spell.look)
	return made


func reach_of(spell: CompiledSpell) -> float:
	return spell.speed * spell.lifetime if spell.spread < 360.0 else 0.0
