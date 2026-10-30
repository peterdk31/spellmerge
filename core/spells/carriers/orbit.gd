class_name CarrierOrbit
extends Carrier
## Shots that circle their caster at `orbit_radius` (`&"orbit"`), spread evenly round
## the circle. They pass through walls and cannot home.


func id() -> StringName:
	return &"orbit"


func traits() -> int:
	return STAYS | HITS | LASTS | GUARDS | SPEED | SHOTS | PIERCE | RING | OUTWARD | MOVES | MEETS_SHOTS


func required_fields() -> Dictionary:
	return {
		"orbit_radius": "An orbit needs an `orbit_radius` above 0.",
	}


## Shot `n` of `count` evenly round the circle from the aim: it circles its caster, the wizard, or
## for a payload the shot that cast it (or the point it was cast from).
func shoot(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, _heading: Vector2, n: int, count: int, source: Node, lifetime: float, chain: int, prev: int) -> int:
	var turn: float = SpellLimits.ORBIT_TURN
	if spell.speed > 0.0 and spell.orbit_radius > 0.0:
		turn = spell.speed / spell.orbit_radius
	var centre: Vector2 = Vector2.INF
	if kit.caster() != SpellRuntime.CASTER_WIZARD:
		var shot: int = kit.caster_shot()
		centre = kit.projectiles.get_position_of(shot) if shot >= 0 else origin
	var slot: int = kit.projectiles.spawn_orbit(actor, spell.orbit_radius, direction.angle() + TAU * n / count, turn, lifetime, spell.radius, SpellRuntime.HITS, spell.pierce, tag, centre)
	return kit.land_shot(slot, spell, tag, source, chain, prev)
