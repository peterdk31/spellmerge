extends RefCounted
## The rings of Pulses (props W9a; the owner, 2026-11-12: "It should emit a pulse going outwards from
## the cast point (using easing as bolt/atom)"), drawn by Feel as motes: every frame each live ring
## gives off sparks (look kind 0, half of them in its infusion's colour) and its cards' particles
## along its edge where it is now, thrown outward, and lays a trail behind its edge, as births
## (`gameplay/feel/births.gd`) of its spell (its tag), so they take its cards' motes. Its edge grows
## as the simulation grows it (the shots' speed curve: `CarrierPulse`), so the motes are where it
## strikes. The edge's rate is per second and per 100 pixels of edge, so a wide ring is as dense as
## a small one. Feel calls `step` every frame with one typed read of the live rings
## (`CarrierPulse.read_view`, a `PulseView`). A ring is segments, each stopped on its own by a wall
## or a body it hit (owner, 2026-11-12: "the ring should be 'individual' motes, that can be blocked
## individually"): a mote is given off only where its segment still reaches (`PulseView.stop_toward`),
## so the look stops where the strikes stop.
##
## **Its trail** (owner, 2026-11-13: "Can the pulse motes be emitted like a trail of the expanding
## ring?"): tail motes (`content/motes`, the `tail` kinds: they barely move and cool where they are
## laid) over the band its edge swept since the last frame, by area, not by time, as a shot lays
## its tail by distance (`ProjectileManager._lay_tail`), so the fast start of its curve leaves as
## whole a trail as its slow end, at any frame rate and through a hit-stop. Each ring takes one of
## the tail kinds by its id, as a shot does by its sequence (`ProjectileManager.tail_code`). What it
## keeps for that is each ring's radius as last drawn, by its id (`PulseView.id`); it allocates
## nothing once its lists are as long as the most rings seen.

const BirthsScript := preload("res://gameplay/feel/births.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## Sparks a second for every 100 pixels of a ring's edge, and the share of them in its infusion's
## colour (the rest white-hot).
const SPARKS_PER_100: float = 60.0
const INFUSED_SHARE: float = 0.5
## Its cards' particles a second for every 100 pixels of edge.
const PARTICLES_PER_100: float = 30.0
## Square pixels of the band its edge sweeps for each tail mote of its trail.
const TRAIL_AREA: float = 10.0

## The rings drawn last frame: how many, their ids and the radius each was drawn at; and this
## frame's, swapped in when it is drawn.
var _last_count: int = 0
var _last_id: PackedInt64Array = PackedInt64Array()
var _last_radius: PackedFloat32Array = PackedFloat32Array()
var _next_id: PackedInt64Array = PackedInt64Array()
var _next_radius: PackedFloat32Array = PackedFloat32Array()


## Gives off this frame's motes (`delta` seconds of Feel's clock) of every ring in `view` into
## `births`; `ramp_of` gives a ring's caster's ramp.
func step(view: PulseView, delta: float, ramp_of: Callable, births: BirthsScript) -> void:
	if view == null or births == null or not (delta > 0.0):
		return
	if _next_id.size() < view.rings:
		_next_id.resize(view.rings)
		_next_radius.resize(view.rings)
	var room: bool = true
	for r in view.rings:
		var radius: float = view.radius[r]
		var was: float = _drawn_at(view.id[r])
		_next_id[r] = view.id[r]
		_next_radius[r] = radius
		if room:
			room = _ring(view, r, was, delta, int(ramp_of.call(view.caster[r])), births)
	var id: PackedInt64Array = _last_id
	var drawn: PackedFloat32Array = _last_radius
	_last_id = _next_id
	_last_radius = _next_radius
	_next_id = id
	_next_radius = drawn
	_last_count = view.rings


## The radius ring `id` was drawn at last frame, or 0 for a ring new this frame (a ring starts at
## its centre).
func _drawn_at(id: int) -> float:
	for i in _last_count:
		if _last_id[i] == id:
			return _last_radius[i]
	return 0.0


## Ring `r`'s motes this frame, its edge swept out (or, on its way home, in) from `was`: false once
## the frame's births are taken.
func _ring(view: PulseView, r: int, was: float, delta: float, ramp: int, births: BirthsScript) -> bool:
	var radius: float = view.radius[r]
	var centre: Vector2 = view.centre[r]
	var look: int = view.look[r]
	var tag: int = view.tag[r]
	var tint: Color = view.core[r]
	var core: Color = Color(tint.r, tint.g, tint.b, 1.0)
	# The trail: over the band swept, evenly by area, thrown back the way the edge came.
	var low: float = minf(was, radius)
	var high: float = maxf(was, radius)
	var back: float = signf(was - radius)
	var code: int = ProjectilesScript.tail_code(view.id[r])
	for n in births.roll(PI * (high * high - low * low) / TRAIL_AREA):
		var out: Vector2 = Vector2.RIGHT.rotated(births.dice() * TAU)
		var at: float = sqrt(lerpf(low * low, high * high, births.dice()))
		if view.stop_toward(r, out) < at:
			continue
		if not births.add(centre + out * at, out * back, code, ramp, look, core, tag):
			return false
	if not (radius > 0.0):
		return true
	# The edge.
	var edge: float = TAU * radius / 100.0 * delta
	for n in births.roll(SPARKS_PER_100 * edge):
		var out: Vector2 = Vector2.RIGHT.rotated(births.dice() * TAU)
		var colour: Color = core if births.dice() < INFUSED_SHARE else Color.WHITE
		if view.stop_toward(r, out) < radius:
			continue
		if not births.add(centre + out * radius, out, 0, ramp, look, colour, tag):
			return false
	if BirthsScript.emitting_count(look) == 0:
		return true
	for n in births.roll(PARTICLES_PER_100 * edge):
		var out: Vector2 = Vector2.RIGHT.rotated(births.dice() * TAU)
		if view.stop_toward(r, out) < radius:
			continue
		if not births.add(centre + out * radius, out, births.emitting_layer(look), ramp, look, core, tag):
			return false
	return true
