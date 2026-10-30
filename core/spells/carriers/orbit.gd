class_name CarrierOrbit
extends Carrier
## Shots that circle their caster at `orbit_radius` (`&"orbit"`), spread evenly round
## the circle. They pass through walls and cannot home.


## Each modifier behaviour (`ModifierBase.Behaviour`) on the orbit, every one (keys: see `Carrier`).
const BEHAVIOURS: Dictionary = {
	B.NONE: {"works": Works.YES, "shows": Shows.DRAWN},
	B.HOMING: {"works": Works.NO, "why_not": "it has nothing to aim, and an orbit is held on its circle"},
	B.CHAIN: {"works": Works.YES, "shows": Shows.DRAWN},
	B.SHIELD: {"works": Works.YES, "shows": Shows.DRAWN},
	B.BLAST: {"works": Works.YES, "shows": Shows.AS_EFFECT},
	B.HOLD: {"works": Works.YES, "shows": Shows.DRAWN},
	B.RECOIL: {"works": Works.YES, "shows": Shows.DRAWN},
	B.BOUNCE: {"works": Works.NO, "why_not": "it turns a shot or a beam at walls, and an orbit is held on its circle"},
	B.ECHO: {"works": Works.YES, "shows": Shows.DRAWN},
	B.LINGER: {"works": Works.YES, "shows": Shows.DRAWN},
	B.HEAVY: {"works": Works.YES, "shows": Shows.DRAWN},
	B.SIPHON: {"works": Works.YES, "shows": Shows.DRAWN},
	B.STICKY: {"works": Works.YES, "shows": Shows.DRAWN},
	B.MAGNET: {"works": Works.YES, "shows": Shows.DRAWN},
	B.GHOST: {"works": Works.NO, "why_not": "an orbit already passes walls"},
	B.SPIRAL: {"works": Works.YES, "shows": Shows.DRAWN},
	B.MIRROR: {"works": Works.YES, "shows": Shows.DRAWN},
	B.GROWTH: {"works": Works.YES, "shows": Shows.DRAWN},
	B.RELAY: {"works": Works.YES, "shows": Shows.DRAWN},
	B.RETURN: {"works": Works.NO, "why_not": "it does not fly out"},
	B.ARC: {"works": Works.YES, "shows": Shows.DRAWN},
	B.POSSESS: {"works": Works.YES, "shows": Shows.DRAWN},
	B.DEFLECT: {"works": Works.YES, "shows": Shows.DRAWN},
}
## Each trigger (`TriggerBase.Event`) on the orbit: "fires" (does it ever go off here?) and, when it
## never does, "why_not".
const EVENTS: Dictionary = {
	E.HIT: {"fires": true},
	E.EXPIRE: {"fires": true},
	E.TIMER: {"fires": true},
	E.BLOCK: {"fires": true},
	E.KILL: {"fires": true},
	E.CAST: {"fires": true},
	E.WALL: {"fires": false, "why_not": "an orbit passes through walls"},
	E.HURT: {"fires": true},
	E.REACTION: {"fires": true},
}
## An infusion (an element card) on the orbit, with the same keys as a behaviour.
const INFUSIONS: Dictionary = {"works": Works.YES, "shows": Shows.DRAWN}


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


func infusions() -> Dictionary:
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
