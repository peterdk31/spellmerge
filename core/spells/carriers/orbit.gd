class_name CarrierOrbit
extends Carrier
## Shots that circle their caster at `orbit_radius` (`&"orbit"`), spread evenly round
## the circle. They pass through walls and cannot home.


func id() -> StringName:
	return &"orbit"


func traits() -> int:
	return STAYS | HITS | LASTS | GUARDS | SPEED | SHOTS | PIERCE | RING | OUTWARD | MOVES | MEETS_SHOTS | CASTS_FROM_SHOT


func required_fields() -> Dictionary:
	return {
		"orbit_radius": "An orbit needs an `orbit_radius` above 0.",
	}


## Shot `n` of `count` evenly round the circle from the aim: it circles its caster, the wizard's
## body, or for a payload the body or shot that cast it (or the point it was cast from), following
## it (the runtime: `Spells._register_shots`).
func spawn_row(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, _heading: Vector2, n: int, count: int, lifetime: float) -> int:
	var turn: float = SpellLimits.ORBIT_TURN
	if spell.speed > 0.0 and spell.orbit_radius > 0.0:
		turn = spell.speed / spell.orbit_radius
	# The actor's own body is the manager's own centre (its anchor); any other caster, where it is.
	var centre: Vector2 = Vector2.INF if kit.caster_body(actor) == actor else kit.caster_place(actor, origin)
	return kit.projectiles.spawn_orbit(actor, spell.orbit_radius, direction.angle() + TAU * n / count, turn, lifetime, spell.radius, SpellRuntime.HITS, spell.pierce, tag, centre)


func rows_only() -> bool:
	return true
