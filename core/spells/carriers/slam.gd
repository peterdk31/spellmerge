class_name CarrierSlam
extends Carrier
## Melee: the staff rises, then strikes the floor ahead and a ring grows from the impact, striking
## each body in it once (`FormBase.Motion.SLAM`, `SpellSlams`). Over at once.


## How the slam takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Use.RUNS, Look.SHOWN],
	B.HOMING: [Use.WASTED, "it has nothing to aim, and a slam is a strike that is over at once"],
	B.CHAIN: [Use.RUNS, Look.SHOWN],
	B.SHIELD: [Use.OWN, Look.SHOWN],
	B.BLAST: [Use.RUNS, Look.CUE],
	B.HOLD: [Use.WASTED, "nothing keeps it on: a slam is a strike that is over at once"],
	B.RECOIL: [Use.RUNS, Look.SHOWN],
	B.BOUNCE: [Use.WASTED, "it turns a shot or a beam at walls, and a slam is a strike that is over at once"],
	B.ECHO: [Use.RUNS, Look.SHOWN],
	B.LINGER: [Use.WASTED, "it only changes a moving shot, and a slam is a strike that is over at once"],
	B.HEAVY: [Use.RUNS, Look.SHOWN],
	B.SIPHON: [Use.RUNS, Look.SHOWN],
	B.STICKY: [Use.WASTED, "it only changes a moving shot, and a slam is a strike that is over at once"],
	B.MAGNET: [Use.WASTED, "it needs a shot or a beam that stays in the world, and a slam is a strike that is over at once"],
	B.GHOST: [Use.WASTED, "it only takes a flying shot or a line through walls, and a slam is a strike that is over at once"],
	B.SPIRAL: [Use.WASTED, "it only changes a moving shot, and a slam is a strike that is over at once"],
	B.MIRROR: [Use.RUNS, Look.SHOWN],
	B.GROWTH: [Use.WASTED, "it grows a shot in the world or a beam, and a slam is a strike that is over at once"],
	B.RELAY: [Use.RUNS, Look.SHOWN],
	B.RETURN: [Use.WASTED, "it does not fly out"],
	B.ARC: [Use.WASTED, "it is not a shot that stays in the air"],
	B.POSSESS: [Use.RUNS, Look.SHOWN],
	B.DEFLECT: [Use.OWN, Look.SHOWN],
}
## When each trigger (`TriggerBase.Event`) fires on the slam: "" when it can, else why it never does.
const EVENTS: Dictionary = {
	E.HIT: "",
	E.EXPIRE: "",
	E.TIMER: "it is over at once",
	E.BLOCK: "",
	E.KILL: "",
	E.CAST: "",
	E.WALL: "a slam strikes short of a wall and its ring never meets one",
	E.HURT: "it is over at once",
	E.REACTION: "",
}
## How the slam takes an infusion.
const INFUSIONS: Array = [Use.RUNS, Look.SHOWN]


func motion() -> int:
	return FormBase.Motion.SLAM


func noun() -> String:
	return "slam"


func what() -> String:
	return "a slam is a strike that is over at once"


func traits() -> int:
	return HITS | REACHES | GUARDS | SPEED | SHOTS | SPREAD | OWN_POSE


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Array:
	return INFUSIONS


func hit_kind() -> StringName:
	return &"burst"
