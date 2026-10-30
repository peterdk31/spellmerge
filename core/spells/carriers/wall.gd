class_name CarrierWall
extends Carrier
## `shots` still, solid shots in a line across the aim, `spread` pixels apart: a short-lived wall that
## stands through every hit (`FormBase.Motion.WALL`). Homing makes it creep toward a target, as a rune.


## How the wall takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Use.RUNS, Look.SHOWN],
	B.HOMING: [Use.RUNS, Look.SHOWN],
	B.CHAIN: [Use.RUNS, Look.SHOWN],
	B.SHIELD: [Use.RUNS, Look.SHOWN],
	B.BLAST: [Use.RUNS, Look.CUE],
	B.HOLD: [Use.RUNS, Look.SHOWN],
	B.RECOIL: [Use.RUNS, Look.SHOWN],
	B.BOUNCE: [Use.WASTED, "it turns a shot or a beam at walls, and a wall stands still through every hit"],
	B.ECHO: [Use.RUNS, Look.SHOWN],
	B.LINGER: [Use.WASTED, "it does not move"],
	B.HEAVY: [Use.RUNS, Look.SHOWN],
	B.SIPHON: [Use.RUNS, Look.SHOWN],
	B.STICKY: [Use.WASTED, "it does not move"],
	B.MAGNET: [Use.RUNS, Look.SHOWN],
	B.GHOST: [Use.WASTED, "it only takes a flying shot or a line through walls, and a wall stands still through every hit"],
	B.SPIRAL: [Use.WASTED, "it does not move"],
	B.MIRROR: [Use.RUNS, Look.SHOWN],
	B.GROWTH: [Use.RUNS, Look.SHOWN],
	B.RELAY: [Use.RUNS, Look.SHOWN],
	B.RETURN: [Use.WASTED, "it does not fly out"],
	B.ARC: [Use.RUNS, Look.SHOWN],
	B.POSSESS: [Use.RUNS, Look.SHOWN],
	B.DEFLECT: [Use.RUNS, Look.SHOWN],
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
const INFUSIONS: Array = [Use.RUNS, Look.SHOWN]


func motion() -> int:
	return FormBase.Motion.WALL


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
