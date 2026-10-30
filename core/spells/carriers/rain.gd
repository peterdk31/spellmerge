class_name CarrierRain
extends Carrier
## Strikes the aim point after `lifetime` seconds and drops its payload there (`FormBase.Motion.RAIN`).
## Homing places it on a target near the point; held, it falls again and again.


## How the rain takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Use.RUNS, Look.SHOWN],
	B.HOMING: [Use.OWN, Look.SHOWN],
	B.CHAIN: [Use.RUNS, Look.SHOWN],
	B.SHIELD: [Use.WASTED, "it blocks shots that touch the carrier or guards the caster on a move, and a rain strikes once where it lands"],
	B.BLAST: [Use.RUNS, Look.CUE],
	B.HOLD: [Use.RUNS, Look.SHOWN],
	B.RECOIL: [Use.RUNS, Look.SHOWN],
	B.BOUNCE: [Use.WASTED, "it turns a shot or a beam at walls, and a rain strikes once where it lands"],
	B.ECHO: [Use.RUNS, Look.SHOWN],
	B.LINGER: [Use.WASTED, "it only changes a moving shot, and a rain strikes once where it lands"],
	B.HEAVY: [Use.RUNS, Look.SHOWN],
	B.SIPHON: [Use.RUNS, Look.SHOWN],
	B.STICKY: [Use.WASTED, "it only changes a moving shot, and a rain strikes once where it lands"],
	B.MAGNET: [Use.WASTED, "it needs a shot or a beam that stays in the world, and a rain strikes once where it lands"],
	B.GHOST: [Use.WASTED, "it only takes a flying shot or a line through walls, and a rain strikes once where it lands"],
	B.SPIRAL: [Use.WASTED, "it only changes a moving shot, and a rain strikes once where it lands"],
	B.MIRROR: [Use.RUNS, Look.SHOWN],
	B.GROWTH: [Use.WASTED, "it grows a shot in the world or a beam, and a rain strikes once where it lands"],
	B.RELAY: [Use.RUNS, Look.SHOWN],
	B.RETURN: [Use.WASTED, "it does not fly out"],
	B.ARC: [Use.WASTED, "it is not a shot that stays in the air"],
	B.POSSESS: [Use.RUNS, Look.SHOWN],
	B.DEFLECT: [Use.WASTED, "it touches no shots"],
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
const INFUSIONS: Array = [Use.RUNS, Look.SHOWN]


func motion() -> int:
	return FormBase.Motion.RAIN


func noun() -> String:
	return "rain"


func what() -> String:
	return "a rain strikes once where it lands"


func traits() -> int:
	return HITS | LASTS | REACHES | STEERS | SPEED | SHOTS | REPEATS_HELD


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Array:
	return INFUSIONS


func hit_kind() -> StringName:
	return &"ray"
