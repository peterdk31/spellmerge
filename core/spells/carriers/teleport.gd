class_name CarrierTeleport
extends Carrier
## Blinks its caster `ray_length` along the aim, stopping before walls, and strikes the bodies where
## it lands (`FormBase.Motion.TELEPORT`). Over at once: homing bends its way, recoil shortens it.


## How the teleport takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Use.RUNS, Look.NONE],
	B.HOMING: [Use.OWN, Look.NONE],
	B.CHAIN: [Use.RUNS, Look.NONE],
	B.SHIELD: [Use.OWN, Look.NONE],
	B.BLAST: [Use.RUNS, Look.CUE],
	B.HOLD: [Use.WASTED, "nothing keeps it on: a teleport moves its caster at once and hits where it lands"],
	B.RECOIL: [Use.OWN, Look.NONE],
	B.BOUNCE: [Use.WASTED, "it turns a shot or a beam at walls, and a teleport moves its caster at once and hits where it lands"],
	B.ECHO: [Use.RUNS, Look.NONE],
	B.LINGER: [Use.WASTED, "it only changes a moving shot, and a teleport moves its caster at once and hits where it lands"],
	B.HEAVY: [Use.RUNS, Look.NONE],
	B.SIPHON: [Use.RUNS, Look.NONE],
	B.STICKY: [Use.WASTED, "it only changes a moving shot, and a teleport moves its caster at once and hits where it lands"],
	B.MAGNET: [Use.WASTED, "it needs a shot or a beam that stays in the world, and a teleport moves its caster at once and hits where it lands"],
	B.GHOST: [Use.WASTED, "it only takes a flying shot or a line through walls, and a teleport moves its caster at once and hits where it lands"],
	B.SPIRAL: [Use.WASTED, "it only changes a moving shot, and a teleport moves its caster at once and hits where it lands"],
	B.MIRROR: [Use.WASTED, "a move and its mirror cancel"],
	B.GROWTH: [Use.WASTED, "it grows a shot in the world or a beam, and a teleport moves its caster at once and hits where it lands"],
	B.RELAY: [Use.RUNS, Look.NONE],
	B.RETURN: [Use.WASTED, "it does not fly out"],
	B.ARC: [Use.WASTED, "it is not a shot that stays in the air"],
	B.POSSESS: [Use.RUNS, Look.NONE],
	B.DEFLECT: [Use.OWN, Look.NONE],
}
## When each trigger (`TriggerBase.Event`) fires on the teleport: "" when it can, else why it never does.
const EVENTS: Dictionary = {
	E.HIT: "",
	E.EXPIRE: "",
	E.TIMER: "it is over at once",
	E.BLOCK: "",
	E.KILL: "",
	E.CAST: "",
	E.WALL: "it stops before walls",
	E.HURT: "it is over at once",
	E.REACTION: "",
}
## How the teleport takes an infusion.
const INFUSIONS: Array = [Use.RUNS, Look.NONE]


func motion() -> int:
	return FormBase.Motion.TELEPORT


func noun() -> String:
	return "teleport"


func what() -> String:
	return "a teleport moves its caster at once and hits where it lands"


func traits() -> int:
	return HITS | REACHES | STEERS | INSTANT_HOMING


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Array:
	return INFUSIONS


func look_note() -> String:
	return "a teleport is over at once and draws nothing of its own: its cards show only in its hits"
