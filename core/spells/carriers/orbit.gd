class_name CarrierOrbit
extends Carrier
## Shots that circle their caster at `orbit_radius` (`&"orbit"`), spread evenly round
## the circle. They pass through walls and cannot home.


## Modifier cards that do nothing on a orbit, with the sentence the builder shows after
## "<Card> does nothing on a Orbit: ". Every card not listed does something here.
const DOES_NOTHING: Dictionary = {
	B.HOMING: "it has nothing to aim, and an orbit is held on its circle",
	B.BOUNCE: "it turns a shot or a beam at walls, and an orbit is held on its circle",
	B.GHOST: "an orbit already passes walls",
	B.RETURN: "it does not fly out",
}
## Trigger cards that never go off on a orbit, with the sentence the builder shows.
const NEVER_FIRES: Dictionary = {
	E.WALL: "an orbit passes through walls",
}


func id() -> StringName:
	return &"orbit"


func noun() -> String:
	return "orbit"


func what() -> String:
	return "an orbit is held on its circle"


func traits() -> int:
	return STAYS | HITS | LASTS | GUARDS | SPEED | SHOTS | PIERCE | RING | OUTWARD



func required_fields() -> Dictionary:
	return {
		"orbit_radius": "An orbit needs an `orbit_radius` above 0.",
	}

func does_nothing() -> Dictionary:
	return DOES_NOTHING


func never_fires() -> Dictionary:
	return NEVER_FIRES


## Shot `n` of `count` evenly round the circle from the aim: it circles its caster, the wizard, or
## for a payload the shot that cast it (or the point it was cast from).
func shoot(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, _heading: Vector2, n: int, count: int, source: Node, lifetime: float, chain: int, prev: int) -> int:
	var turn: float = SpellLimits.ORBIT_TURN
	if spell.speed > 0.0 and spell.orbit_radius > 0.0:
		turn = spell.speed / spell.orbit_radius
	var centre: Vector2 = Vector2.INF
	if rt._caster != SpellRuntime.CASTER_WIZARD:
		var shot: int = rt._caster_shot()
		centre = rt.projectiles.get_position_of(shot) if shot >= 0 else origin
	var slot: int = rt.projectiles.spawn_orbit(actor, spell.orbit_radius, direction.angle() + TAU * n / count, turn, lifetime, spell.radius, SpellRuntime.HITS, spell.pierce, tag, centre)
	return rt._land_shot(slot, spell, tag, source, chain, prev)
