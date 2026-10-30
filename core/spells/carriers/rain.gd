class_name CarrierRain
extends Carrier
## Strikes the aim point after `lifetime` seconds and drops its payload there (`&"rain"`).
## Homing places it on a target near the point; held, it falls again and again.


## How the rain takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Works.YES, Shows.DRAWN],
	B.HOMING: [Works.OWN_WAY, Shows.DRAWN],
	B.CHAIN: [Works.YES, Shows.DRAWN],
	B.SHIELD: [Works.NO, "it blocks shots that touch the carrier or guards the caster on a move, and a rain strikes once where it lands"],
	B.BLAST: [Works.YES, Shows.AS_EFFECT],
	B.HOLD: [Works.YES, Shows.DRAWN],
	B.RECOIL: [Works.YES, Shows.DRAWN],
	B.BOUNCE: [Works.NO, "it turns a shot or a beam at walls, and a rain strikes once where it lands"],
	B.ECHO: [Works.YES, Shows.DRAWN],
	B.LINGER: [Works.NO, "it only changes a moving shot, and a rain strikes once where it lands"],
	B.HEAVY: [Works.YES, Shows.DRAWN],
	B.SIPHON: [Works.YES, Shows.DRAWN],
	B.STICKY: [Works.NO, "it only changes a moving shot, and a rain strikes once where it lands"],
	B.MAGNET: [Works.NO, "it needs a shot or a beam that stays in the world, and a rain strikes once where it lands"],
	B.GHOST: [Works.NO, "it only takes a flying shot or a line through walls, and a rain strikes once where it lands"],
	B.SPIRAL: [Works.NO, "it only changes a moving shot, and a rain strikes once where it lands"],
	B.MIRROR: [Works.YES, Shows.DRAWN],
	B.GROWTH: [Works.NO, "it grows a shot in the world or a beam, and a rain strikes once where it lands"],
	B.RELAY: [Works.YES, Shows.DRAWN],
	B.RETURN: [Works.NO, "it does not fly out"],
	B.ARC: [Works.NO, "it is not a shot that stays in the air"],
	B.POSSESS: [Works.YES, Shows.DRAWN],
	B.DEFLECT: [Works.NO, "it touches no shots"],
}
## When each trigger (`TriggerBase.Event`) fires on the rain: "" when it can, else why it never does.
const EVENTS: Dictionary = {
	E.HIT: "",
	E.EXPIRE: "",
	E.TIMER: "",
	E.BLOCK: "nothing on it can block a shot",
	E.KILL: "",
	E.CAST: "",
	E.WALL: "a rain falls from above and never meets a wall",
	E.HURT: "",
	E.REACTION: "",
}
## How the rain takes an infusion.
const INFUSIONS: Array = [Works.YES, Shows.DRAWN]


func id() -> StringName:
	return &"rain"


func noun() -> String:
	return "rain"


func what() -> String:
	return "a rain strikes once where it lands"


func traits() -> int:
	return HITS | LASTS | REACHES | STEERS | SPEED | SHOTS | REPEATS_HELD | CARRIES_PAYLOAD | HOLDS_STAFF


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Array:
	return INFUSIONS


func hit_kind() -> StringName:
	return &"ray"


## Marks the aim point and strikes it after its `lifetime` (`Spells._telegraph_rain`).
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, _source: Node, _lifetime: float, _chain: int, _prev: int) -> int:
	return rt._telegraph_rain(spell, tag, actor, origin, direction)


func reach_of(spell: CompiledSpell) -> float:
	return spell.ray_length if spell.ray_length > 0.0 else SpellLimits.RAIN_REACH
