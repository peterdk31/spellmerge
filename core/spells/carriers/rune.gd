class_name CarrierRune
extends Carrier
## A still shot placed a step ahead along the aim that waits for a body to enter it
## (`&"rune"`: the rune). Homing makes it creep toward a target.


## Modifier cards that do nothing on a rune, with the sentence the builder shows after
## "<Card> does nothing on a Rune: ". Every card not listed does something here.
const DOES_NOTHING: Dictionary = {
	B.BOUNCE: "it turns a shot or a beam at walls, and a rune stays where it is",
	B.LINGER: "it does not move",
	B.STICKY: "it does not move",
	B.GHOST: "it only takes a flying shot or a line through walls, and a rune stays where it is",
	B.SPIRAL: "it does not move",
	B.RETURN: "it does not fly out",
}
## Trigger cards that never go off on a rune, with the sentence the builder shows.
const NEVER_FIRES: Dictionary = {
	E.WALL: "it stays where it is and never meets a wall",
}


func id() -> StringName:
	return &"rune"


func noun() -> String:
	return "rune"


func what() -> String:
	return "a rune stays where it is"


func traits() -> int:
	return STAYS | HITS | LASTS | GUARDS | STEERS | SPEED | SHOTS | SPREAD | PIERCE | OUTWARD


func does_nothing() -> Dictionary:
	return DOES_NOTHING


func never_fires() -> Dictionary:
	return NEVER_FIRES


## A still shot a step ahead along `heading` (`Spells._placed_at`).
func shoot(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, source: Node, lifetime: float, chain: int, prev: int) -> int:
	var slot: int = rt.projectiles.spawn(actor, rt._placed_at(spell, origin, heading), Vector2.ZERO, lifetime, spell.radius, SpellRuntime.HITS, spell.pierce, tag, SpellRuntime.ProjectilesScript.MOTION_STILL)
	return rt._land_shot(slot, spell, tag, source, chain, prev)
