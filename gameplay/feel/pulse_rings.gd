extends RefCounted
## The rings of Pulses (props W9a; the owner, 2026-11-12: "It should emit a pulse going outwards from
## the cast point (using easing as bolt/atom)"), drawn by Feel as motes: every frame each live ring
## gives off sparks (look kind 0, half of them in its infusion's colour) and its cards' particles
## along its edge where it is now, thrown outward, as births (`gameplay/feel/births.gd`) of its spell
## (`pulse_tag`), so they take its cards' motes. Its edge grows as the simulation grows it (the
## shots' speed curve: `CarrierPulse`), so the motes are where it strikes. The rate is per second and
## per 100 pixels of edge, so a wide ring is as dense as a small one. Feel calls `step` every frame;
## it reads `Spells`' live rings from their plain queries (`pulse_slots`, `pulse_on`,
## `pulse_centre`, `pulse_radius`, ...). Nothing is kept and nothing is allocated.

const BirthsScript := preload("res://gameplay/feel/births.gd")

## Sparks a second for every 100 pixels of a ring's edge, and the share of them in its infusion's
## colour (the rest white-hot).
const SPARKS_PER_100: float = 90.0
const INFUSED_SHARE: float = 0.5
## Its cards' particles a second for every 100 pixels of edge.
const PARTICLES_PER_100: float = 30.0


## Gives off this frame's motes (`delta` seconds of Feel's clock) of every live ring of `rings` (the
## bound `pulse` carrier, or null) into `births`; `ramp_of` gives a ring's caster's ramp.
func step(rings: Object, delta: float, ramp_of: Callable, births: BirthsScript) -> void:
	if rings == null or births == null or not (delta > 0.0):
		return
	for at in int(rings.call("pulse_slots")):
		if not bool(rings.call("pulse_on", at)):
			continue
		var radius: float = float(rings.call("pulse_radius", at))
		if not (radius > 0.0):
			continue
		var edge: float = TAU * radius / 100.0 * delta
		var centre: Vector2 = rings.call("pulse_centre", at) as Vector2
		var tint: Color = rings.call("pulse_tint", at) as Color
		var look: int = int(rings.call("pulse_look", at))
		var tag: int = int(rings.call("pulse_tag", at))
		var ramp: int = int(ramp_of.call(int(rings.call("pulse_actor", at))))
		var core: Color = Color(tint.r, tint.g, tint.b, 1.0)
		for n in births.roll(SPARKS_PER_100 * edge):
			var out: Vector2 = Vector2.RIGHT.rotated(births.dice() * TAU)
			var colour: Color = core if births.dice() < INFUSED_SHARE else Color.WHITE
			if not births.add(centre + out * radius, out, 0, ramp, look, colour, tag):
				return
		if BirthsScript.emitting_count(look) == 0:
			continue
		for n in births.roll(PARTICLES_PER_100 * edge):
			var out: Vector2 = Vector2.RIGHT.rotated(births.dice() * TAU)
			if not births.add(centre + out * radius, out, births.emitting_layer(look), ramp, look, core, tag):
				return
