class_name CarrierRune
extends Carrier
## A still shot placed a step ahead along the aim that waits for a body to enter it
## (`&"rune"`: the rune). Homing makes it creep toward a target.


func id() -> StringName:
	return &"rune"


func traits() -> int:
	return STAYS | HITS | LASTS | GUARDS | STEERS | SPEED | SHOTS | SPREAD | PIERCE | OUTWARD | MEETS_SHOTS


## A still shot a step ahead along `heading` (`Spells._placed_at`).
func shoot(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, source: Node, lifetime: float, chain: int, prev: int) -> int:
	var slot: int = rt.projectiles.spawn(actor, rt._placed_at(spell, origin, heading), Vector2.ZERO, lifetime, spell.radius, SpellRuntime.HITS, spell.pierce, tag, SpellRuntime.ProjectilesScript.MOTION_STILL)
	return rt._land_shot(slot, spell, tag, source, chain, prev)
