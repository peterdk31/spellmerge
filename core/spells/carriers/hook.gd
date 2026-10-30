class_name CarrierHook
extends Carrier
## A flying shot that pulls its caster to where it hits (`FormBase.Motion.HOOK`). Every shot card
## runs on it; its own part is the pull (`on_hit`).


## How the hook takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Use.RUNS, Look.SHOWN],
	B.HOMING: [Use.RUNS, Look.SHOWN],
	B.CHAIN: [Use.RUNS, Look.SHOWN],
	B.SHIELD: [Use.RUNS, Look.SHOWN],
	B.BLAST: [Use.RUNS, Look.CUE],
	B.HOLD: [Use.RUNS, Look.SHOWN],
	B.RECOIL: [Use.RUNS, Look.SHOWN],
	B.BOUNCE: [Use.RUNS, Look.SHOWN],
	B.ECHO: [Use.RUNS, Look.SHOWN],
	B.LINGER: [Use.RUNS, Look.SHOWN],
	B.HEAVY: [Use.RUNS, Look.SHOWN],
	B.SIPHON: [Use.RUNS, Look.SHOWN],
	B.STICKY: [Use.RUNS, Look.SHOWN],
	B.MAGNET: [Use.RUNS, Look.SHOWN],
	B.GHOST: [Use.RUNS, Look.SHOWN],
	B.SPIRAL: [Use.RUNS, Look.SHOWN],
	B.MIRROR: [Use.RUNS, Look.SHOWN],
	B.GROWTH: [Use.RUNS, Look.SHOWN],
	B.RELAY: [Use.RUNS, Look.SHOWN],
	B.RETURN: [Use.RUNS, Look.SHOWN],
	B.ARC: [Use.RUNS, Look.SHOWN],
	B.POSSESS: [Use.RUNS, Look.SHOWN],
	B.DEFLECT: [Use.RUNS, Look.SHOWN],
}
## When each trigger (`TriggerBase.Event`) fires on the hook: "" when it can, else why it never does.
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
## How the hook takes an infusion.
const INFUSIONS: Array = [Use.RUNS, Look.SHOWN]


func motion() -> int:
	return FormBase.Motion.HOOK


func noun() -> String:
	return "hook"


func what() -> String:
	return "a hook flies out and pulls its caster to what it hits"


func traits() -> int:
	return FLIES | STAYS | HITS | LASTS | REACHES | STEERS | SPEED | SHOTS | SPREAD | PIERCE


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Array:
	return INFUSIONS
