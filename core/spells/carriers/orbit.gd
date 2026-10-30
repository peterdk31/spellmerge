class_name CarrierOrbit
extends Carrier
## Shots that circle their caster at `orbit_radius` (`&"orbit"`), spread evenly round
## the circle. They pass through walls and cannot home.


## How the orbit takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Works.YES, Shows.DRAWN],
	B.HOMING: [Works.NO, "it has nothing to aim, and an orbit is held on its circle"],
	B.CHAIN: [Works.YES, Shows.DRAWN],
	B.SHIELD: [Works.YES, Shows.DRAWN],
	B.BLAST: [Works.YES, Shows.AS_EFFECT],
	B.HOLD: [Works.YES, Shows.DRAWN],
	B.RECOIL: [Works.YES, Shows.DRAWN],
	B.BOUNCE: [Works.NO, "it turns a shot or a beam at walls, and an orbit is held on its circle"],
	B.ECHO: [Works.YES, Shows.DRAWN],
	B.LINGER: [Works.YES, Shows.DRAWN],
	B.HEAVY: [Works.YES, Shows.DRAWN],
	B.SIPHON: [Works.YES, Shows.DRAWN],
	B.STICKY: [Works.YES, Shows.DRAWN],
	B.MAGNET: [Works.YES, Shows.DRAWN],
	B.GHOST: [Works.NO, "an orbit already passes walls"],
	B.SPIRAL: [Works.YES, Shows.DRAWN],
	B.MIRROR: [Works.YES, Shows.DRAWN],
	B.GROWTH: [Works.YES, Shows.DRAWN],
	B.RELAY: [Works.YES, Shows.DRAWN],
	B.RETURN: [Works.NO, "it does not fly out"],
	B.ARC: [Works.YES, Shows.DRAWN],
	B.POSSESS: [Works.YES, Shows.DRAWN],
	B.DEFLECT: [Works.YES, Shows.DRAWN],
}
## When each trigger (`TriggerBase.Event`) fires on the orbit: "" when it can, else why it never does.
const EVENTS: Dictionary = {
	E.HIT: "",
	E.EXPIRE: "",
	E.TIMER: "",
	E.BLOCK: "",
	E.KILL: "",
	E.CAST: "",
	E.WALL: "an orbit passes through walls",
	E.HURT: "",
	E.REACTION: "",
}
## How the orbit takes an infusion.
const INFUSIONS: Array = [Works.YES, Shows.DRAWN]


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

func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Array:
	return INFUSIONS


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
