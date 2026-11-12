extends RefCounted
## The rings of Pulses (props W9a; the owner, 2026-11-12: "It should emit a pulse going outwards from
## the cast point (using easing as bolt/atom)"), drawn by Feel as motes: every frame each live ring
## gives off sparks (look kind 0, half of them in its infusion's colour) and its cards' particles
## along its edge where it is now, thrown outward, as births (`gameplay/feel/births.gd`) of its spell
## (its tag), so they take its cards' motes. Its edge grows as the simulation grows it (the shots'
## speed curve: `CarrierPulse`), so the motes are where it strikes. The rate is per second and per
## 100 pixels of edge, so a wide ring is as dense as a small one. Feel calls `step` every frame with
## one typed read of the live rings (`CarrierPulse.read_view`, a `PulseView`). A ring is segments,
## each stopped on its own by a wall or a body it hit (owner, 2026-11-12: "the ring should be
## 'individual' motes, that can be blocked individually"): a mote is given off only where its
## segment still reaches the edge (`PulseView.stop_toward`), so the look stops where the strikes
## stop. Nothing is kept and nothing is allocated.

const BirthsScript := preload("res://gameplay/feel/births.gd")

## Sparks a second for every 100 pixels of a ring's edge, and the share of them in its infusion's
## colour (the rest white-hot).
const SPARKS_PER_100: float = 90.0
const INFUSED_SHARE: float = 0.5
## Its cards' particles a second for every 100 pixels of edge.
const PARTICLES_PER_100: float = 30.0


## Gives off this frame's motes (`delta` seconds of Feel's clock) of every ring in `view` into
## `births`; `ramp_of` gives a ring's caster's ramp.
func step(view: PulseView, delta: float, ramp_of: Callable, births: BirthsScript) -> void:
	if view == null or births == null or not (delta > 0.0):
		return
	for r in view.rings:
		var radius: float = view.radius[r]
		if not (radius > 0.0):
			continue
		var edge: float = TAU * radius / 100.0 * delta
		var centre: Vector2 = view.centre[r]
		var look: int = view.look[r]
		var tag: int = view.tag[r]
		var ramp: int = int(ramp_of.call(view.caster[r]))
		var tint: Color = view.core[r]
		var core: Color = Color(tint.r, tint.g, tint.b, 1.0)
		for n in births.roll(SPARKS_PER_100 * edge):
			var out: Vector2 = Vector2.RIGHT.rotated(births.dice() * TAU)
			var colour: Color = core if births.dice() < INFUSED_SHARE else Color.WHITE
			if view.stop_toward(r, out) < radius:
				continue
			if not births.add(centre + out * radius, out, 0, ramp, look, colour, tag):
				return
		if BirthsScript.emitting_count(look) == 0:
			continue
		for n in births.roll(PARTICLES_PER_100 * edge):
			var out: Vector2 = Vector2.RIGHT.rotated(births.dice() * TAU)
			if view.stop_toward(r, out) < radius:
				continue
			if not births.add(centre + out * radius, out, births.emitting_layer(look), ramp, look, core, tag):
				return
