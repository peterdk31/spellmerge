class_name CarrierBeam
extends Carrier
## A line held by its caster that hits at once and every `SpellLimits.BEAM_TICK` (`FormBase.Motion.RAY`:
## the beam). It runs most shot cards in its own way: it bends to a target, turns at walls, waves,
## widens, pulls and guards along its line (`SpellBeams`).


## How the beam takes each modifier (`ModifierBase.Behaviour`), every one: see `Carrier`.
const BEHAVIOURS: Dictionary = {
	B.NONE: [Use.RUNS, Look.SHOWN],
	B.HOMING: [Use.OWN, Look.SHOWN],
	B.CHAIN: [Use.RUNS, Look.SHOWN],
	B.SHIELD: [Use.OWN, Look.SHOWN],
	B.BLAST: [Use.RUNS, Look.CUE],
	B.HOLD: [Use.RUNS, Look.SHOWN],
	B.RECOIL: [Use.RUNS, Look.SHOWN],
	B.BOUNCE: [Use.OWN, Look.SHOWN],
	B.ECHO: [Use.RUNS, Look.SHOWN],
	B.LINGER: [Use.WASTED, "it only changes a moving shot, and a beam is a line, not a shot"],
	B.HEAVY: [Use.RUNS, Look.SHOWN],
	B.SIPHON: [Use.RUNS, Look.SHOWN],
	B.STICKY: [Use.WASTED, "it only changes a moving shot, and a beam is a line, not a shot"],
	B.MAGNET: [Use.OWN, Look.SHOWN],
	B.GHOST: [Use.OWN, Look.SHOWN],
	B.SPIRAL: [Use.OWN, Look.SHOWN],
	B.MIRROR: [Use.RUNS, Look.SHOWN],
	B.GROWTH: [Use.OWN, Look.SHOWN],
	B.RELAY: [Use.RUNS, Look.SHOWN],
	B.RETURN: [Use.WASTED, "it does not fly out"],
	B.ARC: [Use.WASTED, "it is not a shot that stays in the air"],
	B.POSSESS: [Use.RUNS, Look.SHOWN],
	B.DEFLECT: [Use.OWN, Look.SHOWN],
}
## When each trigger (`TriggerBase.Event`) fires on the beam: "" when it can, else why it never does.
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
## How the beam takes an infusion.
const INFUSIONS: Array = [Use.RUNS, Look.SHOWN]


func motion() -> int:
	return FormBase.Motion.RAY


func noun() -> String:
	return "beam"


func what() -> String:
	return "a beam is a line, not a shot"


func traits() -> int:
	return HITS | LASTS | REACHES | GUARDS | STEERS | SPEED | SHOTS | SPREAD | PIERCE | INSTANT_HOMING


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Array:
	return INFUSIONS


func hit_kind() -> StringName:
	return &"ray"
