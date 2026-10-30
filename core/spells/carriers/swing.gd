class_name CarrierSwing
extends Carrier
## Melee: the staff leans back, then sweeps `arc` degrees round the hand, striking each body in
## the wedge once (`FormBase.Motion.SWING`, `SpellSwings`). Its shield and deflect guard the sweep.


## How the swing takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Use.RUNS, Look.SHOWN],
	B.HOMING: [Use.WASTED, "it has nothing to aim, and a swing is a sweep that is over at once"],
	B.CHAIN: [Use.RUNS, Look.SHOWN],
	B.SHIELD: [Use.OWN, Look.SHOWN],
	B.BLAST: [Use.RUNS, Look.CUE],
	B.HOLD: [Use.RUNS, Look.SHOWN],
	B.RECOIL: [Use.RUNS, Look.SHOWN],
	B.BOUNCE: [Use.WASTED, "it turns a shot or a beam at walls, and a swing is a sweep that is over at once"],
	B.ECHO: [Use.RUNS, Look.SHOWN],
	B.LINGER: [Use.WASTED, "it only changes a moving shot, and a swing is a sweep that is over at once"],
	B.HEAVY: [Use.RUNS, Look.SHOWN],
	B.SIPHON: [Use.RUNS, Look.SHOWN],
	B.STICKY: [Use.WASTED, "it only changes a moving shot, and a swing is a sweep that is over at once"],
	B.MAGNET: [Use.WASTED, "it needs a shot or a beam that stays in the world, and a swing is a sweep that is over at once"],
	B.GHOST: [Use.WASTED, "it only takes a flying shot or a line through walls, and a swing is a sweep that is over at once"],
	B.SPIRAL: [Use.WASTED, "it only changes a moving shot, and a swing is a sweep that is over at once"],
	B.MIRROR: [Use.RUNS, Look.SHOWN],
	B.GROWTH: [Use.WASTED, "it grows a shot in the world or a beam, and a swing is a sweep that is over at once"],
	B.RELAY: [Use.RUNS, Look.SHOWN],
	B.RETURN: [Use.WASTED, "it does not fly out"],
	B.ARC: [Use.WASTED, "it is not a shot that stays in the air"],
	B.POSSESS: [Use.RUNS, Look.SHOWN],
	B.DEFLECT: [Use.OWN, Look.SHOWN],
}
## When each trigger (`TriggerBase.Event`) fires on the swing: "" when it can, else why it never does.
const EVENTS: Dictionary = {
	E.HIT: "",
	E.EXPIRE: "",
	E.TIMER: "",
	E.BLOCK: "",
	E.KILL: "",
	E.CAST: "",
	E.WALL: "a swing's sweep never meets a wall",
	E.HURT: "",
	E.REACTION: "",
}
## How the swing takes an infusion.
const INFUSIONS: Array = [Use.RUNS, Look.SHOWN]


func motion() -> int:
	return FormBase.Motion.SWING


func noun() -> String:
	return "swing"


func what() -> String:
	return "a swing is a sweep that is over at once"


func traits() -> int:
	return HITS | LASTS | REACHES | GUARDS | SPEED | SHOTS | SPREAD | REPEATS_HELD | OWN_POSE


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Array:
	return INFUSIONS


func hit_kind() -> StringName:
	return &"swing"
