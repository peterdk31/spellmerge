class_name CarrierOrbit
extends Carrier
## Shots that circle their caster at `orbit_radius` (`FormBase.Motion.ORBIT`), spread evenly round
## the circle. They pass through walls and cannot home.


## How the orbit takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Use.RUNS, Look.SHOWN],
	B.HOMING: [Use.WASTED, "it has nothing to aim, and an orbit is held on its circle"],
	B.CHAIN: [Use.RUNS, Look.SHOWN],
	B.SHIELD: [Use.RUNS, Look.SHOWN],
	B.BLAST: [Use.RUNS, Look.CUE],
	B.HOLD: [Use.RUNS, Look.SHOWN],
	B.RECOIL: [Use.RUNS, Look.SHOWN],
	B.BOUNCE: [Use.WASTED, "it turns a shot or a beam at walls, and an orbit is held on its circle"],
	B.ECHO: [Use.RUNS, Look.SHOWN],
	B.LINGER: [Use.RUNS, Look.SHOWN],
	B.HEAVY: [Use.RUNS, Look.SHOWN],
	B.SIPHON: [Use.RUNS, Look.SHOWN],
	B.STICKY: [Use.RUNS, Look.SHOWN],
	B.MAGNET: [Use.RUNS, Look.SHOWN],
	B.GHOST: [Use.WASTED, "an orbit already passes walls"],
	B.SPIRAL: [Use.RUNS, Look.SHOWN],
	B.MIRROR: [Use.RUNS, Look.SHOWN],
	B.GROWTH: [Use.RUNS, Look.SHOWN],
	B.RELAY: [Use.RUNS, Look.SHOWN],
	B.RETURN: [Use.WASTED, "it does not fly out"],
	B.ARC: [Use.RUNS, Look.SHOWN],
	B.POSSESS: [Use.RUNS, Look.SHOWN],
	B.DEFLECT: [Use.RUNS, Look.SHOWN],
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
const INFUSIONS: Array = [Use.RUNS, Look.SHOWN]


func motion() -> int:
	return FormBase.Motion.ORBIT


func noun() -> String:
	return "orbit"


func what() -> String:
	return "an orbit is held on its circle"


func traits() -> int:
	return STAYS | HITS | LASTS | GUARDS | SPEED | SHOTS | PIERCE | RING | OUTWARD


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
