class_name Orbit
extends RefCounted
## Orbit, the circling modifier (owner, 2026-11-09; docs/milestones/carrier-modifiers.md Part 5): the
## next carrier circles its caster instead of going out. It changes only how the carrier moves;
## its look, size, hits, pierce, payloads and infusions are its own, and it adds no count (Split,
## Nova and the like make more). The card sets the circle's radius (`behaviour_reach`, as
## `CompiledSpell.orbit_radius`) and a slow drift (`behaviour_strength`, turns a second); the carrier
## turns by the drift plus its own speed over the radius, so a fast one goes round faster. How long it
## circles is the card's general `lifetime_base`, not orbit code.
##
## All of the modifier is here. The runtime calls it at the places marked "Orbit": `_land_shots`
## (every row a carrier makes is put on its circle, `circle`) and the beam's step (a beam sweeps
## round its caster, `sweep_of`); CastSense, `next_cast_reach` and the compiler ask `orbits_on` (an area, not aimed;
## no homing range). A row is turned into a circler after
## it is spawned (`Projectiles.set_orbit`), so no carrier knows about orbit. Taking it out again is
## this file, the card folder, those calls, and `set_orbit` in the projectile manager.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## Not state: the runtime's kit, set up again (core/sim/README.md).
const DERIVED: Array[StringName] = [&"_kit"]

var _kit: CarrierKit = null


func _init(kit: CarrierKit) -> void:
	_kit = kit


## True when `spell` circles on `carrier`: it has the card, and the card does something there.
static func orbits_on(spell: CompiledSpell, carrier: Carrier) -> bool:
	return spell.behaviour(ModifierBase.Behaviour.ORBIT) > 0.0 and carrier.works(ModifierBase.Behaviour.ORBIT)


## How fast a carrier of `spell` drifts round its caster on top of its own speed, in radians a
## second (0 for one that does not circle on `carrier`).
static func drift_of(spell: CompiledSpell, carrier: Carrier) -> float:
	return TAU * spell.behaviour(ModifierBase.Behaviour.ORBIT) if orbits_on(spell, carrier) else 0.0


## How fast a beam of `spell` sweeps round its caster, in radians a second: its drift (a beam has no
## speed of its own to spend going round). 0 for one that does not circle.
func sweep_of(spell: CompiledSpell) -> float:
	return Orbit.drift_of(spell, _kit.carrier_of(spell))


## Puts each of the first `count` rows in `slots` (-1 for one not made) of a launch of `spell` by
## `actor` on its circle, when `spell` circles: round its caster (the actor's body, which it follows;
## for a payload the shot that cast it or the point it was cast from, `Spells._register_shots`; while
## something falls, that point on its floor line), starting the way it would have gone: its heading,
## or, for a row that does not move, the way from the centre to where it stands. A row the manager
## will not circle (no centre) goes on as it was. The card's cue is shown once, round the centre.
func circle(slots: PackedInt32Array, count: int, spell: CompiledSpell, tag: int) -> void:
	var carrier: Carrier = _kit.carrier_of(spell)
	if not Orbit.orbits_on(spell, carrier):
		return
	var first: int = -1
	for n in count:
		if slots[n] >= 0:
			first = slots[n]
			break
	if first < 0:
		return
	var projectiles: ProjectilesScript = _kit.projectiles
	var actor: int = SpellTag.caster_of(tag)
	# The actor's own body is the manager's own centre (its anchor, INF here); any other caster, where it is.
	var centre: Vector2 = Vector2.INF
	if _kit.caster_body(actor) != actor:
		centre = _kit.on_floor(spell, _kit.caster_place(actor, projectiles.get_position_of(first)))
	var around: Vector2 = centre if centre.is_finite() else projectiles.get_anchor(actor)
	if not around.is_finite():
		return
	var drift: float = Orbit.drift_of(spell, carrier)
	var circled: bool = false
	for n in count:
		var slot: int = slots[n]
		if slot < 0:
			continue
		var way: Vector2 = projectiles.get_velocity_of(slot)
		if way.is_zero_approx():
			way = projectiles.get_position_of(slot) - around
		var angle: float = DMath.angle(way) if not way.is_zero_approx() else 0.0
		circled = projectiles.set_orbit(slot, spell.orbit_radius, angle, drift, centre) or circled
	var cue: StringName = spell.cue_of(ModifierBase.Behaviour.ORBIT)
	if circled and cue != &"" and _kit.events != null:
		_kit.set_cue_tag(tag)
		_kit.events.cue_shown.emit(actor, cue, around, Vector2.RIGHT, spell.orbit_radius, spell.tint, spell.look)
		_kit.set_cue_tag(0)
