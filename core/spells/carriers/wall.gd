class_name CarrierWall
extends Carrier
## `shots` still, solid shots in a line across the aim, `spread` pixels apart: a short-lived wall that
## stands through every hit (`&"wall"`). Homing makes it creep toward a target, as a rune.


## How the wall takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Works.YES, Shows.DRAWN],
	B.HOMING: [Works.YES, Shows.DRAWN],
	B.CHAIN: [Works.YES, Shows.DRAWN],
	B.SHIELD: [Works.YES, Shows.DRAWN],
	B.BLAST: [Works.YES, Shows.AS_EFFECT],
	B.HOLD: [Works.YES, Shows.DRAWN],
	B.RECOIL: [Works.YES, Shows.DRAWN],
	B.BOUNCE: [Works.NO, "it turns a shot or a beam at walls, and a wall stands still through every hit"],
	B.ECHO: [Works.YES, Shows.DRAWN],
	B.LINGER: [Works.NO, "it does not move"],
	B.HEAVY: [Works.YES, Shows.DRAWN],
	B.SIPHON: [Works.YES, Shows.DRAWN],
	B.STICKY: [Works.NO, "it does not move"],
	B.MAGNET: [Works.YES, Shows.DRAWN],
	B.GHOST: [Works.NO, "it only takes a flying shot or a line through walls, and a wall stands still through every hit"],
	B.SPIRAL: [Works.NO, "it does not move"],
	B.MIRROR: [Works.YES, Shows.DRAWN],
	B.GROWTH: [Works.YES, Shows.DRAWN],
	B.RELAY: [Works.YES, Shows.DRAWN],
	B.RETURN: [Works.NO, "it does not fly out"],
	B.ARC: [Works.YES, Shows.DRAWN],
	B.POSSESS: [Works.YES, Shows.DRAWN],
	B.DEFLECT: [Works.YES, Shows.DRAWN],
}
## When each trigger (`TriggerBase.Event`) fires on the wall: "" when it can, else why it never does.
const EVENTS: Dictionary = {
	E.HIT: "",
	E.EXPIRE: "",
	E.TIMER: "",
	E.BLOCK: "",
	E.KILL: "",
	E.CAST: "",
	E.WALL: "it stays where it is and never meets a wall",
	E.HURT: "",
	E.REACTION: "",
}
## How the wall takes an infusion.
const INFUSIONS: Array = [Works.YES, Shows.DRAWN]


func id() -> StringName:
	return &"wall"


func noun() -> String:
	return "wall"


func what() -> String:
	return "a wall stands still through every hit"


func traits() -> int:
	return STAYS | HITS | LASTS | REACHES | GUARDS | STEERS | SPEED | SHOTS


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Array:
	return INFUSIONS


## One solid line of still shots across the aim (`Spells._launch_wall`).
func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, source: Node, lifetime: float, chain: int, prev: int) -> int:
	return rt._launch_wall(spell, tag, actor, origin, direction, source, lifetime, chain, prev)
