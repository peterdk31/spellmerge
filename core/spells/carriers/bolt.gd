class_name CarrierBolt
extends Carrier
## A shot that flies out on its own along the aim (`&"bolt"`: the bolt, and the nova, a
## bolt whose shots fan all the way round). The plain carrier: every card runs on it through the
## shot path (`Spells._apply_travel`, the projectile manager's kit).


## How the bolt takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Works.YES, Shows.DRAWN],
	B.HOMING: [Works.YES, Shows.DRAWN],
	B.CHAIN: [Works.YES, Shows.DRAWN],
	B.SHIELD: [Works.YES, Shows.DRAWN],
	B.BLAST: [Works.YES, Shows.AS_EFFECT],
	B.HOLD: [Works.YES, Shows.DRAWN],
	B.RECOIL: [Works.YES, Shows.DRAWN],
	B.BOUNCE: [Works.YES, Shows.DRAWN],
	B.ECHO: [Works.YES, Shows.DRAWN],
	B.LINGER: [Works.YES, Shows.DRAWN],
	B.HEAVY: [Works.YES, Shows.DRAWN],
	B.SIPHON: [Works.YES, Shows.DRAWN],
	B.STICKY: [Works.YES, Shows.DRAWN],
	B.MAGNET: [Works.YES, Shows.DRAWN],
	B.GHOST: [Works.YES, Shows.DRAWN],
	B.SPIRAL: [Works.YES, Shows.DRAWN],
	B.MIRROR: [Works.YES, Shows.DRAWN],
	B.GROWTH: [Works.YES, Shows.DRAWN],
	B.RELAY: [Works.YES, Shows.DRAWN],
	B.RETURN: [Works.YES, Shows.DRAWN],
	B.ARC: [Works.YES, Shows.DRAWN],
	B.POSSESS: [Works.YES, Shows.DRAWN],
	B.DEFLECT: [Works.YES, Shows.DRAWN],
}
## When each trigger (`TriggerBase.Event`) fires on the bolt: "" when it can, else why it never does.
const EVENTS: Dictionary = {
	E.HIT: "",
	E.EXPIRE: "",
	E.TIMER: "",
	E.BLOCK: "",
	E.KILL: "",
	E.CAST: "",
	E.WALL: "",
	E.HURT: "",
	E.REACTION: "",
}
## How the bolt takes an infusion.
const INFUSIONS: Array = [Works.YES, Shows.DRAWN]


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


func infusions() -> Array:
	return INFUSIONS


## A fan of flying shots; a nova (a fan all the way round) shows its ring once, when a shot flew.
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, source: Node, lifetime: float, chain: int, prev: int) -> int:
	var made: int = super(spell, tag, actor, origin, direction, source, lifetime, chain, prev)
	if rt.events != null and made > 0 and spell.shots > 1 and spell.spread >= 360.0:
		rt.events.form_shown.emit(actor, &"nova", origin, direction, 0.0, spell.tint, spell.look)
	return made


func reach_of(spell: CompiledSpell) -> float:
	return spell.speed * spell.lifetime if spell.spread < 360.0 else 0.0
