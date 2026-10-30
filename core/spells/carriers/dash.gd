class_name CarrierDash
extends Carrier
## Moves its caster `ray_length` along the move direction, striking every body it passes once
## (`&"dash"`). Homing turns it as it goes; its shield guards what it moves.


## How the dash takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Works.YES, Shows.DRAWN],
	B.HOMING: [Works.OWN_WAY, Shows.DRAWN],
	B.CHAIN: [Works.YES, Shows.DRAWN],
	B.SHIELD: [Works.OWN_WAY, Shows.DRAWN],
	B.BLAST: [Works.YES, Shows.AS_EFFECT],
	B.HOLD: [Works.NO, "nothing keeps it on: a dash moves its caster and hits what it passes, once each"],
	B.RECOIL: [Works.YES, Shows.DRAWN],
	B.BOUNCE: [Works.NO, "it turns a shot or a beam at walls, and a dash moves its caster and hits what it passes, once each"],
	B.ECHO: [Works.YES, Shows.DRAWN],
	B.LINGER: [Works.NO, "it only changes a moving shot, and a dash moves its caster and hits what it passes, once each"],
	B.HEAVY: [Works.YES, Shows.DRAWN],
	B.SIPHON: [Works.YES, Shows.DRAWN],
	B.STICKY: [Works.NO, "it only changes a moving shot, and a dash moves its caster and hits what it passes, once each"],
	B.MAGNET: [Works.NO, "it needs a shot or a beam that stays in the world, and a dash moves its caster and hits what it passes, once each"],
	B.GHOST: [Works.NO, "it only takes a flying shot or a line through walls, and a dash moves its caster and hits what it passes, once each"],
	B.SPIRAL: [Works.NO, "it only changes a moving shot, and a dash moves its caster and hits what it passes, once each"],
	B.MIRROR: [Works.NO, "a move and its mirror cancel"],
	B.GROWTH: [Works.NO, "it grows a shot in the world or a beam, and a dash moves its caster and hits what it passes, once each"],
	B.RELAY: [Works.YES, Shows.DRAWN],
	B.RETURN: [Works.NO, "it does not fly out"],
	B.ARC: [Works.NO, "it is not a shot that stays in the air"],
	B.POSSESS: [Works.YES, Shows.DRAWN],
	B.DEFLECT: [Works.OWN_WAY, Shows.DRAWN],
}
## When each trigger (`TriggerBase.Event`) fires on the dash: "" when it can, else why it never does.
const EVENTS: Dictionary = {
	E.HIT: "",
	E.EXPIRE: "",
	E.TIMER: "",
	E.BLOCK: "",
	E.KILL: "",
	E.CAST: "",
	E.WALL: "it stops before walls",
	E.HURT: "",
	E.REACTION: "",
}
## How the dash takes an infusion.
const INFUSIONS: Array = [Works.YES, Shows.DRAWN]


func id() -> StringName:
	return &"dash"


func noun() -> String:
	return "dash"


func what() -> String:
	return "a dash moves its caster and hits what it passes, once each"


func traits() -> int:
	return HITS | LASTS | REACHES | STEERS | SPEED | HOLDS_STAFF


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Array:
	return INFUSIONS


## Moves its caster (`Spells._move_caster`), striking what it passes.
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, _source: Node, _lifetime: float, chain: int, prev: int) -> int:
	return rt._move_caster(spell, tag, actor, origin, direction, chain, prev, true)
