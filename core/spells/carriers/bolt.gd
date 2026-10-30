class_name CarrierBolt
extends Carrier
## A shot that flies out on its own along the aim (`&"bolt"`: the bolt, and the nova, a
## bolt whose shots fan all the way round). The plain carrier: every card runs on it through the
## shot path (`Spells._apply_travel`, the projectile manager's kit).


## Each modifier behaviour (`ModifierBase.Behaviour`) on the bolt, every one (keys: see `Carrier`).
const BEHAVIOURS: Dictionary = {
	B.NONE: {"works": Works.YES, "shows": Shows.DRAWN},
	B.HOMING: {"works": Works.YES, "shows": Shows.DRAWN},
	B.CHAIN: {"works": Works.YES, "shows": Shows.DRAWN},
	B.SHIELD: {"works": Works.YES, "shows": Shows.DRAWN},
	B.BLAST: {"works": Works.YES, "shows": Shows.AS_EFFECT},
	B.HOLD: {"works": Works.YES, "shows": Shows.DRAWN},
	B.RECOIL: {"works": Works.YES, "shows": Shows.DRAWN},
	B.BOUNCE: {"works": Works.YES, "shows": Shows.DRAWN},
	B.ECHO: {"works": Works.YES, "shows": Shows.DRAWN},
	B.LINGER: {"works": Works.YES, "shows": Shows.DRAWN},
	B.HEAVY: {"works": Works.YES, "shows": Shows.DRAWN},
	B.SIPHON: {"works": Works.YES, "shows": Shows.DRAWN},
	B.STICKY: {"works": Works.YES, "shows": Shows.DRAWN},
	B.MAGNET: {"works": Works.YES, "shows": Shows.DRAWN},
	B.GHOST: {"works": Works.YES, "shows": Shows.DRAWN},
	B.SPIRAL: {"works": Works.YES, "shows": Shows.DRAWN},
	B.MIRROR: {"works": Works.YES, "shows": Shows.DRAWN},
	B.GROWTH: {"works": Works.YES, "shows": Shows.DRAWN},
	B.RELAY: {"works": Works.YES, "shows": Shows.DRAWN},
	B.RETURN: {"works": Works.YES, "shows": Shows.DRAWN},
	B.ARC: {"works": Works.YES, "shows": Shows.DRAWN},
	B.POSSESS: {"works": Works.YES, "shows": Shows.DRAWN},
	B.DEFLECT: {"works": Works.YES, "shows": Shows.DRAWN},
}
## Each trigger (`TriggerBase.Event`) on the bolt: "fires" (does it ever go off here?) and, when it
## never does, "why_not".
const EVENTS: Dictionary = {
	E.HIT: {"fires": true},
	E.EXPIRE: {"fires": true},
	E.TIMER: {"fires": true},
	E.BLOCK: {"fires": true},
	E.KILL: {"fires": true},
	E.CAST: {"fires": true},
	E.WALL: {"fires": true},
	E.HURT: {"fires": true},
	E.REACTION: {"fires": true},
}
## An infusion (an element card) on the bolt, with the same keys as a behaviour.
const INFUSIONS: Dictionary = {"works": Works.YES, "shows": Shows.DRAWN}


func id() -> StringName:
	return &"bolt"


func noun() -> String:
	return "bolt"


func what() -> String:
	return "a bolt flies on its own"


func traits() -> int:
	return FLIES | STAYS | HITS | LASTS | REACHES | GUARDS | STEERS | SPEED | SHOTS | SPREAD | PIERCE



func required_fields() -> Dictionary:
	return {
		"speed": "A bolt needs a `speed` above 0.",
	}

func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Dictionary:
	return INFUSIONS


## A fan of flying shots; a nova (a fan all the way round) shows its ring once, when a shot flew.
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, source: Node, lifetime: float, chain: int, prev: int) -> int:
	var made: int = super(spell, tag, actor, origin, direction, source, lifetime, chain, prev)
	if rt.events != null and made > 0 and spell.shots > 1 and spell.spread >= 360.0:
		rt.events.form_shown.emit(actor, &"nova", origin, direction, 0.0, spell.tint, spell.look)
	return made


func reach_of(spell: CompiledSpell) -> float:
	return spell.speed * spell.lifetime if spell.spread < 360.0 else 0.0
