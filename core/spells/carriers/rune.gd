class_name CarrierRune
extends Carrier
## A still shot placed a step ahead along the aim that waits for a body to enter it
## (`&"rune"`: the rune). Homing makes it creep toward a target.


## Each modifier behaviour (`ModifierBase.Behaviour`) on the rune, every one (keys: see `Carrier`).
const BEHAVIOURS: Dictionary = {
	B.NONE: {"works": Works.YES, "shows": Shows.DRAWN},
	B.HOMING: {"works": Works.YES, "shows": Shows.DRAWN},
	B.CHAIN: {"works": Works.YES, "shows": Shows.DRAWN},
	B.SHIELD: {"works": Works.YES, "shows": Shows.DRAWN},
	B.BLAST: {"works": Works.YES, "shows": Shows.AS_EFFECT},
	B.HOLD: {"works": Works.YES, "shows": Shows.DRAWN},
	B.RECOIL: {"works": Works.YES, "shows": Shows.DRAWN},
	B.BOUNCE: {"works": Works.NO, "why_not": "it turns a shot or a beam at walls, and a rune stays where it is"},
	B.ECHO: {"works": Works.YES, "shows": Shows.DRAWN},
	B.LINGER: {"works": Works.NO, "why_not": "it does not move"},
	B.HEAVY: {"works": Works.YES, "shows": Shows.DRAWN},
	B.SIPHON: {"works": Works.YES, "shows": Shows.DRAWN},
	B.STICKY: {"works": Works.NO, "why_not": "it does not move"},
	B.MAGNET: {"works": Works.YES, "shows": Shows.DRAWN},
	B.GHOST: {"works": Works.NO, "why_not": "it only takes a flying shot or a line through walls, and a rune stays where it is"},
	B.SPIRAL: {"works": Works.NO, "why_not": "it does not move"},
	B.MIRROR: {"works": Works.YES, "shows": Shows.DRAWN},
	B.GROWTH: {"works": Works.YES, "shows": Shows.DRAWN},
	B.RELAY: {"works": Works.YES, "shows": Shows.DRAWN},
	B.RETURN: {"works": Works.NO, "why_not": "it does not fly out"},
	B.ARC: {"works": Works.YES, "shows": Shows.DRAWN},
	B.POSSESS: {"works": Works.YES, "shows": Shows.DRAWN},
	B.DEFLECT: {"works": Works.YES, "shows": Shows.DRAWN},
}
## Each trigger (`TriggerBase.Event`) on the rune: "fires" (does it ever go off here?) and, when it
## never does, "why_not".
const EVENTS: Dictionary = {
	E.HIT: {"fires": true},
	E.EXPIRE: {"fires": true},
	E.TIMER: {"fires": true},
	E.BLOCK: {"fires": true},
	E.KILL: {"fires": true},
	E.CAST: {"fires": true},
	E.WALL: {"fires": false, "why_not": "it stays where it is and never meets a wall"},
	E.HURT: {"fires": true},
	E.REACTION: {"fires": true},
}
## An infusion (an element card) on the rune, with the same keys as a behaviour.
const INFUSIONS: Dictionary = {"works": Works.YES, "shows": Shows.DRAWN}


func id() -> StringName:
	return &"rune"


func noun() -> String:
	return "rune"


func what() -> String:
	return "a rune stays where it is"


func traits() -> int:
	return STAYS | HITS | LASTS | GUARDS | STEERS | SPEED | SHOTS | SPREAD | PIERCE | OUTWARD


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Dictionary:
	return INFUSIONS


## A still shot a step ahead along `heading` (`Spells._placed_at`).
func shoot(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, _direction: Vector2, heading: Vector2, _n: int, _count: int, source: Node, lifetime: float, chain: int, prev: int) -> int:
	var slot: int = rt.projectiles.spawn(actor, rt._placed_at(spell, origin, heading), Vector2.ZERO, lifetime, spell.radius, SpellRuntime.HITS, spell.pierce, tag, SpellRuntime.ProjectilesScript.MOTION_STILL)
	return rt._land_shot(slot, spell, tag, source, chain, prev)
