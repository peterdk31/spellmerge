class_name CarrierDash
extends Carrier
## Moves its caster `ray_length` along the move direction, striking every body it passes once
## (`FormBase.Motion.DASH`). Homing turns it as it goes; its shield guards what it moves.


## How the dash takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Use.RUNS, Look.SHOWN],
	B.HOMING: [Use.OWN, Look.SHOWN],
	B.CHAIN: [Use.RUNS, Look.SHOWN],
	B.SHIELD: [Use.OWN, Look.SHOWN],
	B.BLAST: [Use.RUNS, Look.CUE],
	B.HOLD: [Use.WASTED, "nothing keeps it on: a dash moves its caster and hits what it passes, once each"],
	B.RECOIL: [Use.RUNS, Look.SHOWN],
	B.BOUNCE: [Use.WASTED, "it turns a shot or a beam at walls, and a dash moves its caster and hits what it passes, once each"],
	B.ECHO: [Use.RUNS, Look.SHOWN],
	B.LINGER: [Use.WASTED, "it only changes a moving shot, and a dash moves its caster and hits what it passes, once each"],
	B.HEAVY: [Use.RUNS, Look.SHOWN],
	B.SIPHON: [Use.RUNS, Look.SHOWN],
	B.STICKY: [Use.WASTED, "it only changes a moving shot, and a dash moves its caster and hits what it passes, once each"],
	B.MAGNET: [Use.WASTED, "it needs a shot or a beam that stays in the world, and a dash moves its caster and hits what it passes, once each"],
	B.GHOST: [Use.WASTED, "it only takes a flying shot or a line through walls, and a dash moves its caster and hits what it passes, once each"],
	B.SPIRAL: [Use.WASTED, "it only changes a moving shot, and a dash moves its caster and hits what it passes, once each"],
	B.MIRROR: [Use.WASTED, "a move and its mirror cancel"],
	B.GROWTH: [Use.WASTED, "it grows a shot in the world or a beam, and a dash moves its caster and hits what it passes, once each"],
	B.RELAY: [Use.RUNS, Look.SHOWN],
	B.RETURN: [Use.WASTED, "it does not fly out"],
	B.ARC: [Use.WASTED, "it is not a shot that stays in the air"],
	B.POSSESS: [Use.RUNS, Look.SHOWN],
	B.DEFLECT: [Use.OWN, Look.SHOWN],
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
const INFUSIONS: Array = [Use.RUNS, Look.SHOWN]


func motion() -> int:
	return FormBase.Motion.DASH


func noun() -> String:
	return "dash"


func what() -> String:
	return "a dash moves its caster and hits what it passes, once each"


func traits() -> int:
	return HITS | LASTS | REACHES | STEERS | SPEED


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Array:
	return INFUSIONS
